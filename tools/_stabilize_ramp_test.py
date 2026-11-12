"""让 walk_test 的螺旋坡道测试不受前面步骤的残留影响。

问题：单独跑诊断脚本时四个采样点全部通过（误差 0.21~0.30 米，远小于容差 0.9），
但在 walk_test 完整流程里会随机有 1~2 个失败（64/144 轮流）。
差别在于：walk_test 前面的「地表行走」等步骤给玩家留下了地形碰撞激活状态、
以及 45 帧沉降窗口内可能仍在滑动。

修法是让这一段更严谨，而不是放宽断言：
  · 起点先把速度清零并**额外等几帧**让物理稳定
  · 沉降帧数 45 → 80（给足稳定时间，不改容差）
  · 每个采样点前清一次速度
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

T = Path(__file__).resolve().parent.parent / "tests" / "walk_test.gd"

OLD = '''	var cave: Node3D = game.home.find_child("Cave_Qinglan", true, false)
	for sample in [24, 64, 104, 144]:
		var t := float(sample) / 160.0
		var angle := PI * 0.5 - 0.30 + 0.36 * 40.0 * t
		var expected_y := lerpf(-0.2, -12.85, t)
		game.player.reparent(game.home, false)
		game.player.global_position = cave.global_transform * Vector3(cos(angle) * 8.4, expected_y + 1.2, sin(angle) * 8.4)
		game.player.velocity = Vector3.ZERO
		for i in range(45):
			await physics_frame'''

NEW = '''	var cave: Node3D = game.home.find_child("Cave_Qinglan", true, false)
	# ⚠ 2026-11-11：星球放大后这一段会随机有 1~2 个点失败，但单独诊断
	#   （probe_cave_ramp_diag.gd）四个点全过、误差仅 0.21~0.30 米。
	#   说明坡道本身没问题，是**前面几步留下的物理状态**让玩家在 45 帧内
	#   还没落稳。所以这里只加「稳定时间」，不改容差、不放宽判据。
	for sample in [24, 64, 104, 144]:
		var t := float(sample) / 160.0
		var angle := PI * 0.5 - 0.30 + 0.36 * 40.0 * t
		var expected_y := lerpf(-0.2, -12.85, t)
		game.player.reparent(game.home, false)
		game.player.velocity = Vector3.ZERO
		game.player.global_position = cave.global_transform * Vector3(cos(angle) * 8.4, expected_y + 1.2, sin(angle) * 8.4)
		# 先空跑几帧让物理服务器把新位置同步进碰撞检测
		for i in range(10):
			await physics_frame
		game.player.velocity = Vector3.ZERO
		game.player.global_position = cave.global_transform * Vector3(cos(angle) * 8.4, expected_y + 1.2, sin(angle) * 8.4)
		for i in range(80):
			await physics_frame'''

OLD2 = '''		game.player.reparent(game.home, false)
		game.player.velocity = Vector3.ZERO
		game.player.global_position = cave.global_transform * Vector3(cos(angle) * 8.4, expected_y + 1.2, sin(angle) * 8.4)
		# 先空跑几帧'''
# 旧块里 global_position 赋值只有一处，这里不需要第二段；保留占位避免误替换


def main() -> None:
    text = T.read_text(encoding="utf-8", errors="replace")
    if OLD not in text:
        print("没找到目标块")
        return
    T.write_text(text.replace(OLD, NEW), encoding="utf-8", newline="")
    print("已替换坡道测试块")


if __name__ == "__main__":
    main()
