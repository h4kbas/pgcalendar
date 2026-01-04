# Makefile for pgcalendar PostgreSQL extension
# Provides commands for development, testing, building, and publishing

# Configuration
EXTENSION = pgcalendar
VERSION = 1.0.1
PG_VERSION ?= 15
PG_PORT ?= 5433
PG_USER ?= postgres
PG_PASSWORD ?= postgres
PG_DB ?= pgcalendar_test
PG_HOST ?= localhost
PG_DATA_DIR ?= ./postgres_data_test

# Colors for output
GREEN = \033[0;32m
RED = \033[0;31m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

.PHONY: help clean test build publish install

# Help target
help:
	@echo "$(BLUE)pgcalendar PostgreSQL Extension - Available Commands:$(NC)"
	@echo ""
	@echo "$(GREEN)Main Commands:$(NC)"
	@echo "  $(YELLOW)make clean$(NC)    - Clean build artifacts, test data, and temporary files"
	@echo "  $(YELLOW)make test$(NC)     - Run Node.js test suite"
	@echo "  $(YELLOW)make build$(NC)    - Create PGXN-ready tarball"
	@echo "  $(YELLOW)make publish$(NC) - Publish extension to PGXN (requires pgxnclient)"
	@echo ""
	@echo "$(GREEN)Other Commands:$(NC)"
	@echo "  $(YELLOW)make install$(NC)  - Install extension to system PostgreSQL"
	@echo "  $(YELLOW)make help$(NC)     - Show this help message"

# Clean build artifacts, test data, and temporary files
clean:
	@echo "$(BLUE)Cleaning build artifacts and temporary files...$(NC)"
	@rm -rf $(EXTENSION)-$(VERSION).tar.gz
	@rm -rf node_modules
	@rm -rf coverage
	@rm -rf .jest
	@rm -rf $(PG_DATA_DIR)
	@rm -f *.log
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "$(GREEN)✓ Clean complete$(NC)"

# Run Node.js test suite
test:
	@echo "$(BLUE)Running Node.js test suite...$(NC)"
	@if [ ! -d "node_modules" ]; then \
		echo "$(YELLOW)Installing dependencies...$(NC)"; \
		npm install; \
	fi
	@npm test
	@echo "$(GREEN)✓ Tests completed$(NC)"

# Build PGXN-ready tarball
build: clean
	@echo "$(BLUE)Building PGXN-ready tarball...$(NC)"
	@echo "$(YELLOW)Version: $(VERSION)$(NC)"
	@if [ ! -f "META.json" ]; then \
		echo "$(RED)Error: META.json not found$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(EXTENSION).control" ]; then \
		echo "$(RED)Error: $(EXTENSION).control not found$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(EXTENSION).sql" ]; then \
		echo "$(RED)Error: $(EXTENSION).sql not found$(NC)"; \
		exit 1; \
	fi
	@mkdir -p dist/$(EXTENSION)-$(VERSION)
	@cp $(EXTENSION).control dist/$(EXTENSION)-$(VERSION)/
	@cp $(EXTENSION).sql dist/$(EXTENSION)-$(VERSION)/$(EXTENSION)--$(VERSION).sql
	@if [ -f "$(EXTENSION)--uninstall.sql" ]; then \
		cp $(EXTENSION)--uninstall.sql dist/$(EXTENSION)-$(VERSION)/$(EXTENSION)--$(VERSION)--uninstall.sql; \
	fi
	@cp META.json dist/$(EXTENSION)-$(VERSION)/
	@cp README.md dist/$(EXTENSION)-$(VERSION)/
	@cp LICENSE dist/$(EXTENSION)-$(VERSION)/
	@if [ -f "Makefile.pgxn" ]; then \
		cp Makefile.pgxn dist/$(EXTENSION)-$(VERSION)/Makefile; \
	fi
	@cd dist && tar -czf ../$(EXTENSION)-$(VERSION).tar.gz $(EXTENSION)-$(VERSION)
	@rm -rf dist
	@echo "$(GREEN)✓ Build complete: $(EXTENSION)-$(VERSION).tar.gz$(NC)"

# Publish to PGXN
publish: build
	@echo "$(BLUE)Publishing to PGXN...$(NC)"
	@which pgxn > /dev/null || (echo "$(RED)Error: pgxnclient is required but not installed$(NC)" && echo "$(YELLOW)Install with: pip install pgxnclient$(NC)" && exit 1)
	@echo "$(YELLOW)Uploading $(EXTENSION)-$(VERSION).tar.gz to PGXN...$(NC)"
	@pgxn upload $(EXTENSION)-$(VERSION).tar.gz || (echo "$(RED)Error: Failed to upload to PGXN$(NC)" && exit 1)
	@echo "$(GREEN)✓ Published to PGXN successfully!$(NC)"
	@echo "$(BLUE)Visit: https://pgxn.org/dist/$(EXTENSION)/$(NC)"

# Install extension to system PostgreSQL
install: check-psql
	@echo "$(BLUE)Installing $(EXTENSION) extension to system PostgreSQL...$(NC)"
	@echo "$(YELLOW)This will install to the default PostgreSQL instance$(NC)"
	@echo "$(YELLOW)Make sure you have appropriate permissions$(NC)"
	@if [ -f "$(EXTENSION).sql" ]; then \
		psql -f $(EXTENSION).sql; \
	else \
		echo "$(RED)Error: $(EXTENSION).sql not found$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Extension installed successfully!$(NC)"

# Check if psql is available for system installation
check-psql:
	@which psql > /dev/null || (echo "$(RED)Error: psql (PostgreSQL client) is required but not installed$(NC)" && exit 1)
