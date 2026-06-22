import qspi_pkg::*;

module qspi_fsm (
    //=========================================================
    // Clock and Reset
    //=========================================================
    input  logic              clk_i,             // system clock
    input  logic             arst_ni,            // active-low reset

    //=========================================================
    // Control interface (from top / CPU side)
    //=========================================================
    input  logic              start_i,           // start a transaction (top asserts when fifo_count >= threshold)
    input  logic              we_i,              // 1 = write transaction, 0 = read transaction
    output logic              busy_o,            // high while FSM is running a transaction

    input logic               dummy_i;
    //=========================================================
    // Configuration (from register file)
    //=========================================================
    input  qspi_control_reg_t ctrl_reg_i,        // full register struct: opcodes, cfg, addr, counts

    //=========================================================
    // SCK generator control
    //=========================================================
    output logic              sck_en_o,          // enable serial clock generation during active phases

    //=========================================================
    // TX shifter interface
    //=========================================================
    output logic [7:0]        tx_data_o,         // byte to send (muxed: register byte or FIFO byte)
    output logic [1:0]        tx_width_o,        // 00 = single, 01 = dual, 10 = quad
    output logic              tx_start_o,        // pulse: start shifting tx_data out
    input  logic              tx_done_i,         // shifter asserts when one byte has been fully sent

    //=========================================================
    // RX unpacker interface
    //=========================================================
    output logic              rx_en_o,           // enable capture during read data phase
    output logic [1:0]        rx_width_o,        // 00 = single, 01 = dual, 10 = quad
    input  logic [7:0]        rx_data_i,         // byte assembled by the unpacker
    input  logic              rx_done_i,         // unpacker asserts when one byte has been received

    //=========================================================
    // TX FIFO interface (data source for the DATA phase)
    //=========================================================
    output logic              tx_fifo_pop_o,     // pop one byte from TX FIFO
    input  logic [7:0]        tx_fifo_data_i,    // current byte at TX FIFO output
    input  logic              tx_fifo_empty_i,   // high when TX FIFO has no data

    //=========================================================
    // RX FIFO interface (data sink for read data)
    //=========================================================
    output logic              rx_fifo_push_o,    // push one received byte into RX FIFO
    output logic [7:0]        rx_fifo_data_o,    // byte to push (comes from rx_data_i)
    input  logic              rx_fifo_full_i,    // high when RX FIFO cannot accept more

    //=========================================================
    // Flash chip select
    //=========================================================
    output logic              cs_no,             // chip select to flash, active low

    //=========================================================
    // WIP (Write In Progress) status, from RDSR polling
    //=========================================================
    input  logic              wip_bit_i          // 1 = flash still busy writing, 0 = free
);

    // ----- internal signals, state, counters go here -----





        // ── state declaration ──
    typedef enum logic [3:0] {
        IDLE_S,
        WE_CMD_S,
        CS_GAP1_S,
        WCMD_S,
        WADDR_S,
        WMODE_S,
        WDATA_S,
        CS_GAP2_S,
        WIP_S,
        RCMD_S,
        RADDR_S,
        RMODE_S,
        DUMMY_S,
        RDATA_S
    } state_t;

    state_t state, next_state;

    logic [2:0] addr_byte_cnt;
    logic [2:0] waddr_byte_len;
    logic [31:0] addr;
    logic [2:0] data_byte_cnt, wdata_byte_len, rdata_byte_len, raddr_byte_len;

    always_ff @(posedge clk_i or negedge arst_ni) begin
        if(!arst_ni) begin
            state <= IDLE_S;
            addr_byte_cnt <= '0;
            addr <= {ctrl_reg_i.ADDR0, ctrl_reg_i.ADDR1, ctrl_reg_i.ADDR2, ctrl_reg_i.ADDR3};
            waddr_byte_len <= ctrl_reg_i.WADDR_CMD;
            wdata_byte_len <= ctrl_reg_i.WDATA_CMD;
            raddr_byte_len <= ctrl_reg_i.RADDR_CMD;
            rdata_byte_len <= ctrl_reg_i.RDATA_CMD;


        end else begin 
            state <= next_state;

            case(state)
                ADDR_S: begin
                    if() 
                end



            endcase
        end 
    end


    always_ff (posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) addr_byte_cnt <= '0;
        else 
    end

    // NEXT STATE COMBINATIONAL
    always_comb begin
        case(state) 
            IDLE_S: begin 
                if(start) begin
                    if(we_i && ctrl_reg_i.WE_CFG[2]== 1'b1) begin
                        next_state = WE_CMD_S;
                    end else if(!we_i) next_state = RCMD_S;
                else next_state = IDLE_S;    
                    end
                end
            WE_CMD_S: begin
                if(tx_done_i) next_state = CS_GAP1_S;
            end
            
            CS_GAP1_S: if(tcs == cs_cnt - 1) next_state = WCMD_S;
            WCMD_S: if(tx_done_i) next_state <= WAADR_S;
            WADDR_S: if(addr_byte_cnt == (waddr_byte_len - 1)) begin
                if(ctrl_reg_i.WMODE_CFG[2]) begin
                    next_state = WMODE_S;
                end else next_state = WDATA_S;
            end
            WDATA_S: begin
                if(data_byte_cnt == (wdata_byte_len - 1)) next_state <= CS_GAP2_S;
            end
            CS_GAP2_S: begin 
                if((tcs == cs_cnt - 1)) next_state = WIP_S;
            end
            WIP_S: begin
                if(rx_done_i && rx_data_i[0] == 1) begin 
                    next_state = WIP;
                end else next_state = IDLE_S; 
            end
            RCMD_S: if (tx_done_i) next_state = RADDR_S;
            RADDRS: begin 
                if(addr_byte_cnt == (raddr_byte_len - 1)) begin
                    if(ctrl_reg_i.WMODE_CFG[2]) begin
                        next_state = RMODE_S;
                    end else if (dummy_i) next_state = DUMMY_S;
                    else next_state = RDATA_S;
                end
            end
            DUMMY_S: if(tx_done_i) begin 
                next_state = RDATA_S;
            end
            RDATA_S: if((data_byte_cnt == (rdata_byte_len - 1)) && rx_done_i) next_state <= IDLE_S;
            

        endcase
    end



endmodule