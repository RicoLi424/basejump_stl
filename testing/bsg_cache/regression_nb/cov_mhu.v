
`include "bsg_cache_nb.vh"

module cov_mhu
  import bsg_cache_nb_pkg::*;
  (
    input clk_i
    , input reset_i
    
    , input miss_state_e miss_state_r

    , input mhu_we_i
    , input mhu_activate_i
    , input sbuf_or_tbuf_chosen_way_found_i
    , input dma_done_i

    // for sanity check to make sure each of them is never high
    , input mshr_stm_miss_i
    , input store_tag_miss_op_i
    , input track_miss_i
    , input transmitter_store_tag_miss_fill_done_i
    
  );

  covergroup cg_start @ (negedge clk_i iff miss_state_r == START);

    coverpoint mhu_activate_i;
    coverpoint mhu_we_i;

    cross mhu_activate_i, mhu_we_i {
      illegal_bins both_high = 
        binsof(mhu_activate_i) intersect {1'b1} && 
        binsof(mhu_we_i) intersect {1'b1};
    }

  endgroup


  covergroup cg_send_fill_addr @ (negedge clk_i iff miss_state_r == SEND_REFILL_ADDR);
  
    coverpoint dma_done_i;
    coverpoint sbuf_or_tbuf_chosen_way_found_i;

    cross dma_done_i, sbuf_or_tbuf_chosen_way_found_i {
      ignore_bins not_done_and_chosen_way_found = 
        binsof(dma_done_i) intersect {1'b0} && 
        binsof(sbuf_or_tbuf_chosen_way_found_i) intersect {1'b1};
    }

  endgroup

  covergroup cg_wait_snoop @ (negedge clk_i iff miss_state_r == WAIT_SNOOP_DONE);
  
    coverpoint sbuf_or_tbuf_chosen_way_found_i;

  endgroup


  covergroup cg_evict_refill @ (negedge clk_i iff (miss_state_r == SEND_EVICT_ADDR) || (miss_state_r == SEND_EVICT_DATA) || (miss_state_r == WRITE_FILL_DATA));
  
    coverpoint dma_done_i;

  endgroup

  covergroup no_word_tracking @ (negedge clk_i);
  
    coverpoint mshr_stm_miss_i;
    coverpoint store_tag_miss_op_i;
    coverpoint track_miss_i;
    coverpoint transmitter_store_tag_miss_fill_done_i;

    cross mshr_stm_miss_i, store_tag_miss_op_i, track_miss_i, transmitter_store_tag_miss_fill_done_i {
      illegal_bins anyone_high = 
        binsof(mshr_stm_miss_i) intersect {1'b1} || 
        binsof(store_tag_miss_op_i) intersect {1'b1} ||
        binsof(track_miss_i) intersect {1'b1} ||
        binsof(transmitter_store_tag_miss_fill_done_i) intersect {1'b1};
    }    

  endgroup


  initial begin
    cg_start cs = new;
    cg_send_fill_addr csfa = new;
    cg_wait_snoop cws = new;
    cg_evict_refill cer = new;
    no_word_tracking nwt = new;
  end

endmodule
