`include "bsg_defines.v"

module bsg_cache_nb_evict_fill_transmitter
    #( parameter `BSG_INV_PARAM(addr_width_p),
       parameter `BSG_INV_PARAM(word_width_p), 
       parameter `BSG_INV_PARAM(dma_data_width_p),
       parameter `BSG_INV_PARAM(block_size_in_words_p),
       parameter `BSG_INV_PARAM(sets_p),
       parameter `BSG_INV_PARAM(ways_p),
       parameter `BSG_INV_PARAM(mshr_els_p),

       parameter lg_sets_lp=`BSG_SAFE_CLOG2(sets_p),
       parameter lg_ways_lp=`BSG_SAFE_CLOG2(ways_p),
       parameter lg_block_size_in_words_lp=`BSG_SAFE_CLOG2(block_size_in_words_p),
       parameter lg_mshr_els_lp=`BSG_SAFE_CLOG2(mshr_els_p),

       parameter num_of_words_per_bank_lp=(block_size_in_words_p/2),
       parameter num_of_burst_per_bank_lp=(num_of_words_per_bank_lp*word_width_p/dma_data_width_p),
       parameter lg_num_of_burst_per_bank_lp=`BSG_SAFE_CLOG2(num_of_burst_per_bank_lp),

       parameter dma_data_mask_width_lp=(dma_data_width_p>>3),
       parameter word_mask_width_lp=(word_width_p>>3),
       parameter bank_data_mask_width_lp=(dma_data_mask_width_lp*num_of_burst_per_bank_lp),

       parameter block_data_width_lp= (block_size_in_words_p*word_width_p),
       parameter block_data_mask_width_lp=(block_data_width_lp>>3),

       parameter burst_size_in_words_lp=(dma_data_width_p/word_width_p),

       parameter data_bank_els_lp=(sets_p*num_of_burst_per_bank_lp),
       parameter lg_data_bank_els_lp=`BSG_SAFE_CLOG2(data_bank_els_lp)
     )
    (input clk_i
     , input reset_i
     
     , input evict_we_i
     //, input evict_en_i

     , input refill_we_i
     //, input refill_en_i

     // for store tag miss case which only needs to write one or some specific words from mshr to dmem
     , input store_tag_miss_we_i

     , input transmitter_fill_hold_i

     , input [lg_mshr_els_lp-1:0] mshr_id_i

     , input [lg_ways_lp-1:0] way_i
     , input [lg_sets_lp-1:0] addr_index_i

     , output logic [lg_ways_lp-1:0] current_way_o
     , output logic [lg_sets_lp-1:0] current_addr_index_o

     // for track miss refill
     , input track_miss_i
     , input [`BSG_SAFE_MINUS(block_size_in_words_p,1):0] track_data_way_picked_i

     //, input store_tag_miss_en_i
     , input [`BSG_SAFE_MINUS(block_data_width_lp,1):0] mshr_data_i
     // TODO: maybe unnecassary to output this counter
     , output logic [`BSG_WIDTH(num_of_burst_per_bank_lp)-1:0] mshr_data_write_counter_o
     // This could be used for both store tag miss and track miss refill
     , input [`BSG_SAFE_MINUS(block_data_mask_width_lp,1):0] mshr_data_byte_mask_i
     , input [`BSG_SAFE_MINUS(mshr_els_p,1):0] mhu_write_fill_data_in_progress_i

     // when next load / sbuf is accessing odd bank, or even bank gets the priority
     , input even_bank_v_i
     , output logic even_bank_v_o
     , output logic even_bank_w_o
     , output logic [ways_p-1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] even_bank_data_o
     , output logic [ways_p-1:0][dma_data_mask_width_lp-1:0] even_bank_w_mask_o
     , input [ways_p-1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] even_bank_data_i
     , output logic [lg_data_bank_els_lp-1:0] even_bank_addr_o
     , output logic [`BSG_WIDTH(num_of_burst_per_bank_lp)-1:0] even_counter_o

     // when next ld / sbuf is accessing even bank, or odd bank gets the priority
     , input odd_bank_v_i
     , output logic odd_bank_v_o
     , output logic odd_bank_w_o
     , output logic [ways_p-1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] odd_bank_data_o
     , output logic [ways_p-1:0][dma_data_mask_width_lp-1:0] odd_bank_w_mask_o
     , input [ways_p-1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] odd_bank_data_i
     , output logic [lg_data_bank_els_lp-1:0] odd_bank_addr_o
     , output logic [`BSG_WIDTH(num_of_burst_per_bank_lp)-1:0] odd_counter_o


     , output logic dma_refill_ready_o
     , input [1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] dma_refill_data_i
     , input dma_refill_v_i

     , output logic dma_evict_v_o
     , output logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] dma_evict_data_o
     , input dma_evict_yumi_i
     , output logic [lg_mshr_els_lp-1:0] mshr_id_o

     , output logic even_fifo_priority_o
     , output logic odd_fifo_priority_o

     , output logic data_mem_access_done_o

     , output logic dma_refill_done_o
     , output logic evict_data_sent_to_dma_done_o
     , output logic [`BSG_SAFE_MINUS(mshr_els_p,1):0] mhu_store_tag_miss_fill_done_o

     , output logic refill_in_progress_o
     , output logic evict_in_progress_o
     , output logic store_tag_miss_fill_in_progress_o
     );

     localparam byte_offset_width_lp=`BSG_SAFE_CLOG2(word_width_p>>3);
     localparam block_offset_width_lp=(block_size_in_words_p > 1) ? byte_offset_width_lp+lg_block_size_in_words_lp : byte_offset_width_lp;

     logic even_fifo_ready_lo, odd_fifo_ready_lo;
     logic even_fifo_v_li, odd_fifo_v_li;
     logic even_fifo_v_lo, odd_fifo_v_lo;
     logic even_fifo_yumi_li, odd_fifo_yumi_li;

     logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] even_fifo_data_li, odd_fifo_data_li;
     logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] even_fifo_data_lo, odd_fifo_data_lo;

    // bank fifos to dma
     logic [1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] evict2dma_data_lo;
     logic piso_ready_lo;
     logic piso_valid_li;

    // dma to bank fifos
     logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] even_bank_fill_data;
     logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] odd_bank_fill_data;

    // store tag miss 
     logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] mshr_data_low_li;
     logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] mshr_data_high_li;

     logic [`BSG_WIDTH(num_of_burst_per_bank_lp+1)-1:0] even_counter_r;
     logic [`BSG_WIDTH(num_of_burst_per_bank_lp+1)-1:0] odd_counter_r;
     logic [`BSG_WIDTH(num_of_burst_per_bank_lp)-1:0] write_data_into_fifos_counter_r;

     logic even_fifo_done, odd_fifo_done;
     logic data_writing_into_fifos_done; 

     logic evict_en_r, refill_en_r, store_tag_miss_en_r;
     logic track_miss_r;
     logic [lg_mshr_els_lp-1:0] mshr_id_r;
     logic [lg_ways_lp-1:0] way_r;
     logic [lg_sets_lp-1:0] addr_index_r;
     logic [`BSG_SAFE_MINUS(block_size_in_words_p,1):0] track_data_way_picked_r;
     logic [`BSG_SAFE_MINUS(block_data_width_lp,1):0] mshr_data_r;
     logic [`BSG_SAFE_MINUS(block_data_mask_width_lp,1):0] mshr_data_word_mask_r;

     /*
     logic mhu_write_fill_data_in_progress_mux_lo;
     bsg_mux #(
       .width_p(1)
       ,.els_p(mshr_els_p)
     ) mhu_write_fill_in_progress_mux (
       .data_i(mhu_write_fill_data_in_progress_i)
       ,.sel_i(mshr_id_r)
       ,.data_o(mhu_write_fill_data_in_progress_mux_lo)
     );
     */

     logic [`BSG_SAFE_MINUS(dma_data_width_p,1):0] even_bank_data_way_picked, odd_bank_data_way_picked;

     bsg_mux #(
       .width_p(dma_data_width_p)
       ,.els_p(ways_p)
     ) even_bank_data_in_mux (
       .data_i(even_bank_data_i)
       ,.sel_i(way_r)
       ,.data_o(even_bank_data_way_picked)
     );

     bsg_mux #(
       .width_p(dma_data_width_p)
       ,.els_p(ways_p)
     ) odd_bank_data_in_mux (
       .data_i(odd_bank_data_i)
       ,.sel_i(way_r)
       ,.data_o(odd_bank_data_way_picked)
     );

     wire filling_en = (refill_en_r|store_tag_miss_en_r);

     // when evict_en_r = 1, even/odd counter increments when these conditions are met
     // we sort this out separately because at the first clk edge of eviction, we want the counters up
     // while we don't wanna fifos to take in data as the data hasn't been read from dmem yet
     logic evict_even_counter_en_li, evict_odd_counter_en_li;
     assign evict_even_counter_en_li = (evict_en_r & even_bank_v_i & ~even_fifo_done & even_fifo_ready_lo);
     assign evict_odd_counter_en_li = (evict_en_r & odd_bank_v_i & ~odd_fifo_done & odd_fifo_ready_lo);

     // counter for store tag miss writing mshr data (or refill writing data from sipo into fifos)
     bsg_counter_set_en #(
      .max_val_p(num_of_burst_per_bank_lp)
     ) write_data_into_fifos_counter (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.set_i(dma_refill_done_o | (|mhu_store_tag_miss_fill_done_o))                                                                       
      ,.en_i(filling_en & even_fifo_ready_lo & odd_fifo_ready_lo & ~data_writing_into_fifos_done)
      ,.val_i('0)
      ,.count_o(write_data_into_fifos_counter_r)
     );


     bsg_fifo_1r1w_small #(
      .width_p(dma_data_width_p)
      ,.els_p(num_of_burst_per_bank_lp) 
     ) even_fifo ( 
      .clk_i(clk_i)
      ,.reset_i(reset_i)

      ,.data_i(even_fifo_data_li)
      ,.v_i(even_fifo_v_li)
      ,.ready_o(even_fifo_ready_lo)

      ,.v_o(even_fifo_v_lo)
      ,.data_o(even_fifo_data_lo)
      ,.yumi_i(even_fifo_yumi_li)
      ); 

     bsg_counter_set_en #(
      .max_val_p(num_of_burst_per_bank_lp+1)
      ) even_counter (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.set_i(evict_data_sent_to_dma_done_o | dma_refill_done_o | (|mhu_store_tag_miss_fill_done_o))
      ,.en_i(evict_even_counter_en_li | (filling_en & even_fifo_yumi_li))
      ,.val_i('0)
      ,.count_o(even_counter_r)
      );

     assign even_fifo_data_li = evict_en_r ? even_bank_data_way_picked : even_bank_fill_data;
     assign even_fifo_v_li = (evict_even_counter_en_li & (even_counter_r>0)) | (((refill_en_r & dma_refill_v_i) | (store_tag_miss_en_r & ~data_writing_into_fifos_done)) & odd_fifo_ready_lo);
     assign even_fifo_yumi_li = even_fifo_v_lo & (evict_en_r ? (odd_fifo_v_lo & piso_ready_lo) : even_bank_v_i);

     bsg_fifo_1r1w_small #(
      .width_p(dma_data_width_p)
      ,.els_p(num_of_burst_per_bank_lp) 
      ) odd_fifo ( 
      .clk_i(clk_i)
      ,.reset_i(reset_i)

      ,.data_i(odd_fifo_data_li)
      ,.v_i(odd_fifo_v_li)
      ,.ready_o(odd_fifo_ready_lo)

      ,.v_o(odd_fifo_v_lo)
      ,.data_o(odd_fifo_data_lo)
      ,.yumi_i(odd_fifo_yumi_li)
      ); 
     
     bsg_counter_set_en #(
      .max_val_p(num_of_burst_per_bank_lp+1)
     ) odd_counter (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.set_i(evict_data_sent_to_dma_done_o | dma_refill_done_o | (|mhu_store_tag_miss_fill_done_o))
      ,.en_i(evict_odd_counter_en_li | (filling_en & odd_fifo_yumi_li))
      ,.val_i('0)
      ,.count_o(odd_counter_r)
      );

     assign odd_fifo_data_li = evict_en_r ? odd_bank_data_way_picked : odd_bank_fill_data;
     assign odd_fifo_v_li =  (evict_odd_counter_en_li & (odd_counter_r>0)) | (((refill_en_r & dma_refill_v_i) | (store_tag_miss_en_r & ~data_writing_into_fifos_done)) & odd_fifo_ready_lo);
     assign odd_fifo_yumi_li = odd_fifo_v_lo & (evict_en_r ? (even_fifo_v_lo & piso_ready_lo) : odd_bank_v_i);

     assign dma_refill_ready_o = refill_en_r & even_fifo_ready_lo & odd_fifo_ready_lo;
     

     // bank fifos to dma
     bsg_gear_combinator #(
      .width_p(word_width_p)
      ,.els_p(burst_size_in_words_lp)
     ) evict_combinator (
      .data0_i(odd_fifo_data_lo)
      ,.data1_i(even_fifo_data_lo)
      ,.data0_o(evict2dma_data_lo[1])
      ,.data1_o(evict2dma_data_lo[0])
     );

     bsg_parallel_in_serial_out #(
      .width_p(dma_data_width_p)
      ,.els_p(2)
     ) piso (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.valid_i(piso_valid_li)
      ,.data_i(evict2dma_data_lo)
      ,.ready_and_o(piso_ready_lo)
      ,.valid_o(dma_evict_v_o)
      ,.data_o(dma_evict_data_o)
      ,.yumi_i(dma_evict_yumi_i)
     );

     assign piso_valid_li = evict_en_r & (even_fifo_v_lo & odd_fifo_v_lo);


     // dma to bank fifos
     bsg_gear_splitter #(
      .width_p(word_width_p)
      ,.els_p(burst_size_in_words_lp)
     ) fill_splitter (
      .data0_i(store_tag_miss_en_r ? mshr_data_low_li : dma_refill_data_i[0])
      ,.data1_i(store_tag_miss_en_r ? mshr_data_high_li : dma_refill_data_i[1])
      ,.data0_o(even_bank_fill_data)
      ,.data1_o(odd_bank_fill_data)
     );


    // way mask
     logic [ways_p-1:0] way_mask;
     logic [ways_p-1:0][dma_data_mask_width_lp-1:0] way_mask_expanded;

     bsg_decode #(
      .num_out_p(ways_p)
     ) dma_way_demux (
      .i(way_r)
      ,.o(way_mask)
     );

     bsg_expand_bitmask #(
      .in_width_p(ways_p)
      ,.expand_p(dma_data_mask_width_lp)
     ) expand_way (
      .i(way_mask)
      ,.o(way_mask_expanded)
     );
    

    // track bits sel and expand, then set some bits to 0 if that mshr byte mask is 1
     logic [num_of_words_per_bank_lp-1:0] even_track_bits_picked;
     logic [num_of_words_per_bank_lp-1:0] odd_track_bits_picked;
     logic [burst_size_in_words_lp-1:0] even_track_bits_offset_picked;
     logic [burst_size_in_words_lp-1:0] odd_track_bits_offset_picked;
     logic [dma_data_mask_width_lp-1:0] even_track_bits_offset_picked_expanded;
     logic [dma_data_mask_width_lp-1:0] odd_track_bits_offset_picked_expanded;
     logic [dma_data_mask_width_lp-1:0] even_track_bits_offset_picked_expanded_combined;
     logic [dma_data_mask_width_lp-1:0] odd_track_bits_offset_picked_expanded_combined;

     logic [dma_data_mask_width_lp-1:0] refill_even_bank_w_mask_offset_picked;
     logic [dma_data_mask_width_lp-1:0] refill_odd_bank_w_mask_offset_picked;

     bsg_gear_splitter #(
      .width_p(1)
      ,.els_p(num_of_words_per_bank_lp)
     ) track_bits_splitter (
      .data0_i(track_data_way_picked_r[0+:num_of_words_per_bank_lp])
      ,.data1_i(track_data_way_picked_r[num_of_words_per_bank_lp+:num_of_words_per_bank_lp])
      ,.data0_o(even_track_bits_picked)
      ,.data1_o(odd_track_bits_picked)
     );

     bsg_mux #(
      .width_p(burst_size_in_words_lp)
      ,.els_p(num_of_burst_per_bank_lp)
     ) even_track_offset_mux (
      .data_i(even_track_bits_picked)
      ,.sel_i(even_counter_r[0+:lg_num_of_burst_per_bank_lp])
      ,.data_o(even_track_bits_offset_picked)
     );

     bsg_mux #(
      .width_p(burst_size_in_words_lp)
      ,.els_p(num_of_burst_per_bank_lp)
     ) odd_track_offset_mux (
      .data_i(odd_track_bits_picked)
      ,.sel_i(odd_counter_r[0+:lg_num_of_burst_per_bank_lp])
      ,.data_o(odd_track_bits_offset_picked)
     );

     bsg_expand_bitmask #(
      .in_width_p(burst_size_in_words_lp)
      ,.expand_p(word_mask_width_lp)
     ) expand_even_track (
      .i(even_track_bits_offset_picked)
      ,.o(even_track_bits_offset_picked_expanded)
     );

     bsg_expand_bitmask #(
      .in_width_p(burst_size_in_words_lp)
      ,.expand_p(word_mask_width_lp)
     ) expand_odd_track (
      .i(odd_track_bits_offset_picked)
      ,.o(odd_track_bits_offset_picked_expanded)
     );

     // This could be used for both store tag miss and track miss refill
     logic [bank_data_mask_width_lp-1:0] even_mshr_byte_mask_bits_picked;
     logic [bank_data_mask_width_lp-1:0] odd_mshr_byte_mask_bits_picked;
     logic [dma_data_mask_width_lp-1:0] even_mshr_byte_mask_bits_offset_picked;
     logic [dma_data_mask_width_lp-1:0] odd_mshr_byte_mask_bits_offset_picked;

     bsg_gear_splitter #(
      .width_p(word_mask_width_lp)
      ,.els_p(num_of_words_per_bank_lp)
     ) refill_mshr_byte_mask_bits_splitter (
      .data0_i(mshr_data_word_mask_r[0+:bank_data_mask_width_lp])
      ,.data1_i(mshr_data_word_mask_r[bank_data_mask_width_lp+:bank_data_mask_width_lp])
      ,.data0_o(even_mshr_byte_mask_bits_picked)
      ,.data1_o(odd_mshr_byte_mask_bits_picked)
     );

     bsg_mux #(
      .width_p(dma_data_mask_width_lp)
      ,.els_p(num_of_burst_per_bank_lp)
     ) even_refill_mshr_mask_bits_offset_mux (
      .data_i(even_mshr_byte_mask_bits_picked)
      ,.sel_i(even_counter_r[0+:lg_num_of_burst_per_bank_lp])
      ,.data_o(even_mshr_byte_mask_bits_offset_picked)
     );

     bsg_mux #(
      .width_p(dma_data_mask_width_lp)
      ,.els_p(num_of_burst_per_bank_lp)
     ) odd_refill_mshr_mask_bits_offset_mux (
      .data_i(odd_mshr_byte_mask_bits_picked)
      ,.sel_i(odd_counter_r[0+:lg_num_of_burst_per_bank_lp])
      ,.data_o(odd_mshr_byte_mask_bits_offset_picked)
     );


     // This is for when mshr mask bits are from DMA's refill but not store tag miss
     // We need to set a track bit to 0 if the corresponding mshr byte mask bit is 1
     // Since for track miss, the track bits stored in mhu could be out of date
     // as there could be store instructions to the current valid words
     // so in that case some bytes in current valid words also need to be overwritten
     bsg_mux_segmented #(
      .segments_p(dma_data_mask_width_lp)
      ,.segment_width_p(1)
     ) combine_mshr_mask_with_even_track_expanded (
      .data0_i(even_track_bits_offset_picked_expanded)
      ,.data1_i({dma_data_mask_width_lp{1'b0}})
      ,.sel_i(even_mshr_byte_mask_bits_offset_picked)
      ,.data_o(even_track_bits_offset_picked_expanded_combined)
     );

     bsg_mux_segmented #(
      .segments_p(dma_data_mask_width_lp)
      ,.segment_width_p(1)
     ) combine_mshr_mask_with_odd_track_expanded (
      .data0_i(odd_track_bits_offset_picked_expanded)
      ,.data1_i({dma_data_mask_width_lp{1'b0}})
      ,.sel_i(odd_mshr_byte_mask_bits_offset_picked)
      ,.data_o(odd_track_bits_offset_picked_expanded_combined)
     );

     assign refill_even_bank_w_mask_offset_picked = track_miss_r ? ~even_track_bits_offset_picked_expanded_combined : {dma_data_mask_width_lp{1'b1}};
     assign refill_odd_bank_w_mask_offset_picked = track_miss_r ? ~odd_track_bits_offset_picked_expanded_combined : {dma_data_mask_width_lp{1'b1}};
     
     wire [lg_num_of_burst_per_bank_lp-1:0] write_data_into_fifos_counter_low_bits = write_data_into_fifos_counter_r[0+:lg_num_of_burst_per_bank_lp];
     assign mshr_data_low_li = mshr_data_r[(dma_data_width_p*(2*write_data_into_fifos_counter_low_bits))+:dma_data_width_p];
     assign mshr_data_high_li = mshr_data_r[(dma_data_width_p*(2*write_data_into_fifos_counter_low_bits+1))+:dma_data_width_p];

     assign odd_bank_data_o = {ways_p{odd_fifo_data_lo}};
     assign even_bank_data_o = {ways_p{even_fifo_data_lo}};
     assign odd_bank_w_mask_o = way_mask_expanded & {ways_p{store_tag_miss_en_r ? odd_mshr_byte_mask_bits_offset_picked : refill_odd_bank_w_mask_offset_picked}};
     assign even_bank_w_mask_o = way_mask_expanded & {ways_p{store_tag_miss_en_r ? even_mshr_byte_mask_bits_offset_picked : refill_even_bank_w_mask_offset_picked}};
     //assign odd_bank_w_mask_o = way_mask_expanded & {ways_p{store_tag_miss_en_r ? odd_mshr_byte_mask_bits_offset_picked : {dma_data_mask_width_lp{1'b1}}}};
     //assign even_bank_w_mask_o = way_mask_expanded & {ways_p{store_tag_miss_en_r ? even_mshr_byte_mask_bits_offset_picked : {dma_data_mask_width_lp{1'b1}}}};
     
     // TODO: 这里如果利用track bits就可以有些时候不用读bank，那么假如一开始读的一直是另一个bank，
     // TODO：需要后面一直给这个bank priority的时候，由于有几个burst不用读，就可以减少cache stall的cycles
     //assign odd_bank_v_o = odd_bank_v_i & ((evict_en_r & (odd_fifo_ready_lo & (|odd_track_bits_offset_picked) & ~odd_fifo_done)) | (filling_en & odd_fifo_v_lo));
     assign odd_bank_v_o = odd_bank_v_i & ((evict_en_r & (odd_fifo_ready_lo & ~odd_fifo_done)) | (filling_en & odd_fifo_v_lo));
     assign odd_bank_w_o = filling_en & odd_bank_v_i & odd_fifo_v_lo;

     //assign even_bank_v_o = even_bank_v_i & ((evict_en_r & (even_fifo_ready_lo & (|even_track_bits_offset_picked) & ~even_fifo_done)) | (filling_en & even_fifo_v_lo));
     assign even_bank_v_o = even_bank_v_i & ((evict_en_r & (even_fifo_ready_lo & ~even_fifo_done)) | (filling_en & even_fifo_v_lo));
     assign even_bank_w_o = filling_en & even_bank_v_i & even_fifo_v_lo;

     if (num_of_burst_per_bank_lp == 1) begin
       assign even_bank_addr_o = addr_index_r;
       assign odd_bank_addr_o = addr_index_r;
     end else begin
       assign even_bank_addr_o = {
         {(sets_p>1){addr_index_r}},
         even_counter_r[0+:lg_num_of_burst_per_bank_lp]
       };
       assign odd_bank_addr_o = {
         {(sets_p>1){addr_index_r}},
         odd_counter_r[0+:lg_num_of_burst_per_bank_lp]
       };
     end

     assign even_counter_o = even_counter_r;
     assign odd_counter_o = odd_counter_r;
     assign mshr_data_write_counter_o = write_data_into_fifos_counter_r;

     assign even_fifo_done = (evict_en_r & (even_counter_r==num_of_burst_per_bank_lp+1)) | (filling_en & (even_counter_r==num_of_burst_per_bank_lp));
     assign odd_fifo_done = (evict_en_r & (odd_counter_r==num_of_burst_per_bank_lp+1)) | (filling_en & (odd_counter_r==num_of_burst_per_bank_lp));
     assign data_writing_into_fifos_done = (write_data_into_fifos_counter_r == num_of_burst_per_bank_lp);

     assign odd_fifo_priority_o = even_fifo_done && ~odd_fifo_done;
     assign even_fifo_priority_o = odd_fifo_done && ~even_fifo_done;

     assign data_mem_access_done_o = even_fifo_done & odd_fifo_done;

     assign current_way_o = way_r;
     assign current_addr_index_o = addr_index_r;
     
     assign dma_refill_done_o = refill_en_r & data_mem_access_done_o;
     assign store_tag_miss_fill_done = store_tag_miss_en_r & data_mem_access_done_o;
     assign evict_data_sent_to_dma_done_o = evict_en_r & data_mem_access_done_o & ~even_fifo_v_lo & ~odd_fifo_v_lo & ~dma_evict_v_o;

     for(genvar i=0; i<mshr_els_p; i++) begin: mhu_stm_fill_done
       assign mhu_store_tag_miss_fill_done_o[i] = (i==mshr_id_r) & mhu_write_fill_data_in_progress_i[i] & store_tag_miss_fill_done & ~transmitter_fill_hold_i;
     end

     assign refill_in_progress_o = refill_en_r;
     assign evict_in_progress_o = evict_en_r;
     assign store_tag_miss_fill_in_progress_o = store_tag_miss_en_r;

     assign mshr_id_o = mshr_id_r;


     always_ff @ (posedge clk_i) begin
       if (reset_i) begin
         evict_en_r <= 1'b0;
         mshr_id_r <= '0;
         refill_en_r <= 1'b0;
         way_r <= '0;
         addr_index_r <= '0;
         track_miss_r <= 1'b0;
         track_data_way_picked_r <= '0;
         store_tag_miss_en_r <= 1'b0;
         mshr_data_r <= '0;
         mshr_data_word_mask_r <= '0;
       end else begin
         if (evict_we_i) begin
           evict_en_r <= 1'b1;
         end 

         if (refill_we_i) begin
           refill_en_r <= 1'b1;
           track_miss_r <= track_miss_i;
           track_data_way_picked_r <= track_data_way_picked_i;
         end

        // if (evict_we_i | refill_we_i) begin
        //   track_miss_r <= track_miss_i;
        //   track_data_way_picked_r <= track_data_way_picked_i;
        // end
         
         if(refill_we_i | store_tag_miss_we_i) begin
           mshr_data_word_mask_r <= mshr_data_byte_mask_i;
         end

         if (store_tag_miss_we_i) begin
           store_tag_miss_en_r <= 1'b1;
           mshr_data_r <= mshr_data_i;
           //mshr_data_word_mask_r <= mshr_data_byte_mask_i;        
         end

         if (evict_we_i | store_tag_miss_we_i) begin
           mshr_id_r <= mshr_id_i;
         end

         if(evict_we_i | refill_we_i | store_tag_miss_we_i) begin
           way_r <= way_i;
           addr_index_r <= addr_index_i;
         end

         if(evict_data_sent_to_dma_done_o) evict_en_r <= 0;
         if(dma_refill_done_o) refill_en_r <= 0;
         if((|mhu_store_tag_miss_fill_done_o)) store_tag_miss_en_r <= 0;

       end
     end

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_evict_fill_transmitter)