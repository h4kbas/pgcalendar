-- pgcalendar extension installation script
-- Version: 1.0.0

-- Create the extension schema
CREATE SCHEMA IF NOT EXISTS pgcalendar;

-- Set search path
SET search_path TO pgcalendar, public;

-- Create custom types
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

-- Create tables
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

-- Create overlap prevention trigger function
CREATE OR REPLACE FUNCTION pgcalendar.prevent_schedule_overlap()
RETURNS TRIGGER AS $$
BEGIN
    -- Check for overlapping schedules for the same event
    IF EXISTS (
        SELECT 1 FROM pgcalendar.schedules 
        WHERE event_id = NEW.event_id 
        AND schedule_id != COALESCE(NEW.schedule_id, -1)
        AND (
            (NEW.start_date <= end_date AND NEW.end_date >= start_date)
        )
    ) THEN
        RAISE EXCEPTION 'Schedule overlap detected for event %: new schedule (%, %) overlaps with existing schedule', 
            NEW.event_id, NEW.start_date, NEW.end_date;
    END IF;
    
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger for overlap prevention
DROP TRIGGER IF EXISTS prevent_schedule_overlap_trigger ON schedules;
CREATE TRIGGER prevent_schedule_overlap_trigger
    BEFORE INSERT OR UPDATE ON schedules
    FOR EACH ROW
    EXECUTE FUNCTION prevent_schedule_overlap();

