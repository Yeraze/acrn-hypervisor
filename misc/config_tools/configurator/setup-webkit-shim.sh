#!/usr/bin/env bash
#
# Tauri 1.x (used by the ACRN Configurator) links against the webkit2gtk-4.0 /
# javascriptcoregtk-4.0 / libsoup-2.4 stack. Ubuntu 24.04+ (and 26.04) only ship
# the 4.1 / libsoup-3.0 packages; libwebkit2gtk-4.0-dev no longer exists in the
# archive. The 4.0 and 4.1 APIs are identical (4.1 is just 4.0 built against
# libsoup3), so we can satisfy the build by pointing the 4.0 names at the
# installed 4.1 libraries.
#
# This script needs NO root: it builds shim pkg-config (.pc) files and dev
# symlinks under a local directory, then prints the env vars to export before
# running `make configurator`.
#
# Usage:
#     source misc/config_tools/configurator/setup-webkit-shim.sh
#     make configurator
#
set -euo pipefail

ARCH_DIR="$(cc -print-multiarch 2>/dev/null || echo x86_64-linux-gnu)"
SYS_PC="/usr/lib/${ARCH_DIR}/pkgconfig"
SYS_LIB="/usr/lib/${ARCH_DIR}"
SHIM_ROOT="${SHIM_ROOT:-${HOME}/.cache/acrn-webkit-shim}"
SHIM_PC="${SHIM_ROOT}/pkgconfig"
SHIM_LIB="${SHIM_ROOT}/lib"

# If the real 4.0 packages are present, nothing to do.
if pkg-config --exists "webkit2gtk-4.0" 2>/dev/null; then
    echo "webkit2gtk-4.0 already available; no shim needed."
    return 0 2>/dev/null || exit 0
fi

if [ ! -f "${SYS_PC}/webkit2gtk-4.1.pc" ]; then
    echo "ERROR: webkit2gtk-4.1 not found. Install it first:" >&2
    echo "    sudo apt install libwebkit2gtk-4.1-dev libsoup2.4-dev" >&2
    return 1 2>/dev/null || exit 1
fi

mkdir -p "${SHIM_PC}" "${SHIM_LIB}"

# 4.0-named .pc files that resolve to the real 4.1 headers/libs.
for n in webkit2gtk javascriptcoregtk webkit2gtk-web-extension; do
    sed -e 's/Requires:\(.*\)javascriptcoregtk-4\.1/Requires:\1javascriptcoregtk-4.0/' \
        "${SYS_PC}/${n}-4.1.pc" > "${SHIM_PC}/${n}-4.0.pc"
done

# The *-sys crates hardcode `-lwebkit2gtk-4.0` / `-ljavascriptcoregtk-4.0`,
# independent of pkg-config, so provide dev symlinks with those exact names.
ln -sf "${SYS_LIB}/libwebkit2gtk-4.1.so"        "${SHIM_LIB}/libwebkit2gtk-4.0.so"
ln -sf "${SYS_LIB}/libjavascriptcoregtk-4.1.so" "${SHIM_LIB}/libjavascriptcoregtk-4.0.so"

# webkit2gtk-4.1 pulls in libsoup-3.0, but Tauri 1's soup2-sys crate links
# libsoup-2.4. Loading both libsoup2 and libsoup3 in one process aborts at
# runtime. The binary only references soup_message_headers_append /
# soup_message_headers_get_type, which both exist in libsoup-3.0, so point
# `-lsoup-2.4` at libsoup-3.0: the produced binary then needs ONLY libsoup-3.0.
# (Searched before the default lib path, so it overrides the real libsoup-2.4.so.)
ln -sf "${SYS_LIB}/libsoup-3.0.so" "${SHIM_LIB}/libsoup-2.4.so"

export PKG_CONFIG_PATH="${SHIM_PC}:${PKG_CONFIG_PATH:-}"
export RUSTFLAGS="-L ${SHIM_LIB} ${RUSTFLAGS:-}"

echo "webkit 4.0 -> 4.1 shim ready under ${SHIM_ROOT}"
echo "  PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
echo "  RUSTFLAGS=${RUSTFLAGS}"
echo "Now run:  make configurator"
