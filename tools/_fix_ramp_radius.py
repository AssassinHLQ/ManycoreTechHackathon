import io
import re

# 坡道半径在 underground.gd 里是 shaft_radius - 2.2，
# 而 shaft_radius = planet.cave_mouth_radius + 0.6
# => 坡道半径 = cave_mouth_radius - 1.6
RAMP_EXPR = "ramp_radius"

# ─── smoke_test.gd ───
p = r"tests\smoke_test.gd"
s = io.open(p, encoding="utf-8").read()
o = s

old = (
    "\tvar ramp_angle := PI * 0.5 - 0.30 + 0.15\n"
    "\tvar ramp_from: Vector3 = cave.global_transform * "
    "Vector3(cos(ramp_angle) * 8.4, 2.5, sin(ramp_angle) * 8.4)\n"
    "\tvar ramp_to: Vector3 = cave.global_transform * "
    "Vector3(cos(ramp_angle) * 8.4, -3.0, sin(ramp_angle) * 8.4)"
)
new = (
    "\tvar ramp_angle := PI * 0.5 - 0.30 + 0.15\n"
    "\t# \u26a0 2026-11-11 B \u65b9\u6848\uff1a\u5761\u9053\u534a\u5f84\u4e0d\u80fd\u5199\u6b7b\u3002\n"
    "\t#   underground.gd\uff1aramp_radius = shaft_radius - 2.2\uff0c"
    "shaft_radius = cave_mouth_radius + 0.6\n"
    "\t#   => ramp_radius = cave_mouth_radius - 1.6\u3002\n"
    "\t#   \u65e7\u503c 8.4 \u662f\u6309\u300c\u7ad6\u4e95 10.6 - 2.2\u300d\u7b97\u51fa\u6765\u7684\uff0c"
    "\u73b0\u5728\u7ad6\u4e95 = 53\uff0c\u5761\u9053\u5728 51.4 \u7c73\u5904\u3002\n"
    "\tvar " + RAMP_EXPR + ": float = cave.global_transform.basis.get_scale().x "
    "* (game.home.cave_mouth_radius - 1.6)\n"
    "\tvar ramp_from: Vector3 = cave.global_transform * "
    "Vector3(cos(ramp_angle) * " + RAMP_EXPR + ", 2.5, sin(ramp_angle) * " + RAMP_EXPR + ")\n"
    "\tvar ramp_to: Vector3 = cave.global_transform * "
    "Vector3(cos(ramp_angle) * " + RAMP_EXPR + ", -3.0, sin(ramp_angle) * " + RAMP_EXPR + ")"
)
assert s.count(old) == 1, "smoke ramp anchor"
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("smoke_test.gd ramp radius:", o != s)

# ─── walk_test.gd ───
p2 = r"tests\walk_test.gd"
w = io.open(p2, encoding="utf-8").read()
wo = w

# 在采样循环前插入一次 ramp_radius 计算
anchor = "\tfor "
# 找到包含 8.4 的那几行的上下文，插入变量
lines = w.split("\n")
insert_at = None
for i, line in enumerate(lines):
    if "8.4" in line:
        insert_at = i
        break
assert insert_at is not None, "walk ramp line not found"

# 找到包含这行的 for 循环起点，把 ramp_radius 插到循环之前
loop_start = None
for i in range(insert_at, -1, -1):
    if lines[i].strip().startswith("for "):
        loop_start = i
        break
assert loop_start is not None, "walk loop not found"

decl = [
    "\t# \u26a0 2026-11-11 B \u65b9\u6848\uff1a\u5761\u9053\u534a\u5f84 = cave_mouth_radius - 1.6",
    "\t#   \uff08underground.gd: shaft_radius - 2.2\uff0c\u800c shaft_radius = "
    "cave_mouth_radius + 0.6\uff09\u3002",
    "\t#   \u8fd9\u91cc\u7684\u5750\u6807\u662f cave \u5c40\u90e8\u7a7a\u95f4\uff0c\u6240\u4ee5\u76f4\u63a5\u7528"
    " cave_mouth_radius \u63a8\u5bfc\u5373\u53ef\u3002",
    "\tvar ramp_radius: float = game.home.cave_mouth_radius - 1.6",
]
lines[loop_start:loop_start] = decl
w = "\n".join(lines)
w = w.replace("cos(angle) * 8.4", "cos(angle) * ramp_radius")
w = w.replace("sin(angle) * 8.4", "sin(angle) * ramp_radius")
io.open(p2, "w", encoding="utf-8", newline="\n").write(w)
print("walk_test.gd ramp radius:", wo != w)
