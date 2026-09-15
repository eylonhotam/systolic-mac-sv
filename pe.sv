module pe #(parameter A_W = 8, W_W = 8, P_W = 32) (
  input  logic                    clk, rst_n,
  input  logic                    w_shift_en, // 1 is load, 0 compute
  input  logic signed [W_W-1:0]   w_in,       // from PE above
  output logic signed [W_W-1:0]   w_out,      // to PE below
  input  logic signed [A_W-1:0]   a_in,       // from PE left
  output logic signed [A_W-1:0]   a_out,      // to PE right
  input  logic signed [P_W-1:0]   psum_in,    // from PE above
  output logic signed [P_W-1:0]   psum_out    // to PE below
);
  
  logic signed [W_W-1:0] w_reg;               // weights register
  logic signed [P_W-1:0] prod; 				        // product intermediate for multiplication
  
  assign prod = a_in * w_reg;
  
  always_ff @(posedge clk) begin
    if(!rst_n) begin 
      a_out <= 0;
      psum_out <= 0;
      w_reg <= 0;
    end else begin
      a_out <= a_in; 
      psum_out <= psum_in + prod;
   
      if(w_shift_en) begin 
        w_out <= w_reg;
        w_reg <= w_in;
      end
    end
  end
endmodule
