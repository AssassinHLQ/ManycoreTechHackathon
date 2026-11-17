extends SceneTree
# Run headless with the same Godot build used for exports.


func _initialize() -> void:
	var text := "Godot Engine " + str(Engine.get_version_info().string) + "\n"
	text += "Bundled component copyright and licence notices.\n"
	text += "Generated from Engine.get_copyright_info() and Engine.get_license_info().\n"
	text += "https://godotengine.org/license/\n\n"
	for component in Engine.get_copyright_info():
		text += str(component.name) + "\n"
		for part in component.parts:
			text += "Files:\n" + "\n".join(part.files) + "\n"
			text += "Copyright:\n" + "\n".join(part.copyright) + "\n"
			text += "License: " + str(part.license) + "\n\n"
	var licences := Engine.get_license_info()
	var names := licences.keys()
	names.sort()
	for name in names:
		text += "\n===== " + str(name) + " =====\n\n" + str(licences[name]) + "\n"
	var output := FileAccess.open("res://assets/licenses/GODOT_THIRD_PARTY.txt", FileAccess.WRITE)
	if output == null:
		push_error("Could not write engine notices")
		quit(1)
		return
	output.store_string(text.trim_suffix("\n"))
	output.close()
	print("Engine notices written: ", text.length(), " characters")
	quit()
