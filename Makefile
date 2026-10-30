# One entry point for local work and CI. No Docker: xcodebuild only runs on macOS.
# Build output goes to the internal disk, one folder per worktree, so parallel
# worktrees never share products (and non-APFS repo drives do not break codesign).
BUILD_DIR ?= $(or $(TMPDIR),/tmp/)meqat/$(notdir $(CURDIR))
APP := $(BUILD_DIR)/dd/Build/Products/Debug/Meqat.app
XCODEBUILD := xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Debug \
	-destination 'platform=macOS' -derivedDataPath $(BUILD_DIR)/dd \
	CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM=

.PHONY: help check lint format test test-live build run clean

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

check: lint test build ## Everything CI runs

lint: ## swift format lint, warnings fail
	swift format lint --strict --recursive --parallel MeqatCore Meqat

format: ## Rewrite Swift files in place
	swift format format --in-place --recursive --parallel MeqatCore Meqat

test: ## MeqatCore tests, warnings as errors
	swift test --package-path MeqatCore --scratch-path $(BUILD_DIR)/core -Xswiftc -warnings-as-errors

test-live: ## MeqatCore tests including the live Aladhan API
	MEQAT_LIVE_TESTS=1 swift test --package-path MeqatCore --scratch-path $(BUILD_DIR)/core

build: ## Ad-hoc signed Debug app, warnings as errors
	$(XCODEBUILD) SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build

run: build ## Build and launch the app (HARNESS=Overlay|Menu|Settings|LoginItem for a debug harness)
	open -n $(APP) $(if $(HARNESS),--args -MeqatDebugHarness $(HARNESS))

clean: ## Remove this worktree's build output
	rm -rf $(BUILD_DIR)
