#!/usr/bin/env bash
# Reports which tools are present. Exit code 1 if a required one is missing.
miss=0
chk() { # name, required(1/0), hint
  if command -v "$1" >/dev/null 2>&1; then printf "  OK       %s\n" "$1"
  else printf "  MISSING  %-24s %s\n" "$1" "$3"; [ "$2" = 1 ] && miss=1; fi
  return 0
}
echo "Required:"
chk git 1 "apt install git"
chk python3 1 "apt install python3 python3-venv"
chk make 1 "apt install build-essential"
chk dtc 1 "apt install device-tree-compiler"
chk riscv64-unknown-elf-gcc 1 "apt install gcc-riscv64-unknown-elf (or set CROSS=)"
chk openFPGALoader 1 "apt install openfpgaloader"
echo "For gen_fpga (proprietary, install yourself):"
chk gw_sh 0 "Gowin EDA: add <gowin>/IDE/bin to PATH"
echo "Inside the LiteX venv (make setup):"
chk litex_term 0 "make setup"
chk litex_json2dts_linux 0 "make setup"
exit $miss
