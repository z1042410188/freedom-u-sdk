RISCV ?= $(CURDIR)/toolchain
PATH := $(RISCV)/bin:$(PATH)
ISA ?= rv64imafdc
ABI ?= lp64d

srcdir := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
srcdir := $(srcdir:/=)
confdir := $(srcdir)/conf
wrkdir := $(CURDIR)/work

toolchain_srcdir := $(srcdir)/riscv-gnu-toolchain
toolchain_wrkdir := $(wrkdir)/riscv-gnu-toolchain
toolchain_dest := $(CURDIR)/toolchain

buildroot_srcdir := $(srcdir)/buildroot
buildroot_initramfs_wrkdir := $(wrkdir)/buildroot_initramfs
buildroot_initramfs_tar := $(buildroot_initramfs_wrkdir)/images/rootfs.tar
buildroot_initramfs_config := $(confdir)/buildroot_initramfs_config

buildroot_initramfs_sysroot_stamp := $(wrkdir)/.buildroot_initramfs_sysroot
buildroot_initramfs_sysroot := $(wrkdir)/buildroot_initramfs_sysroot

linux_srcdir := $(srcdir)/linux
linux_wrkdir := $(wrkdir)/linux
linux_defconfig := $(confdir)/linux_defconfig

vmlinux := $(linux_wrkdir)/vmlinux
vmlinux_stripped := $(linux_wrkdir)/vmlinux-stripped

pk_srcdir := $(srcdir)/riscv-pk
pk_wrkdir := $(wrkdir)/riscv-pk
bbl := $(pk_wrkdir)/bbl
bin := $(wrkdir)/bbl.bin
hex := $(wrkdir)/bbl.hex

fesvr_srcdir := $(srcdir)/riscv-fesvr
fesvr_wrkdir := $(wrkdir)/riscv-fesvr
libfesvr := $(fesvr_wrkdir)/prefix/lib/libfesvr.so

spike_srcdir := $(srcdir)/riscv-isa-sim
spike_wrkdir := $(wrkdir)/riscv-isa-sim
spike := $(spike_wrkdir)/prefix/bin/spike

qemu_srcdir := $(srcdir)/riscv-qemu
qemu_wrkdir := $(wrkdir)/riscv-qemu
qemu := $(qemu_wrkdir)/prefix/bin/qemu-system-riscv64

rootfs := $(wrkdir)/rootfs.bin

target := riscv64-unknown-linux-gnu

.PHONY: all
all: $(hex)
	@echo
	@echo This image has been generated for an ISA of $(ISA) and an ABI of $(ABI)
	@echo Find the SD-card image in work/bbl.bin
	@echo Program it with: dd if=work/bbl.bin of=/dev/sd-your-card bs=1M
	@echo

$(toolchain_dest)/bin/$(target)-gcc: $(toolchain_srcdir)
	mkdir -p $(toolchain_wrkdir)
	cd $(toolchain_wrkdir); $(toolchain_srcdir)/configure \
		--prefix=$(toolchain_dest) \
		--with-arch=$(ISA) \
		--with-abi=$(ABI) \
		--enable-linux
	$(MAKE) -C $(toolchain_wrkdir)
	sed 's/^#define LINUX_VERSION_CODE.*/#define LINUX_VERSION_CODE 263682/' -i $(toolchain_dest)/sysroot/usr/include/linux/version.h

$(buildroot_initramfs_wrkdir)/.config: $(buildroot_srcdir)
	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	cp $(buildroot_initramfs_config) $@
	$(MAKE) -C $< RISCV=$(RISCV) PATH=$(PATH) O=$(buildroot_initramfs_wrkdir) olddefconfig

$(buildroot_initramfs_tar): $(buildroot_srcdir) $(buildroot_initramfs_wrkdir)/.config $(RISCV)/bin/$(target)-gcc $(buildroot_initramfs_config)
	$(MAKE) -C $< RISCV=$(RISCV) PATH=$(PATH) O=$(buildroot_initramfs_wrkdir)

.PHONY: buildroot_initramfs-menuconfig
buildroot_initramfs-menuconfig: $(buildroot_srcdir)
	$(MAKE) -C $< O=$(buildroot_initramfs_wrkdir) menuconfig

$(buildroot_initramfs_sysroot_stamp): $(buildroot_initramfs_tar)
	mkdir -p $(buildroot_initramfs_sysroot)
	tar -xpf $< -C $(buildroot_initramfs_sysroot) --exclude ./dev --exclude ./usr/share/locale
	touch $@

