`include "bsg_defines.v"
`include "bsg_cache_nb.vh"

module bsg_cache_nb_tag_mgmt_unit
  import bsg_cache_nb_pkg::*;
  #(parameter `BSG_INV_PARAM(addr_width_p)
    ,parameter `BSG_INV_PARAM(word_width_p)
    ,parameter `BSG_INV_PARAM(block_size_in_words_p)
    ,parameter `BSG_INV_PARAM(sets_p)
    ,parameter `BSG_INV_PARAM(ways_p)

    ,parameter lg_block_size_in_words_lp=`BSG_SAFE_CLOG2(block_size_in_words_p)
    ,parameter lg_sets_lp=`BSG_SAFE_CLOG2(sets_p)
    ,parameter data_mask_width_lp=(word_width_p>>3)
    ,parameter lg_data_mask_width_lp=`BSG_SAFE_CLOG2(data_mask_width_lp)
    ,parameter block_offset_width_lp=(block_size_in_words_p > 1) ? lg_data_mask_width_lp+lg_block_size_in_words_lp : lg_data_mask_width_lp
    ,parameter tag_offset_lp=(sets_p == 1) ? block_offset_width_lp : block_offset_width_lp+lg_sets_lp
    ,parameter tag_width_lp=addr_width_p-tag_offset_lp
    ,parameter tag_info_width_lp=`bsg_cache_nb_tag_info_width(tag_width_lp)
    ,parameter lg_ways_lp=`BSG_SAFE_CLOG2(ways_p)
    ,parameter stat_info_width_lp=`bsg_cache_nb_stat_info_width(ways_p)
  )
  (
    input clk_i
    ,input reset_i

    // from tv stage
    ,input mgmt_v_i
    ,input bsg_cache_nb_decode_s decode_v_i
    // TODO:在cache input发现是mgmt就要直接即刻等到mshr cam为空且tl_r和tv_r都为0才输入
    ,input [addr_width_p-1:0] addr_v_i
    ,input [ways_p-1:0][tag_width_lp-1:0] tag_v_i
    ,input [ways_p-1:0] valid_v_i
    //,input [ways_p-1:0] lock_v_i
    ,input [ways_p-1:0] tag_hit_v_i
    ,input [lg_ways_lp-1:0] tag_hit_way_id_i
    ,input tag_hit_found_i

    ,input [lg_ways_lp-1:0] chosen_way_i

    // from store buffer
    ,input sbuf_empty_i

    // from track buffer
    ,input tbuf_empty_i

    ,output logic evict_v_o

    ,output bsg_cache_nb_dma_cmd_e dma_cmd_o
    ,output logic [addr_width_p-1:0] dma_addr_o
    
    ,input dma_done_i

    // from stat_mem
    ,input [stat_info_width_lp-1:0] stat_info_i

    // to stat_mem
    ,output logic stat_mem_v_o
    ,output logic stat_mem_w_o
    ,output logic [lg_sets_lp-1:0] stat_mem_addr_o
    ,output logic [stat_info_width_lp-1:0] stat_mem_data_o
    ,output logic [stat_info_width_lp-1:0] stat_mem_w_mask_o

    // to tag_mem
    ,output logic tag_mem_v_o
    ,output logic tag_mem_w_o
    ,output logic [lg_sets_lp-1:0] tag_mem_addr_o
    ,output logic [ways_p-1:0][tag_info_width_lp-1:0] tag_mem_data_o
    ,output logic [ways_p-1:0][tag_info_width_lp-1:0] tag_mem_w_mask_o

    // to track mem
    ,output logic track_mem_v_o
    ,output logic track_mem_w_o
    ,output logic [lg_sets_lp-1:0] track_mem_addr_o
    ,output logic [ways_p-1:0][block_size_in_words_p-1:0] track_mem_w_mask_o
    ,output logic [ways_p-1:0][block_size_in_words_p-1:0] track_mem_data_o

    //,output logic [lg_ways_lp-1:0] flush_way_o
    //,output logic [lg_ways_lp-1:0] chosen_way_o

    ,output logic [lg_ways_lp-1:0] curr_way_o
    //,output logic goto_flush_op_o
    //,output logic goto_lock_op_o

    // to pipeline
    ,output logic mgmt_done_o
    ,output logic recover_o

    ,input ack_i
  );

  // stat/tag info
  //
  `declare_bsg_cache_nb_tag_info_s(tag_width_lp);
  `declare_bsg_cache_nb_stat_info_s(ways_p);

  bsg_cache_nb_stat_info_s stat_info_in;
  assign stat_info_in = stat_info_i;

  bsg_cache_nb_tag_info_s [ways_p-1:0] tag_mem_data_out, tag_mem_w_mask_out;
  bsg_cache_nb_stat_info_s stat_mem_data_out, stat_mem_w_mask_out;
  
  assign tag_mem_data_o = tag_mem_data_out;
  assign stat_mem_data_o = stat_mem_data_out;

  assign tag_mem_w_mask_o = tag_mem_w_mask_out;
  assign stat_mem_w_mask_o = stat_mem_w_mask_out;

  mgmt_miss_state_e miss_state_r;
  mgmt_miss_state_e miss_state_n;
  logic [lg_ways_lp-1:0] chosen_way_r, chosen_way_n;
  logic [lg_ways_lp-1:0] flush_way_r, flush_way_n;

  // for flush/inv ops, go to FLUSH_OP.
  // for AUNLOCK, or ALOCK with tag hit, to go LOCK_OP.
  wire goto_flush_op = decode_v_i.tagfl_op| decode_v_i.ainv_op| decode_v_i.afl_op| decode_v_i.aflinv_op;
  wire goto_lock_op = decode_v_i.aunlock_op | (decode_v_i.alock_op & tag_hit_found_i);

  //assign goto_flush_op_o = goto_flush_op;
  //assign goto_lock_op_o = goto_lock_op;

  //assign flush_way_o = flush_way_r;
  //assign chosen_way_o = chosen_way_r;

  assign curr_way_o = goto_flush_op
                    ? flush_way_r
                    : chosen_way_r;

  logic [tag_width_lp-1:0] addr_tag_v;
  logic [lg_sets_lp-1:0] addr_index_v;
  logic [lg_ways_lp-1:0] addr_way_v;

  assign addr_index_v
    = addr_v_i[block_offset_width_lp+:lg_sets_lp];
  assign addr_tag_v
    = addr_v_i[tag_offset_lp+:tag_width_lp];
  assign addr_way_v
    = addr_v_i[tag_offset_lp+:lg_ways_lp];


  assign stat_mem_addr_o = addr_index_v;
  assign tag_mem_addr_o = addr_index_v;
  assign track_mem_addr_o = addr_index_v;

  // chosen way lru decode
  //
  logic [ways_p-2:0] chosen_way_lru_data;
  logic [ways_p-2:0] chosen_way_lru_mask;

  bsg_lru_pseudo_tree_decode #(
    .ways_p(ways_p)
  ) chosen_way_lru_decode (
    .way_id_i(chosen_way_r)
    ,.data_o(chosen_way_lru_data)
    ,.mask_o(chosen_way_lru_mask)
  );

  // chosen way demux
  //
  logic [ways_p-1:0] chosen_way_decode;
  bsg_decode #(
    .num_out_p(ways_p)
  ) chosen_way_demux (
    .i(chosen_way_n)
    ,.o(chosen_way_decode)
  );

  // flush way demux
  logic [ways_p-1:0] addr_way_v_decode;
  bsg_decode #(
    .num_out_p(ways_p)
  ) addr_way_v_demux (
    .i(addr_way_v)
    ,.o(addr_way_v_decode)
  );
  
  logic [ways_p-1:0] flush_way_decode;
  assign flush_way_decode = decode_v_i.tagfl_op
                          ? addr_way_v_decode
                          : tag_hit_v_i;

  wire mgmt_unit_boot_up = (mgmt_v_i & sbuf_empty_i & tbuf_empty_i);

  always_comb begin

    stat_mem_v_o = 1'b0;
    stat_mem_w_o = 1'b0;
    stat_mem_data_out = '0;
    stat_mem_w_mask_out = '0;

    tag_mem_v_o = 1'b0;
    tag_mem_w_o = 1'b0;
    tag_mem_data_out = '0;
    tag_mem_w_mask_out = '0;

    track_mem_v_o = 1'b0;
    track_mem_w_o = 1'b0;
    track_mem_data_o = '0;
    track_mem_w_mask_o = '0;

    chosen_way_n = chosen_way_r;
    flush_way_n = flush_way_r;

    dma_addr_o = '0;
    dma_cmd_o = e_dma_nop;

    recover_o = '0;
    mgmt_done_o = '0;

    evict_v_o = 1'b0;

    case (miss_state_r)

      MGMT_START: begin
        stat_mem_v_o = mgmt_unit_boot_up;
        track_mem_v_o = mgmt_unit_boot_up;
        miss_state_n = mgmt_unit_boot_up
                     ? (goto_flush_op
                       ? MGMT_FLUSH_OP 
                       : (goto_lock_op
                          ? MGMT_LOCK_OP
                          : MGMT_SEND_FILL_ADDR)) 
                     : MGMT_START;
      end

      MGMT_SEND_FILL_ADDR: begin
        chosen_way_n = chosen_way_i;
        dma_cmd_o = e_dma_send_refill_addr;          
        dma_addr_o = {
          addr_tag_v,
          {(sets_p>1){addr_index_v}},
          {(block_offset_width_lp){1'b0}}
        };

        // if the chosen way is dirty and valid, then evict.
        miss_state_n = dma_done_i
          ? ((stat_info_in.dirty[chosen_way_n] & valid_v_i[chosen_way_n])
            ? MGMT_SEND_EVICT_ADDR
            : MGMT_GET_FILL_DATA)
          : MGMT_SEND_FILL_ADDR;
      end

      // Handling the cases for TAGFL, AINV, AFL, AFLINV.
      MGMT_FLUSH_OP: begin
        // for TAGFL, pick whichever way set by the addr input.
        // Otherwise, pick the way with the tag hit.
        flush_way_n = decode_v_i.tagfl_op
                    ? addr_way_v 
                    : tag_hit_way_id_i;
        // Clear the dirty bit for the chosen set.
        // LRU bit does not need to be updated.
        stat_mem_v_o = 1'b1;
        stat_mem_w_o = 1'b1;
        stat_mem_data_out.dirty = {ways_p{1'b0}};
        stat_mem_data_out.lru_bits = {(ways_p-1){1'b0}};
        stat_mem_data_out.waiting_for_fill_data = {ways_p{1'b0}};
        stat_mem_w_mask_out.dirty = flush_way_decode;
        stat_mem_w_mask_out.lru_bits = {(ways_p-1){1'b0}};
        stat_mem_w_mask_out.waiting_for_fill_data = {ways_p{1'b0}};

        // If it's invalidate op, then clear the valid bit for the chosen way.
        // Otherwise, do not touch the valid bits.
        tag_mem_v_o = 1'b1;
        tag_mem_w_o = 1'b1;

        for (integer i = 0; i < ways_p; i++) begin
          tag_mem_data_out[i].valid = 1'b0;
          tag_mem_data_out[i].lock = 1'b0;
          tag_mem_data_out[i].tag = {tag_width_lp{1'b0}};
          tag_mem_w_mask_out[i].valid = (decode_v_i.ainv_op | decode_v_i.aflinv_op) & flush_way_decode[i];
          tag_mem_w_mask_out[i].lock = (decode_v_i.ainv_op | decode_v_i.aflinv_op) & flush_way_decode[i];
          tag_mem_w_mask_out[i].tag =  {tag_width_lp{1'b0}};
        end

        // If it's not AINV, and the chosen set is dirty and valid, evict the block.
        miss_state_n = (~decode_v_i.ainv_op & stat_info_in.dirty[flush_way_n] & valid_v_i[flush_way_n])
          ? MGMT_SEND_EVICT_ADDR
          : MGMT_RECOVER;
      end

      // handling AUNLOCK, and ALOCK with line not missing.
      MGMT_LOCK_OP: begin
        tag_mem_v_o = 1'b1;
        tag_mem_w_o = 1'b1;

        for (integer i = 0; i < ways_p; i++) begin
          tag_mem_data_out[i].valid = 1'b0;
          tag_mem_data_out[i].lock = decode_v_i.alock_op;
          tag_mem_data_out[i].tag = {tag_width_lp{1'b0}};
          tag_mem_w_mask_out[i].valid = 1'b0;
          tag_mem_w_mask_out[i].lock = tag_hit_v_i[i];
          tag_mem_w_mask_out[i].tag = {tag_width_lp{1'b0}};
        end

        miss_state_n = MGMT_RECOVER;
      end

      // Send out the block addr for eviction, before initiating the eviction.
      MGMT_SEND_EVICT_ADDR: begin
        dma_cmd_o = e_dma_send_evict_addr;
        dma_addr_o = {
          tag_v_i[curr_way_o],
          {(sets_p>1){addr_index_v}},
          {(block_offset_width_lp){1'b0}}
        };

        miss_state_n = dma_done_i
                     ? MGMT_SEND_EVICT_DATA
                     : MGMT_SEND_EVICT_ADDR;

        evict_v_o = dma_done_i;
      end

      MGMT_SEND_EVICT_DATA: begin
        miss_state_n = dma_done_i
          ? ((decode_v_i.tagfl_op| decode_v_i.aflinv_op| decode_v_i.afl_op) 
            ? MGMT_RECOVER 
            : MGMT_GET_FILL_DATA)
          : MGMT_SEND_EVICT_DATA;
      end

      MGMT_GET_FILL_DATA: begin
        stat_mem_v_o = dma_done_i;
        stat_mem_w_o = 1'b1;
        stat_mem_data_out.dirty = {ways_p{decode_v_i.atomic_op}};
        stat_mem_data_out.lru_bits = chosen_way_lru_data;
        stat_mem_data_out.waiting_for_fill_data = {ways_p{1'b0}};
        stat_mem_w_mask_out.dirty = chosen_way_decode;
        stat_mem_w_mask_out.lru_bits = chosen_way_lru_mask;
        stat_mem_w_mask_out.waiting_for_fill_data = {ways_p{1'b0}};

        // set the tag and the valid bit to 1'b1 for the chosen way.
        tag_mem_v_o = dma_done_i;
        tag_mem_w_o = 1'b1;

        for (integer i = 0; i < ways_p; i++) begin
          tag_mem_data_out[i].tag = addr_tag_v;
          tag_mem_data_out[i].lock = decode_v_i.alock_op;
          tag_mem_data_out[i].valid = 1'b1; 
          tag_mem_w_mask_out[i].tag = {tag_width_lp{chosen_way_decode[i]}};
          tag_mem_w_mask_out[i].lock = chosen_way_decode[i];
          tag_mem_w_mask_out[i].valid = chosen_way_decode[i];
        end

        miss_state_n = dma_done_i
          ? MGMT_RECOVER
          : MGMT_GET_FILL_DATA;
      end

      // Spend one cycle to recover the tl stage.
      // By recovering, it means re-reading the data_mem and tag_mem for the tl stage.
      MGMT_RECOVER: begin
        recover_o = 1'b1;
        miss_state_n = MGMT_DONE;
      end

      // Miss handling is done. Output is valid.
      // Move onto next state, when the output data is taken.
      MGMT_DONE: begin
        mgmt_done_o = 1'b1;
        miss_state_n = ack_i ? MGMT_START : MGMT_DONE;
      end

      // this should never happen, but if it does, go back to START;
      default: begin
        miss_state_n = MGMT_START;
      end

    endcase
  end

  // synopsys sync_set_reset "reset_i"
  always_ff @ (posedge clk_i) begin
    if (reset_i) begin
      miss_state_r <= MGMT_START;
      chosen_way_r <= '0;
      flush_way_r <= '0;
    end
    else begin
      miss_state_r <= miss_state_n;
      chosen_way_r <= chosen_way_n;
      flush_way_r <= flush_way_n;
    end
  end

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_tag_mgmt_unit)
