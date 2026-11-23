"""Nullgram: Telegram the way Telegram-iOS shows it, on Qt Quick + TDLib.

QML draws everything and keeps the state (qml/Store.qml); this file only loads
TDLib and carries its JSON both ways. Rule (NOTES.md): no Python on the
render thread and none in the UI thread's hot paths -- TDLib's answers are read
on a thread of our own (ctypes lets the interpreter go while it waits) and
reach QML as queued signals, which QML takes without Python.

  python3 nullgram.py [--test-dc]      (--test-dc: Telegram's test servers, a throwaway account;
                                       NULLGRAM_TEST_PHONE=99966XYYYY signs in there by itself)
"""
import base64
import ctypes
import gzip
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import hashlib
import math
import os
import queue
import random
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import parse_qs, unquote, urlparse

# letters over 64 px are drawn from outlines every time, uncached; at the S10's 4x that is all of them
os.environ.setdefault("QT_MAX_CACHED_GLYPH_SIZE", "256")
# Store.qml reads the emoji code->file map (app/emoji/emoji-map.json) over XMLHttpRequest, a local file
os.environ.setdefault("QML_XHR_ALLOW_FILE_READ", "1")

from PySide6.QtCore import Property, QByteArray, QFileSystemWatcher, QObject, QPointF, QRectF, QSize, QSocketNotifier, Qt, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QFont, QLinearGradient, QFontDatabase, QGuiApplication, QSyntaxHighlighter, QTextCharFormat, QImage, QImageReader, QPainter, QPainterPath, QTransform
from PySide6.QtQuick import QQuickImageProvider, QQuickView
# (what the picture providers use, here and not in their requestImage: two of Qt's threads ask them at once — an
# Image and an asynchronous one — and PySide loading a class for both at the same moment crashed on the phone)
from PySide6.QtSvg import QSvgRenderer

HERE = os.path.dirname(os.path.abspath(__file__))
TEST = "--test-dc" in sys.argv
DATA = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.nullgram" + (".test" if TEST else ""))
KEYDIR = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.nullgram")
# the Telegram API key, the first one found: the user's own (Settings › «O'z API kalitingiz», for when the
# packaged one is blocked), install.sh --key's (our phone), the one a package carries beside the app
OWN_KEY = os.path.join(KEYDIR, "api-own.json")
KEYS = [OWN_KEY, os.path.join(KEYDIR, "api.json"), os.path.join(HERE, "api.json")]
LIBS = [os.path.expanduser("~/.local/td/lib/libtdjson.so"), "/usr/lib/nullgram/libtdjson.so", "libtdjson.so"]
# the Apple emoji set (not in the package: Apple's pictures; downloaded by the user, OMMA-UCHUN.md): beside
# the app in a checkout (install.sh links it), else the user's cache
EMOJI_DIRS = [os.path.join(HERE, "emoji"), os.path.expanduser("~/.cache/nullgram-emoji")]
# its download (Ko'rinish › Emoji): emoji_get.py beside this file, in its own process, says how far it is here
EMOJI_DEST = os.path.expanduser("~/.cache/nullgram-emoji")
EMOJI_GET = os.path.join(HERE, "emoji_get.py")
EMOJI_STATUS = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "nullgram-emoji.json")
VERSION = "0.9.3"
CLIENT_ID = re.compile(r'"@client_id":(\d+)')
VENDOR = os.path.join(HERE, "vendor")	# qrcode (install.sh)
if os.path.isdir(VENDOR):
	sys.path.insert(0, VENDOR)
# NULLGRAM_FPS (see main): what each frame did, counted -- rows made, pictures asked, TDLib's answers -- and
# printed by a late frame's line, to tell what held it
FPS = bool(os.environ.get("NULLGRAM_FPS"))
MARKS = {}


def mark(name, n=1):
	MARKS[name] = MARKS.get(name, 0) + n


def _load():
	for path in LIBS:
		try:
			lib = ctypes.CDLL(path)
			break
		except OSError:
			continue
	else:
		raise SystemExit("libtdjson.so not found (" + ", ".join(LIBS) + ")")
	lib.td_create_client_id.restype = ctypes.c_int
	lib.td_send.argtypes = [ctypes.c_int, ctypes.c_char_p]
	lib.td_receive.argtypes = [ctypes.c_double]
	lib.td_receive.restype = ctypes.c_char_p
	lib.td_execute.argtypes = [ctypes.c_char_p]
	lib.td_execute.restype = ctypes.c_char_p
	return lib


def read_key():
	"""(api_id, api_hash, path) of the first usable key in KEYS, or (0, "", "") with none: the app then
	asks for one at sign-in instead of failing."""
	for path in KEYS:
		try:
			with open(path) as f:
				key = json.load(f)
			if int(key["id"]) > 0 and key["hash"]:
				return int(key["id"]), str(key["hash"]), path
		except (OSError, ValueError, KeyError, TypeError):
			continue
	return 0, "", ""


def device_names():
	"""(device, system) as the account's «Qurilmalar» list shows this session: the phone's own model
	(the device tree's) and the system's name and version (os-release), not a fixed "OmonullOS"."""
	device = ""
	try:
		with open("/proc/device-tree/model", "rb") as f:
			device = f.read().rstrip(b"\0\n").decode(errors="replace").strip()
	except OSError:
		pass
	osr = {}
	try:
		with open("/etc/os-release") as f:
			for line in f:
				k, _, v = line.strip().partition("=")
				osr[k] = v.strip('"')
	except OSError:
		pass
	system = " ".join(x for x in (osr.get("NAME") or "Linux", osr.get("VERSION_ID", "")) if x)
	return device or "Linux phone", system


def round_note_file(src, start, dur, mirrored, audio, out):
	"""A round video's file as Telegram wants one (384×384 square H.264 MP4, AAC): `dur` ms of `src` from
	`start` ms (round again from its start if it ends), cut to its middle square, mirrored if asked, with the
	sound recorded meanwhile (`audio`, the microphone's) or silence. While omonullOS has no camera, `src`
	is NULLGRAM_FAKE_CAMERA: the file standing in for it. Its path on success, else ""."""
	os.makedirs(os.path.dirname(out), exist_ok=True)
	vf = "crop='min(iw,ih)':'min(iw,ih)',scale=384:384,setsar=1" + (",hflip" if mirrored else "")
	cmd = ["ffmpeg", "-v", "error", "-y", "-stream_loop", "-1", "-ss", "%.3f" % (start / 1000.0), "-i", src]
	if audio and os.path.isfile(audio) and os.path.getsize(audio) > 200:
		cmd += ["-i", audio]
	else:
		cmd += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono"]
	cmd += ["-map", "0:v:0", "-map", "1:a:0", "-t", "%.3f" % (dur / 1000.0), "-vf", vf, "-r", "30",
	        "-c:v", "libx264", "-preset", "veryfast", "-crf", "27", "-pix_fmt", "yuv420p",
	        "-c:a", "aac", "-b:a", "64k", "-ac", "1", "-movflags", "+faststart", out]
	try:
		ok = subprocess.run(cmd, timeout=180).returncode == 0
	except (OSError, subprocess.TimeoutExpired):
		ok = False
	return out if ok and os.path.isfile(out) else ""


class _VideoStream:
	"""Loopback HTTP Range server over TDLib files so Qt MediaPlayer (FFmpeg) streams story videos
	immediately from partial byte ranges instead of waiting for a full 10-20 MB download."""

	def __init__(self, td):
		self.td = td
		self.lock = threading.Lock()
		self.cond = threading.Condition(self.lock)
		self.files = {}			# file_id -> latest TDLib file dict, only for files handed out by url()
		self.wanted = set()		# file ids url() was asked for: the only ones the server serves or remembers
		# a secret in every URL: without it any other program on the phone (or a web page in a browser)
		# could ask 127.0.0.1:<port> for any TDLib file by its small numeric id
		self.token = secrets.token_urlsafe(18)
		self._seq = 0
		self._wait = {}			# extra -> (Event, [result])
		stream = self

		class Handler(BaseHTTPRequestHandler):
			protocol_version = "HTTP/1.1"

			def log_message(self, fmt, *args):
				pass

			def _parse_id(self):
				u = urlparse(self.path)
				m = re.match(r"^/([A-Za-z0-9_-]+)/file/(\d+)(?:\.[a-z0-9]+)?$", u.path)
				if not m or not secrets.compare_digest(m.group(1), stream.token):
					return 0, 0
				fid = int(m.group(2))
				with stream.lock:
					if fid not in stream.wanted:
						return 0, 0
				qs = parse_qs(u.query)
				try:
					hint = int(qs.get("size", ["0"])[0] or 0)
				except ValueError:
					hint = 0
				return fid, hint

			def _file_info(self, fid, hint):
				with stream.lock:
					f = stream.files.get(fid)
				if not f or not (f.get("size") or f.get("expected_size")):
					r = stream.call({"@type": "getFile", "file_id": fid}, 3.0)
					if r and r.get("@type") == "file":
						stream.on_file(r)
						f = r
				total = 0
				if f:
					total = int(f.get("size") or f.get("expected_size") or 0)
				if not total:
					total = hint
				return f, total

			def do_HEAD(self):
				fid, hint = self._parse_id()
				if not fid:
					self.send_error(404)
					return
				_, total = self._file_info(fid, hint)
				if total <= 0:
					self.send_error(404)
					return
				self.send_response(200)
				self.send_header("Content-Type", "video/mp4")
				self.send_header("Accept-Ranges", "bytes")
				self.send_header("Content-Length", str(total))
				self.send_header("Cache-Control", "no-store")
				self.end_headers()

			def do_GET(self):
				fid, hint = self._parse_id()
				if not fid:
					self.send_error(404)
					return
				f, total = self._file_info(fid, hint)
				if total <= 0:
					self.send_error(404)
					return
				rng = self.headers.get("Range", "")
				start, end = 0, total - 1
				partial = False
				if rng.startswith("bytes="):
					partial = True
					spec = rng[6:].split(",")[0].strip()
					a, _, b = spec.partition("-")
					if a == "":
						n = int(b or 0)
						start = max(0, total - n)
					else:
						start = int(a)
						if b:
							end = min(total - 1, int(b))
				if start >= total or start > end:
					self.send_response(416)
					self.send_header("Content-Range", f"bytes */{total}")
					self.end_headers()
					return
				length = end - start + 1
				self.send_response(206 if partial else 200)
				self.send_header("Content-Type", "video/mp4")
				self.send_header("Accept-Ranges", "bytes")
				if partial:
					self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
				self.send_header("Content-Length", str(length))
				self.send_header("Cache-Control", "no-store")
				self.end_headers()
				try:
					pos = start
					prefetched = -1
					while pos <= end:
						path, avail, done = stream.wait_range(fid, pos, total)
						if not path or avail <= 0:
							break
						want = min(avail, end - pos + 1, 262144)
						if not done and pos + avail <= end and (pos + avail) - (pos + want) < 262144 and prefetched < pos + avail:
							prefetched = pos + avail
							lim = min(524288, total - prefetched)
							if lim > 0:
								stream.kick(fid, prefetched, lim)
						with open(path, "rb") as fp:
							fp.seek(pos)
							buf = fp.read(want)
						if not buf:
							break
						self.wfile.write(buf)
						pos += len(buf)
				except (BrokenPipeError, ConnectionResetError, OSError):
					pass

		self.srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
		self.srv.daemon_threads = True
		self.port = self.srv.server_address[1]
		threading.Thread(target=self.srv.serve_forever, name="stream", daemon=True).start()

	def url(self, fid: int, size: int) -> str:
		with self.lock:
			self.wanted.add(int(fid))
		return f"http://127.0.0.1:{self.port}/{self.token}/file/{fid}.mp4?size={max(0, int(size))}"

	def on_file(self, f: dict):
		fid = f.get("id")
		if not fid:
			return
		with self.cond:
			if fid not in self.wanted:		# every other file's updates: not ours to keep
				return
			self.files[fid] = f
			self.cond.notify_all()

	def on_extra(self, extra: str, obj: dict):
		with self.lock:
			w = self._wait.pop(extra, None)
		if w:
			w[1].append(obj)
			w[0].set()

	def call(self, req: dict, timeout: float = 2.0):
		with self.lock:
			self._seq += 1
			ex = f"_st:{self._seq}"
			ev = threading.Event()
			box = []
			self._wait[ex] = (ev, box)
		req = dict(req)
		req["@extra"] = ex
		self.td.send(json.dumps(req))
		if ev.wait(timeout) and box:
			return box[0]
		with self.lock:
			self._wait.pop(ex, None)
		return None

	def kick(self, fid: int, offset: int, limit: int):
		self.td.send(json.dumps({"@type": "downloadFile", "file_id": fid, "priority": 32,
		                         "offset": int(offset), "limit": int(limit), "synchronous": False,
		                         "@extra": "_st:0"}))

	def wait_range(self, fid: int, pos: int, total: int):
		"""Ensure bytes starting at `pos` are on disk, returning (path, avail_bytes, is_completed)."""
		# a slow network or a big video: wait long, and ask again every few seconds (another reader of the
		# same file — the player opens several connections — may have moved TDLib's offset elsewhere)
		deadline = time.monotonic() + 45.0
		next_kick = 0.0
		while time.monotonic() < deadline:
			with self.lock:
				f = self.files.get(fid)
			loc = f.get("local") if f else None
			path = loc.get("path", "") if loc else ""
			if loc and loc.get("is_downloading_completed") and path and os.path.exists(path):
				return path, max(0, total - pos), True
			if path and os.path.exists(path):
				r = self.call({"@type": "getFileDownloadedPrefixSize", "file_id": fid, "offset": pos}, 1.5)
				if r and r.get("@type") == "fileDownloadedPrefixSize":
					# TDLib 1.8.x answers `size` (older ones `count`): reading only `count` saw 0 always, so a
					# story played only once the whole file was down within the wait
					n = int(r.get("size", r.get("count")) or 0)
					if n > 0:
						return path, n, False
			now = time.monotonic()
			if now >= next_kick:
				lim = min(524288, max(65536, total - pos))
				self.kick(fid, pos, lim)
				next_kick = now + 3.0
			with self.cond:
				self.cond.wait(0.2)
		return "", 0, False


