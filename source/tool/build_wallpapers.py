#!/usr/bin/env python3
"""Collect 365 existing, distinct, open-license 4K Christian images.

Search metadata comes from Openverse. The image itself stays tied to its original
internet host and source page. Nothing is AI-generated. Each item records creator,
license, source, original dimensions, and the untouched 4K image URL.
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import io
import json
import pathlib
import time
from typing import Any

import requests
from PIL import Image, ImageOps

SEARCH_API = "https://api.openverse.org/v1/images/"
OUT = pathlib.Path(__file__).resolve().parents[1] / "assets" / "wallpapers"
COUNT = 365
PREVIEW_SIZE = (720, 1280)
USER_AGENT = "Scripture365/1.2 (+https://github.com/adarsh8630/APP-IDEA)"
OPEN_LICENSES = {"cc0", "pdm", "by", "by-sa"}

QUERIES = [
    "Jesus Christ", "Jesus cross", "Jesus church", "Christ crucifix",
    "Christ statue", "Christian cross", "cross sunrise", "cross sunset",
    "cross mountain", "cross church", "wooden cross Christianity", "Holy Bible",
    "open Bible", "Bible study Christian", "Bible prayer", "Christian prayer",
    "Christian worship", "church worship", "church prayer", "church altar",
    "church candles", "church stained glass", "Christian stained glass",
    "cathedral cross", "cathedral altar", "chapel cross", "Christian baptism",
    "Christian communion", "Christian rosary", "Christian faith", "Christian hope",
    "Christian Easter", "Christian Christmas", "Christian pilgrimage",
    "Christian monastery", "Christian Holy Land", "Jerusalem Christian",
    "Bethlehem church", "Sea of Galilee Bible", "Christian scripture",
    "Christian devotional", "Christian church interior", "Christian sacred art",
    "Jesus painting", "Jesus icon", "Jesus mosaic", "Jesus stained glass",
    "resurrection of Jesus art", "nativity of Jesus art", "Last Supper art",
]

session = requests.Session()
session.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})


def is_usable(item: dict[str, Any]) -> bool:
    width = int(item.get("width") or 0)
    height = int(item.get("height") or 0)
    license_name = str(item.get("license") or "").lower()
    url = str(item.get("url") or "")
    landing = str(item.get("foreign_landing_url") or "")
    if max(width, height) < 3840 or min(width, height) < 2160:
        return False
    if license_name not in OPEN_LICENSES or not url.startswith("https://"):
        return False
    if not landing.startswith("http"):
        return False
    lowered = " ".join([
        str(item.get("title") or ""), str(item.get("tags") or ""),
        str(item.get("attribution") or ""),
    ]).lower()
    blocked = (" ai generated", "ai-generated", "midjourney", "stable diffusion")
    return not any(word in lowered for word in blocked)


def search_candidates() -> list[dict[str, Any]]:
    selected: dict[str, dict[str, Any]] = {}
    for query in QUERIES:
        for page in range(1, 4):
            response = session.get(
                SEARCH_API,
                params={
                    "q": query,
                    "page": page,
                    "page_size": 80,
                    "license": ",".join(sorted(OPEN_LICENSES)),
                    "mature": "false",
                },
                timeout=60,
            )
            response.raise_for_status()
            payload = response.json()
            results = payload.get("results", [])
            if not results:
                break
            for item in results:
                if not is_usable(item):
                    continue
                source_id = f"{item.get('source', 'internet')}:{item.get('id', '')}"
                if source_id.endswith(":"):
                    continue
                selected.setdefault(source_id, {
                    "sourceId": source_id,
                    "source": item.get("source") or item.get("provider") or "Openverse",
                    "title": item.get("title") or query,
                    "creator": item.get("creator") or "Unknown creator",
                    "creatorUrl": item.get("creator_url") or "",
                    "license": str(item.get("license") or "").upper(),
                    "licenseUrl": item.get("license_url") or "",
                    "sourceUrl": item.get("foreign_landing_url") or "",
                    "originalUrl": item.get("url") or "",
                    "download4kUrl": item.get("url") or "",
                    "previewUrl": item.get("thumbnail") or item.get("url") or "",
                    "originalWidth": int(item.get("width") or 0),
                    "originalHeight": int(item.get("height") or 0),
                    "searchTheme": query,
                })
            if len(selected) >= COUNT + 180:
                return list(selected.values())
            if page >= int(payload.get("page_count") or page):
                break
            time.sleep(0.35)
    if len(selected) < COUNT:
        raise RuntimeError(f"Only {len(selected)} distinct qualifying 4K images found; need {COUNT}")
    return list(selected.values())


def fetch_preview(candidate: dict[str, Any]) -> tuple[dict[str, Any], bytes, str] | None:
    try:
        response = session.get(candidate["previewUrl"], timeout=60)
        response.raise_for_status()
        payload = response.content
        if len(payload) < 5000:
            return None
        with Image.open(io.BytesIO(payload)) as source:
            image = ImageOps.exif_transpose(source).convert("RGB")
            image = ImageOps.fit(image, PREVIEW_SIZE, Image.Resampling.LANCZOS)
            output = io.BytesIO()
            image.save(output, "WEBP", quality=76, method=6)
        preview = output.getvalue()
        return candidate, preview, hashlib.sha256(preview).hexdigest()
    except Exception as exc:
        print(f"Skipping unreachable preview: {candidate['sourceId']} ({exc})")
        return None


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for path in OUT.glob("day_*.webp"):
        path.unlink()

    candidates = search_candidates()
    records: list[dict[str, Any]] = []
    seen_previews: set[str] = set()

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        fetched = pool.map(fetch_preview, candidates)

        for result in fetched:
            if result is None:
                continue
            candidate, preview, digest = result
            if digest in seen_previews:
                continue
            seen_previews.add(digest)
            day = len(records) + 1
            filename = f"day_{day:03d}.webp"
            (OUT / filename).write_bytes(preview)
            records.append({
                "day": day,
                "file": filename,
                **candidate,
                "previewSha256": digest,
            })
            print(f"{day:03d}/{COUNT}: {candidate['source']} — {candidate['title']}")
            if day == COUNT:
                break

    if len(records) != COUNT:
        raise RuntimeError(f"Collected {len(records)} unique reachable wallpapers; expected {COUNT}")

    manifest = {
        "catalog": "Openverse",
        "policy": "365 existing internet images. Every source ID and preview is distinct, every original is 4K-qualified, licenses are CC0/PDM/CC BY/CC BY-SA, and no artwork is AI-generated.",
        "previewWidth": PREVIEW_SIZE[0],
        "previewHeight": PREVIEW_SIZE[1],
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
