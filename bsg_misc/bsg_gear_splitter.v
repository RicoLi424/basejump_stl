// Cross splice two inputs to be two outputs
// This is different to gear combinator in that the two inputs
// are in order but we want to split and recombine them to be 
// two different outputs which one is of elements with even indices
// while the other is of elements with odd indices.
//
// e.g.   input0: 3 2 1 0   / output0: 6 4 2 0  
//                        -- 
//        input1: 7 6 5 4   \ output1: 7 5 3 1
//

`include "bsg_defines.v"

module bsg_gear_splitter
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
        for (genvar i = 0; i < els_p/2; i++) begin: COMBINE
            assign data0_o[width_p*i +: width_p] = data0_i[width_p*(2*i) +: width_p];
            assign data0_o[width_p*(els_p/2 + i) +: width_p] = data1_i[width_p*(2*i) +: width_p];

            assign data1_o[width_p*i +: width_p] = data0_i[width_p*(2*i+1) +: width_p];
            assign data1_o[width_p*(els_p/2 + i) +: width_p] = data1_i[width_p*(2*i+1) +: width_p];
        end  
    end
endmodule

`BSG_ABSTRACT_MODULE(bsg_gear_splitter)