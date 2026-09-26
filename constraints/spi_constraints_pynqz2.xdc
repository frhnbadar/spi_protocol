## spi_top.xdc
## Constraints for spi_top (clk_div + spi_master) on the PYNQ-Z2 board
## Target part: xc7z020clg400-1
##
## Pin mapping used here:
##   clk      -> onboard 125 MHz oscillator
##   rst_n    -> SW0   (flip down = reset held, up = run)
##   start    -> BTN0  (press to trigger one 8-bit transfer)
##   data_in  -> Pmod JA[7:0] (drive with jumpers/DIP switches from an
##               external source -- there aren't enough onboard switches
##               for a full byte)
##   sclk     -> Pmod JB[0]  \
##   mosi     -> Pmod JB[1]   } real SPI bus out to a slave device,
##   cs_n     -> Pmod JB[2]  /  logic analyzer, or oscilloscope probes
##   busy     -> LED0
##   done     -> LED1

## ---------------------------------------------------------------
## Clock (125 MHz onboard oscillator)
## ---------------------------------------------------------------
set_property -dict { PACKAGE_PIN H16  IOSTANDARD LVCMOS33 } [get_ports { clk }]; #Sch=sysclk
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

## ---------------------------------------------------------------
## Reset and start control
## ---------------------------------------------------------------
set_property -dict { PACKAGE_PIN M20  IOSTANDARD LVCMOS33 } [get_ports { rst_n }]; #Sch=sw[0]
set_property -dict { PACKAGE_PIN D19  IOSTANDARD LVCMOS33 } [get_ports { start }]; #Sch=btn[0]

## ---------------------------------------------------------------
## data_in[7:0] -> Pmod JA (all 8 data pins)
## ---------------------------------------------------------------
set_property -dict { PACKAGE_PIN Y18  IOSTANDARD LVCMOS33 } [get_ports { data_in[0] }]; #Sch=ja_p[1]
set_property -dict { PACKAGE_PIN Y19  IOSTANDARD LVCMOS33 } [get_ports { data_in[1] }]; #Sch=ja_n[1]
set_property -dict { PACKAGE_PIN Y16  IOSTANDARD LVCMOS33 } [get_ports { data_in[2] }]; #Sch=ja_p[2]
set_property -dict { PACKAGE_PIN Y17  IOSTANDARD LVCMOS33 } [get_ports { data_in[3] }]; #Sch=ja_n[2]
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports { data_in[4] }]; #Sch=ja_p[3]
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports { data_in[5] }]; #Sch=ja_n[3]
set_property -dict { PACKAGE_PIN W18  IOSTANDARD LVCMOS33 } [get_ports { data_in[6] }]; #Sch=ja_p[4]
set_property -dict { PACKAGE_PIN W19  IOSTANDARD LVCMOS33 } [get_ports { data_in[7] }]; #Sch=ja_n[4]

## ---------------------------------------------------------------
## SPI bus out -> Pmod JB (connect a slave / scope / logic analyzer here)
## ---------------------------------------------------------------
set_property -dict { PACKAGE_PIN W14  IOSTANDARD LVCMOS33 } [get_ports { sclk }]; #Sch=jb_p[1]
set_property -dict { PACKAGE_PIN Y14  IOSTANDARD LVCMOS33 } [get_ports { mosi }]; #Sch=jb_n[1]
set_property -dict { PACKAGE_PIN T11  IOSTANDARD LVCMOS33 } [get_ports { cs_n }]; #Sch=jb_p[2]

## ---------------------------------------------------------------
## Status LEDs
## ---------------------------------------------------------------
set_property -dict { PACKAGE_PIN R14  IOSTANDARD LVCMOS33 } [get_ports { busy }]; #Sch=led[0]
set_property -dict { PACKAGE_PIN P14  IOSTANDARD LVCMOS33 } [get_ports { done }]; #Sch=led[1]

## ---------------------------------------------------------------
## Required for a standalone PL-only bitstream on this 7-series part
## ---------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
