import io, os, re, sys, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
root = r"C:\Users\WY157\Desktop\GODOT\ManycoreTechHackathon"

modes = collections.Counter()
fmt = collections.Counter()
src_bytes = 0

for dp, dn, fn in os.walk(os.path.join(root, "assets")):
    for f in fn:
        if not f.endswith(".import"):
            continue
        p = os.path.join(dp, f)
        try:
            txt = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        m = re.search(r"compress/mode=(\d+)", txt)
        if m:
            modes[m.group(1)] += 1
        m2 = re.search(r'"imported_formats": \[([^\]]*)\]', txt)
        if m2:
            fmt[m2.group(1).strip()] += 1
        m3 = re.search(r'source_file="res://([^"]+)"', txt)
        if m3:
            sp = os.path.join(root, m3.group(1).replace("/", os.sep))
            if os.path.exists(sp):
                src_bytes += os.path.getsize(sp)

print("compress/mode 分布 (0无损 1有损 2VRAM压缩 3VRAM不压 4Basis):")
for k, v in sorted(modes.items()):
    print("   mode=%s : %d 个" % (k, v))

print()
print("已生成的 GPU 格式:")
for k, v in fmt.most_common():
    print("   %-24s : %d 个" % (k or "(空)", v))

print()
print("源图片合计: %.1f MB" % (src_bytes / 1048576))

imp = os.path.join(root, ".godot", "imported")
tot = collections.Counter()
if os.path.isdir(imp):
    for f in os.listdir(imp):
        p = os.path.join(imp, f)
        if not os.path.isfile(p):
            continue
        ext = f.rsplit(".", 1)[-1] if "." in f else "?"
        tot[ext] += os.path.getsize(p)

print()
print(".godot/imported 合计 %.1f MB" % (sum(tot.values()) / 1048576))
for k, v in tot.most_common(8):
    print("   .%-12s %8.1f MB" % (k, v / 1048576))

print()
for f in ["demo/index.pck", "demo/index.wasm", "demo/index.js"]:
    p = os.path.join(root, f.replace("/", os.sep))
    if os.path.exists(p):
        print("%-20s %8.1f MB" % (f, os.path.getsize(p) / 1048576))

# 关键项目设置
print()
pg = open(os.path.join(root, "project.godot"), encoding="utf-8", errors="replace").read()
for key in ["import_etc2_astc", "import_s3tc_bptc", "texture_mipmap"]:
    for line in pg.splitlines():
        if key in line:
            print("project.godot: " + line.strip())
