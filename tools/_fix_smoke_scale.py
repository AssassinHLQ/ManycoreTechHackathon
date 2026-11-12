import io

p = r"tests\smoke_test.gd"
s = io.open(p, encoding="utf-8").read()
o = s

old = (
    "\tvar ray_from: Vector3 = game.home.global_position "
    "+ game.home.surface_position(game.home.cave_direction, 14.0)\n"
    "\tvar ray_to: Vector3 = game.home.global_position "
    "+ game.home.surface_position(game.home.cave_direction, -22.0)"
)
new = (
    "\t# \u26a0 2026-11-11 B \u65b9\u6848\uff1a\u6d1e\u7a74\u6574\u4f53\u6309 prop_scale\uff08\u00d75\uff09\u653e\u5927\uff0c"
    "\u4e95\u6df1\u4ece 13 \u7c73\u53d8 65 \u7c73\u3002\n"
    "\t#   \u8fd9\u4e24\u4e2a\u9ad8\u5ea6\u662f**\u4e16\u754c\u7a7a\u95f4\u7684\u7edd\u5bf9\u7c73\u6570**\uff0c"
    "\u5fc5\u987b\u8ddf\u7740\u653e\u5927\uff0c\u5426\u5219\u5c04\u7ebf\u53ea\u6253\u5230 -22 \u7c73\n"
    "\t#   \uff08= \u6d1e\u5c40\u90e8 -4.4 \u7c73\uff09\uff0c\u538b\u6839\u591f\u4e0d\u5230\u6d1e\u5e95\u3002\n"
    "\t#   \u6ce8\u610f\u4e0b\u9762 cave_local.y \u7684\u9608\u503c\u4e0d\u7528\u6539 \u2014\u2014 "
    "\u90a3\u662f cave \u5c40\u90e8\u7a7a\u95f4\uff0c\u7f29\u653e\u5df2\u88ab\u62b5\u6d88\u3002\n"
    "\tvar cave_scale: float = game.home.prop_scale if game.home.prop_scale > 0.0 else 1.0\n"
    "\tvar ray_from: Vector3 = game.home.global_position "
    "+ game.home.surface_position(game.home.cave_direction, 14.0 * cave_scale)\n"
    "\tvar ray_to: Vector3 = game.home.global_position "
    "+ game.home.surface_position(game.home.cave_direction, -22.0 * cave_scale)"
)
assert s.count(old) == 1, "cave ray anchor"
s = s.replace(old, new)

old2 = (
    "\tvar ship_distance: float = game.player.global_position"
    ".distance_to(game.ship.global_position)\n"
    "\t_check(ship_distance < 9.0 and ship_distance > 2.0, \"player wakes beside the parked ship\")"
)
new2 = (
    "\tvar ship_distance: float = game.player.global_position"
    ".distance_to(game.ship.global_position)\n"
    "\t# \u26a0 2026-11-11 B \u65b9\u6848\uff1a\u7ad9\u70b9\u5e03\u5c40\uff08\u98de\u8239\u505c 30 \u7c73\u3001"
    "\u51fa\u751f\u70b9 35.5 \u7c73\uff09\u4e5f\u6309 prop_scale\n"
    "\t#   \u653e\u5927\u4e86 5 \u500d\uff0c\u4e24\u70b9\u95f4\u8ddd\u968f\u4e4b\u53d8\u6210 ~32 \u7c73\u3002"
    "\u4e0a\u9650\u6309\u5c3a\u5ea6\u653e\u5bbd\uff0c\u4e0b\u9650\u4fdd\u7559 2 \u7c73\n"
    "\t#   \uff08\u4ecd\u7136\u8981\u6c42\u300c\u51fa\u751f\u5c31\u5728\u8239\u8fb9\u4e0a\uff0c"
    "\u4e0d\u662f\u9694\u4e86\u534a\u4e2a\u661f\u7403\u300d\uff09\u3002\n"
    "\tvar wake_limit: float = 9.0 * "
    "(game.home.prop_scale if game.home.prop_scale > 0.0 else 1.0)\n"
    "\t_check(ship_distance < wake_limit and ship_distance > 2.0, "
    "\"player wakes beside the parked ship\")"
)
assert s.count(old2) == 1, "ship distance anchor"
s = s.replace(old2, new2)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("smoke_test.gd updated:", o != s)
