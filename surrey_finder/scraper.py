"""
Scraper module: Fetches rental listings from Craigslist (and extensible sources) using curl_cffi.
"""

import re
import time
import logging
from typing import List, Dict, Any, Optional
from bs4 import BeautifulSoup
from curl_cffi import requests
from .config import SearchConfig

logger = logging.getLogger("surrey_finder.scraper")

class CraigslistScraper:
    def __init__(self, config: Optional[SearchConfig] = None):
        self.config = config or SearchConfig()
        self.headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        }

    def get_search_urls(self) -> List[str]:
        """
        Builds Craigslist search URLs for Surrey/Richmond/Delta (rds) and Greater Vancouver.
        """
        # rds = Richmond / Delta / Surrey area
        urls = [
            f"https://vancouver.craigslist.org/search/rds/apa?max_price={int(self.config.max_price)}&min_bedrooms={self.config.min_bedrooms}&max_bedrooms={self.config.max_bedrooms}&min_bathrooms={int(self.config.min_bathrooms)}&max_bathrooms={int(self.config.max_bathrooms)}&query=surrey",
            f"https://vancouver.craigslist.org/search/rds/apa?max_price={int(self.config.max_price)}&min_bedrooms={self.config.min_bedrooms}&max_bedrooms={self.config.max_bedrooms}&min_bathrooms={int(self.config.min_bathrooms)}&max_bathrooms={int(self.config.max_bathrooms)}"
        ]
        return urls

    def fetch_search_results(self, limit: int = 50) -> List[Dict[str, Any]]:
        """
        Fetches search results pages and extracts basic listing cards.
        """
        items = []
        seen_urls = set()

        for search_url in self.get_search_urls():
            try:
                logger.info(f"Fetching Craigslist search: {search_url}")
                resp = requests.get(search_url, impersonate="chrome120", headers=self.headers, timeout=15)
                if resp.status_code != 200:
                    logger.warning(f"Failed to fetch {search_url} (HTTP {resp.status_code})")
                    continue

                soup = BeautifulSoup(resp.text, "html.parser")
                cards = soup.find_all("li", class_="cl-static-search-result") or soup.find_all("li", class_="result-row")

                for card in cards:
                    link_el = card.find("a")
                    if not link_el or not link_el.get("href"):
                        continue
                    url = link_el.get("href")
                    if url in seen_urls:
                        continue
                    seen_urls.add(url)

                    title_el = card.find("div", class_="title") or card.find("a", class_="result-title")
                    price_el = card.find("div", class_="price") or card.find("span", class_="result-price")
                    location_el = card.find("div", class_="location")

                    title = title_el.text.strip() if title_el else ""
                    price = price_el.text.strip() if price_el else ""
                    loc_text = location_el.text.strip() if location_el else ""

                    # Extract listing ID from URL
                    listing_id = url.split("/")[-1].replace(".html", "")

                    items.append({
                        "id": listing_id,
                        "source": "Craigslist",
                        "url": url,
                        "title": title,
                        "price": price,
                        "location_hint": loc_text
                    })

                    if len(items) >= limit:
                        break

            except Exception as e:
                logger.error(f"Error scraping search page {search_url}: {e}")

            if len(items) >= limit:
                break

        return items

    def fetch_listing_details(self, item: Dict[str, Any]) -> Dict[str, Any]:
        """
        Fetches the listing detail page to obtain coordinates, full description, and structured attributes.
        """
        url = item["url"]
        try:
            resp = requests.get(url, impersonate="chrome120", headers=self.headers, timeout=12)
            if resp.status_code != 200:
                logger.warning(f"Could not fetch details for {url} (HTTP {resp.status_code})")
                return item

            soup = BeautifulSoup(resp.text, "html.parser")

            # Extract GPS coordinates
            map_el = soup.find("div", id="map")
            if map_el:
                lat_str = map_el.get("data-latitude")
                lon_str = map_el.get("data-longitude")
                if lat_str and lon_str:
                    item["lat"] = float(lat_str)
                    item["lon"] = float(lon_str)

            # Extract structured attributes (e.g., 'w/d in unit', 'air conditioning', 'cats are OK')
            attr_groups = soup.find_all("p", class_="attrgroup")
            attributes = []
            for grp in attr_groups:
                for span in grp.find_all("span"):
                    txt = span.text.strip()
                    if txt:
                        attributes.append(txt)
            item["attributes"] = attributes

            # Extract body text
            body_el = soup.find("section", id="postingbody")
            if body_el:
                # Remove "QR Code Link to This Post" boilerplate
                body_text = body_el.text.replace("QR Code Link to This Post", "").strip()
                item["body"] = body_text

            # Extract exact title & price from page if available
            title_el = soup.find("span", id="titletextonly")
            if title_el:
                item["title"] = title_el.text.strip()

            price_el = soup.find("span", class_="price")
            if price_el:
                item["price"] = price_el.text.strip()

        except Exception as e:
            logger.error(f"Error fetching listing detail {url}: {e}")

        return item

    def scrape_all(self, limit: int = 30, progress_callback=None) -> List[Dict[str, Any]]:
        """
        Scrapes listings and their details with rate-limiting pauses.
        """
        basic_items = self.fetch_search_results(limit=limit)
        detailed_items = []

        total = len(basic_items)
        for i, item in enumerate(basic_items, 1):
            if progress_callback:
                progress_callback(i, total, item["title"])

            detailed = self.fetch_listing_details(item)
            detailed_items.append(detailed)

            # Be polite to servers
            time.sleep(self.config.request_delay_seconds)

        return detailed_items
