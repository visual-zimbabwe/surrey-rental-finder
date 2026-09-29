"""
Configuration parameters for Surrey Route 323 Rental Finder
"""

import os
import json
from pathlib import Path
from dataclasses import dataclass, field, asdict
from typing import List

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = DATA_DIR / "rentals.db"
STOPS_FILE = DATA_DIR / "route_323_stops.json"
CONFIG_FILE = DATA_DIR / "config.json"

@dataclass
class SearchConfig:
    # Target constraints
    max_price: float = 2000.0
    min_bedrooms: int = 2
    max_bedrooms: int = 3
    min_bathrooms: float = 1.0
    max_bathrooms: float = 2.0

    # Feature toggles
    require_ac: bool = True
    allow_apartments: bool = False

    # Transit proximity
    route_name: str = "TransLink 323 (Surrey Central to Newton Exchange)"
    max_walk_distance_meters: float = 400.0  # ~5 minutes walking at 80m/min (4.8 km/h)
    walking_speed_m_per_min: float = 80.0

    # Housing type rules
    disallowed_types: List[str] = field(default_factory=lambda: [
        "apartment", "condo", "condominium", "flat", "high-rise", 
        "highrise", "penthouse", "studio", "bachelor", "dorm"
    ])
    
    allowed_types: List[str] = field(default_factory=lambda: [
        "house", "townhouse", "townhome", "duplex", "triplex", "fourplex",
        "basement", "ground level", "lower suite", "upper suite", "main floor",
        "coach house", "laneway house", "detached", "single family", "suite"
    ])

    # Air Conditioning matching
    ac_keywords: List[str] = field(default_factory=lambda: [
        "air conditioning", "air conditioned", "air conditioner", "air-condition",
        "a/c", "ac unit", "central air", "heat pump", "mini-split", "mini split",
        "ductless ac", "climate control", "cooling system"
    ])
    
    ac_negative_keywords: List[str] = field(default_factory=lambda: [
        "no ac", "no a/c", "no air conditioning", "air conditioning not included",
        "without ac", "without a/c", "no air conditioner", "portable ac extra",
        "portable ac not allowed", "not air conditioned"
    ])

    # Notification settings (can be overridden with environment variables)
    discord_webhook_url: str = os.getenv("DISCORD_WEBHOOK_URL", "")
    telegram_bot_token: str = os.getenv("TELEGRAM_BOT_TOKEN", "")
    telegram_chat_id: str = os.getenv("TELEGRAM_CHAT_ID", "")
    enable_desktop_notifications: bool = True

    # Scraper settings
    scrape_interval_minutes: int = 15
    request_delay_seconds: float = 2.0

    @classmethod
    def load(cls) -> "SearchConfig":
        """Loads configuration from config.json if available, or returns default."""
        config = cls()
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for k, v in data.items():
                        if hasattr(config, k):
                            setattr(config, k, v)
            except Exception:
                pass
        return config

    def save(self):
        """Saves current configuration to config.json."""
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(asdict(self), f, indent=2)
