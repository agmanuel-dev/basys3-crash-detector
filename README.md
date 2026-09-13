# FPGA acceleration-triggered crash detector

A Basys-3 / Artix-7 coursework prototype with author-reported working accelerometer triggering, manual controls, OLED and LEDs. The original goal was to measure distance between objects and signal a potential collision. The distance sensor could not be made to work with the board, so the project continued with an accelerometer-only design. The published Verilog implements an ADXL345 SPI interface and a SAFE / WARNING / CRASH state machine with display and LED outputs.

**Focus:** Verilog integration, stateful control, peripheral interfaces and simulation.

## Project outcome

The original distance-based collision-warning goal was not completed. Accelerometer thresholds respond to motion/acceleration; they do not measure object separation or establish that a collision is approaching. This repository contains the accelerometer-based implementation, not a working distance-sensing system.

The following hardware results were reported by Alexander Gaspar Manuel from the original coursework build:

| Feature | Original hardware result |
|---|---|
| LEDs | Worked |
| OLED screen | Worked |
| Switches and manual crash triggers | Worked |
| Distance sensor | Did not work with the FPGA board; integration attempts were unsuccessful and work on that sensor stopped |
| Accelerometer-triggered automatic warning/crash detection | Moving or shaking the accelerometer automatically changed the warning/crash state on the physical board |

The distance-sensor model, specific troubleshooting steps and failure cause are not documented here. These reported hardware results refer to the original build, before the September 2026 source changes. The simulation results below are separate checks and do not establish end-to-end sensor operation.

## My contribution

I built the manual crash-detector controls and OLED display functionality with AI assistance, and personally connected the hardware to the FPGA board. I also attempted to integrate the distance sensor, but did not resolve the issue. This account describes my contribution; it does not claim that I independently authored every module in the repository.

## Implemented architecture

```mermaid
flowchart LR
  A[ADXL345] -->|SPI| B[Signed X/Y/Z]
  B --> C[Squared magnitude and thresholds]
  C --> D[Warning hold and crash latch]
  S[Manual override switches] --> D
  D --> E[OLED / seven-segment / LEDs]
```

## Behavior implemented in the source

- A scaled squared magnitude above 1,200 enters WARNING; above 1,800 enters CRASH.
- WARNING persists for a configured hold interval after detection stops. CRASH latches until reset or manual override.
- Switch 15 enables manual override; switches 1:0 select SAFE (`00`), WARNING (`10`) or CRASH (`01`).
- The automatic crash latch controls LED blinking. Selecting CRASH manually changes displays but intentionally clears that latch.

## Hardware and source

Target: Basys-3 (`xc7a35tcpg236-1`), 100 MHz input clock. The source expects an ADXL345 SPI connection on JA and an SPI OLED interface on JB. Verify your module pinout and power requirements against its documentation before connecting it.

| Connection | Signals |
|---|---|
| JA1–JA4 | chip select, MOSI, MISO, SCLK |
| JB1, JB2, JB4 | OLED chip select, MOSI, SCLK |
| JB7–JB10 | data/command, reset, VCC enable, PMOD enable |
| Center button | Reset |

`top.v` integrates the design. `adxl345_spi.v` contains the sensor interface modules; `oled_controller_full.v`, `spi_master_oled.v` and `display_ctrl.v` drive outputs. `Basys3.xdc` includes only ports used by this design.

## Reproduce the simulation

Run from this directory in a terminal with Vivado tools on PATH:

```text
xvlog top.v adxl345_spi.v ClkDiv_5Hz.v display_ctrl.v oled_controller_full.v spi_master_oled.v
xvlog --sv test_crash.v
xelab test_crash -s crash_test
xsim crash_test -runall
```

Create a fresh portable Vivado project with `vivado -mode batch -source create_project.tcl`. No cached checkpoint is required by the source simulation or project-creation script.

## Verification and corrections

Vivado Simulator 2025.1 passed the supplied test on September 12, 2026. It checks reset, manual override, automatic warning, warning hold, automatic crash detection, latching and recovery by injecting acceleration values at the sensor output boundary. Timing parameters are shortened for simulation; hardware defaults are preserved.

Portfolio preparation widened the warning timer from 27 to 32 bits, made timing configurable, corrected a scale comment, removed unused pin constraints and replaced the original testbench that timed out before later checks. See [PROVENANCE.md](PROVENANCE.md).

## Limits

This is an educational acceleration-threshold prototype, not a validated vehicle safety system. Thresholds are raw scaled counts, not calibrated crash criteria. The nominal sampling divider is about 5 Hz; debounce counts FPGA clocks rather than independent sensor samples. The simulation does not validate real SPI transactions, OLED pixels, sensor calibration, physical timing closure or current hardware operation. Board testing remains necessary after these changes.
