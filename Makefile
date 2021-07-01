# Makefile for RISC-V toolchain; run 'make help' for usage.

XLEN     := 64
ROOT     := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RISCV    ?= $(PWD)/install$(XLEN)
DEST     := $(abspath $(RISCV))
PATH     := $(DEST)/bin:$(PATH)

TOOLCHAIN_PREFIX := $(ROOT)/buildroot/output/host/bin/riscv$(XLEN)-buildroot-linux-gnu-
CC          := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY     := $(TOOLCHAIN_PREFIX)objcopy
OBJDUMP     := $(TOOLCHAIN_PREFIX)objdump
READELF     := $(TOOLCHAIN_PREFIX)readelf

NR_CORES := $(shell nproc)

# default configure flags
fesvr-co              = --prefix=$(RISCV) --target=riscv$(XLEN)-buildroot-linux-gnu
tests-co              = --prefix=$(RISCV)/target

# specific flags and rules for 32 / 64 version
ifeq ($(XLEN), 32)
isa-sim-co            = --prefix=$(RISCV) --enable-commitlog --with-isa=RV32IMA --with-priv=MSU 
gnu-toolchain-co-fast = --prefix=$(RISCV) --with-arch=rv32ima --with-abi=ilp32 --with-cmodel=medany --disable-gdb# no multilib for fast
pk-co                 = --prefix=$(RISCV) --host=riscv$(XLEN)-buildroot-linux-gnu CC=$(CC) OBJDUMP=$(OBJDUMP) OBJCOPY=$(OBJCOPY) --enable-32bit
else
isa-sim-co            = --prefix=$(RISCV) --enable-commitlog --with-fesvr=$(DEST)
gnu-toolchain-co-fast = --prefix=$(RISCV) --disable-gdb# no multilib for fast
pk-co                 = --prefix=$(RISCV) --host=riscv$(XLEN)-buildroot-linux-gnu CC=$(CC) OBJDUMP=$(OBJDUMP) OBJCOPY=$(OBJCOPY)
endif

# default make flags
fesvr-mk                = -j$(NR_CORES)
isa-sim-mk              = -j$(NR_CORES)
gnu-toolchain-libc-mk   = linux -j$(NR_CORES)
pk-mk 					= -j$(NR_CORES)
tests-mk         		= -j$(NR_CORES)

# linux image
buildroot_defconfig = configs/buildroot$(XLEN)_defconfig
linux_defconfig = configs/linux$(XLEN)_defconfig
busybox_defconfig = configs/busybox$(XLEN).config

install-dir:
	mkdir -p $(RISCV)

$(RISCV)/bin/riscv$(XLEN)-unknown-elf-gcc: gnu-toolchain-newlib
	cd riscv-gnu-toolchain/build;\
	make -j$(NR_CORES);\
	cd $(ROOT)

gnu-toolchain-newlib: install-dir
	mkdir -p riscv-gnu-toolchain/build
	cd riscv-gnu-toolchain/build;\
	../configure --prefix=$(RISCV);\
	cd $(ROOT)

gnu-toolchain-libc: $(CC)

gnu-toolchain-no-multilib: install-dir
	mkdir -p riscv-gnu-toolchain/build
	cd riscv-gnu-toolchain/build;\
	../configure $(gnu-toolchain-co-fast);\
	cd $(ROOT)

fesvr: install-dir $(CC)
	mkdir -p riscv-fesvr/build
	cd riscv-fesvr/build;\
	../configure $(fesvr-co);\
	make $(fesvr-mk);\
	make install;\
	cd $(ROOT)

isa-sim: install-dir $(CC) 
	mkdir -p riscv-isa-sim/build
	cd riscv-isa-sim/build;\
	../configure $(isa-sim-co);\
	make $(isa-sim-mk);\
	make install;\
	cd $(ROOT)

tests: install-dir $(CC)
	mkdir -p riscv-tests/build
	cd riscv-tests/build;\
	autoconf;\
	../configure $(tests-co);\
	make $(tests-mk);\
	make install;\
	cd $(ROOT)

pk: install-dir $(CC)
	mkdir -p riscv-pk/build
	cd riscv-pk/build;\
	../configure $(pk-co);\
	make $(pk-mk);\
	make install;\
	cd $(ROOT)

all: $(CC) isa-sim

$(CC): $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig)
	make -C buildroot defconfig BR2_DEFCONFIG=../$(buildroot_defconfig)
	make -C buildroot host-gcc-final

# benchmark for the cache subsystem
cachetest: $(CC)
	cd ./cachetest/ && $(CC) cachetest.c -o cachetest.elf
	cp ./cachetest/cachetest.elf rootfs/

# cool command-line tetris
rootfs/tetris: $(CC)
	cd ./vitetris/ && make clean && ./configure CC=$(CC) && make
	cp ./vitetris/tetris $@

vmlinux: $(CC) cachetest rootfs/tetris
	mkdir -p build
	make -C buildroot
	cp buildroot/output/images/vmlinux build/vmlinux
	cp build/vmlinux $@

bbl: vmlinux
	cd build && ../riscv-pk/configure --host=riscv$(XLEN)-buildroot-linux-gnu READELF=$(READELF) OBJCOPY=$(OBJCOPY) CC=$(CC) OBJDUMP=$(OBJDUMP) --with-payload=vmlinux --enable-logo --with-logo=../configs/logo.txt
	make -C build
	cp build/bbl $@

bbl_binary: bbl
	$(OBJCOPY) -O binary $< $@

clean:
	rm -rf $(RISCV)/bbl.bin $(RISCV)/bbl_binary $(RISCV)/bbl vmlinux bbl riscv-pk/build/vmlinux riscv-pk/build/bbl cachetest/*.elf rootfs/tetris
	make -C buildroot clean

bbl.bin: bbl
	$(OBJCOPY) -S -O binary --change-addresses -0x80000000 $< $@

$(RISCV)/bbl: bbl
	cp $< $@

$(RISCV)/bbl.bin: bbl.bin
	cp $< $@

$(RISCV)/bbl_binary: bbl_binary
	cp $< $@

images: $(RISCV)/bbl $(RISCV)/bbl.bin $(RISCV)/bbl_binary

clean-all: clean
	rm -rf $(RISCV) riscv-fesvr/build riscv-isa-sim/build riscv-gnu-toolchain/build riscv-tests/build riscv-pk/build

.PHONY: cachetest rootfs/tetris

help:
	@echo "usage: $(MAKE) [RISCV='<install/here>'] [tool/img] ..."
	@echo ""
	@echo "install [tool] to \$$RISCV with compiler <flag>'s"
	@echo "    where tool can be any one of:"
	@echo "        fesvr isa-sim gnu-toolchain tests pk"
	@echo ""
	@echo "build linux images for ariane"
	@echo "    build vmlinux with"
	@echo "        make vmlinux"
	@echo "    build bbl (with vmlinux) with"
	@echo "        make bbl"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only buildroot"
	@echo "        make clean"
	@echo "    Clean everything (including toolchain etc)"
	@echo "        make clean-all"
	@echo ""
	@echo "defaults:"
	@echo "    RISCV='$(DEST)'"
