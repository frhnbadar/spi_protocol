`timescale 1ns/1ps

// ============================================================================
// spi_tb.sv
// Class-based, self-checking SystemVerilog testbench for spi_master.v
// (mode 0, single slave, 8-bit transfers) + clk_div.v
//
// Contains: interface, protocol assertions (SVA), transaction, driver,
// monitor, scoreboard, functional coverage, and the top-level test.
// Simulation-only file -- do not add to Design Sources in Vivado.
// ============================================================================

// ----------------------------------------------------------------------
// Interface: bundles DUT I/O and carries protocol assertions
// ----------------------------------------------------------------------
interface spi_if (input logic clk);
    logic       rst_n = 1'b0;      // known value from t=0, not X
    logic       clk_div_tick;
    logic       start = 1'b0;
    logic [7:0] data_in = 8'h00;
    logic       sclk;
    logic       mosi;
    logic       cs_n;
    logic       busy;
    logic       done;

    modport DRV (input clk, output rst_n, start, data_in,
                  input clk_div_tick, sclk, mosi, cs_n, busy, done);

    modport MON (input clk, rst_n, clk_div_tick, start, data_in,
                  sclk, mosi, cs_n, busy, done);

    // -------------------- Protocol assertions (mode 0) --------------------

    // MOSI must be stable while SCLK is high (data only changes on the
    // falling edge in mode 0).
    property mosi_stable_while_sclk_high;
        @(posedge clk) disable iff (!rst_n)
        (sclk && $past(sclk)) |-> ($stable(mosi));
    endproperty
    assert property (mosi_stable_while_sclk_high)
        else $error("[ASSERT] MOSI changed while SCLK was high");

    // SCLK must idle low whenever CS is deasserted.
    property sclk_idle_low_when_deselected;
        @(posedge clk) disable iff (!rst_n)
        (cs_n) |-> (sclk == 1'b0);
    endproperty
    assert property (sclk_idle_low_when_deselected)
        else $error("[ASSERT] SCLK not idling low while CS_N deasserted");

    // done must only pulse for exactly one cycle.
    property done_is_single_cycle;
        @(posedge clk) disable iff (!rst_n)
        done |=> !done;
    endproperty
    assert property (done_is_single_cycle)
        else $error("[ASSERT] done asserted for more than one cycle");

    // busy must be high across the whole cs_n-low window.
    property busy_while_selected;
        @(posedge clk) disable iff (!rst_n)
        (!cs_n) |-> busy;
    endproperty
    assert property (busy_while_selected)
        else $error("[ASSERT] busy deasserted while CS_N low");

endinterface


// ----------------------------------------------------------------------
// Transaction
// ----------------------------------------------------------------------
class spi_txn;
    rand bit [7:0] data;

    // Bias toward corner values (all-0s, all-1s, alternating) plus
    // broad random coverage of the rest of the byte range.
    constraint c_data {
        data dist {
            8'h00         := 5,
            8'hFF         := 5,
            8'hAA         := 5,
            8'h55         := 5,
            [8'h01:8'hFE] :/ 80
        };
    }

    function string to_s();
        return $sformatf("0x%0h", data);
    endfunction
endclass


// ----------------------------------------------------------------------
// Driver: applies transactions to the DUT via the DRV modport
// ----------------------------------------------------------------------
class spi_driver;
    virtual spi_if.DRV vif;
    mailbox #(spi_txn) drv_mbx;

    function new(virtual spi_if.DRV vif, mailbox #(spi_txn) drv_mbx);
        this.vif     = vif;
        this.drv_mbx = drv_mbx;
    endfunction

    task reset();
        vif.rst_n   <= 1'b0;
        vif.start   <= 1'b0;
        vif.data_in <= 8'h00;
        repeat (5) @(posedge vif.clk);
        vif.rst_n   <= 1'b1;
        repeat (2) @(posedge vif.clk);
    endtask

    task run();
        spi_txn txn;
        forever begin
            drv_mbx.get(txn);

            @(posedge vif.clk);
            vif.data_in <= txn.data;
            vif.start   <= 1'b1;
            @(posedge vif.clk);
            vif.start   <= 1'b0;

            // Wait for the transfer to complete before issuing the next.
            wait (vif.done === 1'b1);
            @(posedge vif.clk);
        end
    endtask
endclass


// ----------------------------------------------------------------------
// Monitor: passively samples MOSI like an SPI slave would (captures on
// SCLK rising edge, mode 0) and reconstructs the transmitted byte.
// Also owns functional coverage of captured data values.
// ----------------------------------------------------------------------
class spi_monitor;
    virtual spi_if.MON vif;
    mailbox #(bit [7:0]) mon_mbx; // captured byte -> scoreboard

    bit [7:0] captured_byte;

    covergroup cg_spi @(posedge vif.clk iff vif.done);
        option.per_instance = 1;
        cp_data: coverpoint captured_byte {
            bins zero   = {8'h00};
            bins ones   = {8'hFF};
            bins alt1   = {8'hAA};
            bins alt2   = {8'h55};
            bins others = default;
        }
    endgroup

    function new(virtual spi_if.MON vif, mailbox #(bit [7:0]) mon_mbx);
        this.vif     = vif;
        this.mon_mbx = mon_mbx;
        cg_spi = new();
    endfunction

    task run();
        logic     prev_sclk;
        logic     prev_cs_n;
        bit [7:0] shifted;
        int       bit_cnt;

        shifted   = 8'h00;
        bit_cnt   = 0;
        prev_sclk = 1'b0;
        prev_cs_n = 1'b1;

        forever begin
            // Sample on negedge clk -- a half cycle after the DUT's own
            // posedge-clk NBA updates to cs_n/sclk/mosi have settled.
            // Chaining @(negedge cs_n) then @(posedge sclk) (the previous
            // version) can miss the very first bit: cs_n's negedge and
            // sclk's first posedge can land in the exact same time step
            // (when clk_div_tick already happens to be high the instant
            // CS asserts), and a sequential wait on two derived signals
            // isn't guaranteed to catch a truly simultaneous edge.
            // Comparing against locally-tracked previous values instead
            // catches that case correctly no matter how the edges align.
            @(negedge vif.clk);

            // Start of a new transfer: reset the shift state.
            if (prev_cs_n === 1'b1 && vif.cs_n === 1'b0) begin
                shifted = 8'h00;
                bit_cnt = 0;
            end

            // SCLK rising edge while selected: mode 0 samples here.
            if (vif.cs_n === 1'b0 && prev_sclk === 1'b0 && vif.sclk === 1'b1) begin
                shifted = {shifted[6:0], vif.mosi};
                bit_cnt++;
                if (bit_cnt == 8) begin
                    captured_byte = shifted;
                    mon_mbx.put(shifted);
                end
            end

            prev_sclk = vif.sclk;
            prev_cs_n = vif.cs_n;
        end
    endtask
endclass


// ----------------------------------------------------------------------
// Scoreboard: compares expected (driven) vs. captured (monitored) bytes
// ----------------------------------------------------------------------
class spi_scoreboard;
    mailbox #(spi_txn)   exp_mbx;
    mailbox #(bit [7:0]) mon_mbx;

    int pass_count = 0;
    int fail_count = 0;

    function new(mailbox #(spi_txn) exp_mbx, mailbox #(bit [7:0]) mon_mbx);
        this.exp_mbx = exp_mbx;
        this.mon_mbx = mon_mbx;
    endfunction

    task run();
        spi_txn   exp_txn;
        bit [7:0] got;
        forever begin
            exp_mbx.get(exp_txn);
            mon_mbx.get(got);

            if (got === exp_txn.data) begin
                pass_count++;
                $display("[SCB] PASS  expected=%s got=0x%0h", exp_txn.to_s(), got);
            end else begin
                fail_count++;
                $error("[SCB] FAIL  expected=%s got=0x%0h", exp_txn.to_s(), got);
            end
        end
    endtask

    function void report();
        $display("--------------------------------------------------");
        $display("SCOREBOARD REPORT: %0d passed, %0d failed", pass_count, fail_count);
        $display("--------------------------------------------------");
    endfunction
endclass


// ----------------------------------------------------------------------
// Top-level testbench: DUT instantiation, clocking, test sequence
// ----------------------------------------------------------------------
module spi_tb;

    localparam CLK_PERIOD = 10;   // 100 MHz system clock
    localparam DIVIDER    = 4;    // fast divider for quick sim
    localparam NUM_TXNS   = 40;

    logic clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT interconnect
    spi_if u_if (.clk(clk));

    // clk_div_tick generator
    clk_div #(.DIVIDER(DIVIDER)) u_clk_div (
        .clk          (clk),
        .rst_n        (u_if.rst_n),
        .clk_div_tick (u_if.clk_div_tick)
    );

    // DUT
    spi_master u_dut (
        .clk          (clk),
        .rst_n        (u_if.rst_n),
        .clk_div_tick (u_if.clk_div_tick),
        .start        (u_if.start),
        .data_in      (u_if.data_in),
        .sclk         (u_if.sclk),
        .mosi         (u_if.mosi),
        .cs_n         (u_if.cs_n),
        .busy         (u_if.busy),
        .done         (u_if.done)
    );

    // Env
    mailbox #(spi_txn)   drv_mbx = new();
    mailbox #(spi_txn)   exp_mbx = new();
    mailbox #(bit [7:0]) mon_mbx = new();

    spi_driver     driver;
    spi_monitor    monitor;
    spi_scoreboard scoreboard;

    // Single controlling process: construct, reset, THEN start the
    // driver/monitor/scoreboard together. This removes the race that
    // let the monitor sample X-state signals before reset completed
    // (separate racing `initial` blocks gave no ordering guarantee
    // between construction/reset and .run() -- that's what corrupted
    // the very first transfer).
    initial begin
        spi_txn txn;

        driver     = new(u_if, drv_mbx);
        monitor    = new(u_if, mon_mbx);
        scoreboard = new(exp_mbx, mon_mbx);

        $display("=== SPI master testbench starting ===");
        driver.reset();

        fork
            driver.run();
            monitor.run();
            scoreboard.run();
        join_none

        for (int i = 0; i < NUM_TXNS; i++) begin
            txn = new();
            if (!txn.randomize())
                $fatal(1, "Randomization failed on txn %0d", i);

            exp_mbx.put(txn); // scoreboard's expected value
            drv_mbx.put(txn); // driver applies it to the DUT
        end

        // Allow the last transfer + its scoreboard check to complete.
        // Worst case per transfer: ~ (2 + 8*2) clk_div_tick periods.
        repeat (NUM_TXNS * (2 + 8*2) * DIVIDER + 200) @(posedge clk);

        scoreboard.report();
        if (scoreboard.fail_count != 0)
            $display("*** TEST FAILED: %0d mismatches ***", scoreboard.fail_count);
        else
            $display("*** TEST PASSED: all %0d transfers verified ***", NUM_TXNS);

        $display("Functional coverage: %0.2f%%", monitor.cg_spi.get_coverage());
        $finish;
    end

    // Safety timeout in case of a hang.
    initial begin
        #(CLK_PERIOD * 200000);
        $display("*** TIMEOUT: simulation did not finish in time ***");
        $finish;
    end

    // Waveform dump for viewing in Vivado's simulator.
    initial begin
        $dumpfile("spi_tb.vcd");
        $dumpvars(0, spi_tb);
    end

endmodule