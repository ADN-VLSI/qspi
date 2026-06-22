
// Write path:  [WE] → CMD → ADDR → [MODE] → TX_DATA → DONE
// Read  path:        CMD → ADDR → [DUMMY] → [MODE]  → RX_DATA → DONE

import qspi_pkg::*;

module qspi_fsm (
    input  logic             clk_i,
    input  logic             arst_ni,

    input  logic             req_i,
    input logic              gnt_i,
    input  logic             we_i,
    output logic             busy_o,
    output logic             done_o,

    input  qspi_control_reg_t ctrl_i,

    output logic [7:0]       tx_byte,      
    output logic             tx_start,     
    input  logic             tx_done,      
    output logic [1:0]       bus_width,    
    output logic             cs_n,         

    input  logic [7:0]       rx_byte,      
    input  logic             rx_valid,     

    output logic             pop_tx,       
    input  logic [7:0]       tx_fifo_byte, 
    input  logic             tx_empty,     

    output logic             push_rx,      
    output logic [7:0]       rx_fifo_byte, 
    input  logic             rx_full       
);

  /////////////////////////////////////////////////////////////////////////////////////////////////
  // States
  /////////////////////////////////////////////////////////////////////////////////////////////////
   typedef enum logic [5:0] {
    S_IDLE    =  5'd0,
    S_WE_0    =  5'd1,   
    S_WE_CMD  =  5'd2,   
    S_WE_1    =  5'd3,   
    S_WR_0    =  5'd4,   
    S_WR_1    =  5'd5,   
    S_WR_CMD  =  5'd6,   
    S_WR_ADDR =  5'd7,   
    S_WR_MODE =  5'd8,   
    S_WR_DATA =  5'd9,   
    S_RD_0    =  5'd10,  
    S_RD_CMD  =  5'd11,  
    S_RD_ADDR =  5'd12,  
    S_RD_MODE =  5'd13,  
    S_RD_DUMMY = 5'd14, 
    S_RD_DATA =  5'd15,  
    S_RD_1    =  5'd16  
  } state_t;

  state_t state;

  logic [31:0] addr_sr;      // address shift register — MSB sent first
  logic [2:0]  addr_left;    // address bytes still to send after this one
  logic [7:0]  byte_cnt;     // bytes done in current phase
  logic [7:0]  phase_total;  // total bytes needed in current phase (latched)
 
  // ── 32-bit address from four 8-bit registers ─────────────────────────────
  wire [31:0] full_addr = {ctrl_i.ADDR3, ctrl_i.ADDR2,
                           ctrl_i.ADDR1, ctrl_i.ADDR0};
 
  // ── Bus-width constraint validation (combinational, checked by SW) ──────────
  // Rule: data width must be >= addr width
  //   addr=SINGLE(00) → data can be 00/01/10  → always valid
  //   addr=DUAL  (01) → data must be 01 or 10 → invalid if data=00
  //   addr=QUAD  (10) → data must be 10        → invalid if data=00 or 01
  always_comb begin
    cfg_valid_o = 1'b1;
    // Write path
    if (ctrl_i.WADDR_CFG[1:0] == WIDTH_DUAL &&
        ctrl_i.WDATA_CFG[1:0] == WIDTH_SINGLE)
      cfg_valid_o = 1'b0;
    if (ctrl_i.WADDR_CFG[1:0] == WIDTH_QUAD &&
        ctrl_i.WDATA_CFG[1:0] != WIDTH_QUAD)
      cfg_valid_o = 1'b0;
    // Read path
    if (ctrl_i.RADDR_CFG[1:0] == WIDTH_DUAL &&
        ctrl_i.RDATA_CFG[1:0] == WIDTH_SINGLE)
      cfg_valid_o = 1'b0;
    if (ctrl_i.RADDR_CFG[1:0] == WIDTH_QUAD &&
        ctrl_i.RDATA_CFG[1:0] != WIDTH_QUAD)
      cfg_valid_o = 1'b0;
  end
 
  // ── CS_N: combinational Moore output ────────────────────────────────────────
  // HIGH  (deasserted) only in: IDLE, WE_1, RD_1
  // LOW   (asserted)   in all other states — flash is selected
  always_comb begin
    case (state)
      S_IDLE,
      S_WE_1,
      S_RD_1  : cs_n = 1'b1;
      default  : cs_n = 1'b0;
    endcase
  end
 
  // ═══════════════════════════════════════════════════════════════════════════
  // SINGLE always_ff  —  Moore state machine
  // ═══════════════════════════════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      state        <= S_IDLE;
      busy_o       <= 1'b0;
      done_o       <= 1'b0;
      tx_byte      <= 8'h00;
      tx_start     <= 1'b0;
      bus_width    <= WIDTH_SINGLE;
      pop_tx       <= 1'b0;
      push_rx      <= 1'b0;
      rx_fifo_byte <= 8'h00;
      addr_sr      <= '0;
      addr_left    <= '0;
      byte_cnt     <= '0;
      phase_total  <= '0;
    end else begin
 
      // default — clear all one-cycle strobes
      done_o   <= 1'b0;
      tx_start <= 1'b0;
      pop_tx   <= 1'b0;
      push_rx  <= 1'b0;
 
      case (state)
 
        // ─────────────────────────────────────────────────────────────────────
        // IDLE
        // cs_n = 1  (via comb block)
        //
        // Start conditions:
        //   write + WE_CFG[2]=1  →  WE_0   (need WE pulse first)
        //   write + WE_CFG[2]=0  →  WR_0   (skip WE, write immediately)
        //   read                 →  RD_0
        //
        // gnt_i comes from qspi_core: gnt_o = req_i && !busy_o
        // So req_i && gnt_i is true exactly when we are idle and host asks.
        // ─────────────────────────────────────────────────────────────────────
        S_IDLE: begin
          busy_o <= 1'b0;
          if (req_i && gnt_i) begin
            busy_o   <= 1'b1;
            addr_sr  <= full_addr;    // latch full 32-bit address
            byte_cnt <= '0;
            if (wei) begin
              if (ctrl_i.WE_CFG[2]) begin
                // WE_CFG[2]=EN=1 → send Write Enable first
                state <= S_WE_0;
              end else begin
                // WE_CFG[2]=EN=0 → skip WE, go straight to write command
                addr_left <= ctrl_i.WADDR_CMD;  // WADDR_CMD[2:0]=LEN (count-1)
                state     <= S_WR_0;
              end
            end else begin
              // Read — no WE ever needed
              addr_left <= ctrl_i.RADDR_CMD;    // RADDR_CMD[2:0]=LEN (count-1)
              state     <= S_RD_0;
            end
          end
        end
 
        // ═════════════════════════════════════════════════════════════════════
        // WE SUB-TRANSACTION   (cs_n=0 for WE_0 and WE_CMD, cs_n=1 for WE_1)
        // ═════════════════════════════════════════════════════════════════════
 
        // ─────────────────────────────────────────────────────────────────────
        // WE_0 — CS just fell to 0 (comb output).
        // One setup cycle: pre-load WE opcode so it's ready for WE_CMD.
        // Transition: unconditional → WE_CMD
        // ─────────────────────────────────────────────────────────────────────
        S_WE_0: begin
          tx_byte   <= ctrl_i.WE_CMD;         // WE_CMD[7:0]: opcode (e.g. 0x06)
          bus_width <= ctrl_i.WE_CFG[1:0];    // WE_CFG[1:0]: QUAD/DUAL bits
          state     <= S_WE_CMD;
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // WE_CMD — clock out the Write Enable opcode via PHY.
        // tx_byte and bus_width already set in WE_0.
        // Assert tx_start once; wait for tx_done from PHY.
        // Transition: tx_done → WE_1
        // ─────────────────────────────────────────────────────────────────────
        S_WE_CMD: begin
          if (!tx_start && !tx_done)
            tx_start <= 1'b1;
          if (tx_done) begin
            // Latch write address count for WR_ADDR (done here, not in WR_0,
            // so both paths into WR_0 see the correct value)
            addr_left <= ctrl_i.WADDR_CMD;
            state     <= S_WE_1;
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // WE_1 — CS goes HIGH (cs_n=1 via comb block).
        // This provides the required tCS hold time between the two CS pulses.
        // HOW: cs_n is combinationally 1 the ENTIRE time we are in this state.
        //      One system clock cycle = 1/clk_freq seconds of CS-high time.
        //      At 100 MHz: 10 ns ≥ 20 ns? No — tCS=20 ns needs 2+ cycles.
        //      At  50 MHz: 20 ns = tCS exactly.
        //      At  25 MHz: 40 ns > tCS — safe.
        //      For 100 MHz system clocks, add a counter here for 2 cycles.
        // Transition: unconditional → WR_0
        // ─────────────────────────────────────────────────────────────────────
        S_WE_1: begin
          state <= S_WR_0;
        end
 
        // ═════════════════════════════════════════════════════════════════════
        // WRITE MAIN TRANSACTION  (cs_n=0 from WR_0 through WR_DATA)
        // ═════════════════════════════════════════════════════════════════════
 
        // ─────────────────────────────────────────────────────────────────────
        // WR_0 — CS asserts again (new pulse for the actual write command).
        // One setup cycle before sending anything.
        // Transition: unconditional → WR_1
        // ─────────────────────────────────────────────────────────────────────
        S_WR_0: begin
          state <= S_WR_1;
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // WR_1 — Pre-load write command byte.
        // WCMD_CMD[7:0]: the write opcode (e.g. 0x12 for PP4, 0x02 for PP)
        // WCMD_CFG[1:0]: bus width for the command byte
        // Transition: unconditional → WR_CMD
        // ─────────────────────────────────────────────────────────────────────
        S_WR_1: begin
          tx_byte   <= ctrl_i.WCMD_CMD;       // WCMD_CMD[7:0] = opcode
          bus_width <= ctrl_i.WCMD_CFG[1:0];  // WCMD_CFG[1:0] = width
          state     <= S_WR_CMD;
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // WR_CMD — clock out write opcode.
        // Transition: tx_done → WR_ADDR  (pre-load first address byte)
        // ─────────────────────────────────────────────────────────────────────
        S_WR_CMD: begin
          if (!tx_start && !tx_done)
            tx_start <= 1'b1;
          if (tx_done) begin
            // Pre-load first address byte (MSB of full_addr, now in addr_sr)
            tx_byte   <= addr_sr[31:24];
            bus_width <= ctrl_i.WADDR_CFG[1:0];   // WADDR_CFG[1:0] = width
            addr_sr   <= {addr_sr[23:0], 8'h00};  // shift for next byte
            state     <= S_WR_ADDR;
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // WR_ADDR — shift out address bytes one per tx_done.
        //
        //  WADDR_CMD[2:0]=LEN : number of addr bytes MINUS ONE
        //    (0→1 byte, 1→2 bytes, 2→3 bytes, 3→4 bytes)
        //  addr_left : bytes still to send AFTER this one
        //
        // Self-loop (tx_done && addr_left > 0):
        //   shift next byte into tx_byte, decrement addr_left, tx_start=1
        //
        // Exit (tx_done && addr_left == 0 = last byte just sent):
        //   WMODE_CFG[2]=EN=1  →  WR_MODE
        //   WMODE_CFG[2]=EN=0  →  WR_DATA
        // ─────────────────────────────────────────────────────────────────────
        S_WR_ADDR: begin
          if (!tx_start && !tx_done)
            tx_start <= 1'b1;
          if (tx_done) begin
            if (addr_left == '0) begin
              // Last address byte just sent
              if (ctrl_i.WMODE_CFG[2]) begin            // WMODE_CFG[2]=EN
                tx_byte   <= ctrl_i.WMODE_CMD;          // WMODE_CMD[7:0]=VAL
                bus_width <= ctrl_i.WMODE_CFG[1:0];     // WMODE_CFG[1:0]=width
                state     <= S_WR_MODE;
              end else begin
                phase_total <= ctrl_i.WDATA_CMD;        // WDATA_CMD[7:0]=LEN
                byte_cnt    <= '0;
                bus_width   <= ctrl_i.WDATA_CFG[1:0];   // WDATA_CFG[1:0]=width
                state       <= S_WR_DATA;
              end
            end else begin
              // More address bytes to go — self-loop
              tx_byte   <= addr_sr[31:24];
              addr_sr   <= {addr_sr[23:0], 8'h00};
              addr_left <= addr_left - 1'b1;
              tx_start  <= 1'b1;
            end
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // WR_MODE — optional mode/alt byte.
        // Only entered when WMODE_CFG[2]=EN=1.
        // WMODE_CMD[7:0]: the mode byte value (e.g. 0xA0 for XIP)
        // Transition: tx_done → WR_DATA
        // ─────────────────────────────────────────────────────────────────────
        S_WR_MODE: begin
          if (!tx_start && !tx_done)
            tx_start <= 1'b1;
          if (tx_done) begin
            phase_total <= ctrl_i.WDATA_CMD;       // WDATA_CMD[7:0]=data count
            byte_cnt    <= '0;
            bus_width   <= ctrl_i.WDATA_CFG[1:0];
            state       <= S_WR_DATA;
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // WR_DATA — pop bytes from TX FIFO and clock them to flash.
        //
        // WDATA_CMD[7:0]=LEN : total bytes to send (phase_total latched on entry)
        // WDATA_CFG[1:0]     : bus width (latched into bus_width on entry)
        //
        // Two-cycle pop sequence:
        //   Cycle 1: pop_tx=1  →  FIFO presents byte on tx_fifo_byte
        //   Cycle 2: pop_tx=0, load tx_fifo_byte into tx_byte, tx_start=1
        //
        // Self-loop: tx_done && byte_cnt+1 < phase_total
        // Exit:      tx_done && byte_cnt+1 >= phase_total  →  IDLE + done_o
        //
        // Stall: if tx_empty, no pop_tx — FSM waits with CS low.
        //        SW must fill FIFO before asserting req_i to avoid this.
        // ─────────────────────────────────────────────────────────────────────
        S_WR_DATA: begin
          if (!tx_start && !pop_tx && !tx_done && !tx_empty)
            pop_tx <= 1'b1;
          if (pop_tx) begin
            tx_byte  <= tx_fifo_byte;
            tx_start <= 1'b1;
          end
          if (tx_done) begin
            if (byte_cnt + 8'd1 >= phase_total) begin
              done_o <= 1'b1;
              busy_o <= 1'b0;
              state  <= S_IDLE;    // CS↑ happens automatically (IDLE→cs_n=1)
            end else begin
              byte_cnt <= byte_cnt + 8'd1;
            end
          end
        end
 
        // ═════════════════════════════════════════════════════════════════════
        // READ TRANSACTION  (single CS pulse, no WE needed)
        // ═════════════════════════════════════════════════════════════════════
 
        // ─────────────────────────────────────────────────────────────────────
        // RD_0 — CS asserts. One setup cycle, pre-load read opcode.
        // RCMD_CMD[7:0]: read opcode  (e.g. 0x0C fast read 4-byte addr,
        //                               0xEC quad I/O fast read 4-byte addr)
        // RCMD_CFG[1:0]: bus width for command byte (usually SINGLE)
        // Transition: unconditional → RD_CMD
        // ─────────────────────────────────────────────────────────────────────
        S_RD_0: begin
          tx_byte   <= ctrl_i.RCMD_CMD;
          bus_width <= ctrl_i.RCMD_CFG[1:0];
          state     <= S_RD_CMD;
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // RD_CMD — clock out read opcode.
        // Transition: tx_done → RD_ADDR
        // ─────────────────────────────────────────────────────────────────────
        S_RD_CMD: begin
          if (!tx_start && !tx_done)
            tx_start <= 1'b1;
          if (tx_done) begin
            tx_byte   <= addr_sr[31:24];
            bus_width <= ctrl_i.RADDR_CFG[1:0];   // RADDR_CFG[1:0]
            addr_sr   <= {addr_sr[23:0], 8'h00};
            state     <= S_RD_ADDR;
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // RD_ADDR — shift out address bytes.
        // Same logic as WR_ADDR but uses R-side registers.
        //
        // RADDR_CMD[2:0]=LEN : address byte count minus one
        // RADDR_CFG[1:0]     : bus width for address
        //
        // Exit (last byte):
        //   RMODE_CFG[2]=EN=1  →  RD_MODE
        //   RMODE_CFG[2]=EN=0  →  RD_DUMMY
        // ─────────────────────────────────────────────────────────────────────
        S_RD_ADDR: begin
          if (!tx_start && !tx_done)
            tx_start <= 1'b1;
          if (tx_done) begin
            if (addr_left == '0) begin
              if (ctrl_i.RMODE_CFG[2]) begin             // RMODE_CFG[2]=EN
                tx_byte   <= ctrl_i.RMODE_CMD;           // RMODE_CMD[7:0]=VAL
                bus_width <= ctrl_i.RMODE_CFG[1:0];
                state     <= S_RD_MODE;
              end else begin
                phase_total <= ctrl_i.RDATA_CMD;  // RDATA_CMD[7:0]=dummy count
                byte_cnt    <= '0;
                tx_byte     <= 8'h00;
                bus_width   <= ctrl_i.RDATA_CFG[1:0];   // RDATA_CFG[1:0]
                state       <= S_RD_DUMMY;
              end
            end else begin
              tx_byte   <= addr_sr[31:24];
              addr_sr   <= {addr_sr[23:0], 8'h00};
              addr_left <= addr_left - 1'b1;
              tx_start  <= 1'b1;
            end
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // RD_MODE — optional mode/alt byte for read.
        // RMODE_CMD[7:0]=VAL : mode byte value
        // RMODE_CFG[1:0]     : bus width
        // Only entered when RMODE_CFG[2]=EN=1.
        // Transition: tx_done → RD_DUMMY
        // ─────────────────────────────────────────────────────────────────────
        S_RD_MODE: begin
          if (!tx_start && !tx_done)
            tx_start <= 1'b1;
          if (tx_done) begin
            phase_total <= ctrl_i.RDATA_CMD;
            byte_cnt    <= '0;
            tx_byte     <= 8'h00;
            bus_width   <= ctrl_i.RDATA_CFG[1:0];
            state       <= S_RD_DUMMY;
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // RD_DUMMY — clock RDATA_CMD[7:0] dummy bytes (0x00) to flash.
        //
        // Why dummy bytes?
        //   After the address phase, the flash needs some SCLK cycles to fetch
        //   data from its internal cell array.  These are "dummy" or "latency"
        //   cycles — we clock but don't care about the received bits.
        //   RDATA_CMD[7:0] stores the count.  Typically 1 byte (8 dummy clks)
        //   for SPI Fast Read at moderate frequencies.
        //
        // RDATA_CFG[1:0]: bus width (same width as the incoming data phase)
        //
        // Self-loop: tx_done && byte_cnt+1 < phase_total
        // Exit:      tx_done && byte_cnt+1 >= phase_total  →  RD_DATA
        // ─────────────────────────────────────────────────────────────────────
        S_RD_DUMMY: begin
          if (!tx_start && !tx_done)
            tx_start <= 1'b1;
          if (tx_done) begin
            if (byte_cnt + 8'd1 >= phase_total) begin
              byte_cnt    <= '0;
              phase_total <= ctrl_i.RX_DATA_CNT;   // RX_DATA_CNT[7:0] = actual data count
              state       <= S_RD_DATA;
            end else begin
              byte_cnt <= byte_cnt + 8'd1;
              tx_start <= 1'b1;
            end
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // RD_DATA — capture data bytes from flash into RX FIFO.
        //
        // RX_DATA_CNT[7:0]: number of data bytes to receive (phase_total)
        // RDATA_CFG[1:0]  : bus width (already set in bus_width register)
        //
        // rx_valid from PHY: 1-cycle pulse when a complete byte has been
        // assembled by rx_packer.  Each valid byte goes into RX FIFO via push_rx.
        //
        // Stall on rx_full: if RX FIFO is full, we drop the byte — SW must
        // drain the RX FIFO fast enough.  In a real system add back-pressure
        // to the PHY's SCLK enable to pause clocking.
        //
        // Self-loop: rx_valid && byte_cnt+1 < phase_total
        // Exit:      rx_valid && byte_cnt+1 >= phase_total  →  RD_1
        // ─────────────────────────────────────────────────────────────────────
        S_RD_DATA: begin
          if (rx_valid && !rx_full) begin
            rx_fifo_byte <= rx_byte;
            push_rx      <= 1'b1;
            if (byte_cnt + 8'd1 >= phase_total) begin
              state <= S_RD_1;
            end else begin
              byte_cnt <= byte_cnt + 8'd1;
            end
          end
        end
 
        // ─────────────────────────────────────────────────────────────────────
        // RD_1 — CS deasserts (cs_n=1 via comb block) and done_o pulses.
        //
        // WHY THIS STATE EXISTS (two reasons):
        //
        //   1. tCS hold time: flash requires CS to stay HIGH for at least
        //      tCS (20 ns on s25fs256s) after any transaction before the next
        //      CS falling edge.  This state holds cs_n=1 for one full system
        //      clock cycle.  IDLE also has cs_n=1, so total hold = at least
        //      2 cycles (RD_1 + IDLE).  At 100 MHz: 20 ns minimum ✓
        //
        //   2. Clean done_o: asserting done_o here (one cycle after the last
        //      rx_valid) ensures no overlap with active PHY operations.  The
        //      host sees done_o when it is safe to start the next transaction.
        //
        // Transition: unconditional → IDLE
        // ─────────────────────────────────────────────────────────────────────
        S_RD_1: begin
          done_o <= 1'b1;
          busy_o <= 1'b0;
          state  <= S_IDLE;
        end
 
        default: state <= S_IDLE;
 
      endcase
    end
  end
 
endmodule
endmodule