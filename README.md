# SPI Master — Verilog RTL Design & SystemVerilog Verification

A parameterized **8-bit SPI Master controller** implemented in **Verilog-2001**, supporting **SPI Mode 0 (CPOL=0, CPHA=0)** with MSB-first data transmission.

The project includes a dedicated clock-divider module for SCLK timing and a self-checking **SystemVerilog verification environment** containing protocol assertions, constrained-random transactions, driver, monitor, scoreboard, and functional coverage.

---

## Features

* 8-bit SPI Master
* SPI **Mode 0**

  * CPOL = 0
  * CPHA = 0
* SCLK idles LOW
* Data transmitted **MSB first**
* Data changes on the **falling edge** of SCLK
* Data is sampled on the **rising edge** of SCLK
* Active-low chip select (`CS_N`)
* Configurable clock-divider value
* Busy status indication
* One-cycle `done` pulse at the end of a transfer
* Asynchronous active-low reset
* FSM-based SPI controller
* Self-checking SystemVerilog testbench
* Protocol assertions using SVA
* Constrained-random transaction generation
* Functional coverage
* Scoreboard-based data verification
* Waveform generation for simulation/debugging

---

## Architecture

![SPI Master Architecture](docs/spi_architecture.png)

The design consists of two main RTL modules:

### 1. `clk_div`

Generates a periodic `clk_div_tick` pulse from the system clock.

```text
System Clock
     │
     ▼
┌──────────────┐
│   clk_div    │
│              │
│  DIVIDER     │
└──────┬───────┘
       │
       ▼
 clk_div_tick
```

The tick controls the timing of SCLK transitions inside the SPI Master.

---

### 2. `spi_master`

The SPI Master controls:

* `SCLK`
* `MOSI`
* `CS_N`
* Transfer state
* Bit counter
* Shift register
* `busy`
* `done`

```text
                 ┌─────────────────────┐
 clk ───────────►│                     │
 rst_n ─────────►│                     │
 start ─────────►│                     │
 data_in[7:0] ─►│    SPI MASTER       │────► SCLK
 clk_div_tick ─►│      MODE 0         │────► MOSI
                 │                     │────► CS_N
                 │                     │────► busy
                 │                     │────► done
                 └─────────────────────┘
```

---

## SPI Mode 0

This project implements:

```text
CPOL = 0
CPHA = 0
```

Therefore:

* SCLK remains LOW when idle.
* The first active edge is a **rising edge**.
* Data is sampled on the **rising edge**.
* Data changes on the **falling edge**.

### Transfer sequence

```text
        ┌───┐   ┌───┐   ┌───┐
SCLK ───┘   └───┘   └───┘   └───

MOSI    b7    b6    b5    b4 ... b0
        │     │     │     │
        ↑     ↑     ↑     ↑
      Sample Sample Sample Sample
```

The master presents the next data bit during the LOW phase so that the slave can safely sample it on the following rising edge.

---

# State Machine

The `spi_master` uses a four-state FSM:

```text
                  start
        ┌────────────────────────┐
        │                        ▼
    ┌───────┐              ┌────────────┐
    │ IDLE  │─────────────►│ ASSERT_CS  │
    └───▲───┘              └─────┬──────┘
        │                        │
        │                        │ clk_div_tick
        │                        ▼
        │                  ┌────────────┐
        │                  │  TRANSFER  │
        │                  └─────┬──────┘
        │                        │
        │          bit_idx == 0  │
        │          after falling │
        │             edge       ▼
        │                  ┌─────────────┐
        └──────────────────│ DEASSERT_CS │
                           └─────────────┘
```

### `IDLE`

Default state.

```text
CS_N = 1
SCLK = 0
busy = 0
```

When `start` is asserted:

* `data_in` is loaded into the shift register.
* `bit_idx` is initialized to 7.
* `busy` is asserted.
* FSM moves to `ASSERT_CS`.

---

### `ASSERT_CS`

The slave is selected:

```text
CS_N = 0
```

The first bit:

```text
MOSI = shift_reg[7]
```

is placed on the MOSI line before the first rising SCLK edge.

When `clk_div_tick` occurs, SCLK transitions HIGH and the FSM enters `TRANSFER`.

---

### `TRANSFER`

SCLK toggles on every `clk_div_tick`.

```text
clk_div_tick
     │
     ▼
 SCLK toggles
```

For Mode 0:

```text
Rising edge  → slave samples MOSI
Falling edge → master updates MOSI
```

