shader_type spatial;
// 行星地表细节层：在 Lux3D 的大贴图之上叠一层**平铺的颗粒质感**。
//
// 为什么需要它：Lux3D 给的是「一张 2048² 包住整个星球」的贴图，
// 半径 2000 米的星球 → 每像素约 6.14 米。站在地面上看，脚下整片视野
// 只对应不到一个像素，所以必然是一片糊。
//
// 这里用**三向投影（triplanar）+ 程序化噪声**补细节：
//   · 噪声按物体局部坐标采样，每 detail_scale 的倒数米重复一次（默认 8 米）
//   · 按法线三个轴向加权混合，避免平面投影被拉伸
//   · 只做**亮度调制**（乘在基色上），不改色相 —— 保住 Lux3D 的配色
//   · 不需要额外贴图文件，也就没有显存和加载开销
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
// 每多少米重复一次细节（值越小越密）
uniform float detail_meters = 8.0;
uniform float detail_strength : hint_range(0.0, 0.6) = 0.30;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.88;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
// 细节偏色：让颗粒略带岩石的暖灰，而不是纯灰度
uniform vec3 detail_tint : source_color = vec3(1.02, 0.99, 0.95);
// 模型单位 -> 米的缩放（由 planet.gd 传入 to_world）
uniform float model_scale = 1.0;

varying vec3 v_local;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	// VERTEX 是模型空间单位（球半径约 0.5），乘上缩放才是真实米数
	v_local = VERTEX * model_scale;
}

void fragment() {
	vec3 base = texture(base_tex, UV).rgb;

	// 三向投影权重：按法线各轴分量取 4 次方，边缘过渡更利落
	vec3 n = normalize(NORMAL);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);

	vec3 p = v_local / max(detail_meters, 0.5);

	// 三向采样同一种噪声，各自用不同平面坐标（避免拉伸）
	float d = 0.0;
	d += vnoise(p.zyx * 9.0) * w.x;
	d += vnoise(p.xzy * 9.0) * w.y;
	d += vnoise(p.xyz * 9.0) * w.z;
	// 第二层高频，做碎石颗粒
	float d2 = vnoise(p.zyx * 34.0) * w.x
		+ vnoise(p.xzy * 34.0) * w.y
		+ vnoise(p.xyz * 34.0) * w.z;
	d = d * 0.55 + d2 * 0.45;

	// 只做亮度调制，不改色相 —— 保住 Lux3D 原本的配色
	float k = mix(1.0 - detail_strength, 1.0 + detail_strength, d);
	ALBEDO = base * k * detail_tint;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = 0.35;
}
