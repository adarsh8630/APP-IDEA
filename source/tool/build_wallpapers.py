#!/usr/bin/env python3
"""Build 365 distinct, licensed Christian wallpapers from Wikimedia Commons."""

from __future__ import annotations

import concurrent.futures
import hashlib
import html
import io
import json
import os
import pathlib
import re
import time
from typing import Any

import requests
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

API = "https://commons.wikimedia.org/w/api.php"
OUT = pathlib.Path(__file__).resolve().parents[1] / "assets" / "wallpapers"
COUNT = 365
SIZE = (720, 1280)
USER_AGENT = "Scripture365WallpaperBuilder/1.0 (https://github.com/adarsh8630/APP-IDEA)"

# The mix is intentionally broader than paintings of Jesus alone: the brief calls
# for Christ-centred imagery plus wider Christian faith, worship and sacred art.
QUERIES = [
    "Jesus Christ painting", "Jesus Christ icon", "Jesus Christ mosaic",
    "Jesus Christ stained glass", "Christ Pantocrator", "Sacred Heart Jesus",
    "Jesus Good Shepherd art", "Jesus teaching painting", "Jesus praying art",
    "Jesus and disciples painting", "Jesus miracle painting", "Sermon on the Mount art",
    "Nativity of Jesus painting", "Adoration of the Magi art", "Baptism of Jesus art",
    "Transfiguration of Jesus art", "Last Supper painting", "Crucifixion of Jesus art",
    "Resurrection of Jesus painting", "Ascension of Jesus art", "Jesus church fresco",
    "Christian cross landscape", "Christian cross church", "Bible still life",
    "open Bible church", "Christian prayer art", "Christian worship church",
    "Christian stained glass", "Christian sacred art", "Christian church interior",
    "Christian cathedral interior", "Christian chapel altar", "Christian monastery",
    "Christian pilgrimage", "Christian baptism art", "Christian communion art",
    "Virgin Mary and Jesus art", "Madonna and Child painting", "Holy Family painting",
    "Christian angels painting", "Christian saints painting", "Christian icon art",
    "Christian faith painting", "Christian hope art", "Christian charity art",
]

session = requests.Session()
session.headers["User-Agent"] = USER_AGENT


def plain(value: str | None) -> str:
    text = re.sub(r"<[^>]+>", " ", value or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def metadata_value(meta: dict[str, Any], key: str) -> str:
    value = meta.get(key, {})
    return plain(value.get("value") if isinstance(value, dict) else str(value))


def acceptable_license(meta: dict[str, Any]) -> bool:
    license_name = metadata_value(meta, "LicenseShortName").lower()
    usage = metadata_value(meta, "UsageTerms").lower()
    combined = f"{license_name} {usage}"
    permitted = ("public domain", "cc0", "cc by", "creative commons attribution")
    blocked = ("noncommercial", "no derivatives", "fair use", "copyrighted")
    return any(item in combined for item in permitted) and not any(item in combined for item in blocked)


def search_candidates() -> list[dict[str, Any]]:
    chosen: dict[int, dict[str, Any]] = {}
    for query in QUERIES:
        params = {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "generator": "search",
            "gsrsearch": f"{query} filetype:bitmap",
            "gsrnamespace": "6",
            "gsrlimit": "50",
            "prop": "imageinfo",
            "iiprop": "url|mime|extmetadata",
            "iiurlwidth": str(SIZE[0]),
        }
        response = session.get(API, params=params, timeout=45)
        response.raise_for_status()
        for page in response.json().get("query", {}).get("pages", []):
            info_items = page.get("imageinfo") or []
            if not info_items:
                continue
            info = info_items[0]
            if info.get("mime") not in {"image/jpeg", "image/png", "image/webp"}:
                continue
            meta = info.get("extmetadata") or {}
            if not acceptable_license(meta):
                continue
            page_id = int(page["pageid"])
            chosen.setdefault(page_id, {
                "pageId": page_id,
                "title": page.get("title", ""),
                "imageUrl": info.get("thumburl") or info.get("url"),
                "originalUrl": info.get("url"),
                "sourceUrl": info.get("descriptionurl") or f"https://commons.wikimedia.org/?curid={page_id}",
                "creator": metadata_value(meta, "Artist") or metadata_value(meta, "Credit") or "Wikimedia Commons contributor",
                "license": metadata_value(meta, "LicenseShortName") or metadata_value(meta, "UsageTerms"),
                "licenseUrl": metadata_value(meta, "LicenseUrl"),
                "description": metadata_value(meta, "ImageDescription"),
                "query": query,
            })
        if len(chosen) >= COUNT * 2:
            break
        time.sleep(0.08)
    if len(chosen) < COUNT:
        raise RuntimeError(f"Only {len(chosen)} licensed distinct source pages found; need {COUNT}")
    return list(chosen.values())


def render(candidate: dict[str, Any]) -> tuple[dict[str, Any], bytes, str]:
    response = session.get(candidate["imageUrl"], timeout=90)
    response.raise_for_status()
    raw = response.content
    digest = hashlib.sha256(raw).hexdigest()
    with Image.open(io.BytesIO(raw)) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
        image = ImageOps.fit(image, SIZE, method=Image.Resampling.LANCZOS, centering=(0.5, 0.45))
        # Gentle treatment keeps overlaid Scripture readable without hiding the art.
        image = ImageEnhance.Color(image).enhance(0.9)
        image = ImageEnhance.Contrast(image).enhance(1.02)
        image = image.filter(ImageFilter.GaussianBlur(radius=0.15))
        buffer = io.BytesIO()
        image.save(buffer, "WEBP", quality=74, method=6)
    return candidate, buffer.getvalue(), digest


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # Remove only previously generated daily files; preserve the legacy set for
    # repository history and as a development fallback.
    for path in OUT.glob("day_*.webp"):
        path.unlink()

    candidates = search_candidates()
    records: list[dict[str, Any]] = []
    seen_downloads: set[str] = set()
    next_day = 1

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(render, item) for item in candidates]
        for future in concurrent.futures.as_completed(futures):
            if next_day > COUNT:
                break
            try:
                candidate, payload, digest = future.result()
            except Exception as exc:
                print(f"Skipping failed image: {exc}")
                continue
            if digest in seen_downloads:
                continue
            seen_downloads.add(digest)
            filename = f"day_{next_day:03d}.webp"
            (OUT / filename).write_bytes(payload)
            record = {
                "day": next_day,
                "file": filename,
                "title": candidate["title"],
                "creator": candidate["creator"],
                "license": candidate["license"],
                "licenseUrl": candidate["licenseUrl"],
                "sourceUrl": candidate["sourceUrl"],
                "originalUrl": candidate["originalUrl"],
                "searchTheme": candidate["query"],
                "sourceSha256": digest,
            }
            records.append(record)
            print(f"{next_day:03d}/{COUNT}: {candidate['title']}")
            next_day += 1

    if len(records) != COUNT:
        raise RuntimeError(f"Generated {len(records)} unique wallpapers; expected {COUNT}")

    manifest = {
        "generatedFrom": "Wikimedia Commons",
        "policy": "One different source page and source binary per day; public domain or Creative Commons only.",
        "width": SIZE[0],
        "height": SIZE[1],
        "count": len(records),
        "wallpapers": records,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    assert len({item["sourceUrl"] for item in records}) == COUNT
    assert len({item["sourceSha256"] for item in records}) == COUNT
    print(f"Built and attributed {COUNT} distinct wallpapers in {OUT}")


if __name__ == "__main__":
    main()
