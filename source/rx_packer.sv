module rx_packer (
    input logic clk_i,
    input logic arst_ni,
    input  logic [2:0] cycle_i,   
    input  logic [1:0] size_i,    
    input  logic [3:0] data_i,     
    output logic [7:0] data_o,    
    output logic       valid_o    
);

  logic [7:0] shift_reg;
  logic [2:0] last_cycle;

  always_comb begin
    case (size_i)
      2'b00: last_cycle   = 3'b111; //standard
      2'b01: last_cycle   = 3'b011; //dual
      default: last_cycle = 3'b01;  //quad
    endcase
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      shift_reg <= 8'b0;
      data_o    <= 8'b0;
      valid_o   <= 0;
    end
    else begin 
        valid_o <= 0;
    case (size_i)
      2'b00:  begin
              shift_reg[7-cycle_i] <= data_i[0];
             end
      2'b01:  begin
                shift_reg[7 - 2*cycle_i[1:0]]     <= data_i[1];
                shift_reg[7 - 2*cycle_i[1:0] - 1] <= data_i[0];
             end
      default:  begin
                shift_reg[7 - 4*cycle_i[0]]       <= data_i[3];
                shift_reg[7 - 4*cycle_i[0] - 1]   <= data_i[2];
                shift_reg[7 - 4*cycle_i[0] - 2]   <= data_i[1];
                shift_reg[7 - 4*cycle_i[0] - 3]   <= data_i[0];
               end
    endcase
    if (cycle_i == last_cycle) begin
          data_o  <= shift_reg;
          valid_o <= 1'b1;
        end
  end
end
endmodule
