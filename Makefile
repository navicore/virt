PREFIX ?= /usr/local

.PHONY: build release install uninstall completions clean

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

completions: build
	@echo "# Add to your .zshrc:"
	@echo '#   fpath=(~/.zfunc $$fpath)'
	@echo '#   autoload -Uz compinit && compinit'
	@mkdir -p ~/.zfunc
	.build/debug/virt --generate-completion-script zsh > ~/.zfunc/_virt
	@echo "Installed zsh completions to ~/.zfunc/_virt"
	@echo "Restart your shell or run: autoload -Uz compinit && compinit"

uninstall:
	rm -f $(PREFIX)/bin/virt

clean:
	swift package clean
