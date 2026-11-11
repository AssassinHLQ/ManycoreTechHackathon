shader_type spatial;
// 行星环：一整片扁平半透明圆盘，用径向分带 + 缝隙做出真实的环系质感。
//
// 旧实现是 3 个 TorusMesh（实心圆管、宽度只有半径 2%、三条各自倾斜），
// 视觉上就是三根橙色铁丝套装在星球外面 —— 完全没有「环」的感觉。
//
// 这里改成一片 annulus（见 planet.gd 的 _annulus_mesh），
// UV 的 v 是**径向** 0→1（内缘→外缘）、u 是角度。于是：
//   · 多层不同频率的噪声竖向叠加 → 环的分带
//   · 几处 smoothstep 挖出大缝隙（卡西尼缝那种）
//   · 内外缘淡出，环不会有一刀切的硬边
//   · 角向轻微不均，避免看起来像完美的印刷品
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha, shadows_disabled, fog_disabled;

uniform vec3 ring_light : source_color = vec3(0.80, 0.78, 0.74);
uniform vec3 ring_dark : source_color = vec3(0.38, 0.36, 0.35);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.85;
uniform float inner_fade : hint_range(0.01, 0.5) = 0.10;
uniform float outer_fade : hint_range(0.01, 0.6) = 0.20;
uniform float seed = 0.0;

varying vec2 ring_uv;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void vertex() {
	ring_uv = UV;
}

void fragment() {
	float v = ring_uv.y;          // 0 = 内缘, 1 = 外缘
	float u = ring_uv.x;          // 角度

	// ── 径向分带：三个不同频率叠起来，才有「密-疏-密」的层次 ──
	float bands = 0.0;
	bands += vnoise(v * 41.0 + seed) * 0.42;
	bands += vnoise(v * 97.0 + seed * 2.7) * 0.30;
	bands += vnoise(v * 13.0 + seed * 5.1) * 0.28;

	// ── 大缝隙：两处窄的 + 一处宽的 ──
	float gaps = 1.0;
	gaps *= smoothstep(0.004, 0.020, abs(v - 0.38) - 0.012);
	gaps *= smoothstep(0.004, 0.020, abs(v - 0.66) - 0.009);
	gaps *= smoothstep(0.010, 0.060, abs(v - 0.84) - 0.028);

	float density = bands * gaps;

	// ── 内外缘淡出，不留硬边 ──
	float edge = smoothstep(0.0, inner_fade, v) * (1.0 - smoothstep(1.0 - outer_fade, 1.0, v));

	// ── 角向轻微不均（真实环不是完全轴对称的）──
	float ang = 0.80 + vnoise(u * 29.0 + 7.3) * 0.20;

	ALBEDO = mix(ring_dark, ring_light, clamp(density, 0.0, 1.0)) * ang;
	ALPHA = clamp(density * edge * base_alpha * 1.7, 0.0, 1.0);
}
