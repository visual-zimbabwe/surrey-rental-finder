# Surrey Route 323 Rental Finder

CLI tool & Omarchy desktop widget to monitor rental listings in **Surrey, BC, Canada** along the **TransLink Bus 323** corridor (Surrey Central ↔ Newton Exchange).

## Features
* **Transit Shed**: <= 5 min walk (<= 400m) to all 63 Route 323 stops
* **Housing**: Houses, Basement Suites, Duplexes, Townhouses (No apartments)
* **Specs**: 2–3 Beds, 1–2 Baths, <= $2,000/mo CAD
* **A/C Detection**: Validates positive air conditioning / heat pump mentions

## Quick Start
```bash
./run.sh scan --show-all        # Scan active listings
./run.sh watch --interval 15    # Background monitoring
./run.sh config show            # View filter criteria
./run.sh config set max_price 2200 # Edit search parameters
```

## Desktop Plugin
Copy `plugin/` to `~/.config/omarchy/plugins/juwimana.surrey-rentals` for the bar widget and popup panel.
