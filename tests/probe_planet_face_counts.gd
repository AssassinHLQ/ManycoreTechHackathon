extends SceneTree
# 统计十颗 Lux3D 星球模型的面数 / 顶点数 / 文件大小。
#   godot --headless --path . --script res://tests/probe_planet_face_counts.gd

const MODELS := {
	"qinglan": "res://assets/models/qinglan-planet-v3/model.glb",
	"zheya": "res://assets/models/zheya-lux3d/model.glb",
	"cangbo": "res://assets/models/cangbo-lux3d/model.glb",
	"xuanjing": "res://assets/models/xuanjing-lux3d/model.glb",
	"xuanyuan": "res://assets/models/xuanyuan-lux3d/model.glb",
	"baiyao": "res://assets/models/baiyao-lux3d/model.glb",
	"pansha": "res://assets/models/pansha-lux3d/model.glb",
	"taiyuan": "res://assets/models/taiyuan-lux3d/model.glb",
	"liuwu": "res://assets/models/liuwu-lux3d/model.glb",
	"jianmo": "res://assets/models/jianmo-lux3d/model.glb",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total_tris := 0
	var total_verts := 0
	var total_bytes := 0
	print("星球        三角面      顶点数      GLB")
	for id in MODELS:
		var path: String = MODELS[id]
		var packed: PackedScene = load(path)
		if packed == null:
			print("  %-8s 加载失败 %s" % [id, path])
			continue
		var node := packed.instantiate() as Node3D
		var tris := 0
		var verts := 0
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for s in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(s)
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				verts += vv.size()
				if idx != null and (idx as PackedInt32Array).size() > 0:
					tris += (idx as PackedInt32Array).size() / 3
				else:
					tris += vv.size() / 3
		var f := FileAccess.open(path, FileAccess.READ)
		var bytes := 0
		if f != null:
			bytes = f.get_length()
			f.close()
		total_tris += tris
		total_verts += verts
		total_bytes += bytes
		print("%-8s %10d %10d %8.2f MB" % [id, tris, verts, bytes / 1048576.0])
		node.free()
	print("")
	print("十颗合计：三角面 %d（%.2f M）、顶点 %d（%.2f M）、GLB %.1f MB" % [
		total_tris, total_tris / 1e6, total_verts, total_verts / 1e6,
		total_bytes / 1048576.0])
	quit(0)
