# -*- coding: utf-8 -*-
"""修 A 的 parse error：instance 变量在循环之后才创建。

原写法在 set_instance_transform 的循环里直接引用 `instance`，但那行
`var instance := MultiMeshInstance3D.new()` 在循环**之后**才出现。

改法：循环里只收集「本次 flush 涉及的交互点下标」，等 instance 建好再统一绑定。
"""
import io

P = r"scripts\planet.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# 1. 循环内：改成收集到 pending 数组
old = '''			mm.set_instance_transform(i, Transform3D(basis, origin))
			mm.set_instance_color(i, e["tint"])
			# \u4ea4\u4e92\u70b9\u5efa\u7acb\u5230\u5b9e\u4f8b\u7684\u6620\u5c04\uff08\u4f9b\u91c7\u7a7a\u540e\u8c03\u6697\u7528\uff09
			if e.has("spot"):
				var si: int = int(e["spot"])
				if si >= 0 and si < interactive_spots.size():
					(interactive_spots[si] as Dictionary)["node"] = instance
					(interactive_spots[si] as Dictionary)["mi"] = i'''
assert s.count(old) == 1, "anchor1"
new = '''			mm.set_instance_transform(i, Transform3D(basis, origin))
			mm.set_instance_color(i, e["tint"])
			# \u4ea4\u4e92\u70b9\u8bb0\u4e0b\u300c\u5b9e\u4f8b\u4e0b\u6807\u300d\uff0c\u7b49 instance \u5efa\u597d\u518d\u7ed1\u5b9a\u8282\u70b9
			if e.has("spot"):
				pending_spots.append([int(e["spot"]), i])'''
s = s.replace(old, new)

# 2. 循环前声明 pending_spots
old2 = '''		mm.instance_count = entries.size()
		for i in range(entries.size()):'''
assert s.count(old2) == 1, "anchor2"
new2 = '''		mm.instance_count = entries.size()
		var pending_spots: Array = []
		for i in range(entries.size()):'''
s = s.replace(old2, new2)

# 3. instance 建好后绑定
old3 = '''		var instance := MultiMeshInstance3D.new()
		instance.name = "Prop_%s" % prop_id
		instance.multimesh = mm'''
assert s.count(old3) == 1, "anchor3"
new3 = '''		var instance := MultiMeshInstance3D.new()
		instance.name = "Prop_%s" % prop_id
		instance.multimesh = mm
		# \u628a\u4ea4\u4e92\u70b9\u7ed1\u5230\u5b9e\u4f8b\u4e0a\uff08\u91c7\u7a7a\u540e\u9700\u8981\u5355\u72ec\u8c03\u6697\u90a3\u4e00\u4e2a\uff09
		for pair in pending_spots:
			var si: int = int(pair[0])
			if si >= 0 and si < interactive_spots.size():
				(interactive_spots[si] as Dictionary)["node"] = instance
				(interactive_spots[si] as Dictionary)["mi"] = int(pair[1])'''
s = s.replace(old3, new3)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("fix instance scope:", o != s)
