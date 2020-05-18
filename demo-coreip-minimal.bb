DESCRIPTION = "SiFive RISC-V Core IP Demo Minimal Linux image"

IMAGE_FEATURES += "\
    ssh-server-dropbear"

IMAGE_INSTALL = "\
    packagegroup-core-boot \
    ${CORE_IMAGE_EXTRA_INSTALL} \
    "

IMAGE_INSTALL_append_freedom-u540 = "\
    unleashed-udev-rules \
    "

inherit core-image extrausers

EXTRA_USERS_PARAMS = "usermod -P sifive root;"
