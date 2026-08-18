#!/bin/bash
# build_vol_write.sh v3 - compile k60_vol_write.ko matched to the phone kernel.
#
# Phone kernel: 5.10.136-android12-9-00003-g8970630c07cd-ab9368044 (official GKI,
# clang 12.0.5 r416183b). To match vermagic+CRC we need:
#   1. source commit  : g8970630c07cd  (android12-5.10 branch)
#   2. LOCALVERSION   : -g8970630c07cd-ab9368044 (git-scm suffix)
#   3. toolchain      : clang-r416183b (same as official build)
#   4. config         : optionally pulled from phone via adb (--with-config)
#
# Usage:  bash build_vol_write.sh [--with-config]
#   --with-config : adb-pull /proc/config.gz from the phone first, so the
#                   kernel .config matches byte-for-byte (CRC guaranteed).
set -e

SRC_COMMIT="g8970630c07cd"
LOCALV="-g8970630c07cd-ab9368044"
KDIR="/tmp/opencode/gki136"
TC="/tmp/opencode/ddk/clang-r416183b"
REPO_RAW="https://raw.githubusercontent.com/caogenfunan123/battery-unlock-tools/main"
WITH_CONFIG=0
[ "$1" = "--with-config" ] && WITH_CONFIG=1

echo '[1/5] checking environment...'
command -v curl >/dev/null 2>&1 || { echo 'ERR: no curl'; exit 1; }
[ -d "$KDIR" ] || { echo "ERR: kernel tree not at $KDIR"; exit 1; }
[ -x "$TC/bin/clang" ] || { echo "ERR: toolchain not at $TC (check /tmp/opencode/ddk/)"; exit 1; }
if [ "$WITH_CONFIG" = "1" ]; then
  command -v adb >/dev/null 2>&1 || { echo 'ERR: --with-config needs adb'; exit 1; }
  adb devices | grep -q 'device$' || { echo 'ERR: phone not connected'; exit 1; }
fi

echo '[2/5] aligning source commit...'
HEAD=$(git -C "$KDIR" log -1 --format=%H 2>/dev/null || echo none)
echo "  tree HEAD = $HEAD"
if [ "${HEAD:0:12}" != "$SRC_COMMIT" ]; then
  echo "  HEAD != $SRC_COMMIT, trying to fetch/checkout..."
  git -C "$KDIR" remote add google https://android.googlesource.com/kernel/common 2>/dev/null || true
  if git -C "$KDIR" cat-file -e "$SRC_COMMIT^{commit}" 2>/dev/null; then
    git -C "$KDIR" checkout -q "$SRC_COMMIT"
    echo "  checked out $SRC_COMMIT (already in repo)"
  else
    echo "  fetching android12-5.10 (first time may be large)..."
    git -C "$KDIR" fetch --quiet google android12-5.10
    git -C "$KDIR" checkout -q FETCH_HEAD
    git -C "$KDIR" checkout -q "$SRC_COMMIT" 2>/dev/null || {
      echo 'WARN: commit not found after fetch.';
      echo '  Use: git fetch --depth=1000 google android12-5.10 && git checkout $SRC_COMMIT'
    }
  fi
fi

echo '[3/5] preparing build dir & source...'
rm -rf /tmp/k60build && mkdir -p /tmp/k60build
curl -fkSL -o /tmp/k60build/k60_vol_write.c "$REPO_RAW/kernel/k60_vol_write.c"
wc -c /tmp/k60build/k60_vol_write.c
cat > /tmp/k60build/Kbuild <<'EOF'
obj-m := k60_vol_write.o

KDIR ?= /tmp/opencode/gki136
TOOLCHAIN ?= /tmp/opencode/ddk/clang-r416183b

CC := $(TOOLCHAIN)/bin/clang
LD := $(TOOLCHAIN)/bin/ld.lld
NM := $(TOOLCHAIN)/bin/llvm-nm
OBJCOPY := $(TOOLCHAIN)/bin/llvm-objcopy
OBJDUMP := $(TOOLCHAIN)/bin/llvm-objdump
READELF := $(TOOLCHAIN)/bin/llvm-readelf
AR := $(TOOLCHAIN)/bin/llvm-ar

all:
	$(MAKE) ARCH=arm64 CC=$(CC) LD=$(LD) NM=$(NM) OBJCOPY=$(OBJCOPY) OBJDUMP=$(OBJDUMP) READELF=$(READELF) AR=$(AR) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) ARCH=arm64 -C $(KDIR) M=$(CURDIR) clean
EOF

if [ "$WITH_CONFIG" = "1" ]; then
  echo '  (-with-config) pulling phone config.gz...'
  adb pull /proc/config.gz /tmp/k60build/config.gz >/dev/null
  zcat /tmp/k60build/config.gz > "$KDIR/.config"
  (cd "$KDIR" && make O=out ARCH=arm64 olddefconfig >/dev/null 2>&1) || true
  echo '  phone config installed into kernel tree'
fi

echo '[4/5] compiling with LOCALVERSION="$LOCALV" ...'
cd /tmp/k60build && make -C "$KDIR" M=/tmp/k60build modules LOCALVERSION="$LOCALV" CONFIG_LOCALVERSION_AUTO=n

echo '[5/5] verifying vermagic...'
modinfo /tmp/k60build/k60_vol_write.ko 2>/dev/null | grep vermagic || \
  strings /tmp/k60build/k60_vol_write.ko | grep -m1 -E '5\.10\.136' || true
echo ''
echo '============================================='
echo ' EXPECTED: 5.10.136-android12-9-00003-g8970630c07cd-ab9368044'
echo '           SMP preempt mod_unload modversions aarch64'
echo '============================================='
echo 'If vermagic matches above, send ko to phone:'
echo '  adb push /tmp/k60build/k60_vol_write.ko /data/adb/modules/k60_battery_unlock/kernel/'
echo 'or copy it over - agent will insmod + verify.'