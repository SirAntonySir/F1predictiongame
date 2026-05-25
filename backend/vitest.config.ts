import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    globals: false,
    setupFiles: ['test/helpers/setup.ts'],
    testTimeout: 10_000,
    // Single fork: integration tests share one Postgres and rely on
    // beforeEach truncate. Parallel forks would race that truncate.
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } }
  }
})
