# pgcalendar - Infinite Calendar Extension for PostgreSQL

A powerful PostgreSQL extension for managing recurring events with infinite projections, multiple schedule configurations, and exception handling.

## Overview

pgcalendar provides a robust system for managing recurring events where:

- **Events** represent logical entities (meetings, tasks, etc.)
- **Schedules** define non-overlapping time configurations that generate projections
- **Exceptions** modify individual instances (cancellations, modifications)
- **Projections** are the actual calendar occurrences generated from schedules

## Installation

### Prerequisites

- PostgreSQL 12.0 or later
- PostgreSQL development tools (for building from source)

### Method 1: Install from PGXN (Recommended)

```bash
pip install pgxnclient
pgxn install pgcalendar
```

### Method 2: Install from Source

```bash
# Clone the repository
git clone https://github.com/h4kbas/pgcalendar.git
cd pgcalendar

# Build and install
make
sudo make install

# Create extension in your database
psql -d your_database -c "CREATE EXTENSION pgcalendar;"
```

### Method 3: Manual Installation

```bash
# Copy files to PostgreSQL extensions directory
sudo cp pgcalendar.control /usr/share/postgresql/15/extension/
sudo cp pgcalendar.sql /usr/share/postgresql/15/extension/pgcalendar--1.0.1.sql
sudo cp pgcalendar--uninstall.sql /usr/share/postgresql/15/extension/pgcalendar--1.0.1--uninstall.sql

# Create extension in your database
psql -d your_database -c "CREATE EXTENSION pgcalendar;"
```

### Method 4: Direct SQL Installation

```bash
# Run SQL file directly (simpler, but not using CREATE EXTENSION)
psql -d your_database -f pgcalendar.sql
```

### Verification

```sql
-- Check if extension is installed
SELECT * FROM pg_extension WHERE extname = 'pgcalendar';

-- Test basic functionality
SELECT * FROM pgcalendar.event_calendar LIMIT 5;
```

## Quick Start

```sql
-- 1. Create an event
INSERT INTO pgcalendar.events (name, description, category)
VALUES ('Daily Standup', 'Team daily standup meeting', 'meeting');

-- 2. Get the event_id
SELECT event_id FROM pgcalendar.events WHERE name = 'Daily Standup';

-- 3. Create a schedule (replace X with actual event_id)
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (
    X, '2024-01-01 09:00:00', '2024-01-07 23:59:59', 'daily', 1
);

-- 4. Get projections
SELECT * FROM pgcalendar.get_event_projections(X, '2024-01-01'::date, '2024-01-07'::date);
```

## Usage Examples

### Daily Schedule

```sql
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (
    1, '2024-01-01 09:00:00', '2024-01-07 23:59:59', 'daily', 1
);
```

### Weekly Schedule

```sql
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_day_of_week
) VALUES (
    1, '2024-01-01 10:00:00', '2024-12-31 23:59:59', 'weekly', 1, 1
);
-- recurrence_day_of_week: 0=Sunday, 1=Monday, etc.
```

### Monthly Schedule

```sql
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_day_of_month
) VALUES (
    1, '2024-01-01 10:00:00', '2024-12-31 23:59:59', 'monthly', 1, 15
);
-- recurrence_day_of_month: 1-31
```

### Yearly Schedule

```sql
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_month, recurrence_day_of_month
) VALUES (
    1, '2024-01-01 10:00:00', '2030-12-31 23:59:59', 'yearly', 1, 1, 1
);
-- recurrence_month: 1-12, recurrence_day_of_month: 1-31
```

### Adding Exceptions

```sql
-- Cancel a specific occurrence
INSERT INTO pgcalendar.exceptions (
    schedule_id, exception_date, exception_type, notes
) VALUES (
    1, '2024-01-15', 'cancelled', 'Holiday - meeting cancelled'
);

-- Modify time only
INSERT INTO pgcalendar.exceptions (
    schedule_id, exception_date, exception_type, modified_start_time, modified_end_time, notes
) VALUES (
    1, '2024-01-22', 'modified', '2024-01-22 11:00:00', '2024-01-22 12:00:00', 'Moved to 11 AM'
);

-- Modify date and time
INSERT INTO pgcalendar.exceptions (
    schedule_id, exception_date, exception_type, modified_date, modified_start_time, modified_end_time, notes
) VALUES (
    1, '2024-01-22', 'modified', '2024-01-23', '2024-01-23 14:00:00', '2024-01-23 15:00:00', 'Moved to next day'
);
```

