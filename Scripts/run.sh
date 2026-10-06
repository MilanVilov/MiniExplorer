#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$PROJECT_DIR/Scripts/build-app.sh"
open "$PROJECT_DIR/.build/app/MiniExplorer.app"
