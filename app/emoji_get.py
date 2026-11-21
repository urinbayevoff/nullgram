#!/usr/bin/env python3
"""Nullgram's Apple emoji set: downloaded by the user, at their own wish (Apple's pictures are not in the
package). The 160 px pictures and the list of them come from iamcal/emoji-data (a pinned tag, through the
jsDelivr CDN; GitHub itself if that fails) into ~/.cache/nullgram-emoji/, as apple/<file>.png plus
emoji-map.json (the code points, "1f600" or "1f468-200d-1f469", -> the file), which Nullgram's Emo.qml reads.

It runs on its own (Nullgram starts it in its own session, so closing the app does not stop it) and writes
how far it is to a status file the app reads: $XDG_RUNTIME_DIR/nullgram-emoji.json. Stopped, it goes on
where it was the next time (the pictures got so far wait in ~/.cache/nullgram-emoji.part/).

  python3 emoji_get.py            download (or go on), printing the progress when on a terminal
  python3 emoji_get.py --stop     stop the one running
  python3 emoji_get.py --remove   stop it and delete the set (Nullgram goes back to the system's emoji)
"""
import concurrent.futures
import json
import os
import shutil
import signal
import sys
import threading
import time
import urllib.request

TAG = "v16.0.0"
SOURCES = [f"https://cdn.jsdelivr.net/gh/iamcal/emoji-data@{TAG}/",
           f"https://raw.githubusercontent.com/iamcal/emoji-data/{TAG}/"]
SIZE = "img-apple-160/"
DEST = os.path.expanduser("~/.cache/nullgram-emoji")
PART = DEST + ".part"
STATUS = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "nullgram-emoji.json")
VER = f"iamcal-{TAG}-160"
WORKERS = 12
NEED = 140 << 20            # free room asked for first (~95 MB of pictures, and some to spare)
AGENT = "nullgram-emoji/1.0"
stop = threading.Event()


def status() -> dict:
	try:
		with open(STATUS) as f:
			return json.load(f)
	except (OSError, ValueError):
		return {}


def alive(pid) -> bool:
	try:
		os.kill(int(pid), 0)
	except (OSError, ValueError, TypeError):
		return False
	try:		# (a pid used again by something else is not us)
		with open(f"/proc/{int(pid)}/cmdline", "rb") as f:
			return b"emoji_get" in f.read()
	except OSError:
		return False


def write(**st):
	st["pid"] = os.getpid()
	st["time"] = time.time()
	tmp = STATUS + ".new"
	with open(tmp, "w") as f:
		json.dump(st, f)
	os.replace(tmp, STATUS)


def fetch(path: str, tries: int = 3) -> bytes:
	err = None
	for k in range(tries):
		for base in SOURCES:
			if stop.is_set():
				raise InterruptedError
			try:
				req = urllib.request.Request(base + path, headers={"User-Agent": AGENT})
				with urllib.request.urlopen(req, timeout=15) as r:
					return r.read()
			except Exception as e:		# noqa: BLE001 (any network trouble: the next source, then again)
				err = e
		time.sleep(1 + 2 * k)
	raise OSError(f"{path}: {err}")


def keys(e: dict) -> set:
	"""The code point runs this picture stands for: the full one, the unqualified one, and without U+FE0F."""
	out = set()
	for u in (e.get("unified"), e.get("non_qualified")):
		if u:
			u = u.lower()
			out.add(u)
			out.add("-".join(c for c in u.split("-") if c != "fe0f"))
	out.discard("")
	return out


def plan(listing: list) -> tuple:
	"""The files to get, and the map: every Apple picture of the list, skin tones too."""
	files, emap = [], {}
	for e in listing:
		for x in [e] + list((e.get("skin_variations") or {}).values()):
			if not x.get("has_img_apple") or not x.get("image"):
				continue
			if x["image"] not in files:
				files.append(x["image"])
			for k in keys(x):
				emap.setdefault(k, x["image"])
	return files, emap


