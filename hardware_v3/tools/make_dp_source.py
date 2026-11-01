"""Write ../rtl/dp_comp80_source.v: hamsternz's 800 x 600, one-lane DisplayPort
colour-bar source (DisplayPort_Verilog, MIT licence) with the colour bars
replaced by the COMP80's screen.

  python3 make_dp_source.py      (after tools/fetch.sh)

His module emits the stream's symbols (blank start and end, fill, the MSA
slots, pixel bytes) for 800 x 600 at 60 Hz on one 2.7 Gb/s lane. Only the
pixel values change here: each 6 x 10 character cell is drawn 12 x 18 pixels
(dot columns 2 pixels wide, rows 2,2,2,2,1,2,2,2,2,1 high), 768 x 576 with a
border. A two-line buffer of dot rows is filled for the next line while the
current one goes out, from the module's own copies of the screen, the set-up
screen and the font.
"""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parent / "build" / "DisplayPort_Verilog" / "src" / "test_streams" / "test_source_800_600_RGB_444_colourbar.v"
OUT = HERE.parent / "rtl" / "dp_comp80_source.v"

PORTS_OLD = """        input             clk,
        output reg        ready,
        output reg [72:0] data
    );"""
PORTS_NEW = """        input             clk,
        output reg        ready,
        output reg [72:0] data,
        // the COMP80's screen, written from the system clock domain
        input             wclk,
        input             scr_we,
        input      [10:0] scr_addr,
        input       [7:0] scr_data,
        input             menu_we,
        input      [10:0] menu_addr,
        input       [7:0] menu_data,
        input             menu_on,        // quasi-static
        input      [23:0] colour          // quasi-static, RGB
    );"""

PIXELS_NEW = r"""    /////////////////////////////////////////////
    // COMP80 v3: the screen instead of colour bars
    /////////////////////////////////////////////
    if(switch_point_last == 1'b0 && switch_point == 1'b1) begin
       pixel_count <= 19'b0;
       line_y      <= 10'd0;
       pixels      <= 48'h000000000000;
    end else if(d1 == PIX_12) begin    // Can only be used for d1
       // the next pair of pixels: two of the same dot
       if(pixel_count == 798) begin
         pixel_count <= 19'b0;
         line_y      <= line_y + 10'd1;
         pixels      <= 48'h000000000000;   // the next line starts in the border
       end else begin
         pixel_count <= pixel_count + 2;
         pixels      <= next_dot ? {colour_s, colour_s} : 48'h000000000000;
       end
    end
    switch_point_last <= switch_point;

    //////////////////////////////////////////////////
    // Line buffer requests: lines 0 and 1 at the start of a frame, then the
    // line two ahead each time a line ends, into the buffer it used
    //////////////////////////////////////////////////
    if(switch_point_last == 1'b0 && switch_point == 1'b1) begin
       fill_req    <= 1'b1;
       fill_second <= 1'b1;
       fill_line   <= 10'd0;
       fill_row    <= 5'd0;
       fill_sub    <= 5'd0;
    end else if(d1 == PIX_12 && pixel_count == 798 && line_y + 10'd2 < 10'd600) begin
       fill_req    <= 1'b1;
    end else if(fill_req && !filling) begin
       fill_req    <= 1'b0;                 // taken
    end else if(fill_done && fill_second) begin
       fill_req    <= 1'b1;
       fill_second <= 1'b0;
    end

    //////////////////////////////////////////////////
    // The line buffer filler: 64 cells of the line fill_line
    //////////////////////////////////////////////////
    fill_done <= 1'b0;
    if(fill_req && !filling) begin
       filling  <= 1'b1;
       fill_c   <= 7'd0;
       fill_act <= (fill_line >= 10'd12) && (fill_line < 10'd588);
    end else if(filling) begin
       fill_c <= fill_c + 7'd1;
       if(fill_c == 7'd66) begin
          filling   <= 1'b0;
          fill_done <= 1'b1;
          // step the fill counters to the next line
          fill_line <= fill_line + 10'd1;
          if(fill_line >= 10'd12) begin
             if(fill_sub == 5'd17) begin fill_sub <= 5'd0; fill_row <= fill_row + 5'd1; end
             else fill_sub <= fill_sub + 5'd1;
          end
       end
    end
    // three stages: the character, its row of dots, into the buffer
    chr_q  <= menu_s[1] ? menu[{fill_row, fill_c[5:0]}] : scr[{fill_row, fill_c[5:0]}];
    c1     <= fill_c;
    font_q <= font[{chr_q[6], chr_q[5:0], dot_row(fill_sub)}];
    c2     <= c1;
    if(filling && c2 < 7'd64)
       linebuf[{fill_line[0], c2[5:0]}] <= fill_act ? font_q : 6'b000000;

"""

