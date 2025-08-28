#!/bin/bash

# Test runner script for pgcalendar extension
# This script runs the test suite using pg_regress

set -e

# Configuration
PG_VERSION=${PG_VERSION:-15}
PG_PORT=${PG_PORT:-5433}
PG_USER=${PG_USER:-postgres}
PG_DB=${PG_DB:-pgcalendar_test}

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Running pgcalendar extension tests...${NC}"
echo -e "${YELLOW}PostgreSQL version: ${PG_VERSION}${NC}"
echo -e "${YELLOW}Database: ${PG_DB} on localhost:${PG_PORT}${NC}"
echo ""

# Check if pg_regress is available
if ! command -v pg_regress &> /dev/null; then
    echo -e "${RED}Error: pg_regress not found${NC}"
    echo -e "${YELLOW}Please install PostgreSQL development tools${NC}"
    exit 1
fi

# Check if test database is accessible
if ! psql -h localhost -p $PG_PORT -U $PG_USER -d $PG_DB -c "SELECT 1;" &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to test database${NC}"
    echo -e "${YELLOW}Make sure PostgreSQL is running and accessible${NC}"
    echo -e "${YELLOW}You can use 'make init' to start a test instance${NC}"
    exit 1
fi

# Create test database if it doesn't exist
psql -h localhost -p $PG_PORT -U $PG_USER -d postgres -c "CREATE DATABASE $PG_DB;" 2>/dev/null || true

# Install the extension
echo -e "${BLUE}Installing pgcalendar extension...${NC}"
psql -h localhost -p $PG_PORT -U $PG_USER -d $PG_DB -f pgcalendar--1.0.0.sql

# Run tests using pg_regress
echo -e "${BLUE}Running test suite...${NC}"
cd test
pg_regress --host=localhost --port=$PG_PORT --user=$PG_USER --dbname=$PG_DB pgcalendar_test

echo ""
echo -e "${GREEN}✓ Tests completed successfully!${NC}"
echo -e "${BLUE}Test results are available in the test output above${NC}"
