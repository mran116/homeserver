#!/usr/bin/env python3
"""
seed-uptime-kuma.py — populate an empty Uptime Kuma from a version-controlled
monitor list, plus an ntfy notification that every monitor alerts through.

Why direct SQLite (not the API): Uptime Kuma has no declarative config and its
socket.io API needs the admin password (which lives only in the UI, not .env).
Writing the DB needs no credentials. Every NOT NULL column in the `monitor`
table has a default, so a minimal INSERT is safe. Uptime Kuma loads monitors at
startup, so the wrapper stops the container, runs this, and starts it again.

Idempotent: skips monitors whose name already exists; only inserts what's
missing. Safe to re-run. Use --force only to seed even if monitors exist.
"""
import argparse
import json
import sqlite3
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True, help="path to kuma.db")
    ap.add_argument("--seed", required=True, help="path to seed.json")
    ap.add_argument("--ntfy-server", default="http://ntfy")
    ap.add_argument("--ntfy-topic", default="diun-updates")
    ap.add_argument("--ntfy-priority", type=int, default=4)
    ap.add_argument("--force", action="store_true", help="seed even if monitors exist")
    args = ap.parse_args()

    with open(args.seed, encoding="utf-8") as fh:
        seed = json.load(fh)
    monitors = seed.get("monitorList", [])
    if not monitors:
        print("seed: no monitors in seed file — nothing to do")
        return 0

    con = sqlite3.connect(args.db)
    con.execute("PRAGMA foreign_keys = ON")
    cur = con.cursor()

    existing = cur.execute("SELECT count(*) FROM monitor").fetchone()[0]
    if existing and not args.force:
        print(f"seed: {existing} monitor(s) already present — skipping (use --force to override)")
        return 0

    row = cur.execute("SELECT id FROM user ORDER BY id LIMIT 1").fetchone()
    if not row:
        print("seed: no admin user yet — finish Uptime Kuma first-run setup, then re-run", file=sys.stderr)
        return 1
    user_id = row[0]

    # ntfy notification (alert channel) — created once, reused, linked to every monitor.
    notif_name = f"ntfy {args.ntfy_topic}"
    notif_cfg = json.dumps({
        "name": notif_name,
        "type": "ntfy",
        "ntfyserverurl": args.ntfy_server,
        "ntfytopic": args.ntfy_topic,
        "ntfyPriority": args.ntfy_priority,
        "ntfyAuthenticationMethod": "none",
    })
    row = cur.execute("SELECT id FROM notification WHERE name = ?", (notif_name,)).fetchone()
    if row:
        notif_id = row[0]
        cur.execute("UPDATE notification SET config = ?, active = 1 WHERE id = ?", (notif_cfg, notif_id))
    else:
        cur.execute(
            "INSERT INTO notification (name, active, user_id, is_default, config) VALUES (?, 1, ?, 0, ?)",
            (notif_name, user_id, notif_cfg),
        )
        notif_id = cur.lastrowid

    added = skipped = 0
    for m in monitors:
        name = m.get("name")
        if not name:
            continue
        if cur.execute("SELECT 1 FROM monitor WHERE name = ?", (name,)).fetchone():
            skipped += 1
            continue
        codes = json.dumps(m.get("accepted_statuscodes", ["200-299"]))
        cur.execute(
            """INSERT INTO monitor
               (name, type, url, interval, retry_interval, maxretries, method,
                ignore_tls, upside_down, accepted_statuscodes_json, active, user_id)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)""",
            (
                name,
                m.get("type", "http"),
                m.get("url"),
                int(m.get("interval", 60)),
                int(m.get("retryInterval", 60)),
                int(m.get("maxretries", 2)),
                m.get("method", "GET"),
                1 if m.get("ignoreTls", True) else 0,
                1 if m.get("upsideDown", False) else 0,
                codes,
                user_id,
            ),
        )
        cur.execute(
            "INSERT INTO monitor_notification (monitor_id, notification_id) VALUES (?, ?)",
            (cur.lastrowid, notif_id),
        )
        added += 1

    con.commit()
    con.close()
    print(f"seed: added {added} monitor(s), skipped {skipped} existing; "
          f"all linked to '{notif_name}' (ntfy {args.ntfy_server}/{args.ntfy_topic})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
