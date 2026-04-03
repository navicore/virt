PREFIX ?= /usr/local

.PHONY: build release install uninstall clean

build:
	swift build
	codesign --entitlements virt.entitlements --force -s - .build/debug/virt

release:
	swift build -c release
	codesign --entitlements virt.entitlements --force -s - .build/release/virt

install: release
	install -d $(PREFIX)/bin
	install .build/release/virt $(PREFIX)/bin/virt
	codesign --entitlements virt.entitlements --force -s - $(PREFIX)/bin/virt

uninstall:
	rm -f $(PREFIX)/bin/virt

clean:
	swift package clean
