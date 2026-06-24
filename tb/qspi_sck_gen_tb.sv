`timescale 1ns/1ps

module qspi_sck_gen_tb;

    logic       clk_i;
    logic       arst_ni;
    logic       sck_en_i;
    logic [7:0] clk_div0_i, clk_div1_i, clk_div2_i, clk_div3_i;
    logic       sck_o;
    logic       sck_pulse_tx_o;
    logic       sck_pulse_rx_o;


    // 400 MHz clock → period = 2.5 ns → half = 1.25 ns
    always #1.25 clk_i = ~clk_i;

    // DUT
    qspi_sck_gen d (
        .clk_i           (clk_i         ),          
        .arst_ni         (arst_ni       ),            
        .sck_en_i        (sck_en_i      ),             
        .clk_div0_i      (clk_div0_i    ),               
        .clk_div1_i      (clk_div1_i    ),               
        .clk_div2_i      (clk_div2_i    ),               
        .clk_div3_i      (clk_div3_i    ),               
        .sck_o           (sck_o         ),          
        .sck_pulse_tx_o  (sck_pulse_tx_o),                   
        .sck_pulse_rx_o  (sck_pulse_rx_o)                  

    );

    initial begin
        clk_i   = 0;
        arst_ni = 0;
        clk_div0_i = 3;  
        clk_div1_i = 1; 
        clk_div2_i = 1;
        clk_div3_i = 1;
        sck_en_i = 1;
/*
target SCK পেতে DIV মান:
  50 MHz  → গুণফল 8  (2,2,2,1)
  133 MHz → গুণফল 3  (3,1,1,1)
  25 MHz  → গুণফল 16 (2,2,2,2)
*/

        repeat (3) @(posedge clk_i);
        arst_ni = 1;
        #300;
        $finish;
    end

    // waveform
    initial begin
        $dumpfile("qspi_sck_gen_tb.vcd");
        $dumpvars(0, qspi_sck_gen_tb);
    end

endmodule