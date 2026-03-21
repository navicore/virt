import ArgumentParser
import Foundation
import Virtualization

private var savedTermios: termios?

final class VMInstance: NSObject, VZVirtualMachineDelegate {
    let config: VMConfig
    let dir: VMDirectory
    let isoPath: String?
    private var virtualMachine: VZVirtualMachine?
    private var shutdownRequested = false

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

        let semaphore = DispatchSemaphore(value: 0)

        vm.start { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                fputs("VM start failed: \(error.localizedDescription)\n", stderr)
                semaphore.signal()
            }
        }

        // Run the run loop to keep the VM alive and handle console I/O
        while !shutdownRequested {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
            if vm.state == .stopped || vm.state == .error {
                break
            }
        }

        removePIDFile()
    }

    func requestShutdown() {
        guard let vm = virtualMachine else { return }
        shutdownRequested = true

        if vm.canRequestStop {
            do {
                try vm.requestStop()
                fputs("Shutdown requested, waiting up to 10 seconds...\n", stderr)
            } catch {
                fputs("Failed to request stop: \(error.localizedDescription)\n", stderr)
            }

            // Wait up to 10 seconds for graceful shutdown
            let deadline = Date(timeIntervalSinceNow: 10)
            while vm.state != .stopped && Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
            }
        }

        if vm.state != .stopped {
            fputs("Force stopping VM...\n", stderr)
            vm.stop { error in
                if let error = error {
                    fputs("Force stop failed: \(error.localizedDescription)\n", stderr)
                }
            }
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
        bootLoader.variableStore = VZEFIVariableStore(url: dir.nvramURL)
        vzConfig.bootLoader = bootLoader

        // Main disk
        let diskAttachment = try VZDiskImageStorageDeviceAttachment(
            url: dir.diskURL,
            readOnly: false
        )
        let diskDevice = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
        vzConfig.storageDevices = [diskDevice]

        // ISO attachment (if provided)
        if let isoPath = isoPath {
            let isoURL = URL(fileURLWithPath: isoPath)
            guard FileManager.default.fileExists(atPath: isoURL.path) else {
                throw ValidationError("ISO file not found: \(isoPath)")
            }
            let isoAttachment = try VZDiskImageStorageDeviceAttachment(
                url: isoURL,
                readOnly: true
            )
            let isoDevice = VZUSBMassStorageDeviceConfiguration(attachment: isoAttachment)
            vzConfig.storageDevices.append(isoDevice)
        }

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

        // Pipe stdin to the VM
        pipeStdinToVM(inputPipe: inputPipe)

        // Pipe VM output to stdout
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
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

        // Restore terminal on exit
        atexit {
            guard var t = savedTermios else { return }
            tcsetattr(STDIN_FILENO, TCSANOW, &t)
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
