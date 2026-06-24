module qspi_core (
    import qspi_pkg::*;

    input qspi_pkg::qspi_control_reg_t ctrl_reg_i,

    input  logic              clk_i,             // system clock
    input  logic              arst_ni,           // active-low async reset

    //=========================================================
    // Control interface (from top / CPU side)
    //=========================================================
    output  logic             start_i,           // start a transaction
    input   logic             we_i,              // 1 = write, 0 = read
    output  logic             busy_o,            // high while running

    input  logic              dummy_i,           // 1 = read needs dummy cycles

    //=========================================================
    // TX FIFO interface (data source for DATA phase)
    //=========================================================
    output logic              tx_fifo_pop_o,     // pop one byte
    input  logic [7:0]        tx_fifo_data_i,    // current byte at FIFO out
    input  logic              tx_fifo_empty_i,   // FIFO empty
    input  logic [7:0]        tx_fifo_count_i

    //=========================================================
    // RX FIFO interface (data sink for read data)
    //=========================================================
    output logic              rx_fifo_push_o,    // push one byte
    output logic [7:0]        rx_fifo_data_o,    // byte to push
    input  logic              rx_fifo_full_i,    // FIFO full
    input  logic [7:0]        rx_fifo_count_i,


    //=========================================================
    // Flash chip select
    //=========================================================
    output logic              cs_no,             // chip select, active low
    output logic              sck_o,
    inout wire [3:0]          io_o,          // data bits on IO0-IO3
      
    
    input  logic [7:0] clk_div0_i, clk_div1_i, clk_div2_i, clk_div3_i,

    
    output logic [3:0]  io_oe_o        // output enable per IO line

);

    logic        start_i;
    logic [3:0]  io_oe_;


qfsm dut1 (
    .clk_i                      (),
    .arst_ni                    (),
    .start_i                    (),
    .we_i                       (),
    .busy_o                     (),
    .dummy_i                    (),
    .ctrl_reg_i                 (),
    .sck_en_o                   (),
    .tx_data_o                  (),
    .tx_width_o                 (),
    .tx_start_o                 (),
    .tx_done_i                  (),
    .rx_en_o                    (),
    .rx_width_o                 (),
    .rx_data_i                  (),
    .rx_done_i                  (),
    .tx_fifo_pop_o              (),
    .tx_fifo_data_i             (),
    .tx_fifo_empty_i            (),
    .rx_fifo_push_o             (),
    .rx_fifo_data_o             (),
    .rx_fifo_full_i             (),
    .cs_no                      (),
    .wip_bit_i                  (),
);



endmodule
