`timescale 1ps/1ps
// NOTE: compile with +define+SPEEDSIM for shorter flash timings.
//
// IMPORTANT: this TB assumes qspi_core.sv has:
//     assign i_start = ctrl_reg_i.START;
//
// This version mirrors the supervisor's working basic_spi_tb:
//   WRITE: 0x12 (PP4)  with 4-byte address
//   READ : 0x0C (FAST READ 4) with 4-byte address + dummy
// 4-byte address matches what these opcodes expect on the S25FS256S.

import qspi_pkg::*;

module qspi_top_tb;

    qspi_control_reg_t ctrl_reg_i;
    logic              clk_i;
    logic              arst_ni;
    logic              we_i;
    logic              busy_o;
    logic              dummy_i;

    logic [7:0]        tx_data_in_i;
    logic              tx_data_in_valid_i;
    logic              tx_data_in_ready_o;

    logic [7:0]        rx_data_out_o;
    logic              rx_data_out_valid_o;
    logic              rx_data_out_ready_i;

    logic [7:0]        clk_div0_i, clk_div1_i, clk_div2_i, clk_div3_i;

    logic              cs_no;
    logic              sck_o;
    wire  [3:0]        io_io;

    always #20000 clk_i = ~clk_i;   // 40 ns period

    qspi_top #(
        .FIFO_SIZE (4),
        .DATA_WIDTH(8)
    ) dut (
        .ctrl_reg_i          (ctrl_reg_i),
        .clk_i               (clk_i),
        .arst_ni             (arst_ni),
        .we_i                (we_i),
        .busy_o              (busy_o),
        .dummy_i             (dummy_i),
        .tx_data_in_i        (tx_data_in_i),
        .tx_data_in_valid_i  (tx_data_in_valid_i),
        .tx_data_in_ready_o  (tx_data_in_ready_o),
        .rx_data_out_o       (rx_data_out_o),
        .rx_data_out_valid_o (rx_data_out_valid_o),
        .rx_data_out_ready_i (rx_data_out_ready_i),
        .clk_div0_i          (clk_div0_i),
        .clk_div1_i          (clk_div1_i),
        .clk_div2_i          (clk_div2_i),
        .clk_div3_i          (clk_div3_i),
        .cs_no               (cs_no),
        .sck_o               (sck_o),
        .io_io               (io_io)
    );

    // ---- flash model ----
    assign io_io[2] = 1'b1;   // WPNeg    = 1
    assign io_io[3] = 1'b1;   // RESETNeg = 1

    s25fs256s u_flash (
        .SI       (io_io[0]),
        .SO       (io_io[1]),
        .SCK      (sck_o),
        .CSNeg    (cs_no),
        .WPNeg    (io_io[2]),
        .RESETNeg (io_io[3])
    );

    // ---- monitor ----
    always @(dut.u_core.u_fsm.state) begin
        $display("[%0t] state = %s", $time, dut.u_core.u_fsm.state.name());
    end

    // ---- FLASH command monitors ----
    // opcode_in = raw opcode byte the flash shifted in (what we sent)
    // Instruct  = the command the flash decoded it to (NONE = not understood)
    always @(u_flash.opcode_in)
        $display("[%0t]   FLASH opcode_in = 0x%02h", $time, u_flash.opcode_in);
    always @(u_flash.Instruct)
        $display("[%0t]   FLASH Instruct  = %0d", $time, u_flash.Instruct);

    always @(posedge clk_i) begin
        if (rx_data_out_valid_o && rx_data_out_ready_i)
            $display("[%0t]   READ-BACK byte: 0x%02h", $time, rx_data_out_o);
    end

    // ---- push one byte into TX FIFO ----
    task push_tx(input [7:0] b);
        begin
            @(posedge clk_i);
            tx_data_in_i       <= b;
            tx_data_in_valid_i <= 1'b1;
            @(posedge clk_i);
            while (!tx_data_in_ready_o) @(posedge clk_i);
            tx_data_in_valid_i <= 1'b0;
        end
    endtask

    // ---- stimulus ----
    initial begin
        clk_i               <= 0;
        arst_ni             <= 0;
        we_i                <= 0;
        dummy_i             <= 0;
        ctrl_reg_i          <= '0;
        tx_data_in_i        <= '0;
        tx_data_in_valid_i  <= 0;
        rx_data_out_ready_i <= 0;

        clk_div0_i <= 8'd2;
        clk_div1_i <= 8'd1;
        clk_div2_i <= 8'd1;
        clk_div3_i <= 8'd1;

        // power-up wait (tPU ~ 300us)
        #350_000_000;
        @(posedge clk_i);
        arst_ni = 1;
        repeat (4) @(posedge clk_i);

        //=================================================
        // STEP 1: WRITE  -- PP4 (0x12), 4-byte address, 2 data bytes
        // Address = 0x00516011  (same as supervisor TB)
        //=================================================
        $display("\n==== STEP 1: WRITE (PP4, 4-byte addr) ====");

        push_tx(8'hDE);
        push_tx(8'hAD);

        we_i                   <= 1'b1;
        dummy_i                <= 1'b0;          // write: no dummy
        ctrl_reg_i.WE_CMD      <= 8'h06;         // WREN
        ctrl_reg_i.WE_CFG      <= 3'b100;        // EN
        ctrl_reg_i.WCMD_CMD    <= 8'h12;         // PP4  (4-byte address Page Program)
        ctrl_reg_i.WCMD_CFG    <= 2'b00;
        ctrl_reg_i.ADDR3       <= 8'h00;         // 4-byte address: 0x00516011
        ctrl_reg_i.ADDR2       <= 8'h51;
        ctrl_reg_i.ADDR1       <= 8'h60;
        ctrl_reg_i.ADDR0       <= 8'h11;
        ctrl_reg_i.WADDR_CMD   <= 8'd4;          // 4 address bytes
        ctrl_reg_i.WADDR_CFG   <= 2'b00;
        ctrl_reg_i.WMODE_CFG   <= 3'b000;        // no mode byte
        ctrl_reg_i.WDATA_CMD   <= 3'd2;          // 2 data bytes
        ctrl_reg_i.TX_DATA_CNT <= 8'd2;
        ctrl_reg_i.WDATA_CFG   <= 2'b00;
        @(posedge clk_i);
        ctrl_reg_i.START       <= 1'b1;

        wait (busy_o == 1'b1);
        ctrl_reg_i.START       <= 1'b0;          // one-shot
        wait (busy_o == 1'b0);
        $display("==== WRITE done ====\n");

        // ---- PEEK INTO FLASH MEMORY ----
        // Mem is "integer Mem[0:AddrRANGE]" inside the model, indexed by
        // the full byte address. After the Page Program of DE,AD at
        // 0x00516011 these should read back DE and AD. If they read the
        // erased value (MaxData) instead, the WRITE landed wrong (address
        // or data), and that — not the read path — is the root of the zz.
        $display("FLASH Mem[0x00516011] = 0x%02h (expect DE)", u_flash.Mem[32'h00516011]);
        $display("FLASH Mem[0x00516012] = 0x%02h (expect AD)", u_flash.Mem[32'h00516012]);

        repeat (10) @(posedge clk_i);

        // ---- DIAGNOSTIC DELAY ----
        // Mirror supervisor's fixed wait so the flash's internal Page Program
        // (tPP ~ 90us) is guaranteed complete before we read.
        // If read-back data is now correct (DE AD instead of zz), then the
        // WIP poll was terminating too early (program not finished -> zz).
        // If still zz, the problem is in the read path (dummy / SCK), not WIP.
        #750_000_000;   // 750 us (same as supervisor's tdevice_WRR)

        //=================================================
        // STEP 2: READ  -- FAST READ 4 (0x0C), 4-byte addr, dummy, 2 bytes
        //=================================================
        $display("\n==== STEP 2: READ back (FAST READ 4) ====");
        we_i                   <= 1'b0;          // read
        dummy_i                <= 1'b1;          // FAST READ needs dummy cycles
        rx_data_out_ready_i    <= 1'b1;
        ctrl_reg_i.RCMD_CMD    <= 8'h0C;         // FAST READ 4 (4-byte address)
        ctrl_reg_i.RCMD_CFG    <= 2'b00;
        ctrl_reg_i.RADDR_CMD   <= 3'd4;          // 4 address bytes
        ctrl_reg_i.RADDR_CFG   <= 2'b00;
        ctrl_reg_i.RMODE_CFG   <= 3'b000;        // no mode byte
        ctrl_reg_i.RDATA_CMD   <= 3'd2;          // 2 data bytes
        ctrl_reg_i.RX_DATA_CNT <= 8'd2;
        ctrl_reg_i.RDATA_CFG   <= 2'b00;
        // address already set to 0x00516011 above; keep it
        @(posedge clk_i);
        ctrl_reg_i.START       <= 1'b1;

        wait (busy_o == 1'b1);
        ctrl_reg_i.START       <= 1'b0;          // one-shot
        wait (busy_o == 1'b0);
        $display("==== READ done ====\n");

        repeat (20) @(posedge clk_i);
        $display("ALL DONE  (expected read-back: DE AD)");
        $finish;
    end

    initial begin
        #2_000_000_000;   // 2 ms - large enough for power-up + write + 750us delay + read
        $display("ERROR: global timeout");
        $finish;
    end

    initial begin
        $dumpfile("qspi_top_tb.vcd");
        $dumpvars(0, qspi_top_tb);
    end

endmodule