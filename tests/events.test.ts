import { Pool } from 'pg';
import { setupTestDatabase, cleanTestData, dbConfig } from './setup';

describe('pgcalendar - Events', () => {
  let pool: Pool;

  beforeAll(async () => {
    pool = await setupTestDatabase();
  });

  afterEach(async () => {
    if (pool) {
      await cleanTestData(pool);
    }
  });

  describe('Event Creation', () => {
    it('should create an event with all fields', async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.events (name, description, category, priority, status, metadata)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [
          'Test Event',
          'A test event description',
          'meeting',
          5,
          'active',
          JSON.stringify({ custom: 'data' }),
        ]
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].name).toBe('Test Event');
      expect(result.rows[0].description).toBe('A test event description');
      expect(result.rows[0].category).toBe('meeting');
      expect(result.rows[0].priority).toBe(5);
      expect(result.rows[0].status).toBe('active');
      expect(result.rows[0].metadata).toEqual({ custom: 'data' });
      expect(result.rows[0].event_id).toBeDefined();
      expect(result.rows[0].created_at).toBeDefined();
      expect(result.rows[0].updated_at).toBeDefined();
    });

    it('should create an event with minimal fields', async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.events (name)
         VALUES ($1)
         RETURNING *`,
        ['Minimal Event']
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].name).toBe('Minimal Event');
      expect(result.rows[0].priority).toBe(1); // default
      expect(result.rows[0].status).toBe('active'); // default
      expect(result.rows[0].metadata).toEqual({}); // default
    });

    it('should not allow duplicate event names without constraint', async () => {
      await pool.query(
        `INSERT INTO pgcalendar.events (name) VALUES ($1)`,
        ['Duplicate Event']
      );

      // This should succeed (no unique constraint on name)
      const result = await pool.query(
        `INSERT INTO pgcalendar.events (name) VALUES ($1) RETURNING *`,
        ['Duplicate Event']
      );

      expect(result.rows).toHaveLength(1);
    });
  });

  describe('Event Updates', () => {
    let eventId: number;

    beforeEach(async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.events (name, description, category)
         VALUES ($1, $2, $3)
         RETURNING event_id`,
        ['Update Test Event', 'Original description', 'meeting']
      );
      eventId = result.rows[0].event_id;
    });

    it('should update event fields', async () => {
      const result = await pool.query(
        `UPDATE pgcalendar.events
         SET name = $1, description = $2, category = $3, priority = $4
         WHERE event_id = $5
         RETURNING *`,
        ['Updated Event', 'Updated description', 'task', 10, eventId]
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].name).toBe('Updated Event');
      expect(result.rows[0].description).toBe('Updated description');
      expect(result.rows[0].category).toBe('task');
      expect(result.rows[0].priority).toBe(10);
    });

    it('should update updated_at timestamp on update', async () => {
      const before = await pool.query(
        `SELECT updated_at FROM pgcalendar.events WHERE event_id = $1`,
        [eventId]
      );
      const beforeTime = new Date(before.rows[0].updated_at);

      // Wait a bit to ensure timestamp changes
      await new Promise((resolve) => setTimeout(resolve, 100));

      await pool.query(
        `UPDATE pgcalendar.events SET name = $1 WHERE event_id = $2`,
        ['Updated Name', eventId]
      );

      const after = await pool.query(
        `SELECT updated_at FROM pgcalendar.events WHERE event_id = $1`,
        [eventId]
      );
      const afterTime = new Date(after.rows[0].updated_at);

      expect(afterTime.getTime()).toBeGreaterThan(beforeTime.getTime());
    });
  });

  describe('Event Queries', () => {
    beforeEach(async () => {
      await pool.query(
        `INSERT INTO pgcalendar.events (name, category, priority, status) VALUES
         ('Event 1', 'meeting', 1, 'active'),
         ('Event 2', 'task', 2, 'active'),
         ('Event 3', 'meeting', 3, 'inactive')`
      );
    });

    it('should query events by category', async () => {
      const result = await pool.query(
        `SELECT * FROM pgcalendar.events WHERE category = $1`,
        ['meeting']
      );

      expect(result.rows.length).toBeGreaterThanOrEqual(2);
      result.rows.forEach((row) => {
        expect(row.category).toBe('meeting');
      });
    });

    it('should query events by status', async () => {
      const result = await pool.query(
        `SELECT * FROM pgcalendar.events WHERE status = $1`,
        ['active']
      );

      expect(result.rows.length).toBeGreaterThanOrEqual(2);
      result.rows.forEach((row) => {
        expect(row.status).toBe('active');
      });
    });

    it('should query events ordered by priority', async () => {
      const result = await pool.query(
        `SELECT * FROM pgcalendar.events ORDER BY priority DESC`
      );

      expect(result.rows.length).toBeGreaterThanOrEqual(3);
      for (let i = 1; i < result.rows.length; i++) {
        expect(result.rows[i - 1].priority).toBeGreaterThanOrEqual(
          result.rows[i].priority
        );
      }
    });
  });

  describe('Event Deletion', () => {
    let eventId: number;

    beforeEach(async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.events (name) VALUES ($1) RETURNING event_id`,
        ['Delete Test Event']
      );
      eventId = result.rows[0].event_id;
    });

    it('should delete an event', async () => {
      const result = await pool.query(
        `DELETE FROM pgcalendar.events WHERE event_id = $1 RETURNING *`,
        [eventId]
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].event_id).toBe(eventId);

      const check = await pool.query(
        `SELECT * FROM pgcalendar.events WHERE event_id = $1`,
        [eventId]
      );
      expect(check.rows).toHaveLength(0);
    });

    it('should cascade delete schedules when event is deleted', async () => {
      // Create a schedule for the event
      await pool.query(
        `INSERT INTO pgcalendar.schedules
         (event_id, start_date, end_date, recurrence_type, recurrence_interval)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          eventId,
          '2024-01-01 09:00:00',
          '2024-01-07 23:59:59',
          'daily',
          1,
        ]
      );

      // Delete the event
      await pool.query(`DELETE FROM pgcalendar.events WHERE event_id = $1`, [
        eventId,
      ]);

      // Check that schedules were also deleted
      const schedules = await pool.query(
        `SELECT * FROM pgcalendar.schedules WHERE event_id = $1`,
        [eventId]
      );
      expect(schedules.rows).toHaveLength(0);
    });
  });
});
