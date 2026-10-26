# platform-ops-toolkit

PREFIX     ?= $(HOME)/.local
BIN_DIR    := $(PREFIX)/bin
SHARE_DIR  := $(PREFIX)/share/platform-ops-toolkit

SHELLCHECK ?= shellcheck
BATS       ?= bats
PWSH       ?= pwsh

TOOLS      := $(notdir $(wildcard bin/*))
SH_FILES   := $(addprefix bin/,$(TOOLS)) lib/common.sh tests/test_helper.bash

.DEFAULT_GOAL := help
.PHONY: help lint lint-sh lint-ps test test-sh test-ps check install uninstall

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-10s %s\n", $$1, $$2}'

lint: lint-sh lint-ps ## Run every linter

lint-sh: ## ShellCheck all Bash code
	$(SHELLCHECK) -x $(SH_FILES)

lint-ps: ## PSScriptAnalyzer on the PowerShell module (skipped without pwsh)
	@if command -v $(PWSH) >/dev/null 2>&1; then \
		$(PWSH) -NoProfile -File powershell/Invoke-Checks.ps1 -Task Lint; \
	else echo "pwsh not found: skipping PowerShell lint"; fi

test: test-sh test-ps ## Run every test suite

test-sh: ## bats tests for the Bash tools
	$(BATS) tests

test-ps: ## Pester tests (skipped without pwsh)
	@if command -v $(PWSH) >/dev/null 2>&1; then \
		$(PWSH) -NoProfile -File powershell/Invoke-Checks.ps1 -Task Test; \
	else echo "pwsh not found: skipping Pester"; fi

check: lint test ## Lint and test, as CI does

install: ## Install to $(PREFIX) (default ~/.local): tools in share/, symlinks in bin/
	install -d $(SHARE_DIR)/bin $(SHARE_DIR)/lib $(BIN_DIR)
	install -m 0644 lib/common.sh $(SHARE_DIR)/lib/common.sh
	@for tool in $(TOOLS); do \
		install -m 0755 bin/$$tool $(SHARE_DIR)/bin/$$tool; \
		ln -sf $(SHARE_DIR)/bin/$$tool $(BIN_DIR)/$$tool; \
		echo "installed $(BIN_DIR)/$$tool"; \
	done

uninstall: ## Remove what install created
	@for tool in $(TOOLS); do rm -f $(BIN_DIR)/$$tool; done
	rm -rf $(SHARE_DIR)
