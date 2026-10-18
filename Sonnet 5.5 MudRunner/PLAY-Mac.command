#!/bin/bash
# One-click launcher for macOS: unpacks the game on the first start and opens it.
cd "$(dirname "$0")" || exit 1
ZIP="Game/MireAndIron-Mac.zip"
APP="Game/MireAndIron.app"

if [ ! -d "$APP" ]; then
  if [ ! -f "$ZIP" ]; then
    echo
    echo "ERROR: Game/MireAndIron-Mac.zip was not found next to this file."
    echo "Please unzip the WHOLE downloaded folder first, then run PLAY-Mac.command again."
    echo
    read -n 1 -s -r -p "Press any key to close..."
    exit 1
  fi
  echo
  echo "First launch: unpacking the game. This takes about a minute, please wait..."
  echo
  ditto -xk "$ZIP" "Game" || unzip -q -o "$ZIP" -d "Game"
fi

# allow the downloaded game to start (removes the 'downloaded from the internet' mark, fixes permissions, ad-hoc signature)
xattr -dr com.apple.quarantine "$APP" 2>/dev/null
xattr -dr com.apple.quarantine "$(pwd)" 2>/dev/null
chmod -R u+rwX "$APP"
chmod +x "$APP"/Contents/MacOS/* 2>/dev/null
codesign --force --deep -s - "$APP" >/dev/null 2>&1

echo "Starting Mire and Iron..."
open "$APP"
