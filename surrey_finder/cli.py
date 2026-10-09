"""
CLI Interface for Surrey Route 323 Rental Finder
"""

import sys
import time
import click
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn
from .config import SearchConfig
from .transit import TransitCorridor
from .parser import ListingParser
from .storage import RentalDatabase
from .scraper import CraigslistScraper
from .notifier import Notifier

console = Console()

@click.group(context_settings=dict(help_option_names=["-h", "--help"]))
def main():
    """🏡 Surrey Route 323 Rental Finder CLI"""
    pass

@main.command()
@click.option("--limit", default=30, help="Maximum number of search results to evaluate.")
@click.option("--show-all", is_flag=True, help="Display all scanned listings including rejected ones.")
@click.option("--max-price", default=None, type=float, help="Override maximum price (default: $2,000).")
@click.option("--max-walk-mins", default=None, type=float, help="Override maximum walk time in minutes (default: 5 mins).")
def scan(limit: int, show_all: bool, max_price: float, max_walk_mins: float):
    """🔍 Scan active Surrey rental listings for Route 323 matches."""
    config = SearchConfig.load()
    if max_price is not None:
        config.max_price = max_price
    if max_walk_mins is not None:
        config.max_walk_distance_meters = max_walk_mins * config.walking_speed_m_per_min

    console.print(f"[bold cyan]Initializing scan for Route 323 corridor...[/bold cyan]")
    ac_label = "A/C Required" if config.require_ac else "A/C Optional"
    type_label = "House/Suite Only" if not config.allow_apartments else "All Types (incl. Apartments)"
    console.print(f"Criteria: [yellow]{config.min_bedrooms}-{config.max_bedrooms} Beds | {config.min_bathrooms:g}-{config.max_bathrooms:g} Baths | Max ${config.max_price:,.0f} | {type_label} | {ac_label} | <= {config.max_walk_distance_meters/config.walking_speed_m_per_min:.1f} min walk to Bus 323[/yellow]\n")

    transit = TransitCorridor(config=config)
    parser = ListingParser(config=config, transit=transit)
    db = RentalDatabase()
    notifier = Notifier(config=config)
    scraper = CraigslistScraper(config=config)

    parsed_listings = []
    matches = []

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        console=console
    ) as progress:
        fetch_task = progress.add_task("[green]Fetching search results...", total=100)
        basic_items = scraper.fetch_search_results(limit=limit)
        progress.update(fetch_task, completed=100)

        total_items = len(basic_items)
        if total_items == 0:
            console.print("[red]No listings found from search page.[/red]")
            return

        detail_task = progress.add_task(f"[cyan]Evaluating {total_items} listings...", total=total_items)

        for i, item in enumerate(basic_items, 1):
            progress.update(detail_task, description=f"[cyan]Analyzing ({i}/{total_items}): {item['title'][:35]}...")
            detailed_item = scraper.fetch_listing_details(item)
            parsed = parser.evaluate_listing(detailed_item)
            parsed_listings.append(parsed)

            is_new = db.save_listing(parsed)

            if parsed.is_full_match:
                matches.append(parsed)
                if is_new:
                    notifier.notify_all(parsed)
                    db.mark_as_notified([parsed.id])

            progress.advance(detail_task)
            time.sleep(config.request_delay_seconds)

    console.print("\n")
    notifier.display_results_table(parsed_listings, show_all=show_all or len(matches) == 0)

    console.print(f"\n[bold]Scan Complete:[/bold] Evaluated {len(parsed_listings)} listings. Found [bold green]{len(matches)}[/bold green] exact matches.")
    if len(matches) == 0 and not show_all:
        console.print("[dim]Tip: Run with --show-all to see why scanned listings were filtered out.[/dim]")

@main.command()
@click.option("--interval", default=15, help="Minutes between monitoring scans (default: 15).")
@click.option("--limit", default=25, help="Listings to check per scan iteration.")
def watch(interval: int, limit: int):
    """👀 Continuously monitor for new listings and alert immediately."""
    config = SearchConfig.load()
    if interval is not None:
        config.scrape_interval_minutes = interval
    console.print(f"[bold green]Starting continuous watcher for Route 323 corridor (every {config.scrape_interval_minutes} min)...[/bold green]")
    console.print("Press Ctrl+C to stop.\n")

    while True:
        try:
            console.print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Running scheduled check...")
            # Run scan logic
            transit = TransitCorridor(config=config)
            parser = ListingParser(config=config, transit=transit)
            db = RentalDatabase()
            notifier = Notifier(config=config)
            scraper = CraigslistScraper(config=config)

            basic_items = scraper.fetch_search_results(limit=limit)
            new_matches = 0

            for item in basic_items:
                detailed = scraper.fetch_listing_details(item)
                parsed = parser.evaluate_listing(detailed)
                is_new = db.save_listing(parsed)

                if parsed.is_full_match and is_new:
                    new_matches += 1
                    notifier.notify_all(parsed)
                    db.mark_as_notified([parsed.id])

                time.sleep(config.request_delay_seconds)

            console.print(f"Check finished. New matches alerted: {new_matches}. Sleeping for {interval} minutes...")
            time.sleep(interval * 60)
        except KeyboardInterrupt:
            console.print("\n[yellow]Watcher stopped by user.[/yellow]")
            break
        except Exception as e:
            console.print(f"[red]Error during watch cycle: {e}[/red]")
            time.sleep(60)

