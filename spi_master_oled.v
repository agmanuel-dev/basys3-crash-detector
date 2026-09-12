`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Simple SPI Master - 8-bit, MSB first, Mode 0-ish, single-byte transfers
//////////////////////////////////////////////////////////////////////////////////
module spi_master #(
    parameter CLK_DIV = 4   // divide 100 MHz clock -> SPI clock (100MHz/CLK_DIV/2)
)(
    input  wire clk,
    input  wire rst,

    input  wire       start,    // pulse high to start sending data_in
    input  wire [7:0] data_in,  // byte to send

    output reg        done,     // goes high for 1 clk when finished
    output reg        busy,     // 1 while transfer in progress

    output reg        cs,       // chip select (active low)
    output reg        mosi,     // master-out, slave-in
    output reg        sclk      // spi clock (idle low)
);

    localparam S_IDLE  = 2'd0;
    localparam S_TRANS = 2'd1;
    localparam S_DONE  = 2'd2;

    reg [1:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;
    reg [15:0] clk_cnt;
    reg       phase;           // 0: setup data, 1: toggle clock high

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            cs        <= 1'b1;
            sclk      <= 1'b0;
            mosi      <= 1'b0;
            done      <= 1'b0;
            busy      <= 1'b0;
            shift_reg <= 8'd0;
            bit_cnt   <= 3'd0;
            clk_cnt   <= 16'd0;
            phase     <= 1'b0;
        end else begin
            done <= 1'b0;  // default: only pulse for one cycle

            case (state)
                S_IDLE: begin
                    cs   <= 1'b1;
                    sclk <= 1'b0;
                    busy <= 1'b0;
                    clk_cnt <= 0;
                    phase   <= 0;

                    if (start) begin
                        // latch data and begin transfer
                        shift_reg <= data_in;
                        bit_cnt   <= 3'd7;   // MSB first
                        cs        <= 1'b0;   // select device
                        busy      <= 1'b1;
                        state     <= S_TRANS;
                    end
                end

                S_TRANS: begin
                    // clock divider
                    if (clk_cnt == (CLK_DIV - 1)) begin
                        clk_cnt <= 0;
                        phase   <= ~phase;

                        if (phase == 1'b0) begin
                            // phase 0: put data on MOSI, keep SCLK low
                            mosi <= shift_reg[7];
                            sclk <= 1'b0;
                        end else begin
                            // phase 1: toggle SCLK high so slave can sample
                            sclk <= 1'b1;

                            if (bit_cnt == 0) begin
                                // last bit just sent
                                state <= S_DONE;
                            end else begin
                                // shift to next bit
                                shift_reg <= {shift_reg[6:0], 1'b0};
                                bit_cnt   <= bit_cnt - 1;
                            end
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DONE: begin
                    cs   <= 1'b1;  // deselect device
                    sclk <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b1;  // pulse done
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
