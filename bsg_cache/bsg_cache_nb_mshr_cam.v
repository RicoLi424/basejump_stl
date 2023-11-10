/*
 * Non blocking cache MSHR CAM
 */

`include "bsg_defines.v"

module bsg_cache_nb_mshr_cam
 #(parameter `BSG_INV_PARAM(mshr_els_p)
   , parameter `BSG_INV_PARAM(cache_line_offset_width_p)
   , parameter `BSG_INV_PARAM(word_width_p)
   , parameter `BSG_INV_PARAM(block_size_in_words_p)

   , parameter block_data_width_lp = block_size_in_words_p * word_width_p
   , parameter write_mask_width_lp = (block_data_width_lp>>3)
   , parameter lg_mshr_els_lp = `BSG_SAFE_CLOG2(mshr_els_p)
   
   , parameter safe_els_lp = `BSG_MAX(mshr_els_p,1)

   )
  (input                                      clk_i
   , input                                    reset_i

   // Synchronous write/invalidate of a tag
   // one or zero-hot
   , input [safe_els_lp-1:0]                  w_v_i
   , input                                    w_set_not_clear_i
   // Tag/data to set on write
   //, input                                    w_store_tag_miss_i
   //, input                                    w_track_miss_i
   //, input [block_size_in_words_p-1:0]        w_track_bits_i
   , input [cache_line_offset_width_p-1:0]    w_tag_i
   , input [block_data_width_lp-1:0]          w_data_i
   , input [write_mask_width_lp-1:0]          w_mask_i
   // Metadata useful for an external replacement policy
   // Whether there's an empty entry in the tag array
   , output [safe_els_lp-1:0]                 w_empty_o
   
   // Asynchronous read of a tag, if exists
   , input                                    r_by_tag_v_i
   , input [cache_line_offset_width_p-1:0]    r_tag_i
   , input                                    r_by_mshr_id_v_i
   , input [lg_mshr_els_lp-1:0]               r_mshr_id_i
   , output logic [write_mask_width_lp-1:0]   r_valid_bits_o
   //, output logic                             r_track_miss_o
   //, output logic [block_size_in_words_p-1:0] r_track_bits_o
   , output logic [block_data_width_lp-1:0]   r_data_o
   , output logic [safe_els_lp-1:0]           r_tag_match_o
   , output logic                             r_match_found_o
  );

  logic [safe_els_lp-1:0] tag_r_match_lo;
  logic [safe_els_lp-1:0] mshr_id_decode;
  logic [safe_els_lp-1:0] mem_r_v_li;

  assign mem_r_v_li = r_by_mshr_id_v_i
                    ? mshr_id_decode  
                    : ( r_by_tag_v_i 
                      ? tag_r_match_lo
                      : '0);
  
  bsg_decode #(
    .num_out_p(safe_els_lp)
  ) mshr_id_demux (
    .i(r_mshr_id_i)
    ,.o(mshr_id_decode)
  );

  // The cache line addr storage
  bsg_cam_1r1w_tag_array #(
    .width_p(cache_line_offset_width_p)
    ,.els_p(safe_els_lp)
  ) cam_tag_array (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.w_v_i(w_v_i)
    ,.w_set_not_clear_i(w_set_not_clear_i)
    ,.w_tag_i(w_tag_i)
    ,.w_empty_o(w_empty_o)

    ,.r_v_i(r_by_tag_v_i)
    ,.r_tag_i(r_tag_i)
    ,.r_match_o(tag_r_match_lo)
    );

  // The valid bits storage
  bsg_mem_1r1w_one_hot_mask_write_bit #(
    .width_p(write_mask_width_lp)
    ,.els_p(safe_els_lp)
  ) one_hot_valid_bits_mem (
    .w_clk_i(clk_i) 
    ,.w_reset_i(reset_i)

    ,.w_v_i(w_v_i)
    ,.w_data_i({(write_mask_width_lp){w_set_not_clear_i}})
    ,.w_mask_i(w_mask_i)

    ,.r_v_i(mem_r_v_li)
    ,.r_data_o(r_valid_bits_o)
    );
  
  // The data storage
  bsg_mem_1r1w_one_hot_mask_write_byte #(
    .width_p(block_data_width_lp)
    ,.els_p(safe_els_lp)
  ) one_hot_data_mem (
    .w_clk_i(clk_i)
    ,.w_reset_i(reset_i)

    ,.w_v_i(w_v_i)
    ,.w_data_i(w_data_i)
    ,.w_mask_i(w_mask_i)

    ,.r_v_i(mem_r_v_li)
    ,.r_data_o(r_data_o)
    );
  
  // The track bits storage
  // put this in mhu's reg
  /*
  bsg_mem_1r1w_one_hot #(
    .width_p(1+block_size_in_words_p)
    ,.els_p(safe_els_lp)
  ) one_hot_track_mem (
    .w_clk_i(clk_i)
    ,.w_reset_i(reset_i)

    ,.w_v_i(w_v_i)
    ,.w_data_i({w_track_miss_i,w_track_bits_i})

    ,.r_v_i(tag_r_match_lo)
    ,.r_data_o({r_track_miss_o,r_track_bits_o})
  );
  */

  assign r_tag_match_o = tag_r_match_lo;
  assign r_match_found_o = |tag_r_match_lo;

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_mshr_cam)