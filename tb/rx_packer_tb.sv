`timescale 1ns/1ps

module rx_packer_tb;

    logic        clk_i;
    logic        arst_ni;
    logic        rx_en_i;
    logic [1:0]  rx_width_i;
    logic [7:0]  rx_data_o;
    logic        rx_done_o;
    logic        sck_pulse_i;
    logic [3:0]  io_i;

    // clock
    always #5 clk_i = ~clk_i;

    // DUT
    rx_packer dut (
        .clk_i       (clk_i),
        .arst_ni     (arst_ni),
        .rx_en_i     (rx_en_i),
        .rx_width_i  (rx_width_i),
        .rx_data_o   (rx_data_o),
        .rx_done_o   (rx_done_o),
        .sck_pulse_i (sck_pulse_i),
        .io_i        (io_i)
    );

    //=====================================================
    // MOCK SCK pulse: one-cycle pulse every 4 clocks
    //=====================================================
    int pulse_cnt;
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            pulse_cnt   <= 0;
            sck_pulse_i <= 1'b0;
        end else begin
            sck_pulse_i <= 1'b0;
            if (pulse_cnt == 3) begin
                sck_pulse_i <= 1'b1;
                pulse_cnt   <= 0;
            end else begin
                pulse_cnt <= pulse_cnt + 1;
            end
        end
    end

    //=====================================================
    // Drive one bit on io_i just before each pulse
    // (simulates flash sending data)
    //=====================================================
    // single-mode test bits for 0xB5 = 1011_0101, MSB first
    logic [7:0] test_byte = 8'hB5;
    int bit_idx;

    // feed io_i[0] with the next bit when about to pulse (single mode)
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            bit_idx <= 7;
        end else if (sck_pulse_i && dut.shifting && rx_width_i == 2'b00) begin
            if (bit_idx > 0) bit_idx <= bit_idx - 1;
        end else if (sck_pulse_i && dut.shifting && rx_width_i == 2'b01) begin
            if (bit_idx > 0) bit_idx <= bit_idx - 2;
        end else if (sck_pulse_i && dut.shifting && rx_width_i == 2'b10)
        if (bit_idx >= 4) bit_idx <= bit_idx - 4;   // 7 → 3
    end

    // io_i driven combinationally from current bit
    always_comb begin
        io_i = 4'b0000;
        if (rx_width_i == 2'b00)
            io_i[0] = test_byte[bit_idx];          // single
        else if (rx_width_i == 2'b01)
            io_i[1:0] = test_byte[bit_idx -: 2];   // quad (simplified)
        else if (rx_width_i == 2'b10)
            io_i[3:0] = test_byte[bit_idx -: 4];
    end

    //=====================================================
    // Monitor
    //=====================================================
    always @(posedge clk_i) begin
        if (rx_done_o)
            $display("[%0t] BYTE READY: rx_data_o = %b (0x%02h)", $time, rx_data_o, rx_data_o);
    end

    //=====================================================
    // Stimulus
    //=====================================================
    initial begin
        clk_i      = 0;
        arst_ni    = 0;
        rx_en_i    = 0;
        rx_width_i = 2'b00;

        repeat (3) @(posedge clk_i);
        arst_ni = 1;
        @(posedge clk_i);

        //=================================================
        // TEST 1: single mode, receive 0xB5
        //=================================================
        $display("\n==== TEST 1: SINGLE, expect 0xB5 ====");
        rx_width_i <= 2'b01;
        rx_en_i    <= 1'b1;            // non-blocking! (avoid race)

        wait (rx_done_o == 1'b1);
        @(posedge clk_i);
        rx_en_i <= 1'b0;
        $display("==== TEST 1 done ====\n");

        repeat (10) @(posedge clk_i);
        $display("ALL TESTS COMPLETE");
        $finish;
    end

    // timeout
    initial begin
        #10000;
        $display("ERROR: timeout");
        $finish;
    end

    // waveform
    initial begin
        $dumpfile("rx_packer_tb.vcd");
        $dumpvars(0, rx_packer_tb);
    end

endmodule