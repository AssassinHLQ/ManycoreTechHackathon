shader_type sky;

// ═══ 星空的画法（v2）══════════════════════════════════════════════
//
// v1 的星空是两套并存、互相叠加的：
//   · 本着色器里的星：半径换算成视角只有約 0.05 像素，等于点采样，
//     相机一动就闪 —— 这层「假星」就是画面里那些乱跳的点。
//   · _build_starfield() 造的 2600 个 billboard 方片：做过抗锯齿
//     （star_point.gdshader 里的 boost + 通量补偿），但颜色几乎全是
//     蓝白（0.70~1.00, 0.78~1.00, 0.90~1.00，一颗暖星都没有），
//     而且完全静止。
// 两层叠在一起、颜色还不一致，观感就是「星星好多假的」。
//
// v2 把星收进这一个着色器，删掉 3D 方片层。要点：
//
//   · 抗锯齿：星不是点，是有角半径的盘。半径按「角」给（不是按像素），
//     再掐进自己所在的格子；被撑大就压暗、被压小就补亮（软能量守恒），
//     思路与 star_point.gdshader 当年的 boost/flux 一致，只是做在天上。
//   · 不跨界：每颗星只在自己那一格里算，所以半径必须 < 0.26 格，
//     并且乘一个格子窗口。否则贴图会在格边被切断，出现方块接缝。
//   · 连续色温：蓝白 → 白 → 暖橙，用一个 hash 连续插值。真实星空里
//     橙色星是明确存在的（参宿四、心宿二），v1 全偏蓝白正是最大的假处。
//   · 流动：各层绕同一条银河轴以不同角速度缓慢自转（差速 → 视差感），
//     星云做域扭曲并缓慢漂移，另有一层流星按时间槽划过。
//   · 闪烁与十字星芒都由 uniform 开关，按世界给。
//
// 精细度 sky_detail 0/1/2/3 = 低/中/高/极致，控制 fbm 倍频数、星层数、
// 超采样倍率与上述特效。分支条件都是 uniform，不产生 warp 分歧。
//
// ═══ v3：每个世界自己的云 ═══════════════════════════════════════════
//
// v2 留下的账：六个世界共用同一套 fbm，只换颜色与密度，云的轮廓是同一片。
// v3 把「形状」拆成七个按世界可调的项（见下面的 nebula_* uniform）：
// 带子朝向 / 集中度 / 噪声尺度 / 域扭曲 / 覆盖阈值 / 噪声偏移 / 银河结构权重。
// 云海的带宽压到 1，高空云于是铺满整个天，而不是像银河那样只挂一条带子。
//
// 顺带修掉一个一直存在、但没人发现的方向错误：
// 上一版的天色渐变是 mix(zenith, horizon, d.y * 0.5 + 0.5)，而 d.y 向上为正，
// 于是**天顶取到的是 horizon_color**、zenith_color 被画到了地平线以下。
// 所谓「上蓝下金的黎明」其实一直是一整片金色，蓝的天顶从来没出现过。
// 现在用 1.0 - d.y 取得方向，并加了 gradient_power 控制暖色贴地平线的陡度。
//
// 白天的高空云还换了混合方式（nebula_blend）：星云是「发光气体」，加色；
// 白天的云是「实体被照亮」，替换。加色会把云和天一起推亮，tonemap 之后
// 两者一样白，云就没有形状了 —— 云海之前那片奶油色就是这么来的。

// ── 每世界：天色与星密度 ──────────────────────────────────────────
uniform float star_density : hint_range(0.0, 2.0) = 1.0;
uniform vec3 zenith_color : source_color = vec3(0.0045, 0.0075, 0.02);
uniform vec3 horizon_color : source_color = vec3(0.011, 0.017, 0.038);
uniform float nebula_strength : hint_range(0.0, 3.0) = 1.0;
uniform float haze_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec3 haze_color : source_color = vec3(0.5, 0.52, 0.6);
// 天色渐变的陡度：1 = 线性；越大，暖色越贴着地平线，天顶留出的冷色越多。
// 黎明/黄昏要有「一条贴着地平线的金光 + 上方深色」，线性渐变画不出来。
uniform float gradient_power : hint_range(0.4, 6.0) = 1.0;
// 大尺度结构的两个颜色：太空里当星云（深蓝紫），云海里当高空云（暖白）
uniform vec3 nebula_color_a : source_color = vec3(0.035, 0.095, 0.21);
uniform vec3 nebula_color_b : source_color = vec3(0.22, 0.15, 0.3);

