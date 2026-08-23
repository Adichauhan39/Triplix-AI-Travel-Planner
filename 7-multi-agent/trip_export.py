"""Renders a trip plan as shareable day images, and from those a PDF or MP4.

One renderer, two outputs. A day is drawn once as an image; Pillow writes
those images straight out as a multi-page PDF, and ffmpeg stitches the same
frames into a video. Keeping a single drawing path means the PDF and the video
can never drift apart, and adding a third format later is a new writer rather
than a new renderer.

A note on the photos: these come from Google Places, whose terms restrict
storing them and creating redistributable derivative works. Baking them into a
file the user can share is a heavier use than displaying them in the app.
Kept deliberately visible here rather than buried, so the decision is easy to
revisit — passing include_photos=False renders text-only cards that carry no
such constraint.
"""

import io
import os
import tempfile
from typing import Any, Dict, List, Optional

import requests
from PIL import Image, ImageDraw, ImageFont

# 1080x1350 is the portrait frame that reads well both printed and on a phone,
# and is what social platforms accept without cropping.
WIDTH, HEIGHT = 1080, 1350
MARGIN = 64

INK = (17, 24, 39)
MUTED = (107, 114, 128)
ACCENT = (13, 13, 130)
PAPER = (255, 255, 255)
CARD = (243, 244, 246)


def _font(size: int, bold: bool = False):
    """A real font if the system has one, otherwise Pillow's default.

    Never raises: a missing font must degrade the picture, not fail the
    export. The default is small and ugly at these sizes, but a plain PDF
    beats a 500.
    """
    candidates = (
        ["arialbd.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf"]
        if bold else
        ["arial.ttf", "segoeui.ttf", "DejaVuSans.ttf"]
    )
    for name in candidates:
        try:
            return ImageFont.truetype(name, size)
        except Exception:
            continue
    return ImageFont.load_default()


def _wrap(draw, text: str, font, max_width: int) -> List[str]:
    """Greedy word wrap measured against the actual font, not a guess."""
    words = str(text).split()
    lines, current = [], ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width or not current:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def _fetch_image(url: str, size) -> Optional[Image.Image]:
    """A photo cropped to fill [size], or None if it can't be had.

    Failure is silent by design. A day whose photo won't download still
    renders, minus the picture — the alternative is one dead URL taking out
    the whole export.
    """
    if not url:
        return None
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            return None
        img = Image.open(io.BytesIO(resp.content)).convert("RGB")
    except Exception:
        return None

    target_w, target_h = size
    scale = max(target_w / img.width, target_h / img.height)
    img = img.resize((max(1, int(img.width * scale)),
                      max(1, int(img.height * scale))), Image.LANCZOS)
    left = (img.width - target_w) // 2
    top = (img.height - target_h) // 2
    return img.crop((left, top, left + target_w, top + target_h))


def render_day(day: Dict[str, Any], destination: str, day_number: int,
               total_days: int, include_photos: bool = True) -> Image.Image:
    """One day as a single portrait image."""
    canvas = Image.new("RGB", (WIDTH, HEIGHT), PAPER)
    draw = ImageDraw.Draw(canvas)

    f_kicker = _font(30)
    f_title = _font(64, bold=True)
    f_date = _font(32)
    f_place = _font(38, bold=True)
    f_body = _font(28)
    f_small = _font(24)

    # Header band
    draw.rectangle([0, 0, WIDTH, 230], fill=ACCENT)
    draw.text((MARGIN, 54), "TRIPLIX", font=f_kicker, fill=(255, 255, 255))
    draw.text((MARGIN, 100), f"Day {day_number} of {total_days}",
              font=f_title, fill=(255, 255, 255))

    y = 264
    subtitle = day.get("date_label") or ""
    if destination:
        subtitle = f"{destination.split(',')[0]}   ·   {subtitle}".strip(" ·")
    draw.text((MARGIN, y), subtitle, font=f_date, fill=MUTED)
    y += 62

    # Confirmed legs first: they are the fixed points of the day.
    for line in day.get("fixed", [])[:3]:
        draw.rectangle([MARGIN, y, WIDTH - MARGIN, y + 66], fill=CARD)
        draw.text((MARGIN + 20, y + 18), str(line)[:70], font=f_body, fill=INK)
        y += 80

    if day.get("fixed"):
        y += 10

    items = day.get("items", [])
    for item in items[:3]:
        if y > HEIGHT - 260:
            break
        title = str(item.get("title", ""))[:40]
        photo_url = item.get("photo") if include_photos else None

        if photo_url:
            photo = _fetch_image(photo_url, (168, 168))
            if photo is not None:
                canvas.paste(photo, (MARGIN, y))
                text_x = MARGIN + 192
            else:
                text_x = MARGIN
        else:
            text_x = MARGIN

        draw.text((text_x, y + 4), title, font=f_place, fill=INK)
        text_width = WIDTH - MARGIN - text_x

        meta = []
        if item.get("rating"):
            meta.append(f"{item['rating']} stars")
        if item.get("hours_today"):
            meta.append(str(item["hours_today"]))
        if meta:
            draw.text((text_x, y + 54), "   ·   ".join(meta)[:52],
                      font=f_small, fill=MUTED)

        about = str(item.get("about", ""))
        if about:
            for i, line in enumerate(_wrap(draw, about, f_small,
                                           text_width)[:2]):
                draw.text((text_x, y + 92 + i * 32), line, font=f_small,
                          fill=MUTED)
        y += 200

    # The running order, if this day has one.
    notes = day.get("notes", [])
    if notes and y < HEIGHT - 200:
        draw.text((MARGIN, y), "Running order", font=f_small, fill=ACCENT)
        y += 40
        for line in notes:
            if y > HEIGHT - 90:
                break
            for wrapped in _wrap(draw, f"- {line}", f_small,
                                 WIDTH - 2 * MARGIN)[:1]:
                draw.text((MARGIN, y), wrapped, font=f_small, fill=INK)
                y += 34

    if len(items) > 3:
        draw.text((MARGIN, HEIGHT - 76),
                  f"+ {len(items) - 3} more in the app", font=f_small,
                  fill=MUTED)

    return canvas


