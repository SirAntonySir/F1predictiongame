import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    globals: false,
    setupFiles: ['test/helpers/setup.ts'],
    testTimeout: 10_000,
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } }
  }
})
