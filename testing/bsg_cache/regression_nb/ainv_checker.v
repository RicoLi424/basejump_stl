module ainv_checker
  #(parameter `BSG_INV_PARAM(word_width_p)
  , parameter `BSG_INV_PARAM(src_id_width_p))
  (
    input clk_i
    , input reset_i

    , input en_i
  
    , input [word_width_p-1:0] data_o
    , input [src_id_width_p-1:0] src_id_o
    , input v_o
    , input yumi_i
  );


  // ainv test is setup in such way that it should only return zero.

  always_ff @ (posedge clk_i) begin
    
    if (~reset_i & en_i & v_o & (src_id_o!=0) & yumi_i) begin
      $display("src_id_o=%d, data_o=%x", src_id_o, data_o); 
      assert(data_o == '0)
        else $fatal(1, "zero output expected.");
    end

  end

endmodule

`BSG_ABSTRACT_MODULE(ainv_checker)
