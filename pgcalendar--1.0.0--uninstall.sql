-- pgcalendar extension uninstall script
-- Version: 1.0.0

-- Drop the view first
DROP VIEW IF EXISTS pgcalendar.event_calendar;

-- Drop functions
DROP FUNCTION IF EXISTS pgcalendar.transition_event_schedule(INTEGER, TIMESTAMP, TIMESTAMP, recurrence_type, INTEGER, INTEGER, INTEGER, INTEGER, TEXT);
DROP FUNCTION IF EXISTS pgcalendar.check_schedule_overlap(INTEGER, TIMESTAMP, TIMESTAMP);
DROP FUNCTION IF EXISTS pgcalendar.get_events_detailed(DATE, DATE);
DROP FUNCTION IF EXISTS pgcalendar.get_event_projections(INTEGER, DATE, DATE);
DROP FUNCTION IF EXISTS pgcalendar.get_next_recurrence_date(RECORD, DATE);
DROP FUNCTION IF EXISTS pgcalendar.should_generate_projection(RECORD, DATE);
DROP FUNCTION IF EXISTS pgcalendar.generate_projections(INTEGER, DATE, DATE);
DROP FUNCTION IF EXISTS pgcalendar.prevent_schedule_overlap();
DROP FUNCTION IF EXISTS pgcalendar.update_updated_at_column();

-- Drop triggers
DROP TRIGGER IF EXISTS prevent_schedule_overlap_trigger ON pgcalendar.schedules;
DROP TRIGGER IF EXISTS update_schedules_updated_at ON pgcalendar.schedules;
DROP TRIGGER IF EXISTS update_events_updated_at ON pgcalendar.events;

-- Drop tables
DROP TABLE IF EXISTS pgcalendar.exceptions;
DROP TABLE IF EXISTS pgcalendar.schedules;
DROP TABLE IF EXISTS pgcalendar.events;

-- Drop types
DROP TYPE IF EXISTS pgcalendar.exception_type;
DROP TYPE IF EXISTS pgcalendar.recurrence_type;

-- Drop schema
DROP SCHEMA IF EXISTS pgcalendar CASCADE;
