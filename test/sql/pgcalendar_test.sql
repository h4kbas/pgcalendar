-- Test file for pgcalendar extension
-- This file tests the basic functionality of the extension

-- Test 1: Check if extension can be created
SELECT 1;

-- Test 2: Verify schema exists
SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'pgcalendar';

-- Test 3: Verify tables exist
SELECT table_name FROM information_schema.tables WHERE table_schema = 'pgcalendar' ORDER BY table_name;

-- Test 4: Verify types exist
SELECT typname FROM pg_type WHERE typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pgcalendar') ORDER BY typname;

-- Test 5: Verify functions exist
SELECT proname FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pgcalendar') ORDER BY proname;

-- Test 6: Verify view exists
SELECT viewname FROM pg_views WHERE schemaname = 'pgcalendar';

-- Test 7: Basic event creation
INSERT INTO pgcalendar.events (name, description, category) 
VALUES ('Test Event', 'A test event for testing', 'test') RETURNING event_id;

-- Test 8: Basic schedule creation
INSERT INTO pgcalendar.schedules (
    event_id, start_date, end_date, recurrence_type, recurrence_interval
) VALUES (
    (SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'),
    '2024-01-01 09:00:00',
    '2024-01-07 23:59:59',
    'daily',
    1
) RETURNING schedule_id;

-- Test 9: Test projection generation
SELECT * FROM pgcalendar.get_event_projections(
    (SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'),
    '2024-01-01'::date,
    '2024-01-07'::date
);

-- Test 10: Test exception creation
INSERT INTO pgcalendar.exceptions (
    schedule_id, exception_date, exception_type, notes
) VALUES (
    (SELECT schedule_id FROM pgcalendar.schedules WHERE event_id = (SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event')),
    '2024-01-03',
    'cancelled',
    'Test cancellation'
);

-- Test 11: Test modified projection with exception
SELECT * FROM pgcalendar.get_event_projections(
    (SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'),
    '2024-01-01'::date,
    '2024-01-07'::date
);

-- Test 12: Test overlap prevention
DO $$
BEGIN
    -- This should fail due to overlap
    INSERT INTO pgcalendar.schedules (
        event_id, start_date, end_date, recurrence_type, recurrence_interval
    ) VALUES (
        (SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'),
        '2024-01-05 09:00:00',
        '2024-01-10 23:59:59',
        'daily',
        1
    );
    RAISE EXCEPTION 'Overlap prevention failed';
EXCEPTION
    WHEN OTHERS THEN
        -- Expected to fail
        NULL;
END $$;

-- Test 13: Test schedule transition
SELECT pgcalendar.transition_event_schedule(
    p_event_id := (SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'),
    p_new_start_date := '2024-01-15 09:00:00',
    p_new_end_date := '2024-01-31 23:59:59',
    p_recurrence_type := 'weekly',
    p_recurrence_interval := 1,
    p_recurrence_day_of_week := 1,
    p_description := 'Transitioned to weekly schedule'
);

-- Test 14: Test detailed events view
SELECT * FROM pgcalendar.get_events_detailed(
    '2024-01-01'::date,
    '2024-01-31'::date
);

-- Test 15: Test calendar view
SELECT * FROM pgcalendar.event_calendar LIMIT 5;

-- Cleanup test data
DELETE FROM pgcalendar.exceptions WHERE schedule_id IN (
    SELECT schedule_id FROM pgcalendar.schedules WHERE event_id IN (
        SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'
    )
);
DELETE FROM pgcalendar.schedules WHERE event_id IN (
    SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'
);
DELETE FROM pgcalendar.events WHERE name = 'Test Event';

-- Test 16: Verify cleanup
SELECT COUNT(*) as remaining_events FROM pgcalendar.events WHERE name = 'Test Event';
SELECT COUNT(*) as remaining_schedules FROM pgcalendar.schedules WHERE event_id IN (
    SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'
);
SELECT COUNT(*) as remaining_exceptions FROM pgcalendar.exceptions WHERE schedule_id IN (
    SELECT schedule_id FROM pgcalendar.schedules WHERE event_id IN (
        SELECT event_id FROM pgcalendar.events WHERE name = 'Test Event'
    )
);
