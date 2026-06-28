import qspi_pkg::*;

module qspi_fsm (
    //=========================================================
    // Clock and Reset
    //=========================================================
    input  logic              clk_i,
    input  logic              arst_ni,

    //=========================================================
    // Control interface
    //=========================================================
    input  logic              start_i,
    input  logic              we_i,
    output logic              busy_o,
    input  logic              dummy_i,

    //=========================================================
    // Configuration
    //=========================================================
    input  qspi_control_reg_t ctrl_reg_i,

    //=========================================================
    // SCK generator control
    //=========================================================
    output logic              sck_en_o,

    //=========================================================
    // TX shifter interface
    //=========================================================
    output logic [7:0]        tx_data_o,
    output logic [1:0]        tx_width_o,
    output logic              tx_start_o,
    input  logic              tx_done_i,

    //=========================================================
    // RX unpacker interface
    //=========================================================
    output logic              rx_en_o,
    output logic [1:0]        rx_width_o,
    input  logic [7:0]        rx_data_i,
    input  logic              rx_done_i,

    //=========================================================
    // TX FIFO interface
    //=========================================================
    output logic              tx_fifo_pop_o,
    input  logic [7:0]        tx_fifo_data_i,

    //=========================================================
    // RX FIFO interface
    //=========================================================
    output logic              rx_fifo_push_o,
    output logic [7:0]        rx_fifo_data_o,

    //=========================================================
    // Flash chip select
    //=========================================================
    output logic              cs_no
);

    //---------------------------------------------------------
    // State declaration
    //   WIP split into two phases:
    //     WIP_CMD_S  : send RDSR opcode (0x05)  -> TX only
    //     WIP_DATA_S : read status byte         -> RX only
    //   This keeps the command (TX) and status (RX) phases
    //   sequential, instead of asserting tx_start and rx_en
    //   at the same time.
    //---------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE_S, WE_CMD_S, CS_GAP1_S, WCMD_S, WADDR_S, WMODE_S,
        WDATA_S, CS_GAP2_S, WIP_CMD_S, WIP_DATA_S, RCMD_S, RADDR_S,
        RMODE_S, DUMMY_S, RDATA_S
    } state_t;

    state_t state, next_state;

    //---------------------------------------------------------
    // Internal signals
    //---------------------------------------------------------
    logic [2:0]  addr_byte_cnt;
    logic [2:0]  data_byte_cnt;
    logic [2:0]  tcs_cnt;
    logic [31:0] addr;
    logic [2:0]  waddr_byte_len, raddr_byte_len;
    logic [2:0]  wdata_byte_len, rdata_byte_len;

    localparam int TCS = 5;
    localparam int DUMMY_CYCLES = 4;

    //---------------------------------------------------------
    // Config extraction
    //---------------------------------------------------------
    assign addr           = {ctrl_reg_i.ADDR3, ctrl_reg_i.ADDR2,
                             ctrl_reg_i.ADDR1, ctrl_reg_i.ADDR0};
    assign waddr_byte_len = ctrl_reg_i.WADDR_CMD;
    assign wdata_byte_len = ctrl_reg_i.WDATA_CMD;
    assign raddr_byte_len = ctrl_reg_i.RADDR_CMD;
    assign rdata_byte_len = ctrl_reg_i.RDATA_CMD;

    //---------------------------------------------------------
    // State register
    //---------------------------------------------------------
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) state <= IDLE_S;
        else          state <= next_state;
    end

    logic [3:0] dummy_cnt;
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni)            dummy_cnt <= '0;
        else if (state == DUMMY_S) dummy_cnt <= dummy_cnt + 1;
        else                     dummy_cnt <= '0;
    end

    //---------------------------------------------------------
    // Address byte counter
    //---------------------------------------------------------
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni)
            addr_byte_cnt <= '0;
        else if (state == WADDR_S || state == RADDR_S) begin
            if (tx_done_i) addr_byte_cnt <= addr_byte_cnt + 1;
        end
        else
            addr_byte_cnt <= '0;
    end

    //---------------------------------------------------------
    // Data byte counter
    //---------------------------------------------------------
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni)
            data_byte_cnt <= '0;
        else if (state == WDATA_S) begin
            if (tx_done_i) data_byte_cnt <= data_byte_cnt + 1;
        end
        else if (state == RDATA_S) begin
            if (rx_done_i) data_byte_cnt <= data_byte_cnt + 1;
        end
        else
            data_byte_cnt <= '0;
    end

    //---------------------------------------------------------
    // CS-gap cycle counter
    //---------------------------------------------------------
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni)
            tcs_cnt <= '0;
        else if (state == CS_GAP1_S || state == CS_GAP2_S)
            tcs_cnt <= tcs_cnt + 1;
        else
            tcs_cnt <= '0;
    end

    //---------------------------------------------------------
    // Next-state logic
    //---------------------------------------------------------
    always_comb begin
        next_state = state;

        case (state)
            IDLE_S: begin
                if (start_i) begin
                    if (we_i && ctrl_reg_i.WE_CFG[2])
                        next_state = WE_CMD_S;
                    else if (!we_i)
                        next_state = RCMD_S;
                end
            end

            WE_CMD_S:  if (tx_done_i)          next_state = CS_GAP1_S;
            CS_GAP1_S: if (tcs_cnt == TCS - 1) next_state = WCMD_S;
            WCMD_S:    if (tx_done_i)          next_state = WADDR_S;

            WADDR_S: begin
                if (tx_done_i && (addr_byte_cnt == waddr_byte_len - 1)) begin
                    if (ctrl_reg_i.WMODE_CFG[2]) next_state = WMODE_S;
                    else                         next_state = WDATA_S;
                end
            end

            WMODE_S: if (tx_done_i) next_state = WDATA_S;

            WDATA_S: begin
                if (tx_done_i && (data_byte_cnt == wdata_byte_len - 1))
                    next_state = CS_GAP2_S;
            end

            CS_GAP2_S: if (tcs_cnt == TCS - 1) next_state = WIP_CMD_S;

            // WIP phase 1: send RDSR opcode (TX only)
            WIP_CMD_S: if (tx_done_i) next_state = WIP_DATA_S;

            // WIP phase 2: read status byte (RX only)
            WIP_DATA_S: begin
                if (rx_done_i) begin
                    if (rx_data_i[0]) next_state = CS_GAP2_S;  // busy: poll again
                    else              next_state = IDLE_S;     // done
                end
            end

            RCMD_S: if (tx_done_i) next_state = RADDR_S;

            RADDR_S: begin
                if (tx_done_i && (addr_byte_cnt == raddr_byte_len - 1)) begin
                    if (ctrl_reg_i.RMODE_CFG[2])  next_state = RMODE_S;
                    else if (dummy_i)             next_state = DUMMY_S;
                    else                          next_state = RDATA_S;
                end
            end

            RMODE_S: begin
                if (tx_done_i) begin
                    if (dummy_i) next_state = DUMMY_S;
                    else         next_state = RDATA_S;
                end
            end

            DUMMY_S: if (dummy_cnt == DUMMY_CYCLES - 1) next_state = RDATA_S;

            RDATA_S: begin
                if (rx_done_i && (data_byte_cnt == rdata_byte_len - 1))
                    next_state = IDLE_S;
            end

            default: next_state = IDLE_S;
        endcase
    end

    //---------------------------------------------------------
    // Output logic
    //---------------------------------------------------------
    always_comb begin
        busy_o         = 1'b1;
        sck_en_o       = 1'b0;
        tx_data_o      = 8'h00;
        tx_width_o     = 2'b00;
        tx_start_o     = 1'b0;
        rx_en_o        = 1'b0;
        rx_width_o     = 2'b00;
        tx_fifo_pop_o  = 1'b0;
        rx_fifo_push_o = 1'b0;
        rx_fifo_data_o = rx_data_i;
        cs_no          = 1'b1;

        case (state)
            IDLE_S: begin
                busy_o = 1'b0;
                cs_no  = 1'b1;
            end

            CS_GAP1_S,
            CS_GAP2_S: begin
                cs_no = 1'b1;
            end

            WE_CMD_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = ctrl_reg_i.WE_CMD;
                tx_width_o = ctrl_reg_i.WE_CFG[1:0];
                tx_start_o = 1'b1;
            end

            WCMD_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = ctrl_reg_i.WCMD_CMD;
                tx_width_o = ctrl_reg_i.WCMD_CFG[1:0];
                tx_start_o = 1'b1;
            end

            WADDR_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = addr[ (waddr_byte_len - 1 - addr_byte_cnt)*8 +: 8 ];
                tx_width_o = ctrl_reg_i.WADDR_CFG[1:0];
                tx_start_o = 1'b1;
            end

            WMODE_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = ctrl_reg_i.WMODE_CMD;
                tx_width_o = ctrl_reg_i.WMODE_CFG[1:0];
                tx_start_o = 1'b1;
            end

            WDATA_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = tx_fifo_data_i;
                tx_width_o = ctrl_reg_i.WDATA_CFG[1:0];
                tx_start_o = 1'b1;
                if (tx_done_i) tx_fifo_pop_o = 1'b1;
            end

            // WIP phase 1: send RDSR opcode only (TX)
            WIP_CMD_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = 8'h05;        // RDSR
                tx_width_o = 2'b00;        // single
                tx_start_o = 1'b1;
                // rx_en_o stays 0 here
            end

            // WIP phase 2: read status byte only (RX)
            WIP_DATA_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                rx_en_o    = 1'b1;         // capture status
                rx_width_o = 2'b00;        // single
                // tx_start_o stays 0 here
            end

            RCMD_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = ctrl_reg_i.RCMD_CMD;
                tx_width_o = ctrl_reg_i.RCMD_CFG[1:0];
                tx_start_o = 1'b1;
            end

            RADDR_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = addr[ (raddr_byte_len - 1 - addr_byte_cnt)*8 +: 8 ];
                tx_width_o = ctrl_reg_i.RADDR_CFG[1:0];
                tx_start_o = 1'b1;
            end

            RMODE_S: begin
                cs_no      = 1'b0;
                sck_en_o   = 1'b1;
                tx_data_o  = ctrl_reg_i.RMODE_CMD;
                tx_width_o = ctrl_reg_i.RMODE_CFG[1:0];
                tx_start_o = 1'b1;
            end

            DUMMY_S: begin
                cs_no    = 1'b0;
                sck_en_o = 1'b1;
            end

            RDATA_S: begin
                cs_no          = 1'b0;
                sck_en_o       = 1'b1;
                rx_en_o        = 1'b1;
                rx_width_o     = ctrl_reg_i.RDATA_CFG[1:0];
                rx_fifo_data_o = rx_data_i;
                if (rx_done_i) rx_fifo_push_o = 1'b1;
            end

            default: ;
        endcase
    end

endmodule
