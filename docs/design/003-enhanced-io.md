# Design: Enhanced I/O — Console, GUI Desktop, Clipboard, Shared Folders

**Date**: 2026-03-21
**Status**: Draft

## Intent

Extend virt to support real interactive work inside VMs — not just boot and
basic admin, but tmux sessions over the headless console, full Linux desktops
in the GUI window, clipboard sharing between macOS and Linux, and shared
folders for moving files without scp.

These capabilities already exist in Apple's Virtualization.framework and work
in the Xcode sample project. The goal is to expose them through virt's
existing `install` and `start` commands.

## Constraints

- Must not break the current headless `start` or GUI `install` flows
- No new commands required — enhance existing hardware configuration
- Guest-side setup (spice-vdagent, mount commands) is the user's
  responsibility, documented in README
- 3D GPU acceleration is not available (Virtualization.framework only
  provides virtio-gpu 2D) — desktop apps work but OpenGL-heavy apps
  will software-render
- Out of scope: multi-monitor, audio passthrough, USB device passthrough

## Approach

### 1. Headless console improvements

The serial console (hvc0 → stdin/stdout) is a raw byte pipe. ncurses apps,
tmux, vim, and colors already work if `TERM` is set correctly in the guest.

**Limitation**: no terminal resize signaling (SIGWINCH). The guest defaults
to 80x24. Workaround: `stty rows R cols C` in the guest. For a better
experience, SSH into the VM over NAT (192.168.64.x) is recommended for
heavy interactive use.

### 2. GUI display — auto-resize and higher resolution

Add `automaticallyReconfiguresDisplay = true` to `VZVirtualMachineView`
(macOS 14+). The guest display resolution adjusts when the user resizes
the window. Increase default scanout to a more usable resolution.

### 3. Clipboard sharing

Add a second `VZVirtioConsoleDeviceConfiguration` with
`VZSpiceAgentPortAttachment` to `consoleDevices`. This is separate from
the serial port (which lives on `serialPorts`). Only active in GUI mode.

Guest requirement: install `spice-vdagent` package and run the daemon.

### 4. Shared folders

Add `VZVirtioFileSystemDeviceConfiguration` with a configurable host
directory. Guest mounts with `mount -t virtiofs <tag> /mnt/shared`.

New option on `start` and `install`: `--share <path>` to share a host
directory with the VM.

## Domain Events

| Event | What follows |
|---|---|
| GUI VM started | Clipboard channel established via SPICE agent; display auto-resizes |
| Shared folder configured | Host directory mounted in guest via virtiofs |
| Headless VM started | Serial console attached; user configures TERM and stty as needed |

## Checkpoints

1. `virt install myvm` — window auto-resizes guest display when dragged
2. Copy/paste works between macOS and Linux desktop (after `apt install spice-vdagent`)
3. `virt start myvm --share ~/code` — host directory accessible at mount point in guest
4. tmux/vim work over headless console with correct colors and layout
