"""
Storage module: SQLite database for deduplication, history tracking, and query statistics.
"""

import sqlite3
import logging
from typing import List, Optional, Dict, Any
from pathlib import Path
from datetime import datetime, timezone
from .config import DB_PATH
from .parser import ParsedListing

logger = logging.getLogger("surrey_finder.storage")

class RentalDatabase:
    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.init_db()

    def get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def init_db(self):
        with self.get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS listings (
                    id TEXT PRIMARY KEY,
                    source TEXT,
                    url TEXT UNIQUE,
                    title TEXT,
                    price REAL,
                    bedrooms INTEGER,
                    bathrooms REAL,
                    housing_type TEXT,
                    has_ac INTEGER,
                    ac_match_text TEXT,
                    lat REAL,
                    lon REAL,
                    nearest_stop_name TEXT,
                    distance_meters REAL,
                    walk_time_minutes REAL,
                    is_full_match INTEGER,
                    reasons_rejected TEXT,
                    first_seen_at TEXT,
                    last_seen_at TEXT,
                    posted_at TEXT,
                    updated_at TEXT,
                    notified INTEGER DEFAULT 0
                )
            """)
            # Migration check for existing databases
            cursor = conn.cursor()
            cursor.execute("PRAGMA table_info(listings)")
            columns = [row["name"] for row in cursor.fetchall()]
            if "posted_at" not in columns:
                conn.execute("ALTER TABLE listings ADD COLUMN posted_at TEXT")
                conn.execute("UPDATE listings SET posted_at = first_seen_at WHERE posted_at IS NULL")
            if "updated_at" not in columns:
                conn.execute("ALTER TABLE listings ADD COLUMN updated_at TEXT")

            conn.execute("CREATE INDEX IF NOT EXISTS idx_full_match ON listings(is_full_match)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_notified ON listings(notified)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_posted_at ON listings(posted_at)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_first_seen ON listings(first_seen_at)")
            conn.commit()

    def save_listing(self, listing: ParsedListing) -> bool:
        """
        Saves or updates a listing. Returns True if this is a newly inserted listing.
        """
        now = datetime.now(timezone.utc).isoformat()
        is_new = False
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id FROM listings WHERE id = ? OR url = ?", (listing.id, listing.url))
            row = cursor.fetchone()

            nearest_stop_name = listing.walk_match.nearest_stop.name if listing.walk_match else None
            distance_meters = listing.walk_match.distance_meters if listing.walk_match else None
            walk_time_minutes = listing.walk_match.walk_time_minutes if listing.walk_match else None
            reasons = "; ".join(listing.reasons_rejected)
            posted_val = listing.posted_at or now

            if row is None:
                is_new = True
                cursor.execute("""
                    INSERT INTO listings (
                        id, source, url, title, price, bedrooms, bathrooms,
                        housing_type, has_ac, ac_match_text, lat, lon,
                        nearest_stop_name, distance_meters, walk_time_minutes,
                        is_full_match, reasons_rejected, first_seen_at, last_seen_at,
                        posted_at, updated_at, notified
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                """, (
                    listing.id, listing.source, listing.url, listing.title,
                    listing.price, listing.bedrooms, listing.bathrooms,
                    listing.housing_type, 1 if listing.has_ac else 0,
                    listing.ac_match_text, listing.lat, listing.lon,
                    nearest_stop_name, distance_meters, walk_time_minutes,
                    1 if listing.is_full_match else 0, reasons, now, now,
                    posted_val, listing.updated_at
                ))
            else:
                cursor.execute("""
                    UPDATE listings SET
                        title = ?, price = ?, bedrooms = ?, bathrooms = ?,
                        housing_type = ?, has_ac = ?, ac_match_text = ?,
                        lat = ?, lon = ?, nearest_stop_name = ?,
                        distance_meters = ?, walk_time_minutes = ?,
                        is_full_match = ?, reasons_rejected = ?, last_seen_at = ?,
                        posted_at = COALESCE(?, posted_at),
                        updated_at = COALESCE(?, updated_at)
                    WHERE id = ? OR url = ?
                """, (
                    listing.title, listing.price, listing.bedrooms, listing.bathrooms,
                    listing.housing_type, 1 if listing.has_ac else 0,
                    listing.ac_match_text, listing.lat, listing.lon,
                    nearest_stop_name, distance_meters, walk_time_minutes,
                    1 if listing.is_full_match else 0, reasons, now,
                    listing.posted_at, listing.updated_at,
                    listing.id, listing.url
                ))
            conn.commit()
        return is_new

    def get_unnotified_matches(self) -> List[Dict[str, Any]]:
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM listings WHERE is_full_match = 1 AND notified = 0 ORDER BY COALESCE(posted_at, first_seen_at) DESC")
            return [dict(row) for row in cursor.fetchall()]

    def mark_as_notified(self, listing_ids: List[str]):
        if not listing_ids:
            return
        with self.get_connection() as conn:
            conn.executemany("UPDATE listings SET notified = 1 WHERE id = ?", [(lid,) for lid in listing_ids])
            conn.commit()

    def get_all_matches(self) -> List[Dict[str, Any]]:
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM listings WHERE is_full_match = 1 ORDER BY COALESCE(posted_at, first_seen_at) DESC")
            return [dict(row) for row in cursor.fetchall()]

    def get_stats(self) -> Dict[str, int]:
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM listings")
            total = cursor.fetchone()[0]
            cursor.execute("SELECT COUNT(*) FROM listings WHERE is_full_match = 1")
            matches = cursor.fetchone()[0]
            cursor.execute("SELECT COUNT(*) FROM listings WHERE has_ac = 1")
            ac_count = cursor.fetchone()[0]
            cursor.execute("SELECT COUNT(*) FROM listings WHERE walk_time_minutes <= 5.0")
            transit_count = cursor.fetchone()[0]
            return {
                "total_scanned": total,
                "full_matches": matches,
                "has_ac": ac_count,
                "near_bus_323": transit_count
            }
