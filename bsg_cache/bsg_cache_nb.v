`include "bsg_defines.v"
`include "bsg_cache_nb.vh"

module bsg_cache_nb
  import bsg_cache_nb_pkg::*;
  #(parameter `BSG_INV_PARAM(addr_width_p) // byte addr
    ,parameter `BSG_INV_PARAM(word_width_p)  // word size
    ,parameter `BSG_INV_PARAM(block_size_in_words_p)
    ,parameter `BSG_INV_PARAM(sets_p)
    ,parameter `BSG_INV_PARAM(ways_p)
    ,parameter `BSG_INV_PARAM(mshr_els_p)
    ,parameter `BSG_INV_PARAM(read_miss_els_per_mshr_p)
    ,parameter `BSG_INV_PARAM(src_id_width_p)
    ,parameter `BSG_INV_PARAM(word_tracking_p)

    // Explicit size prevents size inference and allows for ((foo == bar) << e_cache_amo_swap)
    ,parameter [31:0] amo_support_p=(1 << e_cache_amo_swap)
                                    | (1 << e_cache_amo_or)
                                    | (1 << e_cache_amo_min)
                                    | (1 << e_cache_amo_max)

    // dma burst width
    ,parameter dma_data_width_p=word_width_p // default value. it can also be pow2 multiple of word_width_p.

    ,parameter bsg_cache_nb_pkt_width_lp=`bsg_cache_nb_pkt_width(addr_width_p,word_width_p,src_id_width_p)
    ,parameter bsg_cache_nb_dma_pkt_width_lp=`bsg_cache_nb_dma_pkt_width(addr_width_p,block_size_in_words_p,mshr_els_p)
    ,parameter burst_size_in_words_lp=(dma_data_width_p/word_width_p)
	  ,parameter lg_mshr_els_lp = `BSG_SAFE_CLOG2(mshr_els_p)

    ,parameter debug_p=0
  )
  (
    input clk_i
    ,input reset_i

    ,input [bsg_cache_nb_pkt_width_lp-1:0] cache_pkt_i
    ,input v_i
    ,output logic yumi_o
    
    ,output logic [word_width_p-1:0] data_o
    ,output logic [src_id_width_p-1:0] src_id_o
    ,output logic v_o
    ,input yumi_i

    ,output logic [bsg_cache_nb_dma_pkt_width_lp-1:0] dma_pkt_o
    ,output logic dma_pkt_v_o
    ,input dma_pkt_yumi_i

    ,input [dma_data_width_p-1:0] dma_data_i
    ,input [lg_mshr_els_lp-1:0] dma_mshr_id_i
    ,input dma_data_v_i
    ,output logic dma_data_ready_o

    ,output logic [dma_data_width_p-1:0] dma_data_o
    ,output logic dma_data_v_o
    ,input dma_data_yumi_i

    // this signal tells the outside world that the instruction is moving from
    // TL to TV stage. It can be used for some metadata outside the cache that
    // needs to move together with the corresponding instruction. The usage of
    // this signal is totally optional.
    ,output logic v_we_o
  );


  // localparam
  //
  localparam lg_sets_lp=`BSG_SAFE_CLOG2(sets_p);
  localparam data_mask_width_lp=(word_width_p>>3);
  localparam lg_data_mask_width_lp=`BSG_SAFE_CLOG2(data_mask_width_lp);
  localparam lg_block_size_in_words_lp=`BSG_SAFE_CLOG2(block_size_in_words_p);
  localparam num_of_words_per_bank_lp=(block_size_in_words_p/2);
  localparam num_of_burst_per_bank_lp=(num_of_words_per_bank_lp*word_width_p/dma_data_width_p);
  localparam block_offset_width_lp=(block_size_in_words_p > 1) ? lg_data_mask_width_lp+lg_block_size_in_words_lp : lg_data_mask_width_lp;
  localparam way_offset_width_lp=(sets_p == 1) ? block_offset_width_lp : block_offset_width_lp+lg_sets_lp;
  localparam tag_width_lp=(sets_p == 1) ? (addr_width_p-block_offset_width_lp) : (addr_width_p-lg_sets_lp-block_offset_width_lp);
  localparam tag_info_width_lp=`bsg_cache_nb_tag_info_width(tag_width_lp);
  localparam cache_line_offset_width_lp=(sets_p == 1) ? tag_width_lp : tag_width_lp+lg_sets_lp;
  localparam lg_ways_lp=`BSG_SAFE_CLOG2(ways_p);
  localparam lg_read_miss_els_per_mshr_lp = `BSG_SAFE_CLOG2(read_miss_els_per_mshr_p);
  localparam stat_info_width_lp = `bsg_cache_nb_stat_info_width(ways_p);
  localparam data_sel_mux_els_lp = `BSG_MIN(4,lg_data_mask_width_lp+1);
  localparam lg_data_sel_mux_els_lp = `BSG_SAFE_CLOG2(data_sel_mux_els_lp);

  localparam block_data_width_lp = block_size_in_words_p*word_width_p;
  localparam block_data_mask_width_lp = (block_data_width_lp>>3);

  localparam safe_mshr_els_lp = `BSG_MAX(mshr_els_p,1);
  localparam safe_read_miss_els_per_mshr_lp = `BSG_MAX(read_miss_els_per_mshr_p,1);

  localparam lg_burst_size_in_words_lp=`BSG_SAFE_CLOG2(burst_size_in_words_lp);
  localparam num_of_burst_lp=(block_size_in_words_p*word_width_p/dma_data_width_p);
  localparam lg_num_of_burst_lp=`BSG_SAFE_CLOG2(num_of_burst_lp);
  localparam dma_data_mask_width_lp=(dma_data_width_p>>3);
  localparam data_mem_els_lp = sets_p*num_of_burst_lp;
  localparam lg_data_mem_els_lp = `BSG_SAFE_CLOG2(data_mem_els_lp);
  localparam data_bank_els_lp=(sets_p*num_of_burst_per_bank_lp);
  localparam lg_data_bank_els_lp=`BSG_SAFE_CLOG2(data_bank_els_lp);
  localparam sbuf_data_mem_addr_offset_lp=(num_of_burst_lp == block_size_in_words_p) ? lg_block_size_in_words_lp+$clog2(sets_p) : lg_num_of_burst_lp+$clog2(sets_p); 

  localparam evict_fifo_info_width_lp = `bsg_cache_nb_evict_fifo_entry_width(ways_p, sets_p, mshr_els_p);
  localparam store_tag_miss_fifo_info_width_lp = `bsg_cache_nb_store_tag_miss_fifo_entry_width(ways_p, sets_p, mshr_els_p, word_width_p, block_size_in_words_p);

  // instruction decoding
  //
  logic [lg_ways_lp-1:0] addr_way;
  logic [lg_sets_lp-1:0] addr_index;

  `declare_bsg_cache_nb_pkt_s(addr_width_p, word_width_p, src_id_width_p);
  bsg_cache_nb_pkt_s cache_pkt;

  assign cache_pkt = cache_pkt_i;

  bsg_cache_nb_decode_s decode;

  bsg_cache_nb_op_decode decode0 (
    .opcode_i(cache_pkt.opcode)
    ,.decode_o(decode)
  );

  //////////////////////
  // TAG LOOKUP STAGE //
  //////////////////////
  logic tl_we;
  logic tl_recover;
  logic v_tl_r;
  bsg_cache_nb_decode_s decode_tl_r;
  logic [data_mask_width_lp-1:0] mask_tl_r;
  logic [addr_width_p-1:0] addr_tl_r;
  logic [word_width_p-1:0] data_tl_r;
  logic [src_id_width_p-1:0] src_id_tl_r;
  logic sbuf_hazard;
  logic [lg_sets_lp-1:0] addr_index_tl;
  logic ld_dma_or_trans_hit_and_word_written_tl_r;

  // TAG MEM
  `declare_bsg_cache_nb_tag_info_s(tag_width_lp);
  logic tag_mem_v_li;
  logic tag_mem_w_li;
  logic [lg_sets_lp-1:0] tag_mem_addr_li;
  bsg_cache_nb_tag_info_s [ways_p-1:0] tag_mem_data_li;
  bsg_cache_nb_tag_info_s [ways_p-1:0] tag_mem_w_mask_li;
  bsg_cache_nb_tag_info_s [ways_p-1:0] tag_mem_data_lo;

  logic [ways_p-1:0] valid_tl;
  logic [ways_p-1:0][tag_width_lp-1:0] tag_tl;
  logic [ways_p-1:0] lock_tl;
  
  // DATA MEM
  logic data_mem_even_bank_v_li;
  logic data_mem_even_bank_w_li;
  logic [lg_data_bank_els_lp-1:0] data_mem_even_bank_addr_li;
  logic [ways_p-1:0][dma_data_width_p-1:0] data_mem_even_bank_data_li;
  logic [ways_p-1:0][dma_data_mask_width_lp-1:0] data_mem_even_bank_w_mask_li;
  logic [ways_p-1:0][dma_data_width_p-1:0] data_mem_even_bank_data_lo;
  logic [lg_data_bank_els_lp-1:0] recover_data_mem_addr;
  logic [lg_data_bank_els_lp-1:0] ld_data_mem_addr;

  logic data_mem_odd_bank_v_li;
  logic data_mem_odd_bank_w_li;
  logic [lg_data_bank_els_lp-1:0] data_mem_odd_bank_addr_li;
  logic [ways_p-1:0][dma_data_width_p-1:0] data_mem_odd_bank_data_li;
  logic [ways_p-1:0][dma_data_mask_width_lp-1:0] data_mem_odd_bank_w_mask_li;
  logic [ways_p-1:0][dma_data_width_p-1:0] data_mem_odd_bank_data_lo;

  logic [ways_p-1:0][dma_data_width_p-1:0] data_mem_data_tl_bank_picked;

  // TRACK MEM
  logic track_mem_v_li;
  logic track_mem_w_li;
  logic [lg_sets_lp-1:0] track_mem_addr_li;
  logic [ways_p-1:0][block_size_in_words_p-1:0] track_mem_data_li;
  logic [ways_p-1:0][block_size_in_words_p-1:0] track_mem_w_mask_li;
  logic [ways_p-1:0][block_size_in_words_p-1:0] track_mem_data_lo;

  //////////////////////
  //////////////////////


  //////////////////////
  // TAG VERIFY STAGE //
  //////////////////////
  logic v_we;
  logic v_v_r;
  bsg_cache_nb_decode_s decode_v_r;
  logic [data_mask_width_lp-1:0] mask_v_r;
  logic [addr_width_p-1:0] addr_v_r;
  logic [word_width_p-1:0] data_v_r;
  logic [src_id_width_p-1:0] src_id_v_r;
  logic [ways_p-1:0] valid_v_r;
  logic [ways_p-1:0] lock_v_r;
  logic [ways_p-1:0][tag_width_lp-1:0] tag_v_r;
  logic [ways_p-1:0][dma_data_width_p-1:0] ld_data_v_r;
  logic [ways_p-1:0][block_size_in_words_p-1:0] track_data_v_r;
  logic return_val_op_v;
  logic ld_dma_or_trans_hit_and_word_written_v_r;

  logic [tag_width_lp-1:0] addr_tag_v;
  logic [lg_sets_lp-1:0] addr_index_v;
  logic [lg_ways_lp-1:0] addr_way_v;
  logic [lg_block_size_in_words_lp-1:0] addr_block_offset_v;
  logic [lg_data_mask_width_lp-1:0] addr_byte_sel_v;
  logic [ways_p-1:0] tag_hit_v;
  logic [lg_ways_lp-1:0] tag_hit_way_id_v;
  logic tag_hit_found_v;

  logic [block_size_in_words_p-1:0] block_offset_decode;
  logic [block_data_mask_width_lp-1:0] block_offset_decode_expand_mask;

  logic bypass_track_lo;

  // STAT MEM
  `declare_bsg_cache_nb_stat_info_s(ways_p);  
  logic stat_mem_v_li;
  logic stat_mem_w_li;
  logic [lg_sets_lp-1:0] stat_mem_addr_li;
  bsg_cache_nb_stat_info_s stat_mem_data_li;
  bsg_cache_nb_stat_info_s stat_mem_w_mask_li;
  bsg_cache_nb_stat_info_s stat_mem_data_lo;

  // Alloc MSHR Entry
  typedef enum logic [1:0] {
    IDLE
    ,WRITE_TAG_AND_STAT
    ,RECOVER
    ,DONE
  } alloc_mshr_state_e;

  alloc_mshr_state_e alloc_mshr_state_n;
  alloc_mshr_state_e alloc_mshr_state_r;
  logic alloc_read_stat_v, alloc_write_tag_and_stat_v, alloc_recover_v, 
        alloc_in_progress_v, alloc_done_v, alloc_no_available_way_v;

  bsg_cache_nb_tag_info_s [ways_p-1:0] alloc_tag_mem_data, alloc_tag_mem_mask;
  bsg_cache_nb_stat_info_s alloc_stat_mem_data, alloc_stat_mem_mask;

  //////////////////////
  //////////////////////


  //////////////////////
  //// STORE BUFFER ////
  //////////////////////
  `declare_bsg_cache_nb_sbuf_entry_s(addr_width_p, word_width_p, ways_p);
  logic sbuf_v_li;
  bsg_cache_nb_sbuf_entry_s sbuf_entry_li;

  logic sbuf_v_lo;
  logic sbuf_yumi_li;
  bsg_cache_nb_sbuf_entry_s sbuf_entry_lo;

  logic [addr_width_p-1:0] sbuf_bypass_addr_li;
  logic sbuf_bypass_v_li;
  logic [word_width_p-1:0] bypass_data_lo;
  logic [data_mask_width_lp-1:0] bypass_mask_lo;
  logic sbuf_full_lo;

  logic [addr_width_p-1:0] sbuf_el0_addr_snoop_lo;
  logic [lg_ways_lp-1:0] sbuf_el0_way_snoop_lo;
  logic sbuf_el0_valid_snoop_lo;

  logic [addr_width_p-1:0] sbuf_el1_addr_snoop_lo;
  logic [lg_ways_lp-1:0] sbuf_el1_way_snoop_lo;
  logic sbuf_el1_valid_snoop_lo;

  logic [ways_p-1:0] sbuf_way_decode;
  logic [`BSG_SAFE_CLOG2(burst_size_in_words_lp)-1:0] sbuf_burst_offset;
  logic [burst_size_in_words_lp-1:0] sbuf_burst_offset_decode;
  logic [dma_data_mask_width_lp-1:0] sbuf_expand_mask;

  logic [ways_p-1:0][dma_data_mask_width_lp-1:0] sbuf_data_mem_w_mask;
  logic [ways_p-1:0][dma_data_width_p-1:0] sbuf_data_mem_data;
  logic [lg_data_mem_els_lp-1:0] sbuf_data_mem_addr;

  logic [data_sel_mux_els_lp-1:0][word_width_p-1:0] sbuf_data_in_mux_li;
  logic [data_sel_mux_els_lp-1:0][data_mask_width_lp-1:0] sbuf_mask_in_mux_li;
  logic [word_width_p-1:0] sbuf_data_in;
  logic [data_mask_width_lp-1:0] sbuf_mask_in;
  logic [word_width_p-1:0] snoop_or_ld_data;
  logic [data_sel_mux_els_lp-1:0][word_width_p-1:0] ld_data_final_li;
  logic [word_width_p-1:0] ld_data_final_lo;
  //////////////////////
  //////////////////////


  //////////////////////
  //// TRACK BUFFER ////
  //////////////////////
  logic tbuf_v_li;
  logic [lg_ways_lp-1:0] tbuf_way_li;
  logic [addr_width_p-1:0] tbuf_addr_li;

  logic tbuf_v_lo;
  logic tbuf_yumi_li;
  logic [lg_ways_lp-1:0] tbuf_way_lo;
  logic [addr_width_p-1:0] tbuf_addr_lo;

  logic [addr_width_p-1:0] tbuf_bypass_addr_li;
  logic tbuf_bypass_v_li;
  logic tbuf_full_lo;

  logic [addr_width_p-1:0] tbuf_el0_addr_snoop_lo;
  logic [lg_ways_lp-1:0] tbuf_el0_way_snoop_lo;
  logic tbuf_el0_valid_snoop_lo;

  logic [addr_width_p-1:0] tbuf_el1_addr_snoop_lo;
  logic [lg_ways_lp-1:0] tbuf_el1_way_snoop_lo;
  logic tbuf_el1_valid_snoop_lo;

  logic [ways_p-1:0] tbuf_way_decode;
  logic [block_size_in_words_p-1:0] tbuf_word_offset_decode;
  
  logic [lg_sets_lp-1:0] tbuf_track_mem_addr;
  logic [ways_p-1:0][block_size_in_words_p-1:0] tbuf_track_mem_w_mask;
  logic [ways_p-1:0][block_size_in_words_p-1:0] tbuf_track_mem_data;
  //////////////////////
  //////////////////////


  ////////////////////////
  // MISS HANDLING UNIT //
  ////////////////////////
  logic [safe_mshr_els_lp-1:0] mhu_we_li, mhu_activate_li;
  logic [safe_mshr_els_lp-1:0] mhu_mshr_stm_miss_li, mhu_mshr_stm_miss_lo;
  //logic [safe_mshr_els_lp-1:0] mhu_read_tag_and_stat_v_lo, mhu_write_tag_and_stat_v_lo; 
  logic [safe_mshr_els_lp-1:0] mhu_read_track_v_lo, mhu_write_track_v_lo;

  bsg_cache_nb_dma_cmd_e mhu_dma_cmd_lo [safe_mshr_els_lp-1:0];
  logic [safe_mshr_els_lp-1:0][addr_width_p-1:0] mhu_dma_addr_lo;
  logic [safe_mshr_els_lp-1:0][lg_sets_lp-1:0] mhu_curr_addr_index_lo;
  logic [safe_mshr_els_lp-1:0][tag_width_lp-1:0] mhu_curr_addr_tag_lo;
  //logic [safe_mshr_els_lp-1:0] mhu_transmitter_store_tag_miss_fill_done_li;

  logic [safe_mshr_els_lp-1:0] mhu_recover_ack_li, mhu_recover_lo;
  logic [safe_mshr_els_lp-1:0][lg_ways_lp-1:0] mhu_chosen_way_lo;
  logic [safe_mshr_els_lp-1:0] transmitter_sbuf_or_tbuf_chosen_way_found_li;
  logic [safe_mshr_els_lp-1:0] mhu_store_tag_miss_op_lo, mhu_track_miss_lo;

  logic [safe_mshr_els_lp-1:0][`BSG_SAFE_MINUS(block_size_in_words_p,1):0] mhu_track_data_way_picked_lo;
  logic [safe_mshr_els_lp-1:0] mhu_evict_v_lo, mhu_store_tag_miss_fill_v_lo;
  logic [safe_mshr_els_lp-1:0] mhu_write_fill_data_in_progress_lo;
  logic [safe_mshr_els_lp-1:0] mhu_req_busy_lo;

  logic [lg_sets_lp-1:0] way_chooser_addr_index_li; 
  logic [lg_ways_lp-1:0] way_chooser_chosen_way_lo;
  logic way_chooser_no_available_way_lo;
  logic [ways_p-1:0] alloc_chosen_way_decode;
  logic [ways_p-1:0] mhu_chosen_way_decode;

  logic [lg_mshr_els_lp-1:0] mhu_evict_mshr_id;
  logic mhu_evict_v_o_found;
  logic [lg_mshr_els_lp-1:0] mhu_store_tag_miss_mshr_id;
  logic mhu_store_tag_miss_v_o_found;
  logic [lg_mshr_els_lp-1:0] mshr_clear_id;
  logic mshr_clear;
  logic [lg_mshr_els_lp-1:0] mhu_req_mshr_id;
  logic mhu_req_exist;

  logic mhu_req_ready;
  ////////////////////////
  ////////////////////////


  ////////////////////////
  /// MSHR CAM & ALLOC ///
  ////////////////////////
  logic [safe_mshr_els_lp-1:0] mshr_cam_w_v_li;
  logic mshr_cam_r_by_tag_v_li, mshr_cam_r_by_mshr_id_v_li;
  logic [lg_mshr_els_lp-1:0] mshr_cam_r_mshr_id_li;
  logic [safe_mshr_els_lp-1:0] mshr_cam_w_empty_lo;
  logic [safe_mshr_els_lp-1:0] mshr_cam_r_tag_match_lo;
  logic [cache_line_offset_width_lp-1:0] mshr_cam_w_tag_li, mshr_cam_r_tag_li;
  logic [block_data_mask_width_lp-1:0] mshr_cam_w_mask_li, mshr_cam_r_mask_lo;
  logic [block_data_width_lp-1:0] mshr_cam_w_data_li, mshr_cam_r_data_lo;
  logic mshr_cam_r_match_found_lo;
  logic mshr_cam_w_set_not_clear_li; 

  logic [data_mask_width_lp-1:0] mshr_mask_out_offset_selected;
  logic [word_width_p-1:0] mshr_data_out_offset_selected;

  logic [safe_mshr_els_lp-1:0] mshr_entry_allocate_encode_data_lo;
  logic mshr_entry_allocate_v_lo;

  logic [lg_mshr_els_lp-1:0] alloc_or_update_mshr_id_lo;

  logic mshr_order_queue_ready_lo;
  logic mshr_order_queue_v_lo, mshr_order_queue_yumi_li;
  logic [safe_mshr_els_lp-1:0] mshr_order_queue_data_lo;
  ////////////////////////
  ////////////////////////


  ////////////////////////
  /// READ MISS QUEUE ////
  ////////////////////////
  logic [lg_mshr_els_lp-1:0] read_miss_queue_mshr_id_li;
  logic read_miss_queue_v_li;
  logic [`BSG_SAFE_MINUS(mshr_els_p, 1):0] read_miss_queue_ready_lo;
  logic read_miss_queue_write_not_read_li;

  logic [`BSG_SAFE_MINUS(src_id_width_p, 1):0] read_miss_queue_src_id_lo;
  logic [lg_block_size_in_words_lp-1:0] read_miss_queue_word_offset_lo;
  logic read_miss_queue_mask_op_lo;
  logic [data_mask_width_lp-1:0] read_miss_queue_mask_lo;
  logic [1:0] read_miss_queue_size_op_lo;
  logic read_miss_queue_sigext_op_lo;
  logic [lg_data_mask_width_lp-1:0] read_miss_queue_byte_sel_lo;
  logic [word_width_p-1:0] read_miss_queue_mshr_data_lo;
  logic [data_mask_width_lp-1:0] read_miss_queue_mshr_data_mask_lo;

  logic [`BSG_SAFE_MINUS(mshr_els_p, 1):0] read_miss_queue_v_lo;

  logic read_miss_queue_read_done_lo;
  logic read_miss_queue_read_in_progress_lo;
  ////////////////////////
  ////////////////////////


  ////////////////////////
  ////////// DMA /////////
  ////////////////////////
  bsg_cache_nb_dma_cmd_e dma_cmd_li;
  logic [addr_width_p-1:0] dma_req_addr_li;
  logic [lg_mshr_els_lp-1:0] dma_req_mshr_id_li;

  logic dma_refill_track_miss_li;
  logic [`BSG_SAFE_MINUS(block_size_in_words_p,1):0] dma_refill_track_data_way_picked_li;
  logic [lg_ways_lp-1:0] dma_refill_way_li;
  logic [lg_sets_lp-1:0] dma_refill_addr_index_li;

  logic [`BSG_SAFE_MINUS(mshr_els_p,1):0] dma_mhu_done_lo;
  logic dma_mgmt_done_lo;

  logic [`BSG_WIDTH(num_of_burst_lp)-1:0] dma_refill_data_in_counter_lo;

  logic [word_width_p-1:0] dma_snoop_word_lo;
  logic dma_serve_read_miss_queue_v_lo;

  logic dma_read_miss_queue_serve_v_li;

  logic [lg_mshr_els_lp-1:0] dma_refill_mshr_id_lo;

  logic dma_refill_hold_li;

  logic dma_mshr_cam_r_v_lo;

  logic [1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] dma_refill_data_lo;
  logic dma_refill_track_miss_lo;
  logic [block_size_in_words_p-1:0] dma_refill_track_data_way_picked_lo;
  logic dma_refill_v_lo;
  logic [lg_ways_lp-1:0] dma_refill_way_lo;
  logic [lg_sets_lp-1:0] dma_refill_addr_index_lo;
  logic [block_data_mask_width_lp-1:0] dma_refill_mshr_data_byte_mask_lo;

  logic [`BSG_WIDTH(num_of_burst_lp)-1:0] dma_refill_data_out_to_sipo_counter_lo;
  logic dma_refill_data_in_done_lo, dma_refill_in_progress_lo;
  logic dma_transmitter_refill_done_lo;

  logic dma_evict_yumi_lo;
  ////////////////////////
  ////////////////////////


  ////////////////////////
  ////// TRANSMITTER /////
  ////////////////////////
  logic transmitter_evict_we_li;
  logic transmitter_refill_we_li;
  logic transmitter_store_tag_miss_we_li;

  logic transmitter_fill_hold_li;

  logic [lg_mshr_els_lp-1:0] transmitter_mshr_id_li;

  logic [lg_ways_lp-1:0] transmitter_way_li;
  logic [lg_sets_lp-1:0] transmitter_addr_index_li;

  logic [lg_ways_lp-1:0] transmitter_current_way_lo;
  logic [lg_sets_lp-1:0] transmitter_current_addr_index_lo;

  // TODO: maybe unnecassary to output this counter
  logic [`BSG_WIDTH(num_of_burst_per_bank_lp)-1:0] transmitter_mshr_data_write_counter_lo;
  // This could be used for both store tag miss and track miss refill
  logic [block_data_mask_width_lp-1:0] transmitter_mshr_data_byte_mask_li;

  // when next load / sbuf is accessing odd bank, or even bank gets the priority
  logic transmitter_even_bank_v_li;
  logic transmitter_even_bank_v_lo;
  logic transmitter_even_bank_w_lo;
  logic [ways_p-1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] transmitter_even_bank_data_lo;
  logic [ways_p-1:0][dma_data_mask_width_lp-1:0] transmitter_even_bank_w_mask_lo;
  //logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] transmitter_even_bank_data_li;
  logic [lg_data_bank_els_lp-1:0] transmitter_even_bank_addr_lo;
  logic [`BSG_WIDTH(num_of_burst_per_bank_lp)-1:0] transmitter_even_counter_lo;

  logic transmitter_odd_bank_v_li;
  logic transmitter_odd_bank_v_lo;
  logic transmitter_odd_bank_w_lo;
  logic [ways_p-1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] transmitter_odd_bank_data_lo;
  logic [ways_p-1:0][dma_data_mask_width_lp-1:0] transmitter_odd_bank_w_mask_lo;
  //logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] transmitter_odd_bank_data_li; 
  logic [lg_data_bank_els_lp-1:0] transmitter_odd_bank_addr_lo;
  logic [`BSG_WIDTH(num_of_burst_per_bank_lp)-1:0] transmitter_odd_counter_lo;

  logic transmitter_refill_ready_lo;
  logic transmitter_evict_v_lo;
  logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] transmitter_evict_data_lo;
  logic [lg_mshr_els_lp-1:0] transmitter_mshr_id_lo;

  logic transmitter_even_fifo_priority_lo;
  logic transmitter_odd_fifo_priority_lo;

  logic transmitter_data_mem_access_done_lo;

  logic transmitter_refill_done_lo;
  logic transmitter_evict_data_sent_to_dma_done_lo;
  logic [`BSG_SAFE_MINUS(mshr_els_p,1):0] transmitter_mhu_store_tag_miss_fill_done_lo;

  logic transmitter_refill_in_progress_lo;
  logic transmitter_evict_in_progress_lo;
  logic transmitter_store_tag_miss_fill_in_progress_lo;
  ////////////////////////
  ////////////////////////


  ////////////////////////
  /////// TAG MGMT ///////
  ////////////////////////
  logic mgmt_evict_v_lo;
  bsg_cache_nb_dma_cmd_e mgmt_dma_cmd_lo;
  logic [addr_width_p-1:0] mgmt_dma_addr_lo;

  // to stat_mem
  logic mgmt_stat_mem_v_lo;
  logic mgmt_stat_mem_w_lo;
  logic [lg_sets_lp-1:0] mgmt_stat_mem_addr_lo;
  logic [stat_info_width_lp-1:0] mgmt_stat_mem_data_lo;
  logic [stat_info_width_lp-1:0] mgmt_stat_mem_w_mask_lo;

  // to tag_mem
  logic mgmt_tag_mem_v_lo;
  logic mgmt_tag_mem_w_lo;
  logic [lg_sets_lp-1:0] mgmt_tag_mem_addr_lo;
  logic [ways_p-1:0][tag_info_width_lp-1:0] mgmt_tag_mem_data_lo;
  logic [ways_p-1:0][tag_info_width_lp-1:0] mgmt_tag_mem_w_mask_lo;

  // to track mem
  logic mgmt_track_mem_v_lo;
  logic mgmt_track_mem_w_lo;
  logic [lg_sets_lp-1:0] mgmt_track_mem_addr_lo;
  logic [ways_p-1:0][block_size_in_words_p-1:0] mgmt_track_mem_w_mask_lo;
  logic [ways_p-1:0][block_size_in_words_p-1:0] mgmt_track_mem_data_lo;

  //logic [lg_ways_lp-1:0] mgmt_flush_way_lo;
  //logic [lg_ways_lp-1:0] mgmt_chosen_way_lo;

  //logic mgmt_goto_flush_op_lo;
  //logic mgmt_goto_lock_op_lo;
  logic [lg_ways_lp-1:0] mgmt_curr_way_lo;

  // to pipeline
  logic mgmt_done_lo;
  logic mgmt_recover_lo;

  logic mgmt_ack_li;
  ////////////////////////
  ////////////////////////


  ////////////////////////
  /// EVICT & STM FIFO ///
  ////////////////////////
  `declare_bsg_cache_nb_evict_fifo_entry_s(ways_p, sets_p, mshr_els_p);
  bsg_cache_nb_evict_fifo_entry_s evict_fifo_entry_li;
  bsg_cache_nb_evict_fifo_entry_s evict_fifo_entry_lo;
  logic evict_fifo_valid_li, evict_fifo_ready_lo;
  logic evict_fifo_valid_lo, evict_fifo_yumi_li;

  `declare_bsg_cache_nb_store_tag_miss_fifo_entry_s(ways_p, sets_p, mshr_els_p, word_width_p, block_size_in_words_p);
  bsg_cache_nb_store_tag_miss_fifo_entry_s store_tag_miss_fifo_entry_li;
  bsg_cache_nb_store_tag_miss_fifo_entry_s store_tag_miss_fifo_entry_lo;
  logic store_tag_miss_fifo_valid_li, store_tag_miss_fifo_ready_lo;
  logic store_tag_miss_fifo_valid_lo, store_tag_miss_fifo_yumi_li;
  ////////////////////////
  ////////////////////////


  assign addr_way
    = cache_pkt.addr[way_offset_width_lp+:lg_ways_lp];
  assign addr_index
    = cache_pkt.addr[block_offset_width_lp+:lg_sets_lp];
  assign addr_block_offset
    = cache_pkt.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp];
  

  wire ld_even_bank = ((decode.ld_op | decode.atomic_op) & addr_block_offset % 2 == 0);
  wire ld_odd_bank = ((decode.ld_op | decode.atomic_op) & addr_block_offset % 2 != 0);

  wire next_access_even_bank = (sbuf_v_lo & sbuf_yumi_li & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp] % 2 == 0))
                             | ld_even_bank;

  wire next_access_odd_bank = (sbuf_v_lo & sbuf_yumi_li & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp] % 2 != 0))
                            | ld_odd_bank;

  wire even_bank_conflict = transmitter_even_fifo_priority_lo 
                          & (ld_even_bank | (decode.st_op & sbuf_v_lo & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp] % 2 == 0)));
  wire odd_bank_conflict = transmitter_odd_fifo_priority_lo 
                         & (ld_odd_bank | (decode.st_op & sbuf_v_lo & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp] % 2 != 0)));

  wire ld_dma_hit = decode.ld_op 
                       & (dma_refill_data_in_done_lo 
                         & (dma_refill_addr_index_lo==addr_index)
                         & (mhu_curr_addr_tag_lo[dma_refill_mshr_id_lo]==cache_pkt.addr[way_offset_width_lp+:tag_width_lp]));

  wire ld_trans_hit = decode.ld_op
                         & (transmitter_store_tag_miss_fill_in_progress_lo
                           & (mhu_curr_addr_tag_lo[transmitter_mshr_id_lo]==cache_pkt.addr[way_offset_width_lp+:tag_width_lp])
                           & (transmitter_current_addr_index_lo==addr_index));

  wire ld_dma_or_trans_hit_and_word_written = ( ld_dma_hit
                                                   & (dma_transmitter_refill_done_lo 
                                                      || (transmitter_refill_in_progress_lo 
                                                          && ((addr_block_offset % 2 == 0 && transmitter_even_counter_lo >= (addr_block_offset / (2 * burst_size_in_words_lp)) + 1) 
                                                             ||(addr_block_offset % 2 != 0 && transmitter_odd_counter_lo >= (addr_block_offset / (2 * burst_size_in_words_lp)) + 1)
                                                             )
                                                          )))
                                                    | (ld_trans_hit
                                                          & (transmitter_mhu_store_tag_miss_fill_done_lo[transmitter_mshr_id_lo]
                                                            || (transmitter_store_tag_miss_fill_in_progress_lo
                                                               && ((addr_block_offset % 2 == 0 && transmitter_even_counter_lo >= (addr_block_offset / (2 * burst_size_in_words_lp)) + 1) 
                                                                  ||(addr_block_offset % 2 != 0 && transmitter_odd_counter_lo >= (addr_block_offset / (2 * burst_size_in_words_lp)) + 1)
                                                                  )
                                                          )));

  if (num_of_burst_per_bank_lp == 1) begin
    assign ld_data_mem_addr = addr_index;
  end
  else if (num_of_burst_per_bank_lp == num_of_words_per_bank_lp) begin
    assign ld_data_mem_addr = {{(sets_p>1){addr_index}}, cache_pkt.addr[(lg_data_mask_width_lp+1)+:(lg_block_size_in_words_lp-1)]};
  end
  else begin
    assign ld_data_mem_addr = {addr_index, cache_pkt.addr[(lg_data_mask_width_lp+lg_burst_size_in_words_lp+1)+:(lg_num_of_burst_lp-1)]};
  end


  /**************************************** TAG **********************************************/
  /*************************************** LOOKUP ********************************************/
  /*************************************** STAGE *********************************************/

  always_ff @ (posedge clk_i) begin
    if (reset_i) begin
      v_tl_r <= 1'b0;
      {mask_tl_r
      ,addr_tl_r
      ,data_tl_r
      ,src_id_tl_r
      ,decode_tl_r
      ,ld_dma_or_trans_hit_and_word_written_tl_r} <= '0;
    end
    else begin
      if (tl_we) begin
        v_tl_r <= v_i;
        if (v_i) begin
          mask_tl_r <= cache_pkt.mask;
          addr_tl_r <= cache_pkt.addr;
          data_tl_r <= cache_pkt.data;
          src_id_tl_r <= cache_pkt.src_id;
          decode_tl_r <= decode;
          ld_dma_or_trans_hit_and_word_written_tl_r <= ld_dma_or_trans_hit_and_word_written;
        end
      end
      else begin
        if (v_we) begin
          v_tl_r <= 1'b0;
        end
      end
    end
  end

  assign addr_index_tl =
    addr_tl_r[block_offset_width_lp+:lg_sets_lp];

  // tag_mem
  //
  bsg_mem_1rw_sync_mask_write_bit #(
    .width_p(tag_info_width_lp*ways_p)
    ,.els_p(sets_p)
    ,.latch_last_read_p(1)
  ) tag_mem (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.v_i(tag_mem_v_li)
    ,.w_i(tag_mem_w_li)
    ,.addr_i(tag_mem_addr_li)
    ,.data_i(tag_mem_data_li)
    ,.w_mask_i(tag_mem_w_mask_li)
    ,.data_o(tag_mem_data_lo)
  );

  for (genvar i = 0; i < ways_p; i++) begin: tag_tl_gen
    assign valid_tl[i] = tag_mem_data_lo[i].valid;
    assign tag_tl[i] = tag_mem_data_lo[i].tag;
    assign lock_tl[i] = tag_mem_data_lo[i].lock;
  end
 
  // if (num_of_burst_per_bank_lp == 1) begin
  //   assign recover_data_mem_addr = addr_index_tl;
  // end
  // else if (num_of_burst_per_bank_lp == num_of_words_per_bank_lp) begin
  //   assign recover_data_mem_addr = {{(sets_p>1){addr_index_tl}}, addr_tl_r[(lg_data_mask_width_lp+1)+:(lg_block_size_in_words_lp-1)]};
  // end
  // else begin
  //   assign recover_data_mem_addr = {addr_index_tl, addr_tl_r[(lg_data_mask_width_lp+lg_burst_size_in_words_lp+1)+:(lg_num_of_burst_lp-1)]};
  // end

  // data_mem
  //
  bsg_mem_1rw_sync_mask_write_byte #(
    .data_width_p(dma_data_width_p*ways_p)
    ,.els_p(data_bank_els_lp)
    ,.latch_last_read_p(1)
  ) data_mem_even_bank (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.v_i(data_mem_even_bank_v_li)
    ,.w_i(data_mem_even_bank_w_li)
    ,.addr_i(data_mem_even_bank_addr_li)
    ,.data_i(data_mem_even_bank_data_li)
    ,.write_mask_i(data_mem_even_bank_w_mask_li)
    ,.data_o(data_mem_even_bank_data_lo)
  );

  bsg_mem_1rw_sync_mask_write_byte #(
    .data_width_p(dma_data_width_p*ways_p)
    ,.els_p(data_bank_els_lp)
    ,.latch_last_read_p(1)
  ) data_mem_odd_bank (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.v_i(data_mem_odd_bank_v_li)
    ,.w_i(data_mem_odd_bank_w_li)
    ,.addr_i(data_mem_odd_bank_addr_li)
    ,.data_i(data_mem_odd_bank_data_li)
    ,.write_mask_i(data_mem_odd_bank_w_mask_li)
    ,.data_o(data_mem_odd_bank_data_lo)
  );

  assign data_mem_data_tl_bank_picked = ((addr_tl_r[lg_data_mask_width_lp+:lg_block_size_in_words_lp])%2 == 0)
                                      ? data_mem_even_bank_data_lo
                                      : data_mem_odd_bank_data_lo;      

  // track_mem
  //
  if (word_tracking_p) begin: track_mem_gen
    bsg_mem_1rw_sync_mask_write_bit #(
      .width_p(block_size_in_words_p*ways_p)
      ,.els_p(sets_p)
      ,.latch_last_read_p(1)
    ) track_mem (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.v_i(track_mem_v_li)
      ,.w_i(track_mem_w_li)
      ,.addr_i(track_mem_addr_li)
      ,.data_i(track_mem_data_li)
      ,.w_mask_i(track_mem_w_mask_li)
      ,.data_o(track_mem_data_lo)
    ); 
  end
  else begin
    for (genvar i = 0; i < ways_p; i++) begin: track_mem_data
      assign track_mem_data_lo[i] = {block_size_in_words_p{1'b1}};
    end
  end

  /*******************************************************************************************/
  /*******************************************************************************************/
  /*******************************************************************************************/




  /**************************************** TAG **********************************************/
  /*************************************** VERIFY ********************************************/
  /*************************************** STAGE *********************************************/

  always_ff @ (posedge clk_i) begin
    if (reset_i) begin
      v_v_r <= 1'b0;
      {mask_v_r
      ,decode_v_r
      ,addr_v_r
      ,data_v_r
      ,valid_v_r
      ,lock_v_r
      ,tag_v_r
      ,track_data_v_r
      ,ld_dma_or_trans_hit_and_word_written_v_r} <= '0;
    end
    else begin
      if (v_we) begin
        v_v_r <= v_tl_r;
        if (v_tl_r) begin
          mask_v_r <= mask_tl_r;
          src_id_v_r <= src_id_tl_r;
          decode_v_r <= decode_tl_r;
          addr_v_r <= addr_tl_r;
          data_v_r <= data_tl_r;
          valid_v_r <= valid_tl;
          tag_v_r <= tag_tl;
          lock_v_r <= lock_tl;
          ld_data_v_r <= data_mem_data_tl_bank_picked;
          track_data_v_r <= track_mem_data_lo;
          ld_dma_or_trans_hit_and_word_written_v_r <= ld_dma_or_trans_hit_and_word_written_tl_r;
        end
    end
    else if (v_o & yumi_i & ~dma_serve_read_miss_queue_v_lo) begin
      v_v_r <= 1'b0;
    end
    end
  end

  assign v_we_o = v_we;

  assign addr_tag_v =
    addr_v_r[way_offset_width_lp+:tag_width_lp];
  assign addr_index_v =
    addr_v_r[block_offset_width_lp+:lg_sets_lp];
  assign addr_way_v =
    addr_v_r[way_offset_width_lp+:lg_ways_lp];
  assign addr_block_offset_v = (block_size_in_words_p > 1)
    ? addr_v_r[lg_data_mask_width_lp+:lg_block_size_in_words_lp]
    : 1'b0;
  assign addr_byte_sel_v = 
    addr_v_r[0+:lg_data_mask_width_lp];

  bsg_decode #(
    .num_out_p(block_size_in_words_p)
  ) block_offset_v_demux (
    .i(addr_block_offset_v)
    ,.o(block_offset_decode) 
  );

  bsg_expand_bitmask #(
    .in_width_p(block_size_in_words_p)
    ,.expand_p(data_mask_width_lp)
  ) block_offset_decode_expand (
    .i(block_offset_decode)
    ,.o(block_offset_decode_expand_mask)
  ); 

  for (genvar i = 0; i < ways_p; i++) begin: tag_hit_v_bits
    assign tag_hit_v[i] = (addr_tag_v == tag_v_r[i]) & valid_v_r[i];
  end

  bsg_priority_encode #(
    .width_p(ways_p)
    ,.lo_to_hi_p(1)
  ) tag_hit_pe (
    .i(tag_hit_v)
    ,.addr_o(tag_hit_way_id_v)
    ,.v_o(tag_hit_found_v)
  );

  wire partial_st    = decode.st_op & (decode.mask_op
                                        ? ~(&cache_pkt.mask)
                                        : (decode.data_size_op < lg_data_mask_width_lp));
  wire partial_st_tl = decode_tl_r.st_op & (decode_tl_r.mask_op
                                        ? ~(&mask_tl_r)
                                        : (decode_tl_r.data_size_op < lg_data_mask_width_lp));
  wire partial_st_v  = decode_v_r.st_op & (decode_v_r.mask_op
                                        ? ~(&mask_v_r)
                                        : (decode_v_r.data_size_op < lg_data_mask_width_lp));
  

  wire mshr_match_found_v = mshr_cam_r_match_found_lo & mshr_cam_r_by_tag_v_li & ~(alloc_in_progress_v | alloc_recover_v | alloc_done_v);

  // Cases where no match is found in MSHR CAM
  wire track_miss_v = v_v_r & (decode_v_r.ld_op | decode_v_r.atomic_op | partial_st_v) & ~mshr_match_found_v 
                    & tag_hit_found_v & ~(track_data_v_r[tag_hit_way_id_v][addr_block_offset_v] | bypass_track_lo);  

  wire ld_miss_v = v_v_r & decode_v_r.ld_op 
                   & ~tag_hit_found_v & ~mshr_match_found_v; 

  wire st_miss_v = v_v_r & decode_v_r.st_op & ~tag_hit_found_v & ~mshr_match_found_v;

  wire atom_miss_v = v_v_r & decode_v_r.atomic_op & ~tag_hit_found_v;

  wire mshr_entry_alloc_ready = (ld_miss_v | st_miss_v) & mshr_entry_allocate_v_lo;

  // Cases where match is found in MSHR CAM  
  wire mshr_hit = mshr_match_found_v 
                & ( decode_v_r.mask_op 
                  ? ((mask_v_r&mshr_mask_out_offset_selected) == mask_v_r)            //This means all the bytes it wants to read/write
                  : ((sbuf_mask_in&mshr_mask_out_offset_selected) == sbuf_mask_in));  //are all valid in the corresponding MSHR entry 
  
  /////////////////////////////////////////////////////////////////////////////////////////////////
  // This means the cache line is found in mshr and this cache line is currently under refilling by DMA
  wire found_in_mshr_and_dma_hit_v = mshr_match_found_v
                                   & (decode_v_r.ld_op
                                      ? dma_refill_data_in_done_lo 
                                      : (decode_v_r.st_op 
                                         ? dma_refill_in_progress_lo
                                         : 1'b0
                                         ))
                                   & (dma_refill_mshr_id_lo==alloc_or_update_mshr_id_lo);
  // This means the cache line is found in mshr and this cache line is currently under
  // store tag miss filling by transmitter
  wire stm_found_in_mshr_and_trans_hit_v = mshr_match_found_v
                                         & transmitter_store_tag_miss_fill_in_progress_lo
                                         & (transmitter_mshr_id_lo == alloc_or_update_mshr_id_lo);
  // This means it is a dma/transmitter hit and the word that the instruction wants to  
  // read/write has already been written into the data mem 
  wire dma_or_trans_hit_and_word_written_to_dmem_done_v = (found_in_mshr_and_dma_hit_v
                                                          & (dma_transmitter_refill_done_lo 
                                                            || (transmitter_refill_in_progress_lo 
                                                               && ((addr_block_offset_v % 2 == 0 && transmitter_even_counter_lo >= (addr_block_offset_v / (2 * burst_size_in_words_lp)) + 1) 
                                                                 ||(addr_block_offset_v % 2 != 0 && transmitter_odd_counter_lo >= (addr_block_offset_v / (2 * burst_size_in_words_lp)) + 1)
                                                                  )
                                                               )))
                                                        | (stm_found_in_mshr_and_trans_hit_v
                                                          & (transmitter_mhu_store_tag_miss_fill_done_lo[transmitter_mshr_id_lo]
                                                            || (transmitter_store_tag_miss_fill_in_progress_lo
                                                               && ((addr_block_offset_v % 2 == 0 && transmitter_even_counter_lo >= (addr_block_offset_v / (2 * burst_size_in_words_lp)) + 1) 
                                                                 ||(addr_block_offset_v % 2 != 0 && transmitter_odd_counter_lo >= (addr_block_offset_v / (2 * burst_size_in_words_lp)) + 1)
                                                                  )
                                                               )));
  wire dma_hit_and_word_has_written_to_dmem_v = found_in_mshr_and_dma_hit_v & dma_or_trans_hit_and_word_written_to_dmem_done_v;
  wire dma_hit_but_word_not_written_to_dmem_yet_v = found_in_mshr_and_dma_hit_v & ~dma_or_trans_hit_and_word_written_to_dmem_done_v;
  wire trans_hit_and_word_has_written_to_dmem_v = stm_found_in_mshr_and_trans_hit_v & dma_or_trans_hit_and_word_written_to_dmem_done_v;
  wire trans_hit_but_word_not_written_to_dmem_yet_v = stm_found_in_mshr_and_trans_hit_v & ~dma_or_trans_hit_and_word_written_to_dmem_done_v;

  // This means the matched mshr entry is a store tag miss, and the stm fill info has been
  // enqueued into store tag miss fifo, and not been dequeued to transmitter yet
  wire found_in_mshr_and_store_tag_miss_has_enqueued_but_not_dequeued_yet_v = mshr_match_found_v
                                                                            & mhu_store_tag_miss_op_lo[alloc_or_update_mshr_id_lo]
                                                                            & ~mhu_mshr_stm_miss_lo[alloc_or_update_mshr_id_lo]
                                                                            & ~mhu_req_busy_lo[alloc_or_update_mshr_id_lo]
                                                                            & ~stm_found_in_mshr_and_trans_hit_v;
  // This means the matched mshr entry is a track miss and the word that the instruction wants to
  // read/write is a valid word in the track data
  wire mshr_found_and_hit_in_track_v = mshr_match_found_v
                                     & (mhu_track_miss_lo[alloc_or_update_mshr_id_lo]
                                       & tag_hit_found_v
                                       & (track_data_v_r[tag_hit_way_id_v][addr_block_offset_v] | bypass_track_lo)
                                       );  
  // Case0:
  // When the matched MSHR is a track miss and the ld/ato word is valid
  // no matter how many bytes in this word have been updated in MSHR,
  // and no matter if it's a mshr hit or miss,
  // we can always use the load data combined with mshr data as the output word 
  wire ld_found_in_mshr_and_hit_in_track_data_v = v_v_r & decode_v_r.ld_op
                                                    & mshr_found_and_hit_in_track_v
                                                    & (~found_in_mshr_and_dma_hit_v
                                                      | dma_hit_but_word_not_written_to_dmem_yet_v
                                                      );

  // Case1:
  // Use the dma snoop data combined with mshr data as the output word
  wire ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_v = v_v_r & decode_v_r.ld_op
                                                                       & dma_hit_but_word_not_written_to_dmem_yet_v
                                                                       & ~mshr_found_and_hit_in_track_v;

  // Case2:
  // Use the ld data directly as the output word
  // BUG: if in input/tl stage the word has still not been written but in tv it has, then 
  // if we use the ld_data_v, it's actully not the right data
  // FIXED prolly
  wire ld_found_in_mshr_output_ld_data_v = v_v_r & decode_v_r.ld_op
                                             & ld_dma_or_trans_hit_and_word_written_v_r
                                             & (dma_hit_and_word_has_written_to_dmem_v
                                               | (trans_hit_and_word_has_written_to_dmem_v
                                                 & mshr_hit)
                                               );
  
  // Case3:
  // Use dma snoop data × mshr data × sbuf bypass as the output word
  wire ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_and_sbuf_bypass = v_v_r & decode_v_r.ld_op
                                                                                     & dma_hit_and_word_has_written_to_dmem_v
                                                                                     & ~ld_dma_or_trans_hit_and_word_written_v_r
                                                                                     & ~mshr_found_and_hit_in_track_v;

  // Case4:
  // Use the mshr hit word as the output word
  wire ld_found_in_mshr_output_mshr_data_v = v_v_r & decode_v_r.ld_op
                                               & mshr_hit
                                               & (
                                                 //subcase0: store tag miss and hit in transmitter, and the mshr hit word not written to DNEM yet
                                                 trans_hit_but_word_not_written_to_dmem_yet_v
                                                 //subcase1: store tag miss and enqueue the fifo but not dequeue to transmitter yet, and mshr hit
                                                 | found_in_mshr_and_store_tag_miss_has_enqueued_but_not_dequeued_yet_v
                                                 //subcase2: not store tag miss, or store tag miss but not enqueue the fifo yet;
                                                 //          mshr hit, and matched mshr entry is not a track miss or it is a track miss
                                                 //          but the ld word is not a valid word
                                                 | ( ~(found_in_mshr_and_dma_hit_v | stm_found_in_mshr_and_trans_hit_v)
                                                   & ~found_in_mshr_and_store_tag_miss_has_enqueued_but_not_dequeued_yet_v
                                                   & ~mshr_found_and_hit_in_track_v
                                                   )
                                                 );

  // Case5:
  // Allocate a read miss entry in the read queue and output nothing
  wire ld_found_in_mshr_alloc_read_miss_entry_v = v_v_r & decode_v_r.ld_op
                                                    & mshr_match_found_v
                                                    & ~(found_in_mshr_and_dma_hit_v | stm_found_in_mshr_and_trans_hit_v)
                                                    & ~found_in_mshr_and_store_tag_miss_has_enqueued_but_not_dequeued_yet_v
                                                    & ~mshr_hit;

  // Case6:
  // Update MSHR with the st data
  wire st_found_in_mshr_update_mshr_v = v_v_r & decode_v_r.st_op
                                      & mshr_match_found_v
                                      & ~(found_in_mshr_and_dma_hit_v | stm_found_in_mshr_and_trans_hit_v)
                                      & ~found_in_mshr_and_store_tag_miss_has_enqueued_but_not_dequeued_yet_v;

  // Case7:
  // Take as common st which put the st data into sbuf, track data into tbuf
  wire st_found_in_mshr_update_sbuf_and_tbuf_v = v_v_r & decode_v_r.st_op
                                               & mshr_match_found_v
                                               & ((found_in_mshr_and_dma_hit_v & dma_hit_and_word_has_written_to_dmem_v)
                                                 | ( stm_found_in_mshr_and_trans_hit_v 
                                                   & (mshr_hit | ~partial_st_v)
                                                   & trans_hit_and_word_has_written_to_dmem_v)
                                                 );
                                                                      
  // Tag management cases
  // this is used for stalling input→tl
  // wire tag_op = decode.taglv_op | decode.tagla_op | decode.tagfl_op | decode.afl_op 
  //               | decode.aflinv_op | decode.ainv_op | decode.alock_op | decode.aunlock_op;
  wire tag_op_tl = decode_tl_r.tagfl_op | decode_tl_r.afl_op | decode_tl_r.aflinv_op 
                 | decode_tl_r.ainv_op | decode_tl_r.alock_op | decode_tl_r.aunlock_op;

  // this is used for mshr's read valid in
  wire tag_op_v = decode_v_r.taglv_op | decode_v_r.tagla_op | decode_v_r.tagst_op | decode_v_r.tagfl_op | decode_v_r.afl_op 
                | decode_v_r.aflinv_op | decode_v_r.ainv_op | decode_v_r.alock_op | decode_v_r.aunlock_op | decode_v_r.taglv_op 
                | decode_v_r.tagla_op | decode_v_r.tagst_op;

  wire tagfl_hit_v = decode_v_r.tagfl_op & valid_v_r[addr_way_v];
  wire aflinv_hit_v = (decode_v_r.afl_op | decode_v_r.aflinv_op | decode_v_r.ainv_op) & tag_hit_found_v;
  wire alock_miss_v = decode_v_r.alock_op & (tag_hit_found_v ? ~lock_v_r[tag_hit_way_id_v] : 1'b1);   // either the line is miss, or the line is unlocked.
  wire aunlock_hit_v = decode_v_r.aunlock_op & (tag_hit_found_v ? lock_v_r[tag_hit_way_id_v] : 1'b0); // the line is hit and locked. 
  wire mgmt_v = (~decode_v_r.tagst_op) & v_v_r 
              & (tagfl_hit_v | aflinv_hit_v | alock_miss_v | aunlock_hit_v | atom_miss_v);

  // ops that return some value other than '0.
  assign return_val_op_v = decode_v_r.ld_op | decode_v_r.taglv_op | decode_v_r.tagla_op | decode_v_r.atomic_op; 

  // stat_mem
  //
  bsg_mem_1rw_sync_mask_write_bit #(
    .width_p(stat_info_width_lp)
    ,.els_p(sets_p)
    ,.latch_last_read_p(1)
  ) stat_mem (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.v_i(stat_mem_v_li)
    ,.w_i(stat_mem_w_li)
    ,.addr_i(stat_mem_addr_li)
    ,.data_i(stat_mem_data_li)
    ,.w_mask_i(stat_mem_w_mask_li)
    ,.data_o(stat_mem_data_lo)
  );


  // TAG MANAGEMENT HANDLING UNIT
  bsg_cache_nb_tag_mgmt_unit #(
    .addr_width_p(addr_width_p)
    ,.word_width_p(word_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.sets_p(sets_p)
    ,.ways_p(ways_p)
  ) tag_management_handling_unit (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.mgmt_v_i(mgmt_v)

    ,.decode_v_i(decode_v_r)
    ,.addr_v_i(addr_v_r)
    ,.tag_v_i(tag_v_r)
    ,.valid_v_i(valid_v_r)
    ,.lock_v_i(lock_v_r)
    ,.tag_hit_v_i(tag_hit_v)
    ,.tag_hit_way_id_i(tag_hit_way_id_v)
    ,.tag_hit_found_i(tag_hit_found_v)

    ,.chosen_way_i(way_chooser_chosen_way_lo)

    ,.sbuf_empty_i(sbuf_empty_lo)
    ,.tbuf_empty_i(tbuf_empty_lo)

    ,.evict_v_o(mgmt_evict_v_lo)

    ,.dma_cmd_o(mgmt_dma_cmd_lo)
    ,.dma_addr_o(mgmt_dma_addr_lo)

    ,.dma_done_i(dma_mgmt_done_lo)

    ,.stat_info_i(stat_mem_data_lo)
    ,.stat_mem_v_o(mgmt_stat_mem_v_lo)
    ,.stat_mem_w_o(mgmt_stat_mem_w_lo)
    ,.stat_mem_addr_o(mgmt_stat_mem_addr_lo)
    ,.stat_mem_data_o(mgmt_stat_mem_data_lo)
    ,.stat_mem_w_mask_o(mgmt_stat_mem_w_mask_lo)

    ,.tag_mem_v_o(mgmt_tag_mem_v_lo)
    ,.tag_mem_w_o(mgmt_tag_mem_w_lo)
    ,.tag_mem_addr_o(mgmt_tag_mem_addr_lo)
    ,.tag_mem_data_o(mgmt_tag_mem_data_lo)
    ,.tag_mem_w_mask_o(mgmt_tag_mem_w_mask_lo)

    ,.track_mem_v_o(mgmt_track_mem_v_lo) 
    ,.track_mem_w_o(mgmt_track_mem_w_lo) 
    ,.track_mem_addr_o(mgmt_track_mem_addr_lo)
    ,.track_mem_w_mask_o(mgmt_track_mem_w_mask_lo)
    ,.track_mem_data_o(mgmt_track_mem_data_lo)

    //,.flush_way_o(mgmt_flush_way_lo)
    //,.chosen_way_o(mgmt_chosen_way_lo)

    //,.goto_flush_op_o(mgmt_goto_flush_op_lo)
    //,.goto_lock_op_o(mgmt_goto_lock_op_lo)
    ,.curr_way_o(mgmt_curr_way_lo)

    ,.mgmt_done_o(mgmt_done_lo)
    ,.recover_o(mgmt_recover_lo)
    ,.ack_i(mgmt_ack_li)   
  );
 
  assign mgmt_ack_li = v_o & yumi_i;

  /*******************************************************************************************/
  /*******************************************************************************************/
  /*******************************************************************************************/



  /**************************************** OUTPUT *******************************************/
  /****************************************** OR *********************************************/
  /************************************ ALLOCATE MSHR ****************************************/


  /****************** MSHR CAM *******************/
  //
  bsg_cache_nb_mshr_cam #(
    .mshr_els_p(mshr_els_p)
    ,.cache_line_offset_width_p(cache_line_offset_width_lp)
    ,.word_width_p(word_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
  ) mshr_cam (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.w_v_i(mshr_cam_w_v_li)
    ,.w_set_not_clear_i(mshr_cam_w_set_not_clear_li)
    ,.w_tag_i(mshr_cam_w_tag_li)
    ,.w_data_i(mshr_cam_w_data_li)
    ,.w_mask_i(mshr_cam_w_mask_li)
    ,.w_empty_o(mshr_cam_w_empty_lo)
    ,.r_by_tag_v_i(mshr_cam_r_by_tag_v_li)
    ,.r_tag_i(mshr_cam_r_tag_li)
    ,.r_valid_bits_o(mshr_cam_r_mask_lo)
    ,.r_by_mshr_id_v_i(mshr_cam_r_by_mshr_id_v_li)
    ,.r_mshr_id_i(mshr_cam_r_mshr_id_li)
    ,.r_data_o(mshr_cam_r_data_lo)
    ,.r_tag_match_o(mshr_cam_r_tag_match_lo)
    ,.r_match_found_o(mshr_cam_r_match_found_lo)
  );

  assign mshr_cam_w_v_li = mshr_clear 
                         ? mhu_write_fill_data_in_progress_lo & (transmitter_mhu_store_tag_miss_fill_done_lo | dma_mhu_done_lo)
                         : ( alloc_write_tag_and_stat_v
                           ? mshr_entry_allocate_encode_data_lo
                           : ( st_found_in_mshr_update_mshr_v 
                             ? mshr_cam_r_tag_match_lo
                             : '0));
  assign mshr_cam_w_set_not_clear_li = ~mshr_clear;
  assign mshr_cam_w_tag_li = mshr_clear ? '0 : addr_v_r[block_offset_width_lp+:cache_line_offset_width_lp];
  assign mshr_cam_w_data_li = (st_miss_v | st_found_in_mshr_update_mshr_v) 
                            ? ( decode_v_r.mask_op
                              ? {block_size_in_words_p{data_v_r}}
                              : {block_size_in_words_p{sbuf_data_in}}
                              )
                            : '0;
  assign mshr_cam_w_mask_li = mshr_clear 
                            ? {block_data_mask_width_lp{1'b1}} 
                            : ((st_miss_v | st_found_in_mshr_update_mshr_v)
                               ? (block_offset_decode_expand_mask & (decode_v_r.mask_op ? {block_size_in_words_p{mask_v_r}} : {block_size_in_words_p{sbuf_mask_in}}))
                               : '0
                              );
  assign mshr_cam_r_by_mshr_id_v_li = mhu_store_tag_miss_v_o_found | dma_mshr_cam_r_v_lo;
  assign mshr_cam_r_mshr_id_li = mhu_store_tag_miss_v_o_found 
                               ? mhu_store_tag_miss_mshr_id
                               : (dma_mshr_cam_r_v_lo
                                 ? dma_mshr_id_i
                                 : '0);
  //assign mshr_cam_r_by_tag_v_li = (v_v_r & ~tag_op_v) & ~mshr_cam_r_by_mshr_id_v_li; FIXME
  assign mshr_cam_r_by_tag_v_li = (v_v_r & ~tag_op_v & ~decode_v_r.atomic_op) & ~mshr_cam_r_by_mshr_id_v_li;
  assign mshr_cam_r_tag_li = addr_v_r[block_offset_width_lp+:cache_line_offset_width_lp];

  /***** SELECT VALID BITS FOR CURRENT WORD ******/
  bsg_mux #(
    .width_p(data_mask_width_lp)
    ,.els_p(block_size_in_words_p)
  ) mshr_mask_out_mux (
    .data_i(mshr_cam_r_mask_lo)
    ,.sel_i(addr_block_offset_v)
    ,.data_o(mshr_mask_out_offset_selected)
  );

  /****** SELECT MSHR DATA FOR CURRENT WORD ******/
  bsg_mux #(
    .width_p(word_width_p)
    ,.els_p(block_size_in_words_p)
  ) mshr_data_out_mux (
    .data_i(mshr_cam_r_data_lo)
    ,.sel_i(addr_block_offset_v)
    ,.data_o(mshr_data_out_offset_selected)
  ); 

  /************ MSHR MATCH ID ENCODER ************/  
  //
  bsg_priority_encode #(
    .width_p(mshr_els_p)
    ,.lo_to_hi_p(1)
  ) alloc_or_update_mshr_id_encode (
    .i(mshr_match_found_v ? mshr_cam_r_tag_match_lo : mshr_cam_w_empty_lo)
    ,.addr_o(alloc_or_update_mshr_id_lo)
    ,.v_o()
  ); 

  /******* MSHR ENTRY ALLOC INDEX ENCODER ********/
  //
  bsg_priority_encode_one_hot_out #(
    .width_p(safe_mshr_els_lp)
    ,.lo_to_hi_p(1)
  ) mshr_entry_allocate_encoder (
    .i(mshr_cam_w_empty_lo)
    ,.o(mshr_entry_allocate_encode_data_lo)
    ,.v_o(mshr_entry_allocate_v_lo)
  );


  /************** MSHR ORDER QUEUE ****************/
  // one hot
  bsg_fifo_1r1w_small #(
    .width_p(safe_mshr_els_lp)
    ,.els_p(safe_mshr_els_lp)
  ) mshr_order_queue (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.data_i(mshr_entry_allocate_encode_data_lo)
    ,.v_i(alloc_write_tag_and_stat_v)
    ,.ready_o(mshr_order_queue_ready_lo)
    ,.v_o(mshr_order_queue_v_lo)
    ,.data_o(mshr_order_queue_data_lo)
    ,.yumi_i(mshr_order_queue_yumi_li)
  );

  assign mshr_order_queue_yumi_li = mshr_order_queue_v_lo & mhu_req_ready;


  /*************** MISS HANDLING UNIT ****************/
  //
  for(genvar i = 0; i < safe_mshr_els_lp; i++) begin: mhu

    bsg_cache_nb_mhu #(
      .addr_width_p(addr_width_p)
      ,.word_width_p(word_width_p)
      ,.block_size_in_words_p(block_size_in_words_p)
      ,.sets_p(sets_p)
      ,.ways_p(ways_p)
      ,.mshr_els_p(mshr_els_p)
    ) miss_handling_units (
      .clk_i(clk_i)
      ,.reset_i(reset_i)

      ,.mhu_we_i(mhu_we_li[i])
      ,.mhu_activate_i(mhu_activate_li[i])

      ,.mshr_stm_miss_i(mhu_mshr_stm_miss_li[i])
      ,.mshr_stm_miss_o(mhu_mshr_stm_miss_lo[i])

      //FIXME,.mhu_read_tag_and_stat_v_o(mhu_read_tag_and_stat_v_lo[i])
      //FIXME,.mhu_read_track_v_o(mhu_read_track_v_lo[i])
      //FIXME,.mhu_write_tag_and_stat_v_o(mhu_write_tag_and_stat_v_lo[i])
      //FIXME,.mhu_write_track_v_o(mhu_write_track_v_lo[i])

      ,.store_tag_miss_op_i(1'b0) //FIXME
      ,.track_miss_i(1'b0)  //FIXME
      //,.decode_v_i(decode_v_r)
      ,.addr_v_i(addr_v_r)
      ,.tag_hit_way_id_i(tag_hit_way_id_v)
      ,.tag_v_i(tag_v_r)
      ,.valid_v_i(valid_v_r)

      ,.chosen_way_i(way_chooser_chosen_way_lo)
      ,.chosen_way_o(mhu_chosen_way_lo[i])

      ,.sbuf_or_tbuf_chosen_way_found_i(transmitter_sbuf_or_tbuf_chosen_way_found_li[i])

      ,.dma_cmd_o(mhu_dma_cmd_lo[i])
      ,.dma_addr_o(mhu_dma_addr_lo[i])

      ,.curr_addr_index_o(mhu_curr_addr_index_lo[i])
      ,.curr_addr_tag_o(mhu_curr_addr_tag_lo[i])

      ,.dma_done_i(dma_mhu_done_lo[i])
      ,.transmitter_store_tag_miss_fill_done_i(transmitter_mhu_store_tag_miss_fill_done_lo[i])

      ,.stat_info_i(stat_mem_data_lo)

      //,.recover_ack_i(mhu_recover_ack_li[i])
      //,.recover_o(mhu_recover_lo[i]) //FIXME // For now we basically don't need to recover anything

      ,.store_tag_miss_op_o(mhu_store_tag_miss_op_lo[i])
      ,.track_miss_o(mhu_track_miss_lo[i])

      //FIXME,.track_mem_data_tl_i(track_mem_data_lo)
      //FIXME,.track_data_way_picked_o(mhu_track_data_way_picked_lo[i])

      ,.evict_v_o(mhu_evict_v_lo[i])
      ,.store_tag_miss_fill_v_o(mhu_store_tag_miss_fill_v_lo[i])

      ,.write_fill_data_in_progress_o(mhu_write_fill_data_in_progress_lo[i])
      ,.mhu_req_busy_o(mhu_req_busy_lo[i])
    );
  
  assign mhu_we_li[i] = alloc_write_tag_and_stat_v & (i==alloc_or_update_mshr_id_lo);
  assign mhu_activate_li[i] = mshr_order_queue_v_lo & mshr_order_queue_data_lo[i] & mhu_req_ready;
  assign mhu_mshr_stm_miss_li[i] = ( ld_found_in_mshr_alloc_read_miss_entry_v 
                                   & (mhu_store_tag_miss_op_lo[alloc_or_update_mshr_id_lo]
                                     & ~mhu_mshr_stm_miss_lo[alloc_or_update_mshr_id_lo]) // FIXME: this line could prolly be omitted
                                   ) 
                                 | ( st_found_in_mshr_update_mshr_v
                                   //& ~mshr_found_and_hit_in_track_v
                                   & ~mshr_hit
                                   & (mhu_store_tag_miss_op_lo[alloc_or_update_mshr_id_lo]
                                     & ~mhu_mshr_stm_miss_lo[alloc_or_update_mshr_id_lo]) // FIXME: this line could prolly be omitted)
                                   & partial_st_v
                                   );
  assign transmitter_sbuf_or_tbuf_chosen_way_found_li[i] = (~tbuf_empty_lo & 
                                                            (( tbuf_el0_valid_snoop_lo
                                                             & tbuf_el0_way_snoop_lo == mhu_chosen_way_lo[i]
                                                             & tbuf_el0_addr_snoop_lo[block_offset_width_lp+:lg_sets_lp] == mhu_curr_addr_index_lo[i]
                                                             )
                                                            |( tbuf_el1_valid_snoop_lo
                                                             & tbuf_el1_way_snoop_lo == mhu_chosen_way_lo[i]
                                                             & tbuf_el1_addr_snoop_lo[block_offset_width_lp+:lg_sets_lp] == mhu_curr_addr_index_lo[i]
                                                             ))
                                                           ) 
                                                         | (~sbuf_empty_lo & 
                                                            (( sbuf_el0_valid_snoop_lo
                                                             & sbuf_el0_way_snoop_lo == mhu_chosen_way_lo[i]
                                                             & sbuf_el0_addr_snoop_lo[block_offset_width_lp+:lg_sets_lp] == mhu_curr_addr_index_lo[i]
                                                             )
                                                            |( sbuf_el1_valid_snoop_lo
                                                             & sbuf_el1_way_snoop_lo == mhu_chosen_way_lo[i]
                                                             & sbuf_el1_addr_snoop_lo[block_offset_width_lp+:lg_sets_lp] == mhu_curr_addr_index_lo[i]
                                                             ))
                                                           );
  
  end                       

  assign mhu_req_ready = ~(|mhu_req_busy_lo);

  bsg_priority_encode #(
    .width_p(mshr_els_p)
    ,.lo_to_hi_p(1)
  ) mhu_evict_mshr_id_encode (
    .i(mhu_evict_v_lo)
    ,.addr_o(mhu_evict_mshr_id)
    ,.v_o(mhu_evict_v_o_found)
  );

  bsg_priority_encode #(
    .width_p(mshr_els_p)
    ,.lo_to_hi_p(1)
  ) mhu_store_tag_miss_mshr_id_encode (
    .i(mhu_store_tag_miss_fill_v_lo)
    ,.addr_o(mhu_store_tag_miss_mshr_id)
    ,.v_o(mhu_store_tag_miss_v_o_found)
  );

   bsg_priority_encode #(
    .width_p(mshr_els_p)
    ,.lo_to_hi_p(1)
   ) mhu_fill_done_mshr_id_encode (
    .i(mhu_write_fill_data_in_progress_lo & (transmitter_mhu_store_tag_miss_fill_done_lo | dma_mhu_done_lo))
    ,.addr_o(mshr_clear_id)
    ,.v_o(mshr_clear)
  ); 

   bsg_priority_encode #(
    .width_p(mshr_els_p)
    ,.lo_to_hi_p(1)
   ) mhu_req_busy_encode (
    .i(mhu_req_busy_lo)
    ,.addr_o(mhu_req_mshr_id)
    ,.v_o(mhu_req_exist)
  ); 

  bsg_decode_with_v #(
    .num_out_p(ways_p)
  ) mhu_chosen_way_demux (
    .i(mhu_chosen_way_lo[dma_mshr_id_i])
    ,.v_i(dma_mshr_cam_r_v_lo)
    ,.o(mhu_chosen_way_decode)
  );

  /************ WAY CHOOSER FOR MHU/MGMT *************/
  //
  bsg_cache_nb_miss_fill_way_chooser #(
    //.addr_width_p(addr_width_p)
    //,.word_width_p(word_width_p)
    //,.block_size_in_words_p(block_size_in_words_p)
    .sets_p(sets_p)
    ,.ways_p(ways_p)
  ) mhu_way_chooser (
    .addr_index_i(addr_index_v)
    ,.valid_i(valid_v_r)
    ,.lock_i(lock_v_r)

    ,.stat_info_i(stat_mem_data_lo)

    ,.dma_refill_in_progress_i(dma_refill_in_progress_lo)
    ,.dma_refill_addr_index_i(dma_refill_addr_index_lo)
    ,.dma_refill_way_i(dma_refill_way_lo)

    ,.transmitter_store_tag_miss_fill_in_progress_i(transmitter_store_tag_miss_fill_in_progress_lo)
    ,.transmitter_store_tag_miss_fill_addr_index_i(transmitter_current_addr_index_lo)
    ,.transmitter_store_tag_miss_fill_way_i(transmitter_current_way_lo)    

    ,.chosen_way_o(way_chooser_chosen_way_lo)
    ,.no_available_way_o(way_chooser_no_available_way_lo)
  );

  bsg_decode #(
    .num_out_p(ways_p)
  ) alloc_chosen_way_demux (
    .i(way_chooser_chosen_way_lo)
    ,.o(alloc_chosen_way_decode)
  );

  /**************** READ MISS QUEUE ******************/
  //
  bsg_cache_nb_read_miss_queue #(
    .block_size_in_words_p(block_size_in_words_p)
    ,.word_width_p(word_width_p)
    ,.src_id_width_p(src_id_width_p)
    ,.mshr_els_p(mshr_els_p)
    ,.read_miss_els_per_mshr_p(read_miss_els_per_mshr_p)
  ) read_miss_queue (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.mshr_id_i(read_miss_queue_mshr_id_li)   
    ,.v_i(read_miss_queue_v_li)
    ,.ready_o(read_miss_queue_ready_lo)
    ,.write_not_read_i(read_miss_queue_write_not_read_li)

    ,.src_id_i(src_id_v_r)
    ,.word_offset_i(addr_block_offset_v)
    ,.mask_op_i(decode_v_r.mask_op)
    ,.mask_i(mask_v_r)
    ,.size_op_i(decode_v_r.data_size_op)
    ,.sigext_op_i(decode_v_r.sigext_op)
    ,.byte_sel_i(addr_byte_sel_v)
    ,.mshr_data_i(mshr_data_out_offset_selected)
    ,.mshr_data_mask_i(mshr_mask_out_offset_selected)

    ,.src_id_o(read_miss_queue_src_id_lo)
    ,.word_offset_o(read_miss_queue_word_offset_lo)
    ,.mask_op_o(read_miss_queue_mask_op_lo)
    ,.mask_o(read_miss_queue_mask_lo)
    ,.size_op_o(read_miss_queue_size_op_lo)
    ,.sigext_op_o(read_miss_queue_sigext_op_lo)
    ,.byte_sel_o(read_miss_queue_byte_sel_lo)
    ,.mshr_data_o(read_miss_queue_mshr_data_lo)
    ,.mshr_data_mask_o(read_miss_queue_mshr_data_mask_lo)
 
    ,.v_o(read_miss_queue_v_lo)
    ,.yumi_i(yumi_i)

    ,.read_done_o(read_miss_queue_read_done_lo)
    ,.read_in_progress_o(read_miss_queue_read_in_progress_lo)
   );   

  assign read_miss_queue_mshr_id_li = dma_serve_read_miss_queue_v_lo
                                    ? dma_refill_mshr_id_lo
                                    : alloc_or_update_mshr_id_lo;
  assign read_miss_queue_v_li = (dma_serve_read_miss_queue_v_lo & ~read_miss_queue_read_done_lo)
                              | ((ld_found_in_mshr_alloc_read_miss_entry_v & read_miss_queue_ready_lo[alloc_or_update_mshr_id_lo])
                                |(ld_miss_v & alloc_write_tag_and_stat_v));
  assign read_miss_queue_write_not_read_li = ~dma_serve_read_miss_queue_v_lo;

  /***************** store buffer ********************/
  //
  bsg_cache_nb_sbuf_snoop #(
    .word_width_p(word_width_p)
    ,.addr_width_p(addr_width_p)
    ,.ways_p(ways_p)
  ) sbuf (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.sbuf_entry_i(sbuf_entry_li)
    ,.v_i(sbuf_v_li)

    ,.sbuf_entry_o(sbuf_entry_lo)
    ,.v_o(sbuf_v_lo)
    ,.yumi_i(sbuf_yumi_li)

    ,.empty_o(sbuf_empty_lo)
    ,.full_o(sbuf_full_lo)

    ,.bypass_addr_i(sbuf_bypass_addr_li)
    ,.bypass_v_i(sbuf_bypass_v_li)
    ,.bypass_data_o(bypass_data_lo)
    ,.bypass_mask_o(bypass_mask_lo)

    ,.el0_addr_snoop_o(sbuf_el0_addr_snoop_lo)
    ,.el0_way_snoop_o(sbuf_el0_way_snoop_lo)
    ,.el0_valid_snoop_o(sbuf_el0_valid_snoop_lo)

    ,.el1_addr_snoop_o(sbuf_el1_addr_snoop_lo)
    ,.el1_way_snoop_o(sbuf_el1_way_snoop_lo)
    ,.el1_valid_snoop_o(sbuf_el1_valid_snoop_lo)
  ); 

  bsg_decode #(
    .num_out_p(ways_p)
  ) sbuf_way_demux (
    .i(sbuf_entry_lo.way_id)
    ,.o(sbuf_way_decode)
  );
  

  // assign sbuf_burst_offset = (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]
  //                          -(2*burst_size_in_words_lp*(sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]/(2*burst_size_in_words_lp)))
  //                          )/2;

  assign sbuf_burst_offset = sbuf_entry_lo.addr[(lg_data_mask_width_lp+1)+:lg_burst_size_in_words_lp];

  bsg_decode #(
    .num_out_p(burst_size_in_words_lp)
  ) sbuf_bo_demux (
    .i(sbuf_burst_offset) 
    ,.o(sbuf_burst_offset_decode)
  );

  bsg_expand_bitmask #(
    .in_width_p(burst_size_in_words_lp)
    ,.expand_p(data_mask_width_lp)
  ) expand0 (
    .i(sbuf_burst_offset_decode)
    ,.o(sbuf_expand_mask)
  );

  for (genvar i = 0 ; i < ways_p; i++) begin: sbuf_gen
    assign sbuf_data_mem_data[i] = {burst_size_in_words_lp{sbuf_entry_lo.data}};
    assign sbuf_data_mem_w_mask[i] = sbuf_way_decode[i]
      ? (sbuf_expand_mask & {burst_size_in_words_lp{sbuf_entry_lo.mask}})
      : '0;
  end
  if (num_of_burst_per_bank_lp == 1) begin
    assign sbuf_data_mem_addr = sbuf_entry_lo.addr[block_offset_width_lp+:lg_sets_lp];
  end 
  else if (num_of_burst_per_bank_lp == num_of_words_per_bank_lp) begin
    assign sbuf_data_mem_addr = sbuf_entry_lo.addr[(lg_data_mask_width_lp+1)+:(sbuf_data_mem_addr_offset_lp-1)];
  end
  else begin
    assign sbuf_data_mem_addr = sbuf_entry_lo.addr[(lg_data_mask_width_lp+lg_burst_size_in_words_lp+1)+:(sbuf_data_mem_addr_offset_lp-1)];
  end
  
  assign sbuf_v_li = v_v_r 
                   & ( decode_v_r.atomic_op
                     | ( decode_v_r.st_op
                       & ((tag_hit_found_v & ~mshr_match_found_v)
                         | st_found_in_mshr_update_sbuf_and_tbuf_v) 
                       )
                     )
                   & v_o & yumi_i;
  assign sbuf_entry_li.way_id = tag_hit_way_id_v;
  assign sbuf_entry_li.addr = addr_v_r;
  // store buffer can write to dmem when
  // 1) there is valid entry in store buffer.
  // 2) incoming request does not read the bank that sbuf wants to write.
  // 3) there's no conflict with transmitter's priority for even/odd bank.
  // 4) TL read DMEM (and bypass from sbuf), and TV is not stalled (v_we).
  assign sbuf_yumi_li = sbuf_v_lo
    & ~(((sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]%2==0 && ld_even_bank)
        | (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]%2!=0 && ld_odd_bank))
        & yumi_o)
    & ~(v_tl_r & (decode_tl_r.ld_op | decode_tl_r.atomic_op) & (~v_we) & (~(mgmt_v | ld_miss_v | st_miss_v)))
    & ~(transmitter_even_fifo_priority_lo & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]%2==0))
    & ~(transmitter_odd_fifo_priority_lo & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]%2!=0)); 

  assign sbuf_bypass_addr_li = addr_tl_r;
  assign sbuf_bypass_v_li = (decode_tl_r.ld_op | decode_tl_r.atomic_op) & v_tl_r & v_we;

  // store buffer data/mask input
  bsg_mux #(
    .width_p(word_width_p)
    ,.els_p(data_sel_mux_els_lp)
  ) sbuf_data_in_mux (
    .data_i(sbuf_data_in_mux_li)
    ,.sel_i(decode_v_r.data_size_op[0+:lg_data_sel_mux_els_lp])
    ,.data_o(sbuf_data_in)
  );

  bsg_mux #(
    .width_p(data_mask_width_lp)
    ,.els_p(data_sel_mux_els_lp)
  ) sbuf_mask_in_mux (
    .data_i(sbuf_mask_in_mux_li)
    ,.sel_i(decode_v_r.data_size_op[0+:lg_data_sel_mux_els_lp])
    ,.data_o(sbuf_mask_in)
  );

  //
  // Atomic operations
  //   Defined only for 32/64 operations
  // Data incoming from cache_pkt
  
  logic [`BSG_MIN(word_width_p, 64)-1:0] atomic_reg_data;
  // Data read from the cache line
  logic [`BSG_MIN(word_width_p, 64)-1:0] atomic_mem_data;
  // Result of the atomic
  logic [`BSG_MIN(word_width_p, 64)-1:0] atomic_alu_result;
  // Final atomic data for store buffer
  logic [`BSG_MIN(word_width_p, 64)-1:0] atomic_result;

  // Shift data to high bits for operations less than 64-bits
  // This allows us to share the arithmetic operators for 32/64 bit atomics
  if (word_width_p >= 64) begin : atomic_64
    wire [63:0] amo32_reg_in = data_v_r[0+:32] << 32;
    wire [63:0] amo64_reg_in = data_v_r[0+:64];
    assign atomic_reg_data = decode_v_r.data_size_op[0] ? amo64_reg_in : amo32_reg_in;

    wire [63:0] amo32_mem_in = ld_data_final_li[2][0+:32] << 32;
    wire [63:0] amo64_mem_in = ld_data_final_li[3][0+:64];
    assign atomic_mem_data = decode_v_r.data_size_op[0] ? amo64_mem_in : amo32_mem_in;
  end
  else if (word_width_p >= 32) begin : atomic_32
    assign atomic_reg_data = data_v_r[0+:32];
    assign atomic_mem_data = ld_data_final_li[2];
  end

  // Atomic ALU
  always_comb begin
    // This logic was confirmed not to synthesize unsupported operators in
    //   Synopsys DC O-2018.06-SP4
    unique casez({amo_support_p[decode_v_r.amo_subop], decode_v_r.amo_subop})
      {1'b1, e_cache_amo_swap}: atomic_alu_result = atomic_reg_data;
      {1'b1, e_cache_amo_and }: atomic_alu_result = atomic_reg_data & atomic_mem_data;
      {1'b1, e_cache_amo_or  }: atomic_alu_result = atomic_reg_data | atomic_mem_data;
      {1'b1, e_cache_amo_xor }: atomic_alu_result = atomic_reg_data ^ atomic_mem_data;
      {1'b1, e_cache_amo_add }: atomic_alu_result = atomic_reg_data + atomic_mem_data;
      {1'b1, e_cache_amo_min }: atomic_alu_result =
          ($signed(atomic_reg_data) < $signed(atomic_mem_data)) ? atomic_reg_data : atomic_mem_data;
      {1'b1, e_cache_amo_max }: atomic_alu_result =
          ($signed(atomic_reg_data) > $signed(atomic_mem_data)) ? atomic_reg_data : atomic_mem_data;
      {1'b1, e_cache_amo_minu}: atomic_alu_result =
          (atomic_reg_data < atomic_mem_data) ? atomic_reg_data : atomic_mem_data;
      {1'b1, e_cache_amo_maxu}: atomic_alu_result =
          (atomic_reg_data > atomic_mem_data) ? atomic_reg_data : atomic_mem_data;
      // Noisily fail in simulation if an unsupported AMO operation is requested
      {1'b0, 4'b????         }: atomic_alu_result = `BSG_UNDEFINED_IN_SIM(0);
      default: atomic_alu_result = '0;
    endcase
  end

  // Shift data from high bits for operations less than 64-bits
  if (word_width_p >= 64) begin : fi
    wire [63:0] amo32_out = atomic_alu_result >> 32;
    wire [63:0] amo64_out = atomic_alu_result;
    assign atomic_result = decode_v_r.data_size_op[0] ? amo64_out : amo32_out;
  end
  else begin
    assign atomic_result = atomic_alu_result;
  end


  for (genvar i = 0; i < data_sel_mux_els_lp; i++) begin: sbuf_in_sel
    localparam slice_width_lp = (8*(2**i));

    logic [slice_width_lp-1:0] slice_data;

    // AMO computation
    // AMOs are only supported for words and double words 
    if ((i == 2'b10) || (i == 2'b11)) begin: atomic_in_sel
      assign slice_data = decode_v_r.atomic_op
        ? atomic_result[0+:slice_width_lp]
        : data_v_r[0+:slice_width_lp];
    end 
    else begin
      assign slice_data = data_v_r[0+:slice_width_lp];
    end
    

    //assign slice_data = data_v_r[0+:slice_width_lp];
    assign sbuf_data_in_mux_li[i] = {(word_width_p/slice_width_lp){slice_data}};

      logic [(word_width_p/slice_width_lp)-1:0] decode_lo;

      bsg_decode #(
        .num_out_p(word_width_p/slice_width_lp)
      ) dec (
        .i(addr_v_r[i+:`BSG_MAX(lg_data_mask_width_lp-i,1)])
        ,.o(decode_lo)
      );

      bsg_expand_bitmask #(
        .in_width_p(word_width_p/slice_width_lp)
        ,.expand_p(2**i)
      ) exp (
        .i(decode_lo)
        ,.o(sbuf_mask_in_mux_li[i])
      );

  end

  // store buffer data,mask input
  always_comb begin
    if (decode_v_r.mask_op) begin
      sbuf_entry_li.data = data_v_r;
      sbuf_entry_li.mask = mask_v_r;
    end
    else begin
      sbuf_entry_li.data = sbuf_data_in; 
      sbuf_entry_li.mask = sbuf_mask_in;
    end
  end
 

  /***************** track buffer ********************/
  //
  if (word_tracking_p) begin : tbuf_gen
    bsg_cache_nb_tbuf_snoop #(
    .word_width_p(word_width_p)
    ,.addr_width_p(addr_width_p)
    ,.ways_p(ways_p)
    ) tbuf (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.addr_i(tbuf_addr_li)
    ,.way_i(tbuf_way_li)
    ,.v_i(tbuf_v_li)

    ,.addr_o(tbuf_addr_lo)
    ,.way_o(tbuf_way_lo)
    ,.v_o(tbuf_v_lo)
    ,.yumi_i(tbuf_yumi_li)

    ,.empty_o(tbuf_empty_lo)
    ,.full_o(tbuf_full_lo)

    ,.bypass_addr_i(tbuf_bypass_addr_li)
    ,.bypass_v_i(tbuf_bypass_v_li)
    ,.bypass_track_o(bypass_track_lo)

    ,.el0_addr_snoop_o(tbuf_el0_addr_snoop_lo)
    ,.el0_way_snoop_o(tbuf_el0_way_snoop_lo)
    ,.el0_valid_snoop_o(tbuf_el0_valid_snoop_lo) 

    ,.el1_addr_snoop_o(tbuf_el1_addr_snoop_lo)
    ,.el1_way_snoop_o(tbuf_el1_way_snoop_lo)
    ,.el1_valid_snoop_o(tbuf_el1_valid_snoop_lo)
    );
  end
  else begin
    assign tbuf_v_lo = 1'b0;
    assign tbuf_empty_lo = 1'b1;
    assign tbuf_full_lo = 1'b0;
    assign bypass_track_lo = 1'b0;
  end

  // bsg_decode #(
  //   .num_out_p(ways_p)
  // ) tbuf_way_demux (
  //   .i(tbuf_way_lo)
  //   ,.o(tbuf_way_decode)
  // );

  // bsg_decode #(
  //   .num_out_p(block_size_in_words_p)
  // ) tbuf_wo_demux (
  //   .i(tbuf_addr_lo[lg_data_mask_width_lp+:lg_block_size_in_words_lp])
  //   ,.o(tbuf_word_offset_decode)
  // );

  // assign tbuf_track_mem_addr = tbuf_addr_lo[block_offset_width_lp+:lg_sets_lp];
  // for (genvar i = 0 ; i < ways_p; i++) begin
  //   assign tbuf_track_mem_data[i] = {block_size_in_words_p{1'b1}};
  //   assign tbuf_track_mem_w_mask[i] = tbuf_way_decode[i] ? tbuf_word_offset_decode : {block_size_in_words_p{1'b0}};
  // end

  // assign tbuf_v_li = (decode_v_r.st_op & ~partial_st_v) & v_o & yumi_i;
  // assign tbuf_way_li = tag_hit_way_id_v;
  // assign tbuf_addr_li = addr_v_r;


  // output stage
  //
  logic [dma_data_width_p-1:0] ld_data_way_picked;
  logic [word_width_p-1:0] ld_data_offset_picked;
  logic [word_width_p-1:0] bypass_data_masked;
  logic [word_width_p-1:0] ld_data_combined_with_mshr_data;
  logic [word_width_p-1:0] dma_snoop_data_combined_with_mshr_data;
  logic [word_width_p-1:0] dma_snoop_data_combined_with_mshr_data_bypassed;
  logic [word_width_p-1:0] ld_data_masked;
  logic [word_width_p-1:0] expanded_mask;

  bsg_mux #(
    .width_p(dma_data_width_p)
    ,.els_p(ways_p)
  ) ld_data_mux (
    .data_i(ld_data_v_r)
    ,.sel_i(tag_hit_way_id_v)
    ,.data_o(ld_data_way_picked)
  );

  bsg_mux #(
    .width_p(word_width_p)
    ,.els_p(burst_size_in_words_lp)
  ) mux00 (
    .data_i(ld_data_way_picked)
    ,.sel_i(addr_v_r[(lg_data_mask_width_lp+1)+:lg_burst_size_in_words_lp])
    ,.data_o(ld_data_offset_picked)
  );

  bsg_mux_segmented #(
    .segments_p(data_mask_width_lp)
    ,.segment_width_p(8)
  ) bypass_mux_segmented (
    .data0_i(ld_data_offset_picked)
    ,.data1_i(bypass_data_lo)
    ,.sel_i(bypass_mask_lo)
    ,.data_o(bypass_data_masked)
  );
  
  bsg_mux_segmented #(
    .segments_p(data_mask_width_lp)
    ,.segment_width_p(8)
  ) ld_data_combine_with_mshr_data (
    .data0_i(bypass_data_masked)
    ,.data1_i(mshr_data_out_offset_selected)
    ,.sel_i(mshr_mask_out_offset_selected)
    ,.data_o(ld_data_combined_with_mshr_data)
  );  

  bsg_mux_segmented #(
    .segments_p(data_mask_width_lp)
    ,.segment_width_p(8)
  ) snoop_data_combine_with_mshr_data_for_ld_ato_mshr_dma_hit (
    .data0_i(dma_snoop_word_lo)
    ,.data1_i(mshr_data_out_offset_selected)
    ,.sel_i(mshr_mask_out_offset_selected)
    ,.data_o(dma_snoop_data_combined_with_mshr_data)
  );  

  bsg_mux_segmented #(
    .segments_p(data_mask_width_lp)
    ,.segment_width_p(8)
  ) snoop_combined_with_mshr_bypass_segmented (
    .data0_i(dma_snoop_data_combined_with_mshr_data)
    ,.data1_i(bypass_data_lo)
    ,.sel_i(bypass_mask_lo)
    ,.data_o(dma_snoop_data_combined_with_mshr_data_bypassed)
  );

  always_comb begin
    if (read_miss_queue_read_in_progress_lo | atom_miss_v) begin
      snoop_or_ld_data = dma_snoop_word_lo;
    end else if (ld_found_in_mshr_output_ld_data_v) begin
      snoop_or_ld_data = bypass_data_masked;
    end else if (ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_v) begin
      snoop_or_ld_data = dma_snoop_data_combined_with_mshr_data;
    end else if (ld_found_in_mshr_output_dma_snoop_combined_with_mshr_data_and_sbuf_bypass) begin
      snoop_or_ld_data = dma_snoop_data_combined_with_mshr_data_bypassed;
    end else if (ld_found_in_mshr_and_hit_in_track_data_v) begin
      snoop_or_ld_data = ld_data_combined_with_mshr_data;
    end else if (ld_found_in_mshr_output_mshr_data_v) begin
      snoop_or_ld_data = mshr_data_out_offset_selected;
    end else begin
      snoop_or_ld_data = bypass_data_masked;
    end
  end
  

  bsg_expand_bitmask #(
    .in_width_p(data_mask_width_lp) 
    ,.expand_p(8)
  ) mask_expand (
    .i(read_miss_queue_read_in_progress_lo ? read_miss_queue_mask_lo : mask_v_r)
    ,.o(expanded_mask)
  );

  assign ld_data_masked = snoop_or_ld_data & expanded_mask;

  // select double/word/half/byte load data
  //

  for (genvar i = 0; i < data_sel_mux_els_lp; i++) begin: ld_data_sel

      logic [(8*(2**i))-1:0] byte_sel;

      bsg_mux #(
        .width_p(8*(2**i))
        ,.els_p(word_width_p/(8*(2**i)))
      ) byte_mux (
        .data_i(snoop_or_ld_data)
        ,.sel_i( read_miss_queue_read_in_progress_lo 
               ? ((i==(data_sel_mux_els_lp-1))
                 ? 1'b0
                 : read_miss_queue_byte_sel_lo[i+:`BSG_MAX(lg_data_mask_width_lp-i,1)])
               : addr_v_r[i+:`BSG_MAX(lg_data_mask_width_lp-i,1)])
        ,.data_o(byte_sel)
      );

      assign ld_data_final_li[i] = 
        {{(word_width_p-(8*(2**i))){(read_miss_queue_read_in_progress_lo 
                                    ? read_miss_queue_sigext_op_lo 
                                    : decode_v_r.sigext_op) & byte_sel[(8*(2**i))-1]}}, byte_sel};

  end
  
  bsg_mux #(
    .width_p(word_width_p)
    ,.els_p(data_sel_mux_els_lp)
  ) ld_data_size_mux (
    .data_i(ld_data_final_li)
    ,.sel_i(read_miss_queue_read_in_progress_lo
           ? read_miss_queue_size_op_lo[0+:lg_data_sel_mux_els_lp]
           : decode_v_r.data_size_op[0+:lg_data_sel_mux_els_lp])
    ,.data_o(ld_data_final_lo)
  );

  // final output mux
  always_comb begin

    if (read_miss_queue_read_in_progress_lo) begin
      if(read_miss_queue_mask_op_lo) begin
        data_o = ld_data_masked;
      end else begin
        data_o = ld_data_final_lo;
      end
    end 
    else if (v_v_r & return_val_op_v) begin
      if (decode_v_r.taglv_op) begin
        data_o = {{(word_width_p-2){1'b0}}, lock_v_r[addr_way_v], valid_v_r[addr_way_v]};
      end
      else if (decode_v_r.tagla_op) begin
        data_o = {tag_v_r[addr_way_v], {(sets_p>1){addr_index_v}}, {(block_offset_width_lp){1'b0}}};
      end
      else if (decode_v_r.mask_op) begin
        data_o = ld_data_masked;
      end
      else if (ld_found_in_mshr_alloc_read_miss_entry_v | ld_miss_v) begin
        data_o = '0;
      end
      else begin
        data_o = ld_data_final_lo;
      end
    end
    else begin
      data_o = '0;
    end 

    if (read_miss_queue_read_in_progress_lo) begin
      src_id_o = read_miss_queue_src_id_lo;
    end
    else if(v_v_r & return_val_op_v) begin
      if(ld_found_in_mshr_alloc_read_miss_entry_v | ld_miss_v) begin
        src_id_o = '0;
      end else begin
        src_id_o = src_id_v_r;
      end
    end else begin
      src_id_o = '0;
    end

  end 

  /*******************************************************************************************/
  /*******************************************************************************************/
  /*******************************************************************************************/



  /****************************************** DMA ********************************************/
  /****************************************** AND ********************************************/
  /******************************* EVICT/FILL DATA TRANSMITTER *******************************/

  bsg_cache_nb_dma #(
    .addr_width_p(addr_width_p)
    ,.word_width_p(word_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.sets_p(sets_p)
    ,.ways_p(ways_p)
    ,.dma_data_width_p(dma_data_width_p)
    ,.mshr_els_p(mshr_els_p)
  ) DMA (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.mgmt_v_i(mgmt_v)

    ,.mhu_or_mgmt_cmd_i(dma_cmd_li)   
    ,.mhu_or_mgmt_req_addr_i(dma_req_addr_li)
    ,.mhu_req_mshr_id_i(dma_req_mshr_id_li)
    ,.track_mem_data_tl_way_picked_i({block_size_in_words_p{1'b1}}) //FIXME

    ,.mhu_refill_track_miss_i(dma_refill_track_miss_li)
   
    ,.mhu_refill_track_data_way_picked_i({block_size_in_words_p{1'b1}}) //FIXME: dma_refill_track_data_way_picked_li
    ,.mhu_refill_way_i(dma_refill_way_li)
    ,.mhu_refill_addr_index_i(dma_refill_addr_index_li)

    ,.mhu_write_fill_data_in_progress_i(mhu_write_fill_data_in_progress_lo)
    ,.transmitter_mhu_store_tag_miss_done_i(transmitter_mhu_store_tag_miss_fill_done_lo)
    ,.mhu_dma_done_o(dma_mhu_done_lo)
    ,.mgmt_dma_done_o(dma_mgmt_done_lo)

    ,.addr_block_offset_v_i(addr_block_offset_v)
    ,.dma_refill_data_in_counter_o(dma_refill_data_in_counter_lo)

    ,.snoop_word_o(dma_snoop_word_lo)
    ,.serve_read_miss_queue_v_o(dma_serve_read_miss_queue_v_lo)
    ,.read_miss_queue_word_offset_i(read_miss_queue_word_offset_lo)
    ,.read_miss_queue_mshr_data_i(read_miss_queue_mshr_data_lo)
    ,.read_miss_queue_mshr_data_mask_i(read_miss_queue_mshr_data_mask_lo)

    ,.read_miss_queue_serve_v_i(dma_read_miss_queue_serve_v_li)
    ,.read_miss_queue_read_in_progress_i(read_miss_queue_read_in_progress_lo)

    ,.dma_pkt_o(dma_pkt_o)
    ,.dma_pkt_v_o(dma_pkt_v_o)
    ,.dma_pkt_yumi_i(dma_pkt_yumi_i)

    ,.dma_data_i(dma_data_i)
    ,.dma_refill_mshr_id_i(dma_mshr_id_i)  
    ,.dma_data_v_i(dma_data_v_i)
    ,.dma_data_ready_o(dma_data_ready_o)
    ,.dma_refill_hold_i(dma_refill_hold_li)
    ,.dma_refill_mshr_id_o(dma_refill_mshr_id_lo)

    ,.addr_v_i(addr_v_r)
    ,.mgmt_chosen_way_i(mgmt_curr_way_lo)

    ,.mshr_data_i(mshr_cam_r_data_lo)
    ,.mshr_data_byte_mask_i(mshr_cam_r_mask_lo)
    ,.mshr_cam_r_v_o(dma_mshr_cam_r_v_lo)

    ,.dma_data_o(dma_data_o)
    ,.dma_data_v_o(dma_data_v_o)
    ,.dma_data_yumi_i(dma_data_yumi_i)

    ,.transmitter_refill_ready_i(transmitter_refill_ready_lo)
    ,.transmitter_refill_data_o(dma_refill_data_lo)
    ,.transmitter_track_miss_o(dma_refill_track_miss_lo)
    ,.transmitter_track_data_way_picked_o(dma_refill_track_data_way_picked_lo)
    ,.transmitter_refill_v_o(dma_refill_v_lo)
    ,.transmitter_refill_way_o(dma_refill_way_lo)
    ,.transmitter_refill_addr_index_o(dma_refill_addr_index_lo)
    ,.transmitter_refill_mshr_data_byte_mask_o(dma_refill_mshr_data_byte_mask_lo)
    ,.transmitter_refill_done_i(transmitter_refill_done_lo)

    // This could later be used for optimization for st dma hit case to reduce stall cycles
    ,.dma_refill_data_out_to_sipo_counter_o(dma_refill_data_out_to_sipo_counter_lo) 
    ,.dma_refill_data_in_done_o(dma_refill_data_in_done_lo)
    ,.dma_refill_in_progress_o(dma_refill_in_progress_lo)
    ,.transmitter_refill_done_o(dma_transmitter_refill_done_lo)

    ,.transmitter_evict_v_i(transmitter_evict_v_lo)
    ,.transmitter_evict_data_i(transmitter_evict_data_lo)
    ,.transmitter_evict_yumi_o(dma_evict_yumi_lo)
    ,.transmitter_evict_mshr_id_i(transmitter_mshr_id_lo)
  );

  assign dma_cmd_li = mgmt_v ? mgmt_dma_cmd_lo : (mhu_req_exist ? mhu_dma_cmd_lo[mhu_req_mshr_id] : e_dma_nop);
  assign dma_req_addr_li = mgmt_v ? mgmt_dma_addr_lo : (mhu_req_exist ? mhu_dma_addr_lo[mhu_req_mshr_id] : '0);
  assign dma_req_mshr_id_li = mhu_req_exist ? mhu_req_mshr_id : '0; 
  assign dma_refill_hold_li = (alloc_in_progress_v & ~alloc_no_available_way_v) 
                            | (st_found_in_mshr_update_mshr_v & dma_data_v_i & addr_index_v==mhu_curr_addr_index_lo[dma_mshr_id_i])
                            | (st_found_in_mshr_update_sbuf_and_tbuf_v & ~yumi_i); 
  assign dma_refill_track_miss_li = dma_refill_in_progress_lo ? mhu_track_miss_lo[dma_refill_mshr_id_lo] : 1'b0;
  assign dma_refill_way_li = dma_refill_in_progress_lo ? mhu_chosen_way_lo[dma_refill_mshr_id_lo] : '0;
  assign dma_refill_addr_index_li = dma_refill_in_progress_lo ? mhu_curr_addr_index_lo[dma_refill_mshr_id_lo] : '0;
  assign dma_read_miss_queue_serve_v_li = dma_refill_in_progress_lo ? read_miss_queue_v_lo[dma_refill_mshr_id_lo] : 1'b0;
 
  bsg_cache_nb_evict_fill_transmitter #( 
    .addr_width_p(addr_width_p)
    ,.word_width_p(word_width_p)
    ,.dma_data_width_p(dma_data_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.sets_p(sets_p)
    ,.ways_p(ways_p)
    ,.mshr_els_p(mshr_els_p)
  ) evict_fill_transmitter (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.evict_we_i(transmitter_evict_we_li)
    ,.refill_we_i(transmitter_refill_we_li)
    ,.store_tag_miss_we_i(transmitter_store_tag_miss_we_li)

    ,.transmitter_fill_hold_i(transmitter_fill_hold_li)

    ,.mshr_id_i(transmitter_mshr_id_li)

    ,.way_i(transmitter_way_li)
    ,.addr_index_i(transmitter_addr_index_li)

    ,.current_way_o(transmitter_current_way_lo)
    ,.current_addr_index_o(transmitter_current_addr_index_lo)

    ,.track_miss_i(dma_refill_track_miss_lo)
    ,.track_data_way_picked_i(dma_refill_track_data_way_picked_lo)

    ,.mshr_data_i(store_tag_miss_fifo_entry_lo.mshr_data)
    ,.mshr_data_write_counter_o(transmitter_mshr_data_write_counter_lo)
    // This could be used for both store tag miss and track miss refill
    ,.mshr_data_byte_mask_i(transmitter_mshr_data_byte_mask_li)
    ,.mhu_write_fill_data_in_progress_i(mhu_write_fill_data_in_progress_lo)

     // when next load / sbuf is accessing odd bank, or even bank gets the priority
    ,.even_bank_v_i(transmitter_even_bank_v_li)
    ,.even_bank_v_o(transmitter_even_bank_v_lo)
    ,.even_bank_w_o(transmitter_even_bank_w_lo)
    ,.even_bank_data_o(transmitter_even_bank_data_lo)
    ,.even_bank_w_mask_o(transmitter_even_bank_w_mask_lo)
    ,.even_bank_data_i(data_mem_even_bank_data_lo)
    ,.even_bank_addr_o(transmitter_even_bank_addr_lo)
    ,.even_counter_o(transmitter_even_counter_lo)

     // when next ld / sbuf is accessing even bank, or odd bank gets the priority
    ,.odd_bank_v_i(transmitter_odd_bank_v_li)
    ,.odd_bank_v_o(transmitter_odd_bank_v_lo)
    ,.odd_bank_w_o(transmitter_odd_bank_w_lo)
    ,.odd_bank_data_o(transmitter_odd_bank_data_lo)
    ,.odd_bank_w_mask_o(transmitter_odd_bank_w_mask_lo)
    ,.odd_bank_data_i(data_mem_odd_bank_data_lo) 
    ,.odd_bank_addr_o(transmitter_odd_bank_addr_lo)
    ,.odd_counter_o(transmitter_odd_counter_lo)

    ,.dma_refill_ready_o(transmitter_refill_ready_lo)
    ,.dma_refill_data_i(dma_refill_data_lo)
    ,.dma_refill_v_i(dma_refill_v_lo)

    ,.dma_evict_v_o(transmitter_evict_v_lo)
    ,.dma_evict_data_o(transmitter_evict_data_lo)
    ,.dma_evict_yumi_i(dma_evict_yumi_lo)

    ,.mshr_id_o(transmitter_mshr_id_lo)

    ,.even_fifo_priority_o(transmitter_even_fifo_priority_lo)
    ,.odd_fifo_priority_o(transmitter_odd_fifo_priority_lo)

    ,.data_mem_access_done_o(transmitter_data_mem_access_done_lo) //currently not used

    ,.dma_refill_done_o(transmitter_refill_done_lo)
    ,.evict_data_sent_to_dma_done_o(transmitter_evict_data_sent_to_dma_done_lo)
    ,.mhu_store_tag_miss_fill_done_o(transmitter_mhu_store_tag_miss_fill_done_lo)

    ,.refill_in_progress_o(transmitter_refill_in_progress_lo)
    ,.evict_in_progress_o(transmitter_evict_in_progress_lo)
    ,.store_tag_miss_fill_in_progress_o(transmitter_store_tag_miss_fill_in_progress_lo)
  );
  
  wire trans_idle = ~(transmitter_refill_in_progress_lo | transmitter_evict_in_progress_lo | transmitter_store_tag_miss_fill_in_progress_lo);
  assign transmitter_fill_hold_li = alloc_in_progress_v & ~alloc_no_available_way_v;
  assign transmitter_evict_we_li = trans_idle & evict_fifo_valid_lo;
  assign transmitter_store_tag_miss_we_li = trans_idle & store_tag_miss_fifo_valid_lo & ~transmitter_evict_we_li;
  assign transmitter_refill_we_li = trans_idle & dma_refill_v_lo & ~transmitter_evict_we_li & ~transmitter_store_tag_miss_we_li;
  assign transmitter_mshr_id_li = transmitter_evict_we_li
                                ? evict_fifo_entry_lo.mshr_id
                                : transmitter_store_tag_miss_we_li
                                  ? store_tag_miss_fifo_entry_lo.mshr_id
                                  : transmitter_refill_we_li 
                                    ? dma_refill_mshr_id_lo 
                                    : '0;

  assign transmitter_way_li = transmitter_evict_we_li
                            ? evict_fifo_entry_lo.way
                            : transmitter_store_tag_miss_we_li
                              ? store_tag_miss_fifo_entry_lo.way
                              : transmitter_refill_we_li 
                                ? dma_refill_way_lo 
                                : '0;

  assign transmitter_addr_index_li = transmitter_evict_we_li
                                   ? evict_fifo_entry_lo.index
                                   : transmitter_store_tag_miss_we_li
                                     ? store_tag_miss_fifo_entry_lo.index
                                     : transmitter_refill_we_li 
                                       ? dma_refill_addr_index_lo 
                                       : '0;

  assign transmitter_mshr_data_byte_mask_li = transmitter_refill_we_li 
                                            ? dma_refill_mshr_data_byte_mask_lo 
                                            : transmitter_store_tag_miss_we_li 
                                              ? store_tag_miss_fifo_entry_lo.mshr_mask
                                              : '0;

  assign transmitter_even_bank_v_li = ~next_access_even_bank | transmitter_even_fifo_priority_lo; 
  assign transmitter_odd_bank_v_li = ~next_access_odd_bank | transmitter_odd_fifo_priority_lo; 

  // evict fifo, input from MHUs, output to transmitter
  bsg_fifo_1r1w_small #(
    .width_p(evict_fifo_info_width_lp)
    ,.els_p(safe_mshr_els_lp)
  ) evict_fifo (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.data_i(evict_fifo_entry_li)
    ,.v_i(evict_fifo_valid_li)
    ,.ready_o(evict_fifo_ready_lo)
    ,.v_o(evict_fifo_valid_lo)
    ,.data_o(evict_fifo_entry_lo)
    ,.yumi_i(evict_fifo_yumi_li)
  );
  
  assign evict_fifo_valid_li = mhu_evict_v_o_found | mgmt_evict_v_lo;
  assign evict_fifo_yumi_li = evict_fifo_valid_lo & transmitter_evict_we_li;
  assign evict_fifo_entry_li.way = mgmt_v ? mgmt_curr_way_lo : mhu_chosen_way_lo[mhu_evict_mshr_id]; 
  assign evict_fifo_entry_li.index = mgmt_v ? addr_v_r[block_offset_width_lp+:lg_sets_lp] : mhu_curr_addr_index_lo[mhu_evict_mshr_id];
  assign evict_fifo_entry_li.mshr_id = mgmt_v ? '0 : mhu_evict_mshr_id;

  // store tag miss fifo, input from MHUs, output to transmitter
  if (word_tracking_p) begin: stm_fifo
    bsg_fifo_1r1w_small #(
      .width_p(store_tag_miss_fifo_info_width_lp)
      ,.els_p(safe_mshr_els_lp)
    ) store_tag_miss_fifo (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.data_i(store_tag_miss_fifo_entry_li)
      ,.v_i(store_tag_miss_fifo_valid_li)
      ,.ready_o(store_tag_miss_fifo_ready_lo)
      ,.v_o(store_tag_miss_fifo_valid_lo)
      ,.data_o(store_tag_miss_fifo_entry_lo)
      ,.yumi_i(store_tag_miss_fifo_yumi_li)
    );
  end else begin: nstm_fifo
    assign store_tag_miss_fifo_valid_lo = 1'b0;
    assign store_tag_miss_fifo_ready_lo = 1'b0;
    assign store_tag_miss_fifo_entry_lo = '0;
  end

  assign store_tag_miss_fifo_valid_li = mhu_store_tag_miss_v_o_found;
  assign store_tag_miss_fifo_yumi_li = store_tag_miss_fifo_valid_lo & transmitter_store_tag_miss_we_li;
  assign store_tag_miss_fifo_entry_li.way = mhu_chosen_way_lo[mhu_store_tag_miss_mshr_id];
  assign store_tag_miss_fifo_entry_li.index = mhu_curr_addr_index_lo[mhu_store_tag_miss_mshr_id];
  assign store_tag_miss_fifo_entry_li.mshr_id = mhu_store_tag_miss_mshr_id;
  assign store_tag_miss_fifo_entry_li.mshr_data = mshr_cam_r_data_lo;
  assign store_tag_miss_fifo_entry_li.mshr_mask = mshr_cam_r_mask_lo;

  /*******************************************************************************************/
  /*******************************************************************************************/
  /*******************************************************************************************/


  // ctrl logic
  //
  wire serve_read_queue_output_occupied = dma_serve_read_miss_queue_v_lo & v_v_r & decode_v_r.ld_op;
  wire alloc_read_miss_entry_but_no_empty = ld_found_in_mshr_alloc_read_miss_entry_v & ~read_miss_queue_ready_lo[alloc_or_update_mshr_id_lo];
  wire st_found_in_mshr_dma_hit_but_not_written_to_dmem_yet = v_v_r & decode_v_r.st_op
                                                            & mshr_match_found_v
                                                            & ((found_in_mshr_and_dma_hit_v & dma_hit_but_word_not_written_to_dmem_yet_v));

  assign v_o = dma_serve_read_miss_queue_v_lo
             ? read_miss_queue_read_in_progress_lo
             : ( v_v_r 
               & ( mgmt_v
                 ? mgmt_done_lo
                 : (( ld_miss_v | st_miss_v )
                   ? alloc_done_v
                   : ~( dma_mshr_cam_r_v_lo | alloc_read_miss_entry_but_no_empty | st_found_in_mshr_dma_hit_but_not_written_to_dmem_yet)
                 ))); 

  assign v_we = ~(v_tl_r & tag_op_tl & ~(&mshr_cam_w_empty_lo))
              & ( v_v_r
                ? ((v_o & yumi_i) 
                  & ~serve_read_queue_output_occupied
                  & ~(dma_serve_read_miss_queue_v_lo & v_v_r & st_miss_v & ~alloc_done_v)
                  )
                : 1'b1);


  // when the store buffer is full, and the TV stage is inserting another entry,
  // load/atomic cannot enter tl stage.
  assign sbuf_hazard = (sbuf_full_lo & sbuf_v_li)
    & (v_i & (decode.ld_op | decode.atomic_op));

  assign tl_recover = mgmt_recover_lo | alloc_recover_v;
  // during miss, tl pipeline cannot take next instruction when
  // 1) input is tagst and mshr is not empty or tl/tv is busy and there instruction is not tagst/la/lv
  // 2) mgmt is writing to tag_mem or track_mem
  // 3) there's even/odd bank conflict between transmitter and next instruction
  // 4) tl_stage is recovering from tag_miss
  // 5) there is  sbuf hazrd.
  // 6) allocating mshr&mhu is in process and currently trying to write to tag
  // 7) next instruction is tag mgmt or atomic, and mshr is not empty
  //    or there's chance that instructions in tl/tv will fetch a cache line from next level memory
  wire tl_ready = ~sbuf_hazard
                & ~tl_recover
                & ~(decode.tagst_op & v_i & (~(&mshr_cam_w_empty_lo) 
                   | (v_tl_r & ~(decode_tl_r.tagst_op | decode_tl_r.taglv_op | decode_tl_r.tagla_op))
                   | (v_v_r & ~(decode_v_r.tagst_op | decode_v_r.taglv_op | decode_v_r.tagla_op))
                   ))
                & ~( decode.atomic_op & v_i 
                   & (~(&mshr_cam_w_empty_lo) 
                     | (v_tl_r & (decode_tl_r.st_op | decode_tl_r.ld_op | decode_tl_r.alock_op | decode_tl_r.atomic_op)) 
                     | (v_v_r & (ld_miss_v | st_miss_v | alock_miss_v | atom_miss_v))))
                & ~(mgmt_v & (mgmt_track_mem_v_lo | mgmt_tag_mem_v_lo))
                & ~((ld_miss_v | st_miss_v) & alloc_write_tag_and_stat_v)
                & ~(even_bank_conflict | odd_bank_conflict);

  assign tl_we =  tl_ready & (v_tl_r ? v_we : 1'b1);
  assign yumi_o = v_i & tl_we;


  // tag_mem
  // values written by tagst command
 
  logic tagst_valid;
  logic tagst_lock;
  logic [tag_width_lp-1:0] tagst_tag;
  logic tagst_write_en;

  assign tagst_valid = cache_pkt.data[word_width_p-1];
  assign tagst_lock = cache_pkt.data[word_width_p-2];
  assign tagst_tag = cache_pkt.data[0+:tag_width_lp];
  assign tagst_write_en = decode.tagst_op & yumi_o;

  logic [ways_p-1:0] addr_way_decode;
  bsg_decode #(
    .num_out_p(ways_p)
  ) addr_way_demux (
    .i(addr_way)
    ,.o(addr_way_decode)
  );

  assign tag_mem_v_li = (decode.tag_read_op & yumi_o)
    | (tl_recover & decode_tl_r.tag_read_op & v_tl_r)
    | mgmt_tag_mem_v_lo
    | alloc_write_tag_and_stat_v 
    | (decode.tagst_op & yumi_o); 
  
  assign tag_mem_w_li = mgmt_v
                      ? (mgmt_tag_mem_v_lo & mgmt_tag_mem_w_lo)
                      : ((ld_miss_v | st_miss_v)
                        ? alloc_write_tag_and_stat_v
                        : tagst_write_en);
  
  always_comb begin
    if (mgmt_v) begin
      tag_mem_addr_li = mgmt_recover_lo
        ? addr_index_tl
        : (mgmt_tag_mem_v_lo ? mgmt_tag_mem_addr_lo : addr_index);
      tag_mem_data_li = mgmt_tag_mem_data_lo;
      tag_mem_w_mask_li = mgmt_tag_mem_w_mask_lo;
    end
    else if(ld_miss_v | st_miss_v) begin
      tag_mem_addr_li = alloc_recover_v
        ? addr_index_tl
        : (alloc_write_tag_and_stat_v ? addr_index_v : addr_index);
      tag_mem_data_li = alloc_tag_mem_data;
      tag_mem_w_mask_li = alloc_tag_mem_mask;
    end
    else begin
      // for TAGST
      tag_mem_addr_li = addr_index;
      for (integer i = 0; i < ways_p; i++) begin
        tag_mem_data_li[i] = {tagst_valid, tagst_lock, tagst_tag};
        tag_mem_w_mask_li[i] = {tag_info_width_lp{addr_way_decode[i]}};
      end
    end
  end

  // data_mem ctrl logic
  //
  assign data_mem_even_bank_v_li = ((yumi_o & ld_even_bank)
    //| (v_tl_r & tl_recover & (decode_tl_r.ld_op | decode_tl_r.atomic_op)) 
    | transmitter_even_bank_v_lo
    | (sbuf_v_lo & sbuf_yumi_li & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]%2==0))
  );

  assign data_mem_odd_bank_v_li = ((yumi_o & ld_odd_bank)
    //| (v_tl_r & tl_recover & (decode_tl_r.ld_op | decode_tl_r.atomic_op)) 
    | transmitter_odd_bank_v_lo
    | (sbuf_v_lo & sbuf_yumi_li & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]%2!=0))
  );

  assign data_mem_even_bank_w_li = transmitter_even_bank_w_lo | (sbuf_v_lo & sbuf_yumi_li & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]%2==0));
  assign data_mem_odd_bank_w_li = transmitter_odd_bank_w_lo | (sbuf_v_lo & sbuf_yumi_li & (sbuf_entry_lo.addr[lg_data_mask_width_lp+:lg_block_size_in_words_lp]%2!=0));

  assign data_mem_even_bank_data_li = transmitter_even_bank_w_lo
                                    ? transmitter_even_bank_data_lo
                                    : sbuf_data_mem_data;

  assign data_mem_odd_bank_data_li = transmitter_odd_bank_w_lo
                                   ? transmitter_odd_bank_data_lo
                                   : sbuf_data_mem_data;

  assign data_mem_even_bank_addr_li = (transmitter_even_bank_v_lo
      ? transmitter_even_bank_addr_lo
      : ((yumi_o & ld_even_bank) 
        ? ld_data_mem_addr
        : sbuf_data_mem_addr));

  assign data_mem_odd_bank_addr_li = (transmitter_odd_bank_v_lo
      ? transmitter_odd_bank_addr_lo
      : ((yumi_o & ld_odd_bank) 
        ? ld_data_mem_addr
        : sbuf_data_mem_addr));

  assign data_mem_even_bank_w_mask_li = transmitter_even_bank_w_lo
    ? transmitter_even_bank_w_mask_lo
    : sbuf_data_mem_w_mask;

  assign data_mem_odd_bank_w_mask_li = transmitter_odd_bank_w_lo
    ? transmitter_odd_bank_w_mask_lo
    : sbuf_data_mem_w_mask;

  // stat_mem ctrl logic
  // TAGST clears the stat_info as it exits tv stage.
  // If it's load or store, and there is a hit, it updates the dirty bits and LRU.
  // If there is a miss, stat_mem may be modified by the miss handler.

  logic [ways_p-2:0] plru_decode_data_lo;
  logic [ways_p-2:0] plru_decode_mask_lo;
  
  bsg_lru_pseudo_tree_decode #(
    .ways_p(ways_p)
  ) plru_decode (
    .way_id_i(alloc_write_tag_and_stat_v ? way_chooser_chosen_way_lo : tag_hit_way_id_v)
    ,.data_o(plru_decode_data_lo)
    ,.mask_o(plru_decode_mask_lo)
  );

  always_comb begin
    if (mgmt_v) begin
      stat_mem_v_li = mgmt_stat_mem_v_lo;
      stat_mem_w_li = mgmt_stat_mem_w_lo;
      stat_mem_addr_li = mgmt_stat_mem_addr_lo;
      stat_mem_data_li = mgmt_stat_mem_data_lo;
      stat_mem_w_mask_li = mgmt_stat_mem_w_mask_lo;
    end
    else if (dma_mshr_cam_r_v_lo) begin
      stat_mem_v_li = 1'b1;
      stat_mem_w_li = 1'b1;
      stat_mem_addr_li = mhu_curr_addr_index_lo[dma_mshr_id_i];
      stat_mem_data_li.dirty = {ways_p{(|mshr_cam_r_mask_lo)}};
      stat_mem_data_li.lru_bits = {(ways_p-1){1'b0}};
      stat_mem_data_li.waiting_for_fill_data = {ways_p{1'b0}};
      stat_mem_w_mask_li.dirty = mhu_chosen_way_decode;
      stat_mem_w_mask_li.lru_bits = {(ways_p-1){1'b0}};
      stat_mem_w_mask_li.waiting_for_fill_data = mhu_chosen_way_decode;
    end
    else if (ld_miss_v | st_miss_v) begin
      stat_mem_v_li = alloc_read_stat_v | alloc_write_tag_and_stat_v;
      stat_mem_w_li = alloc_write_tag_and_stat_v;
      stat_mem_addr_li = addr_index_v;
      stat_mem_data_li = alloc_stat_mem_data;
      stat_mem_w_mask_li = alloc_stat_mem_mask;
    end
    else begin
      stat_mem_v_li = ((decode_v_r.st_op | decode_v_r.ld_op | decode_v_r.tagst_op | decode_v_r.atomic_op) & v_v_r & v_o & yumi_i);
      stat_mem_w_li = ((decode_v_r.st_op | decode_v_r.ld_op | decode_v_r.tagst_op | decode_v_r.atomic_op) & v_v_r & v_o & yumi_i);
      stat_mem_addr_li = addr_index_v;

      if (decode_v_r.tagst_op) begin
        // for TAGST
        stat_mem_data_li.dirty = {ways_p{1'b0}};
        stat_mem_data_li.lru_bits = {(ways_p-1){1'b0}};
        stat_mem_data_li.waiting_for_fill_data = {ways_p{1'b0}};
        stat_mem_w_mask_li.dirty = {ways_p{1'b1}};
        stat_mem_w_mask_li.lru_bits = {(ways_p-1){1'b1}};
        stat_mem_w_mask_li.waiting_for_fill_data = {ways_p{1'b1}};
      end
      else begin
        // for LD, ST, ATOMIC HIT
        stat_mem_data_li.dirty = {ways_p{decode_v_r.st_op | decode_v_r.atomic_op}};
        stat_mem_data_li.lru_bits = plru_decode_data_lo;
        stat_mem_data_li.waiting_for_fill_data = {ways_p{1'b0}};
        stat_mem_w_mask_li.dirty = {ways_p{decode_v_r.st_op | decode_v_r.atomic_op}} & tag_hit_v;
        stat_mem_w_mask_li.lru_bits = plru_decode_mask_lo;
        stat_mem_w_mask_li.waiting_for_fill_data = {ways_p{1'b0}};
      end
    end
  end


  // track buffer
  //
  // track buffer can write to track mem when
  // 1) there is valid entry in track buffer.
  // 2) incoming request does not read track mem.
  // 3) miss handler is not accessing track mem.
  // 4) TL read track mem (and bypass from tbuf), and TV is not stalled (v_we).
  //    During miss, the track buffer can be drained.
  // assign tbuf_yumi_li = tbuf_v_lo
  //   & ~((decode.ld_op | decode.atomic_op | partial_st) & yumi_o)
  //   & (~miss_track_mem_v_lo)
  //   & ~(v_tl_r & (decode_tl_r.ld_op | decode_tl_r.atomic_op | partial_st_tl) & (~v_we) & (~miss_v));

  // assign tbuf_bypass_addr_li = addr_tl_r;
  // assign tbuf_bypass_v_li = (decode_tl_r.ld_op | decode_tl_r.atomic_op | partial_st_tl) & v_tl_r & v_we;

  // alloc new mshr FSM
  //
  always_ff @ (posedge clk_i) begin
    if (reset_i) begin
      alloc_mshr_state_r <= IDLE;
    end else begin
      alloc_mshr_state_r <= alloc_mshr_state_n;
    end
  end

  always_comb begin
    alloc_read_stat_v = 1'b0;
    alloc_write_tag_and_stat_v = 1'b0;
    alloc_recover_v = 1'b0;
    alloc_in_progress_v = 1'b0;
    alloc_done_v = 1'b0;
    alloc_no_available_way_v = 1'b0;
    alloc_tag_mem_data = '0;
    alloc_tag_mem_mask = '0;
    alloc_stat_mem_data = '0;
    alloc_stat_mem_mask = '0;
    alloc_mshr_state_n = alloc_mshr_state_r;

    case (alloc_mshr_state_r)

      IDLE: begin
        alloc_mshr_state_n = mshr_entry_alloc_ready
                           ? WRITE_TAG_AND_STAT 
                           : IDLE;  
        alloc_read_stat_v = mshr_entry_alloc_ready;                
        alloc_in_progress_v = mshr_entry_alloc_ready;
      end

      WRITE_TAG_AND_STAT: begin
        alloc_mshr_state_n = way_chooser_no_available_way_lo
                           ? (dma_mshr_cam_r_v_lo
                             ? IDLE
                             : WRITE_TAG_AND_STAT)
                           : ((dma_serve_read_miss_queue_v_lo & ld_miss_v)
                             ? WRITE_TAG_AND_STAT 
                             : RECOVER);
        alloc_write_tag_and_stat_v = alloc_mshr_state_n==RECOVER;
        alloc_in_progress_v = 1'b1;
        alloc_no_available_way_v = way_chooser_no_available_way_lo;

        for (integer i = 0; i < ways_p; i++) begin
          alloc_tag_mem_data[i].tag = addr_tag_v;
          alloc_tag_mem_data[i].lock = 1'b0;
          alloc_tag_mem_data[i].valid = 1'b1; 
          alloc_tag_mem_mask[i].tag = {tag_width_lp{alloc_chosen_way_decode[i]}};
          alloc_tag_mem_mask[i].lock = alloc_chosen_way_decode[i];
          alloc_tag_mem_mask[i].valid = alloc_chosen_way_decode[i];
        end

        alloc_stat_mem_data.dirty = {ways_p{decode_v_r.st_op}};
        alloc_stat_mem_data.lru_bits = plru_decode_data_lo;
        alloc_stat_mem_data.waiting_for_fill_data = {ways_p{1'b1}};
        alloc_stat_mem_mask.dirty = alloc_chosen_way_decode;
        alloc_stat_mem_mask.lru_bits = plru_decode_mask_lo;
        alloc_stat_mem_mask.waiting_for_fill_data = alloc_chosen_way_decode;

      end

      RECOVER: begin
        // FIXME: for now we don't need this as mshr is accessed in tv stage, so even if there's mshr clear
        // or dma data in, they don't affect the recovery, but we should add this later when change to access
        // the mshr cam in tl stage
        //alloc_in_progress_v = 1'b1; 
        alloc_mshr_state_n = DONE;
        alloc_recover_v = 1'b1;
      end

      DONE: begin
        alloc_done_v = 1'b1;
        alloc_mshr_state_n = (v_o & yumi_i) ? IDLE : DONE;
      end

      default: begin
        alloc_mshr_state_n = IDLE;
      end

    endcase
  end

  // synopsys translate_off

  always_ff @ (negedge clk_i) begin
    if (~reset_i) begin
      if (v_v_r) begin
        // check that there is no multiple hit.
        assert($countones(tag_hit_v) <= 1)
          else $error("[BSG_ERROR][BSG_CACHE_nb] Multiple cache hit detected. %m, T=%t", $time);

        // check that there is at least one unlocked way in a set.
        assert($countones(lock_v_r) < ways_p)
          else $error("[BSG_ERROR][BSG_CACHE_nb] There should be at least one unlocked way in a set. %m, T=%t", $time);

        // Check that client hasn't required unsupported AMO
        assert(~decode_v_r.atomic_op | amo_support_p[decode_v_r.amo_subop])
          else $error("[BSG_ERROR][BSG_CACHE_nb] Unsupported AMO OP %d received. %m, T=%t", decode.amo_subop, $time);

        assert(~decode_v_r.atomic_op || (word_width_p >= 64) || ~decode_v_r.data_size_op[0])
          else $error("[BSG_ERROR][BSG_CACHE_nb] AMO_D performed on data_width < 64. %m T=%t", $time);
        assert(~decode_v_r.atomic_op || (word_width_p >= 32))
          else $error("[BSG_ERROR][BSG_CACHE_nb] AMO performed on data_width < 32. %m T=%t", $time);
      end
    end
  end


  if (debug_p) begin
    always_ff @ (posedge clk_i) begin
      if (v_o & yumi_i) begin
        if (decode_v_r.ld_op) begin
          $display("<VCACHE> M[%4h] == %8h // %8t", addr_v_r, data_o, $time);
        end
        
        if (decode_v_r.st_op) begin
          $display("<VCACHE> M[%4h] := %8h // %8t", addr_v_r, sbuf_entry_li.data, $time);
        end

      end
      if (tag_mem_v_li & tag_mem_w_li) begin
        $display("<VCACHE> tag_mem_write. addr=%8h data_1=%8h data_0=%8h mask_1=%8h mask_0=%8h // %8t",
          tag_mem_addr_li,
          tag_mem_data_li[1+tag_width_lp+:1+tag_width_lp],
          tag_mem_data_li[0+:1+tag_width_lp],
          tag_mem_w_mask_li[1+tag_width_lp+:1+tag_width_lp],
          tag_mem_w_mask_li[0+:1+tag_width_lp],
          $time
        );
      end
    end
  end

  // synopsys translate_on


endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb)
