// The system controller and the machine together, without the clocks, USB and
// HDMI, for soc_tb.cpp: the firmware boots, finds no card, loads its built-in
// ROM and starts the Z80.
module sim_soc #(parameter SYS_HZ = 12_000_000) (
    input         clk,
    input         rst,
    output        uart_tx,
    output        scr_we,
    output [10:0] scr_addr,
    output [7:0]  scr_data,
    output        halted
);
    wire        z80_run, clk4, expansion, menu_on, key_strobe, key_full;
    wire [23:0] colour;
    wire [7:0]  key_code, mm_cmd, mm_status, h_wdata, h_rdata, menu_data;
    wire        mm_cmd_new, mm_done, mm_irq, tape_in, tape_out, h_we, menu_we;
    wire [15:0] h_addr;
    wire [10:0] menu_addr;
    wire [39:0] cycles;
    wire        sd_sck, sd_mosi, sd_cs;

    comp80_machine #(.SYS_HZ(SYS_HZ)) machine (
        .clk(clk), .rst(rst || !z80_run), .clk4(clk4), .expansion(expansion),
        .h_addr(h_addr), .h_wdata(h_wdata), .h_we(h_we), .h_rdata(h_rdata),
        .key_strobe(key_strobe), .key_code(key_code), .key_full(key_full),
        .mm_cmd(mm_cmd), .mm_cmd_new(mm_cmd_new), .mm_done(mm_done), .mm_status(mm_status), .mm_irq(mm_irq),
        .tape_in(tape_in), .tape_out(tape_out),
        .scr_we(scr_we), .scr_addr(scr_addr), .scr_data(scr_data), .halted(halted), .cycles(cycles));

    soc #(.SYS_HZ(SYS_HZ), .FIRMWARE("../firmware/firmware.hex")) soc (
        .clk(clk), .rst(rst), .uart_tx(uart_tx),
        .z80_run(z80_run), .clk4(clk4), .expansion(expansion), .menu_on(menu_on), .colour(colour),
        .key_strobe(key_strobe), .key_code(key_code), .key_full(key_full), .halted(halted),
        .mm_cmd(mm_cmd), .mm_cmd_new(mm_cmd_new), .mm_status(mm_status), .mm_done(mm_done), .mm_irq(mm_irq),
        .tape_in(tape_in), .tape_out(tape_out), .cycles(cycles),
        .h_addr(h_addr), .h_wdata(h_wdata), .h_we(h_we), .h_rdata(h_rdata),
        .menu_we(menu_we), .menu_addr(menu_addr), .menu_data(menu_data),
        .usb_report(1'b0), .usb_typ(2'b0), .usb_mod(8'b0), .usb_keys(32'b0),
        .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(1'b1), .sd_cs(sd_cs),
        .dp_hpd(), .dp_aux_invert(), .dp_lane_sel(), .dp_link_up(1'b0), .pd_scl_low(), .pd_sda_low(), .vbus_en(),
        .pd_scl(1'b1), .pd_sda(1'b1), .pd_int_n(1'b1), .vbus_flt_n(1'b1));
endmodule
