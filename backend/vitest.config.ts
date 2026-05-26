import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    globals: false,
    testTimeout: 10_000,
    // Single fork: integration tests share one Postgres and rely on
    // beforeEach truncate. Parallel forks would race that truncate.
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } },
    projects: [
      {
        test: {
          name: 'unit',
          include: ['test/unit/**/*.test.ts'],
        }
      },
      {
        test: {
          name: 'integration',
          include: ['test/integration/**/*.test.ts'],
          setupFiles: ['test/helpers/setup.ts'],
        }
      }
    ]
  }
})
