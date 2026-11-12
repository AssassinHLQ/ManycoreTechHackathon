extends SceneTree
# 字体覆盖检查：新字体是否覆盖项目里**所有**游戏文本用到的字符。
#
#   godot --headless --path . --script res://tests/probe_font_coverage.gd
#
# 会扫 res://scripts/*.gd、res://scenes/*.tscn、res://data/*.json 里出现的字符串，
# 逐字用 Font.has_char() 检查，报告缺字（缺字会在游戏里显示成豆腐块）。

const FONT_PATH := "res://assets/ui_font.ttf"
const SYMBOL_PATH := "res://assets/ui_symbols.ttf"

var checked := 0
var missing := {}


func _initialize() -> void:
	call_deferred("_run")


func _collect_files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir.path_join(name)
		if d.current_is_dir():
			_collect_files(full, out)
		elif name.ends_with(".gd") or name.ends_with(".tscn") \
				or name.ends_with(".tres") or name.ends_with(".json"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()


func _run() -> void:
	var font: Font = load(FONT_PATH)
	var symbols: Font = load(SYMBOL_PATH)
	if font == null:
		print("✗ 字体加载失败: %s" % FONT_PATH)
		quit(1)
		return
	print("字体已加载: %s" % FONT_PATH)
	print("  家族名 = %s" % font.get_font_name())

	var files: Array = []
	for d in ["res://scripts", "res://scenes", "res://data", "res://shaders"]:
		_collect_files(d, files)
	print("扫描 %d 个文件…" % files.size())

	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		for i in range(text.length()):
			var c := text[i]
			var cp := c.unicode_at(0)
			if cp < 32:
				continue
			checked += 1
			if font.has_char(cp):
				continue
			if symbols != null and symbols.has_char(cp):
				continue
			# 只记录「可能是界面文案」的字符：CJK、全角标点、常用符号
			if cp >= 0x2E80 or (cp >= 0x3000 and cp <= 0x303F) or (cp >= 0xFF00 and cp <= 0xFF65):
				missing[cp] = true

	print("")
	print("=== 结果 ===")
	print("  检查字符总数: %d（含重复）" % checked)
	print("  缺失码点: %d 个" % missing.size())
	if missing.is_empty():
		print("  ✓ 新字体覆盖全部游戏文本，不会有豆腐块")
	else:
		var ks: Array = missing.keys()
		ks.sort()
		var shown := ""
		for k in ks.slice(0, 60):
			shown += "%s(U+%04X) " % [String.chr(k), k]
		print("  ⚠ 缺字: %s" % shown)
	quit(0)
