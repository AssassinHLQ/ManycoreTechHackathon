shader_type spatial;
// ── 内部「三角块」的根因与修法（2026-11-09 实测）────────────────
//
// 这几层壳（light1/light2/light3）的**绕序是反的**：实测法线几乎全部朝内
// （light3：朝外 0 个 / 朝内 7744 个；light1：20 / 13468）。
//
// 于是 `cull_disabled`（正反两面都画）配上 `blend_add`（加法混合），
// 每个像素会把这一层的**近侧和远侧各叠一次**，叠与不叠的分界线正好是这层壳
// 自己的剪影 —— 而壳的面数很少，剪影是折线，屏幕上就是一块块**三角状硬边**。
//
// 修法：只画一侧。注意不能想当然用 cull_back —— 绕序反了，cull_back 裁掉的是
// **近侧**、留下的是远侧内表面（实测截图：穹顶边缘变锯齿毛刺、颜色发灰）。
// 正确的是 `cull_front`：裁掉远侧、留下近侧，每层只剩一层，硬边随之消失。
//
// 之前试过的「按 dot(NORMAL, VIEW) 自己 discard」也是同一个符号错误，
// 同样在裁近侧，所以当时并排对比看不出改善 —— 那条路已经删掉。
render_mode unshaded, cull_front, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

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

	ALBEDO = col * energy * fade;
	ALPHA = 1.0;
}
