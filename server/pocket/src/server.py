#!/usr/bin/env python3
"""Shared evidence catalog and bounded Luna advice; ranking, feasibility and routing stay on device."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import datetime as dt
import hmac
import json
import logging
import math
import os
from pathlib import Path
import re
import secrets
import shlex
import sqlite3
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = Path(os.environ.get("POCKET_RESOURCE_DIR", str(ROOT.parent.parent / "packages/PocketEngine/Sources/PocketEngine/Resources")))
SEED = RESOURCES / "catalog.json"
FIELDS = {"publicAccess", "reading", "coffee", "quiet", "outdoor", "children", "wheelchair", "noMembership"}
LABEL_SCHEMA = RESOURCES / "preference-labels.json"
LABELS = json.loads(LABEL_SCHEMA.read_text())
FIELDS.update(label for section in ("types", "subtypes", "features") for group in LABELS[section].values() for label in group)
MAX_BODY = 2_000_000


def now():
    return dt.datetime.now(dt.timezone.utc)


def stamp(value=None):
    return (value or now()).isoformat(timespec="seconds").replace("+00:00", "Z")


def date(value):
    if not isinstance(value, str):
        raise ValueError("Timestamp must be ISO 8601 text")
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Timestamp must include a time zone")
    return parsed.astimezone(dt.timezone.utc)


def fresh(value):
    if not value:
        return False
    return date(value["checkedAt"]) <= now() < min(date(value["expiresAt"]), date(value["checkedAt"]) + dt.timedelta(days=30))


def load_env():
    path = ROOT / ".env"
    if path.exists():
        for line in path.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            key, separator, value = line.partition("=")
            if not separator or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key.strip()):
                raise ValueError("Invalid .env syntax")
            values = shlex.split(value, comments=True)
            os.environ.setdefault(key.strip(), values[0] if values else "")


class Store:
    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        with self.connection() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS venues (id TEXT PRIMARY KEY, body TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS identity_checks (id TEXT PRIMARY KEY, checked_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS usage (day TEXT PRIMARY KEY, reserved INTEGER NOT NULL);
            """)
            seed = json.loads(Path(os.environ.get("POCKET_SEED_CATALOG", str(SEED))).read_text())
            for venue in seed["venues"]:
                db.execute("INSERT OR IGNORE INTO venues VALUES (?, ?)", (venue["id"], json.dumps(venue, ensure_ascii=False)))
            db.execute("INSERT OR IGNORE INTO meta VALUES ('updatedAt', ?)", (stamp(),))
            db.execute("INSERT OR IGNORE INTO identity_checks SELECT id, ? FROM venues", (stamp(),))
        os.chmod(path, 0o600)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.execute("PRAGMA busy_timeout=10000")
        try:
            with db:
                yield db
        finally:
            db.close()

    def catalog(self):
        with self.connection() as db:
            rows = [json.loads(r[0]) for r in db.execute("SELECT body FROM venues ORDER BY id")]
            updated = db.execute("SELECT value FROM meta WHERE key='updatedAt'").fetchone()[0]
        return dict(schemaVersion=1, generatedAt=updated,
                    attribution="OpenStreetMap contributors (ODbL); Overture and evidence sources as attributed per record.", venues=rows)

    def reserve_provider(self, cap, provider="tomtom"):
        day = now().date().isoformat()
        if provider != "tomtom":
            day = provider + ":" + day
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT reserved FROM usage WHERE day=?", (day,)).fetchone()
            used = row[0] if row else 0
            if used >= cap:
                raise ValueError("Daily TomTom request cap reached")
            db.execute("INSERT INTO usage VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET reserved=excluded.reserved", (day, used + 1))

    def import_identities(self, catalog):
        if catalog.get("schemaVersion") != 1 or not isinstance(catalog.get("venues"), list) or not 1 <= len(catalog["venues"]) <= 20_000:
            raise ValueError("Invalid independent catalog")
        identities = catalog["venues"]
        if len({v["id"] for v in identities}) != len(identities):
            raise ValueError("Duplicate identity IDs")
        for venue in identities:
            if not venue["id"].startswith(("osm-", "overture-")) or not venue.get("license") or not venue.get("sourceURLs"):
                raise ValueError("Retain independent source identity and attribution")
            if venue.get("facts") or venue.get("hours"):
                raise ValueError("Import facts separately through reviewed evidence")
            if not all(isinstance(venue.get(key), str) for key in ("name", "branch", "address", "license")):
                raise ValueError("Identity requires name, branch, address and license")
            if not all(isinstance(venue.get(key), list) and all(isinstance(value, str) for value in venue[key])
                       for key in ("categories", "aliases", "sourceURLs", "operatorURLs")):
                raise ValueError("Identity requires string arrays for categories, aliases and source URLs")
            if not isinstance(venue.get("coordinate"), dict):
                raise ValueError("Identity requires coordinates")
            point = venue["coordinate"]
            if not venue.get("name") or not all(type(point[k]) in (int, float) and math.isfinite(point[k]) for k in ("latitude", "longitude")):
                raise ValueError("Invalid identity or coordinate")
            if not -90 <= point["latitude"] <= 90 or not -180 <= point["longitude"] <= 180:
                raise ValueError("Coordinate outside world bounds")
        accepted = updated = 0
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            for venue in identities:
                existing = db.execute("SELECT v.body, c.checked_at FROM venues v LEFT JOIN identity_checks c ON c.id=v.id WHERE v.id=?", (venue["id"],)).fetchone()
                if existing and existing[1] and date(existing[1]) + dt.timedelta(days=30) > now():
                    continue
                incoming = dict(venue)
                incoming["facts"] = []
                incoming["hours"] = None
                if existing:
                    old = json.loads(existing[0])
                    if old["name"] == incoming["name"] and old["coordinate"] == incoming["coordinate"]:
                        incoming["facts"] = old.get("facts", [])
                        incoming["hours"] = old.get("hours")
                    updated += 1
                else:
                    accepted += 1
                db.execute("INSERT INTO venues VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET body=excluded.body", (incoming["id"], json.dumps(incoming, ensure_ascii=False)))
                db.execute("INSERT INTO identity_checks VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET checked_at=excluded.checked_at", (incoming["id"], stamp()))
            if accepted or updated:
                db.execute("UPDATE meta SET value=? WHERE key='updatedAt'", (stamp(),))
        return dict(accepted=accepted, updatedExpired=updated, preservedExisting=len(identities) - accepted - updated)

    def merge(self, envelope):
        if not isinstance(envelope, dict) or envelope.get("schemaVersion") != 1:
            raise ValueError("Expected schemaVersion 1")
        if envelope.get("reviewed") is not True:
            raise ValueError("Import requires explicitly reviewed evidence, not raw model output")
        records = envelope.get("records")
        if not isinstance(records, list) or not 1 <= len(records) <= 1000:
            raise ValueError("Provide 1-1000 records")
        if len({r.get("venueID") for r in records if isinstance(r, dict)}) != len(records):
            raise ValueError("Each branch may occur once per import")
        accepted = skipped = 0
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            for record in records:
                row = db.execute("SELECT body FROM venues WHERE id=?", (record["venueID"],)).fetchone()
                if not row:
                    raise ValueError("Unknown independent venue ID")
                venue = json.loads(row[0])
                incoming = record.get("facts", [])
                if not isinstance(incoming, list) or len(incoming) > len(FIELDS):
                    raise ValueError("At most one incoming fact per field")
                if len({f.get("field") for f in incoming if isinstance(f, dict)}) != len(incoming):
                    raise ValueError("Duplicate incoming fact field")
                for fact in incoming:
                    self.validate_evidence(fact, venue)
                    if fact.get("field") not in FIELDS or fact.get("status") not in {"supported", "contradicted", "unknown"}:
                        raise ValueError("Invalid field or status")
                    existing = [f for f in venue["facts"] if f["field"] == fact["field"]]
                    if any(fresh(f) for f in existing):
                        skipped += 1
                        continue
                    venue["facts"] = [f for f in venue["facts"] if f["field"] != fact["field"]] + [fact]
                    accepted += 1
                if record.get("hours") is not None:
                    hours = record["hours"]
                    self.validate_evidence(hours, venue)
                    intervals = hours.get("intervals")
                    if not isinstance(intervals, list) or not 1 <= len(intervals) <= 100:
                        raise ValueError("Hours require 1-100 explicit intervals")
                    for interval in intervals:
                        weekday, start, end = (interval.get(k) for k in ("weekday", "startMinute", "endMinute"))
                        if not all(type(v) is int for v in (weekday, start, end)) or not 1 <= weekday <= 7 or not 0 <= start < 1440 or not start < end <= 2880:
                            raise ValueError("Invalid opening interval")
                        if interval.get("date") is not None:
                            parsed = dt.date.fromisoformat(interval["date"])
                            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", interval["date"]) or (parsed.weekday() + 1) % 7 + 1 != weekday:
                                raise ValueError("Date and weekday disagree")
                    if fresh(venue.get("hours")):
                        skipped += 1
                    else:
                        venue["hours"] = hours
                        accepted += 1
                db.execute("UPDATE venues SET body=? WHERE id=?", (json.dumps(venue, ensure_ascii=False), venue["id"]))
            if accepted:
                db.execute("UPDATE meta SET value=? WHERE key='updatedAt'", (stamp(),))
        return dict(accepted=accepted, skippedFresh=skipped, note="Fresh facts are preserved until expiry, at most 30 days. Import is atomic.")

    @staticmethod
    def validate_evidence(value, venue):
        if not isinstance(value, dict):
            raise ValueError("Evidence must be an object")
        checked, expiry = date(value.get("checkedAt")), date(value.get("expiresAt"))
        if checked > now() + dt.timedelta(seconds=60) or expiry <= checked or expiry > checked + dt.timedelta(days=30):
            raise ValueError("Evidence expiry must be within 30 days of a non-future check")
        url = urllib.parse.urlsplit(value.get("sourceURL", ""))
        allowed = {urllib.parse.urlsplit(v).hostname for v in venue["sourceURLs"] + venue["operatorURLs"]}
        host = (url.hostname or "").removeprefix("www.")
        allowed = {(h or "").removeprefix("www.") for h in allowed}
        if url.scheme != "https" or url.username or url.password or url.port or not (host in allowed or host == "jakarta.go.id" or host.endswith(".jakarta.go.id")):
            raise ValueError("Evidence must reference the known operator/source or Jakarta government")
        quote = value.get("quote")
        branch_quote = value.get("branchQuote")
        if not isinstance(quote, str) or not 8 <= len(quote) <= 2000 or not isinstance(branch_quote, str) or not 5 <= len(branch_quote) <= 500:
            raise ValueError("Provide fact quote and branchQuote for review")
        def normalized(text):
            return " ".join(re.findall(r"\w+", text.casefold()))
        names = [venue["name"]] + venue["aliases"]
        if not any(normalized(name) in normalized(branch_quote) for name in names):
            raise ValueError("Branch quote must contain an exact known branch name/alias")
        if "field" in value and (not isinstance(value.get("value"), str) or len(value["value"]) > 500):
            raise ValueError("Invalid fact value")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def tomtom_search(store, body):
    key = os.environ.get("TOMTOM_API_KEY", "")
    if not key:
        raise ValueError("TomTom is disabled; configure TOMTOM_API_KEY on the server")
    query = body.get("query", "").strip()
    lat, lon = float(body.get("latitude", "nan")), float(body.get("longitude", "nan"))
    if not 1 <= len(query) <= 200 or not math.isfinite(lat) or not math.isfinite(lon) or not -6.6 <= lat <= -5.9 or not 106.5 <= lon <= 107.2:
        raise ValueError("Provide a query and Jakarta coordinates")
    cap = int(os.environ.get("TOMTOM_DAILY_CAP", "20"))
    if not 1 <= cap <= 100:
        raise ValueError("TOMTOM_DAILY_CAP must be between 1 and 100")
    store.reserve_provider(cap)
    point = dict(type="point", coordinates=[lon, lat])
    payload = dict(query=query, origin=point, maxResults=5, preferences=dict(geometry=point),
                   filters=dict(types=["poi"], countryCodesIso2=["ID"], geometry=dict(type="rectangle", coordinates=[106.5, -6.6, 107.2, -5.9])))
    request = urllib.request.Request("https://api.tomtom.com/maps/orbis/places/discover", data=json.dumps(payload).encode(), headers={
        "TomTom-Api-Key": key, "TomTom-Api-Version": "3", "Content-Type": "application/json", "Accept-Language": "id-ID,en",
        "Attributes": "results(id,type,title,position,address,openingHours)", "Session-Id": str(__import__("uuid").uuid4())})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=25) as response:
            data = response.read(MAX_BODY + 1)
        if len(data) > MAX_BODY:
            raise ValueError("Provider response exceeded size limit")
        raw = json.loads(data)
    except urllib.error.HTTPError as error:
        raise ValueError("TomTom HTTP " + str(error.code)) from None
    except (urllib.error.URLError, TimeoutError):
        raise ValueError("TomTom connection failed; no alternative provider was called") from None
    hits = []
    if not isinstance(raw, dict) or not isinstance(raw.get("results"), list):
        raise ValueError("Unexpected TomTom response format")
    for row in raw.get("results", [])[:5]:
        if not isinstance(row, dict) or not isinstance(row.get("position"), dict):
            continue
        position = row.get("position", {}).get("coordinates", [])
        if len(position) != 2 or not all(type(v) in (int, float) and math.isfinite(v) for v in position):
            continue
        longitude, latitude = position
        if not -6.6 <= latitude <= -5.9 or not 106.5 <= longitude <= 107.2:
            continue
        address = row.get("address", {})
        if not isinstance(address, dict):
            address = {}
        lines = [str(address.get(k, "")) for k in ("street", "houseNumber", "municipalitySubdivision", "municipality", "postalCode")]
        hours = []
        for day in row.get("openingHours", [])[:10]:
            intervals = ", ".join(str(v.get("start", "?")) + "–" + str(v.get("end", "?")) for v in day.get("timeRanges", []))
            hours.append(str(day.get("date", "")) + ": " + intervals)
        hits.append(dict(id=str(row.get("id", "")), name=str(row.get("title", "Tempat")), address=", ".join(v for v in lines if v),
                         coordinate=dict(latitude=latitude, longitude=longitude), hoursSummary="; ".join(hours) or "Jam tidak disediakan pada hasil ini."))
    return dict(results=hits, notice="© TomTom. Hasil sesi tidak disimpan dalam katalog atau cache fakta 30 hari. Ketepatan cabang dan izin akses tetap perlu diperiksa.")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "PocketCatalog/0.1"
    def log_message(self, *_):
        pass  # Do not log user queries, credentials, or provider responses.

    def setup(self):
        super().setup()
        self.connection.settimeout(35)

    def reply(self, status, value):
        endpoint = self.path.split("?")[0]
        if endpoint not in {"/health", "/v1/catalog", "/v1/evidence/import", "/v1/providers/tomtom/search", "/v1/advice/visits"}:
            endpoint = "other"
        logging.info("request method=%s endpoint=%s status=%s", self.command, endpoint, status)
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True

    def authorized(self, write=False):
        expected = os.environ["POCKET_WRITE_TOKEN" if write else "POCKET_READ_TOKEN"]
        provided = self.headers.get("Authorization", "")
        return hmac.compare_digest(provided.encode(), ("Bearer " + expected).encode())

    def body(self):
        if self.headers.get("Transfer-Encoding"):
            raise ValueError("Chunked request bodies are not supported")
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size <= MAX_BODY:
            raise ValueError("Invalid request size")
        if self.headers.get_content_type() != "application/json":
            raise ValueError("Expected application/json")
        value = json.loads(self.rfile.read(size))
        if not isinstance(value, dict):
            raise ValueError("Expected a JSON object")
        return value

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, dict(service="C67 Pocket catalog", version=1))
        elif self.path == "/v1/catalog":
            if not self.authorized():
                self.reply(401, dict(error="Unauthorized")); return
            self.reply(200, self.server.store.catalog())
        else:
            self.reply(404, dict(error="Unknown endpoint"))

    def do_POST(self):
        if self.path not in {"/v1/evidence/import", "/v1/providers/tomtom/search", "/v1/advice/visits"}:
            self.reply(404, dict(error="Unknown endpoint")); return
        if not self.authorized(write=self.path == "/v1/evidence/import"):
            self.reply(401, dict(error="Unauthorized")); return
        try:
            body = self.body()
            if self.path == "/v1/evidence/import":
                value = self.server.store.merge(body)
            else:
                # Avoid simultaneous paid requests without a queue/upper bound.
                if not self.server.provider_lock.acquire(blocking=False):
                    self.reply(429, dict(error="Provider request already in progress")); return
                try:
                    if self.path == "/v1/advice/visits":
                        from visit_advice import advise
                        value = advise(body, before_request=lambda: self.server.store.reserve_provider(
                            min(100, max(0, int(os.environ.get("POCKET_LUNA_DAILY_CAP", "20")))), "luna"))
                    else:
                        value = tomtom_search(self.server.store, body)
                finally:
                    self.server.provider_lock.release()
            self.reply(200, value)
        except (ValueError, KeyError, TypeError, OverflowError, IndexError):
            self.reply(422, dict(error="Request, evidence, provider configuration, or quota is invalid; no fallback was called."))
        except (sqlite3.Error, OSError):
            self.reply(503, dict(error="Catalog storage or upstream service is unavailable"))


