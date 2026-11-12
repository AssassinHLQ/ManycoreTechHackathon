# -*- coding: utf-8 -*-
"""批量核实 OpenGameArt 上一批 UI 包：许可证 + 文件清单 + 预览图。

只输出结论，不打印整页 HTML，省 token。
"""
import re
import time
import urllib.request

SLUGS = [
    "sci-fi-user-interface",
    "ui-resources",
    "cc0-ui",
    "2duihudskin",
    "ui-elements-1",
    "user-interface-ui-art-collection",
    "type-interface-assets",
    "gui-elements-2",
]

UA = {"User-Agent": "Mozilla/5.0"}


def fetch(u, t=30):
    return urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=t).read().decode("utf-8", "replace")


for slug in SLUGS:
    url = "https://opengameart.org/content/" + slug
    try:
        h = fetch(url)
    except Exception as e:
        print("%-36s ERR %s" % (slug, e))
        continue

    t = re.search(r"<title>(.*?)</title>", h, re.S)
    title = t.group(1).split("|")[0].strip() if t else slug
    lics = sorted(set(re.findall(r"license_images/([A-Za-z0-9_\-]+)\.png", h)))
    a = re.search(r'Author:\s*(?:&nbsp;)*\s*<a href="/users/[^"]+">([^<]+)</a>', h)
    author = a.group(1).strip() if a else "?"
    # 预览大图
    prev = re.findall(r'href="(https://opengameart\.org/sites/default/files/[^"]+\.(?:png|jpg|jpeg))"', h)
    prev = [p for p in prev if "/styles/" not in p][:3]
    # 打包下载
    zips = re.findall(r'href="(https://opengameart\.org/sites/default/files/[^"]+\.zip)"', h)
    # 标签里有没有 dark
    tags = sorted(set(re.findall(r"field_art_tags_tid=([A-Za-z0-9%\.\-]+)", h)))
    dark = any("dark" in x.lower() for x in tags)

    print("\n=== %s" % title[:64])
    print("    slug   : %s" % slug)
    print("    author : %s" % author)
    print("    lic    : %s%s" % (", ".join(lics) or "?", "   [含 dark 标签]" if dark else ""))
    print("    zip    : %s" % (zips[0] if zips else "-"))
    if prev:
        print("    preview: %s" % prev[0])
    time.sleep(0.4)
