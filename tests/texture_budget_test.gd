extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	for path in [
		"res://assets/models/ship-fighter/textures/base_color.png",
		"res://assets/models/ship-fighter/textures/orm.png",
		"res://assets/models/space-station/textures/orm.png",
		"res://assets/models/space-station/textures/normal.png",
		"res://assets/models/space-station-3/textures/base_color.jpg",
		"res://assets/models/props/station/cave-crate/model_Image_0.jpg",
		"res://assets/models/props/attic-worlds/glow-mushroom/model_Image_0.jpg",
		"res://assets/models/qinglan-planet-v5/model_0.jpg"]:
		var texture := load(path) as Texture2D
		_check(texture != null, "texture resolves: " + path)
		if texture == null: continue
		var image := texture.get_image()
		_check(image != null and image.is_compressed(), "GPU-compressed data survives import: " + path)
		if image == null: continue
		_check(image.get_data_size() < texture.get_width() * texture.get_height() * 1.4 + 64, "texture stays within compressed mip budget: " + path)
		if path.ends_with("space-station/textures/orm.png"):
			_check(texture.get_width() == 1024 and texture.get_height() == 1024, "flat station ORM avoids a resident 4K map")
		else:
			var source := Image.new()
			var bytes := FileAccess.get_file_as_bytes(path)
			if path.ends_with(".png"): source.load_png_from_buffer(bytes)
			else: source.load_jpg_from_buffer(bytes)
			_check(source.get_size() == image.get_size(), "original art resolution is retained: " + path)
	print("TEXTURE BUDGET TEST COMPLETE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
