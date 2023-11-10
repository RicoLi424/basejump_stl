`include "bsg_defines.v"
`include "bsg_cache_nb.vh"

module cov_mgmt
  import bsg_cache_nb_pkg::*;
  #(
    parameter `BSG_INV_PARAM(ways_p)
    , parameter stat_info_width_lp=`bsg_cache_nb_stat_info_width(ways_p)
    , parameter lg_ways_lp=`BSG_SAFE_CLOG2(ways_p)
  )
  (
    input clk_i
    , input reset_i
    
    , input bsg_cache_nb_decode_s decode_v_i

    , input mgmt_v_i
    , input sbuf_empty_i
    , input tbuf_empty_i
    , input mgmt_unit_boot_up

    , input dma_done_i
    , input ack_i

    , input [stat_info_width_lp-1:0] stat_info_i
    , input [ways_p-1:0] valid_v_i

    , input mgmt_miss_state_e miss_state_r

    , input goto_flush_op
    , input goto_lock_op

    , input [lg_ways_lp-1:0] chosen_way_n
    , input [lg_ways_lp-1:0] flush_way_n

  );

  `declare_bsg_cache_nb_stat_info_s(ways_p);
  bsg_cache_nb_stat_info_s stat_info_in;
  assign stat_info_in = stat_info_i;

  wire stat_dirty_chosen = stat_info_in.dirty[chosen_way_n];
  wire tag_valid_chosen = valid_v_i[chosen_way_n];
  wire stat_dirty_flush = stat_info_in.dirty[flush_way_n];
  wire tag_valid_flush = valid_v_i[flush_way_n];
  wire decode_ainv = decode_v_i.ainv_op;
  wire decode_tagfl = decode_v_i.tagfl_op;
  wire decode_aflinv = decode_v_i.aflinv_op;
  wire decode_afl = decode_v_i.afl_op;

  covergroup cg_n_mgmt_boot_up @ (negedge clk_i iff ~mgmt_unit_boot_up);

    coverpoint sbuf_empty_i;
    coverpoint tbuf_empty_i {
      bins one = {1'b1};
      illegal_bins zero = {1'b0};
    }
    coverpoint mgmt_v_i;

    cross mgmt_v_i, sbuf_empty_i {
      illegal_bins both_one = 
        binsof(mgmt_v_i) intersect {1'b1} &&
        binsof(sbuf_empty_i) intersect {1'b1};
    }

  endgroup


  covergroup cg_start @ (negedge clk_i iff miss_state_r==MGMT_START);

    coverpoint mgmt_unit_boot_up;
    coverpoint goto_flush_op;
    coverpoint goto_lock_op;

    cross mgmt_unit_boot_up, goto_flush_op, goto_lock_op {
      illegal_bins flush_lock = 
        binsof(goto_flush_op) intersect {1'b1} &&
        binsof(goto_lock_op) intersect {1'b1};
    }

  endgroup 


  covergroup cg_send_fill_addr @ (negedge clk_i iff miss_state_r==MGMT_SEND_FILL_ADDR);

    coverpoint dma_done_i;
    coverpoint stat_dirty_chosen;
    coverpoint tag_valid_chosen;

    cross dma_done_i, stat_dirty_chosen, tag_valid_chosen {
      ignore_bins ig0 =
        binsof(tag_valid_chosen) intersect {1'b0} &&
        binsof(stat_dirty_chosen) intersect {1'b1};
    }

  endgroup


  covergroup cg_flush @ (negedge clk_i iff miss_state_r==MGMT_FLUSH_OP);

    coverpoint decode_ainv;
    coverpoint stat_dirty_flush;
    coverpoint tag_valid_flush {
      bins valid = {1'b1};
      illegal_bins n_valid = {1'b0};
    } // valid has to be 1 to go into mgmt unit and this state

    cross decode_ainv, stat_dirty_flush, tag_valid_flush;

  endgroup


  covergroup cg_send_evict_addr @ (negedge clk_i iff ((miss_state_r==MGMT_SEND_EVICT_ADDR) || (miss_state_r==MGMT_GET_FILL_DATA)));

    coverpoint dma_done_i;

  endgroup


  covergroup cg_send_evict_data @ (negedge clk_i iff miss_state_r==MGMT_SEND_EVICT_DATA);

    coverpoint dma_done_i;
    coverpoint decode_tagfl;
    coverpoint decode_aflinv;
    coverpoint decode_afl;

    cross dma_done_i, decode_tagfl, decode_aflinv, decode_afl {
      illegal_bins op_conflict =
        binsof(decode_tagfl) intersect {1'b1} &&
        (binsof(decode_aflinv) intersect {1'b1} ||
         binsof(decode_afl) intersect {1'b1}) ||
         
         (binsof(decode_aflinv) intersect {1'b1} &&
         binsof(decode_afl) intersect {1'b1});
    }

  endgroup


  covergroup cg_done @ (negedge clk_i iff miss_state_r==MGMT_DONE);

    coverpoint ack_i;

  endgroup


  initial begin
    cg_n_mgmt_boot_up cnmbu = new;
    cg_start cs = new;
    cg_send_fill_addr csfa = new;
    cg_flush cf = new;
    cg_send_evict_addr csea = new;
    cg_send_evict_data csed = new;
    cg_done cd = new;
  end


endmodule
