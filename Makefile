.PHONY: build run clean

APP_NAME = GRBrowser
BUILD_DIR = build
BINARY = $(BUILD_DIR)/$(APP_NAME)

# Build the binary
build:
	@mkdir -p $(BUILD_DIR)
	python3 swift-build.py $(BINARY) --embedded-plist
	@echo ""
	@echo "  Built: $(BINARY)"
	@echo "  Run:   make run"
	@echo ""

# Build and run
run: build
	@./$(BINARY)

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
