// Cross splice two inputs to be two outputs
// This could be especially useful if two inputs were originally 
// parts of a single sequence, and one is of elements with even indices
// while the other is of elements with odd indices.
//
// e.g.   input0: A C E G   / output0: A B C D 
//                        -- 
//        input1: B D F H   \ output1: E F G H 
//

`include "bsg_defines.v"

module bsg_gear_combinator
    #( parameter `BSG_INV_PARAM(width_p), 
       parameter `BSG_INV_PARAM(els_p),

       parameter safe_els_lp = `BSG_MAX(els_p,1)
     )
     (
       input [width_p*safe_els_lp-1:0] data0_i, 
       input [width_p*safe_els_lp-1:0] data1_i,
       output logic [width_p*safe_els_lp-1:0] data0_o,
       output logic [width_p*safe_els_lp-1:0] data1_o    
     );
    
    if(safe_els_lp==1) begin: one
        assign data0_o = data0_i;
        assign data1_o = data1_i;
    end else begin: not_one
      for (genvar i = 0; i < safe_els_lp; i++) begin: COMBINE
        assign data1_o[width_p*i +: width_p] = 
              (i%2) ? data0_i[width_p*(i/2) +: width_p] 
              : data1_i[width_p*(i/2) +: width_p];

        assign data0_o[width_p*i +: width_p] = 
              (i%2) ? data0_i[width_p*(safe_els_lp/2 + i/2) +: width_p] 
              : data1_i[width_p*(safe_els_lp/2 + i/2) +: width_p];
        end  
    end
endmodule

`BSG_ABSTRACT_MODULE(bsg_gear_combinator)