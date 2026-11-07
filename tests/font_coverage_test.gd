extends SceneTree
# 字体覆盖自检：扫描工程内所有会显示到界面上的文本，逐字核对内嵌字体是否覆盖。
# 用法：godot --headless --path . --script res://tests/font_coverage_test.gd
# 缺字时以退出码 1 结束，方便挂进提交前检查。

const FONT_MAIN := "res://assets/ui_font.ttf"
const FONT_SYMBOLS := "res://assets/ui_symbols.ttf"
const SCAN_EXTS := ["gd", "tscn", "tres", "cfg"]
const SKIP_DIRS := [".godot", "build", "captures", "backup"]

var supported := {}
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _load_chars(path: String) -> String:
	var font: FontFile = load(path)
	if font == null:
		return ""
	return font.get_supported_chars()


func _strip_comments(line: String) -> String:
	# 只处理行内 # 注释；字符串里出现的 # 会被误伤，但对纯文本扫描足够
	var out := ""
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote != "":
			out += c
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
			out += c
		elif c == "#":
			break
		else:
			out += c
	return out


func _quoted_text(line: String) -> String:
	# 只取引号内的内容——注释和代码标识符都不该算进上屏文字
	var out := ""
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote != "":
			if c == quote:
				quote = ""
			else:
				out += c
		elif c == "\"" or c == "'":
			quote = c
	return out


func _walk(dir_path: String, files: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if name != "." and name != ".." and not SKIP_DIRS.has(name) and not name.begins_with("."):
				_walk(full, files)
		else:
			var ext := name.get_extension().to_lower()
			if SCAN_EXTS.has(ext):
				files.append(full)
		name = d.get_next()
	d.list_dir_end()


func _run() -> void:
	var main_chars := _load_chars(FONT_MAIN)
	var symbol_chars := _load_chars(FONT_SYMBOLS)
	_check(main_chars.length() > 3000, "内嵌中文字体已加载（覆盖 %d 个字符）" % main_chars.length())
	_check(symbol_chars.length() > 0, "内嵌符号字体已加载（覆盖 %d 个字符）" % symbol_chars.length())
	for c in main_chars:
		supported[c] = true
	for c in symbol_chars:
		supported[c] = true

	var files: Array = []
	_walk("res://", files)
	var used := {}
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		if text == "":
			continue
		if f.get_extension().to_lower() == "gd":
			for line in text.split("\n"):
				for c in _quoted_text(_strip_comments(line)):
					if c.unicode_at(0) > 0x1F:
						used[c] = true
		else:
			for c in text:
				if c.unicode_at(0) > 0x1F:
					used[c] = true
	used.erase("\ufeff")

	var missing: Array = []
	for c in used:
		if not supported.has(c):
			missing.append(c)
	missing.sort()

	_check(used.size() > 300, "扫描到 %d 个上屏字符（%d 个文本文件）" % [used.size(), files.size()])
	if missing.is_empty():
		_check(true, "内嵌字体覆盖全部上屏文字")
	else:
		var sample := ""
		for c in missing:
			sample += c
		_check(false, "内嵌字体缺少 %d 个字：%s" % [missing.size(), sample])
		print("      重新生成子集后再试（见 README「字体」一节）")

	print("FONT COVERAGE TEST COMPLETE: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
