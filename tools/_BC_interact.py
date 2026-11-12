# -*- coding: utf-8 -*-
"""B + C：图鉴进度与完成奖励 + 新交互类型（信标点亮）。

B = 遗迹扫描做成「图鉴/收集进度」：每扫一个显示 n/总数，扫满给奖励。
C = 新增 beacon 类型（signal-beacon 可以点亮，点亮后给一次补给）。

顺带把 A 的次数信息接进提示文案（「采集晶簇 · 燃料 +35（还剩 2 次）」）。
"""
import io
import re

P = r"scripts\main.gd"
s = io.open(P, encoding="utf-8").read()
o = s

# ═══ 1. 整块替换 _planet_interact（保留 _relic_line）═══
start = s.find("func _planet_interact() -> bool:")
assert start >= 0, "找不到 _planet_interact"
# 到 _relic_line 之前
end = s.find("## \u9057\u8ff9\u626b\u63cf\u7684\u4e00\u884c\u8bf4\u660e\u3002", start)
assert end > start, "找不到 _relic_line 注释"

new_fn = '''func _planet_interact() -> bool:
	if player == null:
		return false
	var host: Node = player.get_parent()
	if host == null or not host.has_method("nearest_interactive"):
		return false
	var spot: Dictionary = host.nearest_interactive(player.global_position, 4.0)
	if spot.is_empty():
		return false
	var index: int = int(spot.get("index", -1))
	var kind := String(spot.get("kind", ""))
	var pid := String(spot.get("id", ""))
	match kind:
		"crystal":
			player.fuel = minf(player.fuel + 35.0, 100.0)
			var left: int = host.consume_interactive(index)
			hud.show_toast("\u91c7\u96c6\u6676\u7c07 \u00b7 \u55b7\u6c14\u71c3\u6599 +35%s" % _charges_hint(left), 2.6)
			audio.play_ui(880.0)
		"cargo":
			player.oxygen = minf(player.oxygen + 30.0, 100.0)
			var left2: int = host.consume_interactive(index)
			hud.show_toast("\u62c6\u89e3\u8d27\u8231 \u00b7 \u6c27\u6c14 +30%s" % _charges_hint(left2), 2.6)
			audio.play_ui(620.0)
		"vent":
			var up: Vector3 = (player.global_position - host.global_position).normalized()
			player.velocity += up * 16.0
			host.consume_interactive(index)
			hud.show_toast("\u5730\u70ed\u6c14\u6d41\u6258\u8d77\u4f60", 2.2)
			audio.play_ui(420.0)
		"relic":
			if bool(spot.get("scanned", false)):
				hud.show_toast("\u8fd9\u5904\u9057\u8ff9\u5df2\u8bb0\u5f55\u8fc7", 2.0)
				return true
			(host.interactive_spots[index] as Dictionary)["scanned"] = true
			host.consume_interactive(index)
			var prog: Array = host.relic_progress()
			var done: int = int(prog[0])
			var total: int = int(prog[1])
			hud.show_toast("\u626b\u63cf\u8bb0\u5f55 %d/%d \u00b7 %s" % [done, total, _relic_line(pid)], 3.4)
			audio.play_ui(760.0)
			if total > 0 and done >= total:
				# \u56fe\u9274\u96c6\u6ee1\uff1a\u4e00\u6b21\u6027\u5956\u52b1
				player.fuel = 100.0
				player.oxygen = 100.0
				hud.show_toast("\u56fe\u9274\u96c6\u6ee1 \u00b7 %s \u7684\u9057\u8ff9\u5168\u90e8\u8bb0\u5f55 \u00b7 \u71c3\u6599\u4e0e\u6c27\u6c14\u5df2\u5145\u6ee1" % String(host.get("planet_id")), 4.6)
				audio.play_ui(1180.0)
		"beacon":
			if bool(spot.get("scanned", false)):
				hud.show_toast("\u4fe1\u6807\u5df2\u70b9\u4eae", 1.8)
				return true
			(host.interactive_spots[index] as Dictionary)["scanned"] = true
			host.consume_interactive(index)
			player.fuel = minf(player.fuel + 20.0, 100.0)
			player.oxygen = minf(player.oxygen + 20.0, 100.0)
			hud.show_toast("\u4fe1\u6807\u70b9\u4eae \u00b7 \u4e0a\u4e00\u8258\u8239\u7559\u4e0b\u7684\u8865\u7ed9 \u00b7 \u71c3\u6599\u6c27\u6c14 +20", 3.4)
			audio.play_ui(980.0)
		_:
			return false
	return true


## \u5145\u80fd\u5269\u4f59\u7684\u63d0\u793a\u5c3e\u5df4\uff08\u5269 0 \u6b21\u65f6\u63d0\u9192\u4f1a\u957f\u56de\u6765\uff09\u3002
func _charges_hint(left: int) -> String:
	if left <= 0:
		return "\uff08\u91c7\u7a7a\u4e86\uff0c\u8fc7\u4e00\u4f1a\u513f\u4f1a\u957f\u56de\u6765\uff09"
	if left == 1:
		return "\uff08\u8fd8\u5269 1 \u6b21\uff09"
	return "\uff08\u8fd8\u5269 %d \u6b21\uff09" % left


'''
s = s[:start] + new_fn + s[end:]

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("B+C: planet interact rewritten:", o != s)
