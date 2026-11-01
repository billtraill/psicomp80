// The PSI COMP80 in logic: the Z80, its 64 KB of memory and its I/O ports, as
// the web emulator (web/src/comp80.js) and the v2 firmware (comp80.c) define
// them, so the same ROM images run unchanged.
//
//   0000-0BFF  ROM image (the soft processor loads it; Z80 writes ignored)
//   0C00-1FFF  RAM
//   2000-7FFF  nothing: reads 0, writes ignored
//   8000-87FF  the screen, mirrored up to FFFF (or 32 KB of RAM with the expansion)
//   IN  00  tape level (bit 0)       OUT 20  tape level (bit 7)
//   IN  01  keyboard latch           OUT 60  MM57109 instruction and HOLD
//   IN  03  MM57109 status
//
// The keyboard and the MM57109 are served by the soft processor (soc.v).  A key
// written to key_code latches for IN 01 and pulls NMI; an OUT 60 stalls the Z80
// (WAIT) until the soft processor has passed it to its MM57109 model and set the
// new status, so IN 03 straight afterwards reads what the real chip would show;
// mm_irq raises INT until the Z80 acknowledges it.
module comp80_machine #(
    parameter SYS_HZ = 50_000_000
) (
    input             clk,
    input             rst,            // holds the Z80 in reset
    input             clk4,           // 0: 2 MHz like the real machine, 1: 4 MHz like MAME
    input             expansion,      // the 32 KB memory expansion at 8800-FFFF

    // the soft processor's port into the 64 KB (loading ROMs, reading memory)
    input      [15:0] h_addr,
    input      [7:0]  h_wdata,
    input             h_we,
    output reg [7:0]  h_rdata,

    // keyboard
    input             key_strobe,     // one clock: latch ~key_code and pull NMI
    input      [7:0]  key_code,
    output            key_full,       // the last key hasn't been read yet

    // MM57109
    output reg [7:0]  mm_cmd,         // the last OUT 60
    output reg        mm_cmd_new,     // set by OUT 60, cleared by mm_done
    input             mm_done,        // one clock: mm_status is up to date, let the Z80 go on
    input      [7:0]  mm_status,      // what IN 03 reads
    input             mm_irq,         // one clock: raise INT

    // tape
    input             tape_in,
    output reg        tape_out,

    // the screen, written through to the display's own copy
    output            scr_we,
    output     [10:0] scr_addr,
    output     [7:0]  scr_data,

    output            halted,
    output reg [39:0] cycles          // Z80 T-states since reset
);

    // ------------------------------------------------------------ the clock enable
    // A phase accumulator gives exactly 2 or 4 million enables a second.
    reg [31:0] acc;
    reg        cen;
    wire [31:0] step = clk4 ? 32'd4_000_000 : 32'd2_000_000;
    always @(posedge clk) begin
        if (acc + step >= SYS_HZ) begin acc <= acc + step - SYS_HZ; cen <= 1'b1; end
        else begin acc <= acc + step; cen <= 1'b0; end
    end

    // ------------------------------------------------------------ the Z80
    wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;
    wire [15:0] A;
    wire [7:0]  dout;
    reg  [7:0]  di;
    reg         nmi_n, int_n;
    wire        wait_n;

    tv80c #(.Mode(0), .T2Write(1), .IOWait(1)) z80 (
        .reset_n(~rst), .clk(clk), .cen(cen), .wait_n(wait_n), .int_n(int_n), .nmi_n(nmi_n),
        .busrq_n(1'b1), .di(di), .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n),
        .wr_n(wr_n), .rfsh_n(rfsh_n), .halt_n(halt_n), .busak_n(busak_n), .A(A), .dout(dout));

    assign halted = ~halt_n;

    always @(posedge clk)
        if (rst) cycles <= 40'd0;
        else if (cen) cycles <= cycles + 40'd1;

    // ------------------------------------------------------------ memory
    wire        hi      = A[15];
    wire [15:0] maddr   = (hi && !expansion) ? {5'b10000, A[10:0]} : A;
    wire        nothing = !hi && (A[14:13] != 2'b00);            // 2000-7FFF
    wire        mem_rd  = !mreq_n && !rd_n;
    wire        mem_wr  = !mreq_n && !wr_n && rfsh_n;
    wire        we_a    = mem_wr && !nothing && (A >= 16'h0C00);

    reg [7:0] mem [0:65535];
    reg [7:0] q_a;
    always @(posedge clk) begin
        if (we_a) mem[maddr] <= dout;
        q_a <= mem[maddr];
    end
    always @(posedge clk) begin
        if (h_we) mem[h_addr] <= h_wdata;
        h_rdata <= mem[h_addr];
    end

    assign scr_we   = we_a && (maddr[15:11] == 5'b10000);
    assign scr_addr = maddr[10:0];
    assign scr_data = dout;

    // ------------------------------------------------------------ I/O
    wire io_rd = !iorq_n && !rd_n && m1_n;
    wire io_wr = !iorq_n && !wr_n && m1_n;
    wire inta  = !iorq_n && !m1_n;
    reg  io_rd_d, io_wr_d, inta_d;
    reg  [7:0] io_q;                  // the port's value, taken as the read starts
    reg  [7:0] key_latch;
    reg  [3:0] nmi_count;
    reg  [7:0] mm_status_q;

    assign key_full = key_latch != 8'hff;
    // an OUT 60 waits for the soft processor
    assign wait_n = !(io_wr && A[7:0] == 8'h60 && mm_cmd_new);

    always @(posedge clk) begin
        io_rd_d <= io_rd;
        io_wr_d <= io_wr;
        inta_d  <= inta;
        if (mm_done) begin mm_cmd_new <= 1'b0; mm_status_q <= mm_status; end
        else mm_status_q <= mm_cmd_new ? mm_status_q : mm_status;
        if (rst) begin
            key_latch  <= 8'hff;
            nmi_n      <= 1'b1;
            nmi_count  <= 4'd0;
            int_n      <= 1'b1;
            tape_out   <= 1'b1;
            mm_cmd_new <= 1'b0;
        end else begin
            // reads: take the value as the cycle starts; reading the keyboard empties its latch
            if (io_rd && !io_rd_d) begin
                case (A[7:0])
                    8'h00:   io_q <= {7'b0, tape_in};
                    8'h01:   begin io_q <= key_latch; key_latch <= 8'hff; end
                    8'h03:   io_q <= mm_status_q;
                    default: io_q <= 8'hff;
                endcase
            end
            // writes, once each
            if (io_wr && !io_wr_d) begin
                if (A[7:0] == 8'h20) tape_out <= dout[7];
                if (A[7:0] == 8'h60) begin mm_cmd <= dout; mm_cmd_new <= 1'b1; end
            end
            // a key: latch it and pull NMI low for a few T-states (the Z80 takes the falling edge)
            if (key_strobe) begin
                key_latch <= ~key_code;
                nmi_n     <= 1'b0;
                nmi_count <= 4'd8;
            end else if (cen && nmi_count != 0) begin
                nmi_count <= nmi_count - 4'd1;
                if (nmi_count == 4'd1) nmi_n <= 1'b1;
            end
            // the MM57109's R/W pulse is latched until the Z80 takes the interrupt
            if (mm_irq) int_n <= 1'b0;
            else if (inta && !inta_d) int_n <= 1'b1;
        end
    end

    // the data the Z80 reads: RST 38h for an interrupt, a port, or memory
    reg nothing_q;
    always @(posedge clk) nothing_q <= nothing;
    always @(*) begin
        if (inta)       di = 8'hff;
        else if (io_rd) di = io_q;
        else            di = nothing_q ? 8'h00 : q_a;
    end

endmodule
