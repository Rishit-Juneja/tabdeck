#!/usr/bin/env python3
"""Tab Deck: a Stream Deck-style control page for the tablet, served from this PC.

Each button runs one fixed command here. The page (Firefox kiosk on the tablet) taps buttons through a
small JSON API and polls a status endpoint for volume, mic, now playing and PC load. A token in every
request keeps others on the LAN out.
"""
import json
import re
import secrets
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = 8780
TOKEN_FILE = Path.home() / ".config/tabdeck/token"
PAGE_FILE = Path(__file__).with_name("deck.html")

KG = ["qdbus6", "org.kde.kglobalaccel", "/component/mediacontrol",
      "org.kde.kglobalaccel.Component.invokeShortcut"]
SINK, SOURCE = "@DEFAULT_AUDIO_SINK@", "@DEFAULT_AUDIO_SOURCE@"

# id: command. Labels, icons and colours live in deck.html.
ACTIONS = {
    "prev":  KG + ["previousmedia"],
    "play":  KG + ["playpausemedia"],
    "next":  KG + ["nextmedia"],
    "voldn": ["wpctl", "set-volume", SINK, "5%-"],
    "volup": ["wpctl", "set-volume", "-l", "1.0", SINK, "5%+"],
    "mute":  ["wpctl", "set-mute", SINK, "toggle"],
    "mic":   ["wpctl", "set-mute", SOURCE, "toggle"],
    "shot":  ["spectacle", "-b", "-f"],
    "lock":  ["loginctl", "lock-session"],
    "brave": ["brave"],
    "term":  ["konsole"],
    "files": ["dolphin"],
    "spot":  ["spotify"],
    "disc":  ["discord"],
    "obs":   ["obs"],
}


def token():
    if not TOKEN_FILE.exists():
        TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
        TOKEN_FILE.write_text(secrets.token_urlsafe(16))
        TOKEN_FILE.chmod(0o600)
    return TOKEN_FILE.read_text().strip()


def run(cmd):
    # detached, so launched apps outlive the request and the server
    subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def out(cmd, timeout=2):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


def wp_level(target):
    s = out(["wpctl", "get-volume", target])
    m = re.search(r"([\d.]+)", s)
    return (round(float(m.group(1)) * 100) if m else None), ("MUTED" in s)


def now_playing():
    """First MPRIS player that is playing (else any paused one): title, artist, state."""
    best = None
    for svc in out(["qdbus6"]).split():
        if not svc.startswith("org.mpris.MediaPlayer2.") or "kdeconnect" in svc:
            continue
        base = ["qdbus6", svc, "/org/mpris/MediaPlayer2"]
        state = out(base + ["org.mpris.MediaPlayer2.Player.PlaybackStatus"]).strip()
        if state not in ("Playing", "Paused"):
            continue
        meta = out(base + ["org.mpris.MediaPlayer2.Player.Metadata"])
        title = re.search(r"xesam:title: (.*)", meta)
        artist = re.search(r"xesam:artist: (.*)", meta)
        info = {"state": state, "title": title.group(1).strip() if title else "",
                "artist": artist.group(1).strip() if artist else "",
                "app": svc.split(".")[3].split(".")[0]}
        if state == "Playing":
            return info
        best = best or info
    return best


class Load:
    """CPU from /proc/stat deltas and GPU from nvidia-smi, sampled in the background every 2 s."""
    cpu = gpu = gpu_temp = None

    def __init__(self):
        threading.Thread(target=self.loop, daemon=True).start()

    @staticmethod
    def stat():
        f = [int(x) for x in Path("/proc/stat").read_text().split("\n", 1)[0].split()[1:]]
        idle = f[3] + f[4]
        return sum(f), idle

    def loop(self):
        prev = self.stat()
        while True:
            time.sleep(2)
            cur = self.stat()
            total, idle = cur[0] - prev[0], cur[1] - prev[1]
            self.cpu = round(100 * (total - idle) / total) if total else None
            prev = cur
            g = out(["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu",
                     "--format=csv,noheader,nounits"]).strip().split(",")
            if len(g) == 2:
                self.gpu, self.gpu_temp = int(g[0]), int(g[1])


LOAD = Load()


def status():
    vol, muted = wp_level(SINK)
    _, mic_muted = wp_level(SOURCE)
    return {"volume": vol, "muted": muted, "mic_muted": mic_muted, "playing": now_playing(),
            "cpu": LOAD.cpu, "gpu": LOAD.gpu, "gpu_temp": LOAD.gpu_temp}


class Handler(BaseHTTPRequestHandler):
    def send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authed(self, url):
        return secrets.compare_digest(parse_qs(url.query).get("t", [""])[0], token())

    def do_GET(self):
        url = urlparse(self.path)
        if not self.authed(url):
            return self.send_error(403)
        if url.path == "/":
            return self.send(200, PAGE_FILE.read_bytes(), "text/html; charset=utf-8")
        if url.path == "/api/status":
            return self.send(200, json.dumps(status()).encode(), "application/json")
        self.send_error(404)

    def do_POST(self):
        url = urlparse(self.path)
        if not self.authed(url):
            return self.send_error(403)
        bid = url.path.removeprefix("/api/a/")
        if not url.path.startswith("/api/a/") or bid not in ACTIONS:
            return self.send_error(404)
        run(ACTIONS[bid])
        self.send(200, b'{"ok":true}', "application/json")

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    token()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
