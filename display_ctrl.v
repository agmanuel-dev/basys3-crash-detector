`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/21/2025 09:41:48 AM
// Design Name: 
// Module Name: display_ctrl
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


module display_ctrl(
    input clk,
    input rst,
    input [1:0] car_state,    // MODIFIED: 2'b00=SAFE, 2'b10=WARNING, 2'b01=CRASH
    input [15:0] x_axis,      // Distance data (unused in new design)
    input [9:0] y_axis,       // Unused
    input [9:0] z_axis,       // Unused
    output reg [6:0] seg,
    output reg dp,
    output reg [3:0] an
    );

    // State definitions
    localparam [1:0] STATE_SAFE    = 2'b00;
    localparam [1:0] STATE_CRASH   = 2'b01;
    localparam [1:0] STATE_WARNING = 2'b10;

    //////////////////////////////////////////////////////////////////////////
    // Scrolling Logic for WARNING and CRASH modes
    //////////////////////////////////////////////////////////////////////////
    reg [27:0] scroll_counter;
    reg [3:0] scroll_position;

    // Calculate max scroll position based on state
    wire [3:0] max_scroll_pos = (car_state == STATE_WARNING) ? 4'd11 : 4'd11;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scroll_counter <= 0;
            scroll_position <= 0;
        end
        else if (car_state == STATE_WARNING || car_state == STATE_CRASH) begin
            if (scroll_counter >= 28'd30_000_000) begin  // ~0.3 seconds at 100MHz
                scroll_counter <= 0;
                if (scroll_position >= max_scroll_pos)
                    scroll_position <= 0;
                else
                    scroll_position <= scroll_position + 1;
            end
            else begin
                scroll_counter <= scroll_counter + 1;
            end
        end
        else begin
            scroll_counter <= 0;
            scroll_position <= 0;
        end
    end

    // Get character for CRASH message "CALL 911   "
    function [7:0] get_crash_char;
        input [3:0] position;
        begin
            case (position)
                4'd0:  get_crash_char = "C";
                4'd1:  get_crash_char = "A";
                4'd2:  get_crash_char = "L";
                4'd3:  get_crash_char = "L";
                4'd4:  get_crash_char = " ";
                4'd5:  get_crash_char = "9";
                4'd6:  get_crash_char = "1";
                4'd7:  get_crash_char = "1";
                4'd8:  get_crash_char = " ";
                4'd9:  get_crash_char = " ";
                4'd10: get_crash_char = " ";
                4'd11: get_crash_char = " ";
                default: get_crash_char = " ";
            endcase
        end
    endfunction

    // Get character for WARNING message "VvARNING   " (W split as Vv)
    function [7:0] get_warning_char;
        input [3:0] position;
        begin
            case (position)
                4'd0:  get_warning_char = "V";  // Left half of W
                4'd1:  get_warning_char = "v";  // Right half of W
                4'd2:  get_warning_char = "A";
                4'd3:  get_warning_char = "R";
                4'd4:  get_warning_char = "N";
                4'd5:  get_warning_char = "I";
                4'd6:  get_warning_char = "N";
                4'd7:  get_warning_char = "G";
                4'd8:  get_warning_char = " ";
                4'd9:  get_warning_char = " ";
                4'd10: get_warning_char = " ";
                4'd11: get_warning_char = " ";
                default: get_warning_char = " ";
            endcase
        end
    endfunction

    // Get character for SAFE message "SAFE" (static, no scroll)
    function [7:0] get_safe_char;
        input [1:0] position;
        begin
            case (position)
                2'd0: get_safe_char = "S";
                2'd1: get_safe_char = "A";
                2'd2: get_safe_char = "F";
                2'd3: get_safe_char = "E";
                default: get_safe_char = " ";
            endcase
        end
    endfunction

    //////////////////////////////////////////////////////////////////////////
    // 7-segment letter decoder
    //////////////////////////////////////////////////////////////////////////
    function [6:0] letter_decode;
        input [7:0] letter;
        begin
            case(letter)
                "A": letter_decode = 7'b0001000;  // A
                "C": letter_decode = 7'b1000110;  // C
                "E": letter_decode = 7'b0000110;  // E
                "F": letter_decode = 7'b0001110;  // F
                "G": letter_decode = 7'b1000010;  // G
                "I": letter_decode = 7'b1111001;  // I (same as 1)
                "L": letter_decode = 7'b1000111;  // L
                "N": letter_decode = 7'b1001000;  // n (lowercase, better fit)
                "R": letter_decode = 7'b1001110;  // r (lowercase)
                "S": letter_decode = 7'b0010010;  // S (same as 5)
                "V": letter_decode = 7'b1000011;  // V - left half of W (segments: f,e,d,c,b)
                "v": letter_decode = 7'b1100001;  // v - right half of W (segments: e,d,c,b)
                "9": letter_decode = 7'b0010000;  // 9
                "1": letter_decode = 7'b1111001;  // 1
                " ": letter_decode = 7'b1111111;  // Blank
                default: letter_decode = 7'b1111111;
            endcase
        end
    endfunction

    //////////////////////////////////////////////////////////////////////////
    // Refresh counter for multiplexing
    //////////////////////////////////////////////////////////////////////////
    reg [1:0] digit_sel = 2'b0;
    reg [18:0] refresh_cnt = 19'b0;

    always @(posedge clk) begin
        if (rst) begin
            refresh_cnt <= 19'b0;
            digit_sel <= 2'b0;
        end else begin
            refresh_cnt <= refresh_cnt + 1;
            if (refresh_cnt == 19'd99999) begin  // ~1ms at 100MHz
                refresh_cnt <= 19'b0;
                digit_sel <= digit_sel + 1;
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // Multiplex display based on car_state
    //////////////////////////////////////////////////////////////////////////
    always @(*) begin
        case (car_state)
            STATE_CRASH: begin
                // CRASH MODE: Scrolling "CALL 911"
                case(digit_sel)
                    2'b00: begin  // Rightmost digit
                        an = 4'b1110;
                        seg = letter_decode(get_crash_char(scroll_position + 4'd3));
                        dp = 1'b1;
                    end
                    2'b01: begin
                        an = 4'b1101;
                        seg = letter_decode(get_crash_char(scroll_position + 4'd2));
                        dp = 1'b1;
                    end
                    2'b10: begin
                        an = 4'b1011;
                        seg = letter_decode(get_crash_char(scroll_position + 4'd1));
                        dp = 1'b1;
                    end
                    2'b11: begin  // Leftmost digit
                        an = 4'b0111;
                        seg = letter_decode(get_crash_char(scroll_position));
                        dp = 1'b1;
                    end
                endcase
            end

            STATE_WARNING: begin
                // WARNING MODE: Scrolling "WARNING"
                case(digit_sel)
                    2'b00: begin  // Rightmost digit
                        an = 4'b1110;
                        seg = letter_decode(get_warning_char(scroll_position + 4'd3));
                        dp = 1'b1;
                    end
                    2'b01: begin
                        an = 4'b1101;
                        seg = letter_decode(get_warning_char(scroll_position + 4'd2));
                        dp = 1'b1;
                    end
                    2'b10: begin
                        an = 4'b1011;
                        seg = letter_decode(get_warning_char(scroll_position + 4'd1));
                        dp = 1'b1;
                    end
                    2'b11: begin  // Leftmost digit
                        an = 4'b0111;
                        seg = letter_decode(get_warning_char(scroll_position));
                        dp = 1'b1;
                    end
                endcase
            end

            STATE_SAFE: begin
                // SAFE MODE: Static "SAFE" display
                case(digit_sel)
                    2'b00: begin  // Rightmost digit - "E"
                        an = 4'b1110;
                        seg = letter_decode(get_safe_char(2'd3));
                        dp = 1'b1;
                    end
                    2'b01: begin  // "F"
                        an = 4'b1101;
                        seg = letter_decode(get_safe_char(2'd2));
                        dp = 1'b1;
                    end
                    2'b10: begin  // "A"
                        an = 4'b1011;
                        seg = letter_decode(get_safe_char(2'd1));
                        dp = 1'b1;
                    end
                    2'b11: begin  // Leftmost digit - "S"
                        an = 4'b0111;
                        seg = letter_decode(get_safe_char(2'd0));
                        dp = 1'b1;
                    end
                endcase
            end

            default: begin
                // Default to blank display
                an = 4'b1111;
                seg = 7'b1111111;
                dp = 1'b1;
            end
        endcase
    end

endmodule