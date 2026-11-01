# Simulate comp80_machine.v with Verilator and compare its screens with the v2
# firmware's machine code (hardware_v2/firmware/host).  TV80 is fetched into
# ../build/tv80 by ../tools/fetch.sh.
V2 = ../../hardware_v2/firmware/src
TV80 = ../build/tv80/rtl/core
RTL = ../rtl/comp80_machine.v ../rtl/tv80c.v $(TV80)/tv80_core.v $(TV80)/tv80_alu.v $(TV80)/tv80_mcode.v $(TV80)/tv80_reg.v

obj/Vcomp80_machine: tb.cpp $(RTL) $(V2)/mm57109.c
	verilator --cc --exe --build -O3 -j 8 --Mdir obj --top-module comp80_machine \
	  -GSYS_HZ=12000000 --public-flat-rw -Wno-fatal -Wno-lint -Wno-style \
	  -CFLAGS "-O2 -I$(abspath $(V2))" $(RTL) tb.cpp $(abspath $(V2))/mm57109.c

test: obj/Vcomp80_machine
	sh compare.sh

clean:
	rm -rf obj

# the whole system controller with the machine, booting the firmware
PICO = ../build/picorv32/picorv32.v
obj_soc/Vsim_soc: soc_tb.cpp sim_soc.v ../rtl/soc.v ../rtl/spi_master.v $(RTL) $(PICO) ../firmware/firmware.hex
	verilator --cc --exe --build -O3 -j 8 --Mdir obj_soc --top-module sim_soc -GSYS_HZ=12000000 \
	  -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN sim_soc.v ../rtl/soc.v ../rtl/spi_master.v $(RTL) $(PICO) soc_tb.cpp

boot: obj_soc/Vsim_soc
	./obj_soc/Vsim_soc 3
