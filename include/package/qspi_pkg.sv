`ifndef QSPI_PKG_SV
`define QSPI_PKG_SV 0

        package qspi_pkg;

          localparam int ADDR_CLK_DIV0    = 'h 0000;
          localparam int ADDR_CLK_DIV1    = 'h 0001;
          localparam int ADDR_CLK_DIV2    = 'h 0002;
          localparam int ADDR_CLK_DIV3    = 'h 0003;
          localparam int ADDR_ADDR0       = 'h 0020;
          localparam int ADDR_ADDR1       = 'h 0021;
          localparam int ADDR_ADDR2       = 'h 0022;
          localparam int ADDR_ADDR3       = 'h 0023;
          localparam int ADDR_TX_DATA_CNT = 'h 0040;
          localparam int ADDR_RX_DATA_CNT = 'h 0041;
          localparam int ADDR_WE_CMD      = 'h 0080;
          localparam int ADDR_WE_CFG      = 'h 0081;
          localparam int ADDR_WCMD_CMD    = 'h 0082;
          localparam int ADDR_WCMD_CFG    = 'h 0083;
          localparam int ADDR_WADDR_CMD   = 'h 0084;
          localparam int ADDR_WADDR_CFG   = 'h 0085;
          localparam int ADDR_WMODE_CMD   = 'h 0086;
          localparam int ADDR_WMODE_CFG   = 'h 0087;
          localparam int ADDR_WDATA_CMD   = 'h 0088;
          localparam int ADDR_WDATA_CFG   = 'h 0089;
          localparam int ADDR_RCMD_CMD    = 'h 008A;
          localparam int ADDR_RCMD_CFG    = 'h 008B;
          localparam int ADDR_RADDR_CMD   = 'h 008C;
          localparam int ADDR_RADDR_CFG   = 'h 008D;
          localparam int ADDR_RMODE_CMD   = 'h 008E;
          localparam int ADDR_RMODE_CFG   = 'h 008F;
          localparam int ADDR_RDATA_CMD   = 'h 0090;
          localparam int ADDR_RDATA_CFG   = 'h 0091;

          typedef struct packed {
                    logic [7:0] CLK_DIV0;
                    logic [7:0] CLK_DIV1;
                    logic [7:0] CLK_DIV2;
                    logic [7:0] CLK_DIV3;
                    logic [7:0] ADDR0;
                    logic [7:0] ADDR1;
                    logic [7:0] ADDR2;
                    logic [7:0] ADDR3;
                    logic [7:0] TX_DATA_CNT;
                    logic [7:0] RX_DATA_CNT;
                    logic [7:0] WE_CMD;
                    logic [2:0] WE_CFG;
                    logic [7:0] WCMD_CMD;
                    logic [1:0] WCMD_CFG;
                    logic [2:0] WADDR_CMD;
                    logic [1:0] WADDR_CFG;
                    logic [7:0] WMODE_CMD;
                    logic [2:0] WMODE_CFG;
                    logic [7:0] WDATA_CMD;
                    logic [1:0] WDATA_CFG;
                    logic [7:0] RCMD_CMD;
                    logic [1:0] RCMD_CFG;
                    logic [2:0] RADDR_CMD;
                    logic [1:0] RADDR_CFG;
                    logic [7:0] RMODE_CMD;
                    logic [2:0] RMODE_CFG;
                    logic [7:0] RDATA_CMD;
                    logic [1:0] RDATA_CFG;
                    logic       START;
                  } qspi_control_reg_t;

        endpackage

`endif