// ── 每世界：大尺度结构（星云 / 高空云）的**形状** ──────────────────
// 上一版六个世界共用同一套 fbm：只换颜色、密度和动态参数，云的轮廓是同一片，
// 换个世界只是「同一片云换个色调」。这里把形状拆成七个可调项，各世界各给一套：
//   axis      带子的朝向（太空的银河带 / 雪夜的云带）
//   band      带子的集中度：大 = 窄带；小到 1 = 铺满全天（云海要的就是这个）
//   scale     噪声尺度：小 = 大块团絮；大 = 细碎丝缕
//   warp      域扭曲强度：小 = 软团；大 = 长丝
//   threshold 覆盖阈值：小 = 云更多更厚；大 = 只剩几缕
//   seed      噪声偏移：同尺度下换一整套图案
//   structure 银河专属结构（尘埃带 / 亮核 / 青红斑）的权重；白天与镜界类世界为 0
// 默认值 = 太空那一套，这样漏推某个世界时回落到的仍是原来的星空。
uniform vec3 nebula_axis = vec3(0.22, 0.82, -0.46);
uniform float nebula_band : hint_range(0.4, 14.0) = 4.0;
uniform float nebula_scale : hint_range(1.0, 14.0) = 4.2;
uniform float nebula_warp : hint_range(0.0, 3.0) = 1.15;
uniform float nebula_threshold : hint_range(0.0, 0.85) = 0.32;
uniform vec3 nebula_seed = vec3(1.7, 4.2, 8.3);
uniform float nebula_structure : hint_range(0.0, 1.0) = 1.0;
// 大尺度结构怎么进画面：
//   0 = 加色（发光的气体，星空里的星云就是这样）
//   1 = 替换（被太阳照亮的实体云）。白天的云必须用这个 ——
//       加色会把云和天一起推亮，tonemap 之后两者一样白，云彻底失去形状
//       （云海上一版整片冲成奶油色，就是加色干的）。
// 替换模式下 nebula_strength 当成「最多盖住多少天」用。
uniform float nebula_blend : hint_range(0.0, 1.0) = 0.0;

// ── 精细度与动态 ────────────────────────────────────────────────
uniform int sky_detail : hint_range(0, 3) = 2;
// 一个像素对应的视角（弧度）。由 main.gd 每帧按相机 fov 与视口高度推送，
// 星盘的角半径靠它换算成像素 —— 换分辨率时星的视大小才稳定。
uniform float pixel_angle : hint_range(0.0, 0.02) = 0.00135;
// 流转速度总开关：0 = 星空静止，流星也停
uniform float flow_speed : hint_range(0.0, 3.0) = 1.0;
uniform float twinkle_amount : hint_range(0.0, 1.0) = 0.28;
uniform float meteor_rate : hint_range(0.0, 2.0) = 1.0;
uniform float spike_amount : hint_range(0.0, 2.0) = 1.0;

// ── 天空里的太阳 ──────────────────────────────────────────────
// 方向由 main.gd 按 key_light 反推后推过来，所以太阳出现的位置和投影方向一致。
// 只有需要「有太阳」的世界（云海的黎明）才打开 sun_strength。
// 太空世界不开：那里的太阳是中心的恒星本体（sun_mesh），不是一个盘。
uniform vec3 sun_direction = vec3(0.0, 0.6, 0.8);
uniform float sun_strength : hint_range(0.0, 4.0) = 0.0;
uniform float sun_angular : hint_range(0.001, 0.08) = 0.020;
uniform vec3 sun_color : source_color = vec3(1.0, 0.90, 0.70);

// 银河自转轴：所有星层绕它转，速度各不相同
// （TAU 是 Godot 着色器的内建常量，不能自己再定义一遍，否则编译报 Redefinition）
const vec3 GALAXY_AXIS = vec3(0.34, 0.86, -0.38);

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 rot_axis(vec3 v, vec3 axis, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// 归一化到「去掉的倍频不改变整体亮度」：低档位只少细节，不该整个天变暗或变亮。
// 4 倍频时 norm ≈ 1.0015，所以高档位的星云与 v1 完全一致。
float fbm(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.55;
	float norm = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) {
			break;
		}
		v += noise3(p) * a;
		norm += a;
		p = p * 2.07 + vec3(4.2, 7.1, 2.8);
		a *= 0.48;
	}
	return v / max(norm, 0.0001);
}

