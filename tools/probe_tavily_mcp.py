# -*- coding: utf-8 -*-
"""对 tavily-mcp 做一次完整的 MCP stdio 握手 + tools/list。

为什么要单独写：PowerShell 的 Start-Process 在重定向 stdin 时踩坑，
用 subprocess 直接喂 JSON-RPC 更可靠，也能看清握手到底成没成。
"""
import json
import os
import subprocess
import sys

KEY = "tvly-31rJib-cWV6a4tjprBN9CJVCfdCMzNiUwbyyq9URcj5cBmcST"

env = dict(os.environ)
env["TAVILY_API_KEY"] = KEY

proc = subprocess.Popen(
    ["npx.cmd", "-y", "tavily-mcp@latest"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
    text=True,
    encoding="utf-8",
    errors="replace",
    shell=True,
)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()

def read_line(timeout_note=""):
    line = proc.stdout.readline()
    if not line:
        return None
    try:
        return json.loads(line)
    except Exception:
        return {"_raw": line.strip()}

send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
      "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                 "clientInfo": {"name": "dsh-probe", "version": "1.0"}}})

msg = read_line()
print("=== initialize 响应 ===")
if msg is None:
    print("  没有响应（进程可能已退出）")
else:
    print(json.dumps(msg, ensure_ascii=False)[:600])

# 握手第二步：通知 initialized
send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

# 列工具
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
msg2 = read_line()
print("\n=== tools/list 响应 ===")
if msg2 and "result" in msg2:
    for t in msg2["result"].get("tools", []):
        print("  -", t.get("name"))
elif msg2:
    print(json.dumps(msg2, ensure_ascii=False)[:600])
else:
    print("  没有响应")

proc.terminate()
try:
    err = proc.communicate(timeout=5)[1]
except Exception:
    err = ""
if err.strip():
    print("\n=== stderr ===")
    print(err.strip()[:500])
