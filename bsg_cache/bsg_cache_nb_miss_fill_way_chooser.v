`include "bsg_defines.v"
`include "bsg_cache_nb.vh"

module bsg_cache_nb_miss_fill_way_chooser
  import bsg_cache_nb_pkg::*;
  #(//parameter `BSG_INV_PARAM(addr_width_p)
    //,parameter `BSG_INV_PARAM(word_width_p)
    //,parameter `BSG_INV_PARAM(block_size_in_words_p)
    parameter `BSG_INV_PARAM(sets_p)
    ,parameter `BSG_INV_PARAM(ways_p)

    //,parameter lg_block_size_in_words_lp=`BSG_SAFE_CLOG2(block_size_in_words_p)
    ,parameter lg_sets_lp=`BSG_SAFE_CLOG2(sets_p)
    //,parameter lg_word_mask_width_lp=`BSG_SAFE_CLOG2(word_width_p>>3)
    //,parameter block_offset_width_lp=(block_size_in_words_p > 1) ? lg_word_mask_width_lp+lg_block_size_in_words_lp : lg_word_mask_width_lp
    ,parameter lg_ways_lp=`BSG_SAFE_CLOG2(ways_p)
    ,parameter stat_info_width_lp=`bsg_cache_nb_stat_info_width(ways_p)
  )
  (input [lg_sets_lp-1:0] addr_index_i
    ,input [ways_p-1:0] valid_i
    ,input [ways_p-1:0] lock_i

    ,input [stat_info_width_lp-1:0] stat_info_i

    ,input dma_refill_in_progress_i
    ,input [lg_sets_lp-1:0] dma_refill_addr_index_i
    ,input [lg_ways_lp-1:0] dma_refill_way_i

    ,input transmitter_store_tag_miss_fill_in_progress_i
    ,input [lg_sets_lp-1:0] transmitter_store_tag_miss_fill_addr_index_i
    ,input [lg_ways_lp-1:0] transmitter_store_tag_miss_fill_way_i    

    ,output logic [lg_ways_lp-1:0] chosen_way_o
    ,output logic no_available_way_o
  );

  `declare_bsg_cache_nb_stat_info_s(ways_p);
  bsg_cache_nb_stat_info_s stat_info_in;
  assign stat_info_in = stat_info_i;

  // Find the way that is invalid.
  //
  logic [lg_ways_lp-1:0] invalid_way_id;
  logic invalid_exist;

  bsg_priority_encode #(
    .width_p(ways_p)
    ,.lo_to_hi_p(1)
  ) invalid_way_pe (
    .i(~valid_i & ~lock_i) // invalid and unlocked
    ,.addr_o(invalid_way_id)
    ,.v_o(invalid_exist)
  );


  //logic [lg_sets_lp-1:0] addr_i_index;
  //logic [lg_sets_lp-1:0] dma_refill_addr_index;
  //logic [lg_sets_lp-1:0] transmitter_store_tag_miss_fill_addr_index;

  //assign addr_i_index = addr_i[block_offset_width_lp+:lg_sets_lp];
  //assign dma_refill_addr_index = dma_refill_addr_i[block_offset_width_lp+:lg_sets_lp];
  //assign transmitter_store_tag_miss_fill_addr_index = transmitter_store_tag_miss_fill_addr_i[block_offset_width_lp+:lg_sets_lp];

  // backup LRU
  // When the LRU way designated by the stats_mem_info is locked, a backup way is required for 
  // cache line replacement. In the current design, bsg_lru_pseudo_tree_backup takes the way with 
  // the shortest distance from the locked LRU way in the tree, as the backup option by overriding
  // some of the LRU bits, so that it avoids "LRU trap" from insufficient update on the LRU bits.
  // For now, there is not hardware logic to detect and handle the issue that all the ways in the
  // same set are lock. And it is a programmer's responsibility to make sure that there is at least 
  // one unlock way in a set at any time. 
  // Also if the 'waiting_for_fill_data' in stat info indicates a way has been chosen by another mhu
  // and is currently waiting for fill data, this way cannot be chosen either. Same as the way that 
  // is in refill process in dma (we have to count this in as we've cleared the 'waiting_for_fill_data' 
  // at the moment when the fill data enters the dma), and the way in fill process for stm in transmitter.

  logic [lg_ways_lp-1:0] lru_way_id;
  logic [ways_p-1:0] dma_curr_refill_way_decode;
  logic [ways_p-1:0] transmitter_curr_fill_way_decode;
  logic [ways_p-1:0] disabled_ways;
  logic [ways_p-2:0] modify_mask_lo;
  logic [ways_p-2:0] modify_data_lo;
  logic [ways_p-2:0] modified_lru_bits;

  wire dma_curr_refill_index_match = dma_refill_in_progress_i & (sets_p==1 ? 1'b1 : (addr_index_i == dma_refill_addr_index_i));
  wire transmitter_curr_refill_index_match = transmitter_store_tag_miss_fill_in_progress_i & (sets_p==1 ? 1'b1 : (addr_index_i == transmitter_store_tag_miss_fill_addr_index_i));

  bsg_decode_with_v #(
    .num_out_p(ways_p) 
  ) dma_curr_refill_way_demux (
    .i(dma_refill_way_i)
    ,.v_i(dma_curr_refill_index_match)
    ,.o(dma_curr_refill_way_decode)
  );

  bsg_decode_with_v #(
    .num_out_p(ways_p) 
  ) trans_curr_fill_way_demux (
    .i(transmitter_store_tag_miss_fill_way_i)
    ,.v_i(transmitter_curr_refill_index_match)
    ,.o(transmitter_curr_fill_way_decode)
  );

  assign disabled_ways = lock_i | stat_info_in.waiting_for_fill_data 
                         | dma_curr_refill_way_decode | transmitter_curr_fill_way_decode;

  assign no_available_way_o = (&disabled_ways);

  bsg_lru_pseudo_tree_backup #(
    .ways_p(ways_p)
  ) backup_lru (
    .disabled_ways_i(disabled_ways)
    ,.modify_mask_o(modify_mask_lo)
    ,.modify_data_o(modify_data_lo)
  );

  bsg_mux_bitwise #(
    .width_p(ways_p-1)
  ) lru_bit_mux (
    .data0_i(stat_info_in.lru_bits)
    ,.data1_i(modify_data_lo)
    ,.sel_i(modify_mask_lo)
    ,.data_o(modified_lru_bits)
  );

  bsg_lru_pseudo_tree_encode #(
    .ways_p(ways_p)
  ) lru_encode (
    .lru_i(modified_lru_bits)
    ,.way_id_o(lru_way_id)
  );

  assign chosen_way_o = invalid_exist ? invalid_way_id : lru_way_id;




endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_miss_fill_way_chooser)
