// The COMP80's display, for HDMI: 640 x 480 at 60 Hz (25 MHz pixel clock),
// the 64 x 32 characters drawn 10 x 15 pixels each, as the v2 firmware draws
// them: dot columns 1,2,2,1,2,2 pixels wide, rows alternately 2 and 1 high.
// The characters come from the display's own copy of the screen (written
// through as the Z80 writes 8000-87FF) or, with menu_on, from the soft
// processor's set-up screen.  font.hex holds the COMP80's two character sets,
// made from the MAME driver's tables by ../tools/make_font.py.
module video (
    input             clk,          // system clock: the write ports
    input             scr_we,
    input      [10:0] scr_addr,
    input      [7:0]  scr_data,
    input             menu_we,
    input      [10:0] menu_addr,
    input      [7:0]  menu_data,
    input             menu_on,      // quasi-static, from the system clock domain
    input      [23:0] colour,       // RGB of the dots, likewise

    input             pclk,         // 25 MHz pixel clock
    output reg [7:0]  r, g, b,
    output reg        hs, vs, de
);
    localparam H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_TOTAL = 800;
    localparam V_ACTIVE = 480, V_FP = 10, V_SYNC = 2, V_TOTAL = 525;

    // ------------------------------------------------------------ the screens
    reg [7:0] scr  [0:2047];
    reg [7:0] menu [0:2047];
    reg [5:0] font [0:2047];        // {graphics, code, row} -> 6 dots, bit 5 leftmost
    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1) begin scr[i] = 8'h20; menu[i] = 8'h20; end
        $readmemh("font.hex", font);
    end
    always @(posedge clk) if (scr_we)  scr[scr_addr]   <= scr_data;
    always @(posedge clk) if (menu_we) menu[menu_addr] <= menu_data;

    // the settings, brought into the pixel clock domain
    reg [1:0]  menu_s = 0;
    reg [23:0] colour_s;
    always @(posedge pclk) begin menu_s <= {menu_s[0], menu_on}; colour_s <= colour; end

    // ------------------------------------------------------------ timing
    reg [9:0] x = 0, y = 0;
    reg [5:0] cx = 0;  reg [3:0] sx = 0;    // character column 0-63, pixel within it 0-9
    reg [4:0] cy = 0;  reg [3:0] sy = 0;    // character row 0-31, line within it 0-14
    always @(posedge pclk) begin
        if (x == H_TOTAL - 1) begin
            x <= 0;
            y <= (y == V_TOTAL - 1) ? 10'd0 : y + 10'd1;
            if (y == V_TOTAL - 1) begin cy <= 0; sy <= 0; end
            else if (y < V_ACTIVE) begin
                if (sy == 14) begin sy <= 0; cy <= cy + 5'd1; end else sy <= sy + 4'd1;
            end
        end else x <= x + 10'd1;
        if (x == H_TOTAL - 1) begin cx <= 0; sx <= 0; end
        else if (sx == 9) begin sx <= 0; cx <= cx + 6'd1; end
        else sx <= sx + 4'd1;
    end

    // which of the cell's 6 dot columns and 10 rows a pixel shows
    function [2:0] dot_col(input [3:0] p);
        case (p) 0: dot_col = 0; 1, 2: dot_col = 1; 3, 4: dot_col = 2; 5: dot_col = 3; 6, 7: dot_col = 4; default: dot_col = 5; endcase
    endfunction
    function [3:0] dot_row(input [3:0] p);
        case (p) 0, 1: dot_row = 0; 2: dot_row = 1; 3, 4: dot_row = 2; 5: dot_row = 3; 6, 7: dot_row = 4;
                 8: dot_row = 5; 9, 10: dot_row = 6; 11: dot_row = 7; 12, 13: dot_row = 8; default: dot_row = 9; endcase
    endfunction

    // ------------------------------------------------------------ pipeline
    // 1: read the character; 2: read its row of dots; 3: pick the dot
    reg [7:0] scr_q, menu_q;
    reg [5:0] font_q;
    reg [2:0] col1, col2;
    reg [3:0] row1;
    reg [2:0] de_p = 0, hs_p = 0, vs_p = 0;
    wire active = (x < H_ACTIVE) && (y < V_ACTIVE);
    always @(posedge pclk) begin
        scr_q  <= scr[{cy, cx}];
        menu_q <= menu[{cy, cx}];
        col1   <= dot_col(sx);
        row1   <= dot_row(sy);
        de_p   <= {de_p[1:0], active};
        hs_p   <= {hs_p[1:0], !(x >= H_ACTIVE + H_FP && x < H_ACTIVE + H_FP + H_SYNC)};
        vs_p   <= {vs_p[1:0], !(y >= V_ACTIVE + V_FP && y < V_ACTIVE + V_FP + V_SYNC)};

        font_q <= font[{menu_s[1] ? {menu_q[6], menu_q[5:0]} : {scr_q[6], scr_q[5:0]}, row1}];
        col2   <= col1;

        de <= de_p[1];
        hs <= hs_p[1];
        vs <= vs_p[1];
        {r, g, b} <= (de_p[1] && font_q[3'd5 - col2]) ? colour_s : 24'h000000;
    end
endmodule
