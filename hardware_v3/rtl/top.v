// COMP80 v3: the PSI COMP80 in an Artix-7 XC7A100T.  Pins are in comp80v3.xdc.
// The screen goes out twice: HDMI (hdmi_out.v) and DisplayPort over USB-C (dp_out.v).
//
//   100 MHz oscillator -> PLL:  50 MHz system clock, 12 MHz for USB
//                      -> MMCM: 25 MHz pixel clock, 125 MHz serial clock
module top (
    input        clk100,
    input        btn_reset_n,         // the RESET button: power the COMP80 on again
    output [3:0] tmds_p, tmds_n,      // HDMI: 0 blue, 1 green, 2 red, 3 clock
    inout        usb_dp, usb_dm,      // the keyboard's USB-A socket
    output       sd_sck, sd_mosi, sd_cs_n,
    input        sd_miso,
    output       uart_tx,
    output       led_halt,
    // DisplayPort over the USB-C socket J7, and its USB-PD controller
    input        dp_refclk_p,         // 135 MHz
    input        dp_refclk_n,
    output [3:0] dp_tx_p, dp_tx_n,    // J7: 0 TX1, 1 RX1, 2 TX2, 3 RX2
    inout        dp_aux_p, dp_aux_n,  // J7's SBU pins
    inout        pd_scl, pd_sda,      // FUSB302
    input        pd_int_n,
    output       vbus_en,             // the monitor's VBUS switch
    input        vbus_flt_n
);
    // ------------------------------------------------------------ clocks
    wire pll_fb, pll_locked, clk50_u, clk12_u, clk50, clk12;
    PLLE2_BASE #(.CLKIN1_PERIOD(10.0), .CLKFBOUT_MULT(12), .DIVCLK_DIVIDE(1),
                 .CLKOUT0_DIVIDE(24), .CLKOUT1_DIVIDE(100)) pll (
        .CLKIN1(clk100), .CLKFBIN(pll_fb), .CLKFBOUT(pll_fb), .RST(1'b0), .PWRDWN(1'b0),
        .CLKOUT0(clk50_u), .CLKOUT1(clk12_u), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(pll_locked));
    BUFG b50 (.I(clk50_u), .O(clk50));
    BUFG b12 (.I(clk12_u), .O(clk12));

    wire mmcm_fb, mmcm_locked, pclk_u, sclk_u, pclk, sclk;
    MMCME2_BASE #(.CLKIN1_PERIOD(10.0), .CLKFBOUT_MULT_F(6.25), .DIVCLK_DIVIDE(1),
                  .CLKOUT0_DIVIDE_F(25.0), .CLKOUT1_DIVIDE(5)) mmcm (
        .CLKIN1(clk100), .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb), .CLKFBOUTB(), .RST(1'b0), .PWRDWN(1'b0),
        .CLKOUT0(pclk_u), .CLKOUT0B(), .CLKOUT1(sclk_u), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .LOCKED(mmcm_locked));
    BUFG bp (.I(pclk_u), .O(pclk));
    BUFG bs (.I(sclk_u), .O(sclk));

    // ------------------------------------------------------------ resets
    reg [15:0] por = 0;
    reg [1:0]  btn_s;
    always @(posedge clk50) begin
        btn_s <= {btn_s[0], btn_reset_n};
        if (!pll_locked || !btn_s[1]) por <= 0;
        else if (!por[15]) por <= por + 16'd1;
    end
    wire rst = !por[15];
    reg [1:0] prst_s, urst_s;
    always @(posedge pclk) prst_s <= {prst_s[0], rst || !mmcm_locked};
    always @(posedge clk12) urst_s <= {urst_s[0], rst};

    // ------------------------------------------------------------ the machine
    wire        z80_run, clk4, expansion, menu_on, key_strobe, key_full, halted;
    wire [23:0] colour;
    wire [7:0]  key_code, mm_cmd, mm_status, h_wdata, h_rdata, scr_data, menu_data;
    wire        mm_cmd_new, mm_done, mm_irq, tape_in, tape_out, h_we, scr_we, menu_we;
    wire [15:0] h_addr;
    wire [10:0] scr_addr, menu_addr;
    wire [39:0] cycles;

    comp80_machine #(.SYS_HZ(50_000_000)) machine (
        .clk(clk50), .rst(rst || !z80_run), .clk4(clk4), .expansion(expansion),
        .h_addr(h_addr), .h_wdata(h_wdata), .h_we(h_we), .h_rdata(h_rdata),
        .key_strobe(key_strobe), .key_code(key_code), .key_full(key_full),
        .mm_cmd(mm_cmd), .mm_cmd_new(mm_cmd_new), .mm_done(mm_done), .mm_status(mm_status), .mm_irq(mm_irq),
        .tape_in(tape_in), .tape_out(tape_out),
        .scr_we(scr_we), .scr_addr(scr_addr), .scr_data(scr_data),
        .halted(halted), .cycles(cycles));
    assign led_halt = halted;

    // ------------------------------------------------------------ USB keyboard (12 MHz domain)
    wire [1:0] typ;
    wire       report;
    wire [7:0] kmod, k1, k2, k3, k4;
    usb_hid_host usb (
        .usbclk(clk12), .usbrst_n(!urst_s[1]), .usb_dm(usb_dm), .usb_dp(usb_dp),
        .typ(typ), .report(report), .conerr(),
        .key_modifiers(kmod), .key1(k1), .key2(k2), .key3(k3), .key4(k4),
        .mouse_btn(), .mouse_dx(), .mouse_dy(),
        .game_l(), .game_r(), .game_u(), .game_d(), .game_a(), .game_b(), .game_x(), .game_y(),
        .game_sel(), .game_sta(), .dbg_hid_report());
    // a toggle per report crosses to the system clock; the key registers hold
    // still for the 8 ms or more until the next one
    reg usb_tog;
    always @(posedge clk12) if (report) usb_tog <= ~usb_tog;
    reg [2:0]  tog_s;
    reg [41:0] keys_s;
    always @(posedge clk50) begin
        tog_s  <= {tog_s[1:0], usb_tog};
        keys_s <= {typ, kmod, k4, k3, k2, k1};
    end

    // ------------------------------------------------------------ the system controller
    wire sd_cs;
    wire       dp_hpd, dp_aux_invert, dp_link_up, pd_scl_low, pd_sda_low;
    wire [7:0] dp_lane_sel;
    assign pd_scl = pd_scl_low ? 1'b0 : 1'bz;     // open drain, pulled up on the board
    assign pd_sda = pd_sda_low ? 1'b0 : 1'bz;
    soc #(.SYS_HZ(50_000_000)) soc (
        .clk(clk50), .rst(rst), .uart_tx(uart_tx),
        .z80_run(z80_run), .clk4(clk4), .expansion(expansion), .menu_on(menu_on), .colour(colour),
        .key_strobe(key_strobe), .key_code(key_code), .key_full(key_full), .halted(halted),
        .mm_cmd(mm_cmd), .mm_cmd_new(mm_cmd_new), .mm_status(mm_status), .mm_done(mm_done), .mm_irq(mm_irq),
        .tape_in(tape_in), .tape_out(tape_out), .cycles(cycles),
        .h_addr(h_addr), .h_wdata(h_wdata), .h_we(h_we), .h_rdata(h_rdata),
        .menu_we(menu_we), .menu_addr(menu_addr), .menu_data(menu_data),
        .usb_report(tog_s[2]), .usb_typ(keys_s[41:40]), .usb_mod(keys_s[39:32]), .usb_keys(keys_s[31:0]),
        .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso), .sd_cs(sd_cs),
        .dp_hpd(dp_hpd), .dp_aux_invert(dp_aux_invert), .dp_lane_sel(dp_lane_sel), .dp_link_up(dp_link_up),
        .pd_scl_low(pd_scl_low), .pd_sda_low(pd_sda_low), .vbus_en(vbus_en),
        .pd_scl(pd_scl), .pd_sda(pd_sda), .pd_int_n(pd_int_n), .vbus_flt_n(vbus_flt_n));
    assign sd_cs_n = sd_cs;

    // ------------------------------------------------------------ display
    wire [7:0] r, g, b;
    wire       hs, vs, de;
    video video (
        .clk(clk50), .scr_we(scr_we), .scr_addr(scr_addr), .scr_data(scr_data),
        .menu_we(menu_we), .menu_addr(menu_addr), .menu_data(menu_data),
        .menu_on(menu_on), .colour(colour),
        .pclk(pclk), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de));
    // the same screen again, over DisplayPort at 800 x 600
    wire clk100_g;
    BUFG b100 (.I(clk100), .O(clk100_g));
    wire dp_link_up_100;
    reg [1:0] link_s;
    always @(posedge clk50) link_s <= {link_s[0], dp_link_up_100};
    assign dp_link_up = link_s[1];
    dp_out dp (
        .clk100(clk100_g), .refclk_p(dp_refclk_p), .refclk_n(dp_refclk_n),
        .gtp_p(dp_tx_p), .gtp_n(dp_tx_n), .aux_p(dp_aux_p), .aux_n(dp_aux_n),
        .hpd(dp_hpd), .lane_sel(dp_lane_sel), .aux_invert(dp_aux_invert), .link_up(dp_link_up_100),
        .clk(clk50), .scr_we(scr_we), .scr_addr(scr_addr), .scr_data(scr_data),
        .menu_we(menu_we), .menu_addr(menu_addr), .menu_data(menu_data), .menu_on(menu_on), .colour(colour));

    hdmi_out hdmi (.pclk(pclk), .sclk(sclk), .rst(prst_s[1]), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de),
                   .tmds_p(tmds_p), .tmds_n(tmds_n));
endmodule
