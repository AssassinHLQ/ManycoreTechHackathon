"""把「平铺细节」着色器挂到 Lux3D 星球，并让网格更平滑。

用户： 「按这个来（512² 岩石/沙砾纹理，每 8 米重复，triplanar），平滑一点网格现在突兀」

两处改动：
1. 网格平滑：conform 0.80 → 0.95（顶点几乎完全跟随平滑高度表）
2. 材质：把 GLB 自带的 StandardMaterial3D 换成 planet_detail.gdshader，
   把原来的 albedo 贴图当 base_tex 传进去，叠一层程序化颗粒细节。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

P = Path(__file__).resolve().parent.parent / "scripts" / "planet.gd"

OLD_CONFORM = "	var conform := 0.80"
NEW_CONFORM = "	var conform := 0.95"

# 在 _build_lux3d_surface 返回前，给所有子网格换材质
OLD_TAIL = '''	# ── 缩放并挂上模型（模型单位 → 米）──
	_lux_root.scale = Vector3.ONE * to_world'''

NEW_TAIL = '''	# ── 换成「带平铺细节」的材质 ──
	# Lux3D 原材质是 StandardMaterial3D + 一张 2048² 包全星球的贴图
	# （每像素约 6 米），近看必然糊。这里把它的 albedo 贴图抽出来当基色，
	# 叠一层每 8 米重复的程序化颗粒（三向投影），近看就有质感了。
	_apply_detail_material()

	# ── 缩放并挂上模型（模型单位 → 米）──
	_lux_root.scale = Vector3.ONE * to_world'''

# 新增函数：插在 _median_filter_lux 之前
ANCHOR = "## 对高度表做中值滤波（经度环绕、纬度夹紧）。"

NEW_FUNC = '''## 把 Lux3D 星球的材质换成「基色贴图 + 平铺细节」。
const DETAIL_SHADER := preload("res://shaders/planet_detail.gdshader")


func _apply_detail_material() -> void:
	if _lux_root == null:
		return
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		for s in range(node.mesh.get_surface_count()):
			var src: Material = node.mesh.surface_get_material(s)
			if src == null:
				src = node.material_override
			if src == null:
				continue
			var albedo_tex: Texture2D = null
			var rough: float = 0.88
			if src is StandardMaterial3D:
				albedo_tex = (src as StandardMaterial3D).albedo_texture
				rough = clampf((src as StandardMaterial3D).roughness, 0.0, 1.0)
			if albedo_tex == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = DETAIL_SHADER
			mat.set_shader_parameter("base_tex", albedo_tex)
			mat.set_shader_parameter("detail_meters", 8.0)
			# 暗色星球（玄渊/缄默）细节弱一点，否则会显得脏
			var strength: float = 0.16 if kind in ["xuanyuan", "jianmo"] else 0.22
			mat.set_shader_parameter("detail_strength", strength)
			mat.set_shader_parameter("roughness_value", rough)
			node.mesh.surface_set_material(s, mat)


''' + ANCHOR


def main() -> None:
    text = P.read_text(encoding="utf-8", errors="replace")
    ok = 0
    if OLD_CONFORM in text:
        text = text.replace(OLD_CONFORM, NEW_CONFORM, 1)
        ok += 1
        print("✓ conform 0.80 → 0.95")
    else:
        print("✗ 没找到 conform")

    if "_apply_detail_material" in text:
        print("· 细节材质已存在，跳过")
    elif OLD_TAIL in text and ANCHOR in text:
        text = text.replace(OLD_TAIL, NEW_TAIL, 1)
        text = text.replace(ANCHOR, NEW_FUNC, 1)
        ok += 1
        print("✓ 加入细节材质")
    else:
        print("✗ 没找到挂载锚点")

    P.write_text(text, encoding="utf-8", newline="")
    print("完成 %d 处" % ok)


if __name__ == "__main__":
    main()