// 星的颜色：一个 hash 连续插值。真实星空的色温是连续谱，
// 三档硬切（v1）看起来会像贴纸。
vec3 star_tint(float t) {
	vec3 cool = vec3(0.66, 0.80, 1.00);
	vec3 midc = vec3(0.95, 0.96, 1.00);
	vec3 warm = vec3(1.00, 0.72, 0.44);
	if (t < 0.5) {
		return mix(cool, midc, smoothstep(0.0, 1.0, t * 2.0));
	}
	return mix(midc, warm, smoothstep(0.0, 1.0, (t - 0.5) * 2.0));
}

// 一层星。返回该层的加色贡献（色温、亮度、闪烁、星芒都已含在内）。
//   scale      格子尺度：越大格子越小、星越密
//   threshold  这一格里长星的机率（取反：pick < threshold 则跳过）
//   spin       绕银河轴的角速度（弧度/秒）
//   bright     这一层的整体亮度（远星层要压暗）
//   spike      十字星芒强度；0 = 不算，省下来
vec3 star_layer(vec3 d, float scale, float threshold, float seed_off,
		float spin, float bright, float twinkle, float spike) {
	vec3 rd = rot_axis(d, GALAXY_AXIS, TIME * spin * flow_speed);
	vec3 p = rd * scale;
	vec3 cell = floor(p);
	vec3 fr = fract(p) - 0.5;

	float pick = hash31(cell + vec3(seed_off));
	if (pick < threshold) {
		return vec3(0.0);
	}

	float e = hash31(cell + vec3(seed_off + 9.0));
	float energy = pow(e, 2.6);
	float tb = hash31(cell + vec3(seed_off + 4.0));

	// 角半径（弧度）→ 格子单位。夹进 [至少 0.35 像素, 0.26 格]：
	// 下界让亚像素星不会随机消失，上界保证装得进格子。
	float want = mix(0.00085, 0.00230, energy) * scale;
	float lo = 0.35 * max(pixel_angle, 1e-6) * scale;
	float hi = max(0.26, lo);
	float r = clamp(want, lo, hi);
	// 软能量守恒：被压小就补亮、被撑大就压暗（指数 0.7，比严格 2.0 更接近 v1 手感）
	float gain = pow(want / r, 0.7);

	// 星在格内的位置，偏移限制在 ±0.21 格：给半径与星芒留出装得下的余量
	vec3 center = (fract(vec3(pick, tb, e) * 6.13 + vec3(0.17, 0.41, 0.73)) - 0.5) * 0.42;
	vec3 rel = fr - center;
	float dist = length(rel);

	// 高斯核 + 淡晕，再乘格子窗口。窗口从 0.30 格开始衰减到 0.50 格归零，
	// 这样贡献绝不跨格 —— 看不到方块接缝，也不会漏掉相邻格里的星。
	float core = exp(-dist * dist / max(r * r, 1e-9) * 1.35);
	float halo = exp(-dist / max(r * 2.6, 1e-9)) * 0.16;
	float edge = max(abs(fr.x), max(abs(fr.y), abs(fr.z)));
	float shape = (core + halo) * (1.0 - smoothstep(0.30, 0.50, edge));

	// 十字星芒：只给够亮的星，长度同样夹在格子里，所以只有大格子的英雄星层看得见
	if (spike > 0.001 && energy > 0.30) {
		float w = max(r * 0.55, max(pixel_angle, 1e-6) * scale * 0.5);
		float len = min(r * 4.0, 0.24);
		float hx = max(0.0, 1.0 - abs(rel.x) / len) * max(0.0, 1.0 - abs(rel.y) / w);
		float hy = max(0.0, 1.0 - abs(rel.y) / len) * max(0.0, 1.0 - abs(rel.x) / w);
		shape += (hx + hy) * (energy - 0.30) * 0.85 * spike;
	}

	// 闪烁：每颗星自己的相位与频率。幅度随能量增大（暗星不怎么闪），
	// 并随 flow_speed 一起停。
	float tw = 1.0;
	if (twinkle > 0.001 && flow_speed > 0.001) {
		float phase = hash31(cell + vec3(seed_off + 21.0)) * TAU;
		float freq = mix(1.1, 4.3, hash31(cell + vec3(seed_off + 33.0)));
		tw = max(1.0 + sin(TIME * freq * flow_speed + phase)
			* twinkle * mix(0.30, 1.0, energy), 0.05);
	}

	return star_tint(tb) * shape * (0.16 + energy * 1.55) * gain * tw * bright;
}

