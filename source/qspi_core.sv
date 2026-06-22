module qspi_core (
    import qspi_pkg::*;

    input qspi_pkg::qspi_control_reg_t ctrl_reg_i,

    input logic arst_ni,
    input logic clk_i,

    input  logic we_i,
    input  logic req_i,
    output logic gnt_o,

    input  logic [7:0] data_i,
    input  logic       data_valid_i,
    output logic       data_ready_o,

    output logic [7:0] data_o,
    output logic       data_valid_o,
    input  logic       data_ready_i

);

endmodule
