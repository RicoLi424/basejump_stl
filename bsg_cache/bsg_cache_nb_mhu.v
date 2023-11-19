`include "bsg_defines.v"
`include "bsg_cache_nb.vh"

module bsg_cache_nb_mhu
  import bsg_cache_nb_pkg::*;
  #(parameter `BSG_INV_PARAM(addr_width_p)
    ,parameter `BSG_INV_PARAM(word_width_p)
    ,parameter `BSG_INV_PARAM(block_size_in_words_p)
    ,parameter `BSG_INV_PARAM(sets_p)
    ,parameter `BSG_INV_PARAM(ways_p)
    ,parameter `BSG_INV_PARAM(mshr_els_p)

    ,parameter lg_block_size_in_words_lp=`BSG_SAFE_CLOG2(block_size_in_words_p)
    ,parameter lg_sets_lp=`BSG_SAFE_CLOG2(sets_p)
    ,parameter lg_mshr_els_lp=`BSG_SAFE_CLOG2(mshr_els_p)
    ,parameter word_mask_width_lp=(word_width_p>>3)
    ,parameter lg_word_mask_width_lp=`BSG_SAFE_CLOG2(word_width_p>>3)
    ,parameter block_offset_width_lp=(block_size_in_words_p > 1) ? (lg_word_mask_width_lp+lg_block_size_in_words_lp) : lg_word_mask_width_lp
    ,parameter tag_offset_lp=(sets_p == 1) ? block_offset_width_lp : block_offset_width_lp+lg_sets_lp
    ,parameter tag_width_lp=addr_width_p-tag_offset_lp
    ,parameter tag_info_width_lp=`bsg_cache_nb_tag_info_width(tag_width_lp)
    ,parameter cache_line_offset_width_lp=(sets_p == 1) ? tag_width_lp : tag_width_lp+lg_sets_lp
    ,parameter lg_ways_lp=`BSG_SAFE_CLOG2(ways_p)
    ,parameter stat_info_width_lp=`bsg_cache_nb_stat_info_width(ways_p)
  )
  (
    input clk_i
    , input reset_i

    //, input [lg_mshr_els_lp-1:0] mshr_id_i

    , input mhu_we_i
    , input mhu_activate_i

    , input mshr_stm_miss_i
    // TODO:结合store_tag_miss_op_o,用来给外部来判断什么时候删掉mshr entry,以及track的data input
    , output logic mshr_stm_miss_o
 
    //TODO:外部用一个reg接这个信号，如果其输出端为1，那就阻塞tl→tv
    //, output logic mhu_read_tag_and_stat_v_o
    //TODO:外部用一个reg接这个信号，如果其输出端为1，那就阻塞tl→tv
    //, output logic mhu_read_track_v_o
    //, output logic mhu_write_tag_and_stat_v_o
    //, output logic mhu_write_track_v_o

    // from tv stage
    , input store_tag_miss_op_i
    , input track_miss_i
    //, input bsg_cache_nb_decode_s decode_v_i
    , input [addr_width_p-1:0] addr_v_i
    , input [lg_ways_lp-1:0] tag_hit_way_id_i
    //, input [word_mask_width_lp-1:0] mask_v_i

    , input [ways_p-1:0][tag_width_lp-1:0] tag_v_i
    , input [ways_p-1:0] valid_v_i

    , input [lg_ways_lp-1:0] chosen_way_i
    , output logic [lg_ways_lp-1:0] chosen_way_o

    // snoop sbuf & tbuf before eviction
    , input sbuf_or_tbuf_chosen_way_found_i
    // snoop tl's way and opcode before deciding whether to evict
    //, input tl_store_on_chosen_way_found_i

    , output bsg_cache_nb_dma_cmd_e dma_cmd_o
    , output logic [addr_width_p-1:0] dma_addr_o

    //, output logic [lg_mshr_els_lp-1:0] mshr_id_o
    , output logic [lg_sets_lp-1:0] curr_addr_index_o
    , output logic [tag_width_lp-1:0] curr_addr_tag_o

    , input dma_done_i
    , input transmitter_store_tag_miss_fill_done_i

    // from stat_mem
    , input [stat_info_width_lp-1:0] stat_info_i

    // to pipeline 
    // when recover_o = 1 and there's no other external incoming stall signal, 
    // acknoledge the recovery and mhu is done
    //, input recover_ack_i //FIXME
    //, output logic recover_o //FIXME
    //, output logic mhu_done_o

    , output logic store_tag_miss_op_o
    //, output logic alock_op_o
    , output logic track_miss_o
    //FIXME, input [ways_p-1:0][block_size_in_words_p-1:0] track_mem_data_tl_i
    //FIXME, output logic [block_size_in_words_p-1:0] track_data_way_picked_o

    , output logic evict_v_o
    , output logic store_tag_miss_fill_v_o

    // To dma so the refill_done signal can only come after an evict_done
    , output logic write_fill_data_in_progress_o
    // output this signal to DMA to avoid a case where refill data has come back,
    // but the state machine is still in WAIT_SNOOP_DONE, in that case the new
    // data will be written to DMEM before the old data is evicted
    , output logic evict_enqueued_o

    // TODO:外部用这个来选择dma的mhu_req_mshr_id_i
    // 同时用来判断一个mhu是否已经将evict推入fifo，好让refill data进入
    , output logic mhu_req_busy_o

  );

  mhu_miss_state_e miss_state_r;
  mhu_miss_state_e miss_state_n;

  logic track_miss_r;
  logic mshr_stm_miss_r;
  //logic [ways_p-1:0][block_size_in_words_p-1:0] track_mem_data_way_picked_r;
  //FIXME logic [block_size_in_words_p-1:0] track_mem_data_tl_way_picked; 
  //FIXME logic [block_size_in_words_p-1:0] track_mem_data_way_picked_r;
  logic [cache_line_offset_width_lp-1:0] curr_cache_line_offset_r;
  logic store_tag_miss_op_r, store_tag_miss_op_n;
  //logic alock_op_r;
  //logic st_op_r, atomic_op_r;
  logic [lg_ways_lp-1:0] chosen_way_r;
  logic [tag_width_lp-1:0] tag_mem_tag_way_picked_r;
  //logic mhu_done;
  //logic [lg_ways_lp-1:0] chosen_way_n;
  logic [stat_info_width_lp-1:0] stat_info_r;
  logic [ways_p-1:0] valid_v_r;

  // FIXME  
  // bsg_mux #(
  //   .width_p(block_size_in_words_p)
  //   ,.els_p(ways_p)
  // ) track_data_mux (
  //   .data_i(track_mem_data_tl_i)
  //   ,.sel_i(chosen_way_r)
  //   ,.data_o(track_mem_data_tl_way_picked)
  // );

  `declare_bsg_cache_nb_stat_info_s(ways_p);
  bsg_cache_nb_stat_info_s stat_info;
  assign stat_info = stat_info_r;

  // bsg_dff_reset_en_bypass #(
  //   .width_p(lg_ways_lp)
  // ) chosen_way_dff_bypass (
  //   .clk_i(clk_i)
  //   ,.reset_i(reset_i)
  //   ,.en_i(((miss_state_r==SEND_REFILL_ADDR) & ~store_tag_miss_op_r & ~track_miss_r) 
  //           | (miss_state_r==STORE_TAG_MISS)
  //           | (mhu_we_i & track_miss_i))
  //   ,.data_i((mhu_we_i & track_miss_i) ? tag_hit_way_id_i : chosen_way_i)
  //   ,.data_o(chosen_way_r)
  // );

  bsg_dff_reset_en_bypass #(
    .width_p(lg_ways_lp)
  ) chosen_way_dff_bypass (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.en_i(mhu_we_i)
    ,.data_i(track_miss_i ? tag_hit_way_id_i : chosen_way_i)
    ,.data_o(chosen_way_r)
  );

  bsg_dff_reset_en_bypass #(
    .width_p(1)
  ) mshr_stm_miss_dff_bypass (
    .clk_i(clk_i)
    //,.reset_i(reset_i | recover_ack_i)FIXME
    ,.reset_i(reset_i)
    //I wrote like this at first, but seems not correct now, but since we don't have word tracking fro now,
    //I'll leave it for now and maybe take another look later
    //,.en_i(mshr_stm_miss_i | ~mhu_req_busy_o) 
    ,.en_i(mshr_stm_miss_i & mhu_req_busy_o)
    ,.data_i(1'b1)
    ,.data_o(mshr_stm_miss_r)
  );


  always_ff @ (posedge clk_i) begin
    // $display("mhu_miss_state:%b", miss_state_r); TODO
    if (reset_i) begin
      miss_state_r <= MHU_START;
      //chosen_way_r <= '0;
      track_miss_r <= 1'b0;
      //st_op_r <= 1'b0;
      //atomic_op_r <= 1'b0;
      //alock_op_r <= 1'b0;
      store_tag_miss_op_r <= 1'b0;
      curr_cache_line_offset_r <= '0;
      tag_mem_tag_way_picked_r <= '0;
      valid_v_r <= '0;
    end else begin

      miss_state_r <= miss_state_n;
      store_tag_miss_op_r <= store_tag_miss_op_n;
      //chosen_way_r <= chosen_way_n;

      if (mhu_we_i) begin
        track_miss_r <= track_miss_i;
        //track_mem_data_way_picked_r <= track_mem_data_way_picked_i;
        curr_cache_line_offset_r <= addr_v_i[block_offset_width_lp+:cache_line_offset_width_lp];
        //st_op_r <= decode_v_i.st_op;
        //atomic_op_r <= decode_v_i.atomic_op;
        //alock_op_r <= decode_v_i.alock_op;
        //chosen_way_r <= chosen_way_i;
        //store_tag_miss_op_r <= store_tag_miss_op_i;
        stat_info_r <= stat_info_i;
        tag_mem_tag_way_picked_r <= tag_v_i[chosen_way_i];
        valid_v_r <= valid_v_i;
      end

      //FIXME
      //if(((miss_state_r==SEND_REFILL_ADDR)&track_miss_r) | (miss_state_r==SEND_EVICT_ADDR)) begin
      //  track_mem_data_way_picked_r <= track_mem_data_tl_way_picked;
      //end

      //if (mshr_stm_miss_r) begin
      //  store_tag_miss_op_r <= 1'b0;
      //end

    end
  end


  logic [tag_width_lp-1:0] curr_addr_tag;
  logic [lg_sets_lp-1:0] curr_addr_index;

  assign curr_addr_index
    = (sets_p > 1)
    ? curr_cache_line_offset_r[0+:lg_sets_lp]
    : 1'b0;
  assign curr_addr_tag
    = (sets_p == 1)
      ? curr_cache_line_offset_r[0+:tag_width_lp]
      : curr_cache_line_offset_r[lg_sets_lp+:tag_width_lp];

  assign chosen_way_o = chosen_way_r;
  assign store_tag_miss_op_o = store_tag_miss_op_r;
  //assign alock_op_o = alock_op_r;
  assign mshr_stm_miss_o = mshr_stm_miss_r;
  assign track_miss_o = track_miss_r;
  assign curr_addr_index_o = curr_addr_index;
  assign curr_addr_tag_o = curr_addr_tag;
  //FIXMEassign track_data_way_picked_o = track_mem_data_way_picked_r;
  //assign dma_track_mem_data_way_picked_o = track_mem_data_way_picked_i;
  //assign mhu_done_o = mhu_done;
  //assign mhu_stall_o = mhu_read_tag_and_stat_v_o | mhu_read_track_v_o | mhu_write_tag_and_stat_v_o;
 

  always_comb begin

    //chosen_way_n = chosen_way_r;

    dma_addr_o = '0;
    dma_cmd_o = e_dma_nop;

    //recover_o = '0;FIXME
    //mhu_done = '0;
    store_tag_miss_op_n = store_tag_miss_op_r;

    evict_v_o = '0;
    store_tag_miss_fill_v_o = '0;

    //mhu_read_tag_and_stat_v_o = '0;
    //mhu_read_track_v_o = '0;
    //mhu_write_tag_and_stat_v_o = '0;
    //mhu_write_track_v_o = '0;

    write_fill_data_in_progress_o = '0;
    evict_enqueued_o = '0;

    mhu_req_busy_o = '0;

    case (miss_state_r)

      // miss handler waits in this state, until the miss is detected in tv stage.
      // if an mshr miss of store tag miss happens during this state, set store tag miss op to 0.
      MHU_START: begin
        miss_state_n = mhu_activate_i
                     ? ((store_tag_miss_op_r & ~mshr_stm_miss_r) 
                         ? MHU_STORE_TAG_MISS 
                         : MHU_SEND_REFILL_ADDR)
                     : MHU_START;
        //mhu_read_tag_and_stat_v_o = mhu_activate_i & ~track_miss_r;
        //mhu_read_track_v_o = mhu_activate_i & track_miss_r;
        store_tag_miss_op_n = mhu_we_i 
                              ? store_tag_miss_op_i 
                              : (mshr_stm_miss_r
                                ? 1'b0
                                : store_tag_miss_op_r);
      end

      // Send out the missing cache block address (to read).
      // Choose a block to replace/fill.
      // If the chosen block is dirty, then take evict route.
      MHU_SEND_REFILL_ADDR: begin
        //chosen_way_n = chosen_way_i;
        dma_cmd_o = e_dma_send_refill_addr;         
        dma_addr_o = {
          curr_addr_tag,
          {(sets_p>1){curr_addr_index}},
          {(block_offset_width_lp){1'b0}}
        };

        // if it's not track miss or store tag miss, and the chosen way is dirty and valid,
        // or there's a store in tl which wants to write on the chosen way, then evict.
        miss_state_n = dma_done_i
                     ? (store_tag_miss_op_r
                       ? MHU_SEND_EVICT_DATA
                       : ((track_miss_r | (~(stat_info.dirty[chosen_way_r] & valid_v_r[chosen_way_r]))) //& ~tl_store_on_chosen_way_found_i))
                         ? MHU_WRITE_FILL_DATA 
                         //: ((~tl_store_on_chosen_way_found_i & ~sbuf_or_tbuf_chosen_way_found_i)
                         : (~sbuf_or_tbuf_chosen_way_found_i
                           ? MHU_SEND_EVICT_ADDR
                           : MHU_WAIT_SNOOP_DONE)))
                     : MHU_SEND_REFILL_ADDR;

        //mhu_write_tag_and_stat_v_o = (miss_state_n == MHU_WRITE_FILL_DATA) | (miss_state_n == MHU_SEND_EVICT_ADDR);
        //mhu_read_track_v_o = (miss_state_n == MHU_SEND_EVICT_ADDR); 
        //mhu_read_tag_and_stat_v_o = ~store_tag_miss_op_r & ~dma_done_i; 
        mhu_req_busy_o = 1'b1; 
        evict_v_o = (miss_state_n == MHU_SEND_EVICT_DATA);
        store_tag_miss_fill_v_o = (miss_state_n==MHU_SEND_EVICT_DATA);
        //mhu_write_track_v_o = (miss_state_n==MHU_SEND_EVICT_DATA) | (miss_state_n==MHU_WRITE_FILL_DATA);
      end
    
      // wait until there's no entry in sbuf/tbuf that has the same way as the chosen way,
      // and tl and tv don't have the chosen way either.
      MHU_WAIT_SNOOP_DONE: begin 
        miss_state_n = //(~tl_store_on_chosen_way_found_i & ~sbuf_or_tbuf_chosen_way_found_i)
                     ~sbuf_or_tbuf_chosen_way_found_i
                     ? MHU_SEND_EVICT_ADDR
                     : MHU_WAIT_SNOOP_DONE;

        //mhu_write_tag_and_stat_v_o = (miss_state_n == MHU_SEND_EVICT_ADDR);  
        //mhu_read_track_v_o = (miss_state_n == MHU_SEND_EVICT_ADDR); 
        mhu_req_busy_o = 1'b1;
      end

      // Send out the block addr for eviction, before initiating the eviction.
      MHU_SEND_EVICT_ADDR: begin
        dma_cmd_o = e_dma_send_evict_addr;
        dma_addr_o = {
          tag_mem_tag_way_picked_r,
          {(sets_p>1){curr_addr_index}},
          {(block_offset_width_lp){1'b0}}
        };

        miss_state_n = dma_done_i
                     ? ((store_tag_miss_op_r & mshr_stm_miss_r) 
                       ? MHU_SEND_REFILL_ADDR
                       : MHU_SEND_EVICT_DATA)
                     : MHU_SEND_EVICT_ADDR;

        //mhu_read_track_v_o = ~dma_done_i; 
        mhu_req_busy_o = 1'b1;
        evict_v_o = (miss_state_n==MHU_SEND_EVICT_DATA);
        store_tag_miss_fill_v_o = (miss_state_n==MHU_SEND_EVICT_DATA) & store_tag_miss_op_r;
        //mhu_write_track_v_o = (miss_state_n==MHU_SEND_EVICT_DATA) & store_tag_miss_fill_v_o;
      end

      // BUG: 如果dma的evict data一直不被yumi，会出现先返回refill的done
      // BUG: 再返回evict的done，这样虽然状态机仍是是对的，但是对于mshr cam中何时
      // BUG: 删除对应的entry会出现问题
      // TODO:has been fixed by 'write_fill_data_in_progress_o'

      // wait for dma to return evict done signal
      MHU_SEND_EVICT_DATA: begin
        miss_state_n = dma_done_i
                     ? MHU_WRITE_FILL_DATA
                     : MHU_SEND_EVICT_DATA;
        evict_enqueued_o = 1'b1;
      end

      // wait for dma to return refill done signal or transmitter to return store tag miss fill done signal
      MHU_WRITE_FILL_DATA: begin
        evict_enqueued_o = 1'b1;
        write_fill_data_in_progress_o = 1'b1;
        miss_state_n = (dma_done_i | transmitter_store_tag_miss_fill_done_i)
                     //? MHU_RECOVER FIXME
                     ? MHU_START //for now we don't need to recover anything after this finishes
                     : MHU_WRITE_FILL_DATA;
        //we update the track bits here cuz for track miss, we can only update them after all the data
        //has been written into DMEM, so any ld before that can know whether the word it's gonna read 
        //is valid or not. If it's valid, then there's no need to allocate a new read miss entry. 
        //If we don't do so, this read miss will use the dma snoop instead, which will lead to a wrong output.
        //mhu_write_track_v_o = (miss_state_n==MHU_RECOVER) & (~store_tag_miss_op_r | mshr_stm_miss_r);
      end

      MHU_STORE_TAG_MISS: begin
        miss_state_n = (~(stat_info.dirty[chosen_way_r] & valid_v_r[chosen_way_r])) //& ~tl_store_on_chosen_way_found_i)
                         ? MHU_WRITE_FILL_DATA 
                         //: ((~tl_store_on_chosen_way_found_i & ~sbuf_or_tbuf_chosen_way_found_i)
                         : (~sbuf_or_tbuf_chosen_way_found_i
                           ? MHU_SEND_EVICT_ADDR
                           : MHU_WAIT_SNOOP_DONE);

        //mhu_write_tag_and_stat_v_o = (miss_state_n == MHU_WRITE_FILL_DATA) | (miss_state_n == MHU_SEND_EVICT_ADDR);
        //mhu_read_track_v_o = (miss_state_n == MHU_SEND_EVICT_ADDR);  
        mhu_req_busy_o = 1'b1; 
        store_tag_miss_fill_v_o = (miss_state_n==MHU_WRITE_FILL_DATA);
        //mhu_write_track_v_o = (miss_state_n==MHU_WRITE_FILL_DATA);
      end

      // Spend one cycle to recover the tl stage.
      // By recovering, it means re-reading the mshr_cam, data_mem, tag_mem and track_mem for the tl stage.
      // MHU_RECOVER: begin
      //   recover_o = 1'b1;
      //   miss_state_n = recover_ack_i ? MHU_START : MHU_RECOVER;
      //   //mhu_done = recover_ack_i;
      // end

      // this should never happen, but if it does, go back to START;
      default: begin
        miss_state_n = MHU_START;
      end

    endcase
  end

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_mhu)