def render_title(destination: str, days: List[Dict[str, Any]],
                 include_photos: bool = True) -> Image.Image:
    """The opening card: where, and over how long."""
    canvas = Image.new("RGB", (WIDTH, HEIGHT), ACCENT)
    draw = ImageDraw.Draw(canvas)

    # A photo from the trip behind the title, dimmed so the words stay
    # readable. Falls back to the flat colour when there is nothing to use.
    if include_photos:
        for day in days:
            for item in day.get("items", []):
                photo = _fetch_image(item.get("photo", ""), (WIDTH, HEIGHT))
                if photo is not None:
                    canvas.paste(photo, (0, 0))
                    shade = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
                    canvas = Image.blend(canvas, shade, 0.55)
                    draw = ImageDraw.Draw(canvas)
                    break
            else:
                continue
            break

    first = days[0].get("date_label", "") if days else ""
    last = days[-1].get("date_label", "") if days else ""
    span = first if first == last else f"{first}  -  {last}"

    draw.text((MARGIN, HEIGHT // 2 - 190), "TRIPLIX", font=_font(34),
              fill=(255, 255, 255))
    name = destination.split(",")[0].strip() or "Your trip"
    draw.text((MARGIN, HEIGHT // 2 - 130), name, font=_font(96, bold=True),
              fill=(255, 255, 255))
    draw.text((MARGIN, HEIGHT // 2 + 10), span, font=_font(36),
              fill=(235, 235, 245))
    total = sum(len(d.get("items", [])) for d in days)
    draw.text((MARGIN, HEIGHT // 2 + 76),
              f"{len(days)} days   ·   {total} places", font=_font(32),
              fill=(210, 210, 230))
    return canvas


def render_place(item: Dict[str, Any], day_number: int,
                 include_photos: bool = True) -> Image.Image:
    """One place, photo-led — the shot a slideshow of text cards lacks."""
    canvas = Image.new("RGB", (WIDTH, HEIGHT), INK)
    draw = ImageDraw.Draw(canvas)

    photo = _fetch_image(item.get("photo", ""), (WIDTH, HEIGHT)) \
        if include_photos else None
    if photo is not None:
        canvas.paste(photo, (0, 0))
        # A gradient foot rather than a flat overlay: the picture stays
        # visible at the top while the text below it stays legible.
        overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
        odraw = ImageDraw.Draw(overlay)
        for y in range(HEIGHT - 460, HEIGHT):
            alpha = int(235 * (y - (HEIGHT - 460)) / 460)
            odraw.line([(0, y), (WIDTH, y)], fill=(0, 0, 0, alpha))
        canvas = Image.alpha_composite(
            canvas.convert("RGBA"), overlay).convert("RGB")
        draw = ImageDraw.Draw(canvas)

    y = HEIGHT - 330
    draw.text((MARGIN, y), f"DAY {day_number}", font=_font(30),
              fill=(200, 200, 220))
    y += 46
    for line in _wrap(draw, str(item.get("title", "")), _font(66, bold=True),
                      WIDTH - 2 * MARGIN)[:2]:
        draw.text((MARGIN, y), line, font=_font(66, bold=True),
                  fill=(255, 255, 255))
        y += 74

    meta = []
    if item.get("rating"):
        meta.append(f"{item['rating']} stars")
    if item.get("hours_today"):
        meta.append(str(item["hours_today"]))
    if meta:
        draw.text((MARGIN, y + 6), "   ·   ".join(meta)[:52], font=_font(28),
                  fill=(220, 220, 235))
        y += 44

    about = str(item.get("about", ""))
    if about:
        for line in _wrap(draw, about, _font(26), WIDTH - 2 * MARGIN)[:2]:
            draw.text((MARGIN, y + 10), line, font=_font(26),
                      fill=(205, 205, 220))
            y += 34
    return canvas


def render_closing(destination: str) -> Image.Image:
    canvas = Image.new("RGB", (WIDTH, HEIGHT), ACCENT)
    draw = ImageDraw.Draw(canvas)
    name = destination.split(",")[0].strip()
    draw.text((MARGIN, HEIGHT // 2 - 90),
              f"See you in {name}" if name else "Have a good trip",
              font=_font(66, bold=True), fill=(255, 255, 255))
    draw.text((MARGIN, HEIGHT // 2 + 10), "Planned with Triplix",
              font=_font(32), fill=(215, 215, 235))
    return canvas


def render_film(days: List[Dict[str, Any]], destination: str,
                include_photos: bool = True) -> List[Image.Image]:
    """The full running order of shots: title, then each day and its places.

    A day card alone tells the viewer what is happening; a photo-led shot per
    place is what makes it read as a film rather than a slideshow of
    paperwork. Days with nothing in them still get their card, since an empty
    day is part of the trip.
    """
    frames = [render_title(destination, days, include_photos)]
    total = len(days)
    for i, day in enumerate(days):
        frames.append(render_day(day, destination, i + 1, total,
                                 include_photos))
        for item in day.get("items", [])[:3]:
            frames.append(render_place(item, i + 1, include_photos))
    frames.append(render_closing(destination))
    return frames


def render_days(days: List[Dict[str, Any]], destination: str,
                include_photos: bool = True) -> List[Image.Image]:
    total = len(days)
    return [render_day(day, destination, i + 1, total, include_photos)
            for i, day in enumerate(days)]


def build_pdf(frames: List[Image.Image]) -> bytes:
    """The day images as a multi-page PDF.

    Pillow writes this directly, so the PDF needs no dependency the video
    doesn't already require.
    """
    if not frames:
        return b""
    buffer = io.BytesIO()
    frames[0].save(buffer, format="PDF", save_all=True,
                   append_images=frames[1:], resolution=150)
    return buffer.getvalue()


def build_video(frames: List[Image.Image], seconds_per_day: float = 3.0
                ) -> bytes:
    """The same frames as an MP4 slideshow.

    Written through ffmpeg's image2 demuxer rather than frame-by-frame
    encoding: the input is a handful of stills, and holding each for a few
    seconds is all a trip recap needs.
    """
    if not frames:
        return b""

    import imageio_ffmpeg

    workdir = tempfile.mkdtemp(prefix="triplix_video_")
    try:
        for i, frame in enumerate(frames):
            # yuv420p needs even dimensions; the canvas is already even, but
            # a future size change should not silently produce a broken file.
            frame.save(os.path.join(workdir, f"frame_{i:03d}.png"))

        out_path = os.path.join(workdir, "trip.mp4")
        exe = imageio_ffmpeg.get_ffmpeg_exe()
        fps = 25
        hold = max(0.5, seconds_per_day)
        per_frame = int(fps * hold)
        total_frames = per_frame * len(frames)

        # zoompan gives each still a slow push in, which is what separates a
        # film from a slideshow -- the eye reads a moving image as intentional
        # and a static one as a document. Done in one filter chain rather than
        # an xfade graph per frame, which grows unwieldy and fails oddly on
        # long trips.
        #
        # d= holds each input for the whole shot; the 1.0008 step is a ~10%
        # zoom across it, gentle enough not to look like a mistake. s= locks
        # the output size, since zoompan otherwise renders at its own scale.
        motion = (
            f"zoompan=z='min(zoom+0.0008,1.10)':d={per_frame}"
            f":x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
            f":s={WIDTH}x{HEIGHT}:fps={fps},"
            f"fade=t=in:st=0:d=0.6,"
            f"fade=t=out:st={max(0.0, total_frames / fps - 0.8):.2f}:d=0.8,"
            "format=yuv420p"
        )

        cmd = [
            exe, "-y",
            "-framerate", f"{1 / hold}",
            "-i", os.path.join(workdir, "frame_%03d.png"),
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-pix_fmt", "yuv420p",
            "-vf", motion,
            out_path,
        ]
        import subprocess
        result = subprocess.run(cmd, capture_output=True, timeout=120)
        if result.returncode != 0 or not os.path.exists(out_path):
            raise RuntimeError(
                (result.stderr or b"").decode("utf-8", "replace")[-400:])

        with open(out_path, "rb") as fh:
            return fh.read()
    finally:
        # Best effort: a left-behind temp directory is untidy, not harmful.
        try:
            for name in os.listdir(workdir):
                os.remove(os.path.join(workdir, name))
            os.rmdir(workdir)
        except Exception:
            pass
