#!/bin/sh
# Run the Dash app locally against Lakebase, using the OAuth token on the
# clipboard (Connect dialog -> "Copy OAuth token"). Expires hourly.
set -a; . ./.env.local; set +a
PGPASSWORD="$(pbpaste)" exec .venv/bin/python app/app.py
