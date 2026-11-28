"""Full-resolution photo rotation (90 deg steps) and cropping for SendMediaSheet.

Uses PySide6 QImageReader/QImage/QTransform (Pillow is not installed on the phone).
Original image resolution is preserved (no QML grabToImage downscaling).
"""
import hashlib
import os
import tempfile
import time

from PySide6.QtCore import Qt
from PySide6.QtGui import QImageReader, QTransform

_EDIT_DIR = os.path.join(tempfile.gettempdir(), "nullgram-edit")
_SEQ = 0


def edit_photo(path: str, rot: int = 0, cx: float = 0.0, cy: float = 0.0, cw: float = 1.0, ch: float = 1.0) -> dict:
	"""Rotate (clockwise 90-degree steps) and crop (normalized 0..1 rect after rotation) a photo.

	Returns {"path": str, "w": int, "h": int}. If no transform is needed or reading fails,
	returns the original path unchanged.
	"""
	global _SEQ
	if not path or not os.path.isfile(path):
		return {"path": path or "", "w": 0, "h": 0}
	rot = int(rot) % 360
	if rot not in (0, 90, 180, 270):
		rot = (round(rot / 90.0) * 90) % 360
	cx = max(0.0, min(1.0, float(cx)))
	cy = max(0.0, min(1.0, float(cy)))
	cw = max(0.0, min(1.0 - cx, float(cw)))
	ch = max(0.0, min(1.0 - cy, float(ch)))
	is_full_crop = cx <= 0.001 and cy <= 0.001 and cw >= 0.999 and ch >= 0.999
	if rot == 0 and is_full_crop:
		return {"path": path, "w": 0, "h": 0}

	reader = QImageReader(path)
	reader.setAutoTransform(True)
	img = reader.read()
	if img.isNull():
		return {"path": path, "w": 0, "h": 0}

	if rot:
		img = img.transformed(QTransform().rotate(rot), Qt.SmoothTransformation)

	if not is_full_crop and cw > 0.01 and ch > 0.01:
		iw, ih = img.width(), img.height()
		x = max(0, min(iw - 1, round(cx * iw)))
		y = max(0, min(ih - 1, round(cy * ih)))
		w = max(1, min(iw - x, round(cw * iw)))
		h = max(1, min(ih - y, round(ch * ih)))
		if (x, y, w, h) != (0, 0, iw, ih):
			img = img.copy(x, y, w, h)

	os.makedirs(_EDIT_DIR, exist_ok=True)
	_SEQ += 1
	ext = os.path.splitext(path)[1].lower()
	keep_png = ext in (".png", ".webp") and img.hasAlphaChannel()
	out_ext = ".png" if keep_png else ".jpg"
	tag = hashlib.sha1(f"{path}:{rot}:{cx:.4f}:{cy:.4f}:{cw:.4f}:{ch:.4f}:{time.time_ns()}:{_SEQ}".encode()).hexdigest()[:16]
	out_path = os.path.join(_EDIT_DIR, f"ed-{tag}{out_ext}")
	ok = img.save(out_path, "PNG" if keep_png else "JPEG", -1 if keep_png else 95)
	if not ok:
		return {"path": path, "w": 0, "h": 0}
	return {"path": out_path, "w": img.width(), "h": img.height()}
