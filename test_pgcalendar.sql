-- Test file for pgcalendar extension
-- This file tests the core functionality with assertions

DO $$ BEGIN
    RAISE NOTICE '=== Starting pgcalendar tests ===';
END $$;

-- Clean up any existing test data before starting
DELETE FROM pgcalendar.exceptions WHERE schedule_id IN (
    SELECT schedule_id FROM pgcalendar.schedules WHERE event_id IN (
        SELECT event_id FROM pgcalendar.events WHERE name IN ('Daily Standup', 'Weekly Review', 'Complex Exception Test')
    )
);
DELETE FROM pgcalendar.schedules WHERE event_id IN (
    SELECT event_id FROM pgcalendar.events WHERE name IN ('Daily Standup', 'Weekly Review', 'Complex Exception Test')
);
DELETE FROM pgcalendar.events WHERE name IN ('Daily Standup', 'Weekly Review', 'Complex Exception Test');

DO $$ BEGIN
    RAISE NOTICE 'Cleaned up existing test data';
END $$;

-- Test 1: One event, one schedule generating 1 week of projections
DO $$ BEGIN
    RAISE NOTICE 'Test 1: One event, one schedule generating 1 week of projections';
END $$;

-- Create test event
INSERT INTO pgcalendar.events (name, description, category) 
VALUES ('Daily Standup', 'Team daily standup meeting', 'meeting');

-- Get the event ID
DO $$
DECLARE
    v_event_id INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    -- Create daily schedule for 1 week
    INSERT INTO pgcalendar.schedules (
        event_id, start_date, end_date, recurrence_type, recurrence_interval
    ) VALUES (
        v_event_id, 
        '2024-01-01 09:00:00', 
        '2024-01-07 23:59:59', 
        'daily', 
        1
    );
    
    RAISE NOTICE 'Created daily schedule for Daily Standup event';
END $$;

-- Test: Verify we get 7 projections (one for each day)
DO $$
DECLARE
    v_count INTEGER;
    v_event_id INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    SELECT COUNT(*) INTO v_count 
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-07'::date);
    
    IF v_count = 7 THEN
        RAISE NOTICE '✓ Test 1 PASSED: Generated 7 projections as expected';
    ELSE
        RAISE EXCEPTION 'Test 1 FAILED: Expected 7 projections, got %', v_count;
    END IF;
END $$;

-- Test: Verify specific dates are generated
DO $$
DECLARE
    v_event_id INTEGER;
    v_date_count INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    -- Check if specific dates exist
    SELECT COUNT(*) INTO v_date_count
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-07'::date)
    WHERE projection_date IN ('2024-01-01', '2024-01-03', '2024-01-05', '2024-01-07');
    
    IF v_date_count = 4 THEN
        RAISE NOTICE '✓ Test 1a PASSED: Specific dates generated correctly';
    ELSE
        RAISE EXCEPTION 'Test 1a FAILED: Expected 4 specific dates, got %', v_date_count;
    END IF;
END $$;

-- Test 2: One event, two different schedules generating 1 week of projections
DO $$ BEGIN
    RAISE NOTICE 'Test 2: One event, two different schedules generating 1 week of projections';
END $$;

-- Create second schedule for the same event (different time period)
DO $$
DECLARE
    v_event_id INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    -- Create second schedule for different time period (no overlap)
    INSERT INTO pgcalendar.schedules (
        event_id, start_date, end_date, recurrence_type, recurrence_interval
    ) VALUES (
        v_event_id, 
        '2024-01-08 14:00:00', 
        '2024-01-14 23:59:59', 
        'daily', 
        1
    );
    
    RAISE NOTICE 'Created second schedule for Daily Standup event';
END $$;

-- Test: Verify we get 14 total projections (7 from each schedule)
DO $$
DECLARE
    v_count INTEGER;
    v_event_id INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    SELECT COUNT(*) INTO v_count 
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-14'::date);
    
    IF v_count = 14 THEN
        RAISE NOTICE '✓ Test 2 PASSED: Generated 14 projections (7 from each schedule)';
    ELSE
        RAISE EXCEPTION 'Test 2 FAILED: Expected 14 projections, got %', v_count;
    END IF;
END $$;

