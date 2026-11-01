// A byte-wide SPI master (mode 0) for the microSD card: writing a byte sends
// it and clocks one back.  The clock is clk / (2 * (div + 1)).
module spi_master (
    input            clk,
    input            rst,
    input      [7:0] div,
    input            start,
    input      [7:0] tx,
    output reg [7:0] rx,
    output           busy,
    output reg       sck,
    output           mosi,
    input            miso
);
    reg [7:0] sh;
    reg [3:0] bits;
    reg [7:0] cnt;
    assign busy = bits != 0;
    assign mosi = sh[7];
    always @(posedge clk) begin
        if (rst) begin
            bits <= 0; sck <= 0; sh <= 8'hff;
        end else if (start && !busy) begin
            sh <= tx; bits <= 4'd8; cnt <= div; sck <= 0;
        end else if (busy) begin
            if (cnt != 0) cnt <= cnt - 8'd1;
            else begin
                cnt <= div;
                if (!sck) begin
                    sck <= 1'b1;                    // rising edge: sample
                    rx  <= {rx[6:0], miso};
                end else begin
                    sck  <= 1'b0;                   // falling edge: next bit out
                    sh   <= {sh[6:0], 1'b1};
                    bits <= bits - 4'd1;
                end
            end
        end
    end
endmodule
