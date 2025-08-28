# pgcalendar Installation Guide

This guide covers different ways to install the pgcalendar PostgreSQL extension.

## Prerequisites

- PostgreSQL 12.0 or later
- PostgreSQL development tools (for building from source)
- Basic knowledge of PostgreSQL administration

## Installation Methods

### Method 1: Install from PGXN (Recommended)

The easiest way to install pgcalendar is through the PostgreSQL Extension Network (PGXN):

```bash
# Install pgxnclient if you don't have it
pip install pgxnclient

# Install pgcalendar extension
pgxn install pgcalendar
```

### Method 2: Install from Source

#### Step 1: Download and Extract

```bash
# Download the source
wget https://github.com/huseyinakbas/pgcalendar/archive/refs/heads/master.zip
unzip master.zip
cd pgcalendar-master

# Or clone from git
git clone https://github.com/huseyinakbas/pgcalendar.git
cd pgcalendar
```

#### Step 2: Build and Install

```bash
# Build the extension
make

# Install to your PostgreSQL instance
sudo make install
```

#### Step 3: Create the Extension in Your Database

```sql
-- Connect to your database
\c your_database_name

-- Create the extension
CREATE EXTENSION pgcalendar;
```

### Method 3: Manual Installation

#### Step 1: Copy Files

```bash
# Copy the control file to PostgreSQL extensions directory
sudo cp pgcalendar.control /usr/share/postgresql/15/extension/

# Copy SQL files to PostgreSQL extensions directory
sudo cp pgcalendar--1.0.0.sql /usr/share/postgresql/15/extension/
sudo cp pgcalendar--1.0.0--uninstall.sql /usr/share/postgresql/15/extension/
```

#### Step 2: Create the Extension

```sql
-- Connect to your database
\c your_database_name

-- Create the extension
CREATE EXTENSION pgcalendar;
```

## Verification

After installation, verify that the extension is working:

```sql
-- Check if extension is installed
SELECT * FROM pg_extension WHERE extname = 'pgcalendar';

-- Check if schema exists
SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'pgcalendar';

-- Check if tables exist
SELECT table_name FROM information_schema.tables WHERE table_schema = 'pgcalendar' ORDER BY table_name;

-- Test basic functionality
SELECT * FROM pgcalendar.event_calendar LIMIT 5;
```

## Testing

Run the test suite to ensure everything is working correctly:

```bash
# If you have pg_regress installed
cd test
./run_tests.sh

# Or manually run tests
psql -d your_database_name -f test/sql/pgcalendar_test.sql
```

## Configuration

### Database Permissions

The extension creates a schema called `pgcalendar` and grants appropriate permissions to PUBLIC. If you need to restrict access:

```sql
-- Revoke public access
REVOKE ALL ON SCHEMA pgcalendar FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA pgcalendar FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA pgcalendar FROM PUBLIC;

-- Grant access to specific users/roles
GRANT USAGE ON SCHEMA pgcalendar TO your_role;
GRANT SELECT ON ALL TABLES IN SCHEMA pgcalendar TO your_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pgcalendar TO your_role;
```

### Performance Tuning

For production use, consider these optimizations:

```sql
-- Analyze tables for better query planning
ANALYZE pgcalendar.events;
ANALYZE pgcalendar.schedules;
ANALYZE pgcalendar.exceptions;

-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'pgcalendar'
ORDER BY idx_scan DESC;
```

## Troubleshooting

### Common Issues

#### 1. Extension Not Found

```bash
# Check if files are in the right location
ls -la /usr/share/postgresql/*/extension/pgcalendar*

# Verify PostgreSQL version
pg_config --version
```

#### 2. Permission Denied

```bash
# Check file permissions
ls -la /usr/share/postgresql/*/extension/pgcalendar*

# Fix permissions if needed
sudo chmod 644 /usr/share/postgresql/*/extension/pgcalendar*
```

#### 3. Schema Already Exists

```sql
-- Drop existing schema if needed
DROP SCHEMA IF EXISTS pgcalendar CASCADE;

-- Recreate extension
CREATE EXTENSION pgcalendar;
```

### Logs

Check PostgreSQL logs for errors:

```bash
# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-15-main.log

# Or check system logs
sudo journalctl -u postgresql -f
```

## Uninstallation

To remove the extension:

```sql
-- Drop the extension
DROP EXTENSION pgcalendar;
```

Or use the uninstall script:

```bash
# Run uninstall script
psql -d your_database_name -f /usr/share/postgresql/*/extension/pgcalendar--1.0.0--uninstall.sql
```

## Support

If you encounter issues:

1. Check the [GitHub repository](https://github.com/huseyinakbas/pgcalendar) for known issues
2. Review the [README.md](README.md) for usage examples
3. Open an issue on GitHub with detailed error information
4. Check PostgreSQL logs for detailed error messages

## Version Compatibility

| pgcalendar Version | PostgreSQL Version | Notes           |
| ------------------ | ------------------ | --------------- |
| 1.0.0              | 12.0+              | Initial release |

## License

This extension is licensed under the MIT License. See the LICENSE file for details.
