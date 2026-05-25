import { beforeEach, afterAll } from 'vitest'
import { truncateAll } from './db.js'
import { _resetPoolForTests } from '../../src/db/client.js'

beforeEach(async () => {
  await truncateAll()
})

afterAll(async () => {
  await _resetPoolForTests()
})
