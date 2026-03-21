# Design: GUI Installer for ISO-based VM Setup

**Date**: 2026-03-21
**Status**: Draft

## Intent

The Virtualization.framework EFI firmware only outputs to a framebuffer — it
does not expose serial or virtio console to the bootloader. This means EFI,
GRUB, and OS installers are invisible in a headless CLI session. Workarounds
(extracting kernels, bypassing EFI with VZLinuxBootLoader) are fragile and
break the installer's bootloader setup.

Add a `virt install` command that opens a minimal macOS window with the VM's
framebuffer displayed via `VZVirtualMachineView`. The installer sees real EFI
hardware — GRUB installs correctly, the user interacts with the installer
natively, and the result is a properly bootable disk. This is a one-time
operation per VM; daily use remains headless CLI via `virt start`.

## Constraints

- The GUI is **install-only** — `virt start` stays headless CLI
- Must work as a Swift Package (no Xcode project required)
- The installer window is minimal — no chrome beyond the VM display and a
  title bar. No menu bar app, no dock icon persistence.
- `AppKit` + `VZVirtualMachineView` — no SwiftUI dependency
- The `install` command replaces `start --iso` as the recommended way to set
  up a VM from an ISO
- `start --iso` can remain for advanced/rescue use but is not the primary path
- During install the user should configure GRUB with `console=hvc0` so that
  `virt start` (headless) works post-install
- Out of scope: VNC, remote display, multi-window, clipboard sharing

## Approach

**New command**: `virt install <name> --iso <path>`

1. Load VM config and directory (VM must already exist via `virt create`)
2. Build `VZVirtualMachineConfiguration` with full hardware:
   - `VZEFIBootLoader` + NVRAM (same as today)
   - Disk, ISO, NAT network, entropy (same as today)
   - `VZVirtioGraphicsDeviceConfiguration` — framebuffer for the display
   - `VZUSBKeyboardConfiguration` + `VZUSBPointingDeviceConfiguration` — HID
   - `VZVirtioConsoleDeviceConfiguration` — still wired to hvc0 for
     post-install use
3. Create an `NSApplication` with a single `NSWindow` containing a
   `VZVirtualMachineView`
4. Start the VM, run the AppKit event loop
5. Window close or VM shutdown → clean exit, remove PID file

**Post-install flow**: user runs `virt start <name>` (no ISO, no window).
EFI boots silently, GRUB auto-selects default entry (invisible, 5s timeout),
Linux starts with `console=hvc0`, interactive console appears in the terminal.

**Code organization**:
- `Sources/virt/Commands/Install.swift` — the new command
- `Sources/virt/InstallerApp.swift` — minimal AppKit app + window setup
- `VMInstance` is refactored so both `start` (headless) and `install` (GUI)
  share the same VM configuration builder, differing only in boot mode and
  display

## Domain Events

| Event | What follows |
|---|---|
| Install Started | NSWindow opens with VZVirtualMachineView; VM boots from ISO via EFI; PID file written |
| Install Completed | User shuts down VM from within guest or closes window; PID file removed; window closes |
| Post-install Boot | `virt start` uses EFI; GRUB boots Linux with console=hvc0; terminal console attaches |

## Checkpoints

1. `swift build` succeeds with AppKit/VZVirtualMachineView code
2. `virt install debian --iso debian.iso` opens a window showing EFI boot
3. Debian installer is fully interactive in the window — keyboard and mouse work
4. GRUB installs successfully to the EFI system partition
5. After install: `virt start debian` boots headless, Linux console appears in terminal
6. `virt stop debian` shuts down cleanly
