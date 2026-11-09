shader_type spatial;
// 内部闪烁的根源：blend_add + depth_draw_never + cull_disabled 三者叠加，
// 三角面不写深度、正反两面都画，同一像素叠了哪些面完全取决于飞船当时的角度。
// 飞船一动，重叠的三角面数量就变 —— 屏幕上那片闪烁的三角形就是这么来的。
//
// 修法：不再靠「双面全叠」，改为在 fragment 里按盘面朝向自己算一遍遮挡 ——
// 盘面是厚度几乎为零的一层，从侧面看时正面/背面会互相穿透，所以只在
// 「这一层确实朝向相机」时才画，穿透的那部分直接丢掉。
// 同时保留 blend_add（三层同心盘面本来就该加法叠加）。
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

// 卡冈图雅吸积盘：按「半径」直接求值，不采样贴图。
//
// 为什么不用贴图（这是「曲线不光滑」的真正原因，已实测）：
//   这件资产的 UV 是极坐标（v ≈ 半径），贴图上的水平色带落到盘面上本该是同心圆。
//   但壳的角向只有约 30 段、径向只有 2~11 段，三角面很大，
//   于是每条色带边界被大三角面切成**直弦** —— 屏幕上就是一圈圈多边形阶梯。
//   实测：换成纯色（不采样贴图）盘面立刻变成完美光滑的椭圆；恢复贴图立刻变回锯齿。
//
// 按半径逐像素求值则与网格密度无关：同一条半径环上的所有顶点颜色完全相同，
// 角向分多少段都看不出接缝，色带边界天然是同心圆。
//
// 用 blend_add（加法混合）而不是 blend_mix：这三层同心盘面本来就是半透明叠加的
// 丝带。加法混合与前后顺序无关（blend_mix 要按深度排序，而同一网格节点的多个
// surface 在 Compatibility 后端不保证排序），叠出来的层次也更像气体。

varying vec3 local_pos;

/// 本壳的内缘半径（小于它不画）
uniform float inner_radius = 0.0;
/// 本壳的外缘半径（大于它淡出）
uniform float outer_radius = 700.0;
/// 全局色带映射上限：所有壳共用同一个半径→颜色映射
uniform float ramp_max = 1211.0;
/// 自发光强度
uniform float energy = 1.4;
/// 色带密度（沿半径的噪声频率）
uniform float band_frequency = 0.011;
/// 色带强度：0 = 纯渐变
uniform float band_strength = 0.5;
/// 旋臂扰动幅度（相对 ramp_max），避免读成靶心
uniform float swirl_amount = 0.045;
/// 外缘淡出宽度（相对 ramp_max）
uniform float edge_fade = 0.16;
/// 内缘淡出宽度（相对 ramp_max）
uniform float core_fade = 0.05;

uniform vec4 hot_color : source_color = vec4(1.00, 0.98, 0.90, 1.0);
uniform vec4 mid_color : source_color = vec4(1.00, 0.74, 0.33, 1.0);
uniform vec4 outer_color : source_color = vec4(0.24, 0.08, 0.02, 1.0);

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
	float t = clamp(r / max(1.0, ramp_max), 0.0, 1.0);

	// ── 内部闪烁的修法 ──────────────────────────────────────────
	// 盘面厚度几乎为零，双面渲染时正反两面会在同一个像素上互相穿透。
	// 飞船一动，穿过的三角面数量就变 —— 屏幕上就是那片闪烁。
	//
	// 这里按「法线朝向」把背面丢掉：薄盘只需要画朝向相机的这一面。
	// 用 NG（几何法线，不受光照影响，unshaded 下稳定）点 V（视线方向）。
	// 盘面本身略有起伏，所以留一点容差，别把正侧对时的那圈也丢光。
	//
	// 这一步让「每个像素最多只叠到该层真正朝外的那一面」，
	// 闪烁随之消失，而加法混合的层次感保留。
	float facing = dot(normalize(NORMAL), normalize(VIEW));
	if (facing < -0.02) {
		discard;
	}

	// 旋臂扰动：同心圆加一点角向抖动，避免读成靶心
	float ang = atan(d.y, d.x);
	float rr = r + swirl_amount * ramp_max * sin(ang * 2.0 + r * 0.0032);

	// 细密丝带：沿半径的一维噪声，两层叠加
	float bands = value_noise(rr * band_frequency) * 0.62
		+ value_noise(rr * band_frequency * 2.37 + 11.0) * 0.38;

	vec3 col = mix(hot_color.rgb, mid_color.rgb, smoothstep(0.0, 0.30, t));
	col = mix(col, outer_color.rgb, smoothstep(0.30, 1.0, t));
	col *= (1.0 - band_strength * bands);

	// 内外缘淡出：宽度按 ramp_max 换算成绝对半径
	float edge = max(1.0, edge_fade * ramp_max);
	float core = max(4.0, core_fade * ramp_max);
	float fade = 1.0;
	fade *= 1.0 - smoothstep(max(0.0, outer_radius - edge), outer_radius, r);
	fade *= smoothstep(inner_radius, inner_radius + core, r);

	// 掠射角也淡一点：盘面几乎侧对相机时那一圈最容易闪
	fade *= smoothstep(0.0, 0.18, abs(facing));

	ALBEDO = col * energy * fade;
	ALPHA = 1.0;
}
