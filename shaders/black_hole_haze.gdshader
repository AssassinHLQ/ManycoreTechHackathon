shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

// 注：与 black_hole_disk.gdshader 同样改用 cull_front。
// 这件资产的壳绕序是反的（法线朝内），cull_back 会留下远侧内表面、
// cull_disabled 会让近远两侧在加法混合下叠出三角状硬边。详见 disk 那个文件。

// 卡冈图雅：外圈尘埃 / 星尘壳。
//
// 与 black_hole_disk.gdshader 同一个病因、同一个解法：
//   原贴图（blackholelight_3 / blackholering_1）是横向条纹，在这件资产的极坐标 UV 上
//   会被切成大三角面里的直弦 —— 屏幕上就是一圈圈虚线状的暗环。
//   按半径逐像素求值后，边界天然是同心圆。
//
// 这个壳比吸积盘暗得多，只是盘面外圈的一层浮尘。

varying vec3 local_pos;

/// 本壳的内缘半径（小于它不画）
uniform float inner_radius = 0.0;
/// 本壳的外缘半径（大于它淡出）
uniform float outer_radius = 1200.0;
/// 自发光强度
uniform float energy = 0.5;
/// 色带密度（沿半径的噪声频率）
uniform float band_frequency = 0.009;
/// 色带强度
uniform float band_strength = 0.55;
/// 外缘淡出宽度（相对 outer_radius）
uniform float edge_fade = 0.35;
/// 内缘淡出宽度（相对 outer_radius）
uniform float core_fade = 0.12;

uniform vec4 dust_color : source_color = vec4(0.72, 0.62, 0.48, 1.0);
uniform vec4 outer_dust_color : source_color = vec4(0.30, 0.27, 0.26, 1.0);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float value_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 d = local_pos.xz;
	float r = length(d);

	float span = max(1.0, outer_radius - inner_radius);
	float t = clamp((r - inner_radius) / span, 0.0, 1.0);

	float bands = value_noise(r * band_frequency) * 0.62
		+ value_noise(r * band_frequency * 2.41 + 7.0) * 0.38;

	vec3 col = mix(dust_color.rgb, outer_dust_color.rgb, smoothstep(0.0, 0.85, t));
	col *= (1.0 - band_strength * bands);

	float edge = max(1.0, edge_fade * span);
	float core = max(1.0, core_fade * span);
	float fade = 1.0;
	fade *= 1.0 - smoothstep(max(0.0, outer_radius - edge), outer_radius, r);
	fade *= smoothstep(inner_radius, inner_radius + core, r);

	ALBEDO = col * energy * fade;
	ALPHA = 1.0;
}