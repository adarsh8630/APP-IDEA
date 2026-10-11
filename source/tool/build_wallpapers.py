#!/usr/bin/env python3
"""Collect 365 existing, distinct, open-license 4K Christian images.

The files come from Wikimedia Commons source pages. Nothing is AI-generated.
Every item records creator, license, source, original dimensions and original URL.
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import html
import io
import json
import pathlib
import re
import time
from typing import Any

import requests
from PIL import Image, ImageOps

API = "https://commons.wikimedia.org/w/api.php"
OUT = pathlib.Path(__file__).resolve().parents[1] / "assets" / "wallpapers"
COUNT = 365
PREVIEW_SIZE = (720, 1280)
USER_AGENT = "Scripture365/1.3 (+https://github.com/adarsh8630/APP-IDEA)"

QUERIES = [
    "Jesus Christ painting", "Jesus Christ icon", "Jesus Christ mosaic",
    "Jesus Christ stained glass", "Christ Pantocrator", "Sacred Heart Jesus",
    "Jesus Good Shepherd art", "Jesus teaching painting", "Jesus praying art",
    "Jesus disciples painting", "Jesus miracle painting", "Sermon Mount art",
    "Nativity Jesus painting", "Adoration Magi art", "Baptism Jesus art",
    "Transfiguration Jesus art", "Last Supper painting", "Crucifixion Jesus art",
    "Resurrection Jesus painting", "Ascension Jesus art", "Jesus church fresco",
    "Christian cross landscape", "Christian cross church", "Bible still life",
    "open Bible church", "Christian prayer art", "Christian worship church",
    "Christian stained glass", "Christian sacred art", "Christian church interior",
    "Christian cathedral interior", "Christian chapel altar", "Christian monastery",
    "Christian pilgrimage", "Christian baptism art", "Christian communion art",
    "Virgin Mary Jesus art", "Madonna Child painting", "Holy Family painting",
    "Christian angels painting", "Christian saints painting", "Christian icon art",
    "Christian faith painting", "Christian hope art", "Christian charity art",
    "Orthodox Christian icon", "Catholic sacred art", "Protestant church cross",
    "Biblical landscape", "Holy Land Christian", "Jerusalem church",
]

session = requests.Session()
session.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})


def plain(value: str | None) -> str:
    text = re.sub(r"<[^>]+>", " ", value or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def meta_value(meta: dict[str, Any], key: str) -> str:
    value = meta.get(key, {})
    return plain(value.get("value") if isinstance(value, dict) else str(value))


def acceptable(meta: dict[str, Any], title: str) -> bool:
    license_text = (
        meta_value(meta, "LicenseShortName") + " " + meta_value(meta, "UsageTerms")
    ).lower()
    permitted = ("public domain", "cc0", "cc by", "creative commons attribution")
    blocked_license = ("noncommercial", "no derivatives", "fair use", "copyrighted")
    description = (title + " " + meta_value(meta, "ImageDescription")).lower()
    blocked_art = ("ai-generated", "ai generated", "midjourney", "stable diffusion")
    return (
        any(term in license_text for term in permitted)
        and not any(term in license_text for term in blocked_license)
        and not any(term in description for term in blocked_art)
    )


def search_candidates() -> list[dict[str, Any]]:
    selected: dict[str, dict[str, Any]] = {}
    original_hashes: set[str] = set()
    for query in QUERIES:
        offset = 0
        added_for_query = 0
        for _ in range(4):
            params = {
                "action": "query",
                "format": "json",
                "formatversion": "2",
                "generator": "search",
                "gsrsearch": f"{query} filetype:bitmap",
                "gsrnamespace": "6",
                "gsrlimit": "50",
                "gsroffset": str(offset),
                "prop": "imageinfo",
                "iiprop": "url|mime|size|sha1|extmetadata",
                "iiurlwidth": "1280",
            }
            response = session.get(API, params=params, timeout=60)
            response.raise_for_status()
            payload = response.json()
            pages = payload.get("query", {}).get("pages", [])
            if not pages:
                break
            for page in pages:
                info_list = page.get("imageinfo") or []
                if not info_list:
                    continue
                info = info_list[0]
                width = int(info.get("width") or 0)
                height = int(info.get("height") or 0)
                source_hash = str(info.get("sha1") or "")
                meta = info.get("extmetadata") or {}
                title = str(page.get("title") or "")
                if info.get("mime") not in {"image/jpeg", "image/png", "image/webp"}:
                    continue
                if max(width, height) < 3840 or min(width, height) < 2160:
                    continue
                if not source_hash or source_hash in original_hashes or not acceptable(meta, title):
                    continue
                page_id = int(page["pageid"])
                original_hashes.add(source_hash)
                selected[str(page_id)] = {
                    "sourceId": f"commons:{page_id}",
                    "source": "Wikimedia Commons",
                    "title": title.removeprefix("File:"),
                    "creator": meta_value(meta, "Artist") or meta_value(meta, "Credit") or "Wikimedia Commons contributor",
                    "creatorUrl": "",
                    "license": meta_value(meta, "LicenseShortName") or meta_value(meta, "UsageTerms"),
                    "licenseUrl": meta_value(meta, "LicenseUrl"),
                    "sourceUrl": info.get("descriptionurl") or f"https://commons.wikimedia.org/?curid={page_id}",
                    "originalUrl": info.get("url") or "",
                    "download4kUrl": info.get("url") or "",
                    "previewUrl": info.get("thumburl") or info.get("url") or "",
                    "originalWidth": width,
                    "originalHeight": height,
                    "searchTheme": query,
                    "sourceSha1": source_hash,
                }
                added_for_query += 1
                if added_for_query >= 10:
                    break
            if len(selected) >= COUNT + 180:
                return list(selected.values())
            if added_for_query >= 10:
                break
            offset += 50
            time.sleep(0.12)
    if len(selected) < COUNT:
        raise RuntimeError(f"Only {len(selected)} distinct qualifying 4K images found; need {COUNT}")
    return list(selected.values())


def fetch_preview(candidate: dict[str, Any]) -> tuple[dict[str, Any], bytes, str] | None:
    try:
        response = session.get(candidate["previewUrl"], timeout=25)
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

    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
        for result in pool.map(fetch_preview, candidates[:450]):
            if result is None:
                continue
            candidate, preview, digest = result
            if digest in seen_previews:
                continue
            seen_previews.add(digest)
            day = len(records) + 1
            filename = f"day_{day:03d}.webp"
            (OUT / filename).write_bytes(preview)
            records.append({"day": day, "file": filename, **candidate, "previewSha256": digest})
            print(f"{day:03d}/{COUNT}: {candidate['title']}")
            if day == COUNT:
                break

    if len(records) != COUNT:
        raise RuntimeError(f"Collected {len(records)} unique reachable wallpapers; expected {COUNT}")

    manifest = {
        "catalog": "Wikimedia Commons",
        "policy": "365 existing internet images. Every source file and preview is distinct, every original is 4K-qualified, licenses are public domain/CC0/CC BY/CC BY-SA, and no artwork is AI-generated.",
        "previewWidth": PREVIEW_SIZE[0],
        "previewHeight": PREVIEW_SIZE[1],
        "count": COUNT,
        "wallpapers": records,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    assert len({item["sourceId"] for item in records}) == COUNT
    assert len({item["sourceSha1"] for item in records}) == COUNT
    assert len({item["previewSha256"] for item in records}) == COUNT
    print(f"Collected {COUNT} distinct licensed 4K sources; no synthetic images.")


if __name__ == "__main__":
    main()
