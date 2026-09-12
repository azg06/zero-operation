"""直连 Blender MCP 插件 socket(:9876) 执行代码(桥进程不可用时的等价通道)。
用法:
  python bmcp.py ping
  python bmcp.py exec-file <file.py>
  python bmcp.py scene
  python bmcp.py shot <out.png> [max_size]
"""
import json, socket, sys, base64

HOST, PORT = "127.0.0.1", 9876


def call(cmd_type, params=None, timeout=900):
    payload = json.dumps({"type": cmd_type, "params": params or {}})
    s = socket.create_connection((HOST, PORT), timeout=timeout)
    try:
        s.sendall(payload.encode("utf-8"))
        buf = b""
        while True:
            try:
                chunk = s.recv(65536)
            except socket.timeout:
                return {"status": "error", "message": "socket timeout"}
            if not chunk:
                break
            buf += chunk
            try:
                return json.loads(buf.decode("utf-8"))
            except Exception:
                continue
        return {"status": "error", "message": "connection closed"}
    finally:
        s.close()


def summarize(resp, limit=600):
    txt = json.dumps(resp, ensure_ascii=False)
    return txt if len(txt) <= limit else txt[:limit] + "...[truncated]"


def post(cmd_type, params=None):
    """发射即返回: 不等响应(长命令用; 之后用 exec-file 查询结果)。"""
    payload = json.dumps({"type": cmd_type, "params": params or {}})
    s = socket.create_connection((HOST, PORT), timeout=15)
    try:
        s.sendall(payload.encode("utf-8"))
    finally:
        s.close()
    return True


if __name__ == "__main__":
    argv = sys.argv[1:]
    mode = argv[0] if argv else "ping"
    if mode == "ping":
        print(summarize(call("ping")))
    elif mode == "post-file":
        code = open(argv[1], encoding="utf-8").read()
        post("execute_code", {"code": code})
        print("POSTED", argv[1])
    elif mode == "exec-file":
        code = open(argv[1], encoding="utf-8").read()
        print(summarize(call("execute_code", {"code": code})))
    elif mode == "scene":
        print(summarize(call("get_scene_info"), 2000))
    elif mode == "shot":
        out = argv[1] if len(argv) > 1 else "shot.png"
        resp = call("get_viewport_screenshot", {"max_size": int(argv[2]) if len(argv) > 2 else 1280})
        r = resp.get("result") or {}
        b64 = r.get("image") or r.get("data") or ""
        if b64:
            with open(out, "wb") as f:
                f.write(base64.b64decode(b64))
            print("SHOT_SAVED", out, len(b64))
        else:
            print(summarize(resp))
    else:
        print("unknown mode:", mode)
