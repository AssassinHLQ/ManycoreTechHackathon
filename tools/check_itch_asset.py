# -*- coding: utf-8 -*-
"""核实 itch.io 素材页：许可证、价格、预览图 URL。

itch.io 素材页的许可证通常在 .formatted_description 或 "License" 区块里，
也可能在页脚 "Asset license" 链接。价格在 .buy_row / .price_value。

Windows 控制台默认 GBK，直接 print 非 ASCII 会崩 —— 这里强制 stdout 用 utf-8。
"""
import io
import re
import sys
import urllib.request

# 关键：Windows 下强制 UTF-8 输出，否则中文/emoji 会 UnicodeEncodeError
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

UA = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9",
}

TARGETS = [
    "https://antahonist.itch.io/sci-fi-ui-kit-vol-2-starship-hud-icons",
    "https://sungraphica.itch.io/sci-fi-game-ui-collection-free-version",
    "https://sungraphica.itch.io/sci-fi-game-user-interface",
    "https://deakcor.itch.io/hud-futuristic",
    "https://gabrielatot.itch.io/atompunk-ui",
    "https://djy66.itch.io/cyberpunk-hud-ui-kit-vol-1",
]


def fetch(u):
    req = urllib.request.Request(u, headers=UA)
    return urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")


def main():
    for u in TARGETS:
        print("\n" + "=" * 78)
        try:
            h = fetch(u)
        except Exception as e:
            print("ERR %s  %s" % (u, e))
            continue

        t = re.search(r"<title>(.*?)</title>", h, re.S)
        title = " ".join(t.group(1).split()) if t else "?"
        print("### %s" % title[:90])
        print("    %s" % u)

        # 价格
        price = re.search(r'class="price_value"[^>]*>\s*\$?\s*([\d\.]+)', h)
        if price:
            print("    价格 : $%s" % price.group(1))
        elif re.search(r'class="[^"]*buy_btn[^"]*"[^>]*>\s*Download', h):
            print("    价格 : 免费")
        else:
            print("    价格 : 免费（未发现价格标记）")

        # 许可证关键字
        lic = []
        for kw in ["CC0", "Creative Commons", "public domain", "CC BY", "CC-BY",
                   "no credit", "Attribution", "commercial", "Royalty"]:
            if re.search(kw, h, re.I):
                lic.append(kw)
        print("    授权 : %s" % (", ".join(lic) if lic else "未找到，需人工看"))

        # 预览图（itch 的图片 CDN）
        imgs = re.findall(r'"(https://img\.itch\.zone/[^"]+\.(?:png|jpg|jpeg|gif))"', h)
        imgs = [i for i in imgs if any(k in i for k in ("original", "screenshot"))]
        seen = []
        for i in imgs:
            if i not in seen:
                seen.append(i)
        for i in seen[:2]:
            print("    预览 : %s" % i)

        # 描述里的许可证段落
        desc = re.search(r'<div class="formatted_description[^"]*"[^>]*>(.*?)</div>\s*</div>', h, re.S)
        if desc:
            txt = re.sub(r"<[^>]+>", " ", desc.group(1))
            txt = " ".join(txt.split())
            for kw in ["CC0", "CC-BY", "CC BY", "commercial", "license", "credit", "attribution"]:
                m = re.search(r".{0,80}%s.{0,120}" % re.escape(kw), txt, re.I)
                if m:
                    print("    描述 : ...%s..." % m.group(0).strip()[:180])
                    break


main()
