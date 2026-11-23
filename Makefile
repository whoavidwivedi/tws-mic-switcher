SWIFTC ?= swiftc
SRC = $(wildcard Sources/*.swift)
BIN = bin/tws-mic-switcher

.PHONY: all build install uninstall clean status switch menubar daemon

all: build

build: $(BIN)

$(BIN): $(SRC)
	@mkdir -p bin
	$(SWIFTC) -O $(SRC) -o $(BIN)
	@echo "Built $(BIN)"

install: build
	@chmod +x scripts/install.sh
	@scripts/install.sh

uninstall:
	@chmod +x scripts/uninstall.sh
	@scripts/uninstall.sh

status: build
	@$(BIN) status

switch: build
	@$(BIN) switch

menubar: build
	@$(BIN) menubar

daemon: build
	@$(BIN) daemon

clean:
	rm -rf bin
