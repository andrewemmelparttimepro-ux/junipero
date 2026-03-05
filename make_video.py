#!/usr/bin/env python3
"""Generate Junipero_The_Last_App_Video_Ad.mp4"""

import os, sys, subprocess, math
from PIL import Image, ImageDraw, ImageFont

# Paths
WORKSPACE = "/Users/crustacean/.openclaw/workspace/projects/junipero"
LOGO_PATH = f"{WORKSPACE}/junipero-icon.png"
AUDIO_PATH = f"{WORKSPACE}/junipero_voiceover.mp3"
FRAMES_DIR = f"{WORKSPACE}/frames"
OUT_PATH = f"{WORKSPACE}/Junipero_The_Last_App_Video_Ad.mp4"

os.makedirs(FRAMES_DIR, exist_ok=True)

W, H = 1080, 1920
FPS = 30
DURATION = 49.1
TOTAL_FRAMES = int(DURATION * FPS)

BG_COLOR = (5, 5, 16)
WHITE = (255, 255, 255)
BLUE = (120, 160, 255)
MUTED = (170, 170, 200)

# Font setup
def load_font(size, bold=False):
    paths = [
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Avenir Next.ttc",
    ]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except:
            continue
    return ImageFont.load_default()

# Logo
logo_img = Image.open(LOGO_PATH).convert("RGBA")
LOGO_SIZE = 480
logo_img = logo_img.resize((LOGO_SIZE, LOGO_SIZE), Image.LANCZOS)
LOGO_X = (W - LOGO_SIZE) // 2
LOGO_Y = (H // 2) - LOGO_SIZE // 2 - 120

# Text segments: (start_sec, end_sec, text, color, fontsize, y_frac)
# Timed to match the voiceover pacing
segments = [
    # "You found Junipero." ~ 0-3s
    (0.5,  5.0,  "You found Junipero.",       WHITE,  52, 0.735),
    # "Not by accident." ~ 3-7s
    (3.0,  8.0,  "Not by accident.",           MUTED,  40, 0.800),
    # "Most people..." ~ 8-20s
    (8.0,  20.0, "Most people collect apps.",  WHITE,  44, 0.735),
    (11.0, 20.0, "A tool for this.",           MUTED,  36, 0.790),
    (13.0, 20.0, "A tool for that.",           MUTED,  36, 0.830),
    # "Junipero is different." ~ 20-25s
    (20.5, 30.0, "Junipero is different.",     WHITE,  52, 0.735),
    # "It replaces them." ~ 25-34s
    (25.0, 34.0, "It doesn't compete.",        MUTED,  40, 0.790),
    (27.5, 34.0, "It replaces.",               WHITE,  56, 0.840),
    # "Native. Quiet. Watching." ~ 34-39s
    (34.0, 39.5, "Native. Quiet. Watching.",   MUTED,  40, 0.735),
    # "The race is over." ~ 39-44s
    (39.5, 46.0, "The race is over.",          WHITE,  58, 0.735),
    # "Junipero won." ~ 43-49s
    (43.0, 49.1, "Junipero won.",              BLUE,   72, 0.800),
]

def alpha_for(t, start, end):
    fade = 0.8
    if t < start or t > end:
        return 0.0
    if t < start + fade:
        return (t - start) / fade
    if t > end - fade:
        return (end - t) / fade
    return 1.0

print(f"Rendering {TOTAL_FRAMES} frames...")

for frame_i in range(TOTAL_FRAMES):
    t = frame_i / FPS

    img = Image.new("RGB", (W, H), BG_COLOR)
    draw = ImageDraw.Draw(img)

    # Subtle vignette gradient (pre-baked as overlay would be slow; skip for speed)

    # Logo with pulse glow
    logo_alpha = min(1.0, t / 1.5)  # fade in
    if logo_alpha > 0:
        la = logo_img.copy()
        if logo_alpha < 1.0:
            alpha = la.split()[3]
            alpha = alpha.point(lambda x: int(x * logo_alpha))
            la.putalpha(alpha)
        img.paste(la, (LOGO_X, LOGO_Y), la)

    # Text segments
    for (start, end, text, color, size, y_frac) in segments:
        a = alpha_for(t, start, end)
        if a <= 0:
            continue
        font = load_font(size)
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        tx = (W - tw) // 2
        ty = int(H * y_frac)
        # Apply alpha by blending color toward bg
        blended = tuple(int(c * a + BG_COLOR[i] * (1 - a)) for i, c in enumerate(color))
        draw.text((tx, ty), text, fill=blended, font=font)

    frame_path = f"{FRAMES_DIR}/frame_{frame_i:05d}.png"
    img.save(frame_path, "PNG")

    if frame_i % (FPS * 5) == 0:
        print(f"  {t:.1f}s / {DURATION:.1f}s")

print("Frames done. Encoding video...")

subprocess.run([
    "ffmpeg", "-y",
    "-r", str(FPS),
    "-i", f"{FRAMES_DIR}/frame_%05d.png",
    "-i", AUDIO_PATH,
    "-c:v", "libx264", "-preset", "fast", "-crf", "18",
    "-c:a", "aac", "-b:a", "192k",
    "-pix_fmt", "yuv420p",
    "-t", str(DURATION),
    OUT_PATH
], check=True)

print(f"Done: {OUT_PATH}")

# Cleanup frames
import shutil
shutil.rmtree(FRAMES_DIR)
print("Cleaned up frames.")
