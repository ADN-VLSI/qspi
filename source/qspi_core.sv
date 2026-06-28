import qspi_pkg::*;

module qspi_core (

    input  qspi_control_reg_t ctrl_reg_i,

    input  logic              clk_i,             // system clock
    input  logic              arst_ni,           // active-low async reset
    //input  logic              i_start,

    //=========================================================
    // Control interface (from top / CPU side)
    //=========================================================
    input   logic             we_i,              // 1 = write, 0 = read
    output  logic             busy_o,            // high while running
    input   logic             dummy_i,           // 1 = read needs dummy cycles

    //=========================================================
    // TX FIFO interface (data source for DATA phase)
    //=========================================================
    output logic              tx_fifo_pop_o,     // pop one byte
    input  logic [7:0]        tx_fifo_data_i,    // current byte at FIFO out
    input  logic              tx_fifo_empty_i,   // FIFO empty
    input  logic [7:0]        tx_fifo_count_i,   // bytes currently in TX FIFO

    //=========================================================
    // RX FIFO interface (data sink for read data)
    //=========================================================
    output logic              rx_fifo_push_o,    // push one byte
    output logic [7:0]        rx_fifo_data_o,    // byte to push
    input  logic              rx_fifo_full_i,    // FIFO full
    input  logic [7:0]        rx_fifo_count_i,   // bytes currently in RX FIFO

    //=========================================================
    // Clock divider configuration (cascade)
    //=========================================================
    input  logic [7:0]        clk_div0_i,
    input  logic [7:0]        clk_div1_i,
    input  logic [7:0]        clk_div2_i,
    input  logic [7:0]        clk_div3_i,

    //=========================================================
    // Flash-facing pins
    //=========================================================
    output logic              cs_no,             // chip select, active low
    output logic              sck_o,             // serial clock
    inout  wire  [3:0]        io_io              // bidirectional IO0-IO3
);

    //=========================================================
    // Internal signals
    //=========================================================
    logic              i_start;

    // FSM <-> SCK gen
    logic              i_sck_en;

    // FSM -> TX shifter
    logic [7:0]        i_tx_data;
    logic [1:0]        i_tx_width;
    logic              i_tx_start;
    // TX shifter -> FSM
    logic              i_tx_done;

    // FSM -> RX packer
    logic              i_rx_en;
    logic [1:0]        i_rx_width;
    // RX packer -> FSM
    logic [7:0]        i_rx_data;
    logic              i_rx_done;

    // SCK gen -> shifter / packer
    logic              i_sck_pulse_tx;
    logic              i_sck_pulse_rx;

    // TX shifter -> IO (drive side)
    logic [3:0]        i_io_o;
    logic [3:0]        i_io_oe;

    //=========================================================
    // Start logic (write: enough bytes in TX FIFO)
    //   NOTE: read-start path still to be finalized with supervisor.
    //=========================================================
    assign i_start = ctrl_reg_i.START;

    //=========================================================
    // Tristate IO buffers (bidirectional pins)
    //   write : controller drives (i_io_oe = 1)
    //   read  : controller releases (i_io_oe = 0), flash drives
    //=========================================================
    assign io_io[0] = i_io_oe[0] ? i_io_o[0] : 1'bz;
    assign io_io[1] = i_io_oe[1] ? i_io_o[1] : 1'bz;
    assign io_io[2] = i_io_oe[2] ? i_io_o[2] : 1'bz;
    assign io_io[3] = i_io_oe[3] ? i_io_o[3] : 1'bz;

    //=========================================================
    // FSM (brain)
    //=========================================================
    qspi_fsm u_fsm (
        .clk_i           (clk_i),
        .arst_ni         (arst_ni),
        .start_i         (i_start),
        .we_i            (we_i),
        .busy_o          (busy_o),
        .dummy_i         (dummy_i),
        .ctrl_reg_i      (ctrl_reg_i),
        .sck_en_o        (i_sck_en),
        .tx_data_o       (i_tx_data),
        .tx_width_o      (i_tx_width),
        .tx_start_o      (i_tx_start),
        .tx_done_i       (i_tx_done),
        .rx_en_o         (i_rx_en),
        .rx_width_o      (i_rx_width),
        .rx_data_i       (i_rx_data),
        .rx_done_i       (i_rx_done),
        .tx_fifo_pop_o   (tx_fifo_pop_o),
        .tx_fifo_data_i  (tx_fifo_data_i),
        .rx_fifo_push_o  (rx_fifo_push_o),
        .rx_fifo_data_o  (rx_fifo_data_o),
        .cs_no           (cs_no)
    );

    //=========================================================
    // TX shifter (byte -> bits)
    //=========================================================
    tx_shifter u_tx_shifter (
        .clk_i        (clk_i),
        .arst_ni      (arst_ni),
        .tx_start_i   (i_tx_start),
        .tx_data_i    (i_tx_data),
        .tx_width_i   (i_tx_width),
        .tx_done_o    (i_tx_done),
        .sck_pulse_i  (i_sck_pulse_tx),
        .io_o         (i_io_o),
        .io_oe_o      (i_io_oe)
    );

    //=========================================================
    // RX packer (bits -> byte)
    //   reads directly from the actual pins (io_io), since
    //   during read the flash drives the bus, not the shifter.
    //=========================================================
    rx_packer u_rx_packer (
        .clk_i        (clk_i),
        .arst_ni      (arst_ni),
        .rx_en_i      (i_rx_en),
        .rx_width_i   (i_rx_width),
        .rx_data_o    (i_rx_data),
        .rx_done_o    (i_rx_done),
        .sck_pulse_i  (i_sck_pulse_rx),
        .io_i         (io_io)
    );

    //=========================================================
    // SCK generator (cascade divider + pulses)
    //=========================================================
    qspi_sck_gen u_sck_gen (
        .clk_i          (clk_i),
        .arst_ni        (arst_ni),
        .sck_en_i       (i_sck_en),
        .clk_div0_i     (clk_div0_i),
        .clk_div1_i     (clk_div1_i),
        .clk_div2_i     (clk_div2_i),
        .clk_div3_i     (clk_div3_i),
        .sck_o          (sck_o),
        .sck_pulse_tx_o (i_sck_pulse_tx),
        .sck_pulse_rx_o (i_sck_pulse_rx)
    );

endmodule