#!/usr/bin/env python3
"""Serve web/site/ with the headers wasm threads need (SharedArrayBuffer requires cross-origin isolation)."""
import functools, http.server, pathlib, sys

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".js": "text/javascript"}
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache") # a repacked kernel must not be shadowed by a cached copy
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

root = pathlib.Path(__file__).parent / "site"
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8088
http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=root)).serve_forever()
