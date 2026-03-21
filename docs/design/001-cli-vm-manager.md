# Design: CLI VM Manager using Virtualization.framework

**Date**: 2026-03-20
**Status**: Implemented

## Intent

Build a Swift CLI tool that manages Linux VMs on macOS using Apple's
Virtualization framework. Replaces the workflow of running the Xcode
virtualization example project (or VMware/VirtualBox) with a terminal-native
experience.

The user wants to: define a VM from an ISO image, install via a GUI window,
then start/stop/interact headlessly via console — all from the command line.
Same mental model as VMware/VirtualBox but lighter.

## Constraints

- **macOS only** — Virtualization.framework is Apple-proprietary
- **Apple Silicon primary target** — ARM64 ISOs required (no x86 emulation)
- **GUI for install only** — `virt install` opens a window; daily use via
  `virt start` is headless CLI with console on stdin/stdout
- **ISO-based installs only** — no pre-built images, no container-style rootfs.
  The user brings their own ARM64 ISO
- **Out of scope**: snapshots, shared folders, GPU passthrough, clustering,
  multi-display, Rosetta x86 translation
- **Out of scope**: building a TUI dashboard — keep it simple commands

## Approach

**Swift Package** using:
- `ArgumentParser` — CLI command parsing
- `Virtualization` — VM lifecycle
- `AppKit` — GUI installer window (`VZVirtualMachineView`)
- `Foundation` — file management, JSON config

**VM Configuration stored as JSON** in `~/.virt/vms/<name>/config.json`
alongside the disk image and EFI variable store.

**Commands**:

| Command | What it does |
|---|---|
| `virt create <name> --disk <size> --cpus <n> --memory <mb>` | Allocate disk image, write config, store EFI NVRAM |
| `virt install <name> [--iso <path>]` | Boot VM with GUI window for OS install or configuration |
| `virt start <name>` | Boot VM headless with console in terminal |
| `virt stop <name>` | Request graceful shutdown via SIGINT; fallback to SIGKILL |
| `virt delete <name> [--force]` | Remove VM directory; prompts for confirmation unless `--force` |
| `virt list` | Show all VMs and their state (stopped/running) |

**VM hardware model** (per VM):
- `VZEFIBootLoader` + per-VM NVRAM variable store
- `VZVirtioBlockDeviceConfiguration` — main disk (raw disk image)
- `VZUSBMassStorageDeviceConfiguration` — ISO attachment (removable)
- `VZVirtioNetworkDeviceConfiguration` + `VZNATNetworkDeviceAttachment` — NAT networking
- `VZVirtioGraphicsDeviceConfiguration` — framebuffer (always present; required for EFI/GRUB)
- `VZVirtioConsoleDeviceSerialPortConfiguration` — serial console wired to stdin/stdout
- `VZVirtioEntropyDeviceConfiguration` — `/dev/random` source
- `VZUSBKeyboardConfiguration` + `VZUSBScreenCoordinatePointingDeviceConfiguration` — HID (GUI mode only)

**Entitlements** (virt.entitlements):
- `com.apple.security.virtualization` — required for Virtualization.framework
- `com.apple.security.network.server` — required for DNS forwarder on port 53

**Lifecycle management**: `virt start` runs in the foreground with the console
attached to stdin/stdout. `virt stop` from another terminal sends SIGINT then
escalates to SIGKILL. A PID file tracks running state.

**Post-install setup**: After `virt install`, the user must edit
`/boot/grub/grub.cfg` inside the VM to add `console=hvc0` to all `linux`
lines. This enables headless console output for `virt start`.

## Domain Events

| Event | What follows |
|---|---|
| VM Created | Disk image allocated, EFI NVRAM initialized, config.json written |
| VM Installed | GUI window opened; OS installed from ISO; GRUB configured |
| VM Started | Process holds VM handle; PID file written; console attached to terminal |
| VM Shutdown Requested | SIGINT sent; timeout then SIGKILL |
| VM Stopped | PID file removed; exit code returned |
| VM Deleted | Entire VM directory removed from disk |

## Checkpoints

1. ✅ `swift build` succeeds — package compiles
2. ✅ `virt create` — creates VM directory with config, disk, NVRAM
3. ✅ `virt install --iso` — opens GUI window, installs OS from ISO
4. ✅ `virt start` — boots headless, console appears in terminal
5. ✅ `virt stop` — shuts down cleanly from another terminal
6. ✅ `virt list` — shows VM name, cpu, memory, running/stopped status
7. ✅ `virt delete` — removes VM directory with confirmation
