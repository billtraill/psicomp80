// The system controller: a PicoRV32 RISC-V soft processor with 128 KB of RAM
// (loaded with ../firmware's program when the FPGA is configured) and the
// registers through which it runs the COMP80 machine.  Its firmware loads ROMs
// from the microSD card, models the MM57109, plays and records tapes, turns
// USB keyboard reports into COMP80 keys and draws the set-up screen.
//
//   0000_0000  RAM, 128 KB
//   1000_0000  UART: write a byte to send it; read bit 0 = busy
//   2000_0000  the machine (firmware/hw.h has the registers)
//   3000_0000  the Z80's 64 KB, a byte a word
//   4000_0000  the set-up screen, 2 KB, a byte a word (write only)
//   5000_0000  SPI: +0 data, +4 busy, +8 chip select, +C clock divider
//   2000_0038  DisplayPort: bit 0 hot-plug, bit 1 AUX swapped, bits 15-8 lane map
//   2000_003C  USB-PD: write bit 0 pull SCL low, 1 pull SDA low, 2 VBUS on;
//              read bit 0 SCL, 1 SDA, 2 FUSB302 INT_N, 3 VBUS fault_n, 4 DisplayPort link up
module soc #(
    parameter SYS_HZ = 50_000_000,
    parameter FIRMWARE = "firmware.hex"
) (
    input             clk,
    input             rst,

    output            uart_tx,

    // the machine
    output reg        z80_run,
    output reg        clk4,
    output reg        expansion,
    output reg        menu_on,
    output reg [23:0] colour,
    output reg        key_strobe,
    output reg [7:0]  key_code,
    input             key_full,
    input             halted,
    input      [7:0]  mm_cmd,
    input             mm_cmd_new,
    output reg [7:0]  mm_status,
    output reg        mm_done,
    output reg        mm_irq,
    output reg        tape_in,
    input             tape_out,
    input      [39:0] cycles,
    output reg [15:0] h_addr,
    output reg [7:0]  h_wdata,
    output reg        h_we,
    input      [7:0]  h_rdata,
    output reg        menu_we,
    output reg [10:0] menu_addr,
    output reg [7:0]  menu_data,

    // the USB keyboard, already in this clock domain
    input             usb_report,     // toggles with each report
    input      [1:0]  usb_typ,
    input      [7:0]  usb_mod,
    input      [31:0] usb_keys,       // {key4, key3, key2, key1}

    // microSD
    output            sd_sck,
    output            sd_mosi,
    input             sd_miso,
    output reg        sd_cs,

    // DisplayPort over USB-C, and the FUSB302 USB-PD controller beside it
    output reg        dp_hpd,
    output reg        dp_aux_invert,
    output reg  [7:0] dp_lane_sel,
    input             dp_link_up,
    output reg        pd_scl_low,
    output reg        pd_sda_low,
    output reg        vbus_en,
    input             pd_scl,
    input             pd_sda,
    input             pd_int_n,
    input             vbus_flt_n
);
    // ------------------------------------------------------------ the processor
    wire        mem_valid, mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_MUL(1), .ENABLE_DIV(1), .COMPRESSED_ISA(1), .ENABLE_IRQ(0),
        .PROGADDR_RESET(32'h0), .STACKADDR(32'h0002_0000)
    ) cpu (
        .clk(clk), .resetn(!rst), .trap(),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .mem_la_read(), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(), .pcpi_wr(1'b0), .pcpi_rd(32'b0),
        .pcpi_wait(1'b0), .pcpi_ready(1'b0), .irq(32'b0), .eoi(),
        .trace_valid(), .trace_data());

    // ------------------------------------------------------------ RAM
    reg [31:0] ram [0:32767];
    initial $readmemh(FIRMWARE, ram);
    reg [31:0] ram_q;
    wire ram_sel = mem_valid && mem_addr[31:28] == 4'h0;
    always @(posedge clk) begin
        if (ram_sel) begin
            if (mem_wstrb[0]) ram[mem_addr[16:2]][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) ram[mem_addr[16:2]][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) ram[mem_addr[16:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram[mem_addr[16:2]][31:24] <= mem_wdata[31:24];
        end
        ram_q <= ram[mem_addr[16:2]];
    end

    // ------------------------------------------------------------ UART, 115200 baud
    localparam BAUD_DIV = SYS_HZ / 115200;
    reg [9:0]  u_sh = 10'h3ff;
    reg [3:0]  u_bits;
    reg [15:0] u_cnt;
    assign uart_tx = u_sh[0];
    wire u_busy = u_bits != 0;

    // ------------------------------------------------------------ SPI
    reg  [7:0] spi_div;
    reg        spi_start;
    wire [7:0] spi_rx;
    wire       spi_busy;
    spi_master spi (.clk(clk), .rst(rst), .div(spi_div), .start(spi_start), .tx(mem_wdata[7:0]), .rx(spi_rx),
                    .busy(spi_busy), .sck(sd_sck), .mosi(sd_mosi), .miso(sd_miso));

    // ------------------------------------------------------------ the bus
    reg [1:0]  wait_n;               // RAM reads take a clock, the Z80's memory two
    reg [31:0] usec_div, usec;        // a microsecond clock for the firmware's delays
    reg [7:0]  cycles_hi;             // latched when the low word is read

    always @(posedge clk) begin
        usec_div <= (usec_div == SYS_HZ / 1_000_000 - 1) ? 32'd0 : usec_div + 32'd1;
        if (usec_div == 0) usec <= usec + 32'd1;
    end

    always @(posedge clk) begin
        mem_ready  <= 1'b0;
        key_strobe <= 1'b0;
        mm_done    <= 1'b0;
        mm_irq     <= 1'b0;
        h_we       <= 1'b0;
        menu_we    <= 1'b0;
        spi_start  <= 1'b0;
        if (u_busy && u_cnt != 0) u_cnt <= u_cnt - 16'd1;
        else if (u_busy) begin u_cnt <= BAUD_DIV[15:0]; u_sh <= {1'b1, u_sh[9:1]}; u_bits <= u_bits - 4'd1; end
        if (rst) begin
            z80_run <= 0; clk4 <= 0; expansion <= 0; menu_on <= 0; colour <= 24'hffffff;
            tape_in <= 1; sd_cs <= 1; spi_div <= 8'd62; wait_n <= 0; u_bits <= 0;
            dp_hpd <= 0; dp_aux_invert <= 0; dp_lane_sel <= 8'b11_10_01_00; pd_scl_low <= 0; pd_sda_low <= 0; vbus_en <= 0;
        end else if (mem_valid && !mem_ready) begin
            case (mem_addr[31:28])
                4'h0: begin                       // the RAM's output is a clock behind its address
                    if (wait_n == 2'd1) begin mem_ready <= 1'b1; mem_rdata <= ram_q; wait_n <= 0; end
                    else wait_n <= 2'd1;
                end
                4'h1: begin
                    mem_ready <= 1'b1;
                    mem_rdata <= {31'b0, u_busy};
                    if (mem_wstrb != 0 && !u_busy) begin u_sh <= {1'b1, mem_wdata[7:0], 1'b0}; u_bits <= 4'd10; u_cnt <= BAUD_DIV[15:0]; end
                end
                4'h2: begin
                    mem_ready <= 1'b1;
                    if (mem_wstrb != 0) case (mem_addr[7:2])
                        6'h00: {menu_on, expansion, clk4, z80_run} <= mem_wdata[3:0];
                        6'h01: colour <= mem_wdata[23:0];
                        6'h02: begin key_code <= mem_wdata[7:0]; key_strobe <= 1'b1; end
                        6'h05: mm_status <= mem_wdata[7:0];
                        6'h06: mm_done <= 1'b1;
                        6'h07: mm_irq <= 1'b1;
                        6'h08: tape_in <= mem_wdata[0];
                        6'h0e: {dp_lane_sel, dp_aux_invert, dp_hpd} <= {mem_wdata[15:8], mem_wdata[1:0]};
                        6'h0f: {vbus_en, pd_sda_low, pd_scl_low} <= mem_wdata[2:0];
                        default: ;
                    endcase
                    case (mem_addr[7:2])
                        6'h00: mem_rdata <= {28'b0, menu_on, expansion, clk4, z80_run};
                        6'h03: mem_rdata <= {27'b0, tape_out, mm_cmd_new, key_full, halted};
                        6'h04: mem_rdata <= {24'b0, mm_cmd};
                        6'h09: begin mem_rdata <= cycles[31:0]; cycles_hi <= cycles[39:32]; end
                        6'h0a: mem_rdata <= {24'b0, cycles_hi};
                        6'h0b: mem_rdata <= usb_keys;
                        6'h0c: mem_rdata <= {21'b0, usb_report, usb_typ, usb_mod};
                        6'h0d: mem_rdata <= usec;
                        6'h0e: mem_rdata <= {16'b0, dp_lane_sel, 6'b0, dp_aux_invert, dp_hpd};
                        6'h0f: mem_rdata <= {27'b0, dp_link_up, vbus_flt_n, pd_int_n, pd_sda, pd_scl};
                        default: mem_rdata <= 32'b0;
                    endcase
                end
                4'h3: begin
                    h_addr <= mem_addr[17:2];
                    if (mem_wstrb != 0) begin h_wdata <= mem_wdata[7:0]; h_we <= 1'b1; mem_ready <= 1'b1; end
                    else if (wait_n == 2'd2) begin mem_rdata <= {24'b0, h_rdata}; mem_ready <= 1'b1; wait_n <= 0; end
                    else wait_n <= wait_n + 2'd1;
                end
                4'h4: begin
                    mem_ready <= 1'b1;
                    if (mem_wstrb != 0) begin menu_addr <= mem_addr[12:2]; menu_data <= mem_wdata[7:0]; menu_we <= 1'b1; end
                end
                4'h5: begin
                    mem_ready <= 1'b1;
                    case (mem_addr[3:2])
                        2'd0: begin mem_rdata <= {24'b0, spi_rx}; if (mem_wstrb != 0) spi_start <= 1'b1; end
                        2'd1: mem_rdata <= {31'b0, spi_busy | spi_start};
                        2'd2: if (mem_wstrb != 0) sd_cs <= mem_wdata[0];
                        2'd3: if (mem_wstrb != 0) spi_div <= mem_wdata[7:0];
                    endcase
                end
                default: begin mem_ready <= 1'b1; mem_rdata <= 32'b0; end
            endcase
        end
    end
endmodule
