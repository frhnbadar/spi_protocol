// Simple SPI master (mode 0, single slave, 8-bit transfers).
// Plain Verilog-2001. Assumes a clean clk_div_tick input that
// controls SCLK edges and bit timing.
//
// Mode 0 (CPOL=0, CPHA=0):
//   - SCLK idles low.
//   - Data is captured on the rising edge of SCLK.
//   - Data is changed on the falling edge of SCLK.

`timescale 1ns/1ps

module spi_master (
    input  wire       clk,
    input  wire       rst_n,       // Active-low async reset
    input  wire       clk_div_tick,// Divider pulse controlling SCLK toggling
    input  wire       start,       // Pulse high for one cycle to start transfer
    input  wire [7:0] data_in,     // Byte to send (MSB first on MOSI)
    output reg        sclk,        // SPI serial clock
    output reg        mosi,        // Master Out, Slave In
    output reg        cs_n,        // Active-low chip select
    output reg        busy,        // High while transfer in progress
    output reg        done         // One-cycle pulse at end of transfer
);
    // State encoding (plain Verilog: no typedef enum)
    localparam [1:0] IDLE        = 2'd0,
                      ASSERT_CS   = 2'd1,
                      TRANSFER    = 2'd2,
                      DEASSERT_CS = 2'd3;

    reg [1:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_idx;    // counts bits 7..0 (MSB first)
    reg       phase;      // 0: SCLK low, 1: SCLK high (simple phase tracking)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            shift_reg <= 8'h00;
            bit_idx   <= 3'd7;
            sclk      <= 1'b0;
            mosi      <= 1'b0;
            cs_n      <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
            phase     <= 1'b0;
        end else begin
            // Default: done deasserted except when finishing transfer.
            done <= 1'b0;

            case (state)
                IDLE: begin
                    cs_n  <= 1'b1;
                    sclk  <= 1'b0;
                    phase <= 1'b0;
                    busy  <= 1'b0;
                    if (start) begin
                        shift_reg <= data_in;
                        bit_idx   <= 3'd7;
                        state     <= ASSERT_CS;
                        busy      <= 1'b1;
                    end
                end

                ASSERT_CS: begin
                    // Bring CS low and present first bit on MOSI before first rising edge.
                    cs_n <= 1'b0;
                    mosi <= shift_reg[7];
                    if (clk_div_tick) begin
                        sclk  <= 1'b1; // first rising edge
                        phase <= 1'b1;
                        state <= TRANSFER;
                    end
                end

                TRANSFER: begin
                    if (clk_div_tick) begin
                        // Toggle SCLK each clk_div_tick.
                        sclk  <= ~sclk;
                        phase <= ~phase;

                        if (phase == 1'b1) begin
                            // High -> low transition: update MOSI and bit index.
                            if (bit_idx == 3'd0) begin
                                // Last bit has just been captured on the prior rising edge;
                                // after this falling edge we can deassert CS.
                                state <= DEASSERT_CS;
                            end else begin
                                bit_idx <= bit_idx - 3'd1;
                                mosi    <= shift_reg[bit_idx - 1];
                            end
                        end
                    end
                end

                DEASSERT_CS: begin
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule