`timescale 1ns/1ps
module test_crash;
  reg clk=0, rst=1, miso=0;
  reg [15:0] sw=0;
  wire [15:0] led; wire [6:0] seg; wire dp;
  wire [3:0] an; wire [7:0] JB; wire sclk,mosi,cs_n;
  top #(.WARNING_HOLD_TIME(20),.BLINK_HALF_PERIOD(8)) dut(
    .clk(clk),.rst(rst),.miso(miso),.sw(sw),.led(led),.seg(seg),
    .dp(dp),.an(an),.JB(JB),.sclk(sclk),.mosi(mosi),.cs_n(cs_n));
  always #5 clk=~clk;
  task ticks(input integer n); begin repeat(n) @(negedge clk); end endtask
  task state_is(input [1:0] expected); begin
    if(dut.car_state !== expected) $fatal(1,"state=%b expected=%b",dut.car_state,expected);
  end endtask
  initial begin
    force dut.x_axis_raw=10'd0;
    force dut.y_axis_raw=10'd0;
    force dut.z_axis_raw=10'd0;
    ticks(3); rst=0; ticks(3); state_is(0);
    sw=16'h8002; ticks(2); state_is(2);
    sw=16'h8001; ticks(2); state_is(1);
    if(dut.crash_latched) $fatal(1,"manual override latched crash");
    sw=0; ticks(3); state_is(0);
    // (330^2 * 3) / 256 = 1276: warning, below crash threshold.
    force dut.x_axis_raw=10'd330;
    force dut.y_axis_raw=10'd330;
    force dut.z_axis_raw=10'd330;
    ticks(12); state_is(2);
    force dut.x_axis_raw=10'd0;
    force dut.y_axis_raw=10'd0;
    force dut.z_axis_raw=10'd0;
    ticks(5); state_is(2); ticks(30); state_is(0);
    // (400^2 * 3) / 256 = 1875: crash and latch.
    force dut.x_axis_raw=10'd400;
    force dut.y_axis_raw=10'd400;
    force dut.z_axis_raw=10'd400;
    ticks(12); state_is(1);
    if(!dut.crash_latched) $fatal(1,"automatic crash did not latch");
    force dut.x_axis_raw=10'd0;
    force dut.y_axis_raw=10'd0;
    force dut.z_axis_raw=10'd0;
    ticks(30); state_is(1);
    if(led !== 16'h0000 && led !== 16'hffff) $fatal(1,"invalid crash LED pattern");
    rst=1; ticks(3); rst=0; ticks(3); state_is(0);
    if(dut.crash_latched) $fatal(1,"reset failed to clear crash latch");
    $display("PASS: reset, manual override, automatic warning/hold, crash/latch and recovery");
    $finish;
  end
  initial begin #100000; $fatal(1,"test timeout"); end
endmodule
