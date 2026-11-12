# -*- coding: utf-8 -*-
"""整块重写 LANDFORM_PROPS（旧条目 + 第四批 8 条），避免嵌套错位。

教训：脚本按字符串裁剪多行表容易把新条目塞进内层数组。
这类表直接整块重写最稳，写完用 --check-only 验证。
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

BLOCK = '''const LANDFORM_PROPS := {
	"qinglan": [["rock-cluster", 1, 26, 34, false], ["lf-ridge-spine", 1, 26, 40, false],
		["lf-boulder-field", 1, 26, 40, false]],
	"zheya": [["rock-spire", 2, 28, 42, false], ["lf-canyon-wall", 1, 28, 46, false],
		["lf-lava-flow", 1, 28, 46, false], ["stone-bridge", 1, 14, 26, false]],
	"cangbo": [["floating-rock", 2, 26, 38, false], ["lf-mesa-plateau", 1, 28, 44, false],
		["lf-glacier-wall", 1, 28, 46, false]],
	"xuanjing": [["floating-rock", 3, 26, 42, false], ["lf-ridge-spine", 1, 26, 40, false],
		["lf-sinkhole", 1, 28, 44, false]],
	"xuanyuan": [["rock-spire", 2, 30, 46, false], ["lf-crater-rim", 1, 26, 42, false],
		["stone-bridge", 1, 14, 26, false]],
	"baiyao": [["rock-spire", 2, 28, 44, false], ["lf-canyon-wall", 1, 28, 46, false],
		["lf-glacier-wall", 1, 28, 46, false]],
	"pansha": [["rock-spire", 3, 30, 48, false], ["lf-natural-arch", 1, 26, 40, false],
		["lf-dry-riverbed", 1, 26, 42, false]],
	"taiyuan": [["rock-cluster", 2, 26, 36, false], ["lf-ridge-spine", 1, 26, 40, false],
		["lf-crater-rim", 1, 26, 40, false]],
	"liuwu": [["rock-spire", 1, 28, 40, false], ["lf-canyon-wall", 1, 28, 46, false],
		["lf-lava-flow", 1, 28, 46, false], ["stone-bridge", 1, 14, 26, false]],
	"jianmo": [["rock-spire", 3, 30, 48, false], ["floating-rock", 1, 26, 38, false],
		["lf-crater-rim", 1, 26, 42, false], ["stone-bridge", 1, 14, 26, false]],
	"jiangxiao": [["rock-spire", 2, 28, 44, false], ["lf-mesa-plateau", 1, 28, 44, false],
		["lf-cliff-terraces", 1, 28, 46, false]],
	"cangwu": [["rock-cluster", 2, 26, 36, false], ["lf-ridge-spine", 1, 26, 40, false],
		["lf-sinkhole", 1, 26, 42, false]],
	"jinwu": [["rock-cluster", 2, 26, 34, false], ["lf-mesa-plateau", 1, 28, 44, false],
		["lf-salt-flat", 1, 26, 42, false]],
	"yuheng": [["crystal-cluster", 2, 26, 40, false], ["lf-cliff-terraces", 1, 26, 44, false]],
	"sue": [["rock-spire", 2, 26, 40, false], ["lf-canyon-wall", 1, 28, 46, false],
		["lf-boulder-field", 1, 26, 40, false]],
	"danxia": [["rock-cluster", 2, 26, 38, false], ["rock-spire", 1, 30, 44, false],
		["lf-natural-arch", 1, 26, 40, false], ["lf-cliff-terraces", 1, 28, 46, false],
		["stone-bridge", 1, 14, 26, false]],
	"biluo": [["floating-rock", 2, 26, 40, false], ["lf-natural-arch", 1, 26, 40, false],
		["lf-salt-flat", 1, 26, 40, false]],
	"youdu": [["crystal-cluster", 2, 26, 42, false], ["lf-canyon-wall", 1, 28, 46, false],
		["lf-glacier-wall", 1, 28, 46, false]],
	"yaoguang": [["crystal-cluster", 3, 26, 42, false], ["floating-rock", 1, 26, 38, false],
		["lf-ridge-spine", 1, 26, 40, false], ["lf-crater-rim", 1, 26, 42, false]],
	"xuanpu": [["rock-cluster", 1, 26, 36, false], ["crystal-cluster", 1, 26, 40, false],
		["lf-dry-riverbed", 1, 26, 40, false]],
}
'''

start = s.find("const LANDFORM_PROPS := {")
assert start >= 0, "start"
end = s.find("\n}\n", start)
assert end > start, "end"
s = s[:start] + BLOCK + s[end + 3:]

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("LANDFORM_PROPS rewritten:", o != s)