On each falling edge:

* `bit_idx` is decremented.
* The next MOSI bit is presented.

After bit 0 has been sampled and the final falling edge occurs, the FSM moves to `DEASSERT_CS`.

---

### `DEASSERT_CS`

The transfer is completed.

```text
CS_N = 1
SCLK = 0
busy = 0
done = 1
```

`done` is asserted for one clock cycle before returning to `IDLE`.

---

# RTL Design

## File Structure

```text
spi_master/
│
├── rtl/
│   ├── clk_div.v
│   └── spi_master.v
│
├── tb/
│   └── spi_tb.sv
│
├── docs/
│   └── spi_architecture.png
│
├── README.md
└── .gitignore
```

---

## `clk_div.v`

The clock-divider module generates a one-clock-cycle `clk_div_tick` pulse every `DIVIDER` system-clock cycles.

```text
System Clock
    │
    ▼
┌──────────────┐
│ Clock        │
│ Divider      │
│              │
│ count        │
└──────┬───────┘
       │
       ▼
clk_div_tick
```

The divider is configurable through:

```verilog
parameter DIVIDER = 8
```

---

## `spi_master.v`

The SPI controller contains:

### Shift Register

Stores the byte being transmitted.

```verilog
reg [7:0] shift_reg;
```

Transmission starts from:

```text
shift_reg[7]
```

and proceeds toward:

```text
shift_reg[0]
```

### Bit Counter

```verilog
reg [2:0] bit_idx;
```

Tracks the current bit from:

```text
7 → 6 → 5 → 4 → 3 → 2 → 1 → 0
```

### Phase Tracking

```verilog
reg phase;
```

Tracks the current SCLK phase:

```text
phase = 0 → SCLK LOW
phase = 1 → SCLK HIGH
```

### FSM

```text
IDLE
  ↓
ASSERT_CS
  ↓
TRANSFER
  ↓
DEASSERT_CS
  ↓
IDLE
```

---

# Interface

| Signal         | Direction | Description                       |
| -------------- | --------- | --------------------------------- |
| `clk`          | Input     | System clock                      |
| `rst_n`        | Input     | Active-low asynchronous reset     |
| `clk_div_tick` | Input     | Clock-divider timing pulse        |
| `start`        | Input     | Starts an SPI transfer            |
| `data_in[7:0]` | Input     | Byte to transmit                  |
| `sclk`         | Output    | SPI serial clock                  |
| `mosi`         | Output    | Master Out, Slave In              |
| `cs_n`         | Output    | Active-low chip select            |
| `busy`         | Output    | High while transfer is active     |
| `done`         | Output    | One-cycle transfer-complete pulse |

---

# Verification

The project uses a **class-based SystemVerilog verification environment**.

The testbench contains:

```text
                 ┌──────────────┐
                 │ Transaction  │
                 └──────┬───────┘
                        │
                        ▼
                 ┌──────────────┐
                 │    Driver    │
                 └──────┬───────┘
                        │
                        ▼
                 ┌──────────────┐
                 │     DUT      │
                 │ SPI Master   │
                 └──────┬───────┘
                        │
                        ▼
                 ┌──────────────┐
                 │   Monitor    │
                 └──────┬───────┘
                        │
                        ▼
                 ┌──────────────┐
                 │  Scoreboard  │
                 └──────────────┘
```

---

## Testbench Components

### Interface

`spi_if` bundles the DUT signals and contains protocol assertions.

### Transaction

`spi_txn` generates randomized 8-bit transfer values.

Special emphasis is given to:

```text
00h
FFh
AAh
55h
```

along with randomized values across the remaining byte range.

### Driver

The driver:

1. Applies reset.
2. Drives `data_in`.
3. Pulses `start`.
4. Waits for `done`.
5. Sends the next transaction.

### Monitor

The monitor behaves like an SPI slave from the observation perspective.

For Mode 0 it:

* Detects SCLK rising edges.
* Samples MOSI.
* Reconstructs the transmitted byte.
* Sends the captured byte to the scoreboard.
* Collects functional coverage.

### Scoreboard

The scoreboard compares:

```text
Expected Data
      │
      ▼
┌─────────────┐
│ Scoreboard  │
└──────┬──────┘
       │
       ▼
Captured Data
```

A transaction passes when:

```text
captured_byte == expected_byte
```

### Assertions

The verification environment checks important SPI protocol properties, including:

