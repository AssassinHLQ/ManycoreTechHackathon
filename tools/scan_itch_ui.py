# -*- coding: utf-8 -*-
"""抓 itch.io 的游戏素材列表（带浏览器 UA，否则 403/连接被拒）。

itch.io 的列表页结构：每个素材是 <div class="game_cell">，
里面 .game_title a 是标题+链接，.game_author 是作者。
"""
import re
import sys
import urllib.request

UA = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9",
}

URLS = [
    ("itch CC0 sci-fi", "https://itch.io/game-assets/assets-cc0/tag-science-fiction"),
    ("itch HUD + sci-fi", "https://itch.io/game-assets/tag-hud/tag-science-fiction"),
    ("itch sci-fi (all)", "https://itch.io/game-assets/tag-science-fiction"),
    ("itch CC0 UI", "https://itch.io/game-assets/assets-cc0/tag-user-interface"),
]


def fetch(u):
    return urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=30).read().decode("utf-8", "replace")


def parse(html):
    out = []
    # 每个 cell
    for m in re.finditer(r'<div[^>]+class="game_cell[^"]*"[^>]*>(.*?)(?=<div[^>]+class="game_cell|$)', html, re.S):
        blk = m.group(1)
        t = re.search(r'class="title game_link"[^>]*href="([^"]+)"[^>]*>([^<]+)<', blk)
        if not t:
            t2 = re.search(r'href="(https://[^"]+\.itch\.io/[^"]+)"[^>]*>\s*([^<]{2,80})\s*<', blk)
            if not t2:
                continue
            url, title = t2.group(1), t2.group(2)
        else:
            url, title = t.group(1), t.group(2)
        a = re.search(r'class="game_author"[^>]*>\s*<a[^>]*>([^<]+)</a>', blk)
        author = a.group(1).strip() if a else "?"
        price = "free" if ("price_value" not in blk) else re.search(r'class="price_value"[^>]*>([^<]+)<', blk).group(1)
        out.append((title.strip(), url, author, price))
    return out


def main():
    for label, u in URLS:
        print("\n" + "=" * 76)
        print("### %s" % label)
        print("    %s" % u)
        try:
            html = fetch(u)
        except Exception as e:
            print("    ERR %s" % e)
            continue
        items = parse(html)
        if not items:
            print("    （没解析出条目，页面结构可能变了）")
            continue
        seen = set()
        for title, url, author, price in items:
            if url in seen:
                continue
            seen.add(url)
            print("  · %-52s %-8s %s" % (title[:50], price, author))
            print("    %s" % url)


main()
