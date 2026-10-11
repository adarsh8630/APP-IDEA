#!/usr/bin/env python3
"""Collect 365 existing, distinct, licensed 4K Christian photographs from Unsplash.

No image is synthesized. Each record points to a real photographer, source page,
license, original dimensions, and a 4K download URL. A smaller derivative is
bundled only so the mobile UI loads quickly.
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import io
import json
import pathlib
import time
from typing import Any
from urllib.parse import urlencode

import requests
from PIL import Image, ImageOps

SEARCH_API = "https://unsplash.com/napi/search/photos"
OUT = pathlib.Path(__file__).resolve().parents[1] / "assets" / "wallpapers"
COUNT = 365
PREVIEW_SIZE = (720, 1280)
USER_AGENT = "Scripture365/1.1 (+https://github.com/adarsh8630/APP-IDEA)"
LICENSE_URL = "https://unsplash.com/license"

# Focused searches keep every result connected to Christ, Scripture, Christian
# worship or recognisably Christian sacred spaces and symbols.
QUERIES = [
    "Jesus Christ", "Jesus cross", "Jesus statue", "Jesus church",
    "Christ crucifix", "Christ statue", "Christian cross", "cross sunrise",
    "cross sunset", "cross mountain", "cross church", "wooden cross",
    "Bible", "open Bible", "Bible study", "Bible prayer", "Bible church",
    "Christian prayer", "praying Christian", "Christian worship",
    "church worship", "church prayer", "church altar", "church candles",
    "church stained glass", "Christian stained glass", "cathedral cross",
    "cathedral altar", "chapel cross", "chapel prayer", "Christian baptism",
    "Christian communion", "Christian rosary", "Christian faith",
    "Christian hope", "Christian Easter", "Christian Christmas",
    "Christian pilgrimage", "Christian monastery", "Christian holy land",
    "Jerusalem Christian", "Bethlehem church", "Sea of Galilee Bible",
    "Christian scripture", "Christian devotional", "Christian ministry",
    "Christian church interior", "Christian church exterior",
]

session = requests.Session()
session.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})


def with_params(base: str, **params: Any) -> str:
    joiner = "&" if "?" in base else "?"
    return base + joiner + urlencode(params)


def search_candidates() -> list[dict[str, Any]]:
    selected: dict[str, dict[str, Any]] = {}
    for query in QUERIES:
        for page in range(1, 6):
            response = session.get(
                SEARCH_API,
                params={"query": query, "page": page, "per_page": 30},
                timeout=45,
            )
            response.raise_for_status()
            payload = response.json()
            results = payload.get("results", [])
            if not results:
                break
            for photo in results:
                width = int(photo.get("width") or 0)
                height = int(photo.get("height") or 0)
                if max(width, height) < 3840 or min(width, height) < 2160:
                    continue
                photo_id = str(photo.get("id") or "")
                raw_url = (photo.get("urls") or {}).get("raw")
                page_url = (photo.get("links") or {}).get("html")
                user = photo.get("user") or {}
                if not photo_id or not raw_url or not page_url:
                    continue
                selected.setdefault(photo_id, {
                    "sourceId": photo_id,
                    "title": photo.get("description") or photo.get("alt_description") or query,
                    "creator": user.get("name") or "Unsplash photographer",
                    "creatorUrl": (user.get("links") or {}).get("html") or "",
                    "license": "Unsplash License",
                    "licenseUrl": LICENSE_URL,
                    "sourceUrl": page_url,
                    "originalUrl": raw_url,
                    "originalWidth": width,
                    "originalHeight": height,
                    "searchTheme": query,
                    # Exact portrait 4K derivative of the existing photograph.
                    "download4kUrl": with_params(
                        raw_url, w=2160, h=3840, fit="crop", crop="faces,entropy",
                        fm="jpg", q=92,
                    ),
                    "previewUrl": with_params(
                        raw_url, w=PREVIEW_SIZE[0], h=PREVIEW_SIZE[1],
                        fit="crop", crop="faces,entropy", fm="webp", q=76,
                    ),
                })
            if len(selected) >= COUNT * 2:
                return list(selected.values())
            if page >= int(payload.get("total_pages") or page):
                break
            time.sleep(0.12)
    if len(selected) < COUNT:
        raise RuntimeError(f"Only {len(selected)} distinct qualifying 4K photographs found; need {COUNT}")
    return list(selected.values())


def fetch_preview(candidate: dict[str, Any]) -> tuple[dict[str, Any], bytes, str]:
    response = session.get(candidate["previewUrl"], timeout=90)
    response.raise_for_status()
    payload = response.content
    digest = hashlib.sha256(payload).hexdigest()
    # Verify the response is truly an image and normalize metadata without
    # changing the artwork.
    with Image.open(io.BytesIO(payload)) as image:
        normalized = ImageOps.exif_transpose(image).convert("RGB")
        if normalized.size != PREVIEW_SIZE:
            normalized = ImageOps.fit(normalized, PREVIEW_SIZE, Image.Resampling.LANCZOS)
        output = io.BytesIO()
        normalized.save(output, "WEBP", quality=76, method=6)
    return candidate, output.getvalue(), digest


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for path in OUT.glob("day_*.webp"):
        path.unlink()

    candidates = search_candidates()
    records: list[dict[str, Any]] = []
    seen_previews: set[str] = set()

    # Keep deterministic day assignment even though downloads happen in parallel.
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        fetched = list(pool.map(fetch_preview, candidates[: COUNT + 80]))

    for candidate, preview, digest in fetched:
        if digest in seen_previews:
            continue
        seen_previews.add(digest)
        day = len(records) + 1
        filename = f"day_{day:03d}.webp"
        (OUT / filename).write_bytes(preview)
        records.append({
            "day": day,
            "file": filename,
            "source": "Unsplash",
            "sourceId": candidate["sourceId"],
            "title": candidate["title"],
            "creator": candidate["creator"],
            "creatorUrl": candidate["creatorUrl"],
            "license": candidate["license"],
            "licenseUrl": candidate["licenseUrl"],
            "sourceUrl": candidate["sourceUrl"],
            "originalUrl": candidate["originalUrl"],
            "download4kUrl": candidate["download4kUrl"],
            "originalWidth": candidate["originalWidth"],
            "originalHeight": candidate["originalHeight"],
            "searchTheme": candidate["searchTheme"],
            "previewSha256": digest,
        })
        print(f"{day:03d}/{COUNT}: {candidate['creator']} — {candidate['searchTheme']}")
        if day == COUNT:
            break

    if len(records) != COUNT:
        raise RuntimeError(f"Collected {len(records)} unique wallpapers; expected {COUNT}")

    manifest = {
        "source": "Unsplash",
        "licenseUrl": LICENSE_URL,
        "policy": "365 existing internet photographs. Every source ID and preview is distinct, every original is 4K-qualified, and no artwork is AI-generated.",
        "previewWidth": PREVIEW_SIZE[0],
        "previewHeight": PREVIEW_SIZE[1],
        "downloadWidth": 2160,
        "downloadHeight": 3840,
        "count": COUNT,
        "wallpapers": records,
    }
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    )
    assert len({item["sourceId"] for item in records}) == COUNT
    assert len({item["previewSha256"] for item in records}) == COUNT
    assert all(
        max(item["originalWidth"], item["originalHeight"]) >= 3840
        and min(item["originalWidth"], item["originalHeight"]) >= 2160
        for item in records
    )
    print(f"Collected {COUNT} distinct licensed 4K sources; no synthetic images.")


if __name__ == "__main__":
    main()
