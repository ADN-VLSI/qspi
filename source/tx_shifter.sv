module tx_shifter (
    // ── clock & reset ──
    input  logic        clk_i,
    input  logic        arst_ni,

    // ── from FSM (control) ──
    input  logic        tx_start_i,    // start shifting
    input  logic [7:0]  tx_data_i,     // byte to send
    input  logic [1:0]  tx_width_i,    // 00=single 01=dual 10=quad
    output logic        tx_done_o,     // one byte fully shifted out

    // ── SCK timing ──
    input  logic        sck_pulse_i,   // "shift now" pulse (one per SCK bit period)

    // ── to flash IO ──
    output logic [3:0]  io_o,          // data bits on IO0-IO3
    output logic [3:0]  io_oe_o        // output enable per IO line
);

logic [2:0] cyc_cnt;
logic [7:0] shift_reg;
logic       shifting;
logic [2:0] cnt;
logic [2:0] shift_amt;

logic tx_start_d;
wire tx_start_pulse = tx_start_i && !tx_start_d;

always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
        cyc_cnt   <= '0;
        shift_reg <= '0;
        tx_done_o <= '0;
        io_o      <= '0;
        shifting  <= '0;
        tx_start_d <= 1'b0;
    end
    else begin
        tx_done_o <= 1'b0;                   // default low
        tx_start_d <= tx_start_i;

        if (tx_start_i && !shifting) begin
            shift_reg <= tx_data_i;
            shifting  <= 1'b1;
            cyc_cnt   <= '0;
        end
        else if (shifting && (sck_pulse_i)) begin
            case (tx_width_i)
                2'b00: io_o[0]   <= shift_reg[7];
                2'b01: io_o[1:0] <= shift_reg[7:6];
                2'b10: io_o[3:0] <= shift_reg[7:4];
            endcase
            shift_reg <= shift_reg << shift_amt;
            if (cyc_cnt == cnt) begin
                shifting  <= 1'b0;
                tx_done_o <= 1'b1;
                cyc_cnt   <= '0;
            end else begin
                cyc_cnt <= cyc_cnt + 1;
            end
        end
    end
end

always_comb begin
    case (tx_width_i)
        2'b00: begin cnt = 3'd7; shift_amt = 3'd1; end
        2'b01: begin cnt = 3'd3; shift_amt = 3'd2; end
        2'b10: begin cnt = 3'd1; shift_amt = 3'd4; end
        default: begin cnt = 3'd7; shift_amt = 3'd1; end
    endcase
end

// io_oe combinational
always_comb begin
    if (shifting) begin
        case (tx_width_i)
            2'b00: io_oe_o = 4'b0001;
            2'b01: io_oe_o = 4'b0011;
            2'b10: io_oe_o = 4'b1111;
            default: io_oe_o = 4'b0001;
        endcase
    end else begin
        io_oe_o = 4'b0000;
    end
end
endmodule
 