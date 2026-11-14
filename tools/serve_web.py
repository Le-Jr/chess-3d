"""Serves the web export locally, the way it has to be hosted.

    python tools/serve_web.py [folder] [port]      (defaults: build/web, 8060)

The build uses threads (the chess engine and the sound synthesis run in the
background), which browsers only allow on pages that are "cross-origin
isolated". This server sends the two headers that grant it; on a real host
either configure the same headers or rely on the service worker that the
export installs (it adds them itself, at the cost of one reload on the first
visit).

Open http://localhost:8060 on this machine. To try it on a phone on the same
network, use this machine's address instead - but note that browsers only
grant isolation over HTTPS or on localhost, so over plain http://192.168...
the page falls back to the service worker, which needs HTTPS too. For a
phone, deploy to an HTTPS host (itch.io, GitHub Pages, Netlify...) or use a
tunnel.
"""
import functools
import http.server
import os
import sys

folder = sys.argv[1] if len(sys.argv) > 1 else os.path.join("build", "web")
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8060


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass


if not os.path.isfile(os.path.join(folder, "index.html")):
    sys.exit(f"No index.html in '{folder}'. Export first: tools/export_web.ps1")
handler = functools.partial(Handler, directory=folder)
with http.server.ThreadingHTTPServer(("0.0.0.0", port), handler) as server:
    print(f"Serving {folder} at http://localhost:{port}  (Ctrl+C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
