module tx_unpacker (
    input  logic [2:0] cycle_i,
    input  logic [1:0] size_i,
    input  logic [7:0] data_i,
    output logic [3:0] data_o
);

  logic [3:0][2:0] data_o_sel;

  always_comb begin
    for (int i = 1; i < 4; i++) begin
      data_o_sel[i] = data_o_sel[0] + i;
    end
  end

  always_comb begin
    case (size_i)
      2'b00:   data_o_sel[0] = 7 - cycle_i;
      2'b01:   data_o_sel[0] = 6 - {cycle_i[1:0], 1'b0};
      default: data_o_sel[0] = 4 - {cycle_i[0], 2'b0};
    endcase
  end

  always_comb begin
    for (int i = 0; i < 4; i++) begin
      data_o[i] = data_i[data_o_sel[i]];
    end
  end

endmodule
