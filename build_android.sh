#!/usr/bin/env bash
# 群晖助手 (dsm_helper) Android release 构建脚本
# 用法:
#   ./build_android.sh           # 增量构建
#   ./build_android.sh --clean   # 先 flutter clean 再构建
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="${DSM_TOOLCHAIN:-$(cd "$PROJECT_DIR/../../toolchain" && pwd)}"

if [[ ! -x "$TOOLCHAIN_DIR/flutter/bin/flutter" ]]; then
  echo "找不到 Flutter SDK: $TOOLCHAIN_DIR/flutter" >&2
  echo "请设置 DSM_TOOLCHAIN 指向工具链目录。" >&2
  exit 1
fi

export JAVA_HOME="$TOOLCHAIN_DIR/jdk11/Contents/Home"
export ANDROID_HOME="$TOOLCHAIN_DIR/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$TOOLCHAIN_DIR/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
# 绕过 macOS 系统代理，避免 Gradle 下载卡死
export GRADLE_OPTS="-Djava.net.useSystemProxies=false"

if ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
  echo "警告: 未检测到 Rosetta 2，Flutter 3.7 的 Android AOT 工具需要它。"
  echo "     请执行: softwareupdate --install-rosetta --agree-to-license"
fi

cd "$PROJECT_DIR"

if [[ "${1:-}" == "--clean" ]]; then
  echo "==> flutter clean"
  flutter clean
fi

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build apk --release"
flutter build apk --release

VERSION="$(grep -E '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*//' | cut -d+ -f1)"
APK="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
OUT_DIR="$PROJECT_DIR/dist"
mkdir -p "$OUT_DIR"
OUT_APK="$OUT_DIR/dsm_helper-${VERSION}-release.apk"
cp "$APK" "$OUT_APK"

echo
echo "构建完成: $OUT_APK"
ls -lh "$OUT_APK"
shasum -a 256 "$OUT_APK"
