#!/bin/bash
#
# DrowsinessWatch 再ビルドショートカット
#
# 使い方:
#   1. 下記の PROJECT_DIR を自分の .xcodeproj があるディレクトリに書き換える
#   2. SCHEME を Xcode 上のスキーム名に合わせる
#   3. このファイルをデスクトップに置いてダブルクリックで実行
#
# 署名証明書を更新した後にクリーンビルドし直す用途を想定。
#

# ---- 設定 (自分の環境に合わせて変更) ----

PROJECT_DIR="$HOME/Desktop/DrowsinessWatch"
SCHEME="DrowsinessWatch Watch App"
DESTINATION="generic/platform=watchOS"

# ---- ここから下は基本的に変更不要 ----

set -e

echo "========================================"
echo " DrowsinessWatch 再ビルド"
echo "========================================"
echo ""

# .xcodeproj を直接指定した場合はディレクトリとプロジェクト名に分離する。
if [[ "$PROJECT_DIR" == *.xcodeproj ]]; then
    XCODEPROJ=$(basename "$PROJECT_DIR")
    PROJECT_DIR=$(dirname "$PROJECT_DIR")
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "[ERROR] プロジェクトディレクトリが見つかりません:"
    echo "        $PROJECT_DIR"
    echo ""
    echo "このスクリプトの PROJECT_DIR を正しいパスに書き換えてください。"
    echo ""
    read -n 1 -s -r -p "何かキーを押すと閉じます..."
    exit 1
fi

cd "$PROJECT_DIR"

if [ -z "$XCODEPROJ" ]; then
    XCODEPROJ=$(find . -maxdepth 1 -name "*.xcodeproj" -print -quit)
fi

if [ -z "$XCODEPROJ" ] || [ ! -d "$XCODEPROJ" ]; then
    echo "[ERROR] .xcodeproj が見つかりません: $PROJECT_DIR"
    echo ""
    read -n 1 -s -r -p "何かキーを押すと閉じます..."
    exit 1
fi

# 指定されたスキームが実際に存在するか確認する。
# 存在しないスキームを指定すると xcodebuild が Segmentation fault を返す
# ことがあるので、事前にチェックしておく。
AVAILABLE_SCHEMES=$(xcodebuild -project "$XCODEPROJ" -list 2>/dev/null | awk '/Schemes:/{flag=1;next}/^$/{flag=0}flag' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if ! echo "$AVAILABLE_SCHEMES" | grep -qFx "$SCHEME"; then
    echo "[ERROR] スキーム \"$SCHEME\" が見つかりません。"
    echo ""
    echo "利用可能なスキーム:"
    echo "$AVAILABLE_SCHEMES" | sed 's/^/  /'
    echo ""
    echo "上記のいずれかをスクリプトの SCHEME に設定してください。"
    echo ""
    read -n 1 -s -r -p "何かキーを押すと閉じます..."
    exit 1
fi

# スキーム名や destination が誤っている場合 xcodebuild が Segfault することが
# あるため、`set -e` を一時的に無効化してエラーを最後まで表示できるようにする。
set +e

echo "[1/2] クリーン中..."
xcodebuild clean \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION"

echo ""
echo "[2/2] ビルド中 (署名を含む)..."
xcodebuild build \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -allowProvisioningUpdates
BUILD_RESULT=$?

echo ""
if [ $BUILD_RESULT -eq 0 ]; then
    echo "========================================"
    echo " ビルド成功"
    echo "========================================"
else
    echo "========================================"
    echo " ビルド失敗 (終了コード: $BUILD_RESULT)"
    echo "========================================"
fi

echo ""
read -n 1 -s -r -p "何かキーを押すと閉じます..."
