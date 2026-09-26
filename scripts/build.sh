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
    if [[ -x "$CLANG_BINARY" ]]; then
      info "Clang already present at $CLANG_DIR, skipping download."
      export PATH="$CLANG_DIR/bin:$PATH"
      ver="$("$CLANG_BINARY" --version | head -n1)"
      ver="$(echo "$ver" | sed -E 's/\(http[^)]*\)//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//')"
      export KBUILD_COMPILER_STRING="$ver"
      return 0
    fi

    info "Fetching clang version $CLANG_VERSION..."
    mkdir -p "$CLANG_DIR"
    TARBALL="$(mktemp)"

    URL_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive"
    CLANG_URL="$URL_BASE/mirror-goog-main-llvm-toolchain-source/${CLANG_VERSION}.tar.gz"
    USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    download_ok=0
    if command -v wget >/dev/null 2>&1; then
      if wget -U "$USER_AGENT" --tries=5 --waitretry=3 --show-progress -O "$TARBALL" "$CLANG_URL"; then
        download_ok=1
      fi
    fi

    if [[ $download_ok -eq 0 ]] && command -v curl >/dev/null 2>&1; then
      if curl -A "$USER_AGENT" -L --fail --retry 5 --retry-delay 3 --progress-bar -o "$TARBALL" "$CLANG_URL"; then
        download_ok=1
      fi
    fi

    [[ $download_ok -eq 1 ]] || err "Download failed after multiple attempts"

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