// 全部星层。jitter 是超采样偏移（单位：像素），由 sky() 轮流喂进来。
vec3 star_field(vec3 d, vec2 jitter) {
	vec3 dd = d;
	if (abs(jitter.x) + abs(jitter.y) > 0.0001) {
		// 在视线切平面上偏移，切平面基底随方向走，避免极点处的退化
		vec3 up = abs(dd.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 axis_t = normalize(cross(up, dd));
		vec3 axis_b = cross(dd, axis_t);
		dd = normalize(dd + (axis_t * jitter.x + axis_b * jitter.y) * max(pixel_angle, 1e-6));
	}
	float tw = twinkle_amount;
	// 英雄星：格子极大（约 37 像素），所以装得下真正的长星芒
	//
	// ⚠ 密度配平：v1 是三层（batch 640/1700/3600），总通量被 2600 个方片那套
	// 稀释过；这里层数更多，若沿用 v1 的阈值会明显过密。所以只保留一层
	// 「常驻可见」的亮星，其余层一律推到高档位，并把阈值拉到每层只出 0.3%~0.6%。
	vec3 acc = vec3(0.0);
	if (sky_detail >= 2) {
		acc += star_layer(dd, 20.0, 0.9944, 131.0, 0.00035, 2.2, tw, spike_amount * 1.5);
	}
	// 亮星层：格子约 5 像素。这是唯一在各档位都存在的「主体」星层。
	acc += star_layer(dd, 150.0, 0.9942, 0.0, 0.00045, 0.62, tw, 0.0);
	if (sky_detail >= 2) {
		// 中星层：格子约 2.3 像素
		acc += star_layer(dd, 320.0, 0.9982, 17.0, 0.00068, 0.30, tw, 0.0);
	}
	if (sky_detail >= 3) {
		// 密星层：格子约 1.2 像素，星接近亚像素，靠超采样稳住
		acc += star_layer(dd, 620.0, 0.9990, 41.0, 0.00095, 0.14, tw, 0.0);
		// 极密星层：只给「极致」档，是真正的星尘底噪
		acc += star_layer(dd, 900.0, 0.9993, 73.0, 0.00120, 0.09, tw, 0.0);
	}
	return acc * star_density;
}

// 流星：按时间槽生成，每槽一颗，沿一条短弧划过，两端淡入淡出。
// 只在高档位开，且受 meteor_rate 控制（白天的世界设 0）。
vec3 meteor_layer(vec3 d) {
	vec3 acc = vec3(0.0);
	if (meteor_rate <= 0.001 || flow_speed <= 0.001 || sky_detail < 2) {
		return acc;
	}
	for (int i = 0; i < 2; i++) {
		float t0 = TIME / 7.0 + float(i) * 0.5;
		float slot = floor(t0);
		float u_raw = t0 - slot;
		float h0 = hash31(vec3(slot * 1.13, float(i) * 3.7, 1.3));
		float h1 = hash31(vec3(slot * 1.13, float(i) * 7.1, 5.9));
		float h2 = hash31(vec3(slot * 1.13, float(i) * 2.3, 9.1));
		float life = 0.16 + 0.16 * h0;
		if (u_raw > life) {
			continue;
		}
		// 起始方向（偏上半球）+ 切向运动方向
		vec3 origin = normalize(vec3(h0 * 2.0 - 1.0, 0.30 + h1 * 0.60, h2 * 2.0 - 1.0));
		vec3 up = abs(origin.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 tan_a = normalize(cross(up, origin));
		vec3 tan_b = cross(origin, tan_a);
		float pa = h1 * TAU;
		vec3 travel = tan_a * cos(pa) + tan_b * sin(pa);

		float u = u_raw / life;
		float head_off = (u - 0.35) * 0.16;
		float streak = 0.030 + 0.035 * h0;
		vec3 head = normalize(origin + travel * head_off);
		vec3 tail = normalize(origin + travel * (head_off - streak));

		// 点到线段的角距：用叉积模长（≈ sin 角）而不是 1 - dot。
		// 后者在点积逼近 1 时会被 float32 的精度吃掉，细线会断成一段段的。
		vec3 ab = head - tail;
		float tt = clamp(dot(d - tail, ab) / max(dot(ab, ab), 1e-9), 0.0, 1.0);
		vec3 closest = normalize(tail + ab * tt);
		float w = max(pixel_angle * 0.55, 5.0e-4);
		float glow = exp(-length(cross(d, closest)) / w);
		float head_glow = exp(-length(cross(d, head)) / (w * 3.0)) * 0.9;
		acc += vec3(1.0, 0.93, 0.82) * (glow + head_glow) * sin(u * 3.14159265) * meteor_rate;
	}
	return acc;
}

// 太阳：一个亮的盘 + 两层外晕。
// 与太阳的角距用叉积模长算（≈ sin 角），不用 1 - dot ——
// 后者在点积逼近 1 时会掉进 float32 的精度坑，盘边会出现锯齿。
vec3 sun_layer(vec3 d) {
	if (sun_strength <= 0.001) {
		return vec3(0.0);
	}
	vec3 axis_s = normalize(sun_direction);
	float ang = length(cross(d, axis_s));
	// 光晕必须收得紧。黎明天空本身就很亮，若晕开得太散，
	// 加色之后整片天一起过曝，太阳反而看不出形状（试过 6×/26×，糊成一片白）。
	// 云层也是加色，会直接把盘冲淡 —— 所以盘的亮度要压过云层，
	// 靠 tonemap 把核心夹到纯白，周围仍保持金色。
	float disc = 1.0 - smoothstep(sun_angular * 0.84, sun_angular, ang);
	float bloom = exp(-ang / max(sun_angular * 2.6, 1e-5)) * 0.25;
	float wide = exp(-ang / max(sun_angular * 9.0, 1e-5)) * 0.05;
	// 贴着地平线时压低亮度：日出前后太阳是被大气吃掉一部分的
	float low = smoothstep(-0.06, 0.16, d.y);
	return sun_color * (disc * 5.0 + bloom + wide) * sun_strength * mix(0.55, 1.0, low);
}

void sky() {
	vec3 d = normalize(EYEDIR);

	// 天色渐变的方向：d.y 向上为正（用调试图核对过 —— 画面上方 d.y ≈ +0.83）。
	// 上一版这里写的是 mix(zenith, horizon, d.y * 0.5 + 0.5)，于是**天顶拿到的是
	// horizon_color、zenith_color 反倒被画到了脚底下**：所谓「上蓝下金的黎明」
	// 实际渲染出来是一整片金色，蓝的天顶一次都没出现过。这是渐变方向反了。
	float up = clamp(d.y, 0.0, 1.0);
	float t = pow(1.0 - up, gradient_power);
	vec3 color = mix(zenith_color, horizon_color, t);

	int oct = 2;
	if (sky_detail >= 1) {
		oct = 3;
	}
	if (sky_detail >= 2) {
		oct = 4;
	}
	if (sky_detail >= 3) {
		oct = 6;
	}

	vec3 axis = normalize(nebula_axis);
	float latitude = abs(dot(d, axis));
	float band = pow(clamp(1.0 - latitude, 0.0, 1.0), nebula_band);

	// 星云：整片绕银河轴缓慢漂移（「流动」的主要来源）
	vec3 flow = rot_axis(d, GALAXY_AXIS, TIME * 0.00028 * flow_speed);

	// 域扭曲：把软斑拉成丝缕。只在中档以上做 —— 它要 3 次额外 fbm。
	// 强度按世界给：云海要软团（0.35），雪夜要长丝（1.9）。
	vec3 q = flow * nebula_scale;
	if (sky_detail >= 2) {
		q += vec3(fbm(flow * 1.7 + vec3(0.4, 2.1, 5.6), 2),
			fbm(flow * 1.9 + vec3(5.2, 1.3, 3.7), 2),
			fbm(flow * 2.1 + vec3(2.6, 7.4, 0.9), 2)) * nebula_warp;
	}
	float clouds = fbm(q + nebula_seed, oct);
	// 细节层跟着主噪声一起缩放，否则换世界时「大块」和「细纹」的比例会脱节
	float freq_ratio = nebula_scale / 4.2;
	float fine = fbm(d * 15.0 * freq_ratio + vec3(8.1, 2.4, 5.5), min(oct, 3));
	float dust = fbm(d * 7.5 * freq_ratio + vec3(3.3, 9.1, 1.2), min(oct, 3));
	float nebula = band * smoothstep(nebula_threshold, nebula_threshold + 0.52, clouds + fine * 0.22);
	vec3 nebula_color = mix(nebula_color_a, nebula_color_b, smoothstep(0.35, 0.7, fine));
	if (nebula_blend > 0.5) {
		// 白天的云：替换天空，而不是往上加光。
		// 加色时「云 + 天」的亮度和会被 tonemap 压到同一档，云的轮廓就没了；
		// 替换之后，云的亮度由云自己的颜色决定，蓝的天空和白的云各自成片。
		// 云自身带一点受光：朝太阳那一侧更亮，天顶的薄云比近地平的厚云亮一点。
		float lit = 0.90 + 0.16 * clamp(dot(d, normalize(sun_direction)), 0.0, 1.0);
		vec3 cloud_col = nebula_color * lit;
		color = mix(color, cloud_col, clamp(nebula * nebula_strength, 0.0, 1.0));
	} else {
		color += nebula_color * nebula * 1.35 * nebula_strength;
	}

	// 银河专属结构：尘埃带、亮核、青/玫红两块斑。
	// 这些只有「真的是星系」的世界才要 —— 云海的高空云里出现一条青色斑会很怪。
	if (nebula_structure > 0.001) {
		float ns = nebula_structure;

		vec3 teal_dir = normalize(vec3(0.62, -0.18, 0.68));
		float teal_blob = pow(clamp(dot(d, teal_dir), 0.0, 1.0), 14.0) * smoothstep(0.26, 0.76, fbm(d * 8.0 + vec3(5.0, 2.0, 7.0), min(oct, 3)));
		color += vec3(0.06, 0.28, 0.34) * teal_blob * 0.85 * nebula_strength * ns;

		vec3 rose_dir = normalize(vec3(-0.68, 0.34, 0.5));
		float rose_blob = pow(clamp(dot(d, rose_dir), 0.0, 1.0), 16.0) * smoothstep(0.28, 0.78, fbm(d * 9.5 + vec3(2.0, 6.0, 1.0), min(oct, 3)));
		color += vec3(0.38, 0.13, 0.28) * rose_blob * 0.7 * nebula_strength * ns;

		float lane = band * smoothstep(0.46, 0.62, dust);
		color *= 1.0 - lane * 0.32 * ns;

		float core = pow(band, 3.0) * smoothstep(0.44, 0.8, clouds);
		color += vec3(0.26, 0.21, 0.13) * core * 0.85 * nebula_strength * ns;
	}

	// 太阳：加在星云之后、星之前。加色混合无所谓遮挡顺序，
	// 放在这里只是让雾（下一段）能按距离把太阳一起吃掉。
	color += sun_layer(d);

	// 星：低档单采样，高档在像素内做旋转网格超采样，把亚像素星积成平滑亮度
	if (star_density > 0.001) {
		float n = 1.0;
		if (sky_detail >= 2) {
			n = 2.0;
		}
		if (sky_detail >= 3) {
			n = 3.0;
		}
		// 每像素转一个角度，把残留的走样变成噪点而不是摩尔纹
		float rot = hash31(d * 4096.0) * TAU;
		float cs = cos(rot);
		float sn = sin(rot);
		vec3 sum = vec3(0.0);
		int ni = int(n);
		for (int ix = 0; ix < 3; ix++) {
			if (ix >= ni) {
				break;
			}
			for (int iy = 0; iy < 3; iy++) {
				if (iy >= ni) {
					break;
				}
				vec2 grid = (vec2(float(ix), float(iy)) + 0.5) / n - 0.5;
				vec2 jitter = vec2(grid.x * cs - grid.y * sn, grid.x * sn + grid.y * cs) * 0.9;
				sum += star_field(d, jitter);
			}
		}
		color += sum / (n * n);
	}

	// 流星加在星之后、雾之前
	color += meteor_layer(d);

	// 地平线附近的一层雾/霞：给云海、雨巷这类「有大气」的世界用
	if (haze_strength > 0.001) {
		float up = clamp(d.y, 0.0, 1.0);
		float h = pow(1.0 - up, 3.0) * haze_strength;
		color = mix(color, haze_color, clamp(h, 0.0, 1.0));
	}

	COLOR = color;
}
