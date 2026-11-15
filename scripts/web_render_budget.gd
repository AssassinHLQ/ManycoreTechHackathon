extends RefCounted
## Limit 3D pixels on high-DPI browser windows; Canvas/UI remains full resolution.
static func scale_for(size: Vector2, quality: String) -> float:
	var budget := 1280.0 * 720.0
	if quality == "low":
		budget = 960.0 * 540.0
	elif quality == "high":
		budget = 1920.0 * 1080.0
	return minf(1.0, sqrt(budget / maxf(size.x * size.y, 1.0)))
