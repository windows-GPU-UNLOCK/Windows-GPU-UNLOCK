# SPDX-License-Identifier: GPL-2.0-only
"""Render a 1080p cinematic concept to an offline preview video."""
from pathlib import Path
import math
import subprocess

import cv2
import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H, FPS, CX, CY = 1920, 1080, 30, 960, 470
rng = np.random.default_rng(3090)
Y, X = np.ogrid[:H, :W]
dx, dy = X - CX, Y - CY
radial = np.exp(-((dx / 680) ** 2 + (dy / 420) ** 2))
vignette = np.clip(1 - (dx / 1200) ** 2 - ((Y - 540) / 850) ** 2, .17, 1)
noise = rng.normal(0, .9, (H, W))
board = np.empty((H, W, 3), np.uint8)
for channel, base, intensity in [(0, 9, 15), (1, 20, 48), (2, 8, 15)]:
    board[:, :, channel] = np.clip((base + intensity * radial + noise) * vignette, 0, 255)

power_routes = []
for side in (-1, 1):
    for i in range(33):
        y = CY - 250 + i * 15
        bend = CX + side * (340 + rng.integers(25, 270))
        end = CX + side * rng.integers(680, 1040)
        offset = int((i - 16) * rng.uniform(4, 9))
        route = np.array([(CX + side * 238, y), (bend, y),
                          (bend + side * 65, y + offset), (end, y + offset)], np.int32)
        cv2.polylines(board, [route], False, (25, 58, 23), 3, cv2.LINE_AA)
        cv2.polylines(board, [route], False, (38, 99, 62), 1, cv2.LINE_AA)
        cv2.circle(board, tuple(route[-2]), 4, (35, 116, 76), 1, cv2.LINE_AA)
        # Start the electrical pulse at the board edge and lead it to the chip.
        points = route[::-1].astype(float)
        lengths = np.linalg.norm(np.diff(points, axis=0), axis=1)
        distances = np.concatenate(([0.0], np.cumsum(lengths)))
        delay = .08 + abs(i - 16) * .076 + (.09 if side == 1 else 0)
        power_routes.append((points, distances, delay))
for _ in range(230):
    x, y = rng.integers(0, W), rng.integers(0, H)
    if abs(x - CX) > 285:
        length = int(rng.integers(4, 16))
        cv2.rectangle(board, (x, y), (x + length, y + 4), (26, 58, 29), -1)

