#!/usr/bin/env python3
"""
chrome://gpu smoke test.

Connects to Tungsten's CEF DevTools endpoint (http://127.0.0.1:9222), navigates
a page to chrome://gpu, scrapes the rendered text, and asserts that the
features we care about report "Hardware accelerated" and that ANGLE is on the
Metal backend.

Run with the app already launched in the background. The shell wrapper
(`Tests/ChromeGpuSmokeTest.sh`) handles launch/teardown.
"""

import base64
import json
import os
import re
import socket
import struct
import sys
import time
import urllib.request
from urllib.parse import urlparse

DEVTOOLS = "http://127.0.0.1:9222"

REQUIRED_HW = [
    "Canvas",
    "Compositing",
    "Video Decode",
    "WebGL",
    "WebGPU",
]
REQUIRED_RASTER = ("Rasterization",
                   re.compile(r"^Hardware accelerated"))
REQUIRED_ANGLE = re.compile(r"angle=metal", re.IGNORECASE)


def http(path, method="GET"):
    req = urllib.request.Request(f"{DEVTOOLS}{path}", method=method)
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read())


def wait_for_devtools(timeout=20):
    deadline = time.monotonic() + timeout
    last_err = None
    while time.monotonic() < deadline:
        try:
            http("/json/version")
            return
        except Exception as e:
            last_err = e
            time.sleep(0.25)
    raise RuntimeError(f"CEF DevTools not reachable on 9222: {last_err}")


