# Design: GUI Installer for ISO-based VM Setup

**Date**: 2026-03-21
**Status**: Implemented

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

- The GUI is for **install and configuration** — `virt start` stays headless
- Must work as a Swift Package (no Xcode project required)
- The installer window is minimal — no chrome beyond the VM display and a
  title bar. No menu bar app, no dock icon persistence.
- `AppKit` + `VZVirtualMachineView` — no SwiftUI dependency
- Out of scope: VNC, remote display, multi-window, clipboard sharing

## Approach

**Command**: `virt install <name> [--iso <path>]`

ISO is optional — `virt install` can also be used to boot into the GUI for
post-install configuration (e.g., editing GRUB config).

1. Load VM config and directory (VM must already exist via `virt create`)
2. Build `VZVirtualMachineConfiguration` with full hardware:
   - `VZEFIBootLoader` + NVRAM
   - Disk, optional ISO, NAT network, entropy
   - `VZVirtioGraphicsDeviceConfiguration` — framebuffer (always present,
     required for EFI/GRUB to function even in headless mode)
   - `VZUSBKeyboardConfiguration` + `VZUSBPointingDeviceConfiguration` — HID
     (GUI mode only)
   - `VZVirtioConsoleDeviceSerialPortConfiguration` on `serialPorts` — wired
     to stdin/stdout for headless console (must use direct FileHandle, not
     pipes — pipes do not carry data with this API)
3. Create an `NSApplication` with a single `NSWindow` containing a
   `VZVirtualMachineView`
4. Start the VM, run the AppKit event loop
5. Window close or VM shutdown → clean exit, remove PID file

**Post-install setup** (required for headless `virt start`):
1. Edit `/boot/grub/grub.cfg` — add `console=hvc0` to all `linux` lines
2. Shut down with `systemctl poweroff`

**Post-install flow**: `virt start <name>` boots headless. EFI runs silently
(invisible framebuffer), GRUB auto-selects default (5s timeout), Linux starts
with `console=hvc0`, interactive console appears in the terminal.

## Lessons learned

- `VZVirtioConsoleDeviceConfiguration` (consoleDevices API) does NOT carry
  data — writes to /dev/hvc0 never reach the host pipe
- `VZVirtioConsoleDeviceSerialPortConfiguration` (serialPorts API) works but
  ONLY with direct `FileHandle.standardInput`/`FileHandle.standardOutput` —
  `Pipe()` and `openpty()` do not work
- EFI firmware requires a framebuffer to function — without
  `VZVirtioGraphicsDeviceConfiguration`, EFI/GRUB hang or fail silently
- VZ NAT provides DHCP and routing but does NOT proxy DNS — the gateway is
  advertised as nameserver but doesn't respond to queries. Workaround:
  set `nameserver 1.1.1.1` in `/etc/resolv.conf` post-install
- Debian arm64 ISOs require arm64/aarch64 architecture (no x86 emulation)
- `Ctrl-C` goes to the VM in headless mode (stdin is wired to guest) —
  use `virt stop` from another terminal
- Debian uses `systemctl poweroff` (not `poweroff` or `shutdown`)

## Domain Events

| Event | What follows |
|---|---|
| Install Started | NSWindow opens with VZVirtualMachineView; VM boots from ISO via EFI; PID file written |
| Install Completed | User shuts down VM from within guest or closes window; PID file removed; window closes |
| Post-install Boot | `virt start` uses EFI; GRUB boots Linux with console=hvc0; terminal console attaches |

## Checkpoints

1. ✅ `swift build` succeeds with AppKit/VZVirtualMachineView code
2. ✅ `virt install debian --iso debian.iso` opens a window showing EFI boot
3. ✅ Debian installer is fully interactive in the window — keyboard and mouse work
4. ✅ GRUB installs successfully to the EFI system partition
5. ✅ After install + GRUB config: `virt start debian` boots headless, Linux console appears in terminal
6. ✅ `virt stop debian` shuts down cleanly
