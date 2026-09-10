#!/bin/bash

# Exit on error
set -e

echo "==================================="
echo "Starting SMART-TRAP System"
echo "==================================="

# Start PocketBase in the background
echo "[1/2] Starting PocketBase backend..."
cd backend
if [ -f "pocketbase" ]; then
    ./pocketbase serve &
    PB_PID=$!
    echo "PocketBase running (PID: $PB_PID)"
else
    echo "Error: PocketBase executable not found in ./backend"
    exit 1
fi
cd ..

# Give PB a second to start up
sleep 1

# Start Flutter Desktop App
echo "[2/2] Starting Flutter Desktop App..."
cd smart_trap_app
flutter run -d linux

# Cleanup when Flutter app is closed
echo "Flutter app closed. Cleaning up..."
kill $PB_PID
echo "PocketBase stopped."
echo "Done."
