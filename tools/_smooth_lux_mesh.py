"""把 Lux3D 可视网格「贴合到平滑过的高度表」，消掉那些尖片。

用户反馈：「地上这些非常突兀的起伏怎么解决，贴图改好点能行不」
—— 不是贴图问题，是几何问题：
  · 星球半径 2000 米，起伏 ±140 米，但网格三角形边长约 25 米
    → 25 米的台阶去表达 140 米的山，必然全是尖片
  · 而且碰撞/地形查询用的是**中值平滑过**的高度表，
    可视网格用的却是 Lux3D 原始几何 —— 玩家看到的是最粗糙那份

修法：把每个顶点的**半径**朝高度表的值靠拢（UV 不动，贴图照用），
并按保角比例混合，保留一部分原始细节而不至于全糊。
最后重算一遍法线，让着色是平滑的（尖片的硬边一半来自法线不连续）。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIP = Path(__file__).resolve().parent.parent / "scripts" / "planet.gd"

OLD = '''	var touched := 0
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue'''

NEW = '''	var touched := 0
	# ⚠ 2026-11-11 额外一步：把**所有**顶点朝高度表靠拢，消掉尖片。
	#   混入比例 MESH_CONFORM：1 = 完全跟随平滑高度表（最平），0 = 原始几何。
	var conform := 0.80
	for mi in _lux_root.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue'''

OLD2 = '''			for i in range(verts.size()):
				var v: Vector3 = verts[i]
				var r: float = v.length()
				if r < 0.000001:
					continue
				var dir: Vector3 = v / r
				var angular: float = acos(clampf(dir.dot(site_dir), -1.0, 1.0))
				if angular >= pad_outer:
					continue'''

NEW2 = '''			for i in range(verts.size()):
				var v: Vector3 = verts[i]
				var r: float = v.length()
				if r < 0.000001:
					continue
				var dir: Vector3 = v / r
				# ① 先朝平滑高度表靠拢（全星球范围，消尖片）
				var smooth_r: float = _sample_lux_map(_lux_height_map, dir)
				var blended: float = lerpf(r * to_world, smooth_r, conform)
				# ② 站点附近再压平（原有逻辑，保持不变）
				var angular: float = acos(clampf(dir.dot(site_dir), -1.0, 1.0))
				if angular < pad_outer:
					var blend: float = 1.0 - smoothstep(pad_angle, pad_outer, angular)
					blended = lerpf(blended, site_h, blend)
				verts[i] = dir * (blended / to_world)
				changed_any = true
				touched += 1
			arrays[Mesh.ARRAY_VERTEX] = verts
			# 顶点动过之后重算法线：尖片的硬边一半来自法线不连续，
			# 平滑法线能让起伏看起来像丘陵而不是碎玻璃。
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
			st.generate_normals()
			var rebuilt := st.commit()
			var mat2: Material = node.mesh.surface_get_material(s)
			if mat2 != null:
				rebuilt.surface_set_material(s, mat2)
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
				rebuilt.surface_get_arrays(0))
			if mat2 != null:
				new_mesh.surface_set_material(s, mat2)
			continue'''

OLD3 = '''				# 当前世界半径 → 目标世界半径 → 折算回模型局部单位
				var cur_world: float = r * to_world
				var target_world: float = lerpf(cur_world, site_h, blend)
				verts[i] = dir * (target_world / to_world)
				changed_any = true
				touched += 1
			arrays[Mesh.ARRAY_VERTEX] = verts
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			# 保住原材质
			var mat: Material = node.mesh.surface_get_material(s)
			if mat != null:
				new_mesh.surface_set_material(s, mat)'''

NEW3 = ''''''


def main() -> None:
    text = SHIP.read_text(encoding="utf-8", errors="replace")
    ok = 0
    for old, new, label in (
        (OLD, NEW, "加 conform 系数"),
        (OLD2, NEW2, "顶点朝高度表靠拢 + 重算法线"),
        (OLD3, NEW3, "移除旧的逐顶点块"),
    ):
        if old in text:
            text = text.replace(old, new, 1)
            ok += 1
            print("✓", label)
        else:
            print("✗ 没找到：", label)
    SHIP.write_text(text, encoding="utf-8", newline="")
    print("%d/3" % ok)


if __name__ == "__main__":
    main()
