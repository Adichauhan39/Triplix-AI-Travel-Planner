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
import math
from urllib.parse import quote

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# 1080x1350 is the portrait frame that reads well both printed and on a phone,
# and is what social platforms accept without cropping.
WIDTH, HEIGHT = 1080, 1350
MARGIN = 64

# The film is 9:16, the page stays 4:5. WhatsApp Status and Reels are where a
# trip video actually gets shared, and a 4:5 video is letterboxed there; a PDF
# page has no such constraint and 4:5 prints better.
FILM_WIDTH, FILM_HEIGHT = 1080, 1920

# Shown on every frame and page that carries a Google Places photograph.
# Their terms require the credit to be displayed and never removed, hidden or
# obscured; the map shots already carry the logo Google bakes into its tiles,
# but the photographs carried nothing at all.
PHOTO_CREDIT = "Photos: Google"

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
    drew_photo = False
    for item in items[:3]:
        if y > HEIGHT - 260:
            break
        title = str(item.get("title", ""))[:40]
        photo_url = item.get("photo") if include_photos else None

        if photo_url:
            photo = _fetch_image(photo_url, (168, 168))
            if photo is not None:
                canvas.paste(photo, (MARGIN, y))
                drew_photo = True
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

    # Credited on any page that actually shows a photograph. A page whose
    # places had none carries no credit, because there is nothing to credit.
    if drew_photo:
        draw.text(
            (WIDTH - MARGIN - draw.textlength(PHOTO_CREDIT, font=f_small),
             HEIGHT - 76),
            PHOTO_CREDIT, font=f_small, fill=MUTED)

    return canvas


def render_title(destination: str, days: List[Dict[str, Any]],
                 include_photos: bool = True) -> Image.Image:
    """The opening card: where, and over how long."""
    canvas = Image.new("RGB", (WIDTH, HEIGHT), ACCENT)
    draw = ImageDraw.Draw(canvas)

    # A photo from the trip behind the title, dimmed so the words stay
    # readable. Falls back to the flat colour when there is nothing to use.
    used_photo = False
    if include_photos:
        for day in days:
            for item in day.get("items", []):
                photo = _fetch_image(item.get("photo", ""), (WIDTH, HEIGHT))
                if photo is not None:
                    canvas.paste(photo, (0, 0))
                    shade = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
                    canvas = Image.blend(canvas, shade, 0.55)
                    draw = ImageDraw.Draw(canvas)
                    used_photo = True
                    break
            else:
                continue
            break

    # Credited here too: this card is a photograph like any other shot.
    if used_photo:
        credit = _font(22)
        draw.text((WIDTH - MARGIN - draw.textlength(PHOTO_CREDIT, font=credit),
                   HEIGHT - 48),
                  PHOTO_CREDIT, font=credit, fill=(214, 214, 228))

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

    # Narration takes the place of the description when there is one: it says
    # the same thing in a line meant to be read over a picture, and printing
    # both would be the same fact twice in two voices.
    narration = str(item.get("narration", "")).strip()
    body = narration or str(item.get("about", ""))
    if body:
        font = _font(28) if narration else _font(26)
        colour = (238, 238, 248) if narration else (205, 205, 220)
        for line in _wrap(draw, body, font, WIDTH - 2 * MARGIN)[:2]:
            draw.text((MARGIN, y + 10), line, font=font, fill=colour)
            y += 36
    return canvas


