// Run the DisplayPort source (dp_comp80_source.v and hamsternz's MSA inserter)
// for a little over a frame with a screen loaded, and write the lane's symbols,
// two a clock, to dp_symbols.txt for dp_decode.py to turn back into a picture.
//   iverilog -g2012 -o dp_tb dp_tb.v ../rtl/dp_comp80_source.v \
//     ../build/DisplayPort_Verilog/src/test_streams/insert_main_stream_attrbutes_one_channel.v
//   vvp dp_tb +screen=screen.hex && python3 dp_decode.py screen.hex
`timescale 1ns/1ps
module dp_tb;
    reg clk = 0, wclk = 0;
    always #3.7 clk = ~clk;       // 135 MHz
    always #10 wclk = ~wclk;
    reg scr_we = 0; reg [10:0] scr_addr; reg [7:0] scr_data;
    wire [23:0] M_value, N_value;
    wire [11:0] H_visible, V_visible, H_total, V_total, H_sync_width, V_sync_width, H_start, V_start;
    wire H_vsync_active_high, V_vsync_active_high, flag_sync_clock, flag_YCCnRGB, flag_422n444;
    wire flag_YCC_colour_709, flag_range_reduced, flag_interlaced_even;
    wire [1:0] flags_3d_Indicators; wire [4:0] bits_per_colour; wire [2:0] stream_channel_count;
    wire ready; wire [72:0] raw, out;
    dp_comp80_source s (
        .M_value(M_value), .N_value(N_value), .H_visible(H_visible), .V_visible(V_visible),
        .H_total(H_total), .V_total(V_total), .H_sync_width(H_sync_width), .V_sync_width(V_sync_width),
        .H_start(H_start), .V_start(V_start), .H_vsync_active_high(H_vsync_active_high),
        .V_vsync_active_high(V_vsync_active_high), .flag_sync_clock(flag_sync_clock),
        .flag_YCCnRGB(flag_YCCnRGB), .flag_422n444(flag_422n444), .flag_YCC_colour_709(flag_YCC_colour_709),
        .flag_range_reduced(flag_range_reduced), .flag_interlaced_even(flag_interlaced_even),
        .flags_3d_Indicators(flags_3d_Indicators), .bits_per_colour(bits_per_colour),
        .stream_channel_count(stream_channel_count), .clk(clk), .ready(ready), .data(raw),
        .wclk(wclk), .scr_we(scr_we), .scr_addr(scr_addr), .scr_data(scr_data),
        .menu_we(1'b0), .menu_addr(11'd0), .menu_data(8'd0), .menu_on(1'b0), .colour(24'h33ff66));
    insert_main_stream_attrbutes_one_channel m (
        .clk(clk), .active(1'b1), .M_value(M_value), .N_value(N_value), .H_visible(H_visible),
        .H_total(H_total), .H_sync_width(H_sync_width), .H_start(H_start), .V_visible(V_visible),
        .V_total(V_total), .V_sync_width(V_sync_width), .V_start(V_start),
        .H_vsync_active_high(H_vsync_active_high), .V_vsync_active_high(V_vsync_active_high),
        .flag_sync_clock(flag_sync_clock), .flag_YCCnRGB(flag_YCCnRGB), .flag_422n444(flag_422n444),
        .flag_range_reduced(flag_range_reduced), .flag_interlaced_even(flag_interlaced_even),
        .flag_YCC_colour_709(flag_YCC_colour_709), .flags_3d_Indicators(flags_3d_Indicators),
        .bits_per_colour(bits_per_colour), .in_data(raw), .out_data(out));

    reg [7:0] screen [0:2047];
    reg [1023:0] path;
    integer i, f, n;
    initial begin
        if (!$value$plusargs("screen=%s", path)) path = "screen.hex";
        $readmemh(path, screen);
        for (i = 0; i < 2048; i = i + 1) begin
            @(posedge wclk); scr_we <= 1; scr_addr <= i; scr_data <= screen[i];
        end
        @(posedge wclk); scr_we <= 0;
        f = $fopen("dp_symbols.txt", "w");
        for (n = 0; n < 2_400_000 * 2; n = n + 1) begin    // two frames
            @(posedge clk);
            $fwrite(f, "%05x\n", out[17:0]);
        end
        $fclose(f);
        $finish;
    end
endmodule
