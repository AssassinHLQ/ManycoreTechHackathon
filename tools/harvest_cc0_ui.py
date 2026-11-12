# -*- coding: utf-8 -*-
"""批量收割 OpenGameArt 上的 CC0 UI 包：搜索 -> 筛许可证 -> 下 zip -> 解包。

目标：最快速度堆出一批可商用 UI 素材，让作者有得挑。
只收 CC0（零义务、可改、可商用、不用署名），避免任何授权踩坑。
"""
import io
import os
import re
import sys
import time
import urllib.request
import zipfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0"}
OUT = os.path.join("_uipkgs", "harvest")
os.makedirs(OUT, exist_ok=True)

# 2D Art = 9
SEARCHES = [
    "https://opengameart.org/art-search-advanced?keys=ui&field_art_type_tid%5B%5D=9&field_art_licenses_tid%5B%5D=4&sort_by=count&sort_order=DESC",
    "https://opengameart.org/art-search-advanced?keys=interface&field_art_type_tid%5B%5D=9&field_art_licenses_tid%5B%5D=4&sort_by=count&sort_order=DESC",
    "https://opengameart.org/art-search-advanced?keys=hud&field_art_type_tid%5B%5D=9&field_art_licenses_tid%5B%5D=4&sort_by=count&sort_order=DESC",
    "https://opengameart.org/art-search-advanced?keys=sci-fi+gui&field_art_type_tid%5B%5D=9&sort_by=count&sort_order=DESC",
]

MAX_PACKS = 18


def fetch(u, t=40):
    return urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=t).read()


def fetch_text(u, t=40):
    return fetch(u, t).decode("utf-8", "replace")


def main():
    slugs = []
    for s in SEARCHES:
        try:
            h = fetch_text(s)
        except Exception as e:
            print("search ERR %s" % e)
            continue
        for m in re.finditer(r'href="(/content/[a-z0-9\-_]+)"', h):
            p = m.group(1)
            if p not in slugs:
                slugs.append(p)
        time.sleep(0.3)

    print("候选 %d 个，开始逐个核验 CC0 + 找 zip\n" % len(slugs))

    got = 0
    for p in slugs:
        if got >= MAX_PACKS:
            break
        url = "https://opengameart.org" + p
        slug = p.rsplit("/", 1)[-1]
        try:
            h = fetch_text(url, 25)
        except Exception:
            continue

        lics = set(x.lower() for x in re.findall(r"license_images/([A-Za-z0-9_\-]+)\.png", h))
        if lics != {"cc0"}:
            continue

        zips = re.findall(r'href="(https://opengameart\.org/sites/default/files/[^"]+\.zip)"', h)
        if not zips:
            continue

        t = re.search(r"<title>(.*?)</title>", h, re.S)
        title = t.group(1).split("|")[0].strip() if t else slug

        # 体积过滤：先 HEAD 看大小，跳过 >12MB（太慢）
        zurl = zips[0]
        try:
            req = urllib.request.Request(zurl, headers=UA, method="HEAD")
            size = int(urllib.request.urlopen(req, timeout=20).headers.get("Content-Length", 0))
        except Exception:
            size = 0
        if size > 12 * 1024 * 1024:
            print("  skip(大) %-40s %.1fMB" % (slug[:38], size / 1048576))
            continue

        dest = os.path.join(OUT, slug)
        try:
            blob = fetch(zurl, 90)
            os.makedirs(dest, exist_ok=True)
            zpath = os.path.join(dest, "_pack.zip")
            with io.open(zpath, "wb") as fh:
                fh.write(blob)
            with zipfile.ZipFile(zpath) as z:
                z.extractall(dest)
            os.remove(zpath)
            n = sum(1 for _, _, fs in os.walk(dest) for _ in fs)
            print("  ✓ %-40s %3d 文件  %6.1fKB  %s" % (slug[:38], n, len(blob) / 1024, title[:30]))
            got += 1
        except Exception as e:
            print("  ✗ %-40s %s" % (slug[:38], str(e)[:40]))
        time.sleep(0.5)

    print("\n共收下 %d 个 CC0 包 -> %s" % (got, OUT))


main()
