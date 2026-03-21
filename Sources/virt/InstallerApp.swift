import AppKit
import Virtualization

/// Minimal AppKit application that displays a VM's framebuffer in a window.
/// Used by `virt install` for ISO-based OS installation.
class InstallerApp: NSObject, NSApplicationDelegate, VZVirtualMachineDelegate, NSWindowDelegate {
    private let vmInstance: VMInstance
    private var vm: VZVirtualMachine?
    private var window: NSWindow?

    init(vmInstance: VMInstance) {
        self.vmInstance = vmInstance
    }

    func run() throws {
        let vzConfig = try vmInstance.buildGUIConfiguration()

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self

        let vm = VZVirtualMachine(configuration: vzConfig)
        vm.delegate = self
        self.vm = vm

        let vmView = VZVirtualMachineView()
        vmView.virtualMachine = vm
        vmView.capturesSystemKeys = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "virt install: \(vmInstance.config.name)"
        window.contentView = vmView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        vmInstance.startVM(vm)

        app.activate(ignoringOtherApps: true)
        app.run()

        vmInstance.cleanup()
    }

    // MARK: - VZVirtualMachineDelegate

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        fputs("VM stopped with error: \(error.localizedDescription)\n", stderr)
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        fputs("VM stopped.\n", stderr)
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let vm = vm, vm.state == .running || vm.state == .starting {
            vmInstance.requestShutdown()
            // Give it a moment, then terminate
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSApplication.shared.terminate(nil)
            }
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - NSApplicationDelegate

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
