# Makefile for pgcalendar PostgreSQL extension
# Provides commands for development, testing, and installation

# Configuration
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

.PHONY: help init install test shutdown clean

# Help target
help:
	@echo "$(BLUE)pgcalendar PostgreSQL Extension - Available Commands:$(NC)"
	@echo ""
	@echo "$(GREEN)Development Commands:$(NC)"
	@echo "  $(YELLOW)make init$(NC)      - Initialize test PostgreSQL instance and load extension"
	@echo "  $(YELLOW)make test$(NC)      - Run tests on running test instance"
	@echo "  $(YELLOW)make shutdown$(NC)  - Shutdown test instance"
	@echo "  $(YELLOW)make clean$(NC)     - Cleanup/destroy test instance completely"
	@echo "  $(YELLOW)make reload$(NC)    - Reload extension without restarting container"
	@echo "  $(YELLOW)make debug$(NC)     - Debug database state and tables"
	@echo ""
	@echo "$(GREEN)Installation Commands:$(NC)"
	@echo "  $(YELLOW)make install$(NC)   - Install extension to system PostgreSQL"
	@echo ""
	@echo "$(GREEN)Configuration:$(NC)"
	@echo "  PG_VERSION=$(PG_VERSION) (PostgreSQL version)"
	@echo "  PG_PORT=$(PG_PORT) (test instance port)"
	@echo "  PG_USER=$(PG_USER) (database user)"
	@echo "  PG_DB=$(PG_DB) (test database name)"
	@echo "  PG_DATA_DIR=$(PG_DATA_DIR) (test data directory)"

# Initialize test PostgreSQL instance and load extension
init: check-docker
	@echo "$(BLUE)Initializing test PostgreSQL instance...$(NC)"
	@echo "$(YELLOW)Using PostgreSQL $(PG_VERSION) on port $(PG_PORT)$(NC)"
	
	# Create data directory if it doesn't exist
	@mkdir -p $(PG_DATA_DIR)
	
	# Start PostgreSQL container
	@docker run -d \
		--name pgcalendar-test \
		-e POSTGRES_USER=$(PG_USER) \
		-e POSTGRES_PASSWORD=$(PG_PASSWORD) \
		-e POSTGRES_DB=$(PG_DB) \
		-p $(PG_PORT):5432 \
		-v $(PWD):/workspace \
		-v $(PG_DATA_DIR):/var/lib/postgresql/data \
		postgres:$(PG_VERSION) > /dev/null 2>&1 || true
	
	@echo "$(YELLOW)Waiting for PostgreSQL to start...$(NC)"
	@until docker exec pgcalendar-test pg_isready -U $(PG_USER) -d $(PG_DB) > /dev/null 2>&1; do \
		echo "$(YELLOW)Waiting for database...$(NC)"; \
		sleep 2; \
	done
	
	@echo "$(GREEN)PostgreSQL is ready!$(NC)"
	@echo "$(BLUE)Loading pgcalendar extension...$(NC)"
	
	# Load the extension with verbose output
	@docker exec -i pgcalendar-test psql -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 < pgcalendar.sql
	
	@echo "$(BLUE)Verifying tables were created...$(NC)"
	
	# Check if all expected tables exist
	@docker exec -i pgcalendar-test psql -U $(PG_USER) -d $(PG_DB) -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'pgcalendar' ORDER BY table_name;" | grep -E "(events|schedules|exceptions)" || (echo "$(RED)Error: Not all tables were created$(NC)" && exit 1)
	
	@echo "$(GREEN)✓ Extension loaded successfully!$(NC)"
	@echo "$(BLUE)Test instance ready on localhost:$(PG_PORT)$(NC)"
	@echo "$(BLUE)Database: $(PG_DB), User: $(PG_USER), Password: $(PG_PASSWORD)$(NC)"
	@echo "$(YELLOW)Run 'make test' to execute tests$(NC)"
	@echo "$(YELLOW)Run 'make connect' to connect to database$(NC)"

# Install extension to system PostgreSQL
install: check-psql
	@echo "$(BLUE)Installing pgcalendar extension to system PostgreSQL...$(NC)"
	@echo "$(YELLOW)This will install to the default PostgreSQL instance$(NC)"
	@echo "$(YELLOW)Make sure you have appropriate permissions$(NC)"
	
	# Check if extension already exists
	@psql -c "SELECT 1 FROM pg_extension WHERE extname = 'pgcalendar'" > /dev/null 2>&1 && \
		echo "$(YELLOW)Extension already exists. Updating...$(NC)" || \
		echo "$(BLUE)Creating new extension...$(NC)"
	
	# Load the extension
	@psql -f pgcalendar.sql
	
	@echo "$(GREEN)✓ Extension installed successfully!$(NC)"
	@echo "$(BLUE)You can now use pgcalendar functions in your databases$(NC)"

# Run tests on running test instance
test: check-test-instance
	@echo "$(BLUE)Running pgcalendar tests...$(NC)"
	@echo "$(YELLOW)Test database: $(PG_DB) on localhost:$(PG_PORT)$(NC)"
	
	# Run the test file
	@docker exec -i pgcalendar-test psql -U $(PG_USER) -d $(PG_DB) < test_pgcalendar.sql
	
	@echo "$(GREEN)✓ Tests completed!$(NC)"