$(linux_wrkdir)/.config: $(linux_defconfig) $(linux_srcdir)
	mkdir -p $(dir $@)
	cp -p $< $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
	echo $(ISA)
	echo $(filter rv32%,$(ISA))
ifeq (,$(filter rv%c,$(ISA)))
	sed 's/^.*CONFIG_RISCV_ISA_C.*$$/CONFIG_RISCV_ISA_C=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
endif
ifeq ($(ISA),$(filter rv32%,$(ISA)))
	sed 's/^.*CONFIG_ARCH_RV32I.*$$/CONFIG_ARCH_RV32I=y/' -i $@
	sed 's/^.*CONFIG_ARCH_RV64I.*$$/CONFIG_ARCH_RV64I=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
endif

$(vmlinux): $(linux_srcdir) $(linux_wrkdir)/.config $(buildroot_initramfs_sysroot_stamp)
	$(MAKE) -C $< O=$(linux_wrkdir) \
		CONFIG_INITRAMFS_SOURCE="$(confdir)/initramfs.txt $(buildroot_initramfs_sysroot)" \
		CONFIG_INITRAMFS_ROOT_UID=$(shell id -u) \
		CONFIG_INITRAMFS_ROOT_GID=$(shell id -g) \
		ARCH=riscv \
		vmlinux

$(vmlinux_stripped): $(vmlinux)
	$(target)-strip -o $@ $<

.PHONY: linux-menuconfig
linux-menuconfig: $(linux_wrkdir)/.config
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv menuconfig savedefconfig

$(bbl): $(pk_srcdir) $(vmlinux_stripped)
	rm -rf $(pk_wrkdir)
	mkdir -p $(pk_wrkdir)
	cd $(pk_wrkdir) && $</configure \
		--host=$(target) \
		--with-payload=$(vmlinux_stripped) \
		--enable-logo --enable-print-device-tree \
		--with-logo=$(abspath conf/sifive_logo.txt)
	CFLAGS="-mabi=$(ABI) -march=$(ISA)" $(MAKE) -C $(pk_wrkdir)

$(bin): $(bbl)
	$(target)-objcopy -S -O binary --change-addresses -0x80000000 $< $@

$(hex):	$(bin)
	xxd -c1 -p $< > $@

$(libfesvr): $(fesvr_srcdir)
	rm -rf $(fesvr_wrkdir)
	mkdir -p $(fesvr_wrkdir)
	mkdir -p $(dir $@)
	cd $(fesvr_wrkdir) && $</configure \
		--prefix=$(dir $(abspath $(dir $@)))
	$(MAKE) -C $(fesvr_wrkdir)
	$(MAKE) -C $(fesvr_wrkdir) install
	touch -c $@

$(spike): $(spike_srcdir) $(libfesvr)
	rm -rf $(spike_wrkdir)
	mkdir -p $(spike_wrkdir)
	mkdir -p $(dir $@)
	cd $(spike_wrkdir) && $</configure \
		--prefix=$(dir $(abspath $(dir $@))) \
		--with-fesvr=$(dir $(abspath $(dir $(libfesvr))))
	$(MAKE) -C $(spike_wrkdir)
	$(MAKE) -C $(spike_wrkdir) install
	touch -c $@

$(qemu): $(qemu_srcdir)
	rm -rf $(qemu_wrkdir)
	mkdir -p $(qemu_wrkdir)
	mkdir -p $(dir $@)
	cd $(qemu_wrkdir) && $</configure \
		--prefix=$(dir $(abspath $(dir $@))) \
		--target-list=riscv64-softmmu
	$(MAKE) -C $(qemu_wrkdir)
	$(MAKE) -C $(qemu_wrkdir) install
	touch -c $@

$(rootfs):
	truncate --size=1G $@
	mkfs.ext4 $@

.PHONY: buildroot_initramfs_sysroot vmlinux bbl
buildroot_initramfs_sysroot: $(buildroot_initramfs_sysroot)
vmlinux: $(vmlinux)
bbl: $(bbl)

.PHONY: clean
clean:
	rm -rf -- $(wrkdir) $(toolchain_dest)

.PHONY: sim
sim: $(spike) $(bbl)
	$(spike) --isa=$(ISA) -p4 $(bbl)

.PHONY: qemu
qemu: $(qemu) $(bbl) $(rootfs)
	$(qemu) -nographic -machine virt -kernel $(bbl) \
		-drive file=$(rootfs),format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0
