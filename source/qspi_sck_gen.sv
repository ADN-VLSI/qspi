module qspi_sck_gen (
    input  logic       clk_i,
    input  logic       arst_ni,
    input  logic       sck_en_i,
    input  logic [7:0] clk_div0_i, clk_div1_i, clk_div2_i, clk_div3_i,
    output logic       sck_o,
    output logic       sck_pulse_tx_o,
    output logic       sck_pulse_rx_o
);

    logic clk_s0, clk_s1, clk_s2,i_sck;

    // cascade divider
    clk_div #(8) u0 (.arst_ni, .clk_i(clk_i),  .div_i(clk_div0_i), .clk_o(clk_s0));
    clk_div #(8) u1 (.arst_ni, .clk_i(clk_s0), .div_i(clk_div1_i), .clk_o(clk_s1));
    clk_div #(8) u2 (.arst_ni, .clk_i(clk_s1), .div_i(clk_div2_i), .clk_o(clk_s2));
    clk_div #(8) u3 (.arst_ni, .clk_i(clk_s2), .div_i(clk_div3_i), .clk_o(i_sck));

    // edge detect → pulse
    logic sck_d;
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) sck_d <= 1'b0;
        else          sck_d <= sck_o;
    end

    wire sck_rising  = sck_o && !sck_d;
    wire sck_falling = !sck_o && sck_d;

    assign sck_pulse_tx_o = sck_falling && sck_en_i;
    assign sck_pulse_rx_o = sck_rising  && sck_en_i;
    assign sck_o = sck_en_i && i_sck;


endmodule