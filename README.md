# virt

A CLI tool for managing Linux VMs on macOS using Apple's Virtualization.framework.

## Requirements

- macOS 13+ on Apple Silicon
- ARM64 Linux ISOs (no x86 emulation)

## Build

```
make
```

This runs `swift build` and signs the binary with the required virtualization entitlement.

## Install

```
sudo make install
```

Builds a release binary and installs to `/usr/local/bin`. Customize with `PREFIX=~/.local`.

## Shell completions

```
source <(virt completions zsh)
```

Add that line to your `.zshrc` for persistent tab completion. Bash and fish are also supported:

```
source <(virt completions bash)
virt completions fish | source
```

## Usage

### Create a VM

```
virt create myvm --disk 16 --cpus 2 --memory 4096
```

### Install an OS from ISO

Opens a GUI window with the VM's display for OS installation:

```
virt install myvm --iso ~/Downloads/debian-13-arm64-netinst.iso
```

During the Debian installer:
- Skip the network mirror step if DNS isn't working (see Troubleshooting)
- Let GRUB install to the EFI system partition

After install, boot the VM with the GUI to configure headless console:

```
virt install myvm
```

Log in as root and add `console=hvc0` to every `linux` line in `/boot/grub/grub.cfg`:

```
nano /boot/grub/grub.cfg
```

Then shut down:

```
systemctl poweroff
```

### Start headless

```
virt start myvm
```

EFI boots silently (~5s), then the Linux console appears in your terminal.
Use `virt stop myvm` from another terminal to shut down.

### Shared folders

Share a host directory with the VM:

```
virt start myvm --share ~/code
virt install myvm --share ~/code
```

Inside the VM, mount it:

```
mkdir -p /mnt/share
mount -t virtiofs share /mnt/share
```

For persistent mounting, add to `/etc/fstab`:

```
share /mnt/share virtiofs defaults 0 0
```

### Clipboard (copy/paste)

Clipboard sharing between macOS and the Linux guest works in GUI mode
(`virt install`). Install the SPICE agent inside the VM:

```
apt install spice-vdagent
systemctl enable spice-vdagentd
```

Copy/paste works after the next boot.

### Headless console tips

The serial console passes ANSI escape codes transparently. ncurses apps
(vim, htop, tmux) work if `TERM` is set correctly:

```
export TERM=xterm-256color
```

The console defaults to 80x24. After resizing your terminal window, update
the guest:

```
stty rows 50 cols 120
```

For heavy interactive work (tmux sessions, development), SSH into the VM
over NAT is recommended:

```
apt install openssh-server
# then from macOS:
ssh user@192.168.64.x
```

### Other commands

```
virt list              # show all VMs and status
virt stop myvm         # graceful shutdown, then force kill
virt delete myvm       # remove VM (prompts for confirmation)
virt delete myvm --force
```

## Troubleshooting

### VM DNS not working

VM DNS relies on macOS's `mDNSResponder` listening on port 53. If another
process has grabbed that port, DNS silently breaks for all VMs.

Check what's on port 53:

```
sudo lsof -i :53 -n -P
```

You should see `mDNSResponder`. If you see something else (`dnsmasq`, `docker`,
`cloudflared`, etc.), stop it:

```
# Example for dnsmasq via Homebrew:
sudo brew services stop dnsmasq

# Then restart mDNSResponder:
sudo killall mDNSResponder
```

Known culprits: dnsmasq, Docker Desktop, Cloudflare WARP, Tailscale MagicDNS,
AdGuard Home, Pi-hole.

### No console output from `virt start`

The guest kernel must be configured to use `console=hvc0`. After installing
the OS with `virt install`, boot the GUI again (`virt install myvm` without
`--iso`), log in, and add `console=hvc0` to every `linux` line in
`/boot/grub/grub.cfg`.

### Ctrl-C doesn't work in headless mode

Stdin is wired directly to the VM, so Ctrl-C is sent to the guest. Use
`virt stop myvm` from another terminal to shut down.

### DHCP overwrites /etc/resolv.conf

If you manually set `nameserver 1.1.1.1` in `/etc/resolv.conf`, DHCP will
overwrite it on lease renewal. For a permanent override, add this to
`/etc/dhcp/dhclient.conf` inside the VM:

```
supersede domain-name-servers 1.1.1.1;
```

This is only needed if mDNSResponder cannot be restored as the DNS handler
on the host (see "VM DNS not working" above).
