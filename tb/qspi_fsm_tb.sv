`timescale 1ns/1ps

import qspi_pkg::*;

module qspi_fsm_tb;

    //---------------------------------------------------------
    // Clock / reset
    //---------------------------------------------------------
    logic clk_i;
    logic arst_ni;

    always #5 clk_i = ~clk_i;   // 100 MHz

    //---------------------------------------------------------
    // DUT signals
    //---------------------------------------------------------
    logic              start_i;
    logic              we_i;
    logic              busy_o;
    logic              dummy_i;
    qspi_control_reg_t ctrl_reg_i;
    logic              sck_en_o;
    logic [7:0]        tx_data_o;
    logic [1:0]        tx_width_o;
    logic              tx_start_o;
    logic              tx_done_i;
    logic              rx_en_o;
    logic [1:0]        rx_width_o;
    logic [7:0]        rx_data_i;
    logic              rx_done_i;
    logic              tx_fifo_pop_o;
    logic [7:0]        tx_fifo_data_i;
    logic              tx_fifo_empty_i;
    logic              rx_fifo_push_o;
    logic [7:0]        rx_fifo_data_o;
    logic              rx_fifo_full_i;
    logic              cs_no;
    logic              wip_bit_i;

    //---------------------------------------------------------
    // DUT instance
    //---------------------------------------------------------
    qspi_fsm dut (
        .clk_i           (clk_i),
        .arst_ni         (arst_ni),
        .start_i         (start_i),
        .we_i            (we_i),
        .busy_o          (busy_o),
        .dummy_i         (dummy_i),
        .ctrl_reg_i      (ctrl_reg_i),
        .sck_en_o        (sck_en_o),
        .tx_data_o       (tx_data_o),
        .tx_width_o      (tx_width_o),
        .tx_start_o      (tx_start_o),
        .tx_done_i       (tx_done_i),
        .rx_en_o         (rx_en_o),
        .rx_width_o      (rx_width_o),
        .rx_data_i       (rx_data_i),
        .rx_done_i       (rx_done_i),
        .tx_fifo_pop_o   (tx_fifo_pop_o),
        .tx_fifo_data_i  (tx_fifo_data_i),
        .tx_fifo_empty_i (tx_fifo_empty_i),
        .rx_fifo_push_o  (rx_fifo_push_o),
        .rx_fifo_data_o  (rx_fifo_data_o),
        .rx_fifo_full_i  (rx_fifo_full_i),
        .cs_no           (cs_no),
        .wip_bit_i       (wip_bit_i)
    );

    //=========================================================
    // MOCK shifter: when tx_start_o is high, wait a few SCK
    // cycles then pulse tx_done_i for one cycle.
    // This imitates "one byte has been shifted out".
    //=========================================================
    localparam int BYTE_CYCLES = 4;   // pretend a byte takes 4 clocks

    int tx_cnt;
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            tx_cnt    <= 0;
            tx_done_i <= 1'b0;
        end else begin
            tx_done_i <= 1'b0;                  // default low (one-cycle pulse)
            if (tx_start_o) begin
                if (tx_cnt == BYTE_CYCLES - 1) begin
                    tx_done_i <= 1'b1;          // byte finished
                    tx_cnt    <= 0;
                end else begin
                    tx_cnt <= tx_cnt + 1;
                end
            end else begin
                tx_cnt <= 0;
            end
        end
    end

    //=========================================================
    // MOCK unpacker: when rx_en_o is high, wait a few cycles
    // then pulse rx_done_i and provide a fake byte on rx_data_i.
    //=========================================================
    int rx_cnt;
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            rx_cnt    <= 0;
            rx_done_i <= 1'b0;
            rx_data_i <= 8'h00;
        end else begin
            rx_done_i <= 1'b0;
            if (rx_en_o) begin
                if (rx_cnt == BYTE_CYCLES - 1) begin
                    rx_done_i <= 1'b1;
                    rx_data_i <= 8'hA4;         // fake read data
                    rx_cnt    <= 0;
                end else begin
                    rx_cnt <= rx_cnt + 1;
                end
            end else begin
                rx_cnt <= 0;
            end
        end
    end

    //=========================================================
    // Simple monitor: print state name on every change
    //=========================================================
    // (access internal state via hierarchical reference)
    always @(dut.state) begin
        $display("[%0t] state = %s", $time, dut.state.name());
    end

    //=========================================================
    // Stimulus
    //=========================================================
    initial begin
        // init
        clk_i           = 0;
        arst_ni         = 0;
        start_i         = 0;
        we_i            = 0;
        dummy_i         = 0;
        ctrl_reg_i      = '0;
        tx_fifo_data_i  = 8'h00;
        tx_fifo_empty_i = 0;
        rx_fifo_full_i  = 0;
        wip_bit_i       = 0;

        // reset
        repeat (3) @(posedge clk_i);
        arst_ni = 1;
        @(posedge clk_i);

        //=================================================
        // TEST 1: simple READ transaction (with mode, dummy)
        //=================================================
        $display("\n==== TEST 1: READ (no mode, no dummy) ====");
        ctrl_reg_i.RCMD_CMD  = 8'h03;     // normal read opcode
        ctrl_reg_i.RCMD_CFG  = 2'b00;     // single
        ctrl_reg_i.ADDR3     = 8'h00;
        ctrl_reg_i.ADDR2     = 8'h51;
        ctrl_reg_i.ADDR1     = 8'h60;
        ctrl_reg_i.ADDR0     = 8'h11;
        ctrl_reg_i.RADDR_CMD = 3'd3;      // 3-byte address
        ctrl_reg_i.RADDR_CFG = 2'b00;
        ctrl_reg_i.RMODE_CFG = 3'b100;    // no mode (EN=0)
        ctrl_reg_i.RDATA_CMD = 3'd2;      // read 2 bytes
        ctrl_reg_i.RDATA_CFG = 2'b00;
        dummy_i              = 1'b1;     

        start_i = 1'b1;
        @(posedge clk_i);
        start_i = 1'b0;

        wait (busy_o == 1'b1);    
        wait (busy_o == 1'b0);   
        @(posedge clk_i);
        $display("==== TEST 1 done ====\n");

        repeat (5) @(posedge clk_i);

        //=================================================
        // TEST 2: READ with dummy cycles
        //=================================================
        $display("\n==== TEST 2: READ with dummy ====");
        ctrl_reg_i.RCMD_CMD  = 8'hEB;     // quad read
        ctrl_reg_i.RADDR_CFG = 2'b10;     // quad address
        ctrl_reg_i.RDATA_CFG = 2'b10;     // quad data
        ctrl_reg_i.RMODE_CFG = 3'b000;    // no mode
        dummy_i              = 1'b1;      // dummy needed

        start_i = 1'b1;
        @(posedge clk_i);
        start_i = 1'b0;

        wait (busy_o == 1'b1);    
        wait (busy_o == 1'b0);    
        @(posedge clk_i);
        $display("==== TEST 2 done ====\n");

        repeat (10) @(posedge clk_i);
        $display("\n==== TEST 3: WRITE (mode) ====");
        we_i = '1;
        ctrl_reg_i.WE_CMD  =   8'h06;     // normal read opcode
        ctrl_reg_i.WE_CFG  =   3'b100;
        ctrl_reg_i.WCMD_CMD  = 8'h12;
        ctrl_reg_i.WCMD_CFG  = 2'b10;     // single
        ctrl_reg_i.ADDR3     = 8'h00;
        ctrl_reg_i.ADDR2     = 8'h51;
        ctrl_reg_i.ADDR1     = 8'h60;
        ctrl_reg_i.ADDR0     = 8'h11;
        ctrl_reg_i.WADDR_CMD = 3'd3;      // 3-byte address
        ctrl_reg_i.WADDR_CFG = 2'b00;
        ctrl_reg_i.WMODE_CFG = 3'b100;   
        ctrl_reg_i.WDATA_CMD = 3'd2;      // read 2 bytes
        ctrl_reg_i.WDATA_CFG = 2'b00;
        tx_fifo_data_i = 8'hAA;
        tx_fifo_empty_i = '0;



        start_i = 1'b1;
        @(posedge clk_i);
        start_i = 1'b0;

        wait (busy_o == 1'b1);    
        wait (busy_o == 1'b0);    
        @(posedge clk_i);
        $display("==== TEST 3 done ====\n");
        $display("ALL TESTS COMPLETE");
        $finish;
    end

    //---------------------------------------------------------
    // Safety timeout (so sim never hangs forever)
    //---------------------------------------------------------
    initial begin
        #50000;
        $display("ERROR: timeout - FSM stuck somewhere");
        $finish;
    end

    //---------------------------------------------------------
    // Waveform dump
    //---------------------------------------------------------
    initial begin
        $dumpfile("qspi_fsm_tb.vcd");
        $dumpvars(0, qspi_fsm_tb);
    end

endmodule