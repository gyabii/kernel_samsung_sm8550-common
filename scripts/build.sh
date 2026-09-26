#!/usr/bin/env bash
set -euo pipefail

# (env-overridable)
KERNEL_DEFCONFIG=${KERNEL_DEFCONFIG:-gki_defconfig}
CLANG_VERSION=${CLANG_VERSION:-clang-r614150}
OUT_DIR=${OUT_DIR:-out}
CLANG_DIR=${CLANG_DIR:-"$HOME/tools/google-clang"}
CLANG_BINARY="$CLANG_DIR/bin/clang"
START_TIME=$(date +%s)

# --- pretty logs ---
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
err(){  echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

setup_clang() {
    info "Fetching clang version $CLANG_VERSION..."
    mkdir -p "$CLANG_DIR"
    TARBALL="$(mktemp)"

    URL_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive"
    CLANG_URL="$URL_BASE/mirror-goog-main-llvm-toolchain-source/${CLANG_VERSION}.tar.gz"

    if command -v wget >/dev/null 2>&1; then
      wget -c --show-progress -O "$TARBALL" "$CLANG_URL" || err "Download failed"
    elif command -v curl >/dev/null 2>&1; then
      curl -L --fail --progress-bar -o "$TARBALL" "$CLANG_URL" || err "Download failed"
    else
      err "Need wget or curl to download the toolchain."
    fi

    info "Extracting toolchain..."
    tar -xzf "$TARBALL" -C "$CLANG_DIR"
    rm -f "$TARBALL"

    export PATH="$CLANG_DIR/bin:$PATH"
    ver="$("$CLANG_BINARY" --version | head -n1)"
    ver="$(echo "$ver" | sed -E 's/\(http[^)]*\)//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//')"
    export KBUILD_COMPILER_STRING="$ver"
}

build_kernel() {
  info "Starting kernel build..."
  setup_clang
  mkdir -p "$OUT_DIR"

  make -j"$(nproc --all)" O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
       "$KERNEL_DEFCONFIG" || err "Defconfig failed"

  make -j"$(nproc --all)" O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
       || err "Build failed"

  total=$(( $(date +%s) - START_TIME ))
  info "Build finished in $((total/60))m $((total%60))s."
}

# Always build
build_kernel