@main.command(name="stops")
def list_stops():
    """🚏 List all TransLink Route 323 stops and coordinates."""
    transit = TransitCorridor()
    stops = transit.get_all_stops()
    console.print(f"[bold cyan]TransLink Route 323 Bus Stops ({len(stops)} stops):[/bold cyan]\n")

    from rich.table import Table
    table = Table(title="Route 323 Stops (Surrey Central ↔ Newton Exchange)")
    table.add_column("Stop ID", justify="right", style="cyan")
    table.add_column("Stop Name", style="bold")
    table.add_column("Direction", style="dim")
    table.add_column("Latitude", justify="right")
    table.add_column("Longitude", justify="right")

    for s in stops:
        table.add_row(str(s.id), s.name, s.direction, f"{s.lat:.5f}", f"{s.lon:.5f}")

    console.print(table)

@main.command(name="test-coords", context_settings=dict(ignore_unknown_options=True))
@click.argument("lat", type=float)
@click.argument("lon", type=float)
def test_coordinates(lat: float, lon: float):
    """📍 Test any GPS coordinate against the 5-minute walk shed for Route 323."""
    config = SearchConfig()
    transit = TransitCorridor(config=config)
    match = transit.evaluate_proximity(lat, lon)

    if match:
        status_color = "green" if match.is_within_threshold else "red"
        status_text = "WITHIN 5-MIN WALK" if match.is_within_threshold else "EXCEEDS 5-MIN WALK"

        console.print(f"Nearest Stop: [bold]{match.nearest_stop.name}[/bold]")
        console.print(f"Distance: [bold]{match.distance_meters} meters[/bold]")
        console.print(f"Walk Time: [bold]{match.walk_time_minutes} minutes[/bold]")
        console.print(f"Status: [{status_color}]{status_text}[/{status_color}] (Limit: {config.max_walk_distance_meters}m)")
    else:
        console.print("[red]Could not calculate distance.[/red]")

@main.command(name="history")
def show_history():
    """📜 Display previously matched listings from the local database."""
    db = RentalDatabase()
    matches = db.get_all_matches()
    if not matches:
        console.print("[yellow]No historical matches recorded in database yet.[/yellow]")
        return

    from rich.table import Table
    table = Table(title=f"📜 Historical Matches ({len(matches)} listings)")
    table.add_column("Posted / Seen", style="dim")
    table.add_column("Title", style="bold")
    table.add_column("Price", justify="right")
    table.add_column("Beds/Baths", justify="center")
    table.add_column("Type", justify="center")
    table.add_column("Nearest 323 Stop", justify="left")
    table.add_column("Link", style="blue")

    for m in matches:
        date_raw = m.get("posted_at") or m.get("first_seen_at") or ""
        date_str = date_raw[:16].replace("T", " ") if date_raw else ""
        price_str = f"${m['price']:,.0f}" if m['price'] else "?"
        beds_baths = f"{m['bedrooms']}bd / {m['bathrooms']}ba"
        stop_info = f"{m['nearest_stop_name'] or 'N/A'} ({m['walk_time_minutes']} min)"
        table.add_row(date_str, m["title"][:30], price_str, beds_baths, m["housing_type"], stop_info, m["url"])

    console.print(table)

@main.command(name="stats")
def show_stats():
    """📊 View database statistics and scan metrics."""
    db = RentalDatabase()
    stats = db.get_stats()
    console.print(f"[bold cyan]Rental Finder Database Statistics:[/bold cyan]")
    console.print(f"• Total Listings Scanned: [bold]{stats['total_scanned']}[/bold]")
    console.print(f"• Within 5-min walk of Bus 323: [bold]{stats['near_bus_323']}[/bold]")
    console.print(f"• With Air Conditioning: [bold]{stats['has_ac']}[/bold]")
    console.print(f"• Full Matches (All Criteria): [bold green]{stats['full_matches']}[/bold green]")

@main.command(name="json-matches")
def json_matches():
    """Output matches, stats, and config as JSON for UI integration."""
    import json
    from dataclasses import asdict
    db = RentalDatabase()
    config = SearchConfig.load()
    matches = db.get_all_matches()
    stats = db.get_stats()
    cfg_data = asdict(config)
    cfg_data["max_walk_mins"] = config.max_walk_distance_meters / config.walking_speed_m_per_min
    sys.stdout.write(json.dumps({"stats": stats, "config": cfg_data, "matches": matches}, indent=2) + "\n")
    sys.stdout.flush()

