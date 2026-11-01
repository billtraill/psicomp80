# The system controller's firmware, for the PicoRV32 in soc.v.  Needs a RISC-V
# GCC (xPack riscv-none-elf-gcc 15) and ../build/fatfs (../tools/fetch.sh).
# Writes firmware.hex, the 128 KB RAM's contents for soc.v's $readmemh.
CROSS ?= riscv-none-elf-
V2 = ../../hardware_v2/firmware/src
FF = ../build/fatfs/source
CFLAGS = -march=rv32imc -mabi=ilp32 -Os -ffunction-sections -fdata-sections -Wall \
         -I. -I$(V2) -Ibuild
SRC = start.S main.c sd_spi.c pd.c $(V2)/mm57109.c $(V2)/tape.c $(V2)/storage.c $(V2)/data.c \
      build/ff.c build/ffunicode.c

firmware.hex: build/firmware.bin
	python3 ../tools/bin2hex.py $< $@ 32768

build/firmware.bin: build/firmware.elf
	$(CROSS)objcopy -O binary $< $@

build/firmware.elf: $(SRC) link.ld hw.h pd.h
	$(CROSS)gcc $(CFLAGS) -T link.ld -nostartfiles --specs=nano.specs -u _printf_float \
	  -Wl,--gc-sections -o $@ $(SRC) -lm
	$(CROSS)size $@

# FatFs's ff.h includes "ffconf.h" from its own folder, so build copies next to the v2 settings
build/ff.c build/ffunicode.c: $(FF)/ff.c $(FF)/ffunicode.c $(V2)/ffconf.h
	mkdir -p build
	cp $(FF)/ff.c $(FF)/ff.h $(FF)/ffunicode.c $(FF)/diskio.h build/
	cp $(V2)/ffconf.h build/

clean:
	rm -rf build firmware.hex
