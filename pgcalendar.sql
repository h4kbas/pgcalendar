
CREATE SCHEMA IF NOT EXISTS pgcalendar;

SET search_path TO pgcalendar, public;

DO $$ BEGIN
    CREATE TYPE recurrence_type AS ENUM ('daily', 'weekly', 'monthly', 'yearly');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE exception_type AS ENUM ('cancelled', 'modified');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS events (
    event_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    priority INTEGER DEFAULT 1,
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);


CREATE TABLE IF NOT EXISTS schedules (
    schedule_id SERIAL PRIMARY KEY,
    event_id INTEGER REFERENCES events(event_id) ON DELETE CASCADE,
    description TEXT,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP NOT NULL,
    recurrence_type recurrence_type NOT NULL,
    recurrence_interval INTEGER DEFAULT 1,
    recurrence_day_of_week INTEGER, -- 0=Sunday, 1=Monday, etc.
    recurrence_day_of_month INTEGER, -- 1-31
    recurrence_month INTEGER, -- 1-12
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT valid_recurrence_interval CHECK (recurrence_interval > 0),
    CONSTRAINT valid_day_of_week CHECK (recurrence_day_of_week IS NULL OR (recurrence_day_of_week >= 0 AND recurrence_day_of_week <= 6)),
    CONSTRAINT valid_day_of_month CHECK (recurrence_day_of_month IS NULL OR (recurrence_day_of_month >= 1 AND recurrence_day_of_month <= 31)),
        CONSTRAINT valid_month CHECK (recurrence_month IS NULL OR (recurrence_month >= 1 AND recurrence_month <= 12))
  );

CREATE TABLE IF NOT EXISTS exceptions (
    exception_id SERIAL PRIMARY KEY,
    schedule_id INTEGER REFERENCES schedules(schedule_id) ON DELETE CASCADE,
    exception_date DATE NOT NULL,
    exception_type exception_type NOT NULL,
    modified_date DATE,
    modified_start_time TIMESTAMP,
    modified_end_time TIMESTAMP,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(schedule_id, exception_date)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_events_category ON events(category);
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
CREATE INDEX IF NOT EXISTS idx_events_priority ON events(priority);

CREATE INDEX IF NOT EXISTS idx_schedules_event_id ON schedules(event_id);
CREATE INDEX IF NOT EXISTS idx_schedules_recurrence_type ON schedules(recurrence_type);
CREATE INDEX IF NOT EXISTS idx_schedules_start_date ON schedules(start_date);
CREATE INDEX IF NOT EXISTS idx_schedules_end_date ON schedules(end_date);

CREATE INDEX IF NOT EXISTS idx_exceptions_schedule_id ON exceptions(schedule_id);
CREATE INDEX IF NOT EXISTS idx_exceptions_date ON exceptions(exception_date);
CREATE INDEX IF NOT EXISTS idx_exceptions_type ON exceptions(exception_type);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION pgcalendar.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
DROP TRIGGER IF EXISTS update_events_updated_at ON events;
CREATE TRIGGER update_events_updated_at
    BEFORE UPDATE ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_schedules_updated_at ON schedules;
CREATE TRIGGER update_schedules_updated_at
    BEFORE UPDATE ON schedules
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create trigger to prevent overlapping schedules
CREATE OR REPLACE FUNCTION pgcalendar.prevent_schedule_overlap()
RETURNS TRIGGER AS $$
BEGIN
    IF pgcalendar.check_schedule_overlap(NEW.event_id, NEW.start_date, NEW.end_date, NEW.schedule_id) THEN
        RAISE EXCEPTION 'Schedule overlaps with existing schedules for this event';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_schedule_overlap_trigger ON schedules;
CREATE TRIGGER prevent_schedule_overlap_trigger
    BEFORE INSERT OR UPDATE ON schedules
    FOR EACH ROW
    EXECUTE FUNCTION prevent_schedule_overlap();

-- Function to generate event dates for a schedule
CREATE OR REPLACE FUNCTION pgcalendar.generate_event_dates(
    p_schedule_id INTEGER,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    event_date DATE,
    v_result_schedule_id INTEGER,
    event_name VARCHAR(255),
    start_time TIME,
    end_time TIME,
    recurrence_type recurrence_type,
    metadata JSONB
) AS $$
DECLARE
    v_schedule RECORD;
    v_event RECORD;
    v_current_date DATE;
    v_event_date DATE;
    v_day_of_week INTEGER;
    v_day_of_month INTEGER;
    v_month INTEGER;
    v_year INTEGER;
    v_interval INTEGER;
BEGIN
    -- Get schedule details
    SELECT s.*, e.name as event_name
    INTO v_schedule
    FROM pgcalendar.schedules s
    LEFT JOIN pgcalendar.events e ON s.event_id = e.event_id
    WHERE s.schedule_id = p_schedule_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Schedule with ID % not found', p_schedule_id;
    END IF;
    
    -- Get event details
    SELECT * INTO v_event FROM pgcalendar.events WHERE event_id = v_schedule.event_id;
    
    v_current_date := GREATEST(p_start_date, v_schedule.start_date::DATE);
    v_interval := v_schedule.recurrence_interval;
    
    WHILE v_current_date <= LEAST(p_end_date, v_schedule.end_date::DATE) LOOP
        v_event_date := NULL;
        
        CASE v_schedule.recurrence_type
            WHEN 'daily' THEN
                -- Daily recurrence
                IF (v_current_date - v_schedule.start_date::DATE) % v_interval = 0 THEN
                    v_event_date := v_current_date;
                END IF;
                
            WHEN 'weekly' THEN
                -- Weekly recurrence
                IF v_schedule.recurrence_day_of_week IS NOT NULL THEN
                    v_day_of_week := EXTRACT(DOW FROM v_current_date);
                    IF v_day_of_week = v_schedule.recurrence_day_of_week THEN
                        IF (v_current_date - v_schedule.start_date::DATE) / 7 % v_interval = 0 THEN
                            v_event_date := v_current_date;
                        END IF;
                    END IF;
                ELSE
                    -- Default to start date's day of week
                    IF (v_current_date - v_schedule.start_date::DATE) / 7 % v_interval = 0 THEN
                        v_event_date := v_current_date;
                    END IF;
                END IF;
                
            WHEN 'monthly' THEN
                -- Monthly recurrence - completely rewritten logic
                IF v_schedule.recurrence_day_of_month IS NOT NULL THEN
                    -- Use specified day of month
                    IF EXTRACT(DAY FROM v_current_date) = v_schedule.recurrence_day_of_month THEN
                        -- Simple month calculation: check if current date is on the right day and month interval
                        v_month := EXTRACT(MONTH FROM v_current_date);
                        v_year := EXTRACT(YEAR FROM v_current_date);
                        IF (v_year - EXTRACT(YEAR FROM v_schedule.start_date)) * 12 + (v_month - EXTRACT(MONTH FROM v_schedule.start_date)) >= 0 THEN
                            v_event_date := v_current_date;
                        END IF;
                    END IF;
                ELSE
                    -- Default to start date's day of month
                    IF EXTRACT(DAY FROM v_current_date) = EXTRACT(DAY FROM v_schedule.start_date) THEN
                        -- Simple month calculation: check if current date is on the right day and month interval
                        v_month := EXTRACT(MONTH FROM v_current_date);
                        v_year := EXTRACT(YEAR FROM v_current_date);
                        IF (v_year - EXTRACT(YEAR FROM v_schedule.start_date)) * 12 + (v_month - EXTRACT(MONTH FROM v_schedule.start_date)) >= 0 THEN
                            v_event_date := v_current_date;
                        END IF;
                    END IF;
                END IF;
                
            WHEN 'yearly' THEN
                -- Yearly recurrence
                IF v_schedule.recurrence_month IS NOT NULL AND v_schedule.recurrence_day_of_month IS NOT NULL THEN
                    v_month := EXTRACT(MONTH FROM v_current_date);
                    v_day_of_month := EXTRACT(DAY FROM v_current_date);
                    IF v_month = v_schedule.recurrence_month AND v_day_of_month = v_schedule.recurrence_day_of_month THEN
                        IF (EXTRACT(YEAR FROM v_current_date) - EXTRACT(YEAR FROM v_schedule.start_date)) % v_interval = 0 THEN
                            v_event_date := v_current_date;
                        END IF;
                    END IF;
                ELSE
                    -- Default to start date's month and day
                    IF (EXTRACT(YEAR FROM v_current_date) - EXTRACT(YEAR FROM v_schedule.start_date)) % v_interval = 0 AND
                       EXTRACT(MONTH FROM v_current_date) = EXTRACT(MONTH FROM v_schedule.start_date) AND
                       EXTRACT(DAY FROM v_current_date) = EXTRACT(DAY FROM v_schedule.start_date) THEN
                        v_event_date := v_current_date;
                    END IF;
                END IF;
        END CASE;
        
        -- Return event if found
        IF v_event_date IS NOT NULL THEN
            -- Check for exceptions - only filter out cancelled events
            IF NOT EXISTS (
                SELECT 1 FROM pgcalendar.exceptions 
                WHERE schedule_id = p_schedule_id AND exception_date = v_event_date 
                AND exception_type = 'cancelled'
            ) THEN
                RETURN QUERY SELECT 
                    v_event_date,
                    p_schedule_id,
                    COALESCE(v_event.name, 'No Event'),
                    v_schedule.start_date::TIME,
                    v_schedule.end_date::TIME,
                    v_schedule.recurrence_type,
                    v_schedule.metadata;
            END IF;
        END IF;
        
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgcalendar.get_events_detailed(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    event_date DATE,
    schedule_id INTEGER,
    event_name VARCHAR(255),
    start_time TIME,
    end_time TIME,
    recurrence_type recurrence_type,
    status TEXT,
    notes TEXT,
    metadata JSONB
) AS $$
BEGIN
    RETURN QUERY
    WITH all_events AS (
        SELECT 
            ed.event_date as calc_event_date,
            ed.v_result_schedule_id as schedule_id,
            ed.event_name,
            ed.start_time,
            ed.end_time,
            ed.recurrence_type,
            ed.metadata
        FROM pgcalendar.schedules s
        CROSS JOIN LATERAL pgcalendar.generate_event_dates(s.schedule_id, p_start_date, p_end_date) ed
        WHERE s.start_date::DATE <= p_end_date AND s.end_date::DATE >= p_start_date
    ),
    events_with_exceptions AS (
        SELECT 
            ae.calc_event_date as normal_event_date,
            ae.schedule_id as normal_schedule_id,
            ae.event_name as normal_event_name,
            -- Apply time modifications when they exist
            CASE 
                WHEN e.exception_type = 'modified' AND e.modified_start_time IS NOT NULL THEN e.modified_start_time::TIME
                ELSE ae.start_time
            END as normal_start_time,
            CASE 
                WHEN e.exception_type = 'modified' AND e.modified_end_time IS NOT NULL THEN e.modified_end_time::TIME
                ELSE ae.end_time
            END as normal_end_time,
            ae.recurrence_type as normal_recurrence_type,
            ae.metadata as normal_metadata,
            e.exception_type as normal_exception_type,
            e.modified_date as normal_modified_date,
            e.modified_start_time as normal_modified_start_time,
            e.modified_end_time as normal_modified_end_time,
            e.notes as normal_notes,
            CASE 
                WHEN e.exception_type = 'cancelled' THEN 'CANCELLED'
                WHEN e.exception_type = 'modified' THEN 
                    CASE 
                        WHEN e.modified_date IS NOT NULL AND e.modified_date != e.exception_date THEN
                            'MODIFIED: Date ' || e.exception_date || ' → ' || e.modified_date || 
                            ' Time ' || COALESCE(e.modified_start_time::TIME::TEXT, ae.start_time::TEXT) || '-' || 
                            COALESCE(e.modified_end_time::TIME::TEXT, ae.end_time::TEXT)
                        ELSE
                            'MODIFIED: Time ' || COALESCE(e.modified_start_time::TIME::TEXT, ae.start_time::TEXT) || '-' || 
                            COALESCE(e.modified_end_time::TIME::TEXT, ae.end_time::TEXT)
                    END
                ELSE 'NORMAL: ' || ae.start_time::TEXT || '-' || ae.end_time::TEXT
            END as normal_status
        FROM all_events ae
        LEFT JOIN pgcalendar.exceptions e ON ae.schedule_id = e.schedule_id AND ae.calc_event_date = e.exception_date
    ),
    -- Handle date modifications by creating new projections on the modified dates
    date_modified_events AS (
        SELECT 
            e.modified_date as modified_event_date,
            s.schedule_id as modified_schedule_id,
            ev.name as modified_event_name,
            COALESCE(e.modified_start_time::TIME, s.start_date::TIME) as modified_start_time,
            COALESCE(e.modified_end_time::TIME, s.end_date::TIME) as modified_end_time,
            s.recurrence_type as modified_recurrence_type,  -- Use actual recurrence_type from schedule
            '{}'::jsonb as modified_metadata,
            'modified' as modified_exception_type,
            e.exception_date as modified_exception_date,
            e.modified_start_time as modified_exception_start_time,
            e.modified_end_time as modified_exception_end_time,
            e.notes as modified_notes,
            'MODIFIED: Date ' || e.exception_date || ' → ' || e.modified_date || 
            ' Time ' || COALESCE(e.modified_start_time::TIME::TEXT, s.start_date::TIME::TEXT) || '-' || 
            COALESCE(e.modified_end_time::TIME::TEXT, s.end_date::TIME::TEXT) as modified_status
        FROM pgcalendar.exceptions e
        JOIN pgcalendar.schedules s ON e.schedule_id = s.schedule_id
        JOIN pgcalendar.events ev ON s.event_id = ev.event_id
        WHERE e.exception_type = 'modified' 
        AND e.modified_date IS NOT NULL 
        AND e.modified_date != e.exception_date
        AND e.modified_date BETWEEN p_start_date AND p_end_date

    )
    SELECT 
        combined_events.event_date,
        combined_events.schedule_id,
        combined_events.event_name,
        combined_events.start_time,
        combined_events.end_time,
        combined_events.recurrence_type,
        combined_events.status,
        combined_events.notes,
        combined_events.metadata
    FROM (
        SELECT 
            normal_event_date as event_date,
            normal_schedule_id as schedule_id,
            normal_event_name as event_name,
            normal_start_time as start_time,
            normal_end_time as end_time,
            normal_recurrence_type as recurrence_type,
            normal_status as status,
            normal_notes as notes,
            normal_metadata as metadata
        FROM events_with_exceptions WHERE (normal_exception_type IS NULL OR normal_exception_type != 'cancelled') 
        AND normal_event_date NOT IN (
            SELECT e.exception_date FROM pgcalendar.exceptions e 
            WHERE e.exception_type = 'modified' 
            AND e.modified_date IS NOT NULL 
            AND e.modified_date != e.exception_date
        )
        UNION ALL
        SELECT 
            modified_event_date as event_date,
            modified_schedule_id as schedule_id,
            modified_event_name as event_name,
            modified_start_time as start_time,
            modified_end_time as end_time,
            modified_recurrence_type as recurrence_type,
            modified_status as status,
            modified_notes as notes,
            modified_metadata as metadata
        FROM date_modified_events
    ) combined_events
    ORDER BY combined_events.event_date, combined_events.start_time;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgcalendar.get_event_summary(p_event_id INTEGER)
RETURNS TABLE (
    event_name VARCHAR(255),
    total_schedules INTEGER,
    total_exceptions INTEGER,
    active_schedules INTEGER,
    next_event_date DATE,
    next_event_details TEXT
) AS $$
DECLARE
    v_event RECORD;
    v_next_event RECORD;
BEGIN
    -- Get event info
    SELECT * INTO v_event FROM pgcalendar.events WHERE event_id = p_event_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event with ID % not found', p_event_id;
    END IF;
    
    -- Get next event
    SELECT event_date, event_name, start_time, end_time
    INTO v_next_event
    FROM pgcalendar.get_events_detailed(CURRENT_DATE::date, (CURRENT_DATE + INTERVAL '1 year')::date) ed
    WHERE ed.event_name = v_event.name
    ORDER BY event_date, start_time
    LIMIT 1;
    
    RETURN QUERY
    SELECT 
        v_event.name,
        COUNT(s.schedule_id)::INTEGER as total_schedules,
        COUNT(e.exception_id)::INTEGER as total_exceptions,
        COUNT(s.schedule_id)::INTEGER as active_schedules,
        v_next_event.event_date as next_event_date,
        CASE 
            WHEN v_next_event.event_date IS NOT NULL THEN
                v_next_event.event_name || ' at ' || v_next_event.start_time || '-' || v_next_event.end_time
            ELSE 'No upcoming events'
        END as next_event_details
    FROM pgcalendar.schedules s
    LEFT JOIN pgcalendar.exceptions e ON s.schedule_id = e.schedule_id
    WHERE s.event_id = p_event_id
    GROUP BY s.event_id;
END;
$$ LANGUAGE plpgsql;

-- Function to check if schedules overlap for an event
CREATE OR REPLACE FUNCTION pgcalendar.check_schedule_overlap(
    p_event_id INTEGER,
    p_start_date TIMESTAMP,
    p_end_date TIMESTAMP,
    p_exclude_schedule_id INTEGER DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_overlap_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_overlap_count
    FROM pgcalendar.schedules
    WHERE event_id = p_event_id
    AND (p_exclude_schedule_id IS NULL OR schedule_id != p_exclude_schedule_id)
    AND (start_date, end_date) OVERLAPS (p_start_date, p_end_date);
    
    RETURN v_overlap_count > 0;
END;
$$ LANGUAGE plpgsql;

-- Function to get events by event
CREATE OR REPLACE FUNCTION pgcalendar.get_events_by_event(
    p_event_id INTEGER,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    event_date DATE,
    event_name VARCHAR(255),
    start_time TIME,
    end_time TIME,
    status TEXT,
    notes TEXT,
    metadata JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ed.event_date,
        ed.event_name,
        ed.start_time,
        ed.end_time,
        ed.status,
        ed.notes,
        ed.metadata
    FROM pgcalendar.get_events_detailed(p_start_date, p_end_date) ed
    JOIN pgcalendar.schedules s ON ed.schedule_id = s.schedule_id
    WHERE s.event_id = p_event_id
    ORDER BY ed.event_date, ed.start_time;
END;
$$ LANGUAGE plpgsql;

-- Function to get all projections for an event across all schedules
CREATE OR REPLACE FUNCTION pgcalendar.get_event_projections(
    p_event_id INTEGER,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    projection_date DATE,
    projection_schedule_id INTEGER,
    projection_event_name VARCHAR(255),
    projection_start_time TIME,
    projection_end_time TIME,
    projection_recurrence_type recurrence_type,
    projection_status TEXT,
    projection_notes TEXT,
    projection_metadata JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ed.event_date as projection_date,
        ed.schedule_id as projection_schedule_id,
        ed.event_name as projection_event_name,
        ed.start_time as projection_start_time,
        ed.end_time as projection_end_time,
        ed.recurrence_type as projection_recurrence_type,
        ed.status as projection_status,
        ed.notes as projection_notes,
        ed.metadata as projection_metadata
    FROM pgcalendar.get_events_detailed(p_start_date, p_end_date) ed
    JOIN pgcalendar.schedules s ON ed.schedule_id = s.schedule_id
    WHERE s.event_id = p_event_id
    ORDER BY projection_date, projection_start_time;
END;
$$ LANGUAGE plpgsql;

-- Create event calendar view
CREATE OR REPLACE VIEW event_calendar AS
SELECT 
    ed.event_date,
    ed.schedule_id,
    ed.event_name,
    ed.start_time,
    ed.end_time,
    ed.recurrence_type,
    ed.status,
    ed.notes,
    ed.metadata
FROM pgcalendar.get_events_detailed(CURRENT_DATE::date, (CURRENT_DATE + INTERVAL '1 year')::date) ed;

-- Function to transition event to new schedule configuration
CREATE OR REPLACE FUNCTION pgcalendar.transition_event_schedule(
    p_event_id INTEGER,
    p_new_start_date TIMESTAMP,
    p_new_end_date TIMESTAMP,
    p_recurrence_type recurrence_type,
    p_recurrence_interval INTEGER DEFAULT 1,
    p_recurrence_day_of_week INTEGER DEFAULT NULL,
    p_recurrence_day_of_month INTEGER DEFAULT NULL,
    p_recurrence_month INTEGER DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS INTEGER AS $$
DECLARE
    v_schedule_id INTEGER;
    v_overlap_exists BOOLEAN;
BEGIN
    -- Check for overlaps
    v_overlap_exists := pgcalendar.check_schedule_overlap(p_event_id, p_new_start_date, p_new_end_date);
    
    IF v_overlap_exists THEN
        RAISE EXCEPTION 'New schedule overlaps with existing schedules for this event';
    END IF;
    
    -- Insert new schedule
    INSERT INTO pgcalendar.schedules (
        event_id, start_date, end_date, recurrence_type, recurrence_interval,
        recurrence_day_of_week, recurrence_day_of_month, recurrence_month,
        description, metadata
    ) VALUES (
        p_event_id, p_new_start_date, p_new_end_date, p_recurrence_type, p_recurrence_interval,
        p_recurrence_day_of_week, p_recurrence_day_of_month, p_recurrence_month,
        p_description, p_metadata
    ) RETURNING schedule_id INTO v_schedule_id;
    
    RETURN v_schedule_id;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT USAGE ON SCHEMA pgcalendar TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA pgcalendar TO PUBLIC;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pgcalendar TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pgcalendar TO PUBLIC;

-- Add comments
COMMENT ON SCHEMA pgcalendar IS 'Infinite calendar extension for recurring schedules with exceptions and event grouping';
COMMENT ON TABLE events IS 'Events represent logical events that can have multiple schedule configurations';
COMMENT ON TABLE schedules IS 'Schedule configurations for events, each generating projections for different time periods (overlap prevention handled by triggers)';
COMMENT ON TABLE exceptions IS 'Exceptions modify single instances of projections (cancellations, time modifications, and date modifications)';
COMMENT ON COLUMN exceptions.modified_date IS 'New date for date-modified exceptions (NULL for time-only modifications)';
COMMENT ON FUNCTION generate_event_dates IS 'Generate event dates for a schedule within a date range';
COMMENT ON FUNCTION get_events_detailed IS 'Get detailed events with exception handling';
COMMENT ON FUNCTION get_event_summary IS 'Get summary information for an event';
COMMENT ON FUNCTION get_events_by_event IS 'Get events for a specific event';
COMMENT ON FUNCTION check_schedule_overlap IS 'Check if a schedule overlaps with existing schedules for an event';
COMMENT ON FUNCTION get_event_projections IS 'Get all projections for an event across all its schedule configurations';
COMMENT ON FUNCTION transition_event_schedule IS 'Transition an event to a new schedule configuration without overlaps';
COMMENT ON FUNCTION prevent_schedule_overlap IS 'Trigger function to prevent overlapping schedules for the same event';

-- Display installation status
SELECT 'pgcalendar extension installed successfully' as status;
