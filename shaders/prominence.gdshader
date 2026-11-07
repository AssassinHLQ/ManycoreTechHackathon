shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 loop_color : source_color = vec3(1.0, 0.23, 0.055);
uniform float fade = 0.0;
uniform float seed = 0.0;

void fragment() {
	float flow = 0.55 + 0.45 * sin(UV.y * 26.0 - TIME * 1.6 + seed);
	float pulse = 0.72 + 0.28 * sin(TIME * 0.8 + seed * 2.0);
	float ends = smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.88, UV.y);
	ALBEDO = loop_color * (1.2 + flow * 0.55);
	ALPHA = fade * ends * (0.3 + flow * 0.3) * pulse;
}
