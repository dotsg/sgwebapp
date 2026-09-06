PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
SHARE_DIR ?= $(PREFIX)/share/sgwebapp
SWIFTC ?= swiftc

.PHONY: all build clean install test test-e2e lint

all: build

build: bin/sgwebapp-border bin/sgwebapp-runtime

bin/sgwebapp-border: src/border/main.swift
	@mkdir -p bin
	$(SWIFTC) -O src/border/main.swift -o bin/sgwebapp-border

bin/sgwebapp-runtime: src/runtime/main.swift
	@mkdir -p bin
	$(SWIFTC) -O src/runtime/main.swift -o bin/sgwebapp-runtime

test: build
	@chmod +x tests/test_suite.sh
	@./tests/test_suite.sh

# Launches a real GUI app; keep it out of `make test` so headless runs stay green.
test-e2e: build
	@python3 tests/test_e2e.py

install: build
	@mkdir -p $(BIN_DIR) $(SHARE_DIR)/tools $(SHARE_DIR)/runtime $(SHARE_DIR)/border
	install -m 755 src/tools/chrome_cookies.py $(SHARE_DIR)/tools/chrome_cookies.py
	install -m 755 src/tools/fallback_icon.py $(SHARE_DIR)/tools/fallback_icon.py
	install -m 644 src/runtime/main.swift $(SHARE_DIR)/runtime/main.swift
	install -m 644 src/border/main.swift $(SHARE_DIR)/border/main.swift
	install -m 755 bin/sgwebapp $(BIN_DIR)/sgwebapp
	install -m 755 bin/sgwebapp-border $(BIN_DIR)/sgwebapp-border
	install -m 755 bin/sgwebapp-runtime $(BIN_DIR)/sgwebapp-runtime
	@ln -sf $(BIN_DIR)/sgwebapp $(BIN_DIR)/sgwebapp-install
	@ln -sf $(BIN_DIR)/sgwebapp $(BIN_DIR)/sgwebapp-list
	@ln -sf $(BIN_DIR)/sgwebapp $(BIN_DIR)/sgwebapp-launch
	@ln -sf $(BIN_DIR)/sgwebapp $(BIN_DIR)/sgwebapp-remove
	@echo "Installed sgwebapp to $(BIN_DIR) (support files in $(SHARE_DIR))"

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not installed; skipping"; exit 0; }
	shellcheck -S warning bin/sgwebapp tests/test_suite.sh

clean:
	rm -f bin/sgwebapp-border bin/sgwebapp-runtime
