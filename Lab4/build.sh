#!/usr/bin/env bash
# Dung lai toan bo binary cua thi nghiem Process Doppelganging tu may Linux co mingw-w64.
#   sudo apt install mingw-w64      # doc dong Remove: truoc khi go Y
#   which x86_64-w64-mingw32-g++
# Chay:  bash Lab4/build.sh [thu-muc-ra]   (mac dinh ./build)
set -euo pipefail

OUT="${1:-build}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# 1. Lay source PoC vao thu muc rieng
SRC="$OUT/process_doppelganging"
if [ ! -d "$SRC" ]; then
    git clone --depth 1 https://github.com/hasherezade/process_doppelganging.git "$SRC"
fi

# 2. Sua ten header ve chu thuong: mingw phan biet hoa thuong, Windows thi khong
sed -i 's/#include <Windows.h>/#include <windows.h>/; s/#include <KtmW32.h>/#include <ktmw32.h>/' \
    "$SRC/ntddk.h" "$SRC/pe_hdrs_helper.h" "$SRC/ntdll_undoc.h" "$SRC/main.cpp" "$SRC/util.h"

# 3. Build PoC.
#    -municode la bat buoc: main.cpp dinh nghia wmain, thieu co nay se loi
#    "undefined reference to `WinMain'" luc link.
x86_64-w64-mingw32-g++ \
    "$SRC/main.cpp" "$SRC/util.cpp" "$SRC/ntdll_undoc.cpp" \
    "$SRC/pe_hdrs_helper.cpp" "$SRC/process_env.cpp" \
    -o "$OUT/process_doppelganger.exe" \
    -municode -D_WIN32_WINNT=0x0600 -DWINVER=0x0600 \
    -lktmw32 -lntdll -luserenv -static -mconsole -fpermissive -Wno-write-strings

# 4. Build payload (GUI subsystem: PoC khong set std handle nen payload console khong in duoc gi)
x86_64-w64-mingw32-gcc "$HERE/payload.c" -o "$OUT/payload.exe" -mwindows -static -O2 -s -luser32

# 5. Tu kiem
echo "--- ket qua ---"
file "$OUT/process_doppelganger.exe"
file "$OUT/payload.exe"
sha256sum "$OUT/process_doppelganger.exe" "$OUT/payload.exe"
echo "Mong doi: ca hai la 'PE32+ ... x86-64'; PoC la (console), payload la (GUI)."
echo "Neu payload ra (console) thi thieu -mwindows, chay tren victim se khong thay gi."