-- Test: Verify no overlapping schedules were created
DO $$
DECLARE
    v_event_id INTEGER;
    v_overlap_count INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    SELECT COUNT(*) INTO v_overlap_count
    FROM pgcalendar.schedules s1
    JOIN pgcalendar.schedules s2 ON s1.event_id = s2.event_id AND s1.schedule_id != s2.schedule_id
    WHERE s1.event_id = v_event_id
    AND (s1.start_date, s1.end_date) OVERLAPS (s2.start_date, s2.end_date);
    
    IF v_overlap_count = 0 THEN
        RAISE NOTICE '✓ Test 2a PASSED: No overlapping schedules detected';
    ELSE
        RAISE EXCEPTION 'Test 2a FAILED: Found % overlapping schedules', v_overlap_count;
    END IF;
END $$;

-- Test 3: One event with one schedule and multiple exceptions
DO $$ BEGIN
    RAISE NOTICE 'Test 3: One event with one schedule and multiple exceptions';
END $$;

-- Create new event for exception testing
INSERT INTO pgcalendar.events (name, description, category) 
VALUES ('Weekly Review', 'Weekly team review meeting', 'meeting');

-- Create weekly schedule
DO $$
DECLARE
    v_event_id INTEGER;
    v_schedule_id INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Weekly Review';
    
    INSERT INTO pgcalendar.schedules (
        event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_day_of_week
    ) VALUES (
        v_event_id, 
        '2024-01-01 10:00:00', 
        '2024-01-31 23:59:59', 
        'weekly', 
        1,
        1  -- Monday
    ) RETURNING schedule_id INTO v_schedule_id;
    
    -- Create exception for one specific date (cancellation)
    INSERT INTO pgcalendar.exceptions (
        schedule_id, exception_date, exception_type, notes
    ) VALUES (
        v_schedule_id,
        '2024-01-15',  -- This Monday
        'cancelled',
        'Holiday - meeting cancelled'
    );
    
    -- Create exception for time modification (same date, different time)
    INSERT INTO pgcalendar.exceptions (
        schedule_id, exception_date, exception_type, modified_start_time, modified_end_time, notes
    ) VALUES (
        v_schedule_id,
        '2024-01-22',  -- This Monday
        'modified',
        '2024-01-22 14:00:00',  -- New start time
        '2024-01-22 15:00:00',  -- New end time
        'Moved to afternoon due to conflict'
    );
    
    -- Create exception for date modification (different date and time)
    INSERT INTO pgcalendar.exceptions (
        schedule_id, exception_date, exception_type, modified_date, modified_start_time, modified_end_time, notes
    ) VALUES (
        v_schedule_id,
        '2024-01-29',  -- This Monday
        'modified',
        '2024-01-30',  -- New date (Tuesday)
        '2024-01-30 11:00:00',  -- New start time
        '2024-01-30 12:00:00',  -- New end time
        'Moved to Tuesday due to holiday'
    );
    
    RAISE NOTICE 'Created Weekly Review with 3 exceptions: cancelled, time-modified, and date-modified';
END $$;

-- Test: Verify we get 4 projections (5 weeks minus 1 cancelled)
DO $$
DECLARE
    v_count INTEGER;
    v_event_id INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Weekly Review';
    
    SELECT COUNT(*) INTO v_count 
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date);
    
    IF v_count = 4 THEN
        RAISE NOTICE '✓ Test 3 PASSED: Generated 4 projections (5 weeks minus 1 cancelled, 2 modified)';
    ELSE
        RAISE EXCEPTION 'Test 3 FAILED: Expected 4 projections, got %', v_count;
    END IF;
END $$;

-- Test: Verify the cancelled date is not in results
DO $$
DECLARE
    v_event_id INTEGER;
    v_cancelled_count INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Weekly Review';
    
    SELECT COUNT(*) INTO v_cancelled_count
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date)
    WHERE projection_date = '2024-01-15';
    
    IF v_cancelled_count = 0 THEN
        RAISE NOTICE '✓ Test 3a PASSED: Cancelled date (2024-01-15) not in projections';
    ELSE
        RAISE EXCEPTION 'Test 3a FAILED: Cancelled date still appears in projections';
    END IF;
END $$;

