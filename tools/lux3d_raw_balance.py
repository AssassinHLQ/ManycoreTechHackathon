# -*- coding: utf-8 -*-
"""直接请求账户余额接口，打印**完整原始响应**（只读 GET，零消耗）。

技能里的 commerce_client 只保留 7 个字段，可能把服务端关于试用额度的说明丢掉了。
这里绕过它，看原始 JSON 有没有更多线索（比如 trial 的可用条件、所属能力）。
"""
import json
import os
import re
import sys
import urllib.request

SKILL = os.path.join(os.environ["USERPROFILE"], ".dsh", "skills", "aholo-lux3d")
sys.path.insert(0, os.path.join(SKILL, "core", "runtime"))

from lux3d_client import REGION_BASE_URLS, normalize_region  # noqa: E402

CREDS = os.path.join(os.environ["USERPROFILE"], ".dsh", "credentials", "lux3d-cn.env")


def load_key():
    with open(CREDS, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)", line)
            if m:
                return m.group(2).strip().strip('"').strip("'")
    raise SystemExit("找不到 LUX3D_CN_API_KEY")


def main():
    region = normalize_region("cn")
    key = load_key()
    url = REGION_BASE_URLS[region] + "/lux3d/v1/account/balance?source=3"
    req = urllib.request.Request(url, headers={
        "Authorization": key,
        "Accept": "application/json",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
    doc = json.loads(raw)
    print("=== 原始响应（完整）===")
    print(json.dumps(doc, ensure_ascii=False, indent=2))
    d = doc.get("d") if isinstance(doc, dict) else None
    if isinstance(d, dict):
        print("\n=== d 里出现过的所有键 ===")
        for k, v in d.items():
            print("  %-24s %s" % (k, json.dumps(v, ensure_ascii=False)[:120]))


if __name__ == "__main__":
    main()