def rounded_mask(width, height, radius):
    image = Image.new("L", (W, H))
    ImageDraw.Draw(image).rounded_rectangle(
        (CX-width//2, CY-height//2, CX+width//2, CY+height//2), radius, fill=255)
    return np.asarray(image)

outer = rounded_mask(590, 395, 12)
inner = rounded_mask(322, 236, 7)
shadow = cv2.GaussianBlur(outer, (0, 0), 24).astype(np.float32) / 255
board = (board * (1 - .8 * shadow[:, :, None])).astype(np.uint8)
for x in range(CX-273, CX+274, 11):
    for side in (-1, 1):
        a, b = sorted((CY+side*193, CY+side*217))
        cv2.rectangle(board, (x, a), (x+5, b), (34, 84, 135), -1)
        cv2.line(board, (x, a), (x, b), (86, 162, 202), 1, cv2.LINE_AA)

# Copper planes under a dark green package, with an exposed silicon die.
substrate = np.clip(20 + 18 * np.exp(-((dy + 95 + dx*.3)/140)**2) + noise, 0, 255)
for channel, factor in enumerate((.68, 1.47, .73)):
    board[:, :, channel] = np.where(outer > 0, substrate * factor, board[:, :, channel])
cv2.line(board, (CX-278, CY+194), (CX+278, CY+194), (10, 23, 12), 6, cv2.LINE_AA)
for side in (-1, 1):
    for i in range(17):
        y = CY - 146 + i * 18
        end_y = CY - 105 + i * 13
        for j in range(2):
            x = CX + side * (272 - j*14)
            cv2.circle(board, (x,y), 2, (48, 111, 99), 1, cv2.LINE_AA)
        route = np.array([(CX+side*257,y), (CX+side*220,y),
                          (CX+side*187,end_y), (CX+side*156,end_y)], np.int32)
        cv2.polylines(board, [route], False, (32, 71, 63), 1, cv2.LINE_AA)
    for x in range(CX-145, CX+146, 26):
        for y in (CY+side*148, CY+side*165):
            cv2.rectangle(board, (x-8,y-4), (x+9,y+5), (9, 14, 11), -1)
            cv2.rectangle(board, (x-7,y-4), (x+7,y+3), (114, 139, 157), -1)
            cv2.rectangle(board, (x-4,y-4), (x+4,y+3), (54, 73, 92), -1)
            cv2.line(board, (x-7,y-4), (x+7,y-4), (156, 174, 190), 1)
die_base = rounded_mask(350, 258, 9)
die_shadow = cv2.GaussianBlur(die_base, (0, 0), 9).astype(np.float32) / 255
board = (board * (1 - .65 * die_shadow[:, :, None])).astype(np.uint8)
board[die_base > 0] = (38, 57, 53)
reflect = np.exp(-((dy + 46 + dx*.37)/53)**2)
secondary = np.exp(-((dy - 61 + dx*.22)/90)**2)
grain = np.sin(dx*.78 + dy*.13)*1.4 + noise
for channel, (base, light, tint) in enumerate(((28, 79, 23), (32, 89, 34), (35, 50, 19))):
    silicon = base + light*reflect + tint*secondary + grain
    board[:, :, channel] = np.where(inner > 0, silicon, board[:, :, channel])
for mask, color in [(outer, (47, 97, 66)), (die_base, (88, 124, 112)), (inner, (100, 145, 139))]:
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(board, contours, -1, color, 1, cv2.LINE_AA)
cv2.line(board, (CX-151, CY-117), (CX+151, CY-117), (161, 177, 157), 1, cv2.LINE_AA)
cv2.line(board, (CX-151, CY+118), (CX+151, CY+118), (15, 24, 21), 2, cv2.LINE_AA)

def label(text, size, y, color=(214, 255, 224), bold=False):
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=size)
    draw.text((CX, y), text, fill=color, font=font, anchor="mm")
    return cv2.cvtColor(np.asarray(image), cv2.COLOR_RGB2BGR)

board = cv2.add(board, label("GPU", 82, CY-8, (131, 172, 150), bold=True))
rtx_text = "G R A P H I C S   P R O C E S S O R"
board = cv2.add(board, label(rtx_text, 20, CY+48, (73, 105, 86), bold=True))
chip_emission = label("GPU", 82, CY-8, (123, 245, 160), bold=True)
chip_halo = cv2.GaussianBlur(chip_emission, (0, 0), 9)
rtx_emission = label(rtx_text, 20, CY+48, (140, 255, 169), bold=True)
rtx_halo = cv2.GaussianBlur(rtx_emission, (0, 0), 4)
title_image = Image.new("RGB", (W, H))
title_draw = ImageDraw.Draw(title_image)
title_font = ImageFont.load_default(size=42)
title = "GPU UNLOCK"
tracking = 4
widths = [title_font.getlength(letter) for letter in title]
x = CX - (sum(widths) + tracking * (len(title) - 1)) / 2
for letter, width in zip(title, widths):
    title_draw.text((x, 112), letter, fill=(188, 240, 201), font=title_font, anchor="lm")
    x += width + tracking
title_pixels = cv2.cvtColor(np.asarray(title_image), cv2.COLOR_RGB2BGR)
board = cv2.add(board, title_pixels)
cv2.addWeighted(board, 1, cv2.GaussianBlur(title_pixels, (0, 0), 6), .6, 0, board)
captions = [label("Unlocking GPU", 63, 866, bold=True)]
for number in (1, 2, 3):
    captions.append(cv2.add(label(f"Starting in {number}", 54, 866, bold=True),
                            label("Esc   ·   Start Windows without unlock", 25, 950, (118, 179, 135))))

count = 2350
angle = rng.uniform(0, 2 * math.pi, count)
cos, sin = np.cos(angle), np.sin(angle)
offset = rng.random(count)
velocity = rng.uniform(.14, .64, count)
reach = rng.uniform(220, 1280, count)
depth = rng.uniform(.22, 1, count)
colors = np.array([(64, 255, 89), (21, 242, 53), (135, 255, 176),
                   (18, 173, 43), (64, 255, 191)], np.float32)
hue = colors[rng.choice(len(colors), count, p=[.34, .24, .20, .13, .09])]
rim = cv2.subtract(outer, cv2.erode(outer, np.ones((5, 5), np.uint8)))
rim_light = np.zeros_like(board)
rim_light[rim > 0] = (48, 156, 72)
die_rim = cv2.subtract(inner, cv2.erode(inner, np.ones((3, 3), np.uint8)))
rim_light[die_rim > 0] = (82, 225, 118)
rain_x = [x for x in range(42, W, 38) if abs(x - CX) > 330]
rain = [(x, int(rng.integers(0, H)), int(rng.integers(115, 340)),
         "".join(rng.choice(list("010101ABCDEF"), 17))) for x in rain_x]
out = Path("splash-preview.mp4")

def draw_power_routes(effects, t, charge):
    for points, distances, delay in power_routes:
        progress = min(1, (t - delay) / .88)
        if progress <= 0:
            continue
        front = distances[-1] * progress
        tail = max(0, front - 125)
        brightness = 36 + int(100 * charge)
        for i in range(len(points) - 1):
            start, end = distances[i:i+2]
            if start >= front or end <= start:
                continue
            a, b = points[i:i+2]
            finish = a + (b-a) * ((min(end, front)-start)/(end-start))
            p, q = tuple(a.astype(int)), tuple(finish.astype(int))
            cv2.line(effects, p, q, (11, brightness, 35), 3, cv2.LINE_AA)
            if end > tail:
                pulse = a + (b-a) * ((max(start, tail)-start)/(end-start))
                cv2.line(effects, tuple(pulse.astype(int)), q, (70, 242, 143), 2, cv2.LINE_AA)
            if end >= front:
                cv2.circle(effects, q, 4, (152, 255, 209), -1, cv2.LINE_AA)
        if progress >= 1:
            cv2.circle(effects, tuple(points[-1].astype(int)), 3, (58, 197, 92), -1, cv2.LINE_AA)
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
with subprocess.Popen([ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                       "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{W}x{H}",
                       "-r", str(FPS), "-i", "-", "-an", "-c:v", "libx264",
                       "-preset", "fast", "-crf", "17", "-pix_fmt", "yuv420p",
                       "-movflags", "+faststart", str(out)], stdin=subprocess.PIPE) as encoder:
    for index in range(112):
        t = index / FPS
        charge = min(t / 3, 1) ** 1.4
        burst = max(0, min((t - 3) / .48, 1))
        effects = np.zeros_like(board)
        if t < 3:
            draw_power_routes(effects, t, charge)
        for x, start, speed, glyphs in rain:
            head = int((start + speed * t) % (H + 390))
            for j, glyph in enumerate(glyphs):
                y = head - j * 22
                if 55 < y < H-55:
                    strength = int((1 - j / len(glyphs)) * (26 + 45 * charge))
                    cv2.putText(effects, glyph, (x, y), cv2.FONT_HERSHEY_SIMPLEX,
                                .45, (strength//4, strength, strength//3), 1, cv2.LINE_AA)
        if t < 3:
            phase = (offset + t * velocity) % 1
            radius = 271 + (1 - phase) ** 1.3 * reach
            strength = np.sin(phase * math.pi) * depth * (.18 + .74 * charge)
            trail = (9 + 58 * charge) * depth
            direction = 1
        else:
            radius = 226 + (1 - (1 - burst) ** 1.75) * reach
            strength = depth * (1 - .56 * burst)
            trail = (20 + 95 * burst) * depth
            direction = -1
        positions_x = (CX + cos * radius).astype(int)
        positions_y = (CY + sin * radius * .71).astype(int)
        tails_x = (positions_x + direction * cos * trail).astype(int)
        tails_y = (positions_y + direction * sin * trail * .71).astype(int)
        shades = (hue * strength[:, None]).astype(int)
        for i in range(count if t >= 3 else 450 + int(charge * 1400)):
            x, y = positions_x[i], positions_y[i]
            if -120 < x < W+120 and -120 < y < H+120:
                color = tuple(map(int, shades[i]))
                cv2.line(effects, (x, y), (tails_x[i], tails_y[i]), color,
                         1 + int(depth[i] > .7), cv2.LINE_AA)
                if i % 7 == 0:
                    cv2.circle(effects, (x, y), 2, color, -1, cv2.LINE_AA)
        cv2.addWeighted(effects, 1, rim_light, .08 + .75 * charge, 0, effects)
        if t >= 3 and burst < 1:
            shock = 260 + int(1050 * burst)
            cv2.ellipse(effects, (CX, CY), (shock, int(shock * .71)), 0, 0, 360,
                        (int(105 * (1-burst)), 255, int(116 * (1-burst))), 3, cv2.LINE_AA)
        small = cv2.resize(effects, (W//4, H//4), interpolation=cv2.INTER_AREA)
        bloom = cv2.resize(cv2.GaussianBlur(small, (0, 0), 4), (W, H))
        frame = cv2.add(board, effects)
        cv2.addWeighted(frame, 1, bloom, 2.15, 0, frame)
        if t >= 3:
            ignition = min(burst * 5, 1)
            pulse = ignition * (.26 + .74 * (1 - burst) ** 1.7)
            cv2.addWeighted(frame, 1, chip_halo, pulse * 2.2, 0, frame)
            cv2.addWeighted(frame, 1, chip_emission, pulse, 0, frame)
            rtx_pulse = ignition * (.76 + .24 * (1 - burst))
            cv2.addWeighted(frame, 1, rtx_halo, rtx_pulse * 3.3, 0, frame)
            cv2.addWeighted(frame, 1, rtx_emission, rtx_pulse, 0, frame)
        cv2.add(frame, captions[max(1, 3-index//FPS) if t < 3 else 0], frame)
        if index == 98:
            cv2.imwrite(str(out.with_suffix(".jpg")), frame)
        encoder.stdin.write(frame.tobytes())
    encoder.stdin.close()
    if encoder.wait() != 0:
        raise RuntimeError("FFmpeg failed to encode the preview")
print(out)
