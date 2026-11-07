extends SceneTree
# 诊断：把两张图的差异按 16×9 网格摊开，看清到底是哪一块在变。
# 用法：godot --headless --path . --script res://tests/visual_probe.gd -- 图A 图B

const GW := 16
const GH := 9
const THRESHOLD := 14

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() < 2:
		print("用法：-- 图A 图B")
		quit(1)
		return
	var a := Image.load_from_file(ProjectSettings.globalize_path(argv[0]))
	var b := Image.load_from_file(ProjectSettings.globalize_path(argv[1]))
	if a == null or b == null:
		print("读图失败")
		quit(1)
		return
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var w := a.get_width()
	var h := a.get_height()
	if b.get_width() != w or b.get_height() != h:
		print("尺寸不同")
		quit(1)
		return

	# 每个网格里统计变化像素
	var cells := []
	for i in range(GW * GH):
		cells.append(0)
	var total := 0
	for y in range(h):
		var gy := int(float(y) / float(h) * float(GH))
		for x in range(w):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var d: float = maxf(absf(pa.r - pb.r), maxf(absf(pa.g - pb.g), absf(pa.b - pb.b)))
			if d * 255.0 > float(THRESHOLD):
				var gx := int(float(x) / float(w) * float(GW))
				cells[gy * GW + gx] += 1
				total += 1

	var cell_w := int(float(w) / float(GW))
	var cell_h := int(float(h) / float(GH))
	var cell_total := cell_w * cell_h
	print("图 %dx%d  变化像素 %d（%.3f%%）" % [w, h, total, float(total) / float(w * h) * 100.0])
	print("网格每格变化率（%d×%d，每格 %dx%d 像素）：" % [GW, GH, cell_w, cell_h])
	for gy in range(GH):
		var row := ""
		for gx in range(GW):
			var v: float = float(cells[gy * GW + gx]) / float(cell_total) * 100.0
			if v < 0.05:
				row += "  .  "
			elif v < 1.0:
				row += "  -  "
			elif v < 5.0:
				row += "  +  "
			elif v < 20.0:
				row += "  #  "
			else:
				row += "  @  "
		print("  y%d %s" % [gy, row])
	print("图例：. <0.05%  - <1%  + <5%  # <20%  @ >=20%")
	quit(0)
