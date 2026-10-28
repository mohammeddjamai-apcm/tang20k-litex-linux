# tang20k-litex-linux : LiteX SoC + OpenSBI + Buildroot Linux for Sipeed Tang Primer 20K
SHELL := /bin/bash
.DEFAULT_GOAL := help

-include config.mk
include config.mk.example

ACTIVATE    = $(if $(wildcard $(VENV)/bin/activate),. $(VENV)/bin/activate &&,)
BR2_EXT_ARG = $(if $(BR2_EXTERNAL),BR2_EXTERNAL=$(BR2_EXTERNAL),)

CSR    = $(SOC_OUT)/csr.json
DTB    = $(IMG_DIR)/rv32.dtb
SBI    = $(IMG_DIR)/opensbi.bin
KIMG   = $(IMG_DIR)/Image
ROOTFS = $(IMG_DIR)/rootfs.cpio
BOOT   = $(IMG_DIR)/boot.json

.PHONY: help check setup setup_venv setup_litex setup_buildroot setup_opensbi setup_lol versions \
        all gen_verilog gen_fpga regen_fpga flash flash_spi \
        build dtb opensbi linux bootjson boot_linux \
        br_menuconfig br_savedefconfig clean

help:
	@echo "First time:   make check   (what is installed / missing)"
	@echo "              make setup   (download missing deps, skips existing ones)"
	@echo ""
	@echo "FPGA:         make gen_verilog   LiteX -> Verilog only"
	@echo "              make gen_fpga      LiteX -> Verilog -> Gowin (gw_sh) -> .fs"
	@echo "              make regen_fpga    delete the .fs and rebuild it"
	@echo "              make flash         load bitstream to SRAM (temporary)"
	@echo "              make flash_spi     write bitstream to SPI flash (permanent)"
	@echo "Linux:        make build         DTB + OpenSBI + Buildroot + boot.json"
	@echo "              make boot_linux    upload images with litex_term and boot"
	@echo "Everything:   make all           gen_fpga + build"
	@echo "Buildroot:    make br_menuconfig | br_savedefconfig"
	@echo "Misc:         make versions | clean (only removes ./out)"

check:
	@bash scripts/check_tools.sh

all: gen_fpga build

# ----------------------------- setup ---------------------------------------
setup: setup_venv setup_litex setup_buildroot setup_opensbi setup_lol
	@bash scripts/check_tools.sh || true

setup_venv:
	@[ -d $(VENV) ] || python3 -m venv $(VENV)

setup_litex:
	@if [ -d $(LITEX_DIR)/litex ]; then echo "LiteX found in $(LITEX_DIR), skipping"; else \
	  mkdir -p $(LITEX_DIR) && cd $(LITEX_DIR) && \
	  wget -q https://raw.githubusercontent.com/enjoy-digital/litex/master/litex_setup.py && \
	  $(ACTIVATE) python3 litex_setup.py --init --install --config=full; fi

setup_buildroot:
	@if [ -d $(BUILDROOT_DIR) ]; then echo "Buildroot found, skipping"; else \
	  git clone https://github.com/buildroot/buildroot $(BUILDROOT_DIR) && \
	  git -C $(BUILDROOT_DIR) checkout $(BUILDROOT_REF); fi

setup_lol:
	@if [ -d $(LOL_DIR) ]; then echo "linux-on-litex-vexriscv found, skipping"; else \
	  git clone https://github.com/litex-hub/linux-on-litex-vexriscv $(LOL_DIR); fi

setup_opensbi:
	@if [ -d $(OPENSBI_DIR) ]; then echo "OpenSBI found, skipping"; else \
	  git clone https://github.com/riscv-software-src/opensbi $(OPENSBI_DIR) && \
	  git -C $(OPENSBI_DIR) checkout $(OPENSBI_REF); fi

versions:
	@echo "buildroot: $$(git -C $(BUILDROOT_DIR) describe --always 2>/dev/null || echo unknown)"
	@echo "opensbi:   $$(git -C $(OPENSBI_DIR) describe --always 2>/dev/null || echo unknown)"
	@for d in $(LITEX_DIR)/*/; do [ -d $$d/.git ] && echo "$$(basename $$d): $$(git -C $$d rev-parse --short HEAD)"; done; true
	@command -v gw_sh >/dev/null 2>&1 && echo "gowin: gw_sh at $$(command -v gw_sh)" || echo "gowin: not in PATH"
	@$(CROSS)gcc --version 2>/dev/null | head -1 || true

# ----------------------------- FPGA ----------------------------------------
gen_verilog:
	$(ACTIVATE) $(SOC_CMD) $(SOC_ARGS) --output-dir $(SOC_OUT) --toolchain gowin --build --no-compile-gateware

gen_fpga: $(BIT)

$(BIT):
	@command -v gw_sh >/dev/null 2>&1 || { \
	  echo "gw_sh not found. Install Gowin EDA and add its IDE/bin to PATH."; \
	  echo "Or: make gen_verilog, synthesise in Gowin anywhere, then set BIT= in config.mk"; exit 1; }
	$(ACTIVATE) $(SOC_CMD) $(SOC_ARGS) --output-dir $(SOC_OUT) --toolchain gowin --build
	@test -f $(BIT) || { echo "Build done but $(BIT) is missing."; \
	  echo "Find the .fs under $(SOC_OUT)/gateware and set BIT= in config.mk"; exit 1; }

regen_fpga:
	@command -v gw_sh >/dev/null 2>&1 || { echo "gw_sh not found, refusing to delete $(BIT)"; exit 1; }
	rm -f $(BIT)
	$(MAKE) gen_fpga

flash: $(BIT)
	openFPGALoader -b $(FPGA_BOARD) $(BIT)

flash_spi: $(BIT)
	openFPGALoader -b $(FPGA_BOARD) -f $(BIT)

# ----------------------------- Linux ---------------------------------------
build: dtb opensbi linux bootjson

dtb: $(DTB)

$(CSR):
	$(MAKE) gen_verilog

$(DTB): $(CSR)
	@mkdir -p $(IMG_DIR)
	$(ACTIVATE) DTS_SRC="$(DTS_SRC)" DTS_ARGS="$(DTS_ARGS)" bash scripts/gen_dtb.sh $(CSR) $@

opensbi: $(SBI)

$(SBI):
	@mkdir -p $(IMG_DIR)
	$(MAKE) -C $(OPENSBI_DIR) CROSS_COMPILE=$(CROSS) PLATFORM=litex/vexriscv \
	    PLATFORM_RISCV_XLEN=32 $(OPENSBI_ARGS) O=$(SBI_OUT)
	cp $(SBI_OUT)/platform/litex/vexriscv/firmware/fw_jump.bin $@

linux: $(BR_OUT)/.config
	$(MAKE) -C $(BR_OUT) -j$(JOBS)
	@mkdir -p $(IMG_DIR)
	cp $(BR_OUT)/images/Image $(KIMG)
	cp $(BR_OUT)/images/rootfs.cpio $(ROOTFS)

# Only configures when there is no .config yet, so menuconfig changes are not lost.
$(BR_OUT)/.config:
	@test -d "$(BR2_EXTERNAL)" || { echo "BR2_EXTERNAL not found: $(BR2_EXTERNAL) (run make setup)"; exit 1; }
	$(MAKE) -C $(BUILDROOT_DIR) O=$(BR_OUT) $(BR2_EXT_ARG) \
	    $(if $(BR_DEFCONFIG),BR2_DEFCONFIG=$(BR_DEFCONFIG) defconfig,$(BR_DEFCONFIG_NAME))

bootjson:
	@mkdir -p $(IMG_DIR)
	@printf '{\n  "Image": "%s",\n  "rv32.dtb": "%s",\n  "rootfs.cpio": "%s",\n  "opensbi.bin": "%s"\n}\n' \
	  $(ADDR_KERNEL) $(ADDR_DTB) $(ADDR_ROOTFS) $(ADDR_OPENSBI) > $(BOOT)
	@echo "wrote $(BOOT)"

boot_linux: build
	$(ACTIVATE) litex_term $(UART) --safe --images=$(BOOT)

br_menuconfig: $(BR_OUT)/.config
	$(MAKE) -C $(BR_OUT) menuconfig

# Only needed if you customise Buildroot: saves your config into the repo.
br_savedefconfig: $(BR_OUT)/.config
	$(MAKE) -C $(BR_OUT) savedefconfig BR2_DEFCONFIG=$(CURDIR)/buildroot/my_defconfig

clean:
	rm -rf $(CURDIR)/out
