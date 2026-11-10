shader_type spatial;
// 一维星点云着色器。
//
// ⚠ 2026-11-10 踩坑记录（本文件第一版渲染全黑的教训）：
//   第一版在 `render_mode unshaded` 下写 `EMISSION = COLOR.rgb * brightness`，
//   同时用 `blend_add`。**两处都不对**：
//     · unshaded 下 EMISSION 不参与最终颜色输出，写它等于没写
//     · blend_add 对 POINTS 图元在部分后端上会让整批点消失
//   实测对比（tests/probe_shader_vs_default.gd）：
//     · 着色器版本 → 全黑
//     · StandardMaterial3D（vertex_color_use_as_albedo + UNSHADED）→ 正常
//   而 StandardMaterial3D 又没法做「颜色 × 增益」，所以还是用着色器，
//   但改成**正确的 unshaded 写法：直接输出 ALBEDO，不用 EMISSION、不用加法混合**。
//
// 做的事：
//   · ALBEDO = 顶点色 × brightness  （unshaded 下 ALBEDO 就是最终颜色）
//   · 关掉光照（unshaded）
//   · 不写深度，让后方的点也能透出来（点云的通透感）
render_mode unshaded, depth_draw_never, cull_disabled;

uniform float brightness = 1.0;

void fragment() {
    ALBEDO = COLOR.rgb * brightness;
    ALPHA = COLOR.a;
}
