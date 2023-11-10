
`include "bsg_cache_nb.vh"

module cov_mhu
  import bsg_cache_nb_pkg::*;
  #(parameter `BSG_INV_PARAM(ways_p)
    ,parameter stat_info_width_lp=`bsg_cache_nb_stat_info_width(ways_p)
    ,parameter lg_ways_lp=`BSG_SAFE_CLOG2(ways_p)
  )
  (
    input clk_i
    , input reset_i
    
    , input mhu_miss_state_e miss_state_r

    , input [stat_info_width_lp-1:0] stat_info_r
    , input [ways_p-1:0] valid_v_r
    , input [lg_ways_lp-1:0] chosen_way_r

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

  `declare_bsg_cache_nb_stat_info_s(ways_p);
  bsg_cache_nb_stat_info_s stat_info;
  assign stat_info = stat_info_r;

  wire chosen_way_dirty = stat_info.dirty[chosen_way_r];
  wire chosen_way_valid = valid_v_r[chosen_way_r];

  covergroup cg_start @ (negedge clk_i iff miss_state_r == MHU_START);

    coverpoint mhu_activate_i;
    coverpoint mhu_we_i;

    cross mhu_activate_i, mhu_we_i {
      illegal_bins both_high = 
        binsof(mhu_activate_i) intersect {1'b1} && 
        binsof(mhu_we_i) intersect {1'b1};
    }

  endgroup


  covergroup cg_send_fill_addr @ (negedge clk_i iff miss_state_r == MHU_SEND_REFILL_ADDR);
  
    coverpoint dma_done_i;
    coverpoint sbuf_or_tbuf_chosen_way_found_i;
    coverpoint chosen_way_dirty;
    coverpoint chosen_way_valid;

    cross dma_done_i, sbuf_or_tbuf_chosen_way_found_i, chosen_way_dirty, chosen_way_valid {
      ignore_bins not_done_and_chosen_way_found = 
        binsof(dma_done_i) intersect {1'b0} && 
        binsof(sbuf_or_tbuf_chosen_way_found_i) intersect {1'b1};

      ignore_bins dirty_n_valid = 
        binsof(chosen_way_dirty) intersect {1'b1} && 
        binsof(chosen_way_valid) intersect {1'b0};

      illegal_bins sbuf_found_but_n_v_or_n_dirty = 
        binsof(sbuf_or_tbuf_chosen_way_found_i) intersect {1'b1} && 
        (binsof(chosen_way_valid) intersect {1'b0} || 
         binsof(chosen_way_dirty) intersect {1'b0});
    }

  endgroup

  covergroup cg_wait_snoop @ (negedge clk_i iff miss_state_r == MHU_WAIT_SNOOP_DONE);
  
    coverpoint sbuf_or_tbuf_chosen_way_found_i;

  endgroup


  covergroup cg_evict_refill @ (negedge clk_i iff (miss_state_r == MHU_SEND_EVICT_ADDR) || (miss_state_r == MHU_SEND_EVICT_DATA) || (miss_state_r == MHU_WRITE_FILL_DATA));
  
    coverpoint dma_done_i;

  endgroup

  covergroup no_word_tracking @ (negedge clk_i);
  
    coverpoint mshr_stm_miss_i {
      bins z0 = {1'b0};
      illegal_bins nz0 = {1'b1};
    }
    coverpoint store_tag_miss_op_i {
      bins z1 = {1'b0};
      illegal_bins nz1 = {1'b1};
    }
    coverpoint track_miss_i {
      bins z2 = {1'b0};
      illegal_bins nz2 = {1'b1};
    }
    coverpoint transmitter_store_tag_miss_fill_done_i {
      bins z3 = {1'b0};
      illegal_bins nz3 = {1'b1};
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