def main():
    load_env()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=ROOT / ".local/server")
    parser.add_argument("--import-evidence", type=Path, help="Import reviewed independent evidence atomically, then exit")
    parser.add_argument("--import-identities", type=Path, help="Import independent identity catalog, preserving existing records")
    args = parser.parse_args()
    os.umask(0o077)
    store = Store(args.data_dir / "catalog.sqlite")
    if args.import_identities:
        print(json.dumps(store.import_identities(json.loads(args.import_identities.read_text())), indent=2))
        return
    if args.import_evidence:
        print(json.dumps(store.merge(json.loads(args.import_evidence.read_text())), indent=2))
        return
    for name in ("POCKET_READ_TOKEN", "POCKET_WRITE_TOKEN"):
        if len(os.environ.get(name, "")) < 24:
            raise SystemExit(name + " must contain at least 24 characters")
    if secrets.compare_digest(os.environ["POCKET_READ_TOKEN"], os.environ["POCKET_WRITE_TOKEN"]):
        raise SystemExit("Use different read and write tokens")
    server = ThreadingHTTPServer((os.environ.get("POCKET_HOST", "127.0.0.1"), int(os.environ.get("POCKET_PORT", "8792"))), Handler)
    server.daemon_threads = True
    server.store = store
    server.provider_lock = threading.Lock()
    print("Pocket catalog server ready. Provider requests run only when explicitly requested by a client.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