def render_place_layers(item: Dict[str, Any], day_number: int,
                        include_photos: bool = True):
    """A place shot as (picture, text layer), both at film size.

    Split so the words can arrive after the picture. Painted into a single
    image they appear the instant the shot cuts, which reads as a caption
    stuck on the frame rather than a title introducing it.
    """
    w, h = FILM_WIDTH, FILM_HEIGHT
    base = Image.new("RGB", (w, h), INK)
    photo = _fetch_image(item.get("photo", ""), (w, h)) \
        if include_photos else None
    if photo is not None:
        base.paste(photo, (0, 0))

    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # A gradient foot keeps the picture visible up top while the words stay
    # legible below.
    for y in range(h - 620, h):
        alpha = int(238 * (y - (h - 620)) / 620)
        draw.line([(0, y), (w, y)], fill=(0, 0, 0, alpha))

    y = h - 430
    draw.text((MARGIN, y), f"DAY {day_number}", font=_font(32),
              fill=(198, 198, 222, 255))
    y += 50
    for line in _wrap(draw, str(item.get("title", "")), _font(72, bold=True),
                      w - 2 * MARGIN)[:2]:
        draw.text((MARGIN, y), line, font=_font(72, bold=True),
                  fill=(255, 255, 255, 255))
        y += 82

    meta = []
    if item.get("rating"):
        meta.append(f"{item['rating']} stars")
    if item.get("hours_today"):
        meta.append(str(item["hours_today"]))
    if meta:
        draw.text((MARGIN, y + 8), "   ·   ".join(meta)[:52], font=_font(30),
                  fill=(222, 222, 238, 255))
        y += 48

    body = str(item.get("narration", "")).strip() or str(item.get("about", ""))
    if body:
        for line in _wrap(draw, body, _font(30), w - 2 * MARGIN)[:2]:
            draw.text((MARGIN, y + 12), line, font=_font(30),
                      fill=(236, 236, 248, 255))
            y += 40

    # Whose photograph this is. Google's terms require the credit to be shown
    # and never removed, hidden or obscured, and the film had none: the only
    # attribution anywhere was the logo Google bakes into its own map tiles,
    # which covers the map shots and nothing else.
    #
    # Drawn on the overlay rather than the picture because the overlay is
    # composited after the camera move. Painted onto the base it would be
    # cropped away by the Ken Burns zoom on roughly half the shots, which is
    # exactly the "obscured" the policy rules out.
    if photo is not None:
        credit = _font(24)
        draw.text((w - MARGIN - draw.textlength(PHOTO_CREDIT, font=credit),
                   h - 52),
                  PHOTO_CREDIT, font=credit, fill=(228, 228, 240, 255))

    return base, overlay


