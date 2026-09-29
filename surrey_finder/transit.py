"""
Transit module: Handles TransLink Route 323 stops and pedestrian distance calculations.
"""

import math
import json
import logging
from dataclasses import dataclass
from typing import List, Optional, Tuple
from pathlib import Path
from .config import STOPS_FILE, SearchConfig

logger = logging.getLogger("surrey_finder.transit")

@dataclass
class StopInfo:
    id: int
    name: str
    lat: float
    lon: float
    direction: str = ""

@dataclass
class WalkMatch:
    nearest_stop: StopInfo
    distance_meters: float
    walk_time_minutes: float
    is_within_threshold: bool

def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great circle distance between two points on the earth in meters.
    """
    R = 6371000.0  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (math.sin(delta_phi / 2.0) ** 2 +
         math.cos(phi1) * math.cos(phi2) *
         math.sin(delta_lambda / 2.0) ** 2)
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))

    return R * c

class TransitCorridor:
    def __init__(self, stops_file: Path = STOPS_FILE, config: Optional[SearchConfig] = None):
        self.stops_file = stops_file
        self.config = config or SearchConfig()
        self.stops: List[StopInfo] = []
        self.load_stops()

    def load_stops(self):
        """Loads cached Route 323 stops from JSON."""
        if not self.stops_file.exists():
            logger.warning(f"Stops file {self.stops_file} does not exist. Initializing empty.")
            return

        try:
            with open(self.stops_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                self.stops = [
                    StopInfo(
                        id=s["id"],
                        name=s["name"],
                        lat=float(s["lat"]),
                        lon=float(s["lon"]),
                        direction=s.get("direction", "")
                    )
                    for s in data
                ]
            logger.info(f"Loaded {len(self.stops)} Route 323 stops.")
        except Exception as e:
            logger.error(f"Failed to load stops file: {e}")

    def evaluate_proximity(self, lat: float, lon: float) -> Optional[WalkMatch]:
        """
        Calculates distance from a coordinate to the nearest Route 323 stop.
        Returns WalkMatch with distance and walk time.
        """
        if not self.stops or lat is None or lon is None:
            return None

        best_stop = None
        min_dist = float("inf")

        for stop in self.stops:
            dist = haversine_meters(lat, lon, stop.lat, stop.lon)
            if dist < min_dist:
                min_dist = dist
                best_stop = stop

        if best_stop is None:
            return None

        walk_minutes = min_dist / self.config.walking_speed_m_per_min
        is_within = min_dist <= self.config.max_walk_distance_meters

        return WalkMatch(
            nearest_stop=best_stop,
            distance_meters=round(min_dist, 1),
            walk_time_minutes=round(walk_minutes, 1),
            is_within_threshold=is_within
        )

    def get_all_stops(self) -> List[StopInfo]:
        return self.stops
