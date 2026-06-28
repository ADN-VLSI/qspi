`timescale 1ns/1ps

import qspi_pkg::*;

module qspi_core_tb;

    logic              clk_i;
    logic              arst_ni;
    qspi_control_reg_t ctrl_reg_i;
    logic              we_i;
    logic              busy_o;
    logic              dummy_i;

    logic              tx_fifo_pop_o;
    logic [7:0]        tx_fifo_data_i;
    logic              tx_fifo_empty_i;
    logic [7:0]        tx_fifo_count_i;

    logic              rx_fifo_push_o;
    logic [7:0]        rx_fifo_data_o;
    logic              rx_fifo_full_i;
    logic [7:0]        rx_fifo_count_i;

    logic [7:0]        clk_div0_i, clk_div1_i, clk_div2_i, clk_div3_i;

    logic              cs_no;
    logic              sck_o;
    wire  [3:0]        io_io;

    always #1.25 clk_i = ~clk_i;

    qspi_core dut (
        .clk_i           (clk_i),
        .arst_ni         (arst_ni),
        .ctrl_reg_i      (ctrl_reg_i),
        .we_i            (we_i),
        .busy_o          (busy_o),
        .dummy_i         (dummy_i),
        .tx_fifo_pop_o   (tx_fifo_pop_o),
        .tx_fifo_data_i  (tx_fifo_data_i),
        .tx_fifo_empty_i (tx_fifo_empty_i),
        .tx_fifo_count_i (tx_fifo_count_i),
        .rx_fifo_push_o  (rx_fifo_push_o),
        .rx_fifo_data_o  (rx_fifo_data_o),
        .rx_fifo_full_i  (rx_fifo_full_i),
        .rx_fifo_count_i (rx_fifo_count_i),
        .clk_div0_i      (clk_div0_i),
        .clk_div1_i      (clk_div1_i),
        .clk_div2_i      (clk_div2_i),
        .clk_div3_i      (clk_div3_i),
        .cs_no           (cs_no),
        .sck_o           (sck_o),
        .io_io           (io_io)
    );

    // ---- MOCK FLASH for WIP polling (state-driven, no loop) ----
    logic       in_wip_phase;
    logic [2:0] wip_bit_idx;
    int         wip_poll_count;
    logic [7:0] wip_status_byte;

    assign in_wip_phase = (dut.u_fsm.state == dut.u_fsm.WIP_S);

    always_comb begin
        if (wip_poll_count < 2) wip_status_byte = 8'h01;  // busy
        else                    wip_status_byte = 8'h00;  // free
    end

    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            wip_bit_idx    <= 3'd7;
            wip_poll_count <= 0;
        end else if (in_wip_phase && dut.i_sck_pulse_rx) begin
            if (wip_bit_idx != 0) wip_bit_idx <= wip_bit_idx - 1;
            else begin
                wip_bit_idx    <= 3'd7;
                wip_poll_count <= wip_poll_count + 1;
            end
        end
    end

    assign io_io[1] = in_wip_phase ? wip_status_byte[wip_bit_idx] : 1'bz;

    // ---- Mock TX FIFO ----
    assign tx_fifo_data_i  = 8'hC3;
    assign tx_fifo_empty_i = 1'b0;
    assign rx_fifo_full_i  = 1'b0;

    // ---- Monitor ----
    always @(dut.u_fsm.state) begin
        $display("[%0t] state = %s", $time, dut.u_fsm.state.name());
    end

    always @(posedge clk_i) begin
        if (tx_fifo_pop_o)  $display("[%0t]   TX byte popped", $time);
        if (rx_fifo_push_o) $display("[%0t]   RX byte pushed: 0x%02h", $time, rx_fifo_data_o);
    end

    // ---- Stimulus ----
    initial begin
        clk_i           <= 0;
        arst_ni         <= 0;
        we_i            <= 0;
        dummy_i         <= 0;
        ctrl_reg_i      <= '0;
        // IMPORTANT: set TX_DATA_CNT > 0 while count = 0, so that
        // i_start = (count >= TX_DATA_CNT) = (0 >= 2) = 0 (LOW)
        // even right after reset is released. This stops the FSM
        // from leaving IDLE before we configure we_i / the registers.
        ctrl_reg_i.TX_DATA_CNT <= 8'd2;
        tx_fifo_count_i <= 8'd0;
        rx_fifo_count_i <= 8'd0;

        clk_div0_i <= 8'd2;
        clk_div1_i <= 8'd1;
        clk_div2_i <= 8'd1;
        clk_div3_i <= 8'd1;

        repeat (5) @(posedge clk_i);
        arst_ni <= 1;                 // start is LOW here (0 >= 2 is false)
        @(posedge clk_i);

        $display("\n==== TEST: WRITE (with WIP polling) ====");

        // ---- STEP 1: set ALL config + we_i FIRST ----
        // keep start LOW for now: TX_DATA_CNT=2 but count=0  -> 0>=2 false
        we_i                   <= 1'b1;
        ctrl_reg_i.WE_CMD      <= 8'h06;    // WREN
        ctrl_reg_i.WE_CFG      <= 3'b100;   // EN=1
        ctrl_reg_i.WCMD_CMD    <= 8'h02;    // Page Program
        ctrl_reg_i.WCMD_CFG    <= 2'b00;
        ctrl_reg_i.ADDR3       <= 8'h00;
        ctrl_reg_i.ADDR2       <= 8'h01;
        ctrl_reg_i.ADDR1       <= 8'h02;
        ctrl_reg_i.ADDR0       <= 8'h03;
        ctrl_reg_i.WADDR_CMD   <= 3'd3;
        ctrl_reg_i.WADDR_CFG   <= 2'b00;
        ctrl_reg_i.WMODE_CFG   <= 3'b000;
        ctrl_reg_i.WDATA_CMD   <= 3'd2;
        ctrl_reg_i.TX_DATA_CNT <= 8'd2;     // need 2 bytes
        ctrl_reg_i.WDATA_CFG   <= 2'b00;
        tx_fifo_count_i        <= 8'd0;     // start still LOW (0 >= 2 false)

        // let config settle while start is LOW
        //@(posedge clk_i);
       // @(posedge clk_i);

        // ---- STEP 2: now trigger start (config + we_i already stable) ----
        tx_fifo_count_i <= 8'd2;            // 2 >= 2 -> start HIGH

        // ---- run the transaction ----
        wait (busy_o == 1'b1);
        wait (busy_o == 1'b0);
        @(posedge clk_i);
        $display("==== WRITE test done ====\n");

        repeat (20) @(posedge clk_i);
        $display("ALL DONE");
        $finish;
    end

    initial begin
        #300000;
        $display("ERROR: timeout - core stuck somewhere");
        $finish;
    end

    initial begin
        $dumpfile("qspi_core_tb.vcd");
        $dumpvars(0, qspi_core_tb);
    end

endmodule
