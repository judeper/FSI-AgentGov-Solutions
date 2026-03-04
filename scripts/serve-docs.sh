#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Installing docs dependencies..."
pip install -r requirements-docs.txt --quiet 2>/dev/null

echo "Running build script..."
python scripts/build-docs.py

echo "Starting local preview server..."
mkdocs serve
