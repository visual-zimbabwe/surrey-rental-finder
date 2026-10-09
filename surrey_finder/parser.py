"""
Parser module: Analyzes rental listing text, attributes, housing types, AC, and criteria matching.
"""

import re
import logging
from dataclasses import dataclass
from typing import Optional, List, Dict, Any
from .config import SearchConfig
from .transit import WalkMatch, TransitCorridor

logger = logging.getLogger("surrey_finder.parser")

@dataclass
class ParsedListing:
    id: str
    source: str
    url: str
    title: str
    price: float
    bedrooms: Optional[int]
    bathrooms: Optional[float]
    housing_type: str
    is_not_apartment: bool
    has_ac: bool
    ac_match_text: Optional[str]
    lat: Optional[float]
    lon: Optional[float]
    walk_match: Optional[WalkMatch]
    is_full_match: bool
    reasons_rejected: List[str]
    raw_body: str = ""
    posted_at: Optional[str] = None
    updated_at: Optional[str] = None

class ListingParser:
    def __init__(self, config: Optional[SearchConfig] = None, transit: Optional[TransitCorridor] = None):
        self.config = config or SearchConfig()
        self.transit = transit or TransitCorridor(config=self.config)

    def parse_price(self, price_str: str) -> float:
        """Extracts float price from strings like '$1,850' or '1850/mo'."""
        if not price_str:
            return 0.0
        cleaned = re.sub(r"[^\d.]", "", price_str)
        try:
            return float(cleaned)
        except ValueError:
            return 0.0

    def extract_bedrooms_and_bathrooms(self, title: str, body: str, attrs: List[str]) -> Tuple_Beds_Baths:
        """Extracts bed and bath counts from attributes and text."""
        beds = None
        baths = None

        combined_text = f"{title} {' '.join(attrs)} {body}".lower()

        # Check attributes first
        for attr in attrs:
            attr_lower = attr.lower()
            # e.g. "2br / 1ba", "3 beds", "1.5 baths", "2bdrms"
            br_match = re.search(r"(\d+)\s*(?:br|bed|bedroom|bdrm|bdr)s?", attr_lower)
            if br_match and beds is None:
                beds = int(br_match.group(1))

            ba_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:ba|bath|bathroom)s?", attr_lower)
            if ba_match and baths is None:
                baths = float(ba_match.group(1))

        # Fallback to title & body regex
        if beds is None:
            bed_m = re.search(r"(?:^|[^\w])([1-5])\s*(?:bed|bedroom|bdrm|br|bdr)s?(?:$|[^\w])", combined_text)
            if bed_m:
                beds = int(bed_m.group(1))

        if baths is None:
            bath_m = re.search(r"(?:^|[^\w])([1-4](?:\.[05])?)\s*(?:bath|bathroom|ba)s?(?:$|[^\w])", combined_text)
            if bath_m:
                baths = float(bath_m.group(1))

        return beds, baths

    def determine_housing_type(self, title: str, body: str, attrs: List[str]) -> Tuple_Housing:
        """
        Determines housing type and verifies it is NOT an apartment/condo.
        Must be a house, suite, basement, duplex, townhouse, etc.
        """
        text = f"{title} {' '.join(attrs)} {body}".lower()

        # Check for explicit apartment/condo terminology
        is_apartment = False
        for dis in self.config.disallowed_types:
            # Match whole words to avoid matching "suite" in "apartment suite"
            if re.search(rf"\b{re.escape(dis)}\b", text):
                is_apartment = True
                break

        # Check for allowed house/suite types
        detected_type = "Unknown"
        is_allowed_house = False
        for allowed in self.config.allowed_types:
            if re.search(rf"\b{re.escape(allowed)}\b", text):
                detected_type = allowed.title()
                is_allowed_house = True
                break

        # If it explicitly says "basement suite in house" or "suite in house", prioritize house over apartment
        if ("basement" in text or "suite" in text or "house" in text) and not ("apartment building" in text or "condo building" in text):
            if "basement" in text:
                detected_type = "Basement Suite"
                is_apartment = False
                is_allowed_house = True
            elif "townhouse" in text or "townhome" in text:
                detected_type = "Townhouse"
                is_apartment = False
                is_allowed_house = True
            elif "duplex" in text:
                detected_type = "Duplex"
                is_apartment = False
                is_allowed_house = True
            elif "house" in text or "main floor" in text or "upper suite" in text:
                detected_type = "House / Suite"
                is_apartment = False
                is_allowed_house = True

        is_valid_non_apartment = is_allowed_house and not is_apartment

        return detected_type, is_valid_non_apartment

    def check_air_conditioning(self, title: str, body: str, attrs: List[str]) -> Tuple_AC:
        """
        Checks for positive presence of air conditioning while filtering out negative matches.
        """
        text = f"{title} {' '.join(attrs)} {body}".lower()

        # Check negative phrases first
        for neg in self.config.ac_negative_keywords:
            if re.search(rf"\b{re.escape(neg)}\b", text):
                return False, f"Explicitly excluded: '{neg}'"

        # Check positive keywords
        for pos in self.config.ac_keywords:
            # Word boundary check
            if re.search(rf"\b{re.escape(pos)}\b", text):
                return True, pos

        return False, None

    def evaluate_listing(self, raw_data: Dict[str, Any]) -> ParsedListing:
        """
        Evaluates a raw listing against all user constraints:
        1. Price <= $2,000
        2. 2 <= Bedrooms <= 3
        3. 1 <= Bathrooms <= 2
        4. Not an apartment (House / Suite / Duplex / Townhouse)
        5. Air conditioning present
        6. Within 5-minute walk (<= 400m) of Bus 323 stop
        """
        listing_id = str(raw_data.get("id", ""))
        source = raw_data.get("source", "Craigslist")
        url = raw_data.get("url", "")
        title = raw_data.get("title", "")
        body = raw_data.get("body", "")
        attrs = raw_data.get("attributes", [])
        lat = raw_data.get("lat")
        lon = raw_data.get("lon")

        price = raw_data.get("price")
        if isinstance(price, (int, float)):
            price_val = float(price)
        else:
            price_val = self.parse_price(str(price or ""))

        beds, baths = self.extract_bedrooms_and_bathrooms(title, body, attrs)
        housing_type, is_not_apartment = self.determine_housing_type(title, body, attrs)
        has_ac, ac_match_text = self.check_air_conditioning(title, body, attrs)

        walk_match = None
        if lat is not None and lon is not None:
            walk_match = self.transit.evaluate_proximity(lat, lon)

        reasons_rejected = []

        if price_val <= 0 or price_val > self.config.max_price:
            reasons_rejected.append(f"Price (${price_val:,.0f}) exceeds max ${self.config.max_price:,.0f}")

        if beds is None:
            reasons_rejected.append("Could not determine bedroom count")
        elif not (self.config.min_bedrooms <= beds <= self.config.max_bedrooms):
            reasons_rejected.append(f"Bedrooms ({beds}) outside required range ({self.config.min_bedrooms}-{self.config.max_bedrooms})")

        if baths is not None and not (self.config.min_bathrooms <= baths <= self.config.max_bathrooms):
            reasons_rejected.append(f"Bathrooms ({baths}) outside required range ({self.config.min_bathrooms}-{self.config.max_bathrooms})")

        if not self.config.allow_apartments and not is_not_apartment:
            reasons_rejected.append(f"Housing type ({housing_type}) is an apartment/condo (only houses/suites allowed)")

        if self.config.require_ac and not has_ac:
            reasons_rejected.append("No air conditioning mentioned in listing")

        if walk_match is None:
            reasons_rejected.append("No GPS coordinates available to verify Bus 323 walk proximity")
        elif not walk_match.is_within_threshold:
            reasons_rejected.append(f"Too far from Bus 323: {walk_match.distance_meters}m ({walk_match.walk_time_minutes} min walk > 5 min limit)")

        is_full_match = len(reasons_rejected) == 0

        posted_at = raw_data.get("posted_at")
        updated_at = raw_data.get("updated_at")

        return ParsedListing(
            id=listing_id,
            source=source,
            url=url,
            title=title,
            price=price_val,
            bedrooms=beds,
            bathrooms=baths,
            housing_type=housing_type,
            is_not_apartment=is_not_apartment,
            has_ac=has_ac,
            ac_match_text=ac_match_text,
            lat=lat,
            lon=lon,
            walk_match=walk_match,
            is_full_match=is_full_match,
            reasons_rejected=reasons_rejected,
            raw_body=body,
            posted_at=posted_at,
            updated_at=updated_at
        )

# Helper type aliases for type cleanliness
from typing import Tuple
Tuple_Beds_Baths = Tuple[Optional[int], Optional[float]]
Tuple_Housing = Tuple[str, bool]
Tuple_AC = Tuple[bool, Optional[str]]
