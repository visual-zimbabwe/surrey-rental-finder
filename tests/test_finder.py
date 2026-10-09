"""
Unit tests for Surrey Route 323 Rental Finder
"""

import pytest
from surrey_finder.config import SearchConfig
from surrey_finder.transit import TransitCorridor, haversine_meters
from surrey_finder.parser import ListingParser

@pytest.fixture
def parser():
    config = SearchConfig()
    transit = TransitCorridor(config=config)
    return ListingParser(config=config, transit=transit)

def test_haversine_distance():
    # Surrey Central Station to approx 320m away
    dist = haversine_meters(49.1896, -122.8480, 49.1920, -122.8480)
    assert 200 < dist < 350

def test_ac_positive_detection(parser):
    has_ac, match = parser.check_air_conditioning("2 Bedroom House", "Includes central air conditioning and heat pump", [])
    assert has_ac is True
    assert "air conditioning" in match or "heat pump" in match

    has_ac, match = parser.check_air_conditioning("Basement suite with A/C", "Nice suite", [])
    assert has_ac is True

def test_ac_negative_detection(parser):
    has_ac, match = parser.check_air_conditioning("2 Bedroom Suite", "No A/C allowed in unit, electric baseboard heat only", [])
    assert has_ac is False
    assert "Explicitly excluded" in match

def test_housing_type_filtering(parser):
    # House/Basement/Duplex/Townhouse should pass
    t1, ok1 = parser.determine_housing_type("2 Bedroom Basement Suite", "Private entrance basement in quiet house", ["housing_type: house"])
    assert ok1 is True
    assert "Basement" in t1 or "House" in t1

    t2, ok2 = parser.determine_housing_type("3 Bed Townhouse for rent", "Spacious townhouse", [])
    assert ok2 is True

    # Apartment/Condo should fail
    t3, ok3 = parser.determine_housing_type("Luxury 2 Bed Highrise Apartment", "Great condo with views", ["housing_type: apartment"])
    assert ok3 is False

def test_full_match_evaluation(parser):
    # Listing close to 138 St @ 72 Ave (lat 49.1339, lon -122.8385)
    listing_data = {
        "id": "test-match-1",
        "url": "https://vancouver.craigslist.org/test/1.html",
        "title": "Beautiful 3 Bedroom Main Floor House with Central Air Conditioning",
        "price": "$1,950",
        "body": "Spacious 3 bedroom 1 bath upper level of a house. Features ductless mini-split heat pump and air conditioning. Walking distance to bus.",
        "attributes": ["3br", "1ba", "air conditioning", "house"],
        "lat": 49.1340,
        "lon": -122.8386,
        "posted_at": "2026-10-08T21:20:00-0700",
        "updated_at": "2026-10-08T22:00:00-0700"
    }
    result = parser.evaluate_listing(listing_data)
    assert result.is_full_match is True
    assert result.price == 1950.0
    assert result.bedrooms == 3
    assert result.bathrooms == 1.0
    assert result.has_ac is True
    assert result.walk_match.is_within_threshold is True
    assert result.walk_match.walk_time_minutes < 5.0
    assert result.posted_at == "2026-10-08T21:20:00-0700"
    assert result.updated_at == "2026-10-08T22:00:00-0700"

def test_database_latest_first_sorting(tmp_path, parser):
    from surrey_finder.storage import RentalDatabase

    db_file = tmp_path / "test_rentals.db"
    db = RentalDatabase(db_path=db_file)

    # Insert older listing
    old_data = {
        "id": "match-old",
        "url": "https://vancouver.craigslist.org/test/old.html",
        "title": "Older Match 2 Bed",
        "price": "$1,600",
        "body": "Air conditioning included in house",
        "attributes": ["2br", "1ba", "air conditioning", "house"],
        "lat": 49.1340,
        "lon": -122.8386,
        "posted_at": "2026-10-01T10:00:00"
    }
    parsed_old = parser.evaluate_listing(old_data)
    db.save_listing(parsed_old)

    # Insert newer listing
    new_data = {
        "id": "match-new",
        "url": "https://vancouver.craigslist.org/test/new.html",
        "title": "Newer Match 2 Bed",
        "price": "$1,700",
        "body": "Air conditioning included in suite",
        "attributes": ["2br", "1ba", "air conditioning", "suite"],
        "lat": 49.1340,
        "lon": -122.8386,
        "posted_at": "2026-10-08T15:00:00"
    }
    parsed_new = parser.evaluate_listing(new_data)
    db.save_listing(parsed_new)

    matches = db.get_all_matches()
    assert len(matches) == 2
    # Newest listing must come first
    assert matches[0]["id"] == "match-new"
    assert matches[0]["posted_at"] == "2026-10-08T15:00:00"
    assert matches[1]["id"] == "match-old"
    assert matches[1]["posted_at"] == "2026-10-01T10:00:00"
