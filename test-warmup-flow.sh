#!/bin/bash

# Complete flow for testing warm-up
# This cleans up, rebuilds, and starts the app in one go to prevent cache issues

set -e

echo "🧹 STEP 1: Complete cleanup..."
./test-cleanup.sh > /dev/null 2>&1

echo ""
echo "🏗️  STEP 2: Rebuild and deploy..."
./deploy.sh > /dev/null 2>&1

echo ""
echo "✅ Setup complete!"
echo ""
echo "🚀 STEP 3: Starting fresh app for warm-up testing..."
echo ""
echo "   ⚠️  IMPORTANT - When onboarding appears:"
echo "   1. Select 'Base' model"
echo "   2. Click 'Download Model' button (should appear since cache was cleared)"
echo "   3. Watch for extra 2-3 seconds of 'Downloading...' time (that's the warm-up!)"
echo "   4. When complete, finish onboarding"
echo ""
echo "   📋 The logs should show:"
echo "      🔥 Warming up Neural Engine..."
echo "      ✅ Neural Engine warm-up complete in X.XXs"
echo ""

# Verify model cache is actually gone
if [ -d ~/Library/Caches/models/argmaxinc/whisperkit-coreml/openai_whisper-base ]; then
    echo "❌ ERROR: Model cache still exists! Removing manually..."
    rm -rf ~/Library/Caches/models/argmaxinc/whisperkit-coreml/openai_whisper-base
fi

# Start app with logging
swift run LookMaNoHands 2>&1 | tee /tmp/warmup_test_final.log &
APP_PID=$!

echo "App started with PID: $APP_PID"
echo "Logs being saved to: /tmp/warmup_test_final.log"
echo ""
echo "Press Ctrl+C when onboarding is complete to check logs..."

wait $APP_PID 2>/dev/null || true

echo ""
echo "=== WARM-UP LOG CHECK ==="
grep -E "(Warming|Neural|Pass)" /tmp/warmup_test_final.log -i | head -20 || echo "(no warm-up logs found - model may have been pre-cached)"
