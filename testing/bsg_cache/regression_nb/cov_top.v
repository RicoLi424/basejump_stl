`include "bsg_cache_nb.vh"

module cov_top 
  import bsg_cache_nb_pkg::*;
  #(
    parameter `BSG_INV_PARAM(mshr_els_p)
  )
  (
    input clk_i
    , input reset_i

    , input dma_data_mem_pkt_v_lo
    , input mhu_data_mem_pkt_v_lo
    , input v_i
    , input v_o
    , input yumi_o
    , input yumi_i

    , input tl_we
    , input v_tl_r
    , input v_we
    , input v_v_r

    , input dma_data_v_i
    , input dma_data_ready_o
    , input dma_data_v_o
    , input dma_data_yumi_i

    , input bsg_cache_nb_decode_s decode_v_r

    , input mgmt_v

    , input ld_miss_v
    , input ld_found_in_mshr_output_ld_data_v
    , input ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_v
    , input ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_and_sbuf_bypass
    , input ld_found_in_mshr_and_hit_in_track_data_v
    , input ld_found_in_mshr_output_mshr_data_v
    , input ld_found_in_mshr_alloc_read_miss_entry_v

    , input st_miss_v
    , input st_found_in_mshr_update_mshr_v
    , input st_found_in_mshr_update_sbuf_and_tbuf_v

    , input [mshr_els_p-1:0] mshr_cam_w_v_li
    , input mshr_clear
    , input alloc_write_tag_and_stat_v
    , input st_found_in_mshr_update_mshr_v

    , input read_miss_queue_v_li
    , input dma_serve_read_miss_queue_v_lo

    , input alloc_mshr_state_e alloc_mshr_state_r
    , input mshr_entry_alloc_ready
    , input way_chooser_no_available_way_lo
    , input alloc_done_v
    , input alloc_in_progress_v
    , input dma_mshr_cam_r_v_lo

    , input mgmt_recover_lo
    , input alloc_recover_v

    , input serve_read_queue_output_occupied
    , input alloc_read_miss_entry_but_no_empty
    , input st_found_in_mshr_dma_hit_but_not_written_to_dmem_yet

    , input tag_op_tl
    , input [mshr_els_lp-1:0] mshr_cam_w_empty_lo

    , input dma_refill_hold_li
    , input alloc_no_available_way_v
    , input st_found_in_mshr_update_mshr_v

    , input sbuf_hazard
    , input tl_ready
    , input tl_recover
    , input bsg_cache_nb_decode_s decode
    , input even_bank_conflict
    , input odd_bank_conflict
   
  );


  wire decode_tagst_op = decode.tagst_op;
  wire decode_atomic_op = decode.atomic_op;

  covergroup cg_tl_recover @ (posedge clk_i iff ~reset_i);

    coverpoint mgmt_recover_lo;
    coverpoint alloc_recover_v;
    cross mgmt_recover_lo, alloc_recover_v {
      illegal_bins rec_both_high = 
        binsof(mgmt_recover_lo) intersect {1'b1} &&
        binsof(alloc_recover_v) intersect {1'b1};
    }

  endgroup

  covergroup cg_dma_in_out @ (negedge clk_i);  

    coverpoint dma_data_v_i;
    coverpoint dma_data_ready_o;
    coverpoint dma_data_v_o;
    coverpoint dma_data_yumi_i;

    cross dma_data_v_i, dma_data_ready_o, dma_data_v_o, dma_data_yumi_i {
      ignore_bins dma_n_v_o = 
        binsof(dma_data_v_o) intersect {1'b0} &&
        binsof(dma_data_yumi_i) intersect {1'b1};
    }

  endgroup 


  covergroup cg_tl_tv_state @ (negedge clk_i iff ~reset_i); 

    coverpoint tl_we;
    coverpoint v_tl_r;
    coverpoint v_we;
    coverpoint v_v_r;

    cross tl_we, v_tl_r, v_we, v_v_r;

  endgroup 


  covergroup cg_n_v_o @ (negedge clk_i iff ~v_o & ~dma_serve_read_miss_queue_v_lo & v_v_r & ~mgmt_v);

    coverpoint alloc_read_miss_entry_but_no_empty;
    coverpoint st_found_in_mshr_dma_hit_but_not_written_to_dmem_yet;
    coverpoint dma_mshr_cam_r_v_lo;
    coverpoint ld_miss_v;
    coverpoint st_miss_v;
    coverpoint alloc_done_v;

    cross ld_miss_v, st_miss_v, alloc_done_v, dma_mshr_cam_r_v_lo, alloc_read_miss_entry_but_no_empty, st_found_in_mshr_dma_hit_but_not_written_to_dmem_yet {
      illegal_bins ld_st = 
        (binsof(ld_miss_v) intersect {1'b1} ||
        binsof(alloc_read_miss_entry_but_no_empty) intersect {1'b1}) &&
        (binsof(st_miss_v) intersect {1'b1} ||
        binsof(st_found_in_mshr_dma_hit_but_not_written_to_dmem_yet) intersect {1'b1});

      illegal_bins ld_ld = 
        binsof(alloc_read_miss_entry_but_no_empty) intersect {1'b1} &&
        binsof(ld_miss_v) intersect {1'b1};

      illegal_bins st_st = 
        binsof(st_found_in_mshr_dma_hit_but_not_written_to_dmem_yet) intersect {1'b1} &&
        binsof(st_miss_v) intersect {1'b1};

      illegal_bins v_o0 =
        (binsof(ld_miss_v) intersect {1'b1} ||
        binsof(st_miss_v) intersect {1'b1}) &&
        binsof(alloc_done_v) intersect {1'b1};

      illegal_bins v_o1 = 
        binsof(ld_miss_v) intersect {1'b0} &&
        binsof(st_miss_v) intersect {1'b0} &&
        binsof(alloc_read_miss_entry_but_no_empty) intersect {1'b0} &&
        binsof(st_found_in_mshr_dma_hit_but_not_written_to_dmem_yet) intersect {1'b0} &&
        binsof(dma_mshr_cam_r_v_lo) intersect {1'b0};
    }

  endgroup 


  covergroup cd_n_tl_ready @(negedge clk_i iff ~tl_ready);

    coverpoint sbuf_hazard;
    coverpoint tl_recover;
    coverpoint decode_tagst_op;
    coverpoint decode_atomic_op;
    coverpoint mgmt_v;
    coverpoint ld_miss_v;
    coverpoint st_miss_v;
    coverpoint even_bank_conflict;
    coverpoint odd_bank_conflict;

    cross sbuf_hazard, tl_recover, decode_tagst_op, decode_atomic_op, mgmt_v, ld_miss_v, st_miss_v, even_bank_conflict, odd_bank_conflict {
      illegal_bins ld_st_mgmt = 
        binsof(mgmt_v) intersect {1'b1} &&
        (binsof(ld_miss_v) intersect {1'b1} ||
        binsof(st_miss_v) intersect {1'b1}) ||
        
        binsof(ld_miss_v) intersect {1'b1} &&
        binsof(st_miss_v) intersect {1'b1};

      illegal_bins odd_even = 
        binsof(even_bank_conflict) intersect {1'b1} &&
        binsof(odd_bank_conflict) intersect {1'b1};

      illegal_bins tagst_atom =
        binsof(decode_tagst_op) intersect {1'b1} &&
        binsof(decode_atomic_op) intersect {1'b1};

      illegal_bins n_recover = 
        binsof(tl_recover) intersect {1'b1} &&
        binsof(mgmt_v) intersect {1'b0} &&
        binsof(ld_miss_v) intersect {1'b0} &&
        binsof(st_miss_v) intersect {1'b0};

      illegal_bins hazard_sbuf =
        binsof(sbuf_hazard) intersect {1'b1} &&
        (binsof(decode_tagst_op) intersect {1'b1} ||
        binsof(mgmt_v) intersect {1'b1} ||
        binsof(ld_miss_v) intersect {1'b1} ||
        binsof(st_miss_v) intersect {1'b1} ||
        binsof(tl_recover) intersect {1'b1});

      illegal_bins bank_conflict = 
        (binsof(even_bank_conflict) intersect {1'b1} ||
        binsof(odd_bank_conflict) intersect {1'b1}) &&
        (binsof(decode_tagst_op) intersect {1'b1} ||
        binsof(decode_atomic_op) intersect {1'b1} ||
        binsof(mgmt_v) intersect {1'b1});

    }

  endgroup


  covergroup cg_v_we @ (negedge clk_i iff ~reset_i);

  coverpoint v_tl_r;
  coverpoint tag_op_tl;
  coverpoint mshr_cam_w_empty_lo {
    bins all_empty = {'0};
    bins at_least_one_not_empty = {[(1 << mshr_els_p) - 1:1]};
  }
  coverpoint v_v_r;
  coverpoint v_o;
  coverpoint yumi_i;
  coverpoint serve_read_queue_output_occupied;
  coverpoint dma_serve_read_miss_queue_v_lo;
  coverpoint st_miss_v;
  coverpoint alloc_done_v;

    cross v_tl_r, tag_op_tl, mshr_cam_w_empty_lo, v_v_r, v_o, yumi_i, serve_read_queue_output_occupied, dma_serve_read_miss_queue_v_lo, st_miss_v, alloc_done_v {
      ignore_bins n_vo = 
        binsof(v_o) intersect {1'b0} &&
        binsof(yumi_i) intersect {1'b1};

      illegal_bins n_vvr = 
        binsof(v_v_r) intersect {1'b0} &&
        (binsof(serve_read_queue_output_occupied) intersect {1'b1} ||
        binsof(st_miss_v) intersect {1'b1});

      illegal_bins n_st_miss =
        binsof(st_miss_v) intersect {1'b0} &&
        binsof(alloc_done_v) intersect {1'b1};

      illegal_bins ld_st = 
        binsof(serve_read_queue_output_occupied) intersect {1'b1} &&
        binsof(st_miss_v) intersect {1'b1};

      illegal_bins ld_alloc_done =
        binsof(serve_read_queue_output_occupied) intersect {1'b1} &&
        binsof(alloc_done_v) intersect {1'b1};
    }

  endgroup


  covergroup cg_readq_v @ (negedge clk_i iff read_miss_queue_v_li);

    coverpoint dma_serve_read_miss_queue_v_lo;
    coverpoint ld_found_in_mshr_alloc_read_miss_entry_v;
    coverpoint ld_miss_v;

    cross dma_serve_read_miss_queue_v_lo, ld_found_in_mshr_alloc_read_miss_entry_v {
      ignore_bins serve0 = 
        binsof(dma_serve_read_miss_queue_v_lo) intersect {1'b1};
    }

    cross dma_serve_read_miss_queue_v_lo, ld_miss_v {
      ignore_bins serve1 = 
        binsof(dma_serve_read_miss_queue_v_lo) intersect {1'b1};
    }

  endgroup 


  covergroup cg_mshr_write @ (negedge clk_i iff (|mshr_cam_w_v_li));

    coverpoint mshr_clear;
    coverpoint alloc_write_tag_and_stat_v;
    coverpoint st_found_in_mshr_update_mshr_v;

    cross mshr_clear, alloc_write_tag_and_stat_v {
      ignore_bins clear0 = 
        binsof(mshr_clear) intersect {1'b1};
    }

    cross mshr_clear, st_found_in_mshr_update_mshr_v {
      ignore_bins clear1 = 
        binsof(mshr_clear) intersect {1'b1};
    }

  endgroup 


  covergroup cg_ld_case @ (negedge clk_i iff decode_v_r.ld_op);
    
    coverpoint ld_miss_v;
    coverpoint ld_found_in_mshr_output_ld_data_v;
    coverpoint ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_v;
    coverpoint ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_and_sbuf_bypass;
    coverpoint ld_found_in_mshr_and_hit_in_track_data_v {
      bins zero = {0};  
      illegal_bins one = {1};  
    };
    coverpoint ld_found_in_mshr_output_mshr_data_v;
    coverpoint ld_found_in_mshr_alloc_read_miss_entry_v;

    cross ld_miss_v, ld_found_in_mshr_output_ld_data_v, ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_v, ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_and_sbuf_bypass, ld_found_in_mshr_output_mshr_data_v, ld_found_in_mshr_alloc_read_miss_entry_v {
        illegal_bins ld_two_or_more_ones = 
            binsof(ld_found_in_mshr_output_ld_data_v) intersect {1'b1} && 
            (binsof(ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_v) intersect {1'b1} || 
             binsof(ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_and_sbuf_bypass) intersect {1'b1} || 
             binsof(ld_found_in_mshr_output_mshr_data_v) intersect {1'b1} ||
             binsof(ld_miss_v) intersect {1'b1} ||
             binsof(ld_found_in_mshr_alloc_read_miss_entry_v) intersect {1'b1}) ||

            binsof(ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_v) intersect {1'b1} && 
            (binsof(ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_and_sbuf_bypass) intersect {1'b1} || 
             binsof(ld_found_in_mshr_output_mshr_data_v) intersect {1'b1} ||
             binsof(ld_miss_v) intersect {1'b1} ||
             binsof(ld_found_in_mshr_alloc_read_miss_entry_v) intersect {1'b1}) ||

            binsof(ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_and_sbuf_bypass) intersect {1'b1} && 
            (binsof(ld_found_in_mshr_output_mshr_data_v) intersect {1'b1} ||
            binsof(ld_miss_v) intersect {1'b1} ||
            binsof(ld_found_in_mshr_alloc_read_miss_entry_v) intersect {1'b1}) ||
            
            binsof(ld_found_in_mshr_output_mshr_data_v) intersect {1'b1} && 
            (binsof(ld_miss_v) intersect {1'b1} ||
            binsof(ld_found_in_mshr_alloc_read_miss_entry_v) intersect {1'b1})
            
            binsof(ld_miss_v) intersect {1'b1} &&
            binsof(ld_found_in_mshr_alloc_read_miss_entry_v) intersect {1'b1};
    };

  endgroup 


  covergroup cg_st_case @ (negedge clk_i iff decode_v_r.st_op);

    coverpoint st_miss_v;
    coverpoint st_found_in_mshr_update_mshr_v;
    coverpoint st_found_in_mshr_update_sbuf_and_tbuf_v;

    cross st_miss_v, st_found_in_mshr_update_mshr_v, st_found_in_mshr_update_sbuf_and_tbuf_v {
      illegal_bins st_two_or_more_ones = 
        binsof(st_miss_v) intersect {1'b1} &&
        (binsof(st_found_in_mshr_update_mshr_v) intersect {1'b1} ||
         binsof(st_found_in_mshr_update_sbuf_and_tbuf_v) intersect {1'b1}) ||

        binsof(st_found_in_mshr_update_mshr_v) intersect {1'b1} && 
        binsof(st_found_in_mshr_update_sbuf_and_tbuf_v) intersect {1'b1};
    }

  endgroup


  covergroup cg_input_output @ (negedge clk_i);

    coverpoint v_i;
    coverpoint yumi_o;
    coverpoint v_o;
    coverpoint yumi_i;

    cross v_i, yumi_o, v_o, yumi_i {
      ignore_bins n_v_o = 
        binsof(v_o) intersect {1'b0} &&
        binsof(yumi_i) intersect {1'b1};

      illegal_bins n_v_i =
        binsof(v_i) intersect {1'b0} &&
        binsof(yumi_o) intersect {1'b1};
    }

  endgroup 


  covergroup cg_dma_hold @ (negedge clk_i iff (dma_data_v_i & dma_data_ready_o));

    coverpoint dma_refill_hold_li;
    covergroup alloc_in_progress_v;
    covergroup alloc_no_available_way_v;
    covergroup st_found_in_mshr_update_mshr_v;
    covergroup st_found_in_mshr_update_sbuf_and_tbuf_v;
    covergroup yumi_i;

    cross dma_refill_hold_li, alloc_in_progress_v, alloc_no_available_way_v, st_found_in_mshr_update_mshr_v, st_found_in_mshr_update_sbuf_and_tbuf_v, yumi_i {
      ignore_bins n_hold = 
        binsof(dma_refill_hold_li) intersect {1'b0} &&
        binsof(alloc_in_progress_v) intersect {1'b0} &&
        binsof(st_found_in_mshr_update_mshr_v) intersect {1'b0} &&
        binsof(st_found_in_mshr_update_sbuf_and_tbuf_v) intersect {1'b0};
      
      illegal_bins conflict_cases =
        binsof(alloc_in_progress_v) intersect {1'b1} &&
        (binsof(st_found_in_mshr_update_mshr_v) intersect {1'b1} ||
         binsof(st_found_in_mshr_update_sbuf_and_tbuf_v) intersect {1'b1}) ||

        binsof(st_found_in_mshr_update_mshr_v) intersect {1'b1} &&
        binsof(st_found_in_mshr_update_sbuf_and_tbuf_v) intersect {1'b1};

      illegal_bins hold_but_all_zero = 
        binsof(dma_refill_hold_li) intersect {1'b1} &&
        binsof(alloc_in_progress_v) intersect {1'b0} &&
        binsof(st_found_in_mshr_update_mshr_v) intersect {1'b0} &&
        binsof(st_found_in_mshr_update_sbuf_and_tbuf_v) intersect {1'b0};
    }

  endgroup


  covergroup cg_alloc_idle @ (negedge clk_i iff alloc_mshr_state_r == IDLE);
  
    coverpoint mshr_entry_alloc_ready;

  endgroup


  covergroup cg_alloc_write @ (negedge clk_i iff alloc_mshr_state_r == WRITE_TAG_AND_STAT);
  
    coverpoint way_chooser_no_available_way_lo;
    coverpoint dma_mshr_cam_r_v_lo;
    coverpoint dma_serve_read_miss_queue_v_lo;
    coverpoint ld_miss_v;

    cross way_chooser_no_available_way_lo, dma_mshr_cam_r_v_lo {
      illegal_bins avail_but_dma_v = 
        binsof(way_chooser_no_available_way_lo) intersect {1'b0} && 
        binsof(dma_mshr_cam_r_v_lo) intersect {1'b1};
    }

    cross way_chooser_no_available_way_lo, dma_serve_read_miss_queue_v_lo, ld_miss_v {
      ignore_bins no_avail = 
        binsof(way_chooser_no_available_way_lo) intersect {1'b1};
    }

  endgroup

  initial begin
    cg_tl_recover ctr = new;
    cg_dma_in_out cdio = new;
    cg_tl_tv_state ctts = new;
    cg_n_v_o cnvo = new;
    cd_n_tl_ready cntr = new; 
    cg_v_we cvw = new; 
    cg_readq_v crv = new;
    cg_mshr_write cmw = new;
    cg_ld_case clc = new; 
    cg_st_case csc = new;
    cg_input_output cio = new;
    cg_dma_hold cdh = new; 
    cg_alloc_idle cai = new;
    cg_alloc_write caw = new;
  end


endmodule
