import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    globals: false,
    globalSetup: ['test/helpers/globalSetup.ts'],
    setupFiles: ['test/helpers/setup.ts'],
    testTimeout: 10_000,
    // Force NODE_ENV=test even when .env sets it to 'development'. The config
    // module switches to TEST_DATABASE_URL based on this — without the override
    // the test suite would point at the dev DB and truncate its data.
    env: { NODE_ENV: 'test' },
    // Single fork: integration tests share one Postgres and rely on
    // beforeEach truncate. Parallel forks would race that truncate.
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } }
  }
})
