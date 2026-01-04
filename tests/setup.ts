import { Pool } from 'pg';
import * as fs from 'fs';
import * as path from 'path';

// Database connection configuration
export const dbConfig = {
  host: process.env.PG_HOST || 'localhost',
  port: parseInt(process.env.PG_PORT || '5433', 10),
  user: process.env.PG_USER || 'postgres',
  password: process.env.PG_PASSWORD || 'postgres',
  database: process.env.PG_DB || 'pgcalendar_test',
};

// Global test database pool
let testPool: Pool | null = null;
let setupPromise: Promise<Pool> | null = null;

// Initialize test database connection
export async function setupTestDatabase(): Promise<Pool> {
  // Return existing pool if available
  if (testPool) {
    return testPool;
  }

  // If setup is in progress, wait for it
  if (setupPromise) {
    return setupPromise;
  }

  // Start setup
  setupPromise = (async () => {
    testPool = new Pool(dbConfig);

    // Test connection
    try {
      await testPool.query('SELECT 1');
      console.log('✓ Connected to test database');
    } catch (error) {
      const err = error as Error;
      if (err.message.includes('ECONNREFUSED')) {
        console.error('\n✗ Failed to connect to test database');
        console.error(`  Connection refused on ${dbConfig.host}:${dbConfig.port}`);
        console.error('\n  Please ensure PostgreSQL is running. Options:');
        console.error('  1. Start your test database:');
        console.error(`     docker run -d --name pgcalendar-test \\`);
        console.error(`       -e POSTGRES_USER=${dbConfig.user} \\`);
        console.error(`       -e POSTGRES_PASSWORD=${dbConfig.password} \\`);
        console.error(`       -e POSTGRES_DB=${dbConfig.database} \\`);
        console.error(`       -p ${dbConfig.port}:5432 postgres:15`);
        console.error('  2. Or set environment variables:');
        console.error('     PG_HOST=localhost PG_PORT=5432 PG_USER=postgres PG_PASSWORD=postgres PG_DB=pgcalendar_test');
        console.error('');
      } else {
        console.error('✗ Failed to connect to test database:', err.message);
      }
      throw error;
    }

    // Install extension if not already installed
    try {
      // Check if schema exists
      const schemaCheck = await testPool.query(
        "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pgcalendar'"
      );

      if (schemaCheck.rows.length === 0) {
        console.log('Installing pgcalendar extension...');
        const sqlFile = path.join(__dirname, '../pgcalendar.sql');
        const sql = fs.readFileSync(sqlFile, 'utf8');
        await testPool.query(sql);
        console.log('✓ Extension installed');
      } else {
        // Schema exists, verify it's working
        try {
          await testPool.query('SELECT 1 FROM pgcalendar.events LIMIT 1');
          console.log('✓ Extension already installed and verified');
        } catch (verifyError) {
          // Schema exists but might be broken, try to reinstall
          console.log('Extension schema exists but may be incomplete, reinstalling...');
          try {
            // Drop schema and recreate
            await testPool.query('DROP SCHEMA IF EXISTS pgcalendar CASCADE');
            const sqlFile = path.join(__dirname, '../pgcalendar.sql');
            const sql = fs.readFileSync(sqlFile, 'utf8');
            await testPool.query(sql);
            console.log('✓ Extension reinstalled');
          } catch (reinstallError) {
            console.error('✗ Failed to reinstall extension:', reinstallError);
            throw reinstallError;
          }
        }
      }
    } catch (error) {
      const err = error as Error;
      // If it's a deadlock or function conflict, try dropping and recreating
      if (err.message.includes('deadlock') || err.message.includes('cannot change return type')) {
        console.log('Extension installation conflict detected, cleaning and reinstalling...');
        try {
          await testPool.query('DROP SCHEMA IF EXISTS pgcalendar CASCADE');
          const sqlFile = path.join(__dirname, '../pgcalendar.sql');
          const sql = fs.readFileSync(sqlFile, 'utf8');
          await testPool.query(sql);
          console.log('✓ Extension reinstalled after cleanup');
        } catch (reinstallError) {
          console.error('✗ Failed to reinstall extension:', reinstallError);
          throw reinstallError;
        }
      } else {
        console.error('✗ Failed to install extension:', err.message);
        throw error;
      }
    }

    return testPool;
  })();

  return setupPromise;
}

// Clean up test database
export async function cleanupTestDatabase(): Promise<void> {
  if (testPool) {
    const pool = testPool;
    testPool = null; // Clear reference first to prevent double cleanup
    setupPromise = null; // Reset setup promise
    try {
      await pool.end();
    } catch (error) {
      // Ignore errors if pool is already ended
      const errorMessage = (error as Error).message || '';
      if (!errorMessage.includes('ended') && !errorMessage.includes('Cannot')) {
        console.warn('Warning closing pool:', errorMessage);
      }
    }
  }
}

// Clean all test data
export async function cleanTestData(pool: Pool | null | undefined): Promise<void> {
  if (!pool) {
    return;
  }
  try {
    await pool.query('DELETE FROM pgcalendar.exceptions');
    await pool.query('DELETE FROM pgcalendar.schedules');
    await pool.query('DELETE FROM pgcalendar.events');
  } catch (error) {
    // Ignore errors if tables don't exist yet
    const errorMessage = (error as Error).message || '';
    if (!errorMessage.includes('does not exist') && !errorMessage.includes('relation') && !errorMessage.includes('ECONNREFUSED')) {
      throw error;
    }
  }
}

// Cleanup on process exit
process.on('exit', () => {
  if (testPool) {
    testPool.end().catch(() => {
      // Ignore errors on exit
    });
  }
});
