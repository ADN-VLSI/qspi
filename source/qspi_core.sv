module qspi_core (

    input logic [7:0] CLK_DIV0,
    input logic [7:0] CLK_DIV1,
    input logic [7:0] CLK_DIV2,
    input logic [7:0] CLK_DIV3,
    input logic [7:0] ADDR0,
    input logic [7:0] ADDR1,
    input logic [7:0] ADDR2,
    input logic [7:0] ADDR3,
    input logic [7:0] TX_DATA_CNT,
    input logic [7:0] RX_DATA_CNT,
    input logic [7:0] WE_CMD,
    input logic [2:0] WE_CFG,
    input logic [7:0] WCMD_CMD,
    input logic [1:0] WCMD_CFG,
    input logic [2:0] WADDR_CMD,
    input logic [1:0] WADDR_CFG,
    input logic [7:0] WMODE_CMD,
    input logic [2:0] WMODE_CFG,
    input logic [7:0] WDATA_CMD,
    input logic [1:0] WDATA_CFG,
    input logic [7:0] RCMD_CMD,
    input logic [1:0] RCMD_CFG,
    input logic [2:0] RADDR_CMD,
    input logic [1:0] RADDR_CFG,
    input logic [7:0] RMODE_CMD,
    input logic [2:0] RMODE_CFG,
    input logic [7:0] RDATA_CMD,
    input logic [1:0] RDATA_CFG,

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
