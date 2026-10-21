# Common tasks for Luna; run `make` for the list. `make check` mirrors CI.
.DEFAULT_GOAL := help
.PHONY: help run preview install dmg check build test lint fmt icons clean

APP_DIR ?= /Applications

# With only the Command Line Tools, Swift Testing's macro plugin sits outside the default search path.
CLT := /Library/Developer/CommandLineTools
TEST_FLAGS := $(if $(filter $(CLT),$(shell xcode-select -p 2>/dev/null)),-Xswiftc -plugin-path -Xswiftc $(CLT)/usr/lib/swift/host/plugins/testing,)

help: ## Show this list
	@awk 'BEGIN {FS = ":.*## "} /^[a-z0-9-]+:.*## / {printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

run: ## Build a debug Luna.app and open it (quit the installed Luna first)
	@pkill -x Luna 2>/dev/null || true
	scripts/build-app.sh --debug --out build/debug
	open build/debug/Luna.app

preview: ## The panel with made-up displays, for design work (ARGS="--dark --displays 3 --settings")
	@pkill -x Luna 2>/dev/null || true
	scripts/build-app.sh --debug --out build/debug
	build/debug/Luna.app/Contents/MacOS/Luna --preview $(ARGS) &

install: ## Build Luna.app and install it in /Applications
	@if pgrep -f "$(APP_DIR)/Luna.app/Contents/MacOS/" >/dev/null; then echo "Quit Luna first (◐ › Quit Luna), then run make install again."; exit 1; fi
	scripts/build-app.sh
	rm -rf "$(APP_DIR)/Luna.app"
	cp -R build/Luna.app "$(APP_DIR)/"
	@echo "Installed $(APP_DIR)/Luna.app."

dmg: ## Universal Luna.app and Luna.dmg in build/
	scripts/build-app.sh --universal
	scripts/make-dmg.sh build/Luna.app build/Luna.dmg

check: lint build test ## Everything CI runs

build: ## Compile everything
	swift build

test: ## Unit tests
	swift test $(TEST_FLAGS)

lint: ## swift-format, strict
	swift format lint --strict --recursive Sources Tests Package.swift

fmt: ## Format the code
	swift format --in-place --recursive Sources Tests Package.swift

icons: ## Re-render the app icon (scripts/app-icon.swift)
	scripts/make-icons.sh

clean: ## Remove build output
	rm -rf .build build
