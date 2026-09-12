`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/22/2025 01:37:32 PM
// Design Name: 
// Module Name: ClkDiv_5Hz
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module ClkDiv_5Hz(
    input CLK,
    input RST,
    output reg CLKOUT = 1'b0
    );

    reg [23:0] clkCount = 24'h000000;
    parameter [23:0] cntEndVal = 24'h989680;  // 10,000,000 for 5Hz

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            CLKOUT   <= 1'b0;
            clkCount <= 24'h000000;
        end else begin
            if (clkCount == cntEndVal) begin
                CLKOUT   <= ~CLKOUT;
                clkCount <= 24'h000000;
            end else begin
                clkCount <= clkCount + 1'b1;
            end
        end
    end
endmodule