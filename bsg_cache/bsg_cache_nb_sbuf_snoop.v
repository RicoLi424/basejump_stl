`include "bsg_defines.v"
`include "bsg_cache_nb.vh"

module bsg_cache_nb_sbuf_snoop
  import bsg_cache_nb_pkg::*;
  #(parameter `BSG_INV_PARAM(word_width_p)
    ,parameter `BSG_INV_PARAM(addr_width_p)
    ,parameter `BSG_INV_PARAM(ways_p)

    ,parameter way_id_width_lp=`BSG_SAFE_CLOG2(ways_p)
    ,parameter data_mask_width_lp=(word_width_p>>3)
    ,parameter sbuf_entry_width_lp=`bsg_cache_nb_sbuf_entry_width(addr_width_p,word_width_p,ways_p)
  )
  (
    input clk_i
    ,input reset_i

    ,input [sbuf_entry_width_lp-1:0] sbuf_entry_i
    ,input v_i
  
    ,output logic [sbuf_entry_width_lp-1:0] sbuf_entry_o
    ,output logic v_o
    ,input logic yumi_i

    ,output logic empty_o
    ,output logic full_o

    ,input [addr_width_p-1:0] bypass_addr_i
    ,input bypass_v_i
    ,output logic [word_width_p-1:0] bypass_data_o
    ,output logic [data_mask_width_lp-1:0] bypass_mask_o

    ,output logic [addr_width_p-1:0] el0_addr_snoop_o
    ,output logic [way_id_width_lp-1:0] el0_way_snoop_o
    ,output logic el0_valid_snoop_o

    ,output logic [addr_width_p-1:0] el1_addr_snoop_o
    ,output logic [way_id_width_lp-1:0] el1_way_snoop_o
    ,output logic el1_valid_snoop_o
  );

  // localparam
  //
  localparam lg_word_mask_width_lp=`BSG_SAFE_CLOG2(word_width_p>>3);

  `declare_bsg_cache_nb_sbuf_entry_s(addr_width_p, word_width_p, ways_p);
  bsg_cache_nb_sbuf_entry_s el0, el1;
  logic el0_valid, el1_valid;

  bsg_cache_nb_sbuf_entry_s sbuf_entry_in;
  assign sbuf_entry_in = sbuf_entry_i;

  // buffer queue
  bsg_cache_buffer_queue #(
    .width_p(sbuf_entry_width_lp)
  ) q0 (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.v_i(v_i)
    ,.data_i(sbuf_entry_in)

    ,.v_o(v_o)
    ,.data_o(sbuf_entry_o)
    ,.yumi_i(yumi_i)

    ,.el0_valid_o(el0_valid)
    ,.el1_valid_o(el1_valid)
    ,.el0_snoop_o(el0)
    ,.el1_snoop_o(el1)

    ,.empty_o(empty_o)
    ,.full_o(full_o)
  );

  // snoop
  //
  assign el0_addr_snoop_o = el0.addr;
  assign el0_way_snoop_o = el0.way_id;
  assign el0_valid_snoop_o = el0_valid;
  assign el1_addr_snoop_o = el1.addr;
  assign el1_way_snoop_o = el1.way_id;
  assign el1_valid_snoop_o = el1_valid;

  // bypassing
  //
  logic tag_hit0, tag_hit0_n;
  logic tag_hit1, tag_hit1_n;
  logic tag_hit2, tag_hit2_n;
  logic [addr_width_p-lg_word_mask_width_lp-1:0] bypass_word_addr;

  assign bypass_word_addr = bypass_addr_i[addr_width_p-1:lg_word_mask_width_lp];
  assign tag_hit0_n = bypass_word_addr == el0.addr[addr_width_p-1:lg_word_mask_width_lp]; 
  assign tag_hit1_n = bypass_word_addr == el1.addr[addr_width_p-1:lg_word_mask_width_lp]; 
  assign tag_hit2_n = bypass_word_addr == sbuf_entry_in.addr[addr_width_p-1:lg_word_mask_width_lp]; 

  assign tag_hit0 = tag_hit0_n & el0_valid;
  assign tag_hit1 = tag_hit1_n & el1_valid;
  assign tag_hit2 = tag_hit2_n & v_i;

  logic [(word_width_p>>3)-1:0] tag_hit0x4;
  logic [(word_width_p>>3)-1:0] tag_hit1x4;
  logic [(word_width_p>>3)-1:0] tag_hit2x4;
  
  assign tag_hit0x4 = {(word_width_p>>3){tag_hit0}};
  assign tag_hit1x4 = {(word_width_p>>3){tag_hit1}};
  assign tag_hit2x4 = {(word_width_p>>3){tag_hit2}};
   
  logic [word_width_p-1:0] el0or1_data;
  logic [word_width_p-1:0] bypass_data_n;
  logic [(word_width_p>>3)-1:0] bypass_mask_n;

  assign bypass_mask_n = (tag_hit0x4 & el0.mask)
    | (tag_hit1x4 & el1.mask)
    | (tag_hit2x4 & sbuf_entry_in.mask);

  bsg_mux_segmented #(
    .segments_p(word_width_p>>3)
    ,.segment_width_p(8) 
  ) mux_segmented_merge0 (
    .data0_i(el1.data)
    ,.data1_i(el0.data)
    ,.sel_i(tag_hit0x4 & el0.mask)
    ,.data_o(el0or1_data)
  );

  bsg_mux_segmented #(
    .segments_p(word_width_p>>3)
    ,.segment_width_p(8) 
  ) mux_segmented_merge1 (
    .data0_i(el0or1_data)
    ,.data1_i(sbuf_entry_in.data)
    ,.sel_i(tag_hit2x4 & sbuf_entry_in.mask)
    ,.data_o(bypass_data_n)
  );

  always_ff @ (posedge clk_i) begin
    if (reset_i) begin
      bypass_mask_o <= '0;
      bypass_data_o <= '0;
    end
    else begin
      if (bypass_v_i) begin
        bypass_mask_o <= bypass_mask_n;
        bypass_data_o <= bypass_data_n; 
      end
    end
  end


endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_sbuf_snoop)
