shader_type spatial;
render_mode unshaded, cull_back;

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float detail_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 p;

float hash(vec3 x) { return fract(sin(dot(x, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z
	);
}

float fbm(vec3 x) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 5; i++) {
		v += noise(x) * a;
		x = x * 2.04 + vec3(3.1, 7.2, 5.4);
		a *= 0.47;
	}
	return v;
}

void vertex() {
	p = VERTEX;
}

void fragment() {
	vec3 q = normalize(p) * 7.5;
	float flow = fbm(q + vec3(TIME * 0.055, -TIME * 0.025, TIME * 0.018));
	float cells = fbm(q * 2.4 - vec3(TIME * 0.035));
	float plasma = clamp(flow * 0.85 + cells * 0.35, 0.0, 1.0);

	vec3 dark = mix(vec3(0.72, 0.09, 0.008), vec3(0.08, 0.2, 0.8), heat);
	vec3 mid = mix(vec3(1.0, 0.38, 0.025), vec3(0.25, 0.55, 1.0), heat);
	vec3 hot = mix(vec3(1.0, 0.91, 0.46), vec3(0.8, 0.94, 1.0), heat);
	vec3 color = mix(dark, mid, smoothstep(0.18, 0.68, plasma));
	color = mix(color, hot, smoothstep(0.64, 0.96, plasma));

	// 太阳黑子：慢速漂移的磁场噪声，本影更深、半影偏暖，只在近距离 LOD 开启。
	if (detail_amount > 0.001) {
		float spot_field = fbm(q * 0.58 + vec3(19.0, 7.0, 31.0) + vec3(TIME * 0.006, TIME * 0.002, 0.0));
		float spot = smoothstep(0.63, 0.72, spot_field);
		float umbra = smoothstep(0.72, 0.80, spot_field);
		float penumbra = smoothstep(0.56, 0.64, spot_field) * (1.0 - spot);
		float spot_mix = spot * detail_amount;
		color = mix(color, color * vec3(0.40, 0.16, 0.055), spot_mix);
		color = mix(color, color * vec3(0.075, 0.032, 0.018), umbra * detail_amount);
		color += vec3(0.18, 0.045, 0.008) * penumbra * detail_amount;
	}

	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.0);
	ALBEDO = color;
	EMISSION = color * (1.35 + rim * 1.4 + heat * 0.8);
}
