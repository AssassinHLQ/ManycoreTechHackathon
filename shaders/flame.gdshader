shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.78, 0.34);
uniform vec3 edge_color : source_color = vec3(1.0, 0.26, 0.04);
uniform float seed = 0.0;
uniform float strength = 1.0;
uniform float opacity = 0.85;

varying vec2 flame_uv;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	flame_uv = vec2(VERTEX.x / 0.51 * 0.5 + 0.5, VERTEX.y / 0.86 * 0.5 + 0.5);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	float t = TIME * 1.35 + seed;
	float rise = clamp(flame_uv.y, 0.0, 1.0);
	float sway = (vnoise(vec2(rise * 3.2 + seed, t * 0.7)) - 0.5) * 0.24 * rise;
	float x = abs(flame_uv.x - 0.5 + sway);
	float half_width = 0.30 * pow(max(1.0 - rise, 0.0), 0.92) + 0.055;
	float n = vnoise(vec2(flame_uv.x * 6.0 + seed, rise * 3.4 - t * 1.5));
	float body = smoothstep(half_width + 0.06, half_width * 0.28, x + n * 0.055);
	body *= smoothstep(1.0, 0.68, rise);
	body *= smoothstep(0.0, 0.08, rise);
	float heat = clamp(1.0 - rise * 1.2 - x * 1.3, 0.0, 1.0);
	ALBEDO = mix(edge_color, core_color, heat) * strength * (0.8 + n * 0.4);
	ALPHA = body * opacity;
}
