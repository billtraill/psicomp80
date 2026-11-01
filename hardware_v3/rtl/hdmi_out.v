// DVI over the HDMI socket: three TMDS encoders and the Artix-7's serialisers.
// Each 10-bit symbol goes out through a master/slave OSERDESE2 pair at 10:1,
// DDR on the 125 MHz serial clock, into a TMDS_33 output (set in the XDC),
// which drives the display's 50 ohm terminations directly.  With SIM defined
// the serialisers are left out and the symbols are outputs, for the testbench.
module hdmi_out (
    input        pclk,          // 25 MHz
    input        sclk,          // 125 MHz, 5 x pclk, from the same MMCM
    input        rst,
    input  [7:0] r, g, b,
    input        hs, vs, de,
`ifdef SIM
    output [9:0] sym_r, sym_g, sym_b,
`endif
    output [3:0] tmds_p, tmds_n   // 0 blue, 1 green, 2 red, 3 clock
);
    wire [9:0] s0, s1, s2;
    tmds_encoder e0 (.clk(pclk), .d(b), .c({vs, hs}), .de(de), .q(s0));   // sync rides on blue
    tmds_encoder e1 (.clk(pclk), .d(g), .c(2'b00),    .de(de), .q(s1));
    tmds_encoder e2 (.clk(pclk), .d(r), .c(2'b00),    .de(de), .q(s2));

`ifdef SIM
    assign sym_b = s0;
    assign sym_g = s1;
    assign sym_r = s2;
    assign tmds_p = 4'b0;
    assign tmds_n = 4'b1111;
`else
    wire [9:0] sym [0:3];
    assign sym[0] = s0;
    assign sym[1] = s1;
    assign sym[2] = s2;
    assign sym[3] = 10'b0000011111;  // the clock: five 1s then five 0s per pixel

    genvar k;
    generate for (k = 0; k < 4; k = k + 1) begin : lane
        wire ser, shift1, shift2;
        OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("MASTER"),
                    .TRISTATE_WIDTH(1)) master (
            .OQ(ser), .OFB(), .TQ(), .TFB(), .SHIFTOUT1(), .SHIFTOUT2(), .TBYTEOUT(),
            .CLK(sclk), .CLKDIV(pclk),
            .D1(sym[k][0]), .D2(sym[k][1]), .D3(sym[k][2]), .D4(sym[k][3]),
            .D5(sym[k][4]), .D6(sym[k][5]), .D7(sym[k][6]), .D8(sym[k][7]),
            .OCE(1'b1), .RST(rst), .SHIFTIN1(shift1), .SHIFTIN2(shift2),
            .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TBYTEIN(1'b0), .TCE(1'b0));
        OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("SLAVE"),
                    .TRISTATE_WIDTH(1)) slave (
            .OQ(), .OFB(), .TQ(), .TFB(), .SHIFTOUT1(shift1), .SHIFTOUT2(shift2), .TBYTEOUT(),
            .CLK(sclk), .CLKDIV(pclk),
            .D1(1'b0), .D2(1'b0), .D3(sym[k][8]), .D4(sym[k][9]),
            .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
            .OCE(1'b1), .RST(rst), .SHIFTIN1(1'b0), .SHIFTIN2(1'b0),
            .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TBYTEIN(1'b0), .TCE(1'b0));
        OBUFDS obuf (.I(ser), .O(tmds_p[k]), .OB(tmds_n[k]));
    end endgenerate
`endif
endmodule

// DVI 1.0's TMDS encoding: transition-minimised 8b/10b with DC balance, and
// the four control symbols during blanking.  One symbol per pixel clock.
module tmds_encoder (
    input            clk,
    input      [7:0] d,
    input      [1:0] c,
    input            de,
    output reg [9:0] q
);
    function [3:0] ones8(input [7:0] v);
        ones8 = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + v[7];
    endfunction

    wire [3:0] n1d = ones8(d);
    wire use_xnor = (n1d > 4) || (n1d == 4 && d[0] == 1'b0);
    wire [8:0] qm;
    assign qm[0] = d[0];
    genvar i;
    generate for (i = 1; i < 8; i = i + 1) begin : m
        assign qm[i] = use_xnor ? ~(qm[i - 1] ^ d[i]) : (qm[i - 1] ^ d[i]);
    end endgenerate
    assign qm[8] = ~use_xnor;

    wire [3:0] n1 = ones8(qm[7:0]);
    wire [3:0] n0 = 4'd8 - n1;
    wire signed [4:0] diff = $signed({1'b0, n1}) - $signed({1'b0, n0});
    reg signed [4:0] cnt = 0;   // running disparity

    always @(posedge clk) begin
        if (!de) begin
            cnt <= 0;
            case (c)
                2'b00: q <= 10'b1101010100;
                2'b01: q <= 10'b0010101011;
                2'b10: q <= 10'b0101010100;
                2'b11: q <= 10'b1010101011;
            endcase
        end else if (cnt == 0 || n1 == n0) begin
            q   <= {~qm[8], qm[8], qm[8] ? qm[7:0] : ~qm[7:0]};
            cnt <= qm[8] ? cnt + diff : cnt - diff;
        end else if ((cnt > 0 && n1 > n0) || (cnt < 0 && n0 > n1)) begin
            q   <= {1'b1, qm[8], ~qm[7:0]};
            cnt <= cnt + {3'b0, qm[8], 1'b0} - diff;
        end else begin
            q   <= {1'b0, qm[8], qm[7:0]};
            cnt <= cnt - {3'b0, ~qm[8], 1'b0} + diff;
        end
    end
endmodule
