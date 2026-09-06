PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
SWIFTC ?= swiftc

.PHONY: all build clean install test

all: build

build: bin/sgwebapp-border

bin/sgwebapp-border: src/border/main.swift
	@mkdir -p bin
	$(SWIFTC) -O src/border/main.swift -o bin/sgwebapp-border
	@chmod +x bin/sgwebapp

test: build
	@chmod +x tests/test_suite.sh
	@./tests/test_suite.sh

install: build
	@mkdir -p $(BIN_DIR)
	install -m 755 bin/sgwebapp $(BIN_DIR)/sgwebapp
	install -m 755 bin/sgwebapp-border $(BIN_DIR)/sgwebapp-border
	@ln -sf $(BIN_DIR)/sgwebapp $(BIN_DIR)/sgwebapp-install
	@ln -sf $(BIN_DIR)/sgwebapp $(BIN_DIR)/sgwebapp-list
	@ln -sf $(BIN_DIR)/sgwebapp $(BIN_DIR)/sgwebapp-launch
	@ln -sf $(BIN_DIR)/sgwebapp $(BIN_DIR)/sgwebapp-remove
	@echo "Installed sgwebapp to $(BIN_DIR)"

clean:
	rm -f bin/sgwebapp-border
