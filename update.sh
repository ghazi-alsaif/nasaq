#!/bin/bash
# Pull the latest NASAQ and refresh its files. Your bar layout, menu and settings stay.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
git pull --ff-only
./install.sh --update