DECLS = r"""    // ---- COMP80 v3 additions -------------------------------------
    reg [7:0] scr  [0:2047];
    reg [7:0] menu [0:2047];
    reg [5:0] font [0:2047];          // {graphics, code, row}: 6 dots, bit 5 leftmost
    reg [5:0] linebuf [0:127];        // two lines of 64 cells' dot rows
    integer   k;
    initial begin
        for (k = 0; k < 2048; k = k + 1) begin scr[k] = 8'h20; menu[k] = 8'h20; end
        for (k = 0; k < 128; k = k + 1) linebuf[k] = 6'b0;
        $readmemh("font.hex", font);
    end
    always @(posedge wclk) if (scr_we)  scr[scr_addr]   <= scr_data;
    always @(posedge wclk) if (menu_we) menu[menu_addr] <= menu_data;
    reg  [1:0] menu_s = 2'b00;
    reg [23:0] colour_s = 24'hffffff;
    // pixels go out byte 0 first, and DisplayPort sends red first: {blue, green, red}
    always @(posedge clk) begin menu_s <= {menu_s[0], menu_on}; colour_s <= {colour[7:0], colour[15:8], colour[23:16]}; end

    function [3:0] dot_row(input [4:0] s);
        case (s) 0, 1: dot_row = 0; 2, 3: dot_row = 1; 4, 5: dot_row = 2; 6, 7: dot_row = 3; 8: dot_row = 4;
                 9, 10: dot_row = 5; 11, 12: dot_row = 6; 13, 14: dot_row = 7; 15, 16: dot_row = 8; default: dot_row = 9; endcase
    endfunction

    reg  [9:0] line_y = 0;
    reg        fill_req = 0, fill_second = 0, filling = 0, fill_done = 0, fill_act = 0;
    reg  [9:0] fill_line = 0;
    reg  [4:0] fill_row = 0, fill_sub = 0;
    reg  [6:0] fill_c = 0, c1 = 0, c2 = 0;
    reg  [7:0] chr_q = 0;
    reg  [5:0] font_q = 0;
    // the dot the next pair of pixels shows: x = pixel_count + 2
    wire [10:0] nx    = pixel_count[10:0] + 11'd2 - 11'd16;
    wire        nx_in = (pixel_count + 2 >= 16) && (pixel_count + 2 < 784);
    wire  [5:0] ncell = nx / 12;
    wire  [2:0] ndot  = (nx % 12) / 2;
    wire  [5:0] nbits = linebuf[{line_y[0], ncell}];
    wire        next_dot = nx_in && (line_y >= 12) && (line_y < 588) && nbits[3'd5 - ndot];
    // ---------------------------------------------------------------
"""


def main():
    s = SRC.read_text()
    s = s.replace("test_source_800_600_RGB_444_colourbar.v : A hack at making a colour bar",
                  "dp_comp80_source.v : the COMP80's screen as an 800 x 600 DisplayPort stream\n"
                  "//\n// Made by hardware_v3/tools/make_dp_source.py from Mike Field's\n"
                  "// test_source_800_600_RGB_444_colourbar.v (commit 3d509d4), which it keeps\n"
                  "// but for the ports, the pixel values and the line buffer that feeds them")
    s = s.replace("module test_source_800_600_RGB_444_colourbar(", "module dp_comp80_source(")
    assert PORTS_OLD in s
    s = s.replace(PORTS_OLD, PORTS_NEW)
    a = s.index("    /////////////////////////////////////////////\n    // Detect the start of frame to reset counter")
    b = s.index("    ///////////////////////////////////////////////\n    // Stage 1 of video pipeline")
    s = s[:a] + PIXELS_NEW + s[b:]
    # the declarations go before the first always block
    i = s.index("initial begin")
    s = s[:i] + DECLS + s[i:]
    OUT.write_text(s)
    print("wrote", OUT.relative_to(HERE.parent))


if __name__ == "__main__":
    main()
