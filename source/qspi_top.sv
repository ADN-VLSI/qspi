import qspi_pkg::*;

module qspi_top #(
    parameter int FIFO_SIZE  = 4,        // depth = 2^FIFO_SIZE
    parameter int DATA_WIDTH = 8
)(
    input  qspi_control_reg_t ctrl_reg_i,

    input  logic              clk_i,
    input  logic              arst_ni,

    //=========================================================
    // Control
    //=========================================================
    input  logic              we_i,
    output logic              busy_o,
    input  logic              dummy_i,

    //=========================================================
    // TX FIFO write side (from TB / CPU) - valid/ready
    //=========================================================
    input  logic [7:0]        tx_data_in_i,
    input  logic              tx_data_in_valid_i,
    output logic              tx_data_in_ready_o,

    //=========================================================
    // RX FIFO read side (to TB / CPU) - valid/ready
    //=========================================================
    output logic [7:0]        rx_data_out_o,
    output logic              rx_data_out_valid_o,
    input  logic              rx_data_out_ready_i,

    //=========================================================
    // Clock divider configuration
    //=========================================================
    input  logic [7:0]        clk_div0_i, clk_div1_i, clk_div2_i, clk_div3_i,

    //=========================================================
    // Flash-facing pins
    //=========================================================
    output logic              cs_no,
    output logic              sck_o,
    inout  wire  [3:0]        io_io
);

    //=========================================================
    // Wires between core and FIFOs
    //=========================================================
    // TX side: core consumes (pops) from TX FIFO
    logic              core_tx_pop;        // core.tx_fifo_pop_o
    logic [7:0]        tx_fifo_dout;       // tx_fifo.data_out_o
    logic              tx_fifo_dout_valid; // tx_fifo.data_out_valid_o
    logic [FIFO_SIZE:0] tx_fifo_count;     // tx_fifo.count_o (narrow)

    // RX side: core produces (pushes) into RX FIFO
    logic              core_rx_push;       // core.rx_fifo_push_o
    logic [7:0]        core_rx_data;       // core.rx_fifo_data_o

    // core's view of fifo status (widened)
    logic [7:0]        tx_count_8b;
    logic              tx_empty;
    logic              rx_full;

    //=========================================================
    // TX FIFO
    //   write side : driven by TB (tx_data_in_*)
    //   read  side : consumed by core (pop = data_out_ready)
    //=========================================================
    logic tx_fifo_in_ready;   // tx_fifo.data_in_ready_o (unused by core, seen by TB)

    fifo #(
        .FIFO_SIZE (FIFO_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ALLOW_FALLTHROUGH(0)
    ) u_tx_fifo (
        .arst_ni          (arst_ni),
        .clk_i            (clk_i),
        // write side (from TB)
        .data_in_i        (tx_data_in_i),
        .data_in_valid_i  (tx_data_in_valid_i),
        .data_in_ready_o  (tx_data_in_ready_o),
        // read side (to core): core pop == data_out_ready
        .data_out_o       (tx_fifo_dout),
        .data_out_valid_o (tx_fifo_dout_valid),
        .data_out_ready_i (core_tx_pop),
        .count_o          (tx_fifo_count)
    );

    //=========================================================
    // RX FIFO
    //   write side : driven by core (push = data_in_valid)
    //   read  side : consumed by TB (rx_data_out_*)
    //=========================================================
    logic rx_fifo_in_ready;     // rx_fifo.data_in_ready_o (core ignores; could backpressure)
    logic [FIFO_SIZE:0] rx_fifo_count;

    fifo #(
        .FIFO_SIZE (FIFO_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ALLOW_FALLTHROUGH(0)
    ) u_rx_fifo (
        .arst_ni          (arst_ni),
        .clk_i            (clk_i),
        // write side (from core): core push == data_in_valid
        .data_in_i        (core_rx_data),
        .data_in_valid_i  (core_rx_push),
        .data_in_ready_o  (rx_fifo_in_ready),
        // read side (to TB)
        .data_out_o       (rx_data_out_o),
        .data_out_valid_o (rx_data_out_valid_o),
        .data_out_ready_i (rx_data_out_ready_i),
        .count_o          (rx_fifo_count)
    );

    //=========================================================
    // Adapt FIFO status to what the core expects
    //=========================================================
    assign tx_count_8b = {{(8-(FIFO_SIZE+1)){1'b0}}, tx_fifo_count}; // zero-extend to 8b
    assign tx_empty    = (tx_fifo_count == 0);
    assign rx_full     = (rx_fifo_count == (1 << FIFO_SIZE));

    //=========================================================
    // QSPI core
    //=========================================================
    qspi_core u_core (
        .ctrl_reg_i      (ctrl_reg_i),
        .clk_i           (clk_i),
        .arst_ni         (arst_ni),
        .we_i            (we_i),
        .busy_o          (busy_o),
        .dummy_i         (dummy_i),
        // TX FIFO (core side)
        .tx_fifo_pop_o   (core_tx_pop),
        .tx_fifo_data_i  (tx_fifo_dout),
        .tx_fifo_empty_i (tx_empty),
        .tx_fifo_count_i (tx_count_8b),
        // RX FIFO (core side)
        .rx_fifo_push_o  (core_rx_push),
        .rx_fifo_data_o  (core_rx_data),
        .rx_fifo_full_i  (rx_full),
        .rx_fifo_count_i (8'd0),          // core doesn't really use this
        // clock dividers
        .clk_div0_i      (clk_div0_i),
        .clk_div1_i      (clk_div1_i),
        .clk_div2_i      (clk_div2_i),
        .clk_div3_i      (clk_div3_i),
        // flash pins
        .cs_no           (cs_no),
        .sck_o           (sck_o),
        .io_io           (io_io)
    );

endmodule