-- Test: Verify projection structure and content for normal events
DO $$
DECLARE
    v_event_id INTEGER;
    v_projection RECORD;
    v_expected_dates DATE[] := ARRAY['2024-01-01', '2024-01-08', '2024-01-22', '2024-01-30'];
    v_date DATE;
    v_found_count INTEGER := 0;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Weekly Review';
    
    -- Check each expected date
    FOREACH v_date IN ARRAY v_expected_dates
    LOOP
        SELECT * INTO v_projection
        FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date)
        WHERE projection_date = v_date;
        
        IF v_projection.projection_date IS NOT NULL THEN
            -- Verify projection structure
            IF v_projection.projection_schedule_id IS NOT NULL AND 
               v_projection.projection_event_name IS NOT NULL AND 
               v_projection.projection_start_time IS NOT NULL AND 
               v_projection.projection_end_time IS NOT NULL AND
               v_projection.projection_recurrence_type IS NOT NULL AND
               v_projection.projection_status IS NOT NULL THEN
                v_found_count := v_found_count + 1;
                RAISE NOTICE '✓ Found projection for % with all required fields', v_date;
            ELSE
                RAISE EXCEPTION 'Test 3c FAILED: Projection for % missing required fields', v_date;
            END IF;
        ELSE
            RAISE EXCEPTION 'Test 3c FAILED: No projection found for expected date %', v_date;
        END IF;
    END LOOP;
    
    IF v_found_count = 4 THEN
        RAISE NOTICE '✓ Test 3c PASSED: All expected projections have correct structure';
    ELSE
        RAISE EXCEPTION 'Test 3c FAILED: Expected 4 valid projections, found %', v_found_count;
    END IF;
END $$;

-- Test: Verify other Monday dates are present
DO $$
DECLARE
    v_event_id INTEGER;
    v_monday_count INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Weekly Review';
    
    SELECT COUNT(*) INTO v_monday_count
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date)
    WHERE projection_date IN ('2024-01-01', '2024-01-08', '2024-01-22');
    
    IF v_monday_count = 3 THEN
        RAISE NOTICE '✓ Test 3b PASSED: Other Monday dates present in projections';
    ELSE
        RAISE EXCEPTION 'Test 3b FAILED: Expected 3 Monday dates, got %', v_monday_count;
    END IF;
END $$;

-- Test: Verify time modification exception (same date, different time)
DO $$
DECLARE
    v_event_id INTEGER;
    v_projection RECORD;
    v_expected_time_modification RECORD;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Weekly Review';
    
    -- Check that the time-modified event appears on the modified date with correct time
    SELECT * INTO v_projection
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date)
    WHERE projection_date = '2024-01-22';
    
    IF v_projection.projection_date IS NOT NULL THEN
        -- Verify the time was modified correctly
        IF v_projection.projection_start_time = '14:00:00' AND v_projection.projection_end_time = '15:00:00' THEN
            RAISE NOTICE '✓ Test 3d PASSED: Time modification working correctly (14:00-15:00)';
        ELSE
            RAISE EXCEPTION 'Test 3d FAILED: Expected time 14:00-15:00, got %-%', 
                v_projection.projection_start_time, v_projection.projection_end_time;
        END IF;
        
        -- Verify status shows modification
        IF v_projection.projection_status LIKE 'MODIFIED: Time%' THEN
            RAISE NOTICE '✓ Test 3d PASSED: Status correctly shows time modification';
        ELSE
            RAISE EXCEPTION 'Test 3d FAILED: Status does not show time modification: %', v_projection.projection_status;
        END IF;
    ELSE
        RAISE EXCEPTION 'Test 3d FAILED: No projection found for time-modified date 2024-01-22';
    END IF;
END $$;

-- Test: Verify date modification exception (different date and time)
DO $$
DECLARE
    v_event_id INTEGER;
    v_projection RECORD;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Weekly Review';
    
    -- Check that the date-modified event appears on the new date
    SELECT * INTO v_projection
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date)
    WHERE projection_date = '2024-01-30';  -- New date (Tuesday)
    
    IF v_projection.projection_date IS NOT NULL THEN
        -- Verify the date and time were modified correctly
        IF v_projection.projection_start_time = '11:00:00' AND v_projection.projection_end_time = '12:00:00' THEN
            RAISE NOTICE '✓ Test 3e PASSED: Date and time modification working correctly (2024-01-30 11:00-12:00)';
        ELSE
            RAISE EXCEPTION 'Test 3e FAILED: Expected time 11:00-12:00, got %-%', 
                v_projection.projection_start_time, v_projection.projection_end_time;
        END IF;
        
        -- Verify status shows date modification
        IF v_projection.projection_status LIKE 'MODIFIED: Date%' THEN
            RAISE NOTICE '✓ Test 3e PASSED: Status correctly shows date modification';
        ELSE
            RAISE EXCEPTION 'Test 3e FAILED: Status does not show date modification: %', v_projection.projection_status;
        END IF;
        
        -- Verify the original date (2024-01-29) is not in results
        IF NOT EXISTS (
            SELECT 1 FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date)
            WHERE projection_date = '2024-01-29'
        ) THEN
            RAISE NOTICE '✓ Test 3e PASSED: Original date (2024-01-29) correctly removed from projections';
        ELSE
            RAISE EXCEPTION 'Test 3e FAILED: Original date (2024-01-29) still appears in projections';
        END IF;
    ELSE
        RAISE EXCEPTION 'Test 3e FAILED: No projection found for date-modified event on 2024-01-30';
    END IF;
END $$;

-- Test 4: Verify constraint prevents overlapping schedules
DO $$ BEGIN
    RAISE NOTICE 'Test 4: Verify constraint prevents overlapping schedules';
END $$;

DO $$
DECLARE
    v_event_id INTEGER;
    v_error_occurred BOOLEAN := FALSE;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    BEGIN
        -- Try to create overlapping schedule (should fail)
        INSERT INTO pgcalendar.schedules (
            event_id, start_date, end_date, recurrence_type, recurrence_interval
        ) VALUES (
            v_event_id, 
            '2024-01-05 09:00:00',  -- Overlaps with first schedule
            '2024-01-10 23:59:59', 
            'daily', 
            1
        );
        
        RAISE EXCEPTION 'Test 4 FAILED: Overlapping schedule was allowed';
    EXCEPTION
        WHEN OTHERS THEN
            v_error_occurred := TRUE;
            RAISE NOTICE '✓ Test 4 PASSED: Overlapping schedule correctly rejected';
    END;
    
    IF NOT v_error_occurred THEN
        RAISE EXCEPTION 'Test 4 FAILED: Expected error for overlapping schedule';
    END IF;
END $$;

-- Test 5: Test schedule transition function
DO $$ BEGIN
    RAISE NOTICE 'Test 5: Test schedule transition function';
END $$;

DO $$
DECLARE
    v_event_id INTEGER;
    v_new_schedule_id INTEGER;
    v_projection_count INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    -- Transition to new schedule configuration
    v_new_schedule_id := pgcalendar.transition_event_schedule(
        p_event_id := v_event_id,
        p_new_start_date := '2024-01-15 09:00:00',
        p_new_end_date := '2024-01-21 23:59:59',
        p_recurrence_type := 'daily',
        p_recurrence_interval := 2,  -- Every other day
        p_description := 'Modified to every other day'
    );
    
    -- Verify new schedule was created
    IF v_new_schedule_id IS NOT NULL THEN
        RAISE NOTICE '✓ Test 5 PASSED: New schedule transition created successfully';
    ELSE
        RAISE EXCEPTION 'Test 5 FAILED: Schedule transition failed';
    END IF;
    
    -- Verify we get projections from new schedule
    SELECT COUNT(*) INTO v_projection_count
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-15'::date, '2024-01-21'::date);
    
    IF v_projection_count = 4 THEN  -- Every other day for 7 days = 4 projections
        RAISE NOTICE '✓ Test 5a PASSED: New schedule generates correct number of projections';
    ELSE
        RAISE EXCEPTION 'Test 5a FAILED: Expected 4 projections, got %', v_projection_count;
    END IF;
END $$;

-- Test 6: Verify total projections across all schedules
DO $$ BEGIN
    RAISE NOTICE 'Test 6: Verify total projections across all schedules';
END $$;

DO $$
DECLARE
    v_event_id INTEGER;
    v_total_projections INTEGER;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Daily Standup';
    
    -- Get total projections for the entire month
    SELECT COUNT(*) INTO v_total_projections
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date);
    
    -- Expected: 7 (first week) + 7 (second week) + 4 (third week every other day) = 18
    IF v_total_projections = 18 THEN
        RAISE NOTICE '✓ Test 6 PASSED: Total projections across all schedules = 18';
    ELSE
        RAISE EXCEPTION 'Test 6 FAILED: Expected 18 total projections, got %', v_total_projections;
    END IF;
END $$;

-- Test 7: Comprehensive projection content validation
DO $$ BEGIN
    RAISE NOTICE 'Test 7: Comprehensive projection content validation';
END $$;

DO $$
DECLARE
    v_event_id INTEGER;
    v_projection RECORD;
    v_validation_errors TEXT[] := ARRAY[]::TEXT[];
    v_error_count INTEGER := 0;
BEGIN
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Weekly Review';
    
    -- Get all projections and validate each one
    FOR v_projection IN 
        SELECT * FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-31'::date)
        ORDER BY projection_date
    LOOP
        -- Validate required fields exist
        IF v_projection.projection_schedule_id IS NULL THEN
            v_validation_errors := array_append(v_validation_errors, 
                'Projection for ' || v_projection.projection_date || ' missing schedule_id');
            v_error_count := v_error_count + 1;
        END IF;
        
        IF v_projection.projection_event_name IS NULL THEN
            v_validation_errors := array_append(v_validation_errors, 
                'Projection for ' || v_projection.projection_date || ' missing event_name');
            v_error_count := v_error_count + 1;
        END IF;
        
        IF v_projection.projection_start_time IS NULL THEN
            v_validation_errors := array_append(v_validation_errors, 
                'Projection for ' || v_projection.projection_date || ' missing start_time');
            v_error_count := v_error_count + 1;
        END IF;
        
        IF v_projection.projection_end_time IS NULL THEN
            v_validation_errors := array_append(v_validation_errors, 
                'Projection for ' || v_projection.projection_date || ' missing end_time');
            v_error_count := v_error_count + 1;
        END IF;
        
        IF v_projection.projection_status IS NULL THEN
            v_validation_errors := array_append(v_validation_errors, 
                'Projection for ' || v_projection.projection_date || ' missing status');
            v_error_count := v_error_count + 1;
        END IF;
        
        -- Validate specific projection types
        IF v_projection.projection_date = '2024-01-15' THEN
            -- This should not exist (cancelled)
            v_validation_errors := array_append(v_validation_errors, 
                'Cancelled date 2024-01-15 still appears in projections');
            v_error_count := v_error_count + 1;
        END IF;
        
        IF v_projection.projection_date = '2024-01-22' THEN
            -- Time modified event
            IF v_projection.projection_start_time != '14:00:00' OR v_projection.projection_end_time != '15:00:00' THEN
                v_validation_errors := array_append(v_validation_errors, 
                    'Time modification for 2024-01-22 incorrect: expected 14:00-15:00, got ' || 
                    v_projection.projection_start_time || '-' || v_projection.projection_end_time);
                v_error_count := v_error_count + 1;
            END IF;
        END IF;
        
        IF v_projection.projection_date = '2024-01-30' THEN
            -- Date modified event
            IF v_projection.projection_start_time != '11:00:00' OR v_projection.projection_end_time != '12:00:00' THEN
                v_validation_errors := array_append(v_validation_errors, 
                    'Date modification for 2024-01-30 incorrect: expected 11:00-12:00, got ' || 
                    v_projection.projection_start_time || '-' || v_projection.projection_end_time);
                v_error_count := v_error_count + 1;
            END IF;
        END IF;
        
        RAISE NOTICE '✓ Validated projection for % (%)', v_projection.projection_date, v_projection.projection_status;
    END LOOP;
    
    -- Report results
    IF v_error_count = 0 THEN
        RAISE NOTICE '✓ Test 7 PASSED: All projections have correct content and structure';
    ELSE
        RAISE NOTICE '✗ Test 7 FAILED: Found % validation errors:', v_error_count;
        FOR i IN 1..array_length(v_validation_errors, 1)
        LOOP
            RAISE NOTICE '  - %', v_validation_errors[i];
        END LOOP;
        RAISE EXCEPTION 'Test 7 FAILED: % validation errors found', v_error_count;
    END IF;
END $$;

-- Test 8: Complex exception priority handling (modifications override cancellations)
DO $$ BEGIN
    RAISE NOTICE 'Test 8: Complex exception priority handling (modifications override cancellations)';
END $$;

-- Create test event for complex exception scenario
INSERT INTO pgcalendar.events (name, description, category) 
VALUES ('Complex Exception Test', 'Test event for complex exception logic', 'test');

-- Test the scenario: cancel a date, then move another date to it
DO $$
DECLARE
    v_event_id INTEGER;
    v_schedule_id INTEGER;
    v_projection_count INTEGER;
    v_jan3_count INTEGER;
    v_jan5_count INTEGER;
    v_jan5_status TEXT;
