.PHONY: build clean

build:
	swift build
	codesign --entitlements virt.entitlements --force -s - .build/debug/virt

clean:
	swift package clean
