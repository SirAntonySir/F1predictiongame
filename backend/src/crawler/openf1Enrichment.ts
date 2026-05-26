import * as driversRepo from '../repo/drivers.js'
import * as constructorsRepo from '../repo/constructors.js'
import type { OpenF1DriverLookup } from '../openf1/parsers.js'

export async function enrichDriversAndConstructors(drivers: OpenF1DriverLookup[]): Promise<void> {
  const seenConstructors = new Set<string>()
  for (const d of drivers) {
    try {
      const existing = await driversRepo.getByCode(d.code)
      if (existing && existing.headshotUrl == null && d.headshotUrl != null) {
        await driversRepo.setHeadshotUrl(d.code, d.headshotUrl)
      }
      const constructorId = d.teamName.toLowerCase().replace(/\s+/g, '_')
      if (!seenConstructors.has(constructorId)) {
        seenConstructors.add(constructorId)
        const existingCtor = await constructorsRepo.getById(constructorId)
        if (existingCtor && existingCtor.teamColour == null && d.teamColour != null) {
          await constructorsRepo.setTeamColour(constructorId, d.teamColour)
        }
      }
    } catch (err) {
      console.warn('OpenF1 enrichment error', { code: d.code, err })
    }
  }
}