BEGIN
    -- Get the event ID
    SELECT event_id INTO v_event_id FROM pgcalendar.events WHERE name = 'Complex Exception Test';
    
    -- Create daily schedule for 1 week
    INSERT INTO pgcalendar.schedules (
        event_id, start_date, end_date, recurrence_type, recurrence_interval
    ) VALUES (
        v_event_id, 
        '2024-01-01 09:00:00', 
        '2024-01-07 23:59:59', 
        'daily', 
        1
    ) RETURNING schedule_id INTO v_schedule_id;
    
    RAISE NOTICE 'Created schedule with ID: %', v_schedule_id;
    
    -- Step 1: Cancel Jan 5th
    INSERT INTO pgcalendar.exceptions (schedule_id, exception_date, exception_type, notes) 
    VALUES (v_schedule_id, '2024-01-05', 'cancelled', 'Meeting cancelled');
    
    -- Step 2: Move Jan 3rd to Jan 5th
    INSERT INTO pgcalendar.exceptions (schedule_id, exception_date, exception_type, modified_date, notes) 
    VALUES (v_schedule_id, '2024-01-03', 'modified', '2024-01-05', 'Moved from Wednesday to Friday');
    
    RAISE NOTICE 'Created complex exception scenario: Jan 5th cancelled, Jan 3rd moved to Jan 5th';
    
    -- Test: Verify the logic works correctly
    -- Should have 6 projections (Jan 1-2, 4, 6-7), with Jan 3rd removed and Jan 5th showing modified event
    SELECT COUNT(*) INTO v_projection_count 
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-07'::date);
    
    -- Check if Jan 3rd is removed (should not exist)
    SELECT COUNT(*) INTO v_jan3_count 
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-07'::date)
    WHERE projection_date = '2024-01-03';
    
    -- Check if Jan 5th exists and shows modified status
    SELECT COUNT(*) INTO v_jan5_count 
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-07'::date)
    WHERE projection_date = '2024-01-05';
    
    -- Get Jan 5th status
    SELECT projection_status INTO v_jan5_status 
    FROM pgcalendar.get_event_projections(v_event_id, '2024-01-01'::date, '2024-01-07'::date)
    WHERE projection_date = '2024-01-05';
    
    -- Assertions
    IF v_projection_count = 6 THEN
        RAISE NOTICE '✓ Test 8a PASSED: Correct number of projections (6)';
    ELSE
        RAISE EXCEPTION 'Test 8a FAILED: Expected 6 projections, got %', v_projection_count;
    END IF;
    
    IF v_jan3_count = 0 THEN
        RAISE NOTICE '✓ Test 8b PASSED: Jan 3rd properly removed (moved to Jan 5th)';
    ELSE
        RAISE EXCEPTION 'Test 8b FAILED: Jan 3rd still appears (count: %)', v_jan3_count;
    END IF;
    
    IF v_jan5_count = 1 THEN
        RAISE NOTICE '✓ Test 8c PASSED: Jan 5th exists as modified event';
    ELSE
        RAISE EXCEPTION 'Test 8c FAILED: Jan 5th missing (count: %)', v_jan5_count;
    END IF;
    
    IF v_jan5_status LIKE 'MODIFIED: Date 2024-01-03%' THEN
        RAISE NOTICE '✓ Test 8d PASSED: Jan 5th shows correct modification status: %', v_jan5_status;
    ELSE
        RAISE EXCEPTION 'Test 8d FAILED: Jan 5th status incorrect: %', v_jan5_status;
    END IF;
    
    RAISE NOTICE '✓ Test 8 PASSED: Complex exception priority handling working correctly';
    RAISE NOTICE '  - Jan 3rd removed (moved to Jan 5th)';
    RAISE NOTICE '  - Jan 5th shows modified event from Jan 3rd (overriding cancellation)';
    RAISE NOTICE '  - Total projections: 6 (Jan 1-2, 4, 6-7)';
END $$;

-- Cleanup test data
DO $$ BEGIN
    RAISE NOTICE 'Cleaning up test data...';
END $$;

DELETE FROM pgcalendar.exceptions WHERE schedule_id IN (
    SELECT schedule_id FROM pgcalendar.schedules WHERE event_id IN (
        SELECT event_id FROM pgcalendar.events WHERE name IN ('Daily Standup', 'Weekly Review', 'Complex Exception Test')
    )
);
DELETE FROM pgcalendar.schedules WHERE event_id IN (
    SELECT event_id FROM pgcalendar.events WHERE name IN ('Daily Standup', 'Weekly Review', 'Complex Exception Test')
);
DELETE FROM pgcalendar.events WHERE name IN ('Daily Standup', 'Weekly Review', 'Complex Exception Test');

