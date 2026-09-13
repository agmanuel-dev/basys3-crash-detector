`timescale 1ns / 1ps

module oled_controller_full(
    input  wire clk,
    input  wire rst,
    input  wire [1:0] car_state,
    output wire ready,
    output wire cs,
    output wire mosi,
    output wire sclk,
    output reg  dc,
    output reg  res,
    output reg  vccen,
    output reg  pmoden
);

    // Coursework color constants; display-dependent appearance needs board verification.
    localparam [15:0] COLOR_GREEN = 16'h07E0;   // Intended SAFE background
    localparam [15:0] COLOR_RED   = 16'h000F;   // Intended CRASH background  
    localparam [15:0] COLOR_YELLOW = 16'h0EFF;  // Intended WARNING background

    localparam [4:0]
        S_IDLE          = 5'd0,
        S_POWER_UP      = 5'd1,
        S_RESET_LOW     = 5'd2,
        S_RESET_HIGH    = 5'd3,
        S_SEND_INIT     = 5'd4,
        S_WAIT_INIT     = 5'd5,
        S_POWER_VCC     = 5'd6,
        S_DISPLAY_ON    = 5'd7,
        S_WAIT_DISP_ON  = 5'd8,
        S_FILL_SCREEN   = 5'd9,
        S_WAIT_FILL     = 5'd10,
        S_DRAW_FACE     = 5'd11,
        S_WAIT_FACE     = 5'd12,
        S_READY         = 5'd13,
        S_DELAY         = 5'd14;

    reg [4:0] state, next_state;
    reg [24:0] delay_counter;
    reg [5:0] init_index;
    reg [1:0] current_state;
    reg [1:0] previous_state;

    localparam [24:0] DELAY_1MS   = 25'd100_000;
    localparam [24:0] DELAY_5MS   = 25'd500_000;
    localparam [24:0] DELAY_100MS = 25'd10_000_000;

    reg spi_start;
    reg [7:0] spi_data_out;
    wire spi_done;
    wire spi_busy;

    spi_master #(.CLK_DIV(8)) spi_inst (
        .clk(clk),
        .rst(rst),
        .start(spi_start),
        .data_in(spi_data_out),
        .done(spi_done),
        .busy(spi_busy),
        .cs(cs),
        .mosi(mosi),
        .sclk(sclk)
    );

    localparam [5:0] INIT_LENGTH = 6'd32;

    function [7:0] get_init_byte;
        input [5:0] index;
        begin
            case (index)
                6'd0:  get_init_byte = 8'hFD;
                6'd1:  get_init_byte = 8'h12;
                6'd2:  get_init_byte = 8'hAE;
                6'd3:  get_init_byte = 8'hA0;
                6'd4:  get_init_byte = 8'h72;
                6'd5:  get_init_byte = 8'hA1;
                6'd6:  get_init_byte = 8'h00;
                6'd7:  get_init_byte = 8'hA2;
                6'd8:  get_init_byte = 8'h00;
                6'd9:  get_init_byte = 8'hA4;
                6'd10: get_init_byte = 8'hA8;
                6'd11: get_init_byte = 8'h3F;
                6'd12: get_init_byte = 8'hAD;
                6'd13: get_init_byte = 8'h8E;
                6'd14: get_init_byte = 8'hB0;
                6'd15: get_init_byte = 8'h0B;
                6'd16: get_init_byte = 8'hB1;
                6'd17: get_init_byte = 8'h31;
                6'd18: get_init_byte = 8'hB3;
                6'd19: get_init_byte = 8'hF0;
                6'd20: get_init_byte = 8'h8A;
                6'd21: get_init_byte = 8'h64;
                6'd22: get_init_byte = 8'h8B;
                6'd23: get_init_byte = 8'h78;
                6'd24: get_init_byte = 8'h8C;
                6'd25: get_init_byte = 8'h64;
                6'd26: get_init_byte = 8'hBB;
                6'd27: get_init_byte = 8'h3A;
                6'd28: get_init_byte = 8'hBE;
                6'd29: get_init_byte = 8'h3E;
                6'd30: get_init_byte = 8'h87;
                6'd31: get_init_byte = 8'h06;
                default: get_init_byte = 8'h00;
            endcase
        end
    endfunction

    reg fill_active;
    reg [15:0] fill_color;
    reg [3:0] fill_cmd_index;
    wire fill_done;

    localparam [3:0] FILL_CMD_LENGTH = 4'd13;

    wire [5:0] fill_r = {fill_color[15:11], 1'b0};
    wire [5:0] fill_g = fill_color[10:5];
    wire [5:0] fill_b = {fill_color[4:0], 1'b0};

    function [7:0] get_fill_byte;
        input [3:0] index;
        input [5:0] r, g, b;
        begin
            case (index)
                4'd0:  get_fill_byte = 8'h26;
                4'd1:  get_fill_byte = 8'h01;
                4'd2:  get_fill_byte = 8'h22;
                4'd3:  get_fill_byte = 8'h00;
                4'd4:  get_fill_byte = 8'h00;
                4'd5:  get_fill_byte = 8'h5F;
                4'd6:  get_fill_byte = 8'h3F;
                4'd7:  get_fill_byte = {2'b00, b};
                4'd8:  get_fill_byte = {2'b00, g};
                4'd9:  get_fill_byte = {2'b00, r};
                4'd10: get_fill_byte = {2'b00, b};
                4'd11: get_fill_byte = {2'b00, g};
                4'd12: get_fill_byte = {2'b00, r};
                default: get_fill_byte = 8'h00;
            endcase
        end
    endfunction

    assign fill_done = (fill_cmd_index == FILL_CMD_LENGTH) && spi_done;

    reg face_active;
    reg [5:0] face_byte_index;
    wire face_done;

    localparam [5:0] FACE_BYTE_LENGTH = 6'd32;

    function [7:0] get_face_byte;
        input [5:0] index;
        input [1:0] face_type;
        begin
            case (index)
                6'd0:  get_face_byte = 8'h21;
                6'd1:  get_face_byte = 8'd30;
                6'd2:  get_face_byte = 8'd18;
                6'd3:  get_face_byte = 8'd30;
                6'd4:  get_face_byte = 8'd22;
                6'd5:  get_face_byte = 8'h00;
                6'd6:  get_face_byte = 8'h00;
                6'd7:  get_face_byte = 8'h00;

                6'd8:  get_face_byte = 8'h21;
                6'd9:  get_face_byte = 8'd65;
                6'd10: get_face_byte = 8'd18;
                6'd11: get_face_byte = 8'd65;
                6'd12: get_face_byte = 8'd22;
                6'd13: get_face_byte = 8'h00;
                6'd14: get_face_byte = 8'h00;
                6'd15: get_face_byte = 8'h00;

                6'd16: get_face_byte = 8'h21;
                6'd17: get_face_byte = 8'd30;
                6'd18: get_face_byte = (face_type == 2'b00) ? 8'd52 : ((face_type == 2'b01) ? 8'd42 : 8'd47);
                6'd19: get_face_byte = (face_type == 2'b10) ? 8'd65 : 8'd48;
                6'd20: get_face_byte = (face_type == 2'b00) ? 8'd42 : ((face_type == 2'b01) ? 8'd52 : 8'd47);
                6'd21: get_face_byte = 8'h00;
                6'd22: get_face_byte = 8'h00;
                6'd23: get_face_byte = 8'h00;

                6'd24: get_face_byte = 8'h21;
                6'd25: get_face_byte = (face_type == 2'b10) ? 8'd48 : 8'd48;
                6'd26: get_face_byte = (face_type == 2'b00) ? 8'd42 : ((face_type == 2'b01) ? 8'd52 : 8'd47);
                6'd27: get_face_byte = 8'd65;
                6'd28: get_face_byte = (face_type == 2'b00) ? 8'd52 : ((face_type == 2'b01) ? 8'd42 : 8'd47);
                6'd29: get_face_byte = 8'h00;
                6'd30: get_face_byte = 8'h00;
                6'd31: get_face_byte = 8'h00;

                default: get_face_byte = 8'h00;
            endcase
        end
    endfunction

    assign face_done = (face_byte_index == FACE_BYTE_LENGTH) && spi_done;

    reg [15:0] background_color;
    reg [1:0] face_type;

    always @(*) begin
        case (car_state[1:0])
            2'b00: begin
                background_color = COLOR_GREEN;
                face_type = 2'b01;  // Coursework SAFE face selection
            end
            2'b01: begin
                background_color = COLOR_RED;
                face_type = 2'b00;  // Coursework CRASH face selection
            end
            default: begin
                background_color = COLOR_YELLOW;
                face_type = 2'b10;  // NEUTRAL for warning
            end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            delay_counter <= 0;
            init_index <= 0;
            pmoden <= 0;
            vccen <= 0;
            res <= 1;
            dc <= 0;
            spi_start <= 0;
            spi_data_out <= 0;
            fill_active <= 0;
            fill_cmd_index <= 0;
            fill_color <= 0;
            face_active <= 0;
            face_byte_index <= 0;
            next_state <= S_IDLE;
            current_state <= 2'b00;
            previous_state <= 2'b00;
        end else begin
            spi_start <= 0;
            current_state <= car_state;

            case (state)
                S_IDLE: begin
                    pmoden <= 0;
                    vccen <= 0;
                    res <= 1;
                    delay_counter <= DELAY_1MS;
                    state <= S_POWER_UP;
                end

                S_POWER_UP: begin
                    pmoden <= 1;
                    if (delay_counter == 0) begin
                        delay_counter <= DELAY_1MS;
                        state <= S_RESET_LOW;
                    end else begin
                        delay_counter <= delay_counter - 1;
                    end
                end

                S_RESET_LOW: begin
                    res <= 0;
                    if (delay_counter == 0) begin
                        res <= 1;
                        delay_counter <= DELAY_1MS;
                        state <= S_RESET_HIGH;
                    end else begin
                        delay_counter <= delay_counter - 1;
                    end
                end

                S_RESET_HIGH: begin
                    if (delay_counter == 0) begin
                        init_index <= 0;
                        state <= S_SEND_INIT;
                    end else begin
                        delay_counter <= delay_counter - 1;
                    end
                end

                S_SEND_INIT: begin
                    if (init_index < INIT_LENGTH) begin
                        if (!spi_busy) begin
                            dc <= 0;
                            spi_data_out <= get_init_byte(init_index);
                            spi_start <= 1;
                            state <= S_WAIT_INIT;
                        end
                    end else begin
                        delay_counter <= DELAY_100MS;
                        state <= S_POWER_VCC;
                    end
                end

                S_WAIT_INIT: begin
                    if (spi_done) begin
                        init_index <= init_index + 1;
                        state <= S_SEND_INIT;
                    end
                end

                S_POWER_VCC: begin
                    vccen <= 1;
                    if (delay_counter == 0) begin
                        state <= S_DISPLAY_ON;
                    end else begin
                        delay_counter <= delay_counter - 1;
                    end
                end

                S_DISPLAY_ON: begin
                    if (!spi_busy) begin
                        dc <= 0;
                        spi_data_out <= 8'hAF;
                        spi_start <= 1;
                        state <= S_WAIT_DISP_ON;
                    end
                end

                S_WAIT_DISP_ON: begin
                    if (spi_done) begin
                        fill_active <= 1;
                        fill_color <= background_color;
                        fill_cmd_index <= 0;
                        state <= S_FILL_SCREEN;
                    end
                end

                S_FILL_SCREEN: begin
                    if (fill_cmd_index < FILL_CMD_LENGTH) begin
                        if (!spi_busy) begin
                            dc <= 0;
                            spi_data_out <= get_fill_byte(fill_cmd_index, fill_r, fill_g, fill_b);
                            spi_start <= 1;
                            fill_cmd_index <= fill_cmd_index + 1;
                            state <= S_WAIT_FILL;
                        end
                    end else begin
                        fill_active <= 0;
                        delay_counter <= DELAY_5MS;
                        next_state <= S_DRAW_FACE;
                        state <= S_DELAY;
                    end
                end

                S_WAIT_FILL: begin
                    if (spi_done) begin
                        state <= S_FILL_SCREEN;
                    end
                end

                S_DRAW_FACE: begin
                    face_active <= 1;
                    if (face_byte_index < FACE_BYTE_LENGTH) begin
                        if (!spi_busy) begin
                            dc <= 0;
                            spi_data_out <= get_face_byte(face_byte_index, face_type);
                            spi_start <= 1;
                            face_byte_index <= face_byte_index + 1;
                            state <= S_WAIT_FACE;
                        end
                    end else begin
                        face_active <= 0;
                        face_byte_index <= 0;
                        previous_state <= current_state;
                        state <= S_READY;
                    end
                end

                S_WAIT_FACE: begin
                    if (spi_done) begin
                        state <= S_DRAW_FACE;
                    end
                end

                S_READY: begin
                    if (current_state != previous_state) begin
                        fill_active <= 1;
                        fill_color <= background_color;
                        fill_cmd_index <= 0;
                        state <= S_FILL_SCREEN;
                    end
                end

                S_DELAY: begin
                    if (delay_counter == 0) begin
                        state <= next_state;
                    end else begin
                        delay_counter <= delay_counter - 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign ready = (state == S_READY);

endmodule
