`timescale 1ns/1ps

module tx_shifter_tb;

    logic        clk_i;
    logic        arst_ni;
    logic        tx_start_i;
    logic [7:0]  tx_data_i;
    logic [1:0]  tx_width_i;
    logic        tx_done_o;
    logic        sck_pulse_i;
    logic [3:0]  io_o;
    logic [3:0]  io_oe_o;

    // clock
    always #5 clk_i = ~clk_i;

    // DUT
    tx_shifter dut (
        .clk_i       (clk_i),
        .arst_ni     (arst_ni),
        .tx_start_i  (tx_start_i),
        .tx_data_i   (tx_data_i),
        .tx_width_i  (tx_width_i),
        .tx_done_o   (tx_done_o),
        .sck_pulse_i (sck_pulse_i),
        .io_o        (io_o),
        .io_oe_o     (io_oe_o)
    );

    //=====================================================
    // MOCK SCK pulse: every 4 clocks, one-cycle pulse
    // (imitates SCK bit period)
    //=====================================================
    int pulse_cnt;
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            pulse_cnt   <= 0;
            sck_pulse_i <= 1'b0;
        end else begin
            sck_pulse_i <= 1'b0;          // default low (one-cycle pulse)
            if (pulse_cnt == 3) begin
                sck_pulse_i <= 1'b1;       // pulse every 4 clocks
                pulse_cnt   <= 0;
            end else begin
                pulse_cnt <= pulse_cnt + 1;
            end
        end
    end

    //=====================================================
    // Monitor: print io_o on every pulse
    //=====================================================
logic pulse_d;
always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) pulse_d <= 1'b0;
    else          pulse_d <= (sck_pulse_i && dut.shifting);
end

// delayed flag দেখে print — এখন io_o update হয়ে গেছে
always @(posedge clk_i) begin
    if (pulse_d)
        $display("[%0t] io_o = %b (oe=%b)", $time, io_o, io_oe_o);
end
    //=====================================================
    // Stimulus
    //=====================================================
    initial begin
        clk_i      = 0;
        arst_ni    = 0;
        tx_start_i = 0;
        tx_data_i  = 8'h00;
        tx_width_i = 2'b00;

        repeat (3) @(posedge clk_i);
        arst_ni = 1;
        repeat (3) @(posedge clk_i);

        //=================================================
        // TEST 1: single mode, send 0xB5 = 1011_0101
        //=================================================
        $display("\n==== TEST 1: SINGLE, 0xB5 ====");
        $display("expect io_o[0]: 1 0 1 1 0 1 0 1 (MSB first)");
        tx_data_i  <= 8'hB5;
        tx_width_i <= 2'b00;       // single
        tx_start_i <= 1'b1;
        

        wait (tx_done_o == 1'b1);
        @(posedge clk_i);
        tx_start_i <= 1'b0;
        $display("==== TEST 1 done ====\n");

        repeat (5) @(posedge clk_i);

        //=================================================
        // TEST 2: quad mode, send 0xB5
        //=================================================
        $display("\n==== TEST 2: QUAD, 0xB5 ====");
        $display("expect io_o: 1011 then 0101");
        tx_data_i  = 8'hB5;
        tx_width_i = 2'b10;       // quad
        tx_start_i <= 1'b1;


        wait (tx_done_o == 1'b1);
        @(posedge clk_i);
        tx_start_i <= 1'b0;
        $display("==== TEST 2 done ====\n");

        repeat (5) @(posedge clk_i);
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
        $dumpfile("shifter_tb.vcd");
        $dumpvars(0, tx_shifter_tb);
    end

endmodule