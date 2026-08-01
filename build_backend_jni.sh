#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
NDK_VERSION="28.2.13676358"
NDK_PATH="/home/anthony/Android/Sdk/ndk/$NDK_VERSION"

if [ ! -d "$NDK_PATH" ]; then
  NDK_VERSION="30.0.15729638"
  NDK_PATH="/home/anthony/Android/Sdk/ndk/$NDK_VERSION"
fi

if [ ! -d "$NDK_PATH" ]; then
  echo "❌ Android NDK not found!"
  exit 1
fi

echo "Using NDK: $NDK_PATH"

cd "$BACKEND_DIR"

# 1. Build arm64-v8a
echo "🔨 Compiling libtorrent.so for arm64-v8a..."
mkdir -p "$SCRIPT_DIR/android/app/src/main/jniLibs/arm64-v8a"
CGO_ENABLED=1 \
GOOS=android \
GOARCH=arm64 \
CC="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang" \
CXX="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang++" \
go build -ldflags="-checklinkname=0" -buildmode=c-shared -o "$SCRIPT_DIR/android/app/src/main/jniLibs/arm64-v8a/libtorrent.so" -tags library .

# 2. Build x86_64 (emulator)
echo "🔨 Compiling libtorrent.so for x86_64..."
mkdir -p "$SCRIPT_DIR/android/app/src/main/jniLibs/x86_64"
CGO_ENABLED=1 \
GOOS=android \
GOARCH=amd64 \
CC="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android30-clang" \
CXX="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android30-clang++" \
go build -ldflags="-checklinkname=0" -buildmode=c-shared -o "$SCRIPT_DIR/android/app/src/main/jniLibs/x86_64/libtorrent.so" -tags library .

echo "✅ Android FFI binaries built successfully!"
