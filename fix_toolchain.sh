#!/bin/bash
set -e

echo "🔧 Fixing Command Line Tools to restore build chain..."
echo ""

# Step 1: Remove current tools
echo "Step 1: Removing current Command Line Tools..."
sudo rm -rf /Library/Developer/CommandLineTools
echo "✅ Removed"
echo ""

# Step 2: Reinstall tools
echo "Step 2: Reinstalling Command Line Tools..."
echo "A dialog will appear - click 'Install' to proceed"
xcode-select --install

echo ""
echo "⏳ Waiting for installation to complete..."
echo "This may take several minutes. Press Enter when the installation dialog shows 'Done'"
read -p ""

# Step 3: Verify installation
echo ""
echo "Step 3: Verifying installation..."
echo "Command Line Tools path:"
xcode-select -p

echo ""
echo "Swift version:"
swift --version

echo ""
echo "✅ Command Line Tools restored!"
echo ""
echo "Step 4: Testing build..."
cd "$(dirname "$0")"
rm -rf .build .build-xcode

echo "Running swift build test (15 second timeout)..."
swift build -c release 2>&1 &
BUILD_PID=$!
sleep 15

if kill -0 $BUILD_PID 2>/dev/null; then
  kill -9 $BUILD_PID 2>/dev/null
  echo "❌ Build still hanging - toolchain may still be broken"
  echo "You may need to wait for a macOS update from Apple"
  exit 1
else
  wait $BUILD_PID
  BUILD_EXIT=$?
  if [ $BUILD_EXIT -eq 0 ]; then
    echo "✅ Build successful!"
    echo ""
    echo "Step 5: Deploying app..."
    ./deploy.sh
    echo ""
    echo "🎉 All done! Build chain restored and app deployed with waveform improvements!"
  else
    echo "⚠️ Build completed but with errors (exit code $BUILD_EXIT)"
    echo "Check the output above for details"
  fi
fi
