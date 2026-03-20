# Design: CLI VM Manager using Virtualization.framework

**Date**: 2026-03-20
**Status**: Draft

## Intent

Build a Swift CLI tool that manages Linux VMs on macOS using Apple's Virtualization framework. Replaces the workflow of running the Xcode virtualization example project (or VMware/VirtualBox) with a terminal-native experience.

The user wants to: define a VM from an ISO image, start it, interact via console, stop it, delete it — all from the command line. No GUI. Same mental model as VMware/VirtualBox but lighter.

## Constraints

- **macOS only** — Virtualization.framework is Apple-proprietary
- **Apple Silicon primary target** — EFI boot via `VZEFIBootLoader` (Intel support is possible but not the priority)
- **No GUI** — pure CLI; console access via virtio serial to stdin/stdout
- **ISO-based installs only** — no pre-built images, no container-style rootfs. The user brings their own ISO
- **Out of scope**: snapshots, shared folders, GPU passthrough, clustering, multi-display, Rosetta x86 translation
- **Out of scope**: building a TUI dashboard — keep it simple commands

## Approach

**Swift Package** using:
- `ArgumentParser` — CLI command parsing
- `Virtualization` — VM lifecycle
- `Foundation` — file management, JSON config

**VM Configuration stored as JSON** in `~/.virt/vms/<name>/config.json` alongside the disk image and EFI variable store.

**Commands**:

| Command | What it does |
|---|---|
| `virt create <name> --iso <path> --disk <size> --cpus <n> --memory <mb>` | Allocate disk image, write config, store EFI NVRAM |
| `virt start <name> [--iso <path>]` | Boot VM; optional ISO attachment for install/rescue |
| `virt stop <name>` | Request graceful shutdown via virtio; fallback to force kill |
| `virt delete <name>` | Remove VM directory (disk, config, NVRAM) |
| `virt list` | Show all VMs and their state (stopped/running) |

**VM hardware model** (per VM):
- `VZEFIBootLoader` + per-VM NVRAM variable store
- `VZVirtioBlockDeviceConfiguration` — main disk (raw disk image)
- `VZUSBMassStorageDeviceConfiguration` — ISO attachment (removable)
- `VZVirtioNetworkDeviceConfiguration` + `VZNATNetworkDeviceAttachment` — NAT networking
- `VZVirtioConsoleDeviceConfiguration` — serial console piped to process stdin/stdout
- `VZVirtioEntropyDeviceConfiguration` — `/dev/random` source

**Lifecycle management**: A running VM is a process. `start` runs in the foreground with the console attached. Ctrl-C triggers graceful shutdown. A PID file tracks running state for `list` and `stop` (from another terminal).

## Domain Events

| Event | What follows |
|---|---|
| **VM Created** | Disk image allocated, EFI NVRAM initialized, config.json written |
| **VM Started** | Process holds VM handle; PID file written; console attached to terminal |
| **VM Shutdown Requested** | `VZVirtualMachine.requestStop()` called; timeout then force kill |
| **VM Stopped** | PID file removed; exit code returned |
| **VM Deleted** | Entire VM directory removed from disk |

## Checkpoints

1. `swift build` succeeds — package compiles against Virtualization framework
2. `virt create test --disk 10 --cpus 2 --memory 2048` — creates `~/.virt/vms/test/` with config.json and a 10GB disk image
3. `virt start test --iso ubuntu.iso` — boots to ISO installer, console is interactive in terminal
4. After OS install: `virt start test` (no ISO) — boots from disk into installed Linux
5. `virt stop test` from another terminal — VM shuts down cleanly
6. `virt list` — shows VM name, cpu, memory, running/stopped status
7. `virt delete test` — directory gone
