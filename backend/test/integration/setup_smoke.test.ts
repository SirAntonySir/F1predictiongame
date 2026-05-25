import { describe, it, expect } from 'vitest'
import { getDb } from '../../src/db/client.js'
import { season } from '../../src/db/schema.js'

describe('test infrastructure', () => {
  it('starts each test with an empty database', async () => {
    const db = getDb()
    const rows = await db.select().from(season)
    expect(rows).toEqual([])
  })
})