# Shutdown test instance (keeps data)
shutdown: check-test-instance
	@echo "$(BLUE)Shutting down test PostgreSQL instance...$(NC)"
	@docker stop pgcalendar-test
	@echo "$(GREEN)✓ Test instance stopped$(NC)"
	@echo "$(YELLOW)Data preserved in $(PG_DATA_DIR)$(NC)"
	@echo "$(YELLOW)Run 'make init' to restart$(NC)"

# Cleanup/destroy test instance completely
clean: check-test-instance
	@echo "$(RED)Destroying test PostgreSQL instance and data...$(NC)"
	@docker stop pgcalendar-test > /dev/null 2>&1 || true
	@docker rm pgcalendar-test > /dev/null 2>&1 || true
	@rm -rf $(PG_DATA_DIR)
	@echo "$(GREEN)✓ Test instance and data completely removed$(NC)"

# Check if Docker is available
check-docker:
	@which docker > /dev/null || (echo "$(RED)Error: Docker is required but not installed$(NC)" && exit 1)
	@docker --version > /dev/null || (echo "$(RED)Error: Docker is not running$(NC)" && exit 1)

# Check if test instance is running
check-test-instance:
	@docker ps | grep pgcalendar-test > /dev/null || (echo "$(RED)Error: Test instance not running. Run 'make init' first$(NC)" && exit 1)

# Check if psql is available for system installation
check-psql:
	@which psql > /dev/null || (echo "$(RED)Error: psql (PostgreSQL client) is required but not installed$(NC)" && exit 1)

# Show status of test instance
status:
	@echo "$(BLUE)pgcalendar Test Instance Status:$(NC)"
	@if docker ps | grep pgcalendar-test > /dev/null; then \
		echo "$(GREEN)✓ Test instance is running$(NC)"; \
		echo "$(BLUE)  Port: $(PG_PORT)$(NC)"; \
		echo "$(BLUE)  Database: $(PG_DB)$(NC)"; \
		echo "$(BLUE)  User: $(PG_USER)$(NC)"; \
		echo "$(BLUE)  Data directory: $(PG_DATA_DIR)$(NC)"; \
	else \
		echo "$(RED)✗ Test instance is not running$(NC)"; \
		echo "$(YELLOW)Run 'make init' to start$(NC)"; \
	fi

# Connect to test database
connect:
	@echo "$(BLUE)Connecting to test database...$(NC)"
	@docker exec -it pgcalendar-test psql -U $(PG_USER) -d $(PG_DB)

# Show logs from test instance
logs:
	@echo "$(BLUE)Test instance logs:$(NC)"
	@docker logs pgcalendar-test

# Debug: Check what's in the database
debug:
	@echo "$(BLUE)Debugging database state...$(NC)"
	@echo "$(YELLOW)Checking if pgcalendar schema exists:$(NC)"
	@docker exec -i pgcalendar-test psql -U $(PG_USER) -d $(PG_DB) -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'pgcalendar';"
	@echo "$(YELLOW)Checking all tables in pgcalendar schema:$(NC)"
	@docker exec -i pgcalendar-test psql -U $(PG_USER) -d $(PG_DB) -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'pgcalendar' ORDER BY table_name;"
	@echo "$(YELLOW)Checking if tables have data:$(NC)"
	@docker exec -i pgcalendar-test psql -U $(PG_USER) -d $(PG_DB) -c "SELECT 'events' as table_name, COUNT(*) as count FROM pgcalendar.events UNION ALL SELECT 'schedules', COUNT(*) FROM pgcalendar.schedules UNION ALL SELECT 'exceptions', COUNT(*) FROM pgcalendar.exceptions;"

# Quick restart (stop and start)
restart: shutdown
	@echo "$(YELLOW)Waiting 3 seconds before restart...$(NC)"
	@sleep 3
	@$(MAKE) init

# Reload extension (without restarting container)
reload:
	@echo "$(BLUE)Reloading pgcalendar extension...$(NC)"
	@docker exec -i pgcalendar-test psql -U $(PG_USER) -d $(PG_DB) -c "DROP SCHEMA IF EXISTS pgcalendar CASCADE;"
	@docker exec -i pgcalendar-test psql -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 < pgcalendar.sql
	@echo "$(GREEN)✓ Extension reloaded successfully!$(NC)"

# Show all running containers
ps:
	@echo "$(BLUE)Running containers:$(NC)"
	@docker ps

# Clean up all test-related containers (force cleanup)
clean-all:
	@echo "$(RED)Force cleaning all test containers...$(NC)"
	@docker stop pgcalendar-test > /dev/null 2>&1 || true
	@docker rm pgcalendar-test > /dev/null 2>&1 || true
	@docker rm -f pgcalendar-test > /dev/null 2>&1 || true
	@rm -rf $(PG_DATA_DIR)
	@echo "$(GREEN)✓ All test containers and data removed$(NC)"

# Development workflow: init -> test -> clean
dev: init test
	@echo "$(GREEN)Development workflow completed!$(NC)"
	@echo "$(YELLOW)Run 'make clean' to clean up$(NC)"

# Show this help
.PHONY: help