### Multiple Schedule Configurations

```sql
-- First schedule: Daily for first week
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (1, '2024-01-01 09:00:00', '2024-01-07 23:59:59', 'daily', 1);

-- Second schedule: Every other day for second week (no overlap!)
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (1, '2024-01-08 09:00:00', '2024-01-14 23:59:59', 'daily', 2);
```

## Advanced Functions

### Schedule Transition

Safely transition to a new schedule configuration without overlaps:

```sql
SELECT pgcalendar.transition_event_schedule(
    p_event_id := 1,
    p_new_start_date := '2024-01-15 09:00:00',
    p_new_end_date := '2024-01-31 23:59:59',
    p_recurrence_type := 'weekly',
    p_recurrence_interval := 2,
    p_recurrence_day_of_week := 1,
    p_description := 'Changed to bi-weekly schedule'
);
```

### Overlap Checking

Check if a schedule would overlap with existing schedules:

```sql
SELECT pgcalendar.check_schedule_overlap(
    p_event_id := 1,
    p_start_date := '2024-01-05 09:00:00',
    p_end_date := '2024-01-10 23:59:59'
);
```

## Querying Projections

### Get Projections for an Event

```sql
SELECT * FROM pgcalendar.get_event_projections(
    p_event_id := 1,
    p_start_date := '2024-01-01'::date,
    p_end_date := '2024-01-31'::date
);
```

### Get All Events with Details

```sql
SELECT * FROM pgcalendar.get_events_detailed(
    p_start_date := '2024-01-01'::date,
    p_end_date := '2024-01-31'::date
);
```

### Use the Calendar View

```sql
SELECT * FROM pgcalendar.event_calendar;
```

## Schema Reference

### Tables

- `events` - Main event definitions
- `schedules` - Non-overlapping schedule configurations
- `exceptions` - Individual projection modifications

### Functions

- `get_event_projections(event_id, start_date, end_date)` - Get projections for specific event
- `get_events_detailed(start_date, end_date)` - Get all events with exception handling
- `transition_event_schedule(...)` - Safely change schedule configuration
- `check_schedule_overlap(event_id, start_date, end_date)` - Validate schedule timing

### Views

- `event_calendar` - Current year's calendar view

## Rules and Constraints

1. **Non-Overlapping Schedules**: Schedules for the same event cannot overlap in time (enforced by triggers)
2. **Schedule Hierarchy**: Event → Multiple Schedules → Multiple Projections
3. **Exception Handling**: Individual projection instances can be cancelled or modified
4. **Recurrence Patterns**: Daily, Weekly, Monthly, and Yearly with configurable intervals

## Testing

The project includes comprehensive Node.js/TypeScript tests using Jest.

### Setup

```bash
# Install dependencies
npm install

# Start test database (using Docker)
npm run test:db:start

# Or set environment variables
export PG_HOST=localhost
export PG_PORT=5433
export PG_USER=postgres
export PG_PASSWORD=postgres
export PG_DB=pgcalendar_test
```

### Running Tests

```bash
# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Type check
npm run type-check
```

### Test Database Setup

```bash
# Start PostgreSQL container
docker run -d --name pgcalendar-test \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=pgcalendar_test \
  -p 5433:5432 \
  postgres:15

# Install extension
docker exec -i pgcalendar-test psql -U postgres -d pgcalendar_test -f pgcalendar.sql

# Run tests
npm test

# Cleanup
docker stop pgcalendar-test && docker rm pgcalendar-test
```

## Uninstallation

```sql
DROP EXTENSION pgcalendar;
```

## Troubleshooting

### Extension Not Found

```bash
# Check if files are in the right location
ls -la /usr/share/postgresql/*/extension/pgcalendar*

# Verify PostgreSQL version
pg_config --version
```

### Permission Denied

```bash
# Fix permissions if needed
sudo chmod 644 /usr/share/postgresql/*/extension/pgcalendar*
```

### Schema Already Exists

```sql
DROP SCHEMA IF EXISTS pgcalendar CASCADE;
CREATE EXTENSION pgcalendar;
```

## License

This extension is licensed under the MIT License. See the LICENSE file for details.

## Support

- GitHub: https://github.com/h4kbas/pgcalendar
- Issues: https://github.com/h4kbas/pgcalendar/issues
