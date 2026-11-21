#!/usr/bin/env bash
# Builds the PUBLIC app (no personal places, release-signed), the web viewer and
# the download/privacy pages, then deploys everything to golicat.yeasinfiyaz.workers.dev.
set -euo pipefail
cd "$(dirname "$0")/.."
# Toolchain: the office PC keeps everything under E:\DevTools; any other PC uses
# the flutter/java already on PATH (e.g. D:\Tools on the home PC).
if [ -d /e/DevTools/flutter ]; then
  export JAVA_HOME=/e/DevTools/jdk17 ANDROID_HOME='E:\DevTools\android-sdk' PUB_CACHE='E:\DevTools\pub-cache' GRADLE_USER_HOME='E:\DevTools\gradle-home'
  export PATH="/e/DevTools/flutter/bin:$PATH"
fi
command -v flutter >/dev/null || { echo "flutter is not on PATH"; exit 1; }
[ -f android/key.properties ] || { echo "Missing android/key.properties (restore from the signing-key backup)"; exit 1; }
VER=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')

# Build with the EMPTY places file so your home/office can't end up inside the public app.
cp lib/config/seed_places.dart build/seed_places.private.bak
trap 'cp build/seed_places.private.bak lib/config/seed_places.dart' EXIT
cp lib/config/seed_places.example.dart lib/config/seed_places.dart
flutter build apk --release --split-per-abi --target-platform android-arm64,android-arm --dart-define=PUBLIC_BUILD=true
OUT=build/app/outputs/flutter-apk
mkdir -p build/public && cp $OUT/app-arm64-v8a-release.apk build/public/arm64.apk && cp $OUT/app-armeabi-v7a-release.apk build/public/armv7.apk
cp build/seed_places.private.bak lib/config/seed_places.dart

flutter build web -t lib/viewer_main.dart --release
find build/web -name "*.map" -delete
cp -r share/site/. build/web/
rm -f build/web/get/golicat-*.apk   # only the current version is offered
A64="golicat-$VER-arm64.apk"; A7="golicat-$VER-armv7.apk"
cp build/public/arm64.apk "build/web/get/$A64"; cp build/public/armv7.apk "build/web/get/$A7"
mb() { awk -v b="$(stat -c %s "$1")" 'BEGIN { printf "%.1f", b / 1048576 }'; }
SHA=$(sha256sum build/public/arm64.apk | cut -d' ' -f1)
sed -i "s|__APK_ARM64__|$A64|g; s|__APK_ARMV7__|$A7|g; s|__VERSION__|$VER|g; s|__SIZE_ARM64__|$(mb build/public/arm64.apk)|g; s|__SIZE_ARMV7__|$(mb build/public/armv7.apk)|g; s|__SHA_ARM64__|$SHA|g" build/web/get/index.html
grep -q "__" build/web/get/index.html && { echo "unfilled placeholder"; exit 1; }
# NO_DEPLOY=1 bash share/publish.sh  → build everything, test it, deploy later.
[ "${NO_DEPLOY:-}" = 1 ] && { echo "Built $VER (not deployed)"; exit 0; }
cd share && { ./deploy.sh whoami 2>&1 | grep -q "yeasinfiyaz@gmail.com" || ./deploy.sh whoami 2>&1 | grep -q "yeasinfiyaz@gmail.com"; } || { echo "Wrong Cloudflare login"; exit 1; }
./deploy.sh deploy
