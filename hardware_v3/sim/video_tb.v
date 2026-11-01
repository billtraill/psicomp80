// Draw one frame with video.v from a screen dump (SCREEN, 2048 hex bytes) and
// write it as frame.ppm, 640 x 480, to look at.  The TMDS encoders run too, and
// the test checks each symbol decodes back to the pixel or control code.
//   iverilog -g2012 -DSIM -o video_tb video_tb.v ../rtl/video.v ../rtl/hdmi_out.v && vvp video_tb +screen=...
`timescale 1ns/1ps
module video_tb;
    reg clk = 0, pclk = 0;
    always #10 clk = ~clk;
    always #20 pclk = ~pclk;
    reg scr_we = 0; reg [10:0] scr_addr; reg [7:0] scr_data;
    wire [7:0] r, g, b; wire hs, vs, de;
    video v (.clk(clk), .scr_we(scr_we), .scr_addr(scr_addr), .scr_data(scr_data),
             .menu_we(1'b0), .menu_addr(11'd0), .menu_data(8'd0), .menu_on(1'b0), .colour(24'h33ff66),
             .pclk(pclk), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de));
    wire [9:0] sr, sg, sb;
    wire [3:0] tp, tn;
    hdmi_out h (.pclk(pclk), .sclk(1'b0), .rst(1'b0), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de),
                .sym_r(sr), .sym_g(sg), .sym_b(sb), .tmds_p(tp), .tmds_n(tn));

    // decode a TMDS symbol back to its byte
    function [7:0] dec(input [9:0] s);
        reg [7:0] d; integer i;
        begin
            d = s[9] ? ~s[7:0] : s[7:0];
            dec[0] = d[0];
            for (i = 1; i < 8; i = i + 1) dec[i] = s[8] ? d[i] ^ d[i - 1] : ~(d[i] ^ d[i - 1]);
        end
    endfunction

    reg [7:0] screen [0:2047];
    integer i, f, n = 0, bad = 0, x = 0, y = 0;
    reg [7:0] r1, g1, b1; reg de1;
    reg [1023:0] path;
    initial begin
        if (!$value$plusargs("screen=%s", path)) path = "screen.hex";
        $readmemh(path, screen);
        for (i = 0; i < 2048; i = i + 1) begin
            @(posedge clk); scr_we <= 1; scr_addr <= i; scr_data <= screen[i];
        end
        @(posedge clk); scr_we <= 0;
        // wait for the start of a frame
        @(negedge vs); @(posedge vs);
        f = $fopen("frame.ppm", "w");
        $fwrite(f, "P3\n640 480\n255\n");
        while (n < 640 * 480) begin
            @(posedge pclk);
            if (de1) begin
                if (dec(sr) != r1 || dec(sg) != g1 || dec(sb) != b1) bad = bad + 1;
            end
            if (de) begin $fwrite(f, "%0d %0d %0d\n", r, g, b); n = n + 1; end
            r1 <= r; g1 <= g; b1 <= b; de1 <= de;
        end
        $fclose(f);
        $display("frame written; %0d TMDS symbols that didn't decode", bad);
        $finish;
    end
endmodule
