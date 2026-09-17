#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-core.py
mkdir -p .build
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
cc=$(xcrun --sdk iphoneos --find clang)
CGO_ENABLED=1 GOOS=ios GOARCH=arm64 CC="$cc" \
 CGO_CFLAGS="-isysroot $sdk -arch arm64 -miphoneos-version-min=15.0" \
 CGO_LDFLAGS="-isysroot $sdk -arch arm64 -miphoneos-version-min=15.0" \
 go build -tags cli -buildmode=c-archive -trimpath -o .build/libgotohp.a ./cmd/bridge
