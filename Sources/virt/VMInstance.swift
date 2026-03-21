import ArgumentParser
import Foundation
import Virtualization

private var savedTermios: termios?
private var atexitRegistered = false

final class VMInstance: NSObject, VZVirtualMachineDelegate {
    let config: VMConfig
    let dir: VMDirectory
    let isoPath: String?
    private var virtualMachine: VZVirtualMachine?
    private var shutdownRequested = false
    private var shutdownDeadline: Date?

    init(config: VMConfig, dir: VMDirectory, isoPath: String?) {
        self.config = config
        self.dir = dir
        self.isoPath = isoPath
    }

    func run() throws {
        let vzConfig = try buildConfiguration()
        try vzConfig.validate()

        let vm = VZVirtualMachine(configuration: vzConfig)
        vm.delegate = self
        self.virtualMachine = vm

        try writePIDFile()
        setupSignalHandler()

        var startError: Error?
        vm.start { result in
            if case .failure(let error) = result {
                fputs("VM start failed: \(error.localizedDescription)\n", stderr)
                startError = error
            }
        }

        // Run the run loop to keep the VM alive and handle console I/O
        while !shutdownRequested {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
            if startError != nil || vm.state == .stopped || vm.state == .error {
                break
            }
        }

        // If shutdown was requested via Ctrl-C, wait for graceful stop with timeout
        if let deadline = shutdownDeadline {
            while vm.state != .stopped && Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
            }
            if vm.state != .stopped {
                fputs("Force stopping VM...\n", stderr)
                vm.stop { error in
                    if let error = error {
                        fputs("Force stop failed: \(error.localizedDescription)\n", stderr)
                    }
                }
                // Give force stop a moment to complete
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
            }
        }

        removePIDFile()
    }

    func requestShutdown() {
        guard let vm = virtualMachine, !shutdownRequested else { return }
        shutdownRequested = true

        if vm.canRequestStop {
            do {
                try vm.requestStop()
                fputs("Shutdown requested, waiting up to 10 seconds...\n", stderr)
            } catch {
                fputs("Failed to request stop: \(error.localizedDescription)\n", stderr)
            }
            shutdownDeadline = Date(timeIntervalSinceNow: 10)
        }
    }

    // MARK: - VZVirtualMachineDelegate

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        fputs("VM stopped with error: \(error.localizedDescription)\n", stderr)
        shutdownRequested = true
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        fputs("VM stopped.\n", stderr)
        shutdownRequested = true
    }

    // MARK: - Configuration

    private func buildConfiguration() throws -> VZVirtualMachineConfiguration {
        let vzConfig = VZVirtualMachineConfiguration()

        // CPU and memory
        vzConfig.cpuCount = config.cpus
        vzConfig.memorySize = UInt64(config.memoryMB) * 1024 * 1024

        // EFI boot loader with per-VM NVRAM
        let bootLoader = VZEFIBootLoader()
        if FileManager.default.fileExists(atPath: dir.nvramURL.path) {
            bootLoader.variableStore = VZEFIVariableStore(url: dir.nvramURL)
        } else {
            bootLoader.variableStore = try VZEFIVariableStore(creatingVariableStoreAt: dir.nvramURL)
        }
        vzConfig.bootLoader = bootLoader

        // Storage devices — ISO first (if provided) for boot priority on fresh VMs
        var storageDevices: [VZStorageDeviceConfiguration] = []

        if let isoPath = isoPath {
            let isoURL = URL(fileURLWithPath: isoPath)
            guard FileManager.default.fileExists(atPath: isoURL.path) else {
                throw ValidationError("ISO file not found: \(isoPath)")
            }
            let isoAttachment = try VZDiskImageStorageDeviceAttachment(
                url: isoURL,
                readOnly: true
            )
            storageDevices.append(VZUSBMassStorageDeviceConfiguration(attachment: isoAttachment))
        }

        // Main disk
        let diskAttachment = try VZDiskImageStorageDeviceAttachment(
            url: dir.diskURL,
            readOnly: false
        )
        storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: diskAttachment))

        vzConfig.storageDevices = storageDevices

        // NAT networking
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        vzConfig.networkDevices = [networkDevice]

        // Serial console wired to stdin/stdout
        let consoleDevice = VZVirtioConsoleDeviceConfiguration()
        let serialPort = VZVirtioConsolePortConfiguration()
        serialPort.isConsole = true

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        let serialAttachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: inputPipe.fileHandleForReading,
            fileHandleForWriting: outputPipe.fileHandleForWriting
        )
        serialPort.attachment = serialAttachment
        consoleDevice.ports[0] = serialPort
        vzConfig.consoleDevices = [consoleDevice]

        // Pipe stdin to the VM (only if running in a terminal)
        if isatty(STDIN_FILENO) != 0 {
            pipeStdinToVM(inputPipe: inputPipe)
        } else {
            FileHandle.standardInput.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    inputPipe.fileHandleForWriting.write(data)
                }
            }
        }

        // Pipe VM output to stdout
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                FileHandle.standardOutput.write(data)
            }
        }

        // Entropy device
        vzConfig.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        return vzConfig
    }

    private func pipeStdinToVM(inputPipe: Pipe) {
        // Set terminal to raw mode for interactive console
        var originalTermios = termios()
        tcgetattr(STDIN_FILENO, &originalTermios)
        savedTermios = originalTermios
        var rawTermios = originalTermios
        cfmakeraw(&rawTermios)
        tcsetattr(STDIN_FILENO, TCSANOW, &rawTermios)

        // Restore terminal on exit (register only once)
        if !atexitRegistered {
            atexitRegistered = true
            atexit {
                guard var t = savedTermios else { return }
                tcsetattr(STDIN_FILENO, TCSANOW, &t)
            }
        }

        FileHandle.standardInput.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                inputPipe.fileHandleForWriting.write(data)
            }
        }
    }

    // MARK: - PID file

    private func writePIDFile() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        try "\(pid)".write(to: dir.pidURL, atomically: true, encoding: .utf8)
    }

    private func removePIDFile() {
        try? FileManager.default.removeItem(at: dir.pidURL)
    }

    // MARK: - Signal handling

    private func setupSignalHandler() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            self?.requestShutdown()
        }
        source.resume()
    }
}
