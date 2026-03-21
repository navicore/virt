import ArgumentParser
import Foundation
import Virtualization

/// Shared VM configuration builder and runtime for both headless and GUI modes.
final class VMInstance: NSObject, VZVirtualMachineDelegate {
    let config: VMConfig
    let dir: VMDirectory
    let isoPath: String?
    private(set) var virtualMachine: VZVirtualMachine?
    private var shutdownRequested = false
    private var shutdownDeadline: Date?
    private var signalSource: (any DispatchSourceSignal)?
    private var originalTermios: termios?

    init(config: VMConfig, dir: VMDirectory, isoPath: String?) {
        self.config = config
        self.dir = dir
        self.isoPath = isoPath
    }

    // MARK: - Headless run (virt start)

    func runHeadless() throws {
        defer { restoreTerminal() }
        let vzConfig = try buildConfiguration(gui: false)
        try vzConfig.validate()

        let vm = VZVirtualMachine(configuration: vzConfig)
        vm.delegate = self
        self.virtualMachine = vm

        try writePIDFile()
        setupSignalHandler()

        var startError: Error?
        vm.start { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                DispatchQueue.main.async {
                    fputs("VM start failed: \(error.localizedDescription)\n", stderr)
                    startError = error
                }
            }
        }

        while !shutdownRequested {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
            if startError != nil || vm.state == .stopped || vm.state == .error {
                break
            }
        }

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
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
            }
        }

        restoreTerminal()
        removePIDFile()
        // TODO: DNS forwarder disabled until core flow is validated
    }

    // MARK: - GUI install (virt install)

    func buildGUIConfiguration() throws -> VZVirtualMachineConfiguration {
        let vzConfig = try buildConfiguration(gui: true)
        try vzConfig.validate()
        return vzConfig
    }

    func startVM(_ vm: VZVirtualMachine) {
        self.virtualMachine = vm
        vm.delegate = self
        try? writePIDFile()

        vm.start { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                DispatchQueue.main.async {
                    fputs("VM start failed: \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }

    func cleanup() {
        removePIDFile()
        // TODO: DNS forwarder disabled until core flow is validated
    }

    // MARK: - Shutdown

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

    private func buildConfiguration(gui: Bool) throws -> VZVirtualMachineConfiguration {
        let vzConfig = VZVirtualMachineConfiguration()

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

        // Storage devices — ISO first for boot priority
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

        // Entropy
        vzConfig.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        // Framebuffer — always present. EFI and GRUB need it to function.
        // In GUI mode it's displayed in a window; headless it renders to nothing.
        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(
            widthInPixels: 1280,
            heightInPixels: 800
        )]
        vzConfig.graphicsDevices = [graphics]

        if gui {
            vzConfig.keyboards = [VZUSBKeyboardConfiguration()]
            vzConfig.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        }

        // Serial console — Apple's exact pattern: stdin/stdout directly
        let serialAttachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: FileHandle.standardInput,
            fileHandleForWriting: FileHandle.standardOutput
        )
        let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
        serialPort.attachment = serialAttachment
        vzConfig.serialPorts = [serialPort]

        if !gui {
            if isatty(STDIN_FILENO) != 0 {
                enableRawMode()
            }
        }

        return vzConfig
    }

    // MARK: - Terminal

    private func enableRawMode() {
        var current = termios()
        tcgetattr(STDIN_FILENO, &current)
        self.originalTermios = current
        var rawTermios = current
        cfmakeraw(&rawTermios)
        tcsetattr(STDIN_FILENO, TCSANOW, &rawTermios)
    }

    private func restoreTerminal() {
        guard var t = originalTermios else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &t)
        originalTermios = nil
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
        self.signalSource = source
    }
}