def _fit_film(image: Image.Image) -> Image.Image:
    """A 4:5 card centred on a 9:16 canvas, so cards and photos mix cleanly."""
    canvas = Image.new("RGB", (FILM_WIDTH, FILM_HEIGHT), PAPER)
    scale = FILM_WIDTH / image.width
    resized = image.resize(
        (FILM_WIDTH, max(1, int(image.height * scale))), Image.LANCZOS)
    canvas.paste(resized, (0, (FILM_HEIGHT - resized.height) // 2))
    return canvas


def _mercator(lat: float, lng: float, zoom: int):
    """Web Mercator world pixel for a coordinate, at 256px tiles.

    Needed to know where a coordinate lands inside a static map image, so the
    car can be drawn at the right spot. Google gives the picture, not the
    projection, but the projection is fixed and standard.
    """
    import math
    scale = 256 * (2 ** zoom)
    x = (lng + 180.0) / 360.0 * scale
    siny = min(max(math.sin(math.radians(lat)), -0.9999), 0.9999)
    y = (0.5 - math.log((1 + siny) / (1 - siny)) / (4 * math.pi)) * scale
    return x, y


def _fit_zoom(points, width: int, height: int, padding: int = 120) -> int:
    """The closest zoom that still holds every stop inside the frame."""
    for zoom in range(15, 3, -1):
        xs, ys = zip(*[_mercator(la, ln, zoom) for la, ln in points])
        if (max(xs) - min(xs)) <= (width - padding) and \
           (max(ys) - min(ys)) <= (height - padding):
            return zoom
    return 4


def _decode_polyline(encoded: str):
    """Google's encoded polyline format to [(lat, lng)].

    Written out rather than pulled in as a dependency: it is twenty lines of
    a fixed, published format, and the export already asks enough of a
    deployment with Pillow and ffmpeg.
    """
    points, index, lat, lng = [], 0, 0, 0
    while index < len(encoded):
        for is_lat in (True, False):
            shift, result = 0, 0
            while True:
                if index >= len(encoded):
                    return points
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else (result >> 1)
            if is_lat:
                lat += delta
            else:
                lng += delta
        points.append((lat / 1e5, lng / 1e5))
    return points


def fetch_route(points, api_key: str):
    """The driving route through [points], as (overview_encoded, legs).

    The film used to draw the day as straight lines between stops and slide the
    car down them, which is not how anyone travels: it cut across the middle of
    Bhilai rather than following the road. Directions gives the real geometry,
    so the line bends the way the road bends and the car goes with it.

    Legs are kept separate, each a list of coordinates, because the film times
    the journey one hop at a time -- it drives to a stop, arrives, and cuts to
    that place before setting off again.

    Returns None when the route cannot be had; the caller then falls back to
    straight lines rather than losing the map shot entirely.
    """
    if not api_key or len(points) < 2:
        return None
    params = {
        "origin": f"{points[0][0]},{points[0][1]}",
        "destination": f"{points[-1][0]},{points[-1][1]}",
        "mode": "driving",
        "key": api_key,
    }
    if len(points) > 2:
        params["waypoints"] = "|".join(
            f"{la},{ln}" for la, ln in points[1:-1])
    try:
        resp = requests.get(
            "https://maps.googleapis.com/maps/api/directions/json",
            params=params, timeout=15).json()
    except Exception as e:
        print(f"[ROUTE] {e}")
        return None
    if resp.get("status") != "OK" or not resp.get("routes"):
        print(f"[ROUTE] {resp.get('status')}: "
              f"{str(resp.get('error_message') or '')[:120]}")
        return None

    route = resp["routes"][0]
    legs = []
    for leg in route.get("legs", []):
        shape = []
        for step in leg.get("steps", []):
            shape.extend(
                _decode_polyline((step.get("polyline") or {}).get("points", "")))
        legs.append(shape)
    overview = (route.get("overview_polyline") or {}).get("points", "")
    if not overview or not any(legs):
        return None
    return overview, legs


def fetch_day_map(points, api_key: str, size=(FILM_WIDTH, FILM_HEIGHT)):
    """A map of one day's stops, plus where each sits in the image.

    One request per day, not one per frame. The car is animated locally over
    this single picture -- drawing it server-side would mean a billed map
    request twenty-five times a second, which is why this shot is worth
    building at all.

    Returns (image, pixel_points) or None when it cannot be had; the film then
    simply has no map shot rather than failing.
    """
    if not api_key or len(points) < 2:
        return None

    width, height = size
    # Static Maps caps a request at 640x640, doubled with scale=2.
    req_w, req_h = 640, min(640, int(640 * height / width))
    # req_w, not req_w * 2. _fit_zoom measures spans in unscaled world
    # pixels, and scale=2 doubles them in the returned image -- comparing
    # against the doubled size chose a zoom twice too close, which put the
    # first stop on the bottom edge and pushed the last one out of frame.
    zoom = _fit_zoom(points, req_w, req_h)

    centre_lat = sum(p[0] for p in points) / len(points)
    centre_lng = sum(p[1] for p in points) / len(points)

    markers = "".join(
        f"&markers=color:0x0d0d82%7Clabel:{i + 1}%7C{la},{ln}"
        for i, (la, ln) in enumerate(points))

    # The real road where Directions can give us one, straight lines only as a
    # fallback. enc: keeps the URL short -- a route can run to hundreds of
    # coordinates, which as raw pairs would blow past the length a static map
    # request accepts.
    routed = fetch_route(points, api_key)
    if routed is not None:
        overview, legs = routed
        path = ("&path=color:0x0d0d82c0%7Cweight:6%7Cenc:"
                + quote(overview, safe=""))
    else:
        legs = None
        path = "&path=color:0x0d0d82c0%7Cweight:6%7C" + "%7C".join(
            f"{la},{ln}" for la, ln in points)

    url = (f"https://maps.googleapis.com/maps/api/staticmap"
           f"?size={req_w}x{req_h}&scale=2&maptype=roadmap"
           f"&center={centre_lat},{centre_lng}&zoom={zoom}"
           f"{markers}{path}&key={api_key}")
    try:
        resp = requests.get(url, timeout=15)
        if resp.status_code != 200 or "image" not in \
                (resp.headers.get("content-type") or ""):
            print(f"[MAP] {resp.status_code}: {resp.text[:120]}")
            return None
        raw_map = Image.open(io.BytesIO(resp.content)).convert("RGB")
    except Exception as e:
        print(f"[MAP] {e}")
        return None

    # Where each stop falls in the returned image, before it is scaled up.
    cx, cy = _mercator(centre_lat, centre_lng, zoom)
    half_w, half_h = raw_map.width / 2, raw_map.height / 2

    def to_pixel(la, ln):
        px, py = _mercator(la, ln, zoom)
        return ((px - cx) * 2 + half_w, (py - cy) * 2 + half_h)

    pixels = [to_pixel(la, ln) for la, ln in points]
    # The same projection applied to the road itself, so the car can be put on
    # the tarmac rather than on the straight line between two pins.
    leg_pixels = (
        [[to_pixel(la, ln) for la, ln in leg] for leg in legs]
        if legs else None)

    scale = width / raw_map.width
    scaled = raw_map.resize(
        (width, max(1, int(raw_map.height * scale))), Image.LANCZOS)

    # Static Maps caps a request at 640x640, so the map is square and the film
    # is 9:16 -- roughly 800px of the frame is neither map nor text. Filling it
    # with a blurred blow-up of the same map reads as a deliberate backdrop
    # where flat grey read as a rendering fault. Cropping the map to fill
    # instead would be simpler but can push a stop off frame, which is the one
    # thing this shot cannot do.
    cover = width / raw_map.height if raw_map.height else 1
    cover = max(cover, height / raw_map.height if raw_map.height else 1)
    backdrop = raw_map.resize(
        (max(1, int(raw_map.width * cover)), max(1, int(raw_map.height * cover))),
        Image.BILINEAR,
    ).filter(ImageFilter.GaussianBlur(28))
    canvas = Image.new("RGB", (width, height), (232, 234, 238))
    canvas.paste(backdrop, ((width - backdrop.width) // 2,
                            (height - backdrop.height) // 2))
    canvas = Image.blend(canvas, Image.new("RGB", (width, height),
                                           (18, 20, 44)), 0.35)

    top = (height - scaled.height) // 2
    canvas.paste(scaled, (0, top))

    def place(pt):
        return (pt[0] * scale, pt[1] * scale + top)

    pixels = [place(p) for p in pixels]
    if leg_pixels is not None:
        leg_pixels = [[place(p) for p in leg] for leg in leg_pixels]
    else:
        # No road geometry: each leg is the straight hop between two stops, so
        # the car still animates and the shot is unchanged from before.
        leg_pixels = [[pixels[i], pixels[i + 1]]
                      for i in range(len(pixels) - 1)]
    return canvas, pixels, leg_pixels


def render_car(base: Image.Image, pixels, roads, progress: float,
               day_number: int, heading: str = "") -> Image.Image:
    """The map with the car placed along the route at [progress].

    Travels leg by leg at a constant share of the journey per leg, so a day
    with three stops spends the same time on each hop rather than racing the
    short one.

    [heading] names the stop being driven to. The film cuts to that place's
    photos the moment the car lands on it, so the map has to say where it is
    going -- an unlabelled dot sliding between pins is movement without a
    destination, and the cut that follows then reads as a change of subject
    rather than an arrival.
    """
    frame = base.copy()
    draw = ImageDraw.Draw(frame)

    legs = max(1, len(roads))
    position = min(0.9999, max(0.0, progress)) * legs
    leg = min(int(position), legs - 1)
    within = position - leg

    # Along the road, not across the map. Walking the leg by distance rather
    # than by point index keeps the speed even: a polyline is dense through
    # bends and sparse on straights, so stepping point to point would make the
    # car crawl round corners and jump down open road.
    shape = roads[leg] if roads[leg] else [pixels[leg], pixels[leg + 1]]
    spans = [
        math.dist(shape[i], shape[i + 1]) for i in range(len(shape) - 1)]
    total = sum(spans) or 1.0
    target = total * within

    x, y = shape[-1]
    covered = 0.0
    walked = [shape[0]]
    for i, span in enumerate(spans):
        if covered + span >= target:
            t = (target - covered) / (span or 1.0)
            x = shape[i][0] + (shape[i + 1][0] - shape[i][0]) * t
            y = shape[i][1] + (shape[i + 1][1] - shape[i][1]) * t
            break
        covered += span
        walked.append(shape[i + 1])
    walked.append((x, y))

    # The road already travelled, drawn over the route so progress is visible:
    # every completed leg, then how far along this one the car has come.
    travelled = []
    for done in roads[:leg]:
        travelled.extend(done or [])
    travelled.extend(walked)
    if len(travelled) > 1:
        draw.line(travelled, fill=(214, 45, 32), width=9, joint="curve")

    x1, y1 = pixels[min(leg + 1, len(pixels) - 1)]

    # Arrival: a ring opening out of the pin over the last fifth of the leg.
    # Without it the car simply stops, and a cut away from a stationary dot
    # looks like the render gave up rather than like the journey got there.
    if within > 0.8:
        landed = (within - 0.8) / 0.2
        ring = int(30 + 46 * landed)
        fade = int(230 * (1 - landed))
        draw.ellipse([x1 - ring, y1 - ring, x1 + ring, y1 + ring],
                     outline=(214, 45, 32, fade), width=6)

    r = 26
    draw.ellipse([x - r, y - r, x + r, y + r], fill=(214, 45, 32),
                 outline=(255, 255, 255), width=5)
    draw.ellipse([x - 8, y - 8, x + 8, y + 8], fill=(255, 255, 255))

    draw.rectangle([0, 0, FILM_WIDTH, 96], fill=(13, 13, 130))
    draw.text((MARGIN, 30), f"DAY {day_number}  ·  ON THE ROAD",
              font=_font(30), fill=(255, 255, 255))

    if heading:
        band = FILM_HEIGHT - 150
        draw.rectangle([0, band, FILM_WIDTH, band + 150], fill=(13, 13, 130))
        # The band tracks the car. Holding "NEXT STOP" after it has landed
        # describes the wrong moment, and this is the frame the cut to the
        # photos happens on -- it should read as an arrival.
        arrived = within > 0.8 or legs == 0 or progress <= 0.0
        draw.text((MARGIN, band + 30),
                  "ARRIVING AT" if arrived else "NEXT STOP",
                  font=_font(24), fill=(150, 152, 220))
        name = heading if len(heading) <= 26 else heading[:25].rstrip() + "…"
        draw.text((MARGIN, band + 66), name,
                  font=_font(40, bold=True), fill=(255, 255, 255))
    return frame


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
                include_photos: bool = True,
                maps_key: str = "") -> List[Dict[str, Any]]:
    """The running order of shots, each with its own timing and camera move.

    Uniform timing is most of what makes an edit feel generated. A title needs
    to land, a day card is a signpost, an establishing shot wants room, and a
    second angle of the same place is a quick cut. The camera move rotates for
    the same reason -- every shot pushing in reads as mechanical long before
    any single move does.
    """
    shots: List[Dict[str, Any]] = [{
        "image": _fit_film(render_title(destination, days, include_photos)),
        "seconds": 4.0,
        "mode": 0,
    }]

    total = len(days)
    move = 0
    # The last stop of the previous day, so each day's route continues
    # from where the one before it finished.
    carried = None
    for i, day in enumerate(days):
        shots.append({
            "image": _fit_film(
                render_day(day, destination, i + 1, total, include_photos)),
            "seconds": 2.2,
            "mode": 1,
        })
        items = day.get("items", [])[:4]

        def photo_shots(item, day_index=i):
            """Every angle of one place, as consecutive shots."""
            nonlocal move
            out = []
            photos = [u for u in (item.get("photos") or []) if u]
            if not photos:
                photos = [item.get("photo", "")]
            for index, photo in enumerate(photos[:3]):
                shot = {**item, "photo": photo}
                # Name and blurb on the establishing shot only; under every
                # angle they stop introducing the place and start nagging.
                if index > 0:
                    shot["about"] = ""
                    shot["narration"] = ""
                base, overlay = render_place_layers(shot, day_index + 1,
                                                    include_photos)
                move = (move + 1) % 4
                out.append({
                    "image": base,
                    "overlay": overlay,
                    # The picture reads for a beat before the words arrive.
                    "overlay_from": 0.45 if index == 0 else 0.2,
                    "seconds": 3.2 if index == 0 else 1.8,
                    "mode": move,
                })
            return out

        # The day's route, cut so that driving and arriving alternate: the car
        # covers one leg, lands on a pin, and the film cuts straight to that
        # place's photos before setting off again.
        #
        # It used to drive the whole route in one 4s shot and only then show
        # the places, which left the two halves of a day unrelated -- the map
        # finished before the viewer had seen anywhere it went, so the photos
        # that followed could have been of any trip. Arrival is what ties a
        # picture to a point on the map.
        mapped = [it for it in items
                  if it.get("lat") is not None and it.get("lng") is not None]

        # Yesterday's last stop opens today's route, so the journey carries on
        # from where it stopped instead of teleporting to a fresh corner of the
        # map each morning. It gets no pin of its own and no photo shot -- it is
        # only there so the road into the day is drawn.
        lead_in = [carried] if carried is not None else []
        route_points = lead_in + [(it["lat"], it["lng"]) for it in mapped]

        drawn = None
        if maps_key and len(route_points) >= 2:
            drawn = fetch_day_map(route_points, maps_key)
        if mapped:
            carried = (mapped[-1]["lat"], mapped[-1]["lng"])

        if drawn is not None:
            base, pixels, roads = drawn
            # The lead-in occupies the first pin and the first leg, so today's
            # own stops start one along.
            offset = len(lead_in)
            legs = max(1, len(pixels) - 1)
            for stop, item in enumerate(mapped):
                stop += offset
                if stop == 0:
                    # The first pin is where the day starts, so there is no leg
                    # to drive. A short hold establishes the map instead.
                    span = (0.0, 0.0)
                    seconds = 1.4
                else:
                    span = ((stop - 1) / legs, stop / legs)
                    seconds = 1.8
                shots.append({
                    "image": base,
                    "seconds": seconds,
                    # Animated per frame rather than panned: the movement is
                    # the car, not the camera.
                    "animate": (
                        lambda p, b=base, px=pixels, rd=roads, d=i + 1, s=span,
                        h=str(item.get("title") or item.get("name") or ""):
                        render_car(b, px, rd,
                                   s[0] + (s[1] - s[0]) * _ease(p), d, h)
                    ),
                })
                shots.extend(photo_shots(item))
            # Anything Google could not place still belongs to the day; it just
            # cannot be driven to. Compared by identity, not value: two stops
            # can hold equal dicts, and `in` would then drop the second.
            placed = {id(it) for it in mapped}
            for item in items[:3]:
                if id(item) not in placed:
                    shots.extend(photo_shots(item))
        else:
            for item in items[:3]:
                shots.extend(photo_shots(item))
    shots.append({
        "image": _fit_film(render_closing(destination)),
        "seconds": 3.4,
        "mode": 1,
    })
    return shots


def render_day_map(day: Dict[str, Any], destination: str, day_number: int,
                   maps_key: str) -> Optional[Image.Image]:
    """A day's route as its own page: the map, then a numbered key.

    Its own page rather than a strip on the day card, because that card is
    already dense -- it can run to within 260px of the foot before the running
    order is even placed, so a map squeezed in would be the first thing
    dropped. A PDF page costs nothing and a full-width map is the version
    somebody can actually navigate by.
    """
    items = [it for it in day.get("items", [])[:4]
             if it.get("lat") is not None and it.get("lng") is not None]
    if not maps_key or len(items) < 2:
        return None

    # Square, so nothing is cropped: fetch_day_map letterboxes to the size it
    # is given, and asking for a 4:5 page would paste a 1080-tall map into a
    # shorter box and clip the stops nearest the top and bottom edges.
    drawn = fetch_day_map([(it["lat"], it["lng"]) for it in items], maps_key,
                          size=(WIDTH, WIDTH))
    if drawn is None:
        return None
    board = drawn[0].resize((860, 860), Image.LANCZOS)

    canvas = Image.new("RGB", (WIDTH, HEIGHT), PAPER)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([0, 0, WIDTH, 230], fill=ACCENT)
    draw.text((MARGIN, 54), "YOUR ROUTE", font=_font(30),
              fill=(255, 255, 255))
    draw.text((MARGIN, 100), f"Day {day_number}", font=_font(64, bold=True),
              fill=(255, 255, 255))

    canvas.paste(board, ((WIDTH - board.width) // 2, 252))

    y = 252 + board.height + 26
    for n, item in enumerate(items):
        if y > HEIGHT - 46:
            break
        label = f"{n + 1}.  {str(item.get('title', ''))[:46]}"
        draw.text((MARGIN, y), label, font=_font(26), fill=INK)
        y += 36
    return canvas


def render_days(days: List[Dict[str, Any]], destination: str,
                include_photos: bool = True,
                maps_key: str = "") -> List[Image.Image]:
    """The PDF: each day's card, followed by its route map where we have one."""
    total = len(days)
    pages: List[Image.Image] = []
    for i, day in enumerate(days):
        pages.append(render_day(day, destination, i + 1, total,
                                include_photos))
        route = render_day_map(day, destination, i + 1, maps_key)
        if route is not None:
            pages.append(route)
    return pages


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


def _ease(t: float) -> float:
    """Smoothstep: starts and stops gently instead of snapping into motion."""
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def _kenburns(image: Image.Image, progress: float, mode: int,
              size) -> Image.Image:
    """One frame of a slow camera move across [image].

    Four moves, chosen by shot index. Every shot pushing in is what makes a
    sequence feel mechanical -- the eye notices the repetition long before it
    notices any single move.
    """
    out_w, out_h = size
    eased = _ease(progress)
    zoom_span = 0.12

    if mode == 0:      # push in
        zoom = 1.0 + zoom_span * eased
        cx, cy = 0.5, 0.5
    elif mode == 1:    # pull out
        zoom = 1.0 + zoom_span * (1 - eased)
        cx, cy = 0.5, 0.5
    elif mode == 2:    # drift left to right
        zoom = 1.0 + zoom_span * 0.6
        cx, cy = 0.36 + 0.28 * eased, 0.5
    else:              # drift up, slight push
        zoom = 1.0 + zoom_span * (0.3 + 0.5 * eased)
        cx, cy = 0.5, 0.62 - 0.22 * eased

    crop_w = image.width / zoom
    crop_h = image.height / zoom
    left = max(0, min(image.width - crop_w, cx * image.width - crop_w / 2))
    top = max(0, min(image.height - crop_h, cy * image.height - crop_h / 2))
    frame = image.crop((int(left), int(top),
                        int(left + crop_w), int(top + crop_h)))
    # BILINEAR, not LANCZOS. This runs once per frame -- 25 times a second of
    # film -- and nobody pauses a moving shot to inspect it. LANCZOS roughly
    # doubled the render time for a difference invisible in motion.
    return frame.resize((out_w, out_h), Image.BILINEAR)


def build_video(shots, seconds_per_day: float = 3.0,
                music_path: Optional[str] = None,
                on_progress=None) -> bytes:
    """The film, rendered frame by frame and piped straight into ffmpeg.

    [on_progress] is called as `on_progress(done, total)` once per shot, so a
    caller can report a moving figure across a render that takes minutes. Shots
    rather than frames: a frame callback would fire twenty-five times a second
    for no extra information.

    [shots] may be plain images -- the old shape -- or dicts carrying their own
    duration, camera move and text overlay. Frames are generated here rather
    than handed to an ffmpeg filter because that is what buys per-shot timing,
    a different move on each shot, and text that arrives after its picture.
    None of those are expressible as one filter chain over a fixed image
    sequence.

    Raw frames go over a pipe rather than through PNGs on disk: a 30 second
    film is 750 frames, and writing them out costs more than rendering them.

    [music_path] is mixed in when given. Nothing ships with the app -- the
    file has to be one you are licensed to redistribute, since the video is
    made to be shared.
    """
    if not shots:
        return b""

    import subprocess
    import imageio_ffmpeg

    normalised = []
    for i, shot in enumerate(shots):
        if isinstance(shot, dict):
            normalised.append({
                "image": shot["image"],
                "seconds": float(shot.get("seconds", seconds_per_day)),
                "mode": int(shot.get("mode", i % 4)),
                "overlay": shot.get("overlay"),
                "overlay_from": float(shot.get("overlay_from", 0.0)),
                # A shot that draws itself each frame, for the map: the
                # movement belongs to the car rather than the camera.
                "animate": shot.get("animate"),
            })
        else:
            normalised.append({"image": shot, "seconds": seconds_per_day,
                               "mode": i % 4, "overlay": None,
                               "overlay_from": 0.0, "animate": None})

    fps = 25
    width, height = normalised[0]["image"].size
    total_seconds = sum(s["seconds"] for s in normalised)

    exe = imageio_ffmpeg.get_ffmpeg_exe()
    cmd = [
        exe, "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24",
        "-s", f"{width}x{height}", "-r", str(fps), "-i", "-",
    ]
    if music_path and os.path.exists(music_path):
        cmd += ["-i", music_path, "-c:a", "aac", "-b:a", "160k",
                "-shortest", "-af",
                f"afade=t=out:st={max(0.0, total_seconds - 2):.2f}:d=2"]
    # Frames go in over a pipe, but the file comes out on disk: MP4 writes
    # its header last and then seeks back to move it, which a pipe cannot do.
    # Piping the output produced "Invalid argument" mid-write as ffmpeg gave
    # up and closed the input.
    workdir = tempfile.mkdtemp(prefix="triplix_film_")
    out_path = os.path.join(workdir, "trip.mp4")
    cmd += [
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        out_path,
    ]

    # stderr goes to a file, not a pipe. ffmpeg is chatty, and an unread
    # stderr pipe fills, blocks ffmpeg, and deadlocks against us still writing
    # frames into stdin -- the render simply hangs with no error anywhere.
    log_path = os.path.join(workdir, "ffmpeg.log")
    log = open(log_path, "wb")
    process = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                               stdout=subprocess.DEVNULL,
                               stderr=log)
    try:
        elapsed = 0.0
        for shot_index, shot in enumerate(normalised):
            if on_progress:
                # Guarded: a caller whose progress sink has gone away must not
                # take the render down with it.
                try:
                    on_progress(shot_index, len(normalised))
                except Exception:
                    pass
            frames = max(1, int(fps * shot["seconds"]))
            base = shot["image"]
            for f in range(frames):
                progress = f / max(1, frames - 1)
                animate = shot.get("animate")
                frame = animate(progress) if animate else _kenburns(
                    base, progress, shot["mode"], (width, height))

                # The picture lands first and the words follow. Painted into
                # frame one they appear the instant the shot cuts, which reads
                # as a caption rather than a title.
                overlay = shot.get("overlay")
                if overlay is not None:
                    delay = shot["overlay_from"]
                    t = (f / fps) - delay
                    if t > 0:
                        alpha = min(1.0, t / 0.5)
                        if alpha >= 1.0:
                            frame = Image.alpha_composite(
                                frame.convert("RGBA"), overlay).convert("RGB")
                        else:
                            faded = overlay.copy()
                            faded.putalpha(
                                faded.getchannel("A").point(
                                    lambda v, a=alpha: int(v * a)))
                            frame = Image.alpha_composite(
                                frame.convert("RGBA"), faded).convert("RGB")

                # A fade at each end, so it opens and closes rather than
                # starting and stopping.
                now = elapsed + f / fps
                fade = 1.0
                if now < 0.7:
                    fade = now / 0.7
                elif now > total_seconds - 0.9:
                    fade = max(0.0, (total_seconds - now) / 0.9)
                if fade < 1.0:
                    frame = Image.blend(
                        Image.new("RGB", frame.size, (0, 0, 0)), frame, fade)

                process.stdin.write(frame.tobytes())
            elapsed += shot["seconds"]

        process.stdin.close()
        process.wait(timeout=300)
        log.close()
        if process.returncode != 0 or not os.path.exists(out_path):
            with open(log_path, "rb") as fh:
                tail = fh.read()[-400:].decode("utf-8", "replace")
            raise RuntimeError(tail)
        with open(out_path, "rb") as fh:
            return fh.read()
    finally:
        try:
            if process.stdin and not process.stdin.closed:
                process.stdin.close()
        except Exception:
            pass
        try:
            if not log.closed:
                log.close()
        except Exception:
            pass
        try:
            for name in os.listdir(workdir):
                os.remove(os.path.join(workdir, name))
            os.rmdir(workdir)
        except Exception:
            pass
