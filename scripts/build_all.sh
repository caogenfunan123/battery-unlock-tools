#!/bin/bash
# build_all.sh - compile ALL 5 k60 kprobe modules, vermagic-matched to the phone.
# Phone kernel: 5.10.136-android12-9-00003-g8970630c07cd-ab9368044 (clang 12.0.5 r416183b)
# Requirement: kernel tree at /tmp/opencode/gki136 checked out at commit g8970630c07cd,
#              toolchain at /tmp/opencode/ddk/clang-r416183b
#
# Usage:
#   bash build_all.sh               # build all (sources auto-downloaded from repo)
#   bash build_all.sh --with-config # also pull phone config.gz (CRC guarantee)
set -e

SRC_COMMIT="g8970630c07cd"
LOCALV="-g8970630c07cd-ab9368044"
KDIR="/tmp/opencode/gki136"
TC="/tmp/opencode/ddk/clang-r416183b"
REPO_RAW="https://raw.githubusercontent.com/caogenfunan123/battery-unlock-tools/main"
MODULES="k60_vol_write k60_volt_probe k60_batt_probe k60_fcc_probe k60_fcc_unlock"
WITH_CONFIG=0
[ "$1" = "--with-config" ] && WITH_CONFIG=1

echo '[1/6] checking environment...'
command -v curl >/dev/null 2>&1 || { echo "ERR: no curl on this PC"; exit 1; }
[ -d "$KDIR" ] || { echo "ERR: kernel tree not at $KDIR"; exit 1; }
[ -x "$TC/bin/clang" ] || { echo "ERR: toolchain not at $TC"; exit 1; }
if [ "$WITH_CONFIG" = "1" ]; then
  command -v adb >/dev/null 2>&1 || { echo "ERR: --with-config needs adb"; exit 1; }
  adb devices | grep -q 'device$' || { echo "ERR: phone not connected"; exit 1; }
fi

echo '[2/6] aligning source commit...'
HEAD=$(git -C "$KDIR" log -1 --format=%H 2>/dev/null || echo none)
echo "  tree HEAD = $HEAD"
if [ "${HEAD:0:12}" != "$SRC_COMMIT" ]; then
  echo "  HEAD differs, aligning..."
  git -C "$KDIR" remote add google https://android.googlesource.com/kernel/common 2>/dev/null || true
  if git -C "$KDIR" cat-file -e "$SRC_COMMIT^{commit}" 2>/dev/null; then
    git -C "$KDIR" checkout -q "$SRC_COMMIT"
    echo "  checked out $SRC_COMMIT"
  else
    echo "  fetching android12-5.10 (first time can take a while)..."
    git -C "$KDIR" fetch --quiet google android12-5.10
    git -C "$KDIR" checkout -q "$SRC_COMMIT" 2>/dev/null || {
      echo "  WARN: commit not found after fetch; try deeper fetch";
    }
  fi
fi

echo '[3/6] downloading sources from GitHub...'
rm -rf /tmp/k60build && mkdir -p /tmp/k60build
for m in $MODULES; do
  curl -fkSL -o /tmp/k60build/$m.c "$REPO_RAW/kernel/$m.c" || { echo "ERR downloading $m.c"; exit 1; }
done
wc -c /tmp/k60build/*.c | tail -6

cat > /tmp/k60build/Kbuild <<'KEOF'
obj-m := k60_vol_write.o k60_volt_probe.o k60_batt_probe.o k60_fcc_probe.o k60_fcc_unlock.o

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
KEOF

if [ "$WITH_CONFIG" = "1" ]; then
  echo "  pulling phone config..."
  adb pull /proc/config.gz /tmp/k60build/config.gz >/dev/null
  zcat /tmp/k60build/config.gz > "$KDIR/.config"
  (cd "$KDIR" && make O=out ARCH=arm64 olddefconfig >/dev/null 2>&1) || true
  echo "  phone config installed"
fi

echo '[4/6] compiling all modules...'
cd /tmp/k60build && make -C "$KDIR" M=/tmp/k60build modules LOCALVERSION="$LOCALV" CONFIG_LOCALVERSION_AUTO=n

echo '[5/6] verifying vermagic...'
for m in $MODULES; do
  echo "  --- $m ---"
  modinfo /tmp/k60build/$m.ko 2>/dev/null | grep vermagic || strings /tmp/k60build/$m.ko 2>/dev/null | grep -m1 -E '5\.10\.136' || true
done

echo '[6/6] pack & report...'
cd /tmp/k60build && tar czf k60_all_kos.tar.gz k60_*.ko
ls -la /tmp/k60build/k60_all_kos.tar.gz
echo ''
echo '============================================='
echo ' DONE. .ko files in /tmp/k60build/'
echo ' Push: adb push /tmp/k60build/k60_all_kos.tar.gz /data/local/tmp/'
echo ' or copy it to phone (WeChat/USB) - agent tests them all.'
echo ' Next on phone:'
echo '   k60_fcc_probe.ko  target_prop=120 target_value=6200000   (FCC direct write!)'
echo '   k60_volt_probe.ko target_volt=4500000                    (read-path rewrite)'
echo '============================================='