* MOSI remains stable while SCLK is HIGH.
* SCLK remains LOW when `CS_N` is deasserted.
* `done` is a one-cycle pulse.
* `busy` remains asserted while the slave is selected.

---

# Functional Coverage

Functional coverage is collected for transmitted data values.

Coverage bins include:

```text
00h
FFh
AAh
55h
Other values
```

This provides targeted coverage of:

* All-zero data
* All-one data
* Alternating-bit patterns
* General randomized data

---

# Simulation Configuration

The testbench currently uses:

```text
System Clock = 100 MHz
Clock Period = 10 ns
DIVIDER      = 4
Transactions = 40
SPI Mode     = 0
Data Width   = 8 bits
```

The testbench generates a waveform dump:

```text
spi_tb.vcd
```

for signal-level debugging and protocol inspection.

---

# Simulation Results

The verification environment is configured for **40 constrained-random SPI transfers**.

Each transaction is checked automatically using the scoreboard:

```text
Expected byte
      │
      ▼
    DUT
      │
      ▼
Captured MOSI byte
      │
      ▼
Scoreboard comparison
```

The testbench also reports:

* Number of passed transactions
* Number of failed transactions
* Functional coverage percentage
* Protocol assertion failures

> Simulation results should be updated here with the actual simulator output after the final verification run.

---

# Synthesis

The RTL design is written in **plain Verilog-2001** and is intended to be synthesizable.

Synthesis targets:

```text
rtl/clk_div.v
rtl/spi_master.v
```

The SystemVerilog testbench is simulation-only and should not be included in the Vivado Design Sources.

> Add actual synthesis utilization/timing results here after running synthesis.

---

# Implementation

The design can be taken through the FPGA implementation flow after synthesis.

Typical flow:

```text
RTL
 │
 ▼
Synthesis
 │
 ▼
Optimization
 │
 ▼
Place & Route
 │
 ▼
Timing Analysis
 │
 ▼
Bitstream
```

> Implementation and timing results are intentionally not listed until they are measured on the target FPGA.

---

# Tools & Technologies

* **Verilog-2001** — RTL design
* **SystemVerilog** — Verification
* **SVA** — Protocol assertions
* **Vivado** — FPGA design/simulation flow
* **XSim** — Simulation
* **VCD** — Waveform dumping

---

# How to Run

## 1. Add RTL Sources

Add:

```text
rtl/clk_div.v
rtl/spi_master.v
```

to the simulator/project.

## 2. Add Testbench

Add:

```text
tb/spi_tb.sv
```

as the simulation source.

Do **not** add the testbench as a synthesis source.

## 3. Set Simulation Top

Set:

```text
spi_tb
```

as the simulation top module.

## 4. Run Simulation

Run the behavioral simulation and inspect:

```text
cs_n
sclk
mosi
busy
done
```

The expected Mode-0 behavior is:

```text
CS_N  → LOW during transfer

SCLK  → LOW → HIGH → LOW ...

MOSI  → MSB first

Sample → Rising SCLK edge

Change → Falling SCLK edge

CS_N  → HIGH after final falling edge
```

---

# Project Status

| Component                  | Status                          |
| -------------------------- | ------------------------------- |
| SPI Master RTL             | ✅ Implemented                   |
| Clock Divider              | ✅ Implemented                   |
| SPI Mode 0                 | ✅ Implemented                   |
| 8-bit MSB-first transfer   | ✅ Implemented                   |
| FSM                        | ✅ Implemented                   |
| SystemVerilog Testbench    | ✅ Implemented                   |
| Constrained-Random Testing | ✅ Implemented                   |
| Scoreboard                 | ✅ Implemented                   |
| Protocol Assertions        | ✅ Implemented                   |
| Functional Coverage        | ✅ Implemented                   |
| Simulation                 | 🔄 Final results to be recorded |
| Synthesis                  | 🔄 To be recorded               |
| Implementation             | 🔄 To be recorded               |
| FPGA Hardware Testing      | 🔄 To be recorded               |

---

# Future Improvements

Potential extensions to the controller include:

* CPOL/CPHA configurable SPI modes
* Parameterized data width
* Multiple SPI slaves
* Programmable clock polarity and phase
* Receive-data (`MISO`) support
* Full-duplex SPI transfers
* Register-based configuration interface
* FPGA hardware validation

---

## Author

**Farhan Badar**

B.Tech Electronics — VLSI Design & Technology
Jamia Millia Islamia

---

## License

This project is intended for educational, RTL design, FPGA, and digital hardware verification purposes.
