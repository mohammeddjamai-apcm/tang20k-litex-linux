# tang20k-litex-linux

Linux on a RISC-V SoC (LiteX + VexRiscv SMP, RV32IMA) for the Sipeed Tang Primer 20K.
One `make` target per stage: FPGA bitstream, flash, Linux images, boot.

Status: boots to a Buildroot login on real hardware (LiteX BIOS -> OpenSBI 1.3 -> Linux 6.9).
The Makefile automation itself is new and should be treated as a starting point.

## Quick start

    git clone <this repo> && cd tang20k-litex-linux
    make check         # shows what is missing
    make setup         # downloads LiteX, Buildroot, OpenSBI, linux-on-litex-vexriscv (skips what exists)
    make gen_fpga      # LiteX -> Verilog -> Gowin -> .fs
    make flash         # SRAM (lost at power-off); flash_spi = permanent
    make build         # DTB + OpenSBI + Buildroot + boot.json
    make boot_linux    # upload over serial with litex_term

## You must install yourself

- **Gowin EDA** (proprietary, not included). Add `<gowin>/IDE/bin` to PATH so `gw_sh` works.
  No Gowin on this machine? Run `make gen_verilog`, synthesise elsewhere, set `BIT=` in `config.mk`.
- `gcc-riscv64-unknown-elf`, `device-tree-compiler`, `openFPGALoader`, `python3-venv`, `build-essential`.

## Configuration

`config.mk.example` holds the defaults (everything inside this repo).
To use your own folders, create `config.mk` (gitignored) and set only what differs:

    BUILDROOT_DIR = $(HOME)/buildroot/buildroot-2025.02.3
    BR_OUT        = $(HOME)/buildroot/output
    SOC_OUT       = $(HOME)/litex-out/tang20k
    BIT           = /path/to/linux_SoC.fs

## Notes

- Rebuilding the LiteX BIOS changes the ROM init file: **re-run Gowin afterwards** (`make regen_fpga`).
- `serial boot` is slow (about 7 KB/s). An 8 MB kernel takes about 20 minutes. SD boot is faster.
- DDR3 PHY control paths report small negative slack in Gowin timing reports; memtest and Linux are stable in testing.
- `make clean` only deletes `./out`, never your external folders.
- `make versions > docs/versions.txt` records the commits you built with.

## Buildroot config

Uses LiteX's default: `litex_vexriscv_defconfig` from the `buildroot/` external tree of
`linux-on-litex-vexriscv` (cloned by `make setup`). To use your own, set `BR_DEFCONFIG=/path/file` in `config.mk`.
