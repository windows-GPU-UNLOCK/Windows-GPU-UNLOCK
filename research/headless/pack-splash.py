# SPDX-License-Identifier: GPL-2.0-only
"""Pack independent 1080p RGB565 frames for the local EFI player."""
from pathlib import Path
import argparse
import hashlib
import struct

import cv2
import lz4.block
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("video", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
movie, target = args.video, args.output
width, height, count = 1920, 1080, 112
capture = cv2.VideoCapture(str(movie))
if not capture.isOpened() or round(capture.get(cv2.CAP_PROP_FPS)) != 30:
    raise ValueError("Expected the approved 30 FPS video")
offsets = [0]
with target.open("wb") as file:
    header_size = 20 + 4 * (count + 1)
    file.seek(header_size)
    for _ in range(count):
        ok, frame = capture.read()
        if not ok or frame.shape != (height, width, 3):
            raise ValueError("Unexpected frame count or geometry")
        blue, green, red = (frame[:, :, index].astype(np.uint16) for index in range(3))
        pixels = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
        raw = pixels.astype("<u2", copy=False).tobytes()
        compressed = lz4.block.compress(raw, store_size=False)
        if lz4.block.decompress(compressed, uncompressed_size=len(raw)) != raw:
            raise ValueError("Frame did not round-trip")
        file.write(compressed)
        offsets.append(file.tell() - header_size)
    if capture.read()[0]:
        raise ValueError("Unexpected extra frames")
    file.seek(0)
    file.write(struct.pack("<8sIII", b"GUMATX01", width, height, count))
    file.write(struct.pack(f"<{len(offsets)}I", *offsets))
with target.open("rb") as file:
    digest = hashlib.file_digest(file, "sha256").hexdigest()
print(f"{target.name}: {target.stat().st_size:,} bytes; SHA256 {digest}")
