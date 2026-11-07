shader_type spatial;
render_mode cull_back;

uniform vec4 base_color : source_color = vec4(0.2, 0.4, 0.3, 1.0);
uniform vec4 accent_color : source_color = vec4(0.4, 0.8, 0.7, 1.0);
uniform int biome = 0;
uniform float seed = 1.0;
varying vec3 local_pos;
varying vec3 local_normal;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1,0,0)), f.x), mix(hash31(i + vec3(0,1,0)), hash31(i + vec3(1,1,0)), f.x), f.y), mix(mix(hash31(i + vec3(0,0,1)), hash31(i + vec3(1,0,1)), f.x), mix(hash31(i + vec3(0,1,1)), hash31(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float value = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 5; i++) {
		value += noise3(p) * amp;
		p = p * 2.03 + vec3(7.1, 3.4, 5.8);
		amp *= 0.48;
	}
	return value;
}
void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}
void fragment() {
	vec3 p = local_pos * 0.055 + vec3(seed * 3.17);
	float broad = fbm(p * 0.45);
	float detail = noise3(p * 8.0);
	float ridge = abs(noise3(p * 2.4) * 2.0 - 1.0);
	float slope = 1.0 - abs(normalize(local_normal).y);
	vec3 color = base_color.rgb;
	float rough = 0.92;
	float emission = 0.0;
	if (biome == 0) {
		float grove = smoothstep(0.35, 0.75, broad);
		vec3 moss = mix(base_color.rgb * 0.42, base_color.rgb * 1.35, broad);
		vec3 stone = vec3(0.22, 0.24, 0.22) * (0.72 + detail * 0.45);
		float rock = smoothstep(0.74, 0.92, ridge) * 0.55;
		color = mix(moss, stone, rock);
		color = mix(color, color * 1.15, grove * 0.5);
		color += vec3(0.018, 0.03, 0.014) * detail;
	} else if (biome == 1) {
		float cracks = smoothstep(0.055, 0.0, abs(noise3(p * 1.6) - 0.5));
		color = mix(base_color.rgb * (0.45 + broad * 0.65), vec3(0.12, 0.09, 0.1), ridge);
		color = mix(color, vec3(1.0, 0.19, 0.025), cracks * 0.9);
		emission = cracks * 2.4;
		rough = 0.78;
	} else if (biome == 2) {
		float waves = sin(local_pos.x * 0.11 + TIME * 0.35) * sin(local_pos.z * 0.09 - TIME * 0.28);
		color = mix(base_color.rgb * 0.55, accent_color.rgb * 0.85, broad * 0.65 + waves * 0.06);
		color += vec3(0.08, 0.16, 0.18) * detail;
		rough = 0.3;
	} else if (biome == 3) {
		float veins = smoothstep(0.035, 0.0, abs(noise3(p * 2.2) - 0.52));
		color = mix(base_color.rgb * (0.55 + broad), vec3(0.22, 0.18, 0.28), ridge * 0.6);
		color = mix(color, accent_color.rgb * 1.25, veins * 0.7);
		emission = veins * 0.85;
	} else if (biome == 5) {
		// 盐碱裂谷：白盐壳 + 深色裂谷 + 间歇喷泉的暖斑
		float rift = smoothstep(0.05, 0.0, abs(noise3(p * 1.9) - 0.5));
		float crust = smoothstep(0.45, 0.85, broad);
		color = mix(base_color.rgb * (0.72 + broad * 0.5), base_color.rgb * 1.35, crust * 0.7);
		color = mix(color, base_color.rgb * 0.28, rift * 0.85);
		color += accent_color.rgb * smoothstep(0.88, 0.97, detail) * 0.30;
		emission = smoothstep(0.92, 0.99, detail) * 0.35;
		rough = 0.95;
	} else if (biome == 6) {
		// 冰架 + 潮汐裂缝：淡蓝冰面 + 深青裂缝
		float crack = smoothstep(0.04, 0.0, abs(noise3(p * 2.6) - 0.5));
		float plate = smoothstep(0.4, 0.8, broad);
		color = mix(base_color.rgb * 0.9, base_color.rgb * 1.25, plate * 0.75);
		color = mix(color, accent_color.rgb * 0.6, crack * 0.9);
		color += accent_color.rgb * 0.05 * detail;
		emission = crack * 0.22;
		rough = 0.42;
	} else if (biome == 7) {
		// 环站残骸带：灰壤 + 金属碎片 + 微弱磁辉
		float shard = smoothstep(0.68, 0.92, ridge);
		float ore = smoothstep(0.035, 0.0, abs(noise3(p * 3.1) - 0.5));
		color = mix(base_color.rgb * (0.5 + broad * 0.7), vec3(0.58, 0.60, 0.63) * (0.8 + detail * 0.45), shard * 0.75);
		color = mix(color, accent_color.rgb * 1.1, ore * 0.6);
		emission = ore * 0.55;
		rough = 0.68;
	} else if (biome == 8) {
		// 坍缩暗核：近黑表面 + 环带辉光（黑洞前奏的样子）
		float band = smoothstep(0.9, 0.2, abs(local_pos.y) / 170.0);
		float ring = smoothstep(0.05, 0.0, abs(fract(local_pos.y * 0.016) - 0.5));
		color = mix(vec3(0.015, 0.016, 0.022), base_color.rgb * 0.9, broad * 0.55);
		color = mix(color, accent_color.rgb * 1.3, ring * 0.4);
		emission = ring * 0.55 + band * 0.12;
		rough = 0.32;
	} else if (biome == 9) {
		// 白曜星：白垩冰原。高反照白 + 霜蚀沟槽 + 冰晶亮点。
		float rime = smoothstep(0.055, 0.0, abs(noise3(p * 2.1) - 0.5));
		float crust = smoothstep(0.35, 0.82, broad);
		color = mix(base_color.rgb, vec3(0.93, 0.96, 0.99), crust * 0.75);
		color = mix(color, accent_color.rgb * 0.72, rime * 0.55);
		color += vec3(0.045, 0.055, 0.07) * detail;
		emission = rime * 0.10;
		rough = 0.34;
	} else if (biome == 10) {
		// 磐砂星：风蚀沙海。顺风拉丝的沙脊 + 深色砾岩。
		float dune = sin(p.y * 3.1 + noise3(p * 1.4) * 6.2);
		float grit = smoothstep(0.6, 0.95, ridge);
		color = mix(base_color.rgb * 0.88, base_color.rgb * 1.32, 0.5 + dune * 0.2);
		color = mix(color, vec3(0.30, 0.24, 0.19), grit * 0.7);
		color += accent_color.rgb * 0.06 * detail;
		rough = 0.98;
	} else if (biome == 11) {
		// 苔垣星：苔原湿地。苔绿斑块 + 裸岩 + 湿润高光。
		float sod = smoothstep(0.30, 0.72, broad);
		float wet = smoothstep(0.045, 0.0, abs(noise3(p * 1.7) - 0.5));
		color = mix(vec3(0.15, 0.19, 0.13), base_color.rgb * 1.28, sod);
		color = mix(color, accent_color.rgb * 0.52, wet * 0.35);
		color = mix(color, vec3(0.26, 0.27, 0.24), smoothstep(0.72, 0.95, ridge) * 0.6);
		emission = wet * 0.06;
		rough = mix(0.62, 0.92, 1.0 - wet);
	} else if (biome == 12) {
		// 硫坞星：硫磺结晶 + 火山灰 + 喷气孔暖斑。
		float sulfur = smoothstep(0.60, 0.88, broad);
		float vent = smoothstep(0.93, 0.995, detail);
		color = mix(vec3(0.15, 0.14, 0.12), base_color.rgb * 1.22, sulfur);
		color = mix(color, accent_color.rgb * 0.82, sulfur * 0.35);
		color = mix(color, vec3(0.05, 0.09, 0.07), smoothstep(0.7, 0.95, ridge) * 0.8);
		emission = vent * 0.85 + sulfur * 0.05;
		rough = 0.88;
	} else if (biome == 13) {
		// 缄默星：黑曜石玻璃面 + 细裂隙微光。
		float flint = smoothstep(0.03, 0.0, abs(noise3(p * 3.4) - 0.5));
		color = mix(vec3(0.020, 0.018, 0.026), base_color.rgb * 1.05, broad * 0.6);
		color = mix(color, accent_color.rgb * 0.85, flint * 0.55);
		emission = flint * 0.32;
		rough = 0.16;
	} else {
		float glyphs = smoothstep(0.025, 0.0, abs(noise3(p * 3.5) - 0.5));
		color = mix(base_color.rgb * (0.45 + broad * 0.5), accent_color.rgb * 0.4, glyphs * 0.35);
		emission = glyphs * 0.18;
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	EMISSION = accent_color.rgb * emission;
	SPECULAR = (biome == 2 || biome == 6) ? 0.75 : ((biome == 13) ? 1.0 : ((biome == 9) ? 0.6 : 0.28));
}