class WS:
    """Minimal RFC 6455 client for CDP. Text frames only, single-threaded."""

    def __init__(self, url):
        u = urlparse(url)
        self.sock = socket.create_connection((u.hostname, u.port), timeout=10)
        self.sock.settimeout(10)
        path = u.path + (("?" + u.query) if u.query else "")
        key = base64.b64encode(os.urandom(16)).decode()
        handshake = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {u.hostname}:{u.port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(handshake.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("WebSocket handshake failed (eof)")
            buf += chunk
        if b" 101 " not in buf.split(b"\r\n", 1)[0]:
            raise RuntimeError(f"WebSocket handshake rejected: {buf[:120]!r}")
        self._buf = buf.split(b"\r\n\r\n", 1)[1]
        self._mid = 0

    def _recv_exact(self, n):
        out = self._buf[:n]
        self._buf = self._buf[n:]
        while len(out) < n:
            chunk = self.sock.recv(max(4096, n - len(out)))
            if not chunk:
                raise RuntimeError("WebSocket closed by peer")
            need = n - len(out)
            out += chunk[:need]
            if len(chunk) > need:
                self._buf = chunk[need:] + self._buf
        return out

    def send_json(self, method, params=None):
        self._mid += 1
        msg = json.dumps({"id": self._mid, "method": method,
                          "params": params or {}})
        data = msg.encode("utf-8")
        if len(data) < 126:
            header = bytes([0x81, 0x80 | len(data)])
        elif len(data) < 65536:
            header = bytes([0x81, 0x80 | 126]) + struct.pack(">H", len(data))
        else:
            header = bytes([0x81, 0x80 | 127]) + struct.pack(">Q", len(data))
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(header + mask + masked)
        return self._mid

    def _recv_frame(self):
        h = self._recv_exact(2)
        opcode = h[0] & 0x0F
        plen = h[1] & 0x7F
        if plen == 126:
            plen = struct.unpack(">H", self._recv_exact(2))[0]
        elif plen == 127:
            plen = struct.unpack(">Q", self._recv_exact(8))[0]
        masked = bool(h[1] & 0x80)
        mask = self._recv_exact(4) if masked else None
        data = self._recv_exact(plen)
        if mask:
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        return opcode, data

    def wait_for(self, msg_id, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.sock.settimeout(max(0.1, deadline - time.monotonic()))
            opcode, data = self._recv_frame()
            if opcode != 1:
                continue
            obj = json.loads(data.decode("utf-8"))
            if obj.get("id") == msg_id:
                if "error" in obj:
                    raise RuntimeError(f"CDP error: {obj['error']}")
                return obj
        raise TimeoutError(f"No CDP response for id={msg_id}")


def open_gpu_page():
    # CEF's HTTP endpoint creates the tab pre-pointed at chrome://gpu, which
    # avoids the cross-origin restrictions that bite Page.navigate from a
    # regular https:// tab into a chrome:// scheme.
    return http("/json/new?chrome://gpu", method="PUT")


def close_page(target_id):
    try:
        urllib.request.urlopen(
            f"{DEVTOOLS}/json/close/{target_id}", timeout=3
        ).read()
    except Exception:
        pass


def dump_gpu(page):
    ws = WS(page["webSocketDebuggerUrl"])
    ws.send_json("Page.enable")
    # chrome://gpu populates asynchronously after navigation; poll until both
    # the feature table and the driver section are rendered, or 15s pass.
    # chrome://gpu renders inside Polymer shadow DOM; document.body.innerText
    # is empty for two reasons: (1) most content lives behind shadowRoot
    # boundaries, (2) a background CEF tab has no computed layout so
    # innerText returns "" anyway. Walk the DOM tree by hand, descending
    # into shadowRoot, accumulating textContent. Keep newlines between
    # element children so we can still parse "Name: value" rows.
    expr = r"""
(() => {
  function dump(n, depth) {
    if (depth > 12) return '';
    let s = '';
    if (n.shadowRoot) s += dump(n.shadowRoot, depth + 1);
    for (const c of (n.childNodes || [])) {
      if (c.nodeType === 3) {
        s += c.textContent;
      } else if (c.nodeType === 1) {
        const t = c.tagName;
        if (t === 'SCRIPT' || t === 'STYLE') continue;
        s += '\n' + dump(c, depth + 1);
      }
    }
    return s;
  }
  return dump(document.documentElement, 0);
})()
"""
    deadline = time.monotonic() + 20
    text = ""
    while time.monotonic() < deadline:
        eid = ws.send_json("Runtime.evaluate", {
            "expression": expr,
            "returnByValue": True,
        })
        res = ws.wait_for(eid)
        text = res["result"]["result"].get("value", "") or ""
        if "Graphics Feature Status" in text and "Driver Information" in text:
            break
        time.sleep(0.3)
    return text


def _row_value(text, name):
    # The Polymer dump looks like:
    #   "*   "
    #   "Canvas: "
    #   "Hardware accelerated"
    # i.e. label and value land on different lines. Allow whitespace +
    # newlines between the colon and the value.
    pat = rf"\b{re.escape(name)}\s*:\s*\n?\s*([^\n]+)"
    m = re.search(pat, text)
    return m.group(1).strip() if m else None


def assert_feature_status(text):
    failures = []
    successes = []
    for feat in REQUIRED_HW:
        status = _row_value(text, feat)
        if status is None:
            failures.append(f"{feat}: not present in chrome://gpu output")
        elif status.lower().startswith("hardware accelerated"):
            successes.append(f"{feat}: {status}")
        else:
            failures.append(f"{feat}: expected 'Hardware accelerated', got '{status}'")
    name, pat = REQUIRED_RASTER
    status = _row_value(text, name)
    if status is None:
        failures.append(f"{name}: not present")
    elif not pat.search(status):
        failures.append(f"{name}: expected hardware accelerated, got '{status}'")
    else:
        successes.append(f"{name}: {status}")

    impl = _row_value(text, "GL implementation parts")
    if impl is None or not REQUIRED_ANGLE.search(impl):
        failures.append("GL implementation: ANGLE/Metal not active "
                        f"(saw {impl!r})")
    else:
        successes.append(f"GL implementation: {impl}")

    return successes, failures


def main():
    wait_for_devtools()
    page = open_gpu_page()
    try:
        text = dump_gpu(page)
    finally:
        close_page(page["id"])
    if not text or "Graphics Feature Status" not in text:
        print("FAIL  chrome://gpu did not render a Graphics Feature Status section")
        print("---- captured text (first 400 chars) ----")
        print(text[:400])
        return 1
    successes, failures = assert_feature_status(text)
    for s in successes:
        print(f"OK    {s}")
    for f in failures:
        print(f"FAIL  {f}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
