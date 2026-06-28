`timescale 1ps/1ps
// NOTE: compile with +define+SPEEDSIM so the flash model uses the
// shorter timing values (tPP=90us instead of 900us, etc).
//
// IMPORTANT: this TB assumes the core's start logic has been changed to:
//     assign i_start = ctrl_reg_i.START;
// (NOT the old tx_fifo_count >= TX_DATA_CNT). If you have not made that
// change in qspi_core.sv, START will have no effect and read will hang.

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

    // 40 ns period (25 MHz) - gentle for the flash model
    always #20000 clk_i = ~clk_i;

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
    // io_io[0]=SI(IO0), io_io[1]=SO(IO1), io_io[2]=WPNeg, io_io[3]=RESETNeg
    assign io_io[2] = 1'b1;   // WPNeg     = 1 (no write protect)
    assign io_io[3] = 1'b1;   // RESETNeg  = 1 (not in reset)

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

        // power-up wait for the flash model (tPU ~ 300us)
        #350_000_000;
        @(posedge clk_i);
        arst_ni = 1;
        repeat (4) @(posedge clk_i);

        //=================================================
        // STEP 1: WRITE (Page Program, 2 bytes)
        //=================================================
        $display("\n==== STEP 1: WRITE (Page Program) ====");

        push_tx(8'hDE);
        push_tx(8'hAD);

        we_i                   <= 1'b1;
        ctrl_reg_i.WE_CMD      <= 8'h06;   // WREN
        ctrl_reg_i.WE_CFG      <= 3'b100;  // EN
        ctrl_reg_i.WCMD_CMD    <= 8'h02;   // Page Program
        ctrl_reg_i.WCMD_CFG    <= 2'b00;
        ctrl_reg_i.ADDR3       <= 8'h03;
        ctrl_reg_i.ADDR2       <= 8'h02;
        ctrl_reg_i.ADDR1       <= 8'h01;
        ctrl_reg_i.ADDR0       <= 8'h00;
        ctrl_reg_i.WADDR_CMD   <= 8'd3;
        ctrl_reg_i.WADDR_CFG   <= 2'b00;
        ctrl_reg_i.WMODE_CFG   <= 3'b000;
        ctrl_reg_i.WDATA_CMD   <= 3'd2;
        ctrl_reg_i.TX_DATA_CNT <= 8'd2;
        ctrl_reg_i.WDATA_CFG   <= 2'b00;
        @(posedge clk_i);
        ctrl_reg_i.START       <= 1'b1;    // trigger

        wait (busy_o == 1'b1);
        ctrl_reg_i.START       <= 1'b0;    // clear so it doesn't retrigger
        wait (busy_o == 1'b0);
        $display("==== WRITE done ====\n");
        repeat (10) @(posedge clk_i);

        //=================================================
        // STEP 2: READ back the 2 bytes
        //=================================================
        $display("\n==== STEP 2: READ back ====");
        we_i                   <= 1'b0;    // read
        rx_data_out_ready_i    <= 1'b1;    // accept read data
        ctrl_reg_i.RCMD_CMD    <= 8'h03;   // READ
        ctrl_reg_i.RCMD_CFG    <= 2'b00;
        ctrl_reg_i.RADDR_CMD   <= 3'd3;
        ctrl_reg_i.RADDR_CFG   <= 2'b00;
        ctrl_reg_i.RMODE_CFG   <= 3'b000;
        ctrl_reg_i.RDATA_CMD   <= 3'd2;
        ctrl_reg_i.RX_DATA_CNT <= 8'd2;
        ctrl_reg_i.RDATA_CFG   <= 2'b00;
        @(posedge clk_i);
        ctrl_reg_i.START       <= 1'b1;    // trigger read

        wait (busy_o == 1'b1);
        ctrl_reg_i.START       <= 1'b0;    // clear (one-shot) - FIX: was 1'b1
        wait (busy_o == 1'b0);
        $display("==== READ done ====\n");

        repeat (20) @(posedge clk_i);
        $display("ALL DONE");
        $finish;
    end

    initial begin
        #500_000_000;
        $display("ERROR: global timeout");
        $finish;
    end

    initial begin
        $dumpfile("qspi_top_tb.vcd");
        $dumpvars(0, qspi_top_tb);
    end

endmodule