class Td(QObject):
	"""One TDLib client. `received` carries each update or answer as TDLib's JSON text."""
	received = Signal(str)

	def __init__(self):
		super().__init__()
		self.lib = _load()
		self.lib.td_execute(json.dumps({"@type": "setLogVerbosityLevel", "new_verbosity_level": 1}).encode())
		self.client = self.lib.td_create_client_id()
		self._id, self._hash, self._key_path = read_key()
		self._device, self._system = device_names()
		os.makedirs(DATA, exist_ok=True)
		self.closed = threading.Event()
		self._stream = None

	def start(self):
		"""Once QML listens: a signal sent before anyone is connected is lost, and with it
		TDLib's first update (asking for the parameters) -- the app would wait on a blank page."""
		threading.Thread(target=self._receive, name="td", daemon=True).start()
		# TDLib starts the client on its first request; until then no updates come
		self.send(json.dumps({"@type": "getOption", "name": "version"}))

	def _receive(self):
		while True:
			r = self.lib.td_receive(10.0)
			if r:
				r = r.decode()
				# a closed client's late words (a QR asked for, then the number: renew()) are not the
				# new client's; TDLib puts "@client_id" last
				m = CLIENT_ID.search(r, max(0, len(r) - 40))
				if m and int(m.group(1)) != self.client:
					continue
				if '"authorizationStateClosed"' in r:
					self.closed.set()
				# unused here, and big (2-3 MB of JSON, twice at the start): parsing it held the UI thread 0.15 s
				if '"updateTrendingStickerSets"' in r[:64]:
					continue
				st = self._stream
				if st is not None:
					if '"_st:' in r:
						obj = json.loads(r)
						ex = obj.get("@extra", "")
						if isinstance(ex, str) and ex.startswith("_st:"):
							if obj.get("@type") == "file":
								st.on_file(obj)
							if ex != "_st:0":
								st.on_extra(ex, obj)
							continue
					elif '"updateFile"' in r[:48]:
						obj = json.loads(r)
						if obj.get("@type") == "updateFile":
							st.on_file(obj["file"])
				if FPS:
					mark("td")
				self.received.emit(r)

	@Slot(int, int, result=str)
	def streamUrl(self, file_id: int, size: int = 0) -> str:
		"""Local HTTP Range URL for progressive video streaming via TDLib downloadFile."""
		if file_id <= 0:
			return ""
		if self._stream is None:
			self._stream = _VideoStream(self)
		return self._stream.url(file_id, size)

	def close(self, wait: float):
		"""TDLib asked to close (its database written out), waiting for it at most `wait` seconds."""
		self.send(json.dumps({"@type": "close"}))
		self.closed.wait(wait)

	@Slot(str)
	def send(self, request: str):
		self.lib.td_send(self.client, request.encode())

	@Slot()
	def renew(self):
		"""Before signing in, a closed client (a QR asked for, then the number chosen: TDLib takes a number
		only in WaitPhoneNumber, and leaves WaitOtherDeviceConfirmation only by closing) is followed by a new
		one, here in the same app: nothing of an account is loaded yet."""
		print("nullgram: a new TDLib client", flush=True)
		self.closed.clear()
		self.client = self.lib.td_create_client_id()
		self.send(json.dumps({"@type": "getOption", "name": "version"}))

	@Slot()
	def restart(self):
		"""Signed out (here or from another device): TDLib has closed this client and wiped its database.
		The app starts itself afresh (the same process, exec'd), which brings the sign-in with nothing
		of the old account left in QML. (Its picture helpers see their pipes close and end.)"""
		print("nullgram: signed out, starting again", flush=True)
		tile_clear()
		sys.stdout.flush()
		sys.stderr.flush()
		os.execv(sys.executable, [sys.executable] + sys.argv)

	@Slot(str, result="QVariantList")
	def qrHigh(self, text: str) -> list:
		"""As qr, at level H (30% may be lost): a picture laid over its middle (Settings' QR, QrSheet) costs nothing."""
		import qrcode
		q = qrcode.QRCode(border=0, error_correction=qrcode.constants.ERROR_CORRECT_H)
		q.add_data(text)
		q.make(fit=True)
		return ["".join("1" if c else "0" for c in row) for row in q.get_matrix()]

	@Slot(str, result="QVariantList")
	def qr(self, text: str) -> list:
		"""A QR code's rows, each a string of 0 and 1 (QML draws them)."""
		import qrcode
		q = qrcode.QRCode(border=0, error_correction=qrcode.constants.ERROR_CORRECT_M)
		q.add_data(text)
		q.make(fit=True)
		return ["".join("1" if c else "0" for c in row) for row in q.get_matrix()]

	@Slot(str, str, result=str)
	def save(self, path: str, name: str) -> str:
		"""A downloaded file copied to ~/Downloads under its own name (a number added when that is
		taken): where it went, or "" when it could not be."""
		out = os.path.expanduser("~/Downloads")
		os.makedirs(out, exist_ok=True)
		base, ext = os.path.splitext(os.path.basename(name or path))
		to = os.path.join(out, base + ext)
		n = 1
		while os.path.exists(to):
			n += 1
			to = os.path.join(out, "%s (%d)%s" % (base, n, ext))
		try:
			shutil.copyfile(path, to)
		except OSError:
			return ""
		return to

	@Slot(result="QVariantList")
	def recent(self) -> list:
		"""The phone's own files to send, newest first: {path, name, size, kind (photo, video, audio,
		file), w, h}. Only from the user's folders, a level or two down -- not the app's own."""
		roots = ["~/Pictures", "~/Rasmlar", "~/Videos", "~/Music", "~/Downloads", "~/Documents", "~/DCIM"]
		found = []
		for root in roots:
			root = os.path.expanduser(root)
			for top, dirs, names in os.walk(root):
				if top.count(os.sep) - root.count(os.sep) >= 2:
					dirs[:] = []
				dirs[:] = [d for d in dirs if not d.startswith(".")]
				for n in names:
					f = os.path.join(top, n)
					if n.startswith(".") or not os.path.isfile(f):
						continue
					found.append((os.path.getmtime(f), f))
		found.sort(reverse=True)
		out = []
		for _, f in found[:300]:
			ext = os.path.splitext(f)[1].lower()
			kind = PHOTO.get(ext) or VIDEO.get(ext) or AUDIO.get(ext) or "file"
			w = h = 0
			if kind == "photo":
				size = QImageReader(f).size()
				w, h = size.width(), size.height()
			out.append({"path": f, "name": os.path.basename(f), "size": os.path.getsize(f), "kind": kind, "w": w, "h": h})
		return out

	@Slot(str, result="QVariantMap")
	def probe(self, path: str) -> dict:
		"""A video's or a sound's length (seconds), width and height, by ffprobe."""
		try:
			r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
			                    "stream=width,height:format=duration", "-of", "json", path],
			                   capture_output=True, text=True, timeout=10)
			j = json.loads(r.stdout or "{}")
		except (OSError, ValueError, subprocess.TimeoutExpired):
			return {"duration": 0, "width": 0, "height": 0}
		st = (j.get("streams") or [{}])[0]
		return {"duration": int(float(j.get("format", {}).get("duration", 0)) + 0.5),
		        "width": st.get("width", 0), "height": st.get("height", 0)}

	@Slot(str, result="QVariantMap")
	def voice(self, path: str) -> dict:
		"""A voice note's length and Telegram's waveform for it: 100 loudness values of 5 bits,
		packed low bit first (base64), as Telegram-iOS makes it (audioWaveform in its encoder)."""
		try:
			pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
			                     capture_output=True, timeout=20).stdout
		except (OSError, subprocess.TimeoutExpired):
			pcm = b""
		samples = memoryview(pcm).cast("h") if len(pcm) >= 2 else []
		n = len(samples)
		peaks = []
		for k in range(100):
			part = samples[k * n // 100:(k + 1) * n // 100]
			peaks.append(max((abs(v) for v in part), default=0))
		top = max(peaks) or 1
		bits = 0
		value = 0
		out = bytearray()
		for p in peaks:
			value |= (min(31, p * 31 // top)) << bits
			bits += 5
			while bits >= 8:
				out.append(value & 0xff)
				value >>= 8
				bits -= 8
		if bits:
			out.append(value & 0xff)
		return {"duration": max(1, round(n / 8000)), "waveform": base64.b64encode(bytes(out)).decode()}

	@Slot(str, str, bool)
	def notify(self, title: str, body: str, quiet: bool = False):
		"""A banner through the desktop's notification service (ztnotifyd), by gdbus: its arguments
		as GVariant text, so nothing in the message is read as anything else. `quiet`: without its sound
		(the freedesktop hint suppress-sound: the Bildirishnomalar page's «Ilova ichidagi ovozlar» off, the app in front)."""
		def text(v):
			return "'" + v.replace("\\", "\\\\").replace("'", "\\'").replace("\n", " ") + "'"
		print("nullgram: banner from", title, flush=True)	# (not what it says)
		try:
			subprocess.Popen(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
			                  "--object-path", "/org/freedesktop/Notifications",
			                  "--method", "org.freedesktop.Notifications.Notify",
			                  "'Nullgram'", "0", "''", text(title), text(body[:300]), "[]",
			                  "{'suppress-sound': <true>}" if quiet else "{}", "5000"],
			                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
		except OSError:
			pass

	@Slot(str, "QVariantList", int)
	def tile(self, title: str, lines: list, count: int):
		"""The Start tile's back (the shell reads $XDG_RUNTIME_DIR/ztos-live/<the starter's name>):
		up to three lines and the count on its corner; nothing to show takes it away."""
		if not count and not lines:
			tile_clear()
			return
		os.makedirs(os.path.dirname(TILE), exist_ok=True)
		text = "title=%s\n" % title.replace("\n", " ")
		for line in lines[:3]:
			text += "line=%s\n" % str(line).replace("\n", " ")[:60]
		text += "count=%d\n" % count
		with open(TILE + ".new", "w") as f:
			f.write(text)
		os.replace(TILE + ".new", TILE)

	roundMade = Signal(str, int)		# a round video's file made (its path, "" if not; seconds)

	@Slot(str, int, int, bool, str)
	def roundNote(self, src: str, start: int, dur: int, mirrored: bool, audio: str):
		"""round_note_file on a thread of its own (ffmpeg takes a second or two): roundMade when done."""
		out = os.path.join(DATA, "round", "%d.mp4" % int(time.time() * 1000))
		def work():
			self.roundMade.emit(round_note_file(src, start, dur, mirrored, audio, out), max(1, round(dur / 1000)))
		threading.Thread(target=work, daemon=True).start()

	# the file standing in for the camera (NULLGRAM_FAKE_CAMERA), "" for none: a round video's whole way but
	# the camera, until omonullOS has one (tools/fakemic.sh does the same for the microphone)
	fakeCamera = Property(str, lambda self: os.path.expanduser(os.environ.get("NULLGRAM_FAKE_CAMERA", "")), constant=True)

	@Slot(result="QVariantList")
	def disk(self):
		"""The home's disk: [free, total] bytes (Xotiradan foydalanish's «… of your free disk space»)."""
		try:
			u = shutil.disk_usage(os.path.expanduser("~"))
			return [float(u.free), float(u.total)]
		except OSError:
			return [0.0, 0.0]

	@Slot(result=str)
	def voicePath(self) -> str:
		"""Where the next voice note is recorded."""
		d = os.path.join(DATA, "voice")
		os.makedirs(d, exist_ok=True)
		return os.path.join(d, "%d.ogg" % (len(os.listdir(d)) + 1))

	apiId = Property(int, lambda self: self._id, constant=True)
	apiHash = Property(str, lambda self: self._hash, constant=True)
	# where the key came from: "own" (the user's), "local" (install.sh's), "package", "" (none: asked for)
	keySource = Property(str, lambda self: {OWN_KEY: "own", KEYS[1]: "local", KEYS[2]: "package"}.get(
		self._key_path, ""), constant=True)
	deviceModel = Property(str, lambda self: self._device, constant=True)
	systemVersion = Property(str, lambda self: self._system, constant=True)
	appVersion = Property(str, lambda self: "Nullgram " + VERSION, constant=True)

	@Slot(str, str, result=bool)
	def setOwnKey(self, api_id: str, api_hash: str) -> bool:
		"""The user's own key (my.telegram.org) saved, used from the next start on; empty both: removed,
		back to the packaged one. False if it does not look like a key (a number and 32 hex digits)."""
		api_id, api_hash = api_id.strip(), api_hash.strip().lower()
		if not api_id and not api_hash:
			try:
				os.remove(OWN_KEY)
			except FileNotFoundError:
				pass
			return True
		if not api_id.isdigit() or int(api_id) <= 0 or not re.fullmatch(r"[0-9a-f]{32}", api_hash):
			return False
		os.makedirs(KEYDIR, exist_ok=True)
		tmp = OWN_KEY + ".new"
		fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
		with os.fdopen(fd, "w") as f:
			json.dump({"id": int(api_id), "hash": api_hash}, f)
		os.replace(tmp, OWN_KEY)
		return True

	@Slot(result="QVariantMap")
	def ownKey(self) -> dict:
		"""The user's own key as saved ({} without one), for the Settings page's fields."""
		try:
			with open(OWN_KEY) as f:
				k = json.load(f)
			return {"id": str(k.get("id", "")), "hash": str(k.get("hash", ""))}
		except (OSError, ValueError):
			return {}
	dataDir = Property(str, lambda self: DATA, constant=True)
	testDc = Property(bool, lambda self: TEST, constant=True)
	# NULLGRAM_FPS: QML counts what it does into the late frames' lines (only then: td.fps first)
	fps = Property(bool, lambda self: FPS, constant=True)
	# Apple's emoji drawn as pictures (Emo.qml) when the set is downloaded (Ko'rinish › Emoji, emoji_get.py) and
	# chosen: Nullgram's own choice (Prefs.emoji), else omonullOS Settings'; without the set, the font draws them.
	# Both change when a download ends or the set is deleted (emojiChanged; the page asks emojiStatus).
	emojiChanged = Signal()
	appleEmoji = Property(bool, lambda self: apple_emoji(), notify=emojiChanged)
	emojiDir = Property(str, lambda self: emoji_dir(), notify=emojiChanged)

	@Slot(result="QVariantMap")
	def emojiStatus(self) -> dict:
		"""How the Apple set's download goes (emoji_get.py's status file): state none|start|download|stopped|
		error|done, done/total pictures, bytes, est (all the bytes, guessed), speed (bytes/s), left (s);
		`have`: the set is in place. A download whose process is gone is "stopped"."""
		try:
			with open(EMOJI_STATUS) as f:
				st = json.load(f)
		except (OSError, ValueError):
			st = {}
		if st.get("state") in ("start", "download") and not emoji_alive(st.get("pid")):
			st["state"] = "stopped"
		st.setdefault("state", "none")
		st["have"] = emoji_dir() != ""
		st["part"] = os.path.isdir(EMOJI_DEST + ".part")	# a stopped one waits to go on
		if st["have"] != getattr(self, "_had_emoji", None):
			if hasattr(self, "_had_emoji"):
				self.emojiChanged.emit()
			self._had_emoji = st["have"]
		return st

	@Slot()
	def emojiStart(self):
		"""The download, in its own session: it goes on when the app is closed."""
		if self.emojiStatus()["state"] in ("start", "download"):
			return
		subprocess.Popen([sys.executable, EMOJI_GET], start_new_session=True, stdin=subprocess.DEVNULL,
		                 stdout=subprocess.DEVNULL, stderr=open(EMOJI_STATUS + ".log", "w"))

	@Slot()
	def emojiStop(self):
		subprocess.Popen([sys.executable, EMOJI_GET, "--stop"], start_new_session=True,
		                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

	@Slot()
	def emojiRemove(self):
		subprocess.run([sys.executable, EMOJI_GET, "--remove"], stdout=subprocess.DEVNULL,
		               stderr=subprocess.DEVNULL, timeout=30)
		self.emojiStatus()
	# omonullOS Settings' language ("uz" or "en"): Nullgram speaks it unless its own Til page chose one
	systemLang = Property(str, lambda self: system_lang(), constant=True)

	@Slot(str, int)
	def mark(self, name: str, n: int):
		mark(name, n)
	# on the test servers only: sign in by itself with this number (99966XYYYY, the code is X five times)
	# for testing from the PC: open this chat (its id) once the chats are there (run.sh passes it on)
	devOpen = Property(str, lambda self: os.environ.get("NULLGRAM_OPEN", ""), constant=True)
	# and send it these lines, one message each (only with NULLGRAM_OPEN)
	devSay = Property(str, lambda self: os.environ.get("NULLGRAM_SAY", ""), constant=True)
	# or search it for this
	devFind = Property(str, lambda self: os.environ.get("NULLGRAM_FIND", ""), constant=True)
	testPhone = Property(str, lambda self: os.environ.get("NULLGRAM_TEST_PHONE", "") if TEST else "", constant=True)


class Osk(QObject):
	"""The shell's keyboard, for moving the chat over it ourselves (iOS: the header stays, the
	messages and the field go up with the keyboard). The shell is told so ("osk room") and no
	longer lifts the whole window; it writes $XDG_RUNTIME_DIR/ztos-osk ("shown|hidden H MS")
	whenever the keyboard comes or goes. `h`: how much of the window it covers, in points;
	`ms`: how long it takes to get there (an ease-out, QML's Easing.OutExpo)."""
	changed = Signal()

	def __init__(self):
		super().__init__()
		run = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
		self._path = os.path.join(run, "ztos-osk")
		self._h, self._ms = 0, 200
		self._ctl = os.path.join(run, "ztmetro.ctl")
		self._tell(b"osk room ztos.uz.omonullos.nullgram\n")
		# the file is replaced (a rename), so it is its directory that is watched
		self._watch = QFileSystemWatcher([run])
		self._watch.directoryChanged.connect(self._read)
		self._read()

	def _read(self, *_):
		try:
			with open(self._path) as f:
				state, h, ms = f.read().split()
			h, ms = (int(h) if state == "shown" else 0), int(ms)
		except (OSError, ValueError):
			return
		if (h, ms) != (self._h, self._ms):
			self._h, self._ms = h, ms
			self.changed.emit()

	def _tell(self, line):
		try:	# (a FIFO: without O_NONBLOCK, no shell reading it would hang us here)
			fd = os.open(self._ctl, os.O_WRONLY | os.O_NONBLOCK)
			os.write(fd, line)
			os.close(fd)
		except OSError:
			pass

	@Slot()
	def hide(self):
		"""Down now: a page leaving with its field. Qt's text input tells the shell only once
		the field is gone, at the end of the page's slide."""
		self._tell(b"osk hide\n")

	h = Property(int, lambda self: self._h, notify=changed)
	ms = Property(int, lambda self: self._ms, notify=changed)


class Safe(QObject):
	"""How far from the bottom edge our buttons keep (iOS's safe area): over ztMETRO's nav line the
	shell gives us the whole height, with no strip of our colour under us, once told we keep clear of
	the line ourselves ("safe area"). It writes $XDG_RUNTIME_DIR/ztos-safe ("bottom N", points) at
	every config load; 0 with the buttons, or a shell that has no line."""
	changed = Signal()

	def __init__(self):
		super().__init__()
		run = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
		self._path = os.path.join(run, "ztos-safe")
		self._bottom = 0
		try:
			fd = os.open(os.path.join(run, "ztmetro.ctl"), os.O_WRONLY | os.O_NONBLOCK)
			os.write(fd, b"safe area ztos.uz.omonullos.nullgram\n")
			os.close(fd)
		except OSError:
			pass
		self._watch = QFileSystemWatcher([run])
		self._watch.directoryChanged.connect(self._read)
		self._read()

	def _read(self, *_):
		try:
			with open(self._path) as f:
				key, n = f.read().split()
			n = max(0, min(int(n), 60)) if key == "bottom" else 0
		except (OSError, ValueError):
			return
		if n != self._bottom:
			self._bottom = n
			self.changed.emit()

	bottom = Property(int, lambda self: self._bottom, notify=changed)


class Net(QObject):
	"""Which way the phone is online, for Ma'lumotlar va xotira (Telegram-iOS's auto-download by network: Using Cellular
	/ Using Wi-Fi) and TDLib's setNetworkType (its traffic counted per network): `kind` "wifi" when a wireless interface
	(/sys/class/net/*/wireless) is up, else "mobile" when a modem's (rmnet*, wwan*, ccmni*) is, else "none"; looked at
	every 20 s. May be written (the desk's scenes)."""
	changed = Signal()
	ROOT = "/sys/class/net"

	def __init__(self):
		super().__init__()
		self._kind = "wifi"
		self._timer = QTimer(self)
		self._timer.setInterval(20000)
		self._timer.timeout.connect(self._read)
		if os.path.isdir(self.ROOT) and not os.environ.get("NULLGRAM_DESK"):
			self._timer.start()
			self._read()

	def _read(self):
		kind = "none"
		try:
			for d in sorted(os.listdir(self.ROOT)):
				try:
					with open(os.path.join(self.ROOT, d, "operstate")) as f:
						up = f.read().strip() == "up"
				except OSError:
					continue
				if not up:
					continue
				if os.path.isdir(os.path.join(self.ROOT, d, "wireless")):
					kind = "wifi"
					break
				if d.startswith(("rmnet", "wwan", "ccmni")):
					kind = "mobile"
		except OSError:
			return
		self._set(kind)

	def _set(self, v):
		if v != self._kind:
			self._kind = v
			self.changed.emit()

	kind = Property(str, lambda self: self._kind, _set, notify=changed)


class Meter(QObject):
	"""How loud the microphone is while a voice note records (Telegram-iOS's blob round the mic grows with
	it): the default input read beside the recorder (QAudioSource, 16 kHz mono), its loudest sample of
	each read, 0..1, fast up and slow down. QML has no level of its own; ~20 reads a second, a max each."""
	changed = Signal()

	def __init__(self):
		super().__init__()
		self._level = 0.0
		self._src = None
		self._io = None

	@Slot()
	def start(self):
		from PySide6.QtMultimedia import QAudioFormat, QAudioSource, QMediaDevices
		self.stop()
		dev = QMediaDevices.defaultAudioInput()
		if dev.isNull():
			return
		fmt = QAudioFormat()
		fmt.setSampleRate(16000)
		fmt.setChannelCount(1)
		fmt.setSampleFormat(QAudioFormat.Int16)
		self._src = QAudioSource(dev, fmt, self)
		self._src.setBufferSize(1600)		# (50 ms)
		self._io = self._src.start()
		if self._io is not None:
			self._io.readyRead.connect(self._read)

	def _read(self):
		data = bytes(self._io.readAll()) if self._io is not None else b""
		if len(data) < 2:
			return
		peak = max(abs(v) for v in memoryview(data[:len(data) & ~1]).cast("h")) / 32768.0
		self._level = peak if peak > self._level else self._level * 0.75 + peak * 0.25
		self.changed.emit()

	@Slot()
	def stop(self):
		if self._src is not None:
			self._src.stop()
			self._src.deleteLater()
		self._src = self._io = None
		if self._level:
			self._level = 0.0
			self.changed.emit()

	level = Property(float, lambda self: self._level, notify=changed)


class Battery(QObject):
	"""The phone's charge, for the Quvvat tejash page (Telegram-iOS's EnergySavingSettingsScreen: everything heavy
	off below a level the user picks, unless charging): the kernel's battery (/sys/class/power_supply, its
	«Battery» one), else what OmonullOS's zlowbatt writes (/run/zbatt: `capacity` from the S10 5G's fuel gauge,
	`online` 1 on the cable — its kernel has no power_supply; the status bar reads it too), looked at once a minute. `level` 0..100, -1 with none (the desk); `charging` when on the
	cable. Both may be written (the desk's scenes)."""
	changed = Signal()
	ROOT = "/sys/class/power_supply"

	def __init__(self):
		super().__init__()
		self._level, self._charging = -1, False
		self._dir = None
		try:
			for d in sorted(os.listdir(self.ROOT)):
				with open(os.path.join(self.ROOT, d, "type")) as f:
					if f.read().strip() == "Battery":
						self._dir = os.path.join(self.ROOT, d)
						break
		except OSError:
			pass
		self._zbatt = self._dir is None and os.path.exists("/run/zbatt/capacity")
		self._timer = QTimer(self)
		self._timer.setInterval(60000)
		self._timer.timeout.connect(self._read)
		if self._dir or self._zbatt:
			self._timer.start()
			self._read()

	def _read(self):
		try:
			if self._dir:
				with open(os.path.join(self._dir, "capacity")) as f:
					level = int(f.read().strip())
				with open(os.path.join(self._dir, "status")) as f:
					charging = f.read().strip() in ("Charging", "Full")
			else:
				with open("/run/zbatt/capacity") as f:
					level = int(f.read().strip())
				try:
					with open("/run/zbatt/online") as f:
						charging = f.read().strip() == "1"
				except OSError:
					charging = False
		except (OSError, ValueError):
			return
		if (level, charging) != (self._level, self._charging):
			self._level, self._charging = level, charging
			self.changed.emit()

	def _set_level(self, v):
		if v != self._level:
			self._level = v
			self.changed.emit()

	def _set_charging(self, v):
		if v != self._charging:
			self._charging = v
			self.changed.emit()

	level = Property(int, lambda self: self._level, _set_level, notify=changed)
	charging = Property(bool, lambda self: self._charging, _set_charging, notify=changed)


TILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ztos-live", "uz.omonullos.nullgram")


def tile_clear():
	try:
		os.remove(TILE)
	except OSError:
		pass


PHOTO = dict.fromkeys([".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"], "photo")
VIDEO = dict.fromkeys([".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v"], "video")
AUDIO = dict.fromkeys([".mp3", ".ogg", ".oga", ".opus", ".m4a", ".flac", ".wav", ".aac"], "audio")


class Ink(QObject):
	"""The field's formatting drawn in the field (Telegram-iOS shows a message's bold, links, code
	as it is written or edited). The marks are TDLib textEntity's, kept by ChatPage as the words
	change; here they are only painted, a QSyntaxHighlighter on the TextEdit's document. Offsets
	are UTF-16, as the document's own positions."""

	class _Paint(QSyntaxHighlighter):
		def __init__(self, doc):
			super().__init__(doc)
			self.marks, self.accent = [], QColor("#0088ff")

		def highlightBlock(self, _text):
			block = self.currentBlock()
			at, n = block.position(), block.length() - 1
			here = [(k, max(o, at) - at, min(o + l, at + n) - at) for k, o, l in self.marks
			        if max(o, at) < min(o + l, at + n)]
			# cut where any mark starts or ends; each piece gets every mark over it (bold and italic)
			cuts = sorted({0, n} | {x for _, a, b in here for x in (a, b)})
			for a, b in zip(cuts, cuts[1:]):
				f = QTextCharFormat()
				for kind, x, y in here:
					if x <= a and y >= b:
						self._mark(f, kind)
				self.setFormat(a, b - a, f)

		def _mark(self, f, kind):
			if kind == "textEntityTypeBold":
				f.setFontWeight(QFont.DemiBold)
			elif kind == "textEntityTypeItalic":
				f.setFontItalic(True)
			elif kind == "textEntityTypeUnderline":
				f.setFontUnderline(True)
			elif kind == "textEntityTypeStrikethrough":
				f.setFontStrikeOut(True)
			elif kind in ("textEntityTypeCode", "textEntityTypePre", "textEntityTypePreCode"):
				f.setFontFamilies(["monospace"])
			elif kind in ("textEntityTypeTextUrl", "textEntityTypeMentionName"):
				f.setForeground(self.accent)
			elif kind == "textEntityTypeSpoiler":
				f.setBackground(QColor(128, 128, 128, 90))
			elif kind in ("textEntityTypeBlockQuote", "textEntityTypeExpandableBlockQuote"):
				f.setBackground(QColor(self.accent.red(), self.accent.green(), self.accent.blue(), 36))

	def __init__(self):
		super().__init__()
		self._paints = {}

	@Slot(QObject, "QVariantList", QColor)
	def paint(self, quick, marks, accent):
		doc = quick.textDocument()
		p = self._paints.get(id(doc))
		if p is None:
			p = self._paints[id(doc)] = Ink._Paint(doc)
			doc.destroyed.connect(lambda *_, k=id(doc): self._paints.pop(k, None))
		p.marks = [(m["type"]["@type"], int(m["offset"]), int(m["length"])) for m in marks]
		p.accent = accent
		if FPS:
			t = time.perf_counter()
			p.rehighlight()
			mark("inkms", round((time.perf_counter() - t) * 1000))
		else:
			p.rehighlight()


class Imager:
	"""The pictures image://pic, round and thumb give, made in helper processes (nullgram.py
	--imager): PySide holds the interpreter's lock all through QImage's work, so made on Qt's
	loading threads they kept the UI thread waiting whenever it called into Python (sending to
	TDLib, a property): a flick through a group's pictures stood still up to 0.4 s. A loading thread
	here only waits on a pipe, which lets the lock go. Pixels come back raw, RGBA8888 premultiplied:
	what the texture is made of (from ARGB32, 6 MB a picture, converted on the render thread as a
	flick needed it)."""

	def __init__(self, n=2):
		self.free = queue.Queue()
		for _ in range(n):
			self.free.put(self.spawn())

	@staticmethod
	def spawn():
		return subprocess.Popen([sys.executable, os.path.abspath(__file__), "--imager"],
		                        stdin=subprocess.PIPE, stdout=subprocess.PIPE)

	def ask(self, kind, key, requested):
		"""The pixels are read straight into the picture, the lock let go while they come: made
		of the bytes and copied (.copy() under the lock) a chat's picture at 4x, 6 MB, kept the UI
		thread from Python 6 ms each -- and a flick asks for up to ten in a frame."""
		w, h = (requested.width(), requested.height()) if requested.isValid() else (-1, -1)
		p = self.free.get()
		try:
			p.stdin.write(("%s\t%d\t%d\t%s\n" % (kind, w, h, key)).encode())
			p.stdin.flush()
			w, h = (int(x) for x in p.stdout.readline().split())
			img = QImage(w, h, QImage.Format_RGBA8888_Premultiplied)
			if img.bytesPerLine() != 4 * w or p.stdout.readinto(img.bits()) < w * h * 4:
				raise OSError("short")
		except (OSError, ValueError):
			p.kill()
			p = self.spawn()
			img = QImage(1, 1, QImage.Format_ARGB32_Premultiplied)
			img.fill(0)
		finally:
			self.free.put(p)
		if FPS:
			mark("picKB", img.width() * img.height() // 256)
		return img


def imager():
	"""--imager: an Imager's helper: a line in (kind, width, height, key), the picture out."""
	os.environ["QT_QPA_PLATFORM"] = "offscreen"
	app = QGuiApplication(sys.argv[:1])
	makers = {"pic": make_pic, "round": make_round, "thumb": make_thumb}
	out = sys.stdout.buffer
	for line in sys.stdin.buffer:
		kind, w, h, key = line.decode().rstrip("\n").split("\t", 3)
		try:
			img = makers[kind](key, QSize(int(w), int(h)))
		except Exception as e:
			print("nullgram: imager:", kind, key[:80], e, file=sys.stderr, flush=True)
			img = QImage()
		if img.isNull():
			img = QImage(1, 1, QImage.Format_ARGB32_Premultiplied)
			img.fill(Qt.transparent)
		img = img.convertToFormat(QImage.Format_RGBA8888_Premultiplied)		# (the texture's own order: not swizzled on the render thread)
		out.write(b"%d %d\n" % (img.width(), img.height()))
		out.write(bytes(img.constBits())[:img.width() * img.height() * 4] if img.bytesPerLine() == 4 * img.width()
		          else b"".join(bytes(img.constScanLine(y))[:4 * img.width()] for y in range(img.height())))
		out.flush()
	del app


class Asked(QQuickImageProvider):
	"""image://<kind>/...: an Imager's picture, on Qt's image-loading threads."""

	def __init__(self, imager, kind):
		super().__init__(QQuickImageProvider.Image, QQuickImageProvider.ForceAsynchronousImageLoading)
		self.imager, self.kind = imager, kind

	def requestImage(self, key, size, requested):
		if FPS:
			mark(self.kind)
		return self.imager.ask(self.kind, key, requested)


THUMBS = os.path.expanduser("~/.cache/nullgram/thumbs")


def _still(path):
	"""A video file's still (a frame half a second in, by ffmpeg, kept in the cache); any other
	file itself."""
	if os.path.splitext(path)[1].lower() not in VIDEO or not os.path.isfile(path):
		return path
	os.makedirs(THUMBS, exist_ok=True)
	st = os.stat(path)
	key = hashlib.sha1(("%s %d %d" % (path, st.st_size, st.st_mtime)).encode()).hexdigest()
	src = os.path.join(THUMBS, key + ".jpg")
	if not os.path.exists(src):
		subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "0.5", "-i", path, "-frames:v", "1",
		                "-vf", "scale=320:-2", src], timeout=20)
	return src


def make_thumb(path, requested):
	"""image://thumb/<path>: a still of a video file, or the picture itself; for the attach sheet."""
	src = _still(path)
	r = QImageReader(src)
	r.setAutoTransform(True)
	if requested.isValid() and requested.width() > 0:
		full = r.size()
		if full.isValid() and full.width() > 0:
			k = max(requested.width() / full.width(), requested.height() / max(full.height(), 1))
			if k < 1:
				r.setScaledSize(full * k)
	img = r.read()
	return img if not img.isNull() else QImage(1, 1, QImage.Format_ARGB32_Premultiplied)


def make_round(path, requested):
	"""image://round/<path>: the picture cut to a circle at the size asked."""
	src = QImage(path.removeprefix("file://"))
	side = max(requested.width(), requested.height(), 1) if requested.isValid() else min(src.width(), src.height())
	out = QImage(side, side, QImage.Format_ARGB32_Premultiplied)
	out.fill(Qt.transparent)
	if not src.isNull():
		p = QPainter(out)
		p.setRenderHints(QPainter.Antialiasing | QPainter.SmoothPixmapTransform)
		clip = QPainterPath()
		clip.addEllipse(QRectF(0, 0, side, side))
		p.setClipPath(clip)
		big = src.scaled(side, side, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
		p.drawImage(0, 0, big, (big.width() - side) // 2, (big.height() - side) // 2, side, side)
		p.end()
	return out


def _corners(w, h, rs):
	"""A w×h rectangle whose corners (top left, top right, bottom right, bottom left) are rounded each by its own."""
	tl, tr, br, bl = rs
	path = QPainterPath()
	path.moveTo(tl, 0)
	path.lineTo(w - tr, 0)
	path.arcTo(QRectF(w - 2 * tr, 0, 2 * tr, 2 * tr), 90, -90)
	path.lineTo(w, h - br)
	path.arcTo(QRectF(w - 2 * br, h - 2 * br, 2 * br, 2 * br), 0, -90)
	path.lineTo(bl, h)
	path.arcTo(QRectF(0, h - 2 * bl, 2 * bl, 2 * bl), 270, -90)
	path.lineTo(0, tl)
	path.arcTo(QRectF(0, 0, 2 * tl, 2 * tl), 180, -90)
	path.closeSubpath()
	return path


def _box(img, r):
	"""Each row of a small picture blurred by a box 2r + 1 wide (its edges held), premultiplied ARGB."""
	w, h = img.width(), img.height()
	src = bytes(img.constBits())[:w * h * 4]	# (32 bits a pixel: rows are 4·w bytes, no padding)
	out = bytearray(len(src))
	k = 2 * r + 1
	for y in range(h):
		row = y * w * 4
		for c in range(4):
			v = src[row + c:row + w * 4:4]
			s = v[0] * (r + 1) + sum(v[min(i, w - 1)] for i in range(1, r + 1))
			for x in range(w):
				out[row + x * 4 + c] = s // k
				s += v[min(x + r + 1, w - 1)] - v[max(x - r, 0)]
	return QImage(bytes(out), w, h, 4 * w, QImage.Format_ARGB32_Premultiplied).copy()


def _blurred(src):
	"""A spoiler's picture: only its colours left (Telegram-iOS blurs it fitted in 100 points, twice,
	PhotoResources.swift's blurBackground). Fitted in 32 pixels, a box blur twice each way: near a
	Gaussian; drawn large from there it stays smooth."""
	img = src.scaled(32, 32, Qt.KeepAspectRatio, Qt.SmoothTransformation).convertToFormat(QImage.Format_ARGB32_Premultiplied)
	turn, back = QTransform().rotate(90), QTransform().rotate(-90)
	for _ in range(2):
		img = _box(_box(img, 2).transformed(turn), 2).transformed(back)
	return img


def make_pic(key, requested):
	"""image://pic/<radius>/<width>/<path> (or .../mini/<base64>): a message's picture at the size
	asked, cut to the middle, its corners rounded (radius 0: none; -1: a circle; "14,4,4,14": each
	corner its own, from the top left round, as an album's pictures have them). `width` is the
	item's in points, so the radius scales with the pixels asked. `mini` is Telegram's tiny blurred
	preview, there before the picture is. .../blur/<path or mini/...>: blurred past telling what it
	is (a spoiler's, under its dust; a video file's still, one picked to go as a spoiler)."""
	radius, width, rest = key.split("/", 2)
	blur = rest.startswith("blur/")
	if blur:
		rest = rest[5:]
	if rest.startswith("mini/"):
		src = QImage.fromData(base64.b64decode(rest[5:]))
	else:
		src = QImage(_still(rest) if blur else rest)
	if blur and not src.isNull():
		src = _blurred(src)
	if requested.isValid() and requested.width() > 0 and requested.height() > 0:
		w, h = requested.width(), requested.height()
	else:
		w, h = max(src.width(), 1), max(src.height(), 1)
	out = QImage(w, h, QImage.Format_ARGB32_Premultiplied)
	out.fill(Qt.transparent)
	if src.isNull():
		return out
	k = w / max(float(width), 1.0)
	rs = [float(x) for x in radius.split(",")]
	r = rs[0]
	p = QPainter(out)
	p.setRenderHints(QPainter.Antialiasing | QPainter.SmoothPixmapTransform)
	if len(rs) == 4:
		p.setClipPath(_corners(w, h, [min(x * k, w / 2, h / 2) for x in rs]))
	elif r:
		clip = QPainterPath()
		if r < 0:
			clip.addEllipse(QRectF(0, 0, w, h))
		else:
			clip.addRoundedRect(QRectF(0, 0, w, h), r * k, r * k)
		p.setClipPath(clip)
	big = src.scaled(w, h, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
	p.drawImage(0, 0, big, (big.width() - w) // 2, (big.height() - h) // 2, w, h)
	p.end()
	return out


class Lottie(QQuickImageProvider):
	"""image://lottie/<ms>/<how>/<path>: a TGS sticker's frame (Lottie JSON, gzipped), drawn by libtlottie -- the
	renderer Telegram's own apps draw them with (dkaraush/tlottie; on the phone as Telegram Desktop's
	dependency). Here, not in an Imager's helper: the drawing is all in the library, called through ctypes,
	which lets the interpreter's lock go for it (1-5 ms a frame at 512 px on the S10's big cores), and it
	draws straight into the picture Qt takes. Through a helper's pipe the same frame cost ~27 ms: three
	stickers on the screen held one core and the UI thread late every frame. The animations stay parsed,
	the last few, as each sticker asks for frame after frame.

	Each frame is drawn once and kept, given again as the sticker loops, as Telegram's apps keep theirs --
	and two messages of the same sticker share them. Drawn every time, three stickers kept the S10's big
	cores so busy it reached 85 C and zthermal took them off until the next boot. Frames go on a
	30-a-second grid (the stickers' clock, Tick.qml), so a loop asks for the same ones again. Kept up to
	BUDGET bytes (~330 frames at 384 px: three and a half stickers' 3 s loops); past it, a new frame is
	drawn and not kept -- not the oldest let go for it: stickers loop, so the oldest is the next one
	asked for, and kept that way none came again. The frames of a sticker not asked for in IDLE seconds
	(gone off the screen, its chat closed) go: as room is wanted, and every few seconds anyway.

	<how>: "-", or "o" (once: played to its end, not looped -- a frame past the end is none, which tells
	the sticker it is over; an emoji alone, as Telegram-iOS plays them) and/or a digit, the skin tone an
	emoji is drawn in (tlottie's fitz modifier, 1-5). <ms> -1: the last frame (an emoji already played,
	Telegram-iOS's .still(.end))."""
	KEEP = 8
	BUDGET = 192 << 20
	FPS = 30
	IDLE = 2.0

	def __init__(self):
		super().__init__(QQuickImageProvider.Image, QQuickImageProvider.ForceAsynchronousImageLoading)
		self.lock, self.open, self.lib = threading.Lock(), {}, None	# (path, fitz) -> (instance, w, h, frames, rate), oldest first
		self.frames, self.kept = {}, 0		# (path, fitz, w, h, frame) -> its picture, oldest first; their bytes
		self.asked = {}				# path -> when a frame of it was last asked for
		self.sweep = QTimer()
		self.sweep.setInterval(5000)
		self.sweep.timeout.connect(self.swept)
		self.sweep.start()
		try:
			lib = ctypes.CDLL("libtlottie.so")
		except OSError as e:		# (none: a sticker keeps its still)
			print("nullgram: no lottie:", e, file=sys.stderr, flush=True)
			return
		lib.tlottie_new_with_options.restype = ctypes.c_void_p
		lib.tlottie_new_with_options.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_void_p,
		                                         ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32]
		lib.tlottie_drop.argtypes = [ctypes.c_void_p]
		for name, kind in (("width", ctypes.c_uint32), ("height", ctypes.c_uint32),
		                   ("frame_rate", ctypes.c_float), ("frame_count", ctypes.c_uint32)):
			fn = getattr(lib, "tlottie_" + name)
			fn.argtypes, fn.restype = [ctypes.c_void_p], kind
		lib.tlottie_render.argtypes = [ctypes.c_void_p, ctypes.c_float, ctypes.c_uint32, ctypes.c_uint32,
		                               ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32]
		lib.tlottie_render.restype = ctypes.c_int32
		self.lib = lib

	def get(self, path, fitz):
		got = self.open.pop((path, fitz), None)
		if got is None:
			import gzip
			with open(path, "rb") as f:
				data = f.read(4 << 20)
			if data[:2] == b"\x1f\x8b":
				data = gzip.decompress(data)
			L = self.lib
			inst = L.tlottie_new_with_options(data, len(data), fitz, None, 0, None, 0, 0)	# (0: RGBA, as tlottie_new)
			if not inst:
				raise ValueError("not a lottie")
			got = (inst, max(L.tlottie_width(inst), 1), max(L.tlottie_height(inst), 1),
			       max(L.tlottie_frame_count(inst), 1), L.tlottie_frame_rate(inst) or 60.0)
			while len(self.open) >= self.KEEP:
				L.tlottie_drop(self.open.pop(next(iter(self.open)))[0])
		self.open[(path, fitz)] = got
		return got

	def swept(self):
		# (the UI thread's: never kept waiting on a frame being drawn -- tried again next time)
		if self.asked and self.lock.acquire(blocking=False):
			try:
				self.forget(time.monotonic())
			finally:
				self.lock.release()

	def forget(self, now):
		"""The frames of the stickers not asked for in IDLE seconds let go."""
		idle = {p for p, t in self.asked.items() if now - t > self.IDLE}
		if not idle:
			return
		for fk in [fk for fk in self.frames if fk[0] in idle]:
			img = self.frames.pop(fk)
			self.kept -= 4 * img.width() * img.height()
		for p in idle:
			del self.asked[p]

	def requestImage(self, key, size, requested):
		"""The frame `ms` milliseconds in, played over and over (the sticker counts the time, the frame is
		found here: it knows neither the rate nor the length), at the size asked, in the animation's shape."""
		if FPS:
			mark("lottie")
		try:
			if self.lib is None:
				raise ValueError("no libtlottie")
			ms, how, path = key.split("/", 2)
			ms, once = int(ms), "o" in how
			fitz = int(how[-1]) if how[-1:].isdigit() else 0
			with self.lock:		# (an instance is drawn by one thread at a time)
				inst, w0, h0, n, rate = self.get(path, fitz)
				if requested.isValid() and requested.width() > 0:
					k = min(requested.width() / w0, (requested.height() if requested.height() > 0 else requested.width()) / h0)
				else:
					k = 256 / max(w0, h0)
				w, h = max(int(w0 * k), 1), max(int(h0 * k), 1)
				step = max(1, round(rate / self.FPS))		# (a 60-a-second sticker: every other frame)
				at = int(ms * rate / 1000)
				if ms < 0:
					at = n - 1
				elif once:
					if at >= n:
						return QImage()		# (played: the sticker stops, and asks for the last frame)
					at = at // step * step
				else:
					at = at % n // step * step		# (in the loop: an odd length shifts no grid)
				fk = (path, fitz, w, h, at)
				now = time.monotonic()
				self.asked[path] = now
				img = self.frames.get(fk)
				if img is None:
					if FPS:
						mark("lottieDrawn")
					img = QImage(w, h, QImage.Format_RGBA8888_Premultiplied)	# (tlottie's own: [R, G, B, A], premultiplied)
					if img.bytesPerLine() != 4 * w:
						raise ValueError("padded rows")
					bits = img.bits()		# (PySide: a writable memoryview over the picture's own pixels)
					self.lib.tlottie_render(inst, float(at), w, h, ctypes.addressof(ctypes.c_char.from_buffer(bits)), w * h, 1)
					del bits
					if self.kept + 4 * w * h > self.BUDGET:
						self.forget(now)
					if self.kept + 4 * w * h <= self.BUDGET:
						self.frames[fk] = img		# (Qt only reads it: the same pixels shared, not copied)
						self.kept += 4 * w * h
			return img
		except (OSError, ValueError) as e:
			print("nullgram: lottie:", key[:80], e, file=sys.stderr, flush=True)
			return QImage()		# (none: the Image's Error, and the sticker stops asking)


class Bubble(QQuickImageProvider):
	"""image://bubble/<in|out>/<top: b|s>/<bottom: t|s>/<rrggbb>/<scale>[/<R>/<small>]: a message bubble to
	stretch (BorderImage: top and the far side R, the bottom and the tail's side B = max(R, 10) — the
	tail needs 10 — that side B + TAIL), as Telegram-iOS draws them from
	stretchable images (ChatMessageBubbleImages.swift): big corners, small ones on the side where the
	sender's messages run together, and the tail under the last of a run. R and small from Prefs
	(Xabar burchaklari: bubbleR, bubbleS), 17 and 6 when not given."""
	R, SMALL, TAIL = 17, 6, 6

	def __init__(self):
		super().__init__(QQuickImageProvider.Image)

	def requestImage(self, key, size, requested):
		side, top, bottom, colour, scale, *rr = key.split("/")
		s = float(scale)
		R, r, T = self.R, self.SMALL, self.TAIL
		if len(rr) == 2:
			R = max(2, min(24, int(rr[0])))
			r = max(2, min(R, int(rr[1])))
		B = max(R, 10)		# (the tail's curve: 10 across, 9 up)
		w, h = T + B + R + 2, R + B + 2
		img = QImage(int(w * s), int(h * s), QImage.Format_ARGB32_Premultiplied)
		img.fill(Qt.transparent)
		p = QPainter(img)
		p.setRenderHint(QPainter.Antialiasing)
		p.scale(s, s)
		if side == "out":		# drawn as an incoming one, mirrored: the tail on the right
			p.translate(w, 0)
			p.scale(-1, 1)
		rt = R if top == "b" else r		# the sender's side, top
		x0, x1 = T, w
		path = QPainterPath()
		path.moveTo(x0 + rt, 0)
		path.lineTo(x1 - R, 0)
		path.quadTo(x1, 0, x1, R)
		path.lineTo(x1, h - R)
		path.quadTo(x1, h, x1 - R, h)
		if bottom == "t":		# the tail: out of the bottom corner, a point to the side
			path.lineTo(x0 + 10, h)
			path.cubicTo(x0 + 6.5, h, x0 + 3.5, h - 1.2, x0 + 2, h - 2.4)
			path.cubicTo(x0 - 0.5, h - 0.2, x0 - 3.5, h + 0.1, 0, h - 0.3)
			path.cubicTo(x0 - 1.2, h - 2, x0, h - 4.5, x0, h - 9)
		else:
			path.lineTo(x0 + r, h)
			path.quadTo(x0, h, x0, h - r)
		path.lineTo(x0, rt)
		path.quadTo(x0, 0, x0 + rt, 0)
		p.fillPath(path, QColor("#" + colour))
		p.end()
		# left at device pixel ratio 1: BorderImage on the GPU takes its borders in the picture's
		# pixels and draws them that many points big whatever the ratio, so QML draws it `scale`
		# times bigger and scales the item down (ChatPage.qml)
		return img


class Svg(QQuickImageProvider):
	"""image://svg/<the SVG, percent-encoded>: our line icons (Icons.js) drawn at the size asked, the
	device's pixels. (A data: URL's SVG is read at its own 24 × 24 whatever Image's sourceSize says,
	then stretched: four times on the phone, blurred.)"""

	def __init__(self):
		super().__init__(QQuickImageProvider.Image)

	def requestImage(self, key, size, requested):
		r = QSvgRenderer(QByteArray(unquote(key).encode()))
		w = requested.width() if requested.width() > 0 else 96
		h = requested.height() if requested.height() > 0 else w
		img = QImage(w, h, QImage.Format_ARGB32_Premultiplied)
		img.fill(Qt.transparent)
		if r.isValid():
			p = QPainter(img)
			p.setRenderHint(QPainter.Antialiasing)
			r.render(p)
			p.end()
		return img


class Dust(QQuickImageProvider):
	"""image://dust/<rrggbb>/<seed>/<pixels>: a square of a spoiler's dust to tile (Dust.qml): dots of
	the words' colour, under a point across, some faint; those over an edge drawn again on the other
	side, so the tiles meet unseen. About one dot to 12 square points, as Telegram's looks."""

	def __init__(self):
		super().__init__(QQuickImageProvider.Image)

	def requestImage(self, key, size, requested):
		colour, seed, pixels = key.split("/")
		n = max(int(pixels), 8)
		k = n / 64.0		# pixels a point
		rnd = random.Random(colour + seed)
		img = QImage(n, n, QImage.Format_ARGB32_Premultiplied)
		img.fill(Qt.transparent)
		p = QPainter(img)
		p.setRenderHint(QPainter.Antialiasing)
		p.setPen(Qt.NoPen)
		c = QColor("#" + colour)
		for _ in range(64 * 64 // 12):
			x, y = rnd.random() * n, rnd.random() * n
			r = rnd.uniform(0.3, 0.6) * k
			c.setAlphaF(rnd.uniform(0.3, 1.0))
			p.setBrush(c)
			for dx in ((-n,) if x > n - r else (n,) if x < r else ()) + (0,):
				for dy in ((-n,) if y > n - r else (n,) if y < r else ()) + (0,):
					p.drawEllipse(QPointF(x + dx, y + dy), r, r)
		p.end()
		return img


class Wall(QQuickImageProvider):
	"""image://wall/<rrggbb,rrggbb,rrggbb,rrggbb>: Telegram's freeform wallpaper, its four colours
	blended by nearness (weight max(0, 0.9 - d)^4), small: drawn large it stays smooth."""
	AT = ((0.80, 0.10), (0.35, 0.25), (0.20, 0.90), (0.65, 0.75))

	def __init__(self):
		super().__init__(QQuickImageProvider.Image)

	def requestImage(self, colours, size, requested):
		rgb = [tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in colours.split(",")]
		w, h = 30, 63
		img = QImage(w, h, QImage.Format_RGB32)
		for y in range(h):
			for x in range(w):
				u, v = x / (w - 1), y / (h - 1)
				ws = [max(0.0, 0.9 - ((u - px) ** 2 + (v - py) ** 2) ** 0.5) ** 4 for px, py in self.AT]
				total = sum(ws) or 1.0
				r, g, b = (int(sum(k * c[i] for k, c in zip(ws, rgb)) / total) for i in range(3))
				img.setPixel(x, y, 0xff000000 | (r << 16) | (g << 8) | b)
		return img


class Wallpaper(QQuickImageProvider):
	"""image://wallpaper/<fill>;<intensity>;<kind>;<path>: a chat's background as Telegram-iOS's
	WallpaperBackgroundNode draws it, at the size asked (the device's pixels; Wallpaper.qml asks its own).
	<fill>: "rrggbb" (one colour), "rrggbb,rrggbb@angle" (top to bottom, turned by the angle) or three or
	four "rrggbb" (the freeform gradient, as Wall). <kind> "p": <path> is a pattern (TDLib's .tgv, a gzipped
	SVG) laid over the fill, scaled to fill the screen: black at <intensity> % in soft light (iOS's
	patternImageLayer, compositionOpacity = intensity, softlightMode .always; plain over a black fill);
	a negative intensity is the night's inverted pattern: black, the fill showing only through the
	pattern's lines at |intensity| %. "photo" / "blur": <path> is a picture, filling the screen (blurred).
	"" with no path: the fill alone. "r<k>|" before it: its corners rounded by k of its width (the grids'
	tiles). Asked for again and again as pages come and go: the last ones kept (BUDGET)."""
	AT = Wall.AT
	BUDGET = 64 << 20		# the pictures kept, in bytes: a whole screen on the phone is 17.5 MB, a grid's tile under 1

	def __init__(self):
		super().__init__(QQuickImageProvider.Image)
		self.kept = []			# [(key, image)], the newest last
		self.lock = threading.Lock()

	@staticmethod
	def rgb(c):
		c = c.strip().lstrip("#")[:6].ljust(6, "0")
		return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))

	def fill(self, spec, w, h):
		"""The fill alone, w × h."""
		angle = 0
		if "@" in spec:
			spec, a = spec.split("@", 1)
			angle = int(a or 0)
		cs = [self.rgb(c) for c in spec.split(",") if c.strip()] or [(0xdb, 0xdd, 0xbb)]
		img = QImage(w, h, QImage.Format_RGB32)
		if len(cs) == 1:
			img.fill(QColor(*cs[0]))
		elif len(cs) == 2:			# (iOS: rotated about the middle; 0 is top to bottom)
			rad = math.radians(angle)
			dx, dy = math.sin(rad), -math.cos(rad)
			half = (abs(dx) * w + abs(dy) * h) / 2
			g = QLinearGradient(w / 2 - dx * half, h / 2 + dy * half, w / 2 + dx * half, h / 2 - dy * half)
			g.setColorAt(0, QColor(*cs[0]))
			g.setColorAt(1, QColor(*cs[1]))
			p = QPainter(img)
			p.fillRect(0, 0, w, h, g)
			p.end()
		else:
			sw, sh = 30, 63
			small = QImage(sw, sh, QImage.Format_RGB32)
			at = self.AT[:len(cs)]
			for y in range(sh):
				for x in range(sw):
					u, v = x / (sw - 1), y / (sh - 1)
					ws = [max(0.0, 0.9 - ((u - px) ** 2 + (v - py) ** 2) ** 0.5) ** 4 for px, py in at]
					total = sum(ws) or 1.0
					r, g, b = (int(sum(k * c[i] for k, c in zip(ws, cs)) / total) for i in range(3))
					small.setPixel(x, y, 0xff000000 | (r << 16) | (g << 8) | b)
			img = small.scaled(w, h, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
		return img

	@staticmethod
	def pattern(path, w, h):
		"""The pattern's lines in black on nothing, w × h, its picture scaled to fill (cut at the sides)."""
		try:
			with open(path, "rb") as f:
				data = f.read()
			if data[:2] == b"\x1f\x8b":
				data = gzip.decompress(data)
		except (OSError, EOFError, ValueError):
			return None
		r = QSvgRenderer(QByteArray(data))
		if not r.isValid():
			return None
		vb = r.viewBoxF()
		vw, vh = (vb.width(), vb.height()) if vb.width() > 0 else (r.defaultSize().width(), r.defaultSize().height())
		if vw <= 0 or vh <= 0:
			return None
		k = max(w / vw, h / vh)
		img = QImage(w, h, QImage.Format_ARGB32_Premultiplied)
		img.fill(Qt.transparent)
		p = QPainter(img)
		p.setRenderHint(QPainter.Antialiasing)
		r.render(p, QRectF((w - vw * k) / 2, (h - vh * k) / 2, vw * k, vh * k))
		p.setCompositionMode(QPainter.CompositionMode_SourceIn)
		p.fillRect(0, 0, w, h, Qt.black)
		p.end()
		return img

	def draw(self, key, w, h):
		fill, intensity, kind, path = (key.split(";", 3) + ["", "", ""])[:4]
		try:
			i = int(intensity or 0)
		except ValueError:
			i = 0
		base = self.fill(fill, w, h)
		if kind == "p" and path:
			lines = self.pattern(path, w, h)
			if lines is None:
				return base
			out = QImage(w, h, QImage.Format_RGB32)
			p = QPainter(out)
			if i < 0:		# the night's: black, the fill through the lines
				out.fill(Qt.black)
				through = QImage(lines)
				q = QPainter(through)
				q.setCompositionMode(QPainter.CompositionMode_SourceIn)
				q.drawImage(0, 0, base)
				q.end()
				p.setOpacity(min(1.0, -i / 100))
				p.drawImage(0, 0, through)
			else:
				p.drawImage(0, 0, base)
				cs = [self.rgb(c) for c in fill.split("@")[0].split(",")]
				if max(sum(c[k] for c in cs) / len(cs) for k in range(3)) > 0.01 * 255:	# (iOS: unless the fill is black)
					p.setCompositionMode(QPainter.CompositionMode_SoftLight)
				p.setOpacity(min(1.0, i / 100))
				p.drawImage(0, 0, lines)
			p.end()
			return out
		if kind in ("photo", "blur") and path:
			pic = QImage(path)
			if pic.isNull():
				return base
			if kind == "blur":		# (a cheap blur: down to a sliver and back up, smoothly)
				pic = pic.scaled(max(1, pic.width() // 24), max(1, pic.height() // 24), Qt.KeepAspectRatio, Qt.SmoothTransformation)
			pic = pic.scaled(w, h, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
			out = QImage(w, h, QImage.Format_RGB32)
			p = QPainter(out)
			p.drawImage((w - pic.width()) // 2, (h - pic.height()) // 2, pic)
			p.end()
			return out
		if i < 0:			# (a fill with an inverted intensity and no pattern yet: dimmed, as iOS before it comes)
			p = QPainter(base)
			p.fillRect(0, 0, w, h, QColor(0, 0, 0, int(255 * (1 - min(1.0, -i / 100)))))
			p.end()
		return base

	def requestImage(self, key, size, requested):
		key = full = unquote(key)
		w = requested.width() if requested.width() > 0 else 360
		h = requested.height() if requested.height() > 0 else 760
		with self.lock:
			for k, img in self.kept:
				if k == (full, w, h):
					return img
		k = 0.0
		if key.startswith("r") and "|" in key:
			r, key = key[1:].split("|", 1)
			try:
				k = float(r)
			except ValueError:
				k = 0.0
		img = self.draw(key, w, h)
		if k > 0:
			out = QImage(w, h, QImage.Format_ARGB32_Premultiplied)
			out.fill(Qt.transparent)
			p = QPainter(out)
			p.setRenderHint(QPainter.Antialiasing)
			path = QPainterPath()
			path.addRoundedRect(QRectF(0, 0, w, h), k * w, k * w)
			p.setClipPath(path)
			p.drawImage(0, 0, img)
			p.end()
			img = out
		with self.lock:
			kept = [x for x in self.kept if x[0] != (full, w, h)] + [((full, w, h), img)]
			while len(kept) > 1 and sum(x[1].sizeInBytes() for x in kept) > self.BUDGET:
				kept.pop(0)
			self.kept = kept
		return img


# ARM's little cores (Cortex-A53, A35, A55, A510, A520): /proc/cpuinfo's "CPU part"
LITTLE = {"0xd03", "0xd04", "0xd05", "0xd46", "0xd80"}


def big_cores():
	"""The cores that are not little ones, when the phone has both (else None). The S10's kernel has no
	cpufreq and gives every core the same capacity (1024), so the scheduler put the UI thread on one of
	its four Cortex-A55s as readily as on an A75 or M4 (the desk's rows made end to end: 4.5 s on an A55,
	3.2 on an A75, 1.3 on an M4): one flick fast, the next slow. (Timed instead, on cores just woken,
	the A55s came out as fast as the M4s now and then.)"""
	part, parts = None, {}
	try:
		with open("/proc/cpuinfo") as f:
			for line in f:
				k, _, v = line.partition(":")
				k, v = k.strip(), v.strip()
				if k == "processor":
					part = int(v)
				elif k == "CPU part" and part is not None:
					parts[part] = v.lower()
	except (OSError, ValueError):
		return None
	big = {c for c, v in parts.items() if v not in LITTLE}
	return big if 0 < len(big) < len(parts) else None


# Where Qt looks for a letter Adwaita Sans (Theme.font) has not: fontconfig's own order, but with what names
# and words here need from far down it brought up. Qt walks that list a font at a time, and again for every
# size and weight a text comes in (each its own engine), opening each font on the way: a flag (🇺🇿, the
# emoji font 180th) cost 59 ms each time, a name in math letters (𝒩𝒶𝓇𝑔𝒾𝓏, 155th) 42 ms, circled letters
# (ⓐ) 24 ms -- the name over a bubble, its avatar's letters, a service line, each a size of its own: the
# 130 ms Texts that held a first flick (later ones found the engines made). Now 5-12 ms. The fonts before
# them are fontconfig's first ones, in its order: of 14482 letters tried (U+0020-2FFF, math, emoji) 7 come
# from another font than before. Letters no font has (fullwidth Ａ) still walk the whole list (~54 ms).
FALLBACK = ["Noto Sans", "Noto Sans Coptic", "DejaVu Sans", "Noto Sans Symbols 2", "Noto Sans Symbols", "Adwaita Mono",
            "Noto Sans Math", "Noto Color Emoji"]
# Chinese, Japanese, Korean and the fullwidth letters (Ａ) of names: no font on the phone had them -- boxes, and
# each a walk through all of fontconfig's ~500 fonts (54 ms) -- until tools/fonts.sh put Noto Sans CJK in
# ~/.local/share/fonts. Last: before it, the emoji font keeps the symbols both have in colour.
CJK = "Noto Sans CJK SC"


def system_lang() -> str:
	"""The language omonullOS speaks: "language = uz | en" in ~/.config/ztmetro/config (ztlang.c reads
	it the same way); Uzbek when it is not there."""
	try:
		with open(os.path.expanduser("~/.config/ztmetro/config")) as f:
			for line in f:
				k, _, v = line.partition("=")
				if k.strip() == "language":
					return "en" if v.strip() == "en" else "uz"
	except OSError:
		pass
	return "uz"


def emoji_dir() -> str:
	"""The Apple emoji set's folder as a file URL ending in "/" (EMOJI_DIRS' first with the map), or ""."""
	for d in EMOJI_DIRS:
		if os.path.isfile(os.path.join(d, "emoji-map.json")):
			return QUrl.fromLocalFile(os.path.realpath(d)).toString() + "/"
	return ""


def omonullos() -> bool:
	"""On omonullOS (its Settings choose the emoji), not another ztOS or Linux phone."""
	try:
		with open("/etc/os-release") as f:
			return "omonullos" in f.read().lower()
	except OSError:
		return False


def emoji_alive(pid) -> bool:
	"""The emoji download (emoji_get.py) of this pid still runs."""
	try:
		with open(f"/proc/{int(pid)}/cmdline", "rb") as f:
			return b"emoji_get" in f.read()
	except (OSError, ValueError, TypeError):
		return False


def apple_emoji() -> bool:
	"""omonullOS Settings > theme > Emoji is Apple (ztsettings writes this file; Google removes it).
	Read as Nullgram starts, as the rest of the session reads fontconfig. NULLGRAM_EMOJI=apple|google
	stands in for it (to try the other without touching the owner's setting; tools/desk has the same).
	Elsewhere (no such setting): Apple when the user has downloaded the set."""
	if os.environ.get("NULLGRAM_EMOJI") in ("apple", "google"):
		return os.environ["NULLGRAM_EMOJI"] == "apple"
	if not omonullos():
		return emoji_dir() != ""
	return os.path.exists(os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
	                                   "fontconfig/conf.d/60-omonullos-emoji.conf"))


def fonts():
	"""Where Qt looks for a letter Adwaita Sans has not (FALLBACK, then CJK when it is there)."""
	if os.environ.get("NULLGRAM_FALLBACK") == "off":		# (off: as fontconfig has it, to compare)
		return
	order = list(FALLBACK)
	# omonullOS Settings > theme > Emoji: Apple writes this file (fontconfig puts Apple first everywhere
	# else); here the list is our own, so Apple goes before Noto when it is chosen and installed.
	if apple_emoji() and QFontDatabase.hasFamily("Apple Color Emoji"):
		order.insert(order.index("Noto Color Emoji"), "Apple Color Emoji")
	QFont.insertSubstitutions("Adwaita Sans", order + ([CJK] if QFontDatabase.hasFamily(CJK) else []))


def main():
	# NULLGRAM_CPUS: off (as the kernel schedules it), or the cores to hold it to (e.g. 6,7); else the big
	# ones. Set here, first: every thread made from here on (render, TDLib's, pictures') starts there too.
	want = os.environ.get("NULLGRAM_CPUS", "")
	cpus = None if want == "off" else {int(c) for c in want.split(",")} if want else big_cores()
	if cpus:
		try:
			os.sched_setaffinity(0, cpus)
		except OSError:
			cpus = None
	print("nullgram: cores", sorted(cpus) if cpus else "all", flush=True)
	# Animations by the clock, not a vsync's 16.7 ms a frame: while a video plays the frames come
	# every 33 ms, and Qt's default driver then played every animation at half speed (the
	# gallery's black took 1.5 s to go instead of 0.25 s)
	os.environ.setdefault("QSG_USE_SIMPLE_ANIMATION_DRIVER", "1")
	# NULLGRAM_PROFILE=<port>: QML's profiler may attach there (qmlprofiler --attach localhost -p <port>)
	if os.environ.get("NULLGRAM_PROFILE"):
		from PySide6.QtQml import QQmlDebuggingEnabler
		QQmlDebuggingEnabler.enableDebugging(True)
		sys.argv.append("-qmljsdebugger=port:%s,block" % os.environ["NULLGRAM_PROFILE"])
	app = QGuiApplication(sys.argv)
	fonts()
	app.setOrganizationName("OmonullOS")
	app.setApplicationName("Nullgram")
	app.setDesktopFileName("ztos.uz.omonullos.nullgram")	# the shell knows its window by this (install.sh)
	td = Td()
	view = QQuickView()
	view.setColor("black")
	view.rootContext().setContextProperty("td", td)
	osk = Osk()
	view.rootContext().setContextProperty("osk", osk)
	safe = Safe()
	view.rootContext().setContextProperty("safe", safe)
	ink = Ink()
	view.rootContext().setContextProperty("ink", ink)
	meter = Meter()
	view.rootContext().setContextProperty("meter", meter)
	battery = Battery()
	view.rootContext().setContextProperty("battery", battery)
	net = Net()
	view.rootContext().setContextProperty("net", net)
	imagers = Imager()
	view.engine().addImageProvider("round", Asked(imagers, "round"))
	view.engine().addImageProvider("wall", Wall())
	view.engine().addImageProvider("wallpaper", Wallpaper())		# chats' backgrounds, patterns and all
	view.engine().addImageProvider("bubble", Bubble())
	view.engine().addImageProvider("pic", Asked(imagers, "pic"))
	view.engine().addImageProvider("thumb", Asked(imagers, "thumb"))
	view.engine().addImageProvider("dust", Dust())
	view.engine().addImageProvider("svg", Svg())		# our line icons, sharp
	view.engine().addImageProvider("lottie", Lottie())		# TGS stickers' frames
	view.setResizeMode(QQuickView.SizeRootObjectToView)
	view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "qml", "Main.qml")))
	if view.status() == QQuickView.Error:
		raise SystemExit("\n".join(e.toString() for e in view.errors()))
	td.start()
	view.show()		# a window: ztMETRO puts a fullscreen one on its side (landscape, since 11-15)

	# NULLGRAM_FPS=1: each frame the UI thread was late for (over 25 ms) to the log; =<ms>: each
	# frame over that (=0: every frame)
	if os.environ.get("NULLGRAM_FPS"):
		import time
		last = [time.monotonic()]
		over = float(os.environ["NULLGRAM_FPS"])
		over = 0.025 if over == 1 else over / 1000

		def stepped():
			now = time.monotonic()
			if now - last[0] > over:
				did = " ".join("%s=%d" % kv for kv in sorted(MARKS.items()))
				print("nullgram: frame %.0f ms at %.3f %s" % ((now - last[0]) * 1000, now, did), flush=True)
			MARKS.clear()
			last[0] = now
		view.afterAnimating.connect(stepped)

	# Closed by the shell (a swipe), it only hides: TDLib stays on, so new messages still notify
	# and count on the tile. A tap on the app again (the starter sends SIGUSR1) shows it; SIGTERM
	# (thrown off the switcher) ends it. Signals reach Qt's loop through a socket (set_wakeup_fd).
	app.setQuitOnLastWindowClosed(False)
	rd, wr = socket.socketpair()
	rd.setblocking(False)
	wr.setblocking(False)
	signal.set_wakeup_fd(wr.fileno())
	# (the handlers do nothing: the C side writes each signal's number to the socket, and that is
	# what is read here; Python's own handler may not have run yet when Qt calls back)
	signal.signal(signal.SIGUSR1, lambda n, f: None)
	signal.signal(signal.SIGTERM, lambda n, f: None)

	def woken():
		try:
			got = rd.recv(64)
		except OSError:
			return
		if signal.SIGTERM in got:
			app.quit()
		elif signal.SIGUSR1 in got:
			print("nullgram: shown again", flush=True)
			view.show()
			view.raise_()
			view.requestActivate()
	notifier = QSocketNotifier(rd.fileno(), QSocketNotifier.Read)
	notifier.activated.connect(woken)
	code = app.exec()
	tile_clear()
	# Out at once, not after seconds of Qt and Python taking themselves apart: a tap meanwhile
	# would find it still there and only signal it.
	td.close(1.5)
	sys.stdout.flush()
	sys.stderr.flush()
	os._exit(code)


if __name__ == "__main__":
	imager() if "--imager" in sys.argv else main()
