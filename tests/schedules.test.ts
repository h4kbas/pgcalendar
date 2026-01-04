import { Pool } from 'pg';
import { setupTestDatabase, cleanTestData, dbConfig } from './setup';

describe('pgcalendar - Schedules', () => {
  let pool: Pool;
  let eventId: number;

  beforeAll(async () => {
    pool = await setupTestDatabase();
  });

  beforeEach(async () => {
    await cleanTestData(pool);
    const result = await pool.query(
      `INSERT INTO pgcalendar.events (name, description, category)
       VALUES ($1, $2, $3)
       RETURNING event_id`,
      ['Test Event', 'A test event', 'meeting']
    );
    eventId = result.rows[0].event_id;
  });


  describe('Schedule Creation', () => {
    it('should create a daily schedule', async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.schedules
         (event_id, start_date, end_date, recurrence_type, recurrence_interval)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [
          eventId,
          '2024-01-01 09:00:00',
          '2024-01-07 23:59:59',
          'daily',
          1,
        ]
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].event_id).toBe(eventId);
      expect(result.rows[0].recurrence_type).toBe('daily');
      expect(result.rows[0].recurrence_interval).toBe(1);
      expect(result.rows[0].schedule_id).toBeDefined();
    });

    it('should create a weekly schedule', async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.schedules
         (event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_day_of_week)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [
          eventId,
          '2024-01-01 10:00:00',
          '2024-12-31 23:59:59',
          'weekly',
          1,
          1, // Monday
        ]
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].recurrence_type).toBe('weekly');
      expect(result.rows[0].recurrence_day_of_week).toBe(1);
    });

    it('should create a monthly schedule', async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.schedules
         (event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_day_of_month)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [
          eventId,
          '2024-01-01 09:00:00',
          '2024-12-31 23:59:59',
          'monthly',
          1,
          15, // 15th of each month
        ]
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].recurrence_type).toBe('monthly');
      expect(result.rows[0].recurrence_day_of_month).toBe(15);
    });

    it('should create a yearly schedule', async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.schedules
         (event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_month, recurrence_day_of_month)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *`,
        [
          eventId,
          '2024-01-01 09:00:00',
          '2030-12-31 23:59:59',
          'yearly',
          1,
          6, // June
          15, // 15th
        ]
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].recurrence_type).toBe('yearly');
      expect(result.rows[0].recurrence_month).toBe(6);
      expect(result.rows[0].recurrence_day_of_month).toBe(15);
    });
  });

  describe('Schedule Constraints', () => {
    it('should enforce valid recurrence interval', async () => {
      await expect(
        pool.query(
          `INSERT INTO pgcalendar.schedules
           (event_id, start_date, end_date, recurrence_type, recurrence_interval)
           VALUES ($1, $2, $3, $4, $5)`,
          [
            eventId,
            '2024-01-01 09:00:00',
            '2024-01-07 23:59:59',
            'daily',
            0, // Invalid: must be > 0
          ]
        )
      ).rejects.toThrow();
    });

    it('should enforce valid day of week', async () => {
      await expect(
        pool.query(
          `INSERT INTO pgcalendar.schedules
           (event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_day_of_week)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [
            eventId,
            '2024-01-01 09:00:00',
            '2024-01-07 23:59:59',
            'weekly',
            1,
            7, // Invalid: must be 0-6
          ]
        )
      ).rejects.toThrow();
    });

    it('should enforce valid day of month', async () => {
      await expect(
        pool.query(
          `INSERT INTO pgcalendar.schedules
           (event_id, start_date, end_date, recurrence_type, recurrence_interval, recurrence_day_of_month)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [
            eventId,
            '2024-01-01 09:00:00',
            '2024-12-31 23:59:59',
            'monthly',
            1,
            32, // Invalid: must be 1-31
          ]
        )
      ).rejects.toThrow();
    });
  });

  describe('Schedule Overlap Prevention', () => {
    it('should prevent overlapping schedules for the same event', async () => {
      // Create first schedule
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

      // Try to create overlapping schedule - should fail
      await expect(
        pool.query(
          `INSERT INTO pgcalendar.schedules
           (event_id, start_date, end_date, recurrence_type, recurrence_interval)
           VALUES ($1, $2, $3, $4, $5)`,
          [
            eventId,
            '2024-01-05 09:00:00', // Overlaps with first schedule
            '2024-01-10 23:59:59',
            'daily',
            1,
          ]
        )
      ).rejects.toThrow(/overlap/);
    });

    it('should allow non-overlapping schedules for the same event', async () => {
      // Create first schedule
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

      // Create non-overlapping schedule - should succeed
      const result = await pool.query(
        `INSERT INTO pgcalendar.schedules
         (event_id, start_date, end_date, recurrence_type, recurrence_interval)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [
          eventId,
          '2024-01-08 09:00:00', // After first schedule ends
          '2024-01-14 23:59:59',
          'daily',
          1,
        ]
      );

      expect(result.rows).toHaveLength(1);
    });

    it('should allow overlapping schedules for different events', async () => {
      // Create event 2
      const event2Result = await pool.query(
        `INSERT INTO pgcalendar.events (name) VALUES ($1) RETURNING event_id`,
        ['Event 2']
      );
      const event2Id = event2Result.rows[0].event_id;

      // Create schedule for event 1
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

      // Create overlapping schedule for event 2 - should succeed
      const result = await pool.query(
        `INSERT INTO pgcalendar.schedules
         (event_id, start_date, end_date, recurrence_type, recurrence_interval)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [
          event2Id,
          '2024-01-05 09:00:00', // Overlaps with event 1's schedule
          '2024-01-10 23:59:59',
          'daily',
          1,
        ]
      );

      expect(result.rows).toHaveLength(1);
    });
  });

  describe('Schedule Updates', () => {
    let scheduleId: number;

    beforeEach(async () => {
      const result = await pool.query(
        `INSERT INTO pgcalendar.schedules
         (event_id, start_date, end_date, recurrence_type, recurrence_interval)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING schedule_id`,
        [
          eventId,
          '2024-01-01 09:00:00',
          '2024-01-07 23:59:59',
          'daily',
          1,
        ]
      );
      scheduleId = result.rows[0].schedule_id;
    });

    it('should update schedule fields', async () => {
      const result = await pool.query(
        `UPDATE pgcalendar.schedules
         SET description = $1, recurrence_interval = $2
         WHERE schedule_id = $3
         RETURNING *`,
        ['Updated description', 2, scheduleId]
      );

      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].description).toBe('Updated description');
      expect(result.rows[0].recurrence_interval).toBe(2);
    });

    it('should update updated_at timestamp on update', async () => {
      const before = await pool.query(
        `SELECT updated_at FROM pgcalendar.schedules WHERE schedule_id = $1`,
        [scheduleId]
      );
      const beforeTime = new Date(before.rows[0].updated_at);

      await new Promise((resolve) => setTimeout(resolve, 100));

      await pool.query(
        `UPDATE pgcalendar.schedules SET description = $1 WHERE schedule_id = $2`,
        ['New description', scheduleId]
      );

      const after = await pool.query(
        `SELECT updated_at FROM pgcalendar.schedules WHERE schedule_id = $1`,
        [scheduleId]
      );
      const afterTime = new Date(after.rows[0].updated_at);

      expect(afterTime.getTime()).toBeGreaterThan(beforeTime.getTime());
    });
  });
});
