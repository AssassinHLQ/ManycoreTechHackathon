# -*- coding: utf-8 -*-
"""解析已保存的 itch.io HTML，抽出素材条目。

itch.io 的每次请求可能只在 Playwright 渲染后才完整，但静态 HTML 里
game_cell 通常已经有了。这里做宽松匹配，多套正则兜底。
"""
import glob
import io
import os
import re

HTML_DIR = os.path.join("_uipkgs", "html")


def parse(html):
    items = []
    # 策略 1：找所有 itch.io 项目链接，标题取链接文字
    for m in re.finditer(
        r'href="(https://([a-z0-9\-]+)\.itch\.io/([a-z0-9\-]+))"[^>]*>(.*?)</a>',
        html, re.S | re.I,
    ):
        url, author, slug, inner = m.group(1), m.group(2), m.group(3), m.group(4)
        # 标题：去标签、压空白
        title = re.sub(r"<[^>]+>", " ", inner)
        title = " ".join(title.split())
        if not title or len(title) < 2:
            continue
        # 跳过导航/页脚
        if url in items:
            continue
        items.append((title[:60], url, author, slug))
    return items


def main():
    files = sorted(glob.glob(os.path.join(HTML_DIR, "*.html")))
    for f in files:
        with io.open(f, "r", encoding="utf-8", errors="replace") as fh:
            html = fh.read()
        items = parse(html)
        # 去重
        seen, uniq = set(), []
        for t, u, a, s in items:
            if u in seen:
                continue
            seen.add(u)
            uniq.append((t, u, a, s))

        print("\n" + "=" * 78)
        print("### %s  (%d 条)" % (os.path.basename(f), len(uniq)))
        for t, u, a, s in uniq[:40]:
            print("  · %-50s  by %s" % (t[:48], a))
            print("    %s" % u)


main()
