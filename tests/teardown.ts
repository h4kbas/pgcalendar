import { cleanupTestDatabase } from './setup';

export default async function globalTeardown() {
  await cleanupTestDatabase();
}


