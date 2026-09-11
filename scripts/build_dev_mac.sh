#!/usr/bin/env bash
# Personal dev helper: build MTG Sheet Optimizer, drop it in ~/Downloads,
# kill any running instance, and relaunch the fresh build.
set -euo pipefail

APP_NAME="MTG Sheet Optimizer"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$PROJECT_DIR/dist/$APP_NAME.app"
DEST_APP="$HOME/Downloads/$APP_NAME.app"

echo "==> Closing running instances of $APP_NAME..."
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -x MTGSheetOptimizer >/dev/null 2>&1 || true

echo "==> Building release app..."
"$PROJECT_DIR/build.sh"

echo "==> Copying build to $DEST_APP..."
rm -rf "$DEST_APP"
cp -R "$BUILT_APP" "$DEST_APP"

echo "==> Launching $DEST_APP..."
open "$DEST_APP"

echo "Done."
