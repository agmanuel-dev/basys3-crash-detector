`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/21/2025 09:43:04 AM
// Design Name: 
// Module Name: adxl345_spi
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

//////////////////////////////////////////////////////////////////////////////////
// ADXL345 SPI Interface Module
// Handles SPI communication with ADXL345 accelerometer
//////////////////////////////////////////////////////////////////////////////////

module SPIcomponent(
    input CLK,
    input RST,
    input START,
    input SDI,
    output SDO,
    output SCLK,
    output SS,
    output [9:0] xAxis,
    output [9:0] yAxis,
    output [9:0] zAxis
    );

    wire [15:0] TxBuffer;
    wire [7:0] RxBuffer;
    wire done;
    wire transmit;

    SPImaster master(
        .rst(RST),
        .start(START),
        .clk(CLK),
        .transmit(transmit),
        .txdata(TxBuffer),
        .rxdata(RxBuffer),
        .done(done),
        .x_axis_data(xAxis),
        .y_axis_data(yAxis),
        .z_axis_data(zAxis)
    );

    SPIinterface interface(
        .sdi(SDI),
        .sdo(SDO),
        .rst(RST),
        .clk(CLK),
        .sclk(SCLK),
        .txbuffer(TxBuffer),
        .rxbuffer(RxBuffer),
        .done_out(done),
        .transmit(transmit)
    );

    slaveSelect ss_ctrl(
        .clk(CLK),
        .ss(SS),
        .done(done),
        .transmit(transmit),
        .rst(RST)
    );

endmodule

//////////////////////////////////////////////////////////////////////////////////
// SPI Master Controller
//////////////////////////////////////////////////////////////////////////////////
module SPImaster(
    input rst,
    input clk,
    input start,
    input [7:0] rxdata,
    input done,
    output reg transmit = 1'b0,
    output reg [15:0] txdata = 16'h0000,
    output reg [9:0] x_axis_data = 10'b0,
    output reg [9:0] y_axis_data = 10'b0,
    output reg [9:0] z_axis_data = 10'b0
    );

    // Configuration registers
    parameter [15:0] POWER_CTL = 16'h2D08;      // Measurement mode
    parameter [15:0] BW_RATE = 16'h2C0A;        // 100Hz
    parameter [15:0] DATA_FORMAT = 16'h3100;    // ±2g

    // Read registers (single byte, increment)
    parameter [15:0] xAxis0 = 16'hB200;
    parameter [15:0] xAxis1 = 16'hB300;
    parameter [15:0] yAxis0 = 16'hB400;
    parameter [15:0] yAxis1 = 16'hB500;
    parameter [15:0] zAxis0 = 16'hB600;
    parameter [15:0] zAxis1 = 16'hB700;

    // FSM states
    parameter [2:0]
        IDLE = 3'd0,
        CONFIGURE = 3'd1,
        TRANSMITTING = 3'd2,
        RECEIVING = 3'd3,
        FINISHED = 3'd4,
        BREAK = 3'd5,
        HOLDING = 3'd6;

    reg [2:0] STATE = IDLE;

    // Configuration sequence
    parameter [1:0]
        CFG_POWER = 2'd0,
        CFG_BW = 2'd1,
        CFG_FORMAT = 2'd2;

    reg [1:0] CONFIG_SEL = CFG_POWER;

    // Data selection
    parameter [1:0]
        DATA_X = 2'd0,
        DATA_Y = 2'd1,
        DATA_Z = 2'd2;

    reg [1:0] DATA_SEL = DATA_X;

    reg [11:0] break_count = 12'h000;
    reg [20:0] hold_count = 21'h00000;
    reg done_configure = 1'b0;
    reg register_select = 1'b0;
    reg finish = 1'b0;
    reg sample_done = 1'b0;
    reg end_configure = 1'b0;
    reg [3:0] prevstart = 4'b0;

    always @(posedge clk) begin
        prevstart <= {prevstart[2:0], start};

        if (rst) begin
            transmit <= 1'b0;
            STATE <= IDLE;
            DATA_SEL <= DATA_X;
            break_count <= 12'h000;
            hold_count <= 21'h00000;
            done_configure <= 1'b0;
            CONFIG_SEL <= CFG_POWER;
            txdata <= 16'h0000;
            register_select <= 1'b0;
            sample_done <= 1'b0;
            finish <= 1'b0;
            x_axis_data <= 10'b0;
            y_axis_data <= 10'b0;
            z_axis_data <= 10'b0;
            end_configure <= 1'b0;
        end
        else begin
            case (STATE)
                IDLE: begin
                    if (!done_configure) begin
                        STATE <= CONFIGURE;
                        txdata <= POWER_CTL;
                        transmit <= 1'b1;
                    end
                    else if (prevstart == 4'b0011 && start && done_configure) begin
                        STATE <= TRANSMITTING;
                        finish <= 1'b0;
                        txdata <= xAxis0;
                        sample_done <= 1'b0;
                    end
                end

                CONFIGURE: begin
                    case (CONFIG_SEL)
                        CFG_POWER: begin
                            STATE <= FINISHED;
                            CONFIG_SEL <= CFG_BW;
                            transmit <= 1'b1;
                        end
                        CFG_BW: begin
                            txdata <= BW_RATE;
                            STATE <= FINISHED;
                            CONFIG_SEL <= CFG_FORMAT;
                            transmit <= 1'b1;
                        end
                        CFG_FORMAT: begin
                            txdata <= DATA_FORMAT;
                            STATE <= FINISHED;
                            transmit <= 1'b1;
                            finish <= 1'b1;
                            end_configure <= 1'b1;
                        end
                    endcase
                end

                TRANSMITTING: begin
                    case (DATA_SEL)
                        DATA_X: begin
                            STATE <= RECEIVING;
                            transmit <= 1'b1;
                        end
                        DATA_Y: begin
                            STATE <= RECEIVING;
                            transmit <= 1'b1;
                        end
                        DATA_Z: begin
                            STATE <= RECEIVING;
                            transmit <= 1'b1;
                        end
                    endcase
                end

                RECEIVING: begin
                    case (DATA_SEL)
                        DATA_X: begin
                            case (register_select)
                                1'b0: begin
                                    transmit <= 1'b0;
                                    if (done) begin
                                        txdata <= xAxis1;
                                        x_axis_data[7:0] <= rxdata[7:0];
                                        STATE <= FINISHED;
                                        register_select <= 1'b1;
                                    end
                                end
                                default: begin
                                    transmit <= 1'b0;
                                    if (done) begin
                                        txdata <= yAxis0;
                                        x_axis_data[9:8] <= rxdata[1:0];
                                        register_select <= 1'b0;
                                        DATA_SEL <= DATA_Y;
                                        STATE <= FINISHED;
                                    end
                                end
                            endcase
                        end

                        DATA_Y: begin
                            case (register_select)
                                1'b0: begin
                                    transmit <= 1'b0;
                                    if (done) begin
                                        txdata <= yAxis1;
                                        y_axis_data[7:0] <= rxdata[7:0];
                                        register_select <= 1'b1;
                                        STATE <= FINISHED;
                                    end
                                end
                                default: begin
                                    transmit <= 1'b0;
                                    if (done) begin
                                        txdata <= zAxis0;
                                        y_axis_data[9:8] <= rxdata[1:0];
                                        register_select <= 1'b0;
                                        DATA_SEL <= DATA_Z;
                                        STATE <= FINISHED;
                                    end
                                end
                            endcase
                        end

                        DATA_Z: begin
                            case (register_select)
                                1'b0: begin
                                    transmit <= 1'b0;
                                    if (done) begin
                                        txdata <= zAxis1;
                                        z_axis_data[7:0] <= rxdata[7:0];
                                        register_select <= 1'b1;
                                        STATE <= FINISHED;
                                    end
                                end
                                default: begin
                                    transmit <= 1'b0;
                                    if (done) begin
                                        txdata <= xAxis0;
                                        z_axis_data[9:8] <= rxdata[1:0];
                                        register_select <= 1'b0;
                                        DATA_SEL <= DATA_X;
                                        STATE <= FINISHED;
                                        sample_done <= 1'b1;
                                    end
                                end
                            endcase
                        end
                    endcase
                end

                FINISHED: begin
                    transmit <= 1'b0;
                    if (done) begin
                        STATE <= BREAK;
                        if (end_configure)
                            done_configure <= 1'b1;
                    end
                end

                BREAK: begin
                    if (break_count == 12'hFFF) begin
                        break_count <= 12'h000;
                        if ((finish || sample_done) && !start) begin
                            STATE <= IDLE;
                            txdata <= xAxis0;
                        end
                        else if (sample_done && start)
                            STATE <= HOLDING;
                        else if (done_configure && !sample_done) begin
                            STATE <= TRANSMITTING;
                            transmit <= 1'b1;
                        end
                        else if (!done_configure)
                            STATE <= CONFIGURE;
                    end
                    else
                        break_count <= break_count + 1'b1;
                end

                HOLDING: begin
                    if (hold_count == 21'h1FFFFF) begin
                        hold_count <= 21'h00000;
                        STATE <= TRANSMITTING;
                        sample_done <= 1'b0;
                    end
                    else if (!start) begin
                        STATE <= IDLE;
                        hold_count <= 21'h00000;
                    end
                    else
                        hold_count <= hold_count + 1'b1;
                end
            endcase
        end
    end
endmodule

//////////////////////////////////////////////////////////////////////////////////
// SPI Interface
//////////////////////////////////////////////////////////////////////////////////
module SPIinterface(
    input [15:0] txbuffer,
    output [7:0] rxbuffer,
    input transmit,
    output done_out,
    input sdi,
    output reg sdo = 1'b1,
    input rst,
    input clk,
    output sclk
    );

    parameter [7:0] CLKDIVIDER = 8'hFF;  // ~98kHz SCLK

    parameter [1:0]
        TX_IDLE = 2'd0,
        TX_TRANSMITTING = 2'd1;

    parameter [1:0]
        RX_IDLE = 2'd0,
        RX_RECEIVING = 2'd1;

    parameter [1:0]
        SCK_IDLE = 2'd0,
        SCK_RUNNING = 2'd1;

    reg [7:0] clk_count = 8'd0;
    reg clk_edge_buffer = 1'b0;
    reg sck_previous = 1'b1;
    reg sck_buffer = 1'b1;
    reg [15:0] tx_shift_register = 16'h0000;
    reg [3:0] tx_count = 4'h0;
    reg [7:0] rx_shift_register = 8'h00;
    reg [3:0] rx_count = 4'h0;
    reg done = 1'b0;
    reg [1:0] TxSTATE = TX_IDLE;
    reg [1:0] RxSTATE = RX_IDLE;
    reg [1:0] SCLKSTATE = SCK_IDLE;

    // Transmission
    always @(posedge clk) begin
        if (rst) begin
            tx_shift_register <= 16'd0;
            tx_count <= 4'd0;
            sdo <= 1'b1;
            TxSTATE <= TX_IDLE;
        end
        else begin
            case (TxSTATE)
                TX_IDLE: begin
                    tx_shift_register <= txbuffer;
                    if (transmit)
                        TxSTATE <= TX_TRANSMITTING;
                    else if (done)
                        sdo <= 1'b1;
                end
                TX_TRANSMITTING: begin
                    if (sck_previous && !sck_buffer) begin
                        if (tx_count == 4'b1111) begin
                            TxSTATE <= TX_IDLE;
                            tx_count <= 4'd0;
                            sdo <= tx_shift_register[15];
                        end
                        else begin
                            tx_count <= tx_count + 1'b1;
                            sdo <= tx_shift_register[15];
                            tx_shift_register <= {tx_shift_register[14:0], 1'b0};
                        end
                    end
                end
            endcase
        end
    end

    // Reception
    always @(posedge clk) begin
        if (rst) begin
            rx_shift_register <= 8'h00;
            rx_count <= 4'h0;
            done <= 1'b0;
            RxSTATE <= RX_IDLE;
        end
        else begin
            case (RxSTATE)
                RX_IDLE: begin
                    if (transmit) begin
                        RxSTATE <= RX_RECEIVING;
                        rx_shift_register <= 8'h00;
                    end
                    else if (SCLKSTATE == RX_IDLE)
                        done <= 1'b0;
                end
                RX_RECEIVING: begin
                    if (!sck_previous && sck_buffer) begin
                        if (rx_count == 4'b1111) begin
                            RxSTATE <= RX_IDLE;
                            rx_count <= 4'd0;
                            rx_shift_register <= {rx_shift_register[6:0], sdi};
                            done <= 1'b1;
                        end
                        else begin
                            rx_count <= rx_count + 1'b1;
                            rx_shift_register <= {rx_shift_register[6:0], sdi};
                        end
                    end
                end
            endcase
        end
    end

    // Clock generation
    always @(posedge clk) begin
        if (rst) begin
            clk_count <= 8'h00;
            SCLKSTATE <= SCK_IDLE;
            sck_previous <= 1'b1;
            sck_buffer <= 1'b1;
        end
        else begin
            case (SCLKSTATE)
                SCK_IDLE: begin
                    sck_previous <= 1'b1;
                    sck_buffer <= 1'b1;
                    clk_count <= 8'h00;
                    clk_edge_buffer <= 1'b0;
                    if (transmit)
                        SCLKSTATE <= SCK_RUNNING;
                end
                SCK_RUNNING: begin
                    if (done)
                        SCLKSTATE <= SCK_IDLE;
                    else if (clk_count == CLKDIVIDER) begin
                        if (!clk_edge_buffer) begin
                            sck_buffer <= 1'b1;
                            clk_edge_buffer <= 1'b1;
                        end
                        else begin
                            sck_buffer <= ~sck_buffer;
                            clk_count <= 8'h00;
                        end
                    end
                    else begin
                        sck_previous <= sck_buffer;
                        clk_count <= clk_count + 1'b1;
                    end
                end
            endcase
        end
    end

    assign rxbuffer = rx_shift_register;
    assign sclk = sck_buffer;
    assign done_out = done;

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Slave Select Control
//////////////////////////////////////////////////////////////////////////////////
module slaveSelect(
    input rst,
    input clk,
    input transmit,
    input done,
    output reg ss = 1'b1
    );

    always @(posedge clk) begin
        if (rst)
            ss <= 1'b1;
        else if (transmit)
            ss <= 1'b0;
        else if (done)
            ss <= 1'b1;
    end
endmodule