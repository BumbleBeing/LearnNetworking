#!/usr/bin/env python3
"""Fail if any project script has a GDScript warning or error.

The editor shows analyzer warnings (integer division, shadowing, unused
variables...), but headless runs don't print them. This starts Godot's
GDScript language server, opens every .gd file outside addons/ and prints
each diagnostic it reports, so CI catches what the editor would show.

Usage: python3 tools/check_gdscript_warnings.py [godot_binary] [project_dir]
       (defaults: godot, the project this script is in)
Exit code: 0 if clean, 1 if there are diagnostics, 2 if the server didn't respond.
"""
import json
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

PORT = 6011


class Lsp:
    def __init__(self, port):
        self.sock = None
        for _ in range(240):
            try:
                self.sock = socket.create_connection(("127.0.0.1", port))
                break
            except OSError:
                time.sleep(0.5)
        if self.sock is None:
            raise TimeoutError("language server didn't start")
        self.buf = b""

    def send(self, msg):
        body = json.dumps(msg).encode()
        self.sock.sendall(b"Content-Length: %d\r\n\r\n" % len(body) + body)

    def recv(self, timeout):
        self.sock.settimeout(timeout)
        while True:
            m = re.search(rb"Content-Length: (\d+)\r\n\r\n", self.buf)
            if m and len(self.buf) >= m.end() + int(m.group(1)):
                end = m.end() + int(m.group(1))
                body, self.buf = self.buf[m.end():end], self.buf[end:]
                return json.loads(body)
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                return None
            if not chunk:
                return None
            self.buf += chunk


def main(argv):
    godot = argv[1] if len(argv) > 1 else "godot"
    proj = Path(argv[2] if len(argv) > 2 else Path(__file__).resolve().parent.parent).resolve()
    files = sorted(f for f in proj.rglob("*.gd") if not {"addons", ".godot"} & set(f.relative_to(proj).parts))
    server = subprocess.Popen([godot, "--headless", "--editor", "--path", str(proj), "--lsp-port", str(PORT)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    diags = {}
    try:
        lsp = Lsp(PORT)
        lsp.send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": {"processId": None, "rootUri": proj.as_uri(), "capabilities": {}}})
        while (r := lsp.recv(60)) is not None and r.get("id") != 1:
            pass
        lsp.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        for f in files:
            lsp.send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {
                "uri": f.as_uri(), "languageId": "gdscript", "version": 1, "text": f.read_text()}}})
        deadline = time.time() + 120
        while time.time() < deadline and len(diags) < len(files):
            r = lsp.recv(10)
            if r is None:
                break
            if r.get("method") == "textDocument/publishDiagnostics":
                diags[r["params"]["uri"]] = r["params"]["diagnostics"]
    except TimeoutError as e:
        print(f"error: {e}")
        return 2
    finally:
        server.kill()

    if len(diags) < len(files):
        print(f"error: the language server checked only {len(diags)} of {len(files)} scripts")
        return 2
    count = 0
    for uri, found in sorted(diags.items()):
        rel = uri[len(proj.as_uri()) + 1:]
        for d in found:
            count += 1
            print(f"{rel}:{d['range']['start']['line'] + 1}: {d['message']}")
    print(f"{count} warning(s) or error(s) in {len(files)} scripts")
    return 1 if count else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
