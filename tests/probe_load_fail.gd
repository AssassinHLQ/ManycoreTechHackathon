extends SceneTree
# 直接加载报错点名的模型，看是缓存坏了还是别的原因。
#
#   godot --headless --path . --script res://tests/probe_load_fail.gd

const PATHS := [
	"res://assets/models/props/rope-coil/model.glb",
	"res://assets/models/ship-fighter/model.glb",
	"res://assets/models/space-station/model.glb",
	"res://assets/models/space-station-3/model.glb",
	"res://assets/models/props/ore-scrap/model.glb",
	"res://assets/models/props/dune-grass/model.glb",
	"res://assets/models/props/alien-tree/model.glb",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for p in PATHS:
		var exists := ResourceLoader.exists(p)
		var res: Resource = null
		if exists:
			res = ResourceLoader.load(p)
		var sz := -1
		if res is PackedScene:
			sz = 1
		print("%-52s exists=%-5s loaded=%-5s %s" % [
			p, str(exists), str(res != null),
			"(" + res.get_class() + ")" if res != null else "\u52a0\u8f7d\u5931\u8d25"])
	quit(0)
