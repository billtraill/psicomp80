// DisplayPort over the USB-C socket J7: the COMP80's screen at 800 x 600 on
// one 2.7 Gb/s lane, built from hamsternz's DisplayPort_Verilog (MIT; fetched
// into ../build by tools/fetch.sh) the way his top_level_nexys_video.v puts it
// together, with the COMP80 source (dp_comp80_source.v) in place of his test
// patterns and four transceivers (dp_transceivers.v) instead of two.
//
// The USB-PD side (the firmware and the FUSB302) agrees DisplayPort alternate
// mode with the monitor and reports hot-plug; which of the socket's four pairs
// carries each lane depends on the cable's orientation and the agreed pin
// assignment, so the firmware sets lane_sel. The AUX channel's two wires swap
// over with the orientation too, which aux_invert undoes.
module dp_out (
    input        clk100,            // AUX channel and link management (as in the original)
    input        refclk_p,          // 135 MHz reference for the transceivers
    input        refclk_n,
    output [3:0] gtp_p,             // to J7: 0 TX1, 1 RX1, 2 TX2, 3 RX2
    output [3:0] gtp_n,
    inout        aux_p,             // to J7's SBU pins, through AC coupling
    inout        aux_n,

    // from the system controller (system clock domain, quasi-static)
    input        hpd,               // the monitor's hot-plug state, from USB-PD Attention messages
    input  [7:0] lane_sel,          // 2 bits per pair: which lane it carries
    input        aux_invert,        // the AUX wires are swapped
    output       link_up,           // link training finished (clk100 domain)

    // the screen, written from the system clock domain
    input        clk,
    input        scr_we,
    input [10:0] scr_addr,
    input  [7:0] scr_data,
    input        menu_we,
    input [10:0] menu_addr,
    input  [7:0] menu_data,
    input        menu_on,
    input [23:0] colour
);
    // ------------------------------------------------------------ clocks and settings
    wire refclk0, odiv2_0;
    IBUFDS_GTE2 ibufds_gte2_0 (.O(refclk0), .ODIV2(odiv2_0), .CEB(1'b0), .I(refclk_p), .IB(refclk_n));

    reg [1:0] hpd_s;
    reg [1:0] inv_s;
    always @(posedge clk100) begin hpd_s <= {hpd_s[0], hpd}; inv_s <= {inv_s[0], aux_invert}; end

    // ------------------------------------------------------------ AUX channel
    wire auxch_in_raw, auxch_out, auxch_tri;
    IOBUFDS #(.DIFF_TERM("FALSE"), .IBUF_LOW_PWR("TRUE"), .IOSTANDARD("DEFAULT"), .SLEW("SLOW")) aux_buf (
        .O(auxch_in_raw), .IO(aux_p), .IOB(aux_n), .I(auxch_out ^ inv_s[1]), .T(auxch_tri));
    wire auxch_in = auxch_in_raw ^ inv_s[1];

    // ------------------------------------------------------------ link management (clk100)
    wire       tx_symbol_clk;
    wire [3:0] tx_powerup_channel;      // per lane
    wire [3:0] tx_running;              // per lane
    wire       preemp_0p0, preemp_3p5, preemp_6p0, swing_0p4, swing_0p6, swing_0p8;
    wire       tx_align_train, tx_clock_train, tx_link_established;
    wire [2:0] stream_channel_count;
    wire [7:0] debug_cm;
    assign link_up = tx_link_established;

    channel_management cm (
        .clk100(clk100), .debug(debug_cm), .hpd(hpd_s[1]),
        .auxch_in(auxch_in), .auxch_out(auxch_out), .auxch_tri(auxch_tri),
        .stream_channel_count(stream_channel_count), .source_channel_count(3'b001),
        .tx_clock_train(tx_clock_train), .tx_align_train(tx_align_train),
        .tx_powerup_channel(tx_powerup_channel),
        .tx_preemp_0p0(preemp_0p0), .tx_preemp_3p5(preemp_3p5), .tx_preemp_6p0(preemp_6p0),
        .tx_swing_0p4(swing_0p4), .tx_swing_0p6(swing_0p6), .tx_swing_0p8(swing_0p8),
        .tx_running(tx_running), .tx_link_established(tx_link_established));

    // ------------------------------------------------------------ the stream (symbol clock)
    wire [23:0] M_value, N_value;
    wire [11:0] H_visible, V_visible, H_total, V_total, H_sync_width, V_sync_width, H_start, V_start;
    wire        H_vsync_active_high, V_vsync_active_high, flag_sync_clock, flag_YCCnRGB, flag_422n444;
    wire        flag_YCC_colour_709, flag_range_reduced, flag_interlaced_even;
    wire  [1:0] flags_3d_Indicators;
    wire  [4:0] bits_per_colour;
    wire [72:0] raw_data, msa_data;
    wire        source_ready;

    dp_comp80_source source (
        .M_value(M_value), .N_value(N_value), .H_visible(H_visible), .V_visible(V_visible),
        .H_total(H_total), .V_total(V_total), .H_sync_width(H_sync_width), .V_sync_width(V_sync_width),
        .H_start(H_start), .V_start(V_start), .H_vsync_active_high(H_vsync_active_high),
        .V_vsync_active_high(V_vsync_active_high), .flag_sync_clock(flag_sync_clock),
        .flag_YCCnRGB(flag_YCCnRGB), .flag_422n444(flag_422n444), .flag_YCC_colour_709(flag_YCC_colour_709),
        .flag_range_reduced(flag_range_reduced), .flag_interlaced_even(flag_interlaced_even),
        .flags_3d_Indicators(flags_3d_Indicators), .bits_per_colour(bits_per_colour),
        .stream_channel_count(stream_channel_count),
        .clk(tx_symbol_clk), .ready(source_ready), .data(raw_data),
        .wclk(clk), .scr_we(scr_we), .scr_addr(scr_addr), .scr_data(scr_data),
        .menu_we(menu_we), .menu_addr(menu_addr), .menu_data(menu_data),
        .menu_on(menu_on), .colour(colour));

    insert_main_stream_attrbutes_one_channel msa (
        .clk(tx_symbol_clk), .active(1'b1),
        .M_value(M_value), .N_value(N_value), .H_visible(H_visible), .H_total(H_total),
        .H_sync_width(H_sync_width), .H_start(H_start), .V_visible(V_visible), .V_total(V_total),
        .V_sync_width(V_sync_width), .V_start(V_start), .H_vsync_active_high(H_vsync_active_high),
        .V_vsync_active_high(V_vsync_active_high), .flag_sync_clock(flag_sync_clock),
        .flag_YCCnRGB(flag_YCCnRGB), .flag_422n444(flag_422n444), .flag_range_reduced(flag_range_reduced),
        .flag_interlaced_even(flag_interlaced_even), .flag_YCC_colour_709(flag_YCC_colour_709),
        .flags_3d_Indicators(flags_3d_Indicators), .bits_per_colour(bits_per_colour),
        .in_data(raw_data), .out_data(msa_data));

    wire [79:0] lane_symbols;           // 20 bits per lane
    main_stream_processing msp (
        .symbol_clk(tx_symbol_clk), .tx_link_established(tx_link_established), .source_ready(source_ready),
        .tx_clock_train(tx_clock_train), .tx_align_train(tx_align_train),
        .in_data(msa_data), .tx_symbols(lane_symbols));

    // ------------------------------------------------------------ lanes onto pairs
    reg [7:0] sel_s, sel_t;
    always @(posedge tx_symbol_clk) begin sel_s <= lane_sel; sel_t <= sel_s; end
    reg [79:0] pair_symbols;
    reg  [3:0] pair_powerup;
    wire [3:0] pair_running;
    integer p;
    always @(*) begin
        for (p = 0; p < 4; p = p + 1) begin
            pair_symbols[p * 20 +: 20] = lane_symbols[sel_t[p * 2 +: 2] * 20 +: 20];
            pair_powerup[p] = tx_powerup_channel[lane_sel[p * 2 +: 2]];
        end
        pair_powerup[0] = pair_powerup[0] | (|tx_powerup_channel);   // channel 0 runs the quad's PLL
    end
    // each lane is running when the pair carrying it is
    reg [3:0] lane_running;
    integer q;
    always @(*) begin
        lane_running = 4'b0000;
        for (q = 0; q < 4; q = q + 1)
            if (tx_powerup_channel[lane_sel[q * 2 +: 2]]) lane_running[lane_sel[q * 2 +: 2]] = pair_running[q];
    end
    assign tx_running = lane_running;

    dp_transceivers gtp (
        .mgmt_clk(clk100), .powerup_channel(pair_powerup),
        .preemp_0p0(preemp_0p0), .preemp_3p5(preemp_3p5), .preemp_6p0(preemp_6p0),
        .swing_0p4(swing_0p4), .swing_0p6(swing_0p6), .swing_0p8(swing_0p8),
        .tx_running(pair_running), .refclk0(refclk0), .refclk1(1'b0),
        .tx_symbol_clk(tx_symbol_clk), .tx_symbols(pair_symbols),
        .gtptx_p(gtp_p), .gtptx_n(gtp_n));
endmodule
