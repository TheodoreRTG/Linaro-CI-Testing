#!/bin/bash

set -ex

git config --global user.email "ci_notify@linaro.org"
git config --global user.name "Linaro CI"

if ! sudo DEBIAN_FRONTEND=noninteractive apt-get -q=2 update; then
  echo "INFO: apt update error - try again in a moment"
  sleep 15
  sudo DEBIAN_FRONTEND=noninteractive apt-get -q=2 update || true
fi
pkg_list="python-pip"
if ! sudo DEBIAN_FRONTEND=noninteractive apt-get -q=2 install -y ${pkg_list}; then
  echo "INFO: apt install error - try again in a moment"
  sleep 15
  sudo DEBIAN_FRONTEND=noninteractive apt-get -q=2 install -y ${pkg_list}
fi

# Install ruamel.yaml
pip install --user --force-reinstall ruamel.yaml

git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9
git clone --depth=1 https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86
export PATH=${PWD}/aarch64-linux-android-4.9/bin/:${PWD}/linux-x86/${TOOLCHAIN}/bin/:${PATH}

git clone --depth=1 https://android.googlesource.com/kernel/configs

export ANDROID_VERSION=$(echo $REFERENCE_BUILD_URL | awk -F"/" '{print$(NF-1)}')

if echo "$ANDROID_VERSION" | grep aosp-master ; then
    CMD="androidboot.console=ttyFIQ0 androidboot.hardware=hikey firmware_class.path=/vendor/firmware efi=noruntime printk.devkmsg=on buildvariant=userdebug  overlay_mgr.overlay_dt_entry=hardware_cfg_enable_android_fstab"
else
    CMD="androidboot.console=ttyFIQ0 androidboot.hardware=hikey firmware_class.path=/system/etc/firmware efi=noruntime printk.devkmsg=on buildvariant=userdebug"
fi

mkdir -p out
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-android-
ARCH=arm64 scripts/kconfig/merge_config.sh arch/arm64/configs/hikey_defconfig configs/${CONFIG_FRAGMENTS_PATH}/android-base.cfg configs/${CONFIG_FRAGMENTS_PATH}/android-base-arm64.cfg
cp .config out/defconfig
make ARCH=arm64 CC=clang HOSTCC=clang -j$(nproc) -s Image.gz-dtb

wget -q https://android-git.linaro.org/platform/system/core.git/plain/mkbootimg/mkbootimg -O mkbootimg
wget -q ${REFERENCE_BUILD_URL}/ramdisk.img -O ramdisk.img

python mkbootimg \
  --kernel ${PWD}/arch/arm64/boot/Image.gz-dtb \
  --cmdline console="${CMD}" \
  --os_version O \
  --os_patch_level 2016-11-05 \
  --ramdisk ramdisk.img \
  --output out/boot.img
xz out/boot.img

rm -rf configs