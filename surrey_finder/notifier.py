"""
Notifier module: Rich terminal formatting, Discord webhooks, and desktop notifications.
"""

import subprocess
import logging
from typing import List, Dict, Any, Optional
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.text import Text
from curl_cffi import requests
from .config import SearchConfig
from .parser import ParsedListing

logger = logging.getLogger("surrey_finder.notifier")
console = Console()

class Notifier:
    def __init__(self, config: Optional[SearchConfig] = None):
        self.config = config or SearchConfig()

    def display_listing_panel(self, listing: ParsedListing):
        """Displays a single matched listing in a highlighted rich panel."""
        walk = listing.walk_match
        stop_str = f"{walk.nearest_stop.name} (~{walk.walk_time_minutes} min walk / {walk.distance_meters}m)" if walk else "N/A"
        ac_str = f"[bold green]Yes[/bold green] ({listing.ac_match_text})" if listing.has_ac else "[bold red]No[/bold red]"
        
        content = (
            f"[bold cyan]Rent:[/bold cyan] ${listing.price:,.0f}/mo\n"
            f"[bold cyan]Layout:[/bold cyan] {listing.bedrooms} Beds | {listing.bathrooms or '?'} Baths\n"
            f"[bold cyan]Type:[/bold cyan] {listing.housing_type} (Non-Apartment)\n"
            f"[bold cyan]Air Conditioning:[/bold cyan] {ac_str}\n"
            f"[bold cyan]Nearest Bus 323 Stop:[/bold cyan] {stop_str}\n"
            f"[bold cyan]Link:[/bold cyan] [underline blue]{listing.url}[/underline blue]"
        )

        panel = Panel(
            content,
            title=f"🎯 [bold green]MATCH FOUND[/bold green]: {listing.title[:60]}",
            border_style="green",
            expand=False
        )
        console.print(panel)

    def display_results_table(self, listings: List[ParsedListing], show_all: bool = False):
        """Displays results in a formatted Rich table."""
        table = Table(title="🏡 Surrey Bus 323 Rental Search Results", show_lines=True)
        table.add_column("Status", style="bold", justify="center")
        table.add_column("Price", justify="right")
        table.add_column("Beds/Baths", justify="center")
        table.add_column("Type", justify="center")
        table.add_column("A/C", justify="center")
        table.add_column("Nearest 323 Stop & Walk Time", justify="left")
        table.add_column("Details / Reason", justify="left")

        for item in listings:
            if not show_all and not item.is_full_match:
                continue

            status = "[green]MATCH[/green]" if item.is_full_match else "[red]REJECTED[/red]"
            price_str = f"${item.price:,.0f}" if item.price else "?"
            beds_baths = f"{item.bedrooms or '?'}bd / {item.bathrooms or '?'}ba"
            type_str = item.housing_type
            ac_str = "[green]✓ AC[/green]" if item.has_ac else "[dim]No AC[/dim]"

            if item.walk_match:
                stop_desc = f"{item.walk_match.nearest_stop.name}\n({item.walk_match.walk_time_minutes} min / {item.walk_match.distance_meters}m)"
            else:
                stop_desc = "[dim]No GPS[/dim]"

            if item.is_full_match:
                details = f"[blue]{item.url}[/blue]"
            else:
                details = "\n".join(f"• {r}" for r in item.reasons_rejected[:2])

            table.add_row(status, price_str, beds_baths, type_str, ac_str, stop_desc, details)

        console.print(table)

    def send_discord_notification(self, listing: ParsedListing):
        """Sends rich webhook embed to Discord."""
        if not self.config.discord_webhook_url:
            return

        walk = listing.walk_match
        stop_desc = f"{walk.nearest_stop.name} (~{walk.walk_time_minutes} min walk / {walk.distance_meters}m)" if walk else "N/A"

        payload = {
            "username": "Surrey 323 Rental Finder",
            "embeds": [
                {
                    "title": f"🎯 Match: {listing.title}",
                    "url": listing.url,
                    "color": 3066993,  # Green
                    "fields": [
                        {"name": "💰 Rent", "value": f"${listing.price:,.0f}/month", "inline": True},
                        {"name": "🛏️ Beds / Baths", "value": f"{listing.bedrooms} Beds / {listing.bathrooms or '?'} Baths", "inline": True},
                        {"name": "🏡 Type", "value": f"{listing.housing_type}", "inline": True},
                        {"name": "❄️ Air Conditioning", "value": f"Yes ({listing.ac_match_text or 'Detected'})", "inline": True},
                        {"name": "🚌 Bus 323 Proximity", "value": stop_desc, "inline": False}
                    ],
                    "footer": {"text": "Surrey TransLink 323 Rental Alert"}
                }
            ]
        }

        try:
            requests.post(self.config.discord_webhook_url, json=payload, timeout=10)
            logger.info(f"Sent Discord notification for listing {listing.id}")
        except Exception as e:
            logger.error(f"Failed to send Discord webhook: {e}")

    def send_desktop_notification(self, listing: ParsedListing):
        """Sends native desktop notification via notify-send if available."""
        if not self.config.enable_desktop_notifications:
            return

        try:
            walk = listing.walk_match
            stop_str = f"Near {walk.nearest_stop.name} ({walk.walk_time_minutes}m walk)" if walk else ""
            subprocess.run([
                "notify-send",
                "-u", "normal",
                "🎯 Surrey 323 Rental Match Found!",
                f"${listing.price:,.0f} - {listing.bedrooms}BR {listing.housing_type}\n{stop_str}"
            ], check=False, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    def notify_all(self, listing: ParsedListing):
        """Broadcasts notification to all enabled channels."""
        self.display_listing_panel(listing)
        self.send_discord_notification(listing)
        self.send_desktop_notification(listing)
