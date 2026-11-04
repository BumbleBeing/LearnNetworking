#!/usr/bin/env python3
"""Install only the Godot web export templates the Web preset needs.

The official export templates come as one ~1 GB archive. This reads just the
two single-threaded web templates (~17 MB) out of it with HTTP range requests
and puts them where Godot looks for them.

Usage: python3 tools/fetch_web_templates.py [godot_version]   (default 4.3)
"""
import io
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

NEEDED = ["templates/web_nothreads_release.zip", "templates/web_nothreads_debug.zip"]


class HttpFile(io.RawIOBase):
    """A read-only, seekable file over HTTP range requests (enough for zipfile)."""

    def __init__(self, url):
        head = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"))
        self.url, self.size, self.pos = head.geturl(), int(head.headers["Content-Length"]), 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else self.pos + offset if whence == 1 else self.size + offset
        return self.pos

    def read(self, n=-1):
        if n < 0:
            n = self.size - self.pos
        if n <= 0:
            return b""
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{self.pos + n - 1}"})
        data = urllib.request.urlopen(req).read()
        self.pos += len(data)
        return data


def template_dir(version):
    if sys.platform == "darwin":
        base = Path.home() / "Library/Application Support/Godot"
    elif os.name == "nt":
        base = Path(os.environ["APPDATA"]) / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "godot"
    return base / "export_templates" / f"{version}.stable"


def main(argv):
    version = argv[1] if len(argv) > 1 else "4.3"
    dest = template_dir(version)
    if all((dest / Path(n).name).exists() for n in NEEDED):
        print(f"web templates already in {dest}")
        return 0
    url = (f"https://github.com/godotengine/godot/releases/download/{version}-stable/"
           f"Godot_v{version}-stable_export_templates.tpz")
    archive = zipfile.ZipFile(HttpFile(url))
    dest.mkdir(parents=True, exist_ok=True)
    for name in NEEDED:
        (dest / Path(name).name).write_bytes(archive.read(name))
        print(f"installed {Path(name).name} -> {dest}")
    (dest / "version.txt").write_text(f"{version}.stable")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
