shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;
uniform vec4 cloud_color : source_color = vec4(0.65, 0.85, 0.9, 0.25);
uniform float seed = 1.0;
varying vec3 p;
float hash(vec3 x) { return fract(sin(dot(x, vec3(12.9898,78.233,37.719))) * 43758.5453); }
float noise(vec3 x) {
	vec3 i=floor(x), f=fract(x); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){ p=VERTEX; }
void fragment(){
	vec3 q = normalize(p) * 12.0 + vec3(seed + TIME * 0.004, 0.0, TIME * 0.002);
	float n = noise(q) * 0.65 + noise(q * 2.7) * 0.35;
	ALBEDO = cloud_color.rgb;
	ALPHA = cloud_color.a * smoothstep(0.46, 0.72, n);
}
