class_name Calculations
## Pure functions. No UI or scene access.

const G0 := 9.80665 # m/s^2

## Tsiolkovsky rocket equation: delta-v in m/s.
static func delta_v(isp_s: float, wet_mass_kg: float, dry_mass_kg: float) -> float:
	if dry_mass_kg <= 0.0 or wet_mass_kg <= dry_mass_kg:
		return 0.0
	return isp_s * G0 * log(wet_mass_kg / dry_mass_kg)
