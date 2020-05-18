#!/bin/bash

MACHINE="qemuriscv64"
SDKMACHINE="x86_64"
CONFFILE="conf/auto.conf"
BITBAKEIMAGE="demo-coreip-minimal"

echo "Init OpenEmbedded"
. ./openembedded-core/oe-init-build-env ./build ./bitbake

if [ -e $CONFFILE ]; then
echo "Your build directory already has local configuration file!"
echo "If you want to start from scratch remove old build directory:"
echo ""
echo "    rm -rf $PWD"
echo ""
else
echo "Adding layers"
bitbake-layers add-layer ../meta-openembedded/meta-oe
bitbake-layers add-layer ../meta-openembedded/meta-perl
bitbake-layers add-layer ../meta-openembedded/meta-python
bitbake-layers add-layer ../meta-openembedded/meta-initramfs
bitbake-layers add-layer ../meta-openembedded/meta-filesystems
bitbake-layers add-layer ../meta-openembedded/meta-networking
#bitbake-layers add-layer ../meta-openembedded/meta-multimedia
#bitbake-layers add-layer ../meta-openembedded/meta-webserver
#bitbake-layers add-layer ../meta-openembedded/meta-gnome
#bitbake-layers add-layer ../meta-openembedded/meta-xfce
bitbake-layers add-layer ../meta-riscv
bitbake-layers add-layer ../meta-sifive

echo "Creating auto.conf"
cat <<EOF > $CONFFILE
MACHINE ?= "${MACHINE}"
DL_DIR ?= "/home/sifive/fusdk/downloads"
SSTATE_DIR ?= "/home/sifive/fusdk/sstate-cache"
SDKMACHINE ?= "${SDKMACHINE}"
USER_CLASSES ?= "buildstats buildhistory buildstats-summary image-mklibs image-prelink"
require conf/distro/include/no-static-libs.inc
require conf/distro/include/yocto-uninative.inc
require conf/distro/include/security_flags.inc
INHERIT += "uninative"
DISTRO_FEATURES_append = " largefile opengl ptest multiarch pam systemd vulkan "
DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"
VIRTUAL-RUNTIME_init_manager = "systemd"
HOSTTOOLS_NONFATAL_append = " ssh"
# Disable broken bbappend in meta-riscv layer
BBMASK += "openssl_1.1.1e.bbappend"
# We use NetworkManager instead
PACKAGECONFIG_remove_pn-systemd = "networkd"
# Disable security flags for bootloaders
# Security flags incl. smatch protector which is not supported in these packages
SECURITY_CFLAGS_pn-freedom-u540-c000-bootloader = ""
SECURITY_LDFLAGS_pn-freedom-u540-c000-bootloader = ""
SECURITY_CFLAGS_pn-opensbi = ""
SECURITY_LDFLAGS_pn-opensbi = ""
EOF
fi

echo "---------------------------------------------------"
echo "MACHINE=${MACHINE} bitbake ${BITBAKEIMAGE}"
echo "---------------------------------------------------"
echo ""
echo "Buildable machine info"
echo "---------------------------------------------------"
echo "* freedom-u540: The SiFive HiFive Unleashed board"
echo "* qemuriscv64: The 64-bit RISC-V machine"
echo "---------------------------------------------------"
