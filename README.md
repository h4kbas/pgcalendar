# pgcalendar - Infinite Calendar Extension for PostgreSQL

A powerful PostgreSQL extension for managing recurring events with infinite projections, multiple schedule configurations, and exception handling.

## Overview

pgcalendar provides a robust system for managing recurring events where:

- **Events** represent logical entities (meetings, tasks, etc.)
- **Schedules** define non-overlapping time configurations that generate projections
- **Exceptions** modify individual instances (cancellations, modifications)
- **Projections** are the actual calendar occurrences generated from schedules

## Key Concepts

### 1. Events

- Main logical entities (e.g., "Daily Standup", "Weekly Review")
- Contain metadata like name, description, category, priority
- Can have multiple schedule configurations over time for variations

### 2. Schedules

- Define when and how often an event occurs
- **Overlap Prevention**: Schedules for the same event cannot overlap in time (enforced by triggers)
- Generate projections (calendar occurrences) based on recurrence rules
- Support daily, weekly, monthly, and yearly patterns

### 3. Exceptions

- Modify/Cancel single instances of projections
- Types: `cancelled` (remove from calendar) or `modified` (change time/details)

### 4. Projections

- Actual calendar entries generated from schedules
- Automatically calculated based on recurrence rules
- Can be filtered, modified, or cancelled via exceptions

## Installation

1. Run the SQL file to create the extension:

```sql
\i pgcalendar.sql
```

2. Verify installation:

```sql
SELECT * FROM pgcalendar.event_calendar LIMIT 5;
```

## Basic Usage Examples

### Complete Workflow Example (Recommended)

```sql
-- Step 1: Create an event
INSERT INTO pgcalendar.events (name, description, category)
VALUES ('Daily Standup', 'Team daily standup meeting', 'meeting');

-- Step 2: Get the event_id (copy this value)
SELECT event_id FROM pgcalendar.events WHERE name = 'Daily Standup';

-- Step 3: Create a schedule using the event_id from step 2
-- Example: If event_id = 3, then use:
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (
    3,  -- Use the actual event_id from step 2
    '2024-01-01 09:00:00',
    '2024-01-07 23:59:59',
    'daily',
    1
);

-- Step 4: Get projections using the same event_id
SELECT * FROM pgcalendar.get_event_projections(3, '2024-01-01'::date, '2024-01-07'::date);
```

### Creating a Simple Event with Daily Schedule

```sql
-- Create an event
INSERT INTO pgcalendar.events (name, description, category)
VALUES ('Daily Standup', 'Team daily standup meeting', 'meeting');

-- Get the event ID (use this in subsequent commands)
SELECT event_id FROM pgcalendar.events WHERE name = 'Daily Standup';

-- Create a daily schedule (every day for 1 week)
-- Replace X with the actual event_id from the query above
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (
    X,  -- Replace X with actual event_id from above
    '2024-01-01 09:00:00',
    '2024-01-07 23:59:59',
    'daily',
    1
);

-- Get projections for the week (use the same event_id)
SELECT * FROM pgcalendar.get_event_projections(X, '2024-01-01'::date, '2024-01-07'::date);
```

### Creating Weekly Events

```sql
-- Create weekly meeting (every Monday)
-- Replace X with the actual event_id from your event
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_day_of_week
) VALUES (
    X,  -- Replace X with actual event_id
    '2024-01-01 10:00:00',
    '2024-12-31 23:59:59',
    'weekly',
    1,      -- every week
    1       -- Monday (0=Sunday, 1=Monday, etc.)
);
```

### Adding Exceptions

```sql
-- First, get the schedule_id for your event
-- Replace X with the actual event_id from your event
SELECT schedule_id FROM pgcalendar.schedules WHERE event_id = X;

-- Cancel a specific occurrence
-- Replace Y with the actual schedule_id from above
INSERT INTO pgcalendar.exceptions (
    schedule_id, exception_date, exception_type, notes
) VALUES (
    Y,  -- Replace Y with actual schedule_id from above
    '2024-01-15',  -- specific date
    'cancelled',    -- type
    'Holiday - meeting cancelled'
);

-- Modify a specific occurrence (time only)
-- Replace Y with the actual schedule_id from above
INSERT INTO pgcalendar.exceptions (
    schedule_id, exception_date, exception_type, modified_start_time, modified_end_time, notes
) VALUES (
    Y,  -- Replace Y with actual schedule_id from above
    '2024-01-22',  -- specific date
    'modified',     -- type
    '2024-01-22 11:00:00',  -- new start time
    '2024-01-22 12:00:00',  -- new end time
    'Moved to 11 AM due to conflict'
);

-- Modify a specific occurrence (date and time)
-- Replace Y with the actual schedule_id from above
INSERT INTO pgcalendar.exceptions (
    schedule_id, exception_date, exception_type, modified_date, modified_start_time, modified_end_time, notes
) VALUES (
    Y,  -- Replace Y with actual schedule_id from above
    '2024-01-22',  -- original date
    'modified',     -- type
    '2024-01-23',  -- new date
    '2024-01-23 14:00:00',  -- new start time
    '2024-01-23 15:00:00',  -- new end time
    'Moved to next day due to conflict'
);

-- Note: Date modifications will:
-- 1. Remove the event from the original date
-- 2. Create a new projection on the modified date
-- 3. Show status as "MODIFIED: Date 2024-01-22 → 2024-01-23 Time 14:00-15:00"
```

### Multiple Schedule Configurations

```sql
-- First schedule: Daily for first week
-- Replace X with the actual event_id from your event
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (X, '2024-01-01 09:00:00', '2024-01-07 23:59:59', 'daily', 1);

-- Second schedule: Every other day for second week (no overlap!)
-- Replace X with the actual event_id from your event
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (X, '2024-01-08 09:00:00', '2024-01-14 23:59:59', 'daily', 2);

-- Get all projections across both schedules
-- Replace X with the actual event_id from your event
SELECT * FROM pgcalendar.get_event_projections(X, '2024-01-01'::date, '2024-01-14'::date);
```

## Advanced Functions

### Schedule Transition

```sql
-- Safely transition to new schedule configuration
-- Replace X with the actual event_id from your event
SELECT pgcalendar.transition_event_schedule(
    p_event_id := X,
    p_new_start_date := '2024-01-15 09:00:00',
    p_new_end_date := '2024-01-31 23:59:59',
    p_recurrence_type := 'weekly',
    p_recurrence_interval := 2,  -- every 2 weeks
    p_recurrence_day_of_week := 1,  -- Monday
    p_description := 'Changed to bi-weekly schedule'
);
```

### Overlap Checking

```sql
-- Check if a schedule would overlap
-- Replace X with the actual event_id from your event
SELECT pgcalendar.check_schedule_overlap(
    p_event_id := X,
    p_start_date := '2024-01-05 09:00:00',
    p_end_date := '2024-01-10 23:59:59'
);
```

## Rules and Constraints

### 1. Non-Overlapping Schedules

- **Rule**: Schedules for the same event cannot overlap in time
- **Enforcement**: Trigger functions (not database constraints)
- **Benefit**: Prevents conflicts and ensures clean projections

### 2. Schedule Hierarchy

- **Event** → **Multiple Schedules** → **Multiple Projections**
- Each schedule generates projections for its time period
- Total projections = sum of all schedule projections

### 3. Exception Handling

- **Scope**: Individual projection instances only
- **Types**: Cancellations (remove) or modifications (change)
- **Persistence**: Exceptions are stored and applied to all queries

### 4. Recurrence Patterns

- **Daily**: Every N days from start date
- **Weekly**: Every N weeks on specified day(s)
- **Monthly**: Every N months on specified day of month
- **Yearly**: Every N years on specified month/day

## Querying Projections

### Get All Projections for an Event

```sql
-- Get projections for specific date range
SELECT * FROM pgcalendar.get_event_projections(
    p_event_id := 1,
    p_start_date := '2024-01-01'::date,
    p_end_date := '2024-01-31'::date
);
```

### Get Detailed Events with Exceptions

```sql
-- Get all events with exception handling
SELECT * FROM pgcalendar.get_events_detailed(
    p_start_date := '2024-01-01'::date,
    p_end_date := '2024-01-31'::date
);
```

## Schema Reference

### Tables

- `events`: Main event definitions
- `schedules`: Non-overlapping schedule configurations
- `exceptions`: Individual projection modifications

### Key Functions

- `get_event_projections()`: Get projections for specific event
- `get_events_detailed()`: Get all events with exception handling
- `transition_event_schedule()`: Safely change schedule configuration
- `check_schedule_overlap()`: Validate schedule timing

### Views

- `event_calendar`: Current year's calendar view

## License

This extension is licensed under the MIT License. See the LICENSE file for details.