def download():
	if alive(status().get("pid")) and status().get("pid") != os.getpid():
		print("nullgram-emoji: already downloading", file=sys.stderr)
		return 0
	signal.signal(signal.SIGTERM, lambda *_: stop.set())
	signal.signal(signal.SIGINT, lambda *_: stop.set())
	try:
		os.nice(10)
	except OSError:
		pass
	tty = sys.stdout.isatty()
	os.makedirs(os.path.join(PART, "apple"), exist_ok=True)
	write(state="start", done=0, total=0, bytes=0)
	if shutil.disk_usage(PART).free < NEED:
		write(state="error", error="space", done=0, total=0, bytes=0)
		print("nullgram-emoji: not enough free space (~140 MB)", file=sys.stderr)
		return 1
	try:
		listing = json.loads(fetch("emoji.json"))
	except InterruptedError:
		write(state="stopped", done=0, total=0, bytes=0)
		return 0
	except Exception as e:		# noqa: BLE001
		write(state="error", error="net", detail=str(e)[:200], done=0, total=0, bytes=0)
		print(f"nullgram-emoji: {e}", file=sys.stderr)
		return 1
	files, emap = plan(listing)
	total = len(files)
	have, size0 = set(), 0			# got on an earlier run (a stopped one)
	for f in files:
		try:
			s = os.path.getsize(os.path.join(PART, "apple", f))
		except OSError:
			continue
		if s > 0:
			have.add(f)
			size0 += s
	got = {"n": len(have), "bytes": size0}
	todo = [f for f in files if f not in have]
	lock = threading.Lock()
	start, start_n, start_b = time.time(), got["n"], got["bytes"]
	failed = []

	def one(f):
		data = fetch(SIZE + f)
		if not data.startswith(b"\x89PNG"):
			raise OSError(f"{f}: not a PNG")
		p = os.path.join(PART, "apple", f)
		with open(p + ".tmp", "wb") as o:
			o.write(data)
		os.replace(p + ".tmp", p)
		with lock:
			got["n"] += 1
			got["bytes"] += len(data)

	def report():
		el = max(time.time() - start, 0.1)
		n, b = got["n"], got["bytes"]
		rate = (n - start_n) / el						# files a second, this run
		left = (total - n) / rate if rate > 0 else -1
		est = b / n * total if n >= 50 else 0			# all the bytes, guessed from the mean so far
		write(state="download", done=n, total=total, bytes=b, est=int(est),
		      speed=int((b - start_b) / el), left=int(left))
		if tty:
			print(f"\r{n}/{total}  {b / 1e6:.1f} MB  ~{int(left) if left >= 0 else '?'} s left   ", end="", flush=True)

	pool = concurrent.futures.ThreadPoolExecutor(WORKERS)
	futs = [pool.submit(one, f) for f in todo]
	last = 0
	for fut in concurrent.futures.as_completed(futs):
		try:
			fut.result()
		except (InterruptedError, concurrent.futures.CancelledError):
			pass
		except Exception as e:		# noqa: BLE001
			failed.append(str(e))
			if len(failed) > 20:		# the network is gone: stop, go on later
				stop.set()
		if time.time() - last > 0.4:
			last = time.time()
			report()
		if stop.is_set():
			break
	# stopped: the ones not begun are dropped, the few under way end at their next try (stop is set)
	pool.shutdown(wait=True, cancel_futures=True)
	report()
	if tty:
		print()
	if stop.is_set() and got["n"] < total:
		st = "error" if failed else "stopped"
		write(state=st, error="net" if failed else "", detail=(failed or [""])[-1][:200],
		      done=got["n"], total=total, bytes=got["bytes"])
		return 1 if failed else 0
	if failed:
		write(state="error", error="net", detail=failed[-1][:200], done=got["n"], total=total, bytes=got["bytes"])
		return 1
	# all here: the map, then the set put in place at once (an older set, if any, goes)
	with open(os.path.join(PART, "emoji-map.json"), "w") as f:
		json.dump(emap, f, separators=(",", ":"))
	with open(os.path.join(PART, ".ver"), "w") as f:
		f.write(VER + "\n")
	old = DEST + ".old"
	shutil.rmtree(old, ignore_errors=True)
	if os.path.lexists(DEST):
		os.replace(DEST, old)
	os.replace(PART, DEST)
	shutil.rmtree(old, ignore_errors=True)
	write(state="done", done=total, total=total, bytes=got["bytes"])
	print(f"nullgram-emoji: {total} pictures in {DEST}", file=sys.stderr)
	return 0


def stop_running():
	pid = status().get("pid")
	if alive(pid):
		os.kill(int(pid), signal.SIGTERM)
		for _ in range(200):
			if not alive(pid):
				break
			time.sleep(0.1)


def remove():
	stop_running()
	for d in (DEST, PART, DEST + ".old"):
		if os.path.islink(d):
			os.remove(d)
		else:
			shutil.rmtree(d, ignore_errors=True)
	write(state="none", done=0, total=0, bytes=0)
	return 0


if __name__ == "__main__":
	arg = sys.argv[1] if len(sys.argv) > 1 else ""
	if arg == "--stop":
		stop_running()
		sys.exit(0)
	if arg == "--remove":
		sys.exit(remove())
	if arg in ("-h", "--help"):
		print(__doc__)
		sys.exit(0)
	sys.exit(download())
