"""自动修复 GDScript 的「未使用变量/参数」warning。

用法:
    python tools/fix_unused_warnings.py [--dry-run] [目录...]

为什么需要它:
    Godot 编辑器里会报 105 条 warning：
      "The parameter "planet" is never used in the function "_build_rim()".
       If this is intended, prefix it with an underscore: "_planet"."
      "The local variable "floor_mesh" is declared but never used..."
    GDScript 的约定是：**故意不用的变量/参数用 `_` 前缀**标明意图，
    这样 warning 消失，同时读代码的人也能看懂「这是有意留着的」。

    全部标 `@warning_ignore` 是下策 —— 那会把真正的问题也一起盖住。
    加下划线是官方推荐做法。

做法:
    1. 扫所有 .gd，找出函数体内从未被引用的参数、以及声明后从未再用的局部变量
    2. 在**声明处**给名字加 `_` 前缀
    3. 参数还要处理带默认值 / 带类型标注的形式：
         func f(planet)           -> func f(_planet)
         func f(planet: Node3D)   -> func f(_planet: Node3D)
         func f(planet = null)    -> func f(_planet = null)
    4. 只改声明，不动别处（既然没用过，就没有别处需要改）

不做的事:
    - 不碰 `_` 开头的（已经是正确写法）
    - 不碰 signals / enums / 类名
    - 不碰测试里那些「为了类型检查而存在」的变量以外的复杂情况
      （如果某个变量在字符串里被间接用到，扫描会认为它没用 —— 所以有 --dry-run）
"""
import argparse
import io
import os
import re
import sys

SKIP_DIRS = {".godot", "node_modules", "build", "demo", "__pycache__", ".git"}


def strip_comments_and_strings(src):
    """去掉注释与字符串内容，避免把注释里的变量名当成「用到了」。"""
    # 行注释
    src = re.sub(r"#.*", "", src)
    # 双引号 / 单引号字符串（不处理跨行的三引号，够用）
    src = re.sub(r'"[^"\n]*"', '""', src)
    src = re.sub(r"'[^'\n]*'", "''", src)
    return src


def find_issues(raw, clean):
    """返回 [(kind, name, line_no, indent)]，kind ∈ {param, local}。"""
    issues = []
    clines = clean.split("\n")

    # 局部变量：`var x := ...` / `var x: T = ...`
    for i, ln in enumerate(clines):
        m = re.match(r"(\s+)var\s+(\w+)\s*(?::\s*[^=]+)?\s*[:=]", ln)
        if not m:
            continue
        indent, name = m.group(1), m.group(2)
        if name.startswith("_"):
            continue
        rest = "\n".join(clines[i + 1:])
        if not re.search(r"\b" + re.escape(name) + r"\b", rest):
            issues.append(("local", name, i, len(indent)))

    # 函数参数
    for m in re.finditer(r"^(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)", clean, re.M):
        fname, params = m.group(1), m.group(2)
        if not params.strip():
            continue
        body_start = m.end()
        nxt = re.search(r"^(?:static\s+)?func\s", clean[body_start:], re.M)
        body = clean[body_start: body_start + (nxt.start() if nxt else len(clean))]
        for p in params.split(","):
            p = p.strip()
            if not p:
                continue
            pname = p.split(":")[0].split("=")[0].strip()
            if not pname or pname.startswith("_"):
                continue
            if not re.search(r"\b" + re.escape(pname) + r"\b", body):
                # 记录行号：找这个 func 在原文里的行
                line_no = clean[: m.start()].count("\n")
                issues.append(("param", pname, line_no, 0))
    return issues


def apply_fix(raw, issues):
    """在原文上按行处理：参数改 func 行，局部改 var 行。"""
    lines = raw.split("\n")
    changed = 0

    for kind, name, line_no, _indent in issues:
        if kind == "local":
            ln = lines[line_no]
            new_ln = re.sub(
                r"(\bvar\s+)" + re.escape(name) + r"\b",
                r"\1_" + name,
                ln, count=1)
            if new_ln != ln:
                lines[line_no] = new_ln
                changed += 1
        else:
            # 参数：在这一行（func 定义行）里替换参数名
            ln = lines[line_no]
            new_ln = re.sub(
                r"(\(|,\s*)" + re.escape(name) + r"(\s*[:=,)]|\s*$)",
                lambda mm: mm.group(1) + "_" + name + mm.group(2),
                ln)
            if new_ln != ln:
                lines[line_no] = new_ln
                changed += 1
    return "\n".join(lines), changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("dirs", nargs="*", default=["."])
    args = ap.parse_args()

    total_issues = 0
    total_changed = 0
    touched_files = []

    for base in args.dirs:
        for root, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for f in files:
                if not f.endswith(".gd"):
                    continue
                path = os.path.join(root, f)
                try:
                    raw = io.open(path, encoding="utf-8").read()
                except (UnicodeError, OSError):
                    continue
                clean = strip_comments_and_strings(raw)
                issues = find_issues(raw, clean)
                if not issues:
                    continue
                total_issues += len(issues)
                rel = path.replace("\\", "/")
                for kind, name, line_no, _ in issues:
                    if args.dry_run:
                        print("  %s:%d  %s %s" % (rel, line_no + 1, kind, name))
                if not args.dry_run:
                    fixed, changed = apply_fix(raw, issues)
                    if changed:
                        io.open(path, "w", encoding="utf-8", newline="\n").write(fixed)
                        total_changed += changed
                        touched_files.append(rel)
                        print("  修复 %s：%d 处" % (rel, changed))

    print()
    if args.dry_run:
        print("共发现 %d 处（dry-run，未写入）" % total_issues)
    else:
        print("共 %d 个文件、%d 处已修复" % (len(touched_files), total_changed))


if __name__ == "__main__":
    main()
