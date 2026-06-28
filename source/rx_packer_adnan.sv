module rx_packer (
    // ── clock & reset ──
    input  logic        clk_i,
    input  logic        arst_ni,

    // ── from FSM (control) ──
    input  logic        rx_en_i,       // start capturing (FSM asserts during read data phase)
    input  logic [1:0]  rx_width_i,    // 00=single 01=dual 10=quad
    output logic [7:0]  rx_data_o,     // assembled byte
    output logic        rx_done_o,     // one byte fully received

    // ── SCK timing ──
    input  logic        sck_pulse_i,   // "capture now" pulse (one per SCK bit period)

    // ── from flash IO ──
    input  logic [3:0]  io_i           // data bits coming in on IO0-IO3
);

logic [2:0] cyc_cnt;
logic [7:0] shift_reg;
logic       shifting;
logic [2:0] cnt;

logic rx_start_d;
wire rx_start_pulse = rx_en_i && !rx_start_d;

always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
        cyc_cnt   <= '0;
        shift_reg <= '0;
        rx_done_o <= '0;
        shifting  <= '0;
        rx_start_d <= 1'b0;
    end else begin
        rx_done_o <= 1'b0;                   // default low
        rx_start_d <= rx_en_i;
        if (rx_en_i && !shifting) begin
            shift_reg <= '0;
            shifting  <= 1'b1;
            cyc_cnt   <= '0;
        end
        else if (shifting && (sck_pulse_i)) begin
            case(rx_width_i)
                2'b00: shift_reg <= {shift_reg[6:0], io_i[1]};
                2'b01: shift_reg <= {shift_reg[5:0], io_i[1:0]};
                2'b10: shift_reg <= {shift_reg[3:0], io_i[3:0]};
                default:shift_reg <= {shift_reg[6:0],io_i[1]};
            endcase
            if (cyc_cnt == cnt) begin
                shifting  <= 1'b0;
                rx_done_o <= 1'b1;
                cyc_cnt   <= '0;
            case(rx_width_i)
                2'b00: rx_data_o <= {shift_reg[6:0], io_i[1]};
                2'b01: rx_data_o <= {shift_reg[5:0], io_i[1:0]};
                2'b10: rx_data_o <= {shift_reg[3:0], io_i[3:0]};
                default:rx_data_o <= {shift_reg[6:0],io_i[1]};
            endcase

            end else cyc_cnt <= cyc_cnt + 1;
        end

 
    end
end



always_comb begin
    case (rx_width_i)
        2'b00: begin cnt = 3'd7; end
        2'b01: begin cnt = 3'd3; end
        2'b10: begin cnt = 3'd1; end
        default: begin cnt = 3'd7; end
    endcase
end
endmodule 