-- Create projection generation function
CREATE OR REPLACE FUNCTION pgcalendar.generate_projections(
    p_schedule_id INTEGER,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE(
    projection_date DATE,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    status TEXT
) AS $$
DECLARE
    v_schedule RECORD;
    v_current_date DATE;
    v_projection_date DATE;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_exception RECORD;
BEGIN
    -- Get schedule details
    SELECT * INTO v_schedule 
    FROM pgcalendar.schedules 
    WHERE schedule_id = p_schedule_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Schedule % not found', p_schedule_id;
    END IF;
    
    -- Initialize current date
    v_current_date := GREATEST(p_start_date, v_schedule.start_date::date);
    
    -- Generate projections based on recurrence type
    WHILE v_current_date <= LEAST(p_end_date, v_schedule.end_date::date) LOOP
        -- Check if this date should have a projection
        IF pgcalendar.should_generate_projection(v_schedule, v_current_date) THEN
            -- Check for exceptions
            SELECT * INTO v_exception 
            FROM pgcalendar.exceptions 
            WHERE schedule_id = p_schedule_id AND exception_date = v_current_date;
            
            IF NOT FOUND THEN
                -- No exception, generate normal projection
                v_projection_date := v_current_date;
                v_start_time := (v_current_date || ' ' || v_schedule.start_date::time)::timestamp;
                v_end_time := (v_current_date || ' ' || v_schedule.end_date::time)::timestamp;
                
                RETURN QUERY SELECT v_projection_date, v_start_time, v_end_time, 'active'::text;
            ELSE
                -- Handle exception
                IF v_exception.exception_type = 'cancelled' THEN
                    -- Skip this date
                    NULL;
                ELSIF v_exception.exception_type = 'modified' THEN
                    -- Return modified projection
                    v_projection_date := COALESCE(v_exception.modified_date, v_current_date);
                    v_start_time := COALESCE(v_exception.modified_start_time, 
                        (v_projection_date || ' ' || v_schedule.start_date::time)::timestamp);
                    v_end_time := COALESCE(v_exception.modified_end_time, 
                        (v_projection_date || ' ' || v_schedule.end_date::time)::timestamp);
                    
                    RETURN QUERY SELECT v_projection_date, v_start_time, v_end_time, 
                        'modified'::text;
                END IF;
            END IF;
        END IF;
        
        -- Move to next date based on recurrence
        v_current_date := pgcalendar.get_next_recurrence_date(v_schedule, v_current_date);
    END LOOP;
END;
$$ language 'plpgsql';

-- Helper function to determine if a projection should be generated
CREATE OR REPLACE FUNCTION pgcalendar.should_generate_projection(
    p_schedule RECORD,
    p_date DATE
)
RETURNS BOOLEAN AS $$
BEGIN
    CASE p_schedule.recurrence_type
        WHEN 'daily' THEN
            RETURN (p_date - p_schedule.start_date::date) % p_schedule.recurrence_interval = 0;
        WHEN 'weekly' THEN
            RETURN EXTRACT(DOW FROM p_date) = p_schedule.recurrence_day_of_week
                   AND (p_date - p_schedule.start_date::date) % (p_schedule.recurrence_interval * 7) = 0;
        WHEN 'monthly' THEN
            RETURN EXTRACT(DAY FROM p_date) = p_schedule.recurrence_day_of_month
                   AND (p_date - p_schedule.start_date::date) >= p_schedule.recurrence_interval * 30;
        WHEN 'yearly' THEN
            RETURN EXTRACT(MONTH FROM p_date) = p_schedule.recurrence_month
                   AND EXTRACT(DAY FROM p_date) = p_schedule.recurrence_day_of_month
                   AND (p_date - p_schedule.start_date::date) >= p_schedule.recurrence_interval * 365;
        ELSE
            RETURN FALSE;
    END CASE;
END;
$$ language 'plpgsql';

-- Helper function to get next recurrence date
CREATE OR REPLACE FUNCTION pgcalendar.get_next_recurrence_date(
    p_schedule RECORD,
    p_current_date DATE
)
RETURNS DATE AS $$
BEGIN
    CASE p_schedule.recurrence_type
        WHEN 'daily' THEN
            RETURN p_current_date + p_schedule.recurrence_interval;
        WHEN 'weekly' THEN
            RETURN p_current_date + (p_schedule.recurrence_interval * 7);
        WHEN 'monthly' THEN
            RETURN p_current_date + INTERVAL '1 month' * p_schedule.recurrence_interval;
        WHEN 'yearly' THEN
            RETURN p_current_date + INTERVAL '1 year' * p_schedule.recurrence_interval;
        ELSE
            RETURN p_current_date + 1;
    END CASE;
END;
$$ language 'plpgsql';

-- Main function to get event projections
CREATE OR REPLACE FUNCTION pgcalendar.get_event_projections(
    p_event_id INTEGER,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE(
    projection_date DATE,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    event_name VARCHAR(255),
    event_description TEXT,
    event_category VARCHAR(100),
    schedule_description TEXT,
    status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.projection_date,
        p.start_time,
        p.end_time,
        e.name as event_name,
        e.description as event_description,
        e.category as event_category,
        s.description as schedule_description,
        p.status
    FROM pgcalendar.events e
    JOIN pgcalendar.schedules s ON e.event_id = s.event_id
    CROSS JOIN LATERAL pgcalendar.generate_projections(s.schedule_id, p_start_date, p_end_date) p
    WHERE e.event_id = p_event_id
    ORDER BY p.projection_date, p.start_time;
END;
$$ language 'plpgsql';

-- Function to get all events with detailed information
CREATE OR REPLACE FUNCTION pgcalendar.get_events_detailed(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE(
    projection_date DATE,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    event_name VARCHAR(255),
    event_description TEXT,
    event_category VARCHAR(100),
    schedule_description TEXT,
    status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.projection_date,
        p.start_time,
        p.end_time,
        e.name as event_name,
        e.description as event_description,
        e.category as event_category,
        s.description as schedule_description,
        p.status
    FROM pgcalendar.events e
    JOIN pgcalendar.schedules s ON e.event_id = s.event_id
    CROSS JOIN LATERAL pgcalendar.generate_projections(s.schedule_id, p_start_date, p_end_date) p
    ORDER BY p.projection_date, p.start_time;
END;
$$ language 'plpgsql';

-- Function to check schedule overlap
CREATE OR REPLACE FUNCTION pgcalendar.check_schedule_overlap(
    p_event_id INTEGER,
    p_start_date TIMESTAMP,
    p_end_date TIMESTAMP
)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM pgcalendar.schedules 
        WHERE event_id = p_event_id 
        AND (
            (p_start_date <= end_date AND p_end_date >= start_date)
        )
    );
END;
$$ language 'plpgsql';

-- Function to transition event schedule
CREATE OR REPLACE FUNCTION pgcalendar.transition_event_schedule(
    p_event_id INTEGER,
    p_new_start_date TIMESTAMP,
    p_new_end_date TIMESTAMP,
    p_recurrence_type recurrence_type,
    p_recurrence_interval INTEGER DEFAULT 1,
    p_recurrence_day_of_week INTEGER DEFAULT NULL,
    p_recurrence_day_of_month INTEGER DEFAULT NULL,
    p_recurrence_month INTEGER DEFAULT NULL,
    p_description TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_schedule_id INTEGER;
BEGIN
    -- Check for overlap
    IF pgcalendar.check_schedule_overlap(p_event_id, p_new_start_date, p_new_end_date) THEN
        RAISE EXCEPTION 'New schedule would overlap with existing schedules for event %', p_event_id;
    END IF;
    
    -- Create new schedule
    INSERT INTO pgcalendar.schedules (
        event_id, start_date, end_date, recurrence_type, recurrence_interval,
        recurrence_day_of_week, recurrence_day_of_month, recurrence_month, description
    ) VALUES (
        p_event_id, p_new_start_date, p_new_end_date, p_recurrence_type, p_recurrence_interval,
        p_recurrence_day_of_week, p_recurrence_day_of_month, p_recurrence_month, p_description
    ) RETURNING schedule_id INTO v_schedule_id;
    
    RETURN v_schedule_id;
END;
$$ language 'plpgsql';

-- Create view for current year calendar
CREATE OR REPLACE VIEW pgcalendar.event_calendar AS
SELECT 
    p.projection_date,
    p.start_time,
    p.end_time,
    e.name as event_name,
    e.description as event_description,
    e.category as event_category,
    s.description as schedule_description,
    p.status
FROM pgcalendar.events e
JOIN pgcalendar.schedules s ON e.event_id = s.event_id
CROSS JOIN LATERAL pgcalendar.generate_projections(
    s.schedule_id, 
    (CURRENT_DATE - INTERVAL '6 months')::date, 
    (CURRENT_DATE + INTERVAL '6 months')::date
) p
WHERE p.projection_date >= CURRENT_DATE - INTERVAL '6 months'
  AND p.projection_date <= CURRENT_DATE + INTERVAL '6 months'
ORDER BY p.projection_date, p.start_time;

-- Grant permissions
GRANT USAGE ON SCHEMA pgcalendar TO PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA pgcalendar TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pgcalendar TO PUBLIC;
GRANT SELECT ON pgcalendar.event_calendar TO PUBLIC;