@main.command(name="json-config")
def json_config():
    """Output configuration as JSON for UI integration."""
    import json
    from dataclasses import asdict
    config = SearchConfig.load()
    data = asdict(config)
    data["max_walk_mins"] = config.max_walk_distance_meters / config.walking_speed_m_per_min
    sys.stdout.write(json.dumps(data, indent=2) + "\n")
    sys.stdout.flush()

@main.command(name="json-scan")
@click.option("--limit", default=25, help="Number of listings to scan.")
def json_scan(limit: int):
    """Run a scan and return updated matches/stats in JSON."""
    import json
    from dataclasses import asdict
    config = SearchConfig.load()
    transit = TransitCorridor(config=config)
    parser = ListingParser(config=config, transit=transit)
    db = RentalDatabase()
    scraper = CraigslistScraper(config=config)

    basic_items = scraper.fetch_search_results(limit=limit)
    new_matches = 0

    for item in basic_items:
        detailed = scraper.fetch_listing_details(item)
        parsed = parser.evaluate_listing(detailed)
        is_new = db.save_listing(parsed)
        if parsed.is_full_match and is_new:
            new_matches += 1
        time.sleep(config.request_delay_seconds)

    matches = db.get_all_matches()
    stats = db.get_stats()
    sys.stdout.write(json.dumps({"stats": stats, "new_matches": new_matches, "matches": matches}, indent=2) + "\n")
    sys.stdout.flush()

@main.group(name="config")
def config_group():
    """⚙️ Manage search criteria and filters."""
    pass

@config_group.command(name="show")
def config_show():
    """Display current search parameters."""
    from rich.table import Table
    config = SearchConfig.load()
    table = Table(title="⚙️ Current Search Criteria")
    table.add_column("Parameter", style="cyan bold")
    table.add_column("Value", style="yellow")
    table.add_column("Description", style="dim")

    max_walk_mins = config.max_walk_distance_meters / config.walking_speed_m_per_min
    table.add_row("max_price", f"${config.max_price:,.0f}", "Maximum monthly rent (CAD)")
    table.add_row("min_bedrooms", str(config.min_bedrooms), "Minimum required bedrooms")
    table.add_row("max_bedrooms", str(config.max_bedrooms), "Maximum allowed bedrooms")
    table.add_row("min_bathrooms", str(config.min_bathrooms), "Minimum required bathrooms")
    table.add_row("max_bathrooms", str(config.max_bathrooms), "Maximum allowed bathrooms")
    table.add_row("require_ac", str(config.require_ac), "Require Air Conditioning (true/false)")
    table.add_row("allow_apartments", str(config.allow_apartments), "Allow Apartments/Condos (true/false)")
    table.add_row("max_walk_mins", f"{max_walk_mins:.1f} mins ({config.max_walk_distance_meters:.0f}m)", "Max walk time to Route 323 stop")
    table.add_row("scrape_interval", f"{config.scrape_interval_minutes} mins", "Background check interval")

    console.print(table)

@config_group.command(name="set")
@click.argument("key")
@click.argument("value")
def config_set(key: str, value: str):
    """Update a search parameter (e.g. max_price 2200, require_ac false)."""
    config = SearchConfig.load()
    k = key.lower().strip()
    v = value.strip()

    if k in ["max_price", "price"]:
        config.max_price = float(v.replace("$", "").replace(",", ""))
    elif k in ["min_bedrooms", "min_beds"]:
        config.min_bedrooms = int(v)
    elif k in ["max_bedrooms", "max_beds"]:
        config.max_bedrooms = int(v)
    elif k in ["min_bathrooms", "min_baths"]:
        config.min_bathrooms = float(v)
    elif k in ["max_bathrooms", "max_baths"]:
        config.max_bathrooms = float(v)
    elif k in ["require_ac", "ac_required", "ac"]:
        config.require_ac = v.lower() in ["true", "1", "yes", "on"]
    elif k in ["allow_apartments", "apartments"]:
        config.allow_apartments = v.lower() in ["true", "1", "yes", "on"]
    elif k in ["max_walk_mins", "walk_mins"]:
        mins = float(v)
        config.max_walk_distance_meters = mins * config.walking_speed_m_per_min
    elif k in ["scrape_interval", "interval"]:
        config.scrape_interval_minutes = int(v)
    else:
        console.print(f"[red]Unknown configuration key:[/red] {key}")
        console.print("Valid keys: max_price, min_bedrooms, max_bedrooms, min_bathrooms, max_bathrooms, require_ac, allow_apartments, max_walk_mins, scrape_interval")
        return

    config.save()
    console.print(f"[bold green]✓ Updated {k} to:[/bold green] [yellow]{v}[/yellow]")

@config_group.command(name="reset")
def config_reset():
    """Reset configuration back to default values."""
    config = SearchConfig()
    config.save()
    console.print("[bold green]✓ Configuration reset to default criteria.[/bold green]")

if __name__ == "__main__":
    main()
