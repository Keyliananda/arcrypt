#!/bin/bash
set -e

echo "Starting Flutter app in Profile mode..."
cd "$(dirname "$0")"

# Run in profile mode (works on real devices without memory protection issues)
flutter run --profile

echo "App started successfully!"
