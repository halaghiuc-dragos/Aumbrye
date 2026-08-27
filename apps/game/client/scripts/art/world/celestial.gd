extends RefCounted
class_name Celestial


const LATITUDE_DEG := 47.0

const AXIAL_TILT_DEG := 23.44

const DAYS_PER_YEAR := 96.0
const DAYS_PER_LUNAR_MONTH := 29.53

const LUNAR_INCLINATION_DEG := 5.14


static func sun_direction(phase: float, day: float) -> Vector3:
	return _horizon_vector(_hour_angle(phase), _solar_declination(day))


static func moon_direction(phase: float, day: float) -> Vector3:
	var hour_angle := _hour_angle(phase) - elongation(day)
	return _horizon_vector(hour_angle, _lunar_declination(day))


static func elongation(day: float) -> float:
	return fposmod(day / DAYS_PER_LUNAR_MONTH, 1.0) * TAU


static func illuminated_fraction(day: float) -> float:
	return (1.0 - cos(elongation(day))) * 0.5


static func elevation_deg(dir: Vector3) -> float:
	return rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))


static func light_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.y) < 0.999 else Vector3.FORWARD
	return Basis.looking_at(-dir, up)


static func _hour_angle(phase: float) -> float:
	return (phase - 0.5) * TAU


static func _solar_declination(day: float) -> float:
	var year := fposmod(day / DAYS_PER_YEAR, 1.0)
	return deg_to_rad(AXIAL_TILT_DEG) * sin(year * TAU)


static func _lunar_declination(day: float) -> float:
	var mirrored := -_solar_declination(day) * cos(elongation(day))
	return mirrored + deg_to_rad(LUNAR_INCLINATION_DEG) * sin(day / DAYS_PER_LUNAR_MONTH * TAU * 1.1)


static func _horizon_vector(hour_angle: float, declination: float) -> Vector3:
	var lat := deg_to_rad(LATITUDE_DEG)
	var sin_alt := (
		sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hour_angle)
	)
	var altitude := asin(clampf(sin_alt, -1.0, 1.0))
	var azimuth := atan2(
		sin(hour_angle),
		cos(hour_angle) * sin(lat) - tan(declination) * cos(lat)
	)
	azimuth += PI
	var cos_alt := cos(altitude)
	return Vector3(sin(azimuth) * cos_alt, sin(altitude), -cos(azimuth) * cos_alt)
