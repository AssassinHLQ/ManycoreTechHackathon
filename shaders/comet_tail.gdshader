shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tail_color : source_color = vec4(0.55, 0.82, 1.0, 0.45);
uniform float fade_power = 1.5;
uniform float seed = 0.0;

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float head = smoothstep(0.0, 0.1, along);
	float tail = 1.0 - smoothstep(0.12, 1.0, along);
	float fade = head * pow(tail, fade_power);
	float noise = 0.8 + 0.2 * sin(UV.x * 30.0 + TIME * 0.3 + seed);
	float lateral = 0.55 + 0.45 * smoothstep(0.0, 0.35, abs(dot(normalize(NORMAL), normalize(VIEW))));
	ALBEDO = tail_color.rgb * (tail_color.a * fade * noise * lateral);
}
