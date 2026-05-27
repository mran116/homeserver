#!/usr/bin/env python3
"""
Force-import every queue item that Sonarr blocked with
"Found matching series via grab history, but release was matched to series by ID."

Sonarr's parser refuses auto-import when the filename-derived seriesId disagrees
with the grab-history seriesId (common on anthology series like the unified
Power Rangers entry). The /manualimport endpoint, given the queue's downloadId,
resolves the series+episode correctly — this script just re-POSTs that payload
as a ManualImport command, which Sonarr accepts and clears the queue entry.

Usage:
  scripts/sonarr-bulk-import.py            # dry-run (default)
  scripts/sonarr-bulk-import.py --apply    # actually issue the imports
  scripts/sonarr-bulk-import.py --apply --limit 5

Reads the API key directly from the sonarr container's config.xml so no .env
plumbing is needed.
"""
from __future__ import annotations
import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SONARR_URL = "http://localhost:8989"
BLOCK_MSG = "Found matching series via grab history, but release was matched to series by ID"


def sonarr_api_key() -> str:
    out = subprocess.check_output(
        ["docker", "exec", "sonarr", "sed", "-n",
         r"s/.*<ApiKey>\([^<]*\)<\/ApiKey>.*/\1/p", "/config/config.xml"],
        text=True,
    ).strip()
    if not out:
        sys.exit("could not read Sonarr API key from container")
    return out


def api(method: str, path: str, key: str, *, params=None, body=None):
    url = f"{SONARR_URL}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
    data = None
    headers = {"X-Api-Key": key, "Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> {e.code}: {e.read().decode(errors='replace')}")


def blocked_queue(key: str) -> list[dict]:
    page = api("GET", "/api/v3/queue", key,
               params={"pageSize": 500, "includeUnknownSeriesItems": "true"})
    out = []
    for r in page.get("records", []):
        msgs = []
        for sm in r.get("statusMessages") or []:
            msgs += sm.get("messages", [])
        if any(BLOCK_MSG in m for m in msgs):
            out.append(r)
    return out


def parse_candidates(key: str, folder: str, download_id: str) -> list[dict]:
    return api("GET", "/api/v3/manualimport", key, params={
        "folder": folder,
        "downloadId": download_id,
        "filterExistingFiles": "true",
    }) or []


def submit_import(key: str, files: list[dict]):
    return api("POST", "/api/v3/command", key, body={
        "name": "ManualImport",
        "files": files,
        "importMode": "auto",
    })


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="actually submit imports (default: dry-run)")
    ap.add_argument("--limit", type=int, default=0, help="stop after N items (0 = all)")
    args = ap.parse_args()

    key = sonarr_api_key()
    items = blocked_queue(key)
    print(f"found {len(items)} blocked queue item(s)")
    if not items:
        return 0

    todo = items[: args.limit] if args.limit else items
    print(f"processing {len(todo)} item(s){' (dry-run)' if not args.apply else ''}\n")

    ok = skipped = failed = 0
    for i, q in enumerate(todo, 1):
        title = q.get("title") or "?"
        path = q.get("outputPath")
        dlid = q.get("downloadId")
        print(f"[{i}/{len(todo)}] {title[:90]}")
        if not (path and dlid):
            print("  skip: missing outputPath or downloadId"); skipped += 1; continue

        cands = parse_candidates(key, path, dlid)
        usable = [c for c in cands if (c.get("series") or {}).get("id") and c.get("episodes") and not c.get("rejections")]
        if not usable:
            print(f"  skip: no usable manualimport candidate (got {len(cands)}, rejections present)")
            skipped += 1
            continue

        files = []
        for c in usable:
            files.append({
                "path": c["path"],
                "folderName": path,
                "seriesId": c["series"]["id"],
                "episodeIds": [e["id"] for e in c["episodes"]],
                "quality": c["quality"],
                "languages": c.get("languages") or [{"id": 1, "name": "English"}],
                "releaseGroup": c.get("releaseGroup") or "",
                "downloadId": dlid,
                "episodeFileId": 0,
            })
        eps = ",".join(f"S{c['seasonNumber']:02d}E{e['episodeNumber']:02d}" for c in usable for e in c["episodes"])
        print(f"  -> seriesId={usable[0]['series']['id']} {eps} quality={usable[0]['quality']['quality']['name']}")

        if not args.apply:
            ok += 1
            continue
        try:
            submit_import(key, files)
            ok += 1
            # Be nice to Sonarr — bursting hundreds of ManualImport commands at once
            # makes it serialize anyway and risks timeouts.
            time.sleep(0.5)
        except SystemExit:
            raise
        except Exception as e:
            print(f"  FAIL: {e}")
            failed += 1

    print(f"\ndone: {ok} submitted, {skipped} skipped, {failed} failed")
    if not args.apply:
        print("(dry-run) re-run with --apply to actually import.")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
