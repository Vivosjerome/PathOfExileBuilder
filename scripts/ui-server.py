#!/usr/bin/env python3
"""Local UI for the PoE Build Optimizer. Keeps a warm PoB RPC worker."""

from __future__ import annotations

import argparse
import json
import os
import queue
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

HOST = "127.0.0.1"
PORT = 8765


class Worker:
    def __init__(self, root: Path, luajit: Path):
        self.root = root
        self.luajit = luajit
        self.worker_lua = root / "core" / "pob-engine" / "worker.lua"
        self.pob_src = root / "vendor" / "PathOfBuilding" / "src"
        self.proc: subprocess.Popen | None = None
        self._id = 0
        self._lock = threading.Lock()
        self._stdout_q: queue.Queue[str] = queue.Queue()
        self._logs: queue.Queue[str] = queue.Queue(maxsize=4000)
        self._busy = False
        self.ready = False
        self.last_error = ""

    def start(self) -> None:
        self.stop()
        env = os.environ.copy()
        runtime = self.root / "vendor" / "PathOfBuilding" / "runtime" / "lua"
        shims = self.root / "core" / "pob-engine" / "shims"
        env["LUA_PATH"] = f"{runtime}\\?.lua;{runtime}\\?\\init.lua;{shims}\\?.lua;;"
        env["LUA_CPATH"] = ";;"
        self.proc = subprocess.Popen(
            [str(self.luajit), str(self.worker_lua), "rpc"],
            cwd=str(self.pob_src),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        threading.Thread(target=self._pump_stdout, daemon=True).start()
        threading.Thread(target=self._pump_stderr, daemon=True).start()
        try:
            self.call("ping", {}, timeout=90)
            self.ready = True
            self.last_error = ""
        except Exception as exc:
            self.ready = False
            self.last_error = str(exc)
            raise

    def stop(self) -> None:
        proc = self.proc
        self.proc = None
        self.ready = False
        if not proc:
            return
        try:
            if proc.stdin:
                proc.stdin.write('{"method":"shutdown"}\n')
                proc.stdin.flush()
        except Exception:
            pass
        try:
            proc.kill()
        except Exception:
            pass

    def restart(self) -> None:
        self.start()

    def _pump_stdout(self) -> None:
        proc = self.proc
        if not proc or not proc.stdout:
            return
        for line in proc.stdout:
            self._stdout_q.put(line.rstrip("\n"))

    def _pump_stderr(self) -> None:
        proc = self.proc
        if not proc or not proc.stderr:
            return
        for line in proc.stderr:
            text = line.rstrip("\n")
            if not text:
                continue
            try:
                self._logs.put_nowait(text)
            except queue.Full:
                try:
                    self._logs.get_nowait()
                except queue.Empty:
                    pass
                try:
                    self._logs.put_nowait(text)
                except queue.Full:
                    pass

    def drain_logs(self) -> list[str]:
        out = []
        while True:
            try:
                out.append(self._logs.get_nowait())
            except queue.Empty:
                return out

    def call(self, method: str, params: dict, timeout: float = 30) -> dict:
        with self._lock:
            if not self.proc or not self.proc.stdin:
                raise RuntimeError("worker is not running")
            self._id += 1
            req_id = self._id
            payload = json.dumps({"id": req_id, "method": method, "params": params}, ensure_ascii=False)
            self._busy = True
            try:
                self.proc.stdin.write(payload + "\n")
                self.proc.stdin.flush()
                deadline = time.time() + timeout
                while True:
                    remaining = deadline - time.time()
                    if remaining <= 0:
                        raise TimeoutError(f"{method} timed out")
                    try:
                        line = self._stdout_q.get(timeout=min(0.25, remaining))
                    except queue.Empty:
                        if self.proc.poll() is not None:
                            raise RuntimeError("worker exited")
                        continue
                    if not line.startswith("{"):
                        continue
                    try:
                        msg = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if msg.get("id") != req_id:
                        continue
                    if not msg.get("ok"):
                        raise RuntimeError(msg.get("error") or "worker error")
                    return msg.get("result") or {}
            finally:
                self._busy = False


WORKER: Worker | None = None
SCHEMA_CACHE: dict | None = None
SCHEMA_LOCK = threading.Lock()
UI_DIR: Path


def get_schema() -> dict:
    global SCHEMA_CACHE
    with SCHEMA_LOCK:
        if SCHEMA_CACHE is not None:
            return SCHEMA_CACHE
        assert WORKER is not None
        SCHEMA_CACHE = WORKER.call("schema", {}, timeout=120)
        return SCHEMA_CACHE


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def _send(self, code: int, body: bytes, content_type: str, extra: dict | None = None) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if extra:
            for key, value in extra.items():
                self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, payload: dict) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send(code, raw, "application/json; charset=utf-8")

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/api/health":
            assert WORKER is not None
            self._json(200, {
                "ok": WORKER.ready,
                "busy": WORKER._busy,
                "error": WORKER.last_error,
            })
            return
        if path == "/api/schema":
            try:
                self._json(200, get_schema())
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path in ("/", "/index.html"):
            path = "/index.html"
        rel = path.lstrip("/").replace("\\", "/")
        if ".." in rel:
            self._send(403, b"forbidden", "text/plain")
            return
        file_path = UI_DIR / rel
        if not file_path.is_file():
            self._send(404, b"not found", "text/plain")
            return
        ext = file_path.suffix.lower()
        types = {
            ".html": "text/html; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".js": "text/javascript; charset=utf-8",
            ".svg": "image/svg+xml",
            ".json": "application/json; charset=utf-8",
        }
        self._send(200, file_path.read_bytes(), types.get(ext, "application/octet-stream"))

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length) if length else b"{}"
        try:
            params = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._json(400, {"ok": False, "error": "invalid json"})
            return
        if path == "/api/cancel":
            assert WORKER is not None
            try:
                WORKER.restart()
                self._json(200, {"ok": True})
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path != "/api/generate":
            self._json(404, {"ok": False, "error": "unknown endpoint"})
            return
        assert WORKER is not None
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        done = threading.Event()
        box: dict = {}

        def run() -> None:
            try:
                box["result"] = WORKER.call("generate", params, timeout=4 * 3600)
            except Exception as exc:
                box["error"] = str(exc)
            finally:
                done.set()

        threading.Thread(target=run, daemon=True).start()
        try:
            while not done.wait(0.08):
                for line in WORKER.drain_logs():
                    self.wfile.write((json.dumps({"t": "log", "line": line}, ensure_ascii=False) + "\n").encode("utf-8"))
                self.wfile.flush()
            for line in WORKER.drain_logs():
                self.wfile.write((json.dumps({"t": "log", "line": line}, ensure_ascii=False) + "\n").encode("utf-8"))
            if "error" in box:
                self.wfile.write((json.dumps({"t": "error", "error": box["error"]}, ensure_ascii=False) + "\n").encode("utf-8"))
            else:
                self.wfile.write((json.dumps({"t": "result", "result": box.get("result")}, ensure_ascii=False) + "\n").encode("utf-8"))
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            WORKER.restart()


def main() -> int:
    global WORKER, UI_DIR
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--luajit", required=True)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    UI_DIR = root / "ui"
    WORKER = Worker(root, Path(args.luajit))
    sys.stderr.write("Démarrage du moteur PoB…\n")
    WORKER.start()
    sys.stderr.write("Moteur prêt. Chargement du schéma…\n")
    get_schema()
    httpd = ThreadingHTTPServer((HOST, args.port), Handler)
    url = f"http://{HOST}:{args.port}/"
    sys.stderr.write(f"Interface: {url}\n")
    if not args.no_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        WORKER.stop()
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
