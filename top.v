`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ADXL345 Interface with OLED Display - Complete System
// Automatic crash detection based on accelerometer thresholds
//////////////////////////////////////////////////////////////////////////////////

module top #(
    parameter integer WARNING_HOLD_TIME = 150_000_000,
    parameter integer BLINK_HALF_PERIOD = 25_000_000
) (
    input clk,              // 100MHz clock
    input rst,              // reset button
    // SPI ports for ADXL345
    output sclk,
    output mosi,
    input miso,
    output cs_n,
    output [15:0] led,      // LEDs show status and raw data
    output [6:0] seg,
    output dp,
    output [3:0] an,
    // PMOD JB for OLED display
    output [7:0] JB,
    // Switches
    input [15:0] sw         // SW[15] = manual override enable
    );

    //////////////////////////////////////////////////////////////////////////
    // Signal Declarations
    //////////////////////////////////////////////////////////////////////////

    // Accelerometer outputs (10-bit signed, 2's complement)
    wire [9:0] x_axis_raw;
    wire [9:0] y_axis_raw;
    wire [9:0] z_axis_raw;

    // 5Hz sample tick
    wire clk_5hz;

    // Car state: 2'b00 = SAFE (green smile), 2'b01 = CRASH (red frown), 2'b10 = WARNING (yellow neutral)
    reg [1:0] car_state;

    // OLED signals
    wire oled_cs;
    wire oled_mosi;
    wire oled_sclk;
    wire oled_dc;
    wire oled_res;
    wire oled_vccen;
    wire oled_pmoden;
    wire oled_ready;

    //////////////////////////////////////////////////////////////////////////
    // Crash Detection Logic - MAGNITUDE BASED
    // Works in any orientation by calculating total acceleration
    //////////////////////////////////////////////////////////////////////////

    // Convert 10-bit 2's complement to signed
    wire signed [9:0] x_signed = x_axis_raw;
    wire signed [9:0] y_signed = y_axis_raw;
    wire signed [9:0] z_signed = z_axis_raw;

    // Square each signed axis; sum and scale the squared magnitude.
    wire [19:0] x_sq = x_signed * x_signed;
    wire [19:0] y_sq = y_signed * y_signed;
    wire [19:0] z_sq = z_signed * z_signed;

    // Sum of squares (total acceleration magnitude squared)
    wire [21:0] accel_mag_sq = x_sq + y_sq + z_sq;

    // Scale down to reasonable range for comparison (divide by 256)
    wire [11:0] accel_mag_scaled = accel_mag_sq[19:8];

    // Based on your measurements:
    // At rest: ~1000
    // Moderate shake: ~2000
    // Hard shake: ~3000+
    parameter [11:0] CRASH_MAG  = 12'd1800;   // Hard shake/impact
    parameter [11:0] WARNING_MAG = 12'd1200;  // Moderate shake

    // Detection based on total acceleration magnitude
    wire crash_detected = (accel_mag_scaled > CRASH_MAG);
    wire warning_detected = (accel_mag_scaled > WARNING_MAG) && !crash_detected;

    // Add debouncing - require multiple consecutive detections
    reg [3:0] crash_debounce;
    reg [3:0] warning_debounce;

    always @(posedge clk) begin
        if (rst) begin
            crash_debounce <= 4'b0;
            warning_debounce <= 4'b0;
        end else begin
            // Count up if detected, reset to 0 if not
            if (crash_detected && crash_debounce < 4'hF)
                crash_debounce <= crash_debounce + 1'b1;
            else if (!crash_detected)
                crash_debounce <= 4'b0;

            if (warning_detected && warning_debounce < 4'hF)
                warning_debounce <= warning_debounce + 1'b1;
            else if (!warning_detected)
                warning_debounce <= 4'b0;
        end
    end

    // Only trigger after multiple consecutive detections (debounced)
    wire crash_confirmed = (crash_debounce >= 4'd5);     // ~5 clocks in a row
    wire warning_confirmed = (warning_debounce >= 4'd5); // ~5 clocks in a row

    // State machine with hysteresis to prevent flickering
    // State machine with crash latch - once crash detected, stays in crash state
    reg crash_latched;
    reg [31:0] state_counter;

    localparam [1:0] STATE_SAFE    = 2'b00;
    localparam [1:0] STATE_CRASH   = 2'b01;
    localparam [1:0] STATE_WARNING = 2'b10;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            car_state <= STATE_SAFE;
            state_counter <= 32'd0;
            crash_latched <= 1'b0;  // Clear crash latch on reset
        end
        else if (sw[15]) begin
            // Manual override mode - use switches directly
            car_state <= sw[1:0];
            state_counter <= 32'd0;
            crash_latched <= 1'b0;  // Clear latch in manual mode
        end
        else begin
            // Automatic crash detection mode
            if (crash_confirmed) begin
                // CRASH: Latch and stay in crash state forever
                car_state <= STATE_CRASH;
                crash_latched <= 1'b1;
                state_counter <= 32'd0;
            end
            else if (crash_latched) begin
                // Once crashed, STAY in crash state
                car_state <= STATE_CRASH;
            end
            else if (warning_confirmed) begin
                // WARNING: Immediate transition, hold for 1.5 seconds
                if (car_state == STATE_SAFE || state_counter == 0) begin
                    car_state <= STATE_WARNING;
                    state_counter <= WARNING_HOLD_TIME;
                end
            end
            else begin
                // No danger detected - count down hold timer
                if (state_counter > 0) begin
                    state_counter <= state_counter - 1'b1;
                    // Keep current state until timer expires
                end
                else begin
                    // Timer expired, return to safe
                    car_state <= STATE_SAFE;
                end
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // 5Hz Clock Divider for Accelerometer Sampling
    //////////////////////////////////////////////////////////////////////////
    ClkDiv_5Hz sample_clk(
        .CLK(clk),
        .RST(rst),
        .CLKOUT(clk_5hz)
    );

    //////////////////////////////////////////////////////////////////////////
    // SPI Interface to ADXL345 Accelerometer
    //////////////////////////////////////////////////////////////////////////
    SPIcomponent spi(
        .CLK(clk),
        .RST(rst),
        .START(clk_5hz),
        .SDI(miso),
        .SDO(mosi),
        .SCLK(sclk),
        .SS(cs_n),
        .xAxis(x_axis_raw),
        .yAxis(y_axis_raw),
        .zAxis(z_axis_raw)
    );

    //////////////////////////////////////////////////////////////////////////
    // 7-Segment Display - Shows acceleration magnitude for debugging
    //////////////////////////////////////////////////////////////////////////
    // Show the scaled magnitude value (same scale as thresholds)
    wire [15:0] display_value = {4'b0, accel_mag_scaled};

    display_ctrl disp (
        .clk(clk),
        .rst(rst),
        .car_state(car_state),      // MODIFIED: Pass the full car state
        .x_axis(display_value),     // No longer used
        .y_axis(y_axis_raw),        // No longer used
        .z_axis(z_axis_raw),        // No longer used
        .seg(seg),
        .dp(dp),
        .an(an)
    );

    //////////////////////////////////////////////////////////////////////////
    // OLED Controller for Car State Display
    //////////////////////////////////////////////////////////////////////////
    oled_controller_full u_oled (
        .clk       (clk),
        .rst       (rst),
        .car_state (car_state),
        .ready     (oled_ready),
        .cs        (oled_cs),
        .mosi      (oled_mosi),
        .sclk      (oled_sclk),
        .dc        (oled_dc),
        .res       (oled_res),
        .vccen     (oled_vccen),
        .pmoden    (oled_pmoden)
    );

    //////////////////////////////////////////////////////////////////////////
    // LED Display - Progressive indicator of acceleration magnitude
    //////////////////////////////////////////////////////////////////////////
    // LEDs progressively turn on as acceleration increases
    // LED 0-14: Progressive fill based on proximity to crash threshold
    // LED 15 ON + Blinking: CRASH state (latched)

    // Blink clock divider - creates ~2Hz blink rate for crash state
    reg [25:0] blink_counter;
    reg blink_state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            blink_counter <= 26'd0;
            blink_state <= 1'b0;
        end
        else begin
            if (blink_counter >= BLINK_HALF_PERIOD - 1) begin  // Toggle every 0.25 seconds
                blink_counter <= 26'd0;
                blink_state <= ~blink_state;
            end
            else begin
                blink_counter <= blink_counter + 1'b1;
            end
        end
    end

    reg [15:0] led_pattern;

    // Calculate how many LEDs should be on based on acceleration magnitude
    // Map accel_mag_scaled (0-4095) to LED count (0-15)
    // Safe range: 0-1200 (WARNING_MAG) -> 0-7 LEDs
    // Warning range: 1200-1800 (CRASH_MAG) -> 8-14 LEDs  
    // Crash: 1800+ -> 15 LEDs + blink

    wire [4:0] led_count;  // 0 to 15

    // Scale the magnitude to LED count
    // Use WARNING_MAG as starting point, CRASH_MAG as endpoint
    assign led_count = (accel_mag_scaled < WARNING_MAG) ? 
                       // Below warning: scale 0 to 7 LEDs
                       (accel_mag_scaled[11:7]) :  // Divide by 128, gives 0-9 range for 0-1200
                       (accel_mag_scaled < CRASH_MAG) ?
                       // Warning to crash: scale 8 to 14 LEDs
                       (5'd8 + ((accel_mag_scaled - WARNING_MAG) * 7) / (CRASH_MAG - WARNING_MAG)) :
                       // At or above crash: 15 LEDs
                       5'd15;

    // Generate LED pattern
    integer i;
    always @(*) begin
        if (crash_latched) begin
            // CRASH STATE: All LEDs blink together
            if (blink_state)
                led_pattern = 16'b1111_1111_1111_1111;  // All ON
            else
                led_pattern = 16'b0000_0000_0000_0000;  // All OFF
        end
        else begin
            // NORMAL STATE: Progressive LED bar
            led_pattern = 16'b0000_0000_0000_0000;
            for (i = 0; i < 16; i = i + 1) begin
                if (i < led_count)
                    led_pattern[i] = 1'b1;
            end
        end
    end

    assign led = led_pattern;

    //////////////////////////////////////////////////////////////////////////
    // Map OLED Signals to Pmod JB Pins
    //////////////////////////////////////////////////////////////////////////
    assign JB[0] = oled_cs;      // JB1: Chip Select
    assign JB[1] = oled_mosi;    // JB2: MOSI (Data)
    assign JB[2] = 1'b0;         // JB3: Not Connected
    assign JB[3] = oled_sclk;    // JB4: SPI Clock
    assign JB[4] = oled_dc;      // JB7: Data/Command
    assign JB[5] = oled_res;     // JB8: Reset
    assign JB[6] = oled_vccen;   // JB9: VCC Enable
    assign JB[7] = oled_pmoden;  // JB10: PMOD Enable

endmodule