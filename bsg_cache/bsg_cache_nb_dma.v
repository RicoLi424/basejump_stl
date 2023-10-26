`include "bsg_defines.v"
`include "bsg_cache_nb.vh"

module bsg_cache_nb_dma
  import bsg_cache_nb_pkg::*;
  #(parameter `BSG_INV_PARAM(addr_width_p)
    ,parameter `BSG_INV_PARAM(word_width_p)
    ,parameter `BSG_INV_PARAM(block_size_in_words_p)
    ,parameter `BSG_INV_PARAM(sets_p)
    ,parameter `BSG_INV_PARAM(ways_p)
    ,parameter `BSG_INV_PARAM(dma_data_width_p)
    ,parameter `BSG_INV_PARAM(mshr_els_p)

    ,parameter safe_mshr_els_lp = `BSG_MAX(mshr_els_p,1)
    ,parameter lg_block_size_in_words_lp=`BSG_SAFE_CLOG2(block_size_in_words_p)
    ,parameter lg_sets_lp=`BSG_SAFE_CLOG2(sets_p)
    ,parameter lg_ways_lp=`BSG_SAFE_CLOG2(ways_p)
    ,parameter lg_mshr_els_lp=`BSG_SAFE_CLOG2(mshr_els_p)
    ,parameter word_mask_width_lp=(word_width_p>>3)
    ,parameter lg_word_mask_width_lp=`BSG_SAFE_CLOG2(word_mask_width_lp)
    ,parameter dma_data_mask_width_lp=(dma_data_width_p>>3)
    ,parameter num_of_burst_lp=(block_size_in_words_p*word_width_p/dma_data_width_p)
    ,parameter lg_num_of_burst_lp=`BSG_SAFE_CLOG2(num_of_burst_lp)
    ,parameter burst_size_in_words_lp=(dma_data_width_p/word_width_p)
    ,parameter lg_burst_size_in_words_lp=`BSG_SAFE_CLOG2(burst_size_in_words_lp)
    ,parameter block_data_width_lp= (block_size_in_words_p*word_width_p)
    ,parameter block_data_mask_width_lp=(block_data_width_lp>>3)
    ,parameter bsg_cache_nb_dma_pkt_width_lp=`bsg_cache_nb_dma_pkt_width(addr_width_p, block_size_in_words_p, mshr_els_p)
  
    ,parameter debug_p=0
  )
  (
    input clk_i
    , input reset_i

    // indicating the data being evicted now is for tag mgmt operation
    , input mgmt_v_i

    , input bsg_cache_nb_dma_cmd_e mhu_or_mgmt_cmd_i
    , input [addr_width_p-1:0] mhu_or_mgmt_req_addr_i
    , input [lg_mshr_els_lp-1:0] mhu_req_mshr_id_i
    , input [`BSG_SAFE_MINUS(block_size_in_words_p,1):0] track_mem_data_tl_way_picked_i

    , input mhu_refill_track_miss_i
    // TODO: this is used for both mhu and mgmt
    , input [`BSG_SAFE_MINUS(block_size_in_words_p,1):0] mhu_refill_track_data_way_picked_i
    , input [lg_ways_lp-1:0] mhu_refill_way_i
    , input [lg_sets_lp-1:0] mhu_refill_addr_index_i


    //TODO: combine to be an integrated signal
    //, output logic [`BSG_SAFE_MINUS(mshr_els_p,1):0] mhu_evict_done_o
    //, output logic [`BSG_SAFE_MINUS(mshr_els_p,1):0] mhu_req_done_o
    //, output logic [`BSG_SAFE_MINUS(mshr_els_p,1):0] mhu_refill_done_o

    // This signal is used to prevent a case where the yumi_i for evict data just doesn't come
    // but refill process has been finished, then the refill done signal will go to mhu earlier
    // than the evict done signal, which will cause the deletion of corresponding mshr entry
    // take place at wrong time
    , input [`BSG_SAFE_MINUS(mshr_els_p,1):0] mhu_write_fill_data_in_progress_i
    , input [`BSG_SAFE_MINUS(mshr_els_p,1):0] transmitter_mhu_store_tag_miss_done_i
    , output logic [`BSG_SAFE_MINUS(mshr_els_p,1):0] mhu_dma_done_o
    , output logic mgmt_dma_done_o

    // This is used for a load mshr miss in tv stage which wants to read the data not written in mshr 
    // but that cache line that is being refilled while not finish writing into DMEM yet
    // In this way a new read miss queue entry is unnecassary to be allocated
    , input [lg_block_size_in_words_lp-1:0] addr_block_offset_v_i
    , output logic [`BSG_WIDTH(num_of_burst_lp)-1:0] dma_refill_data_in_counter_o

    , output logic [word_width_p-1:0] snoop_word_o
    , output logic serve_read_miss_queue_v_o
    , input [lg_block_size_in_words_lp-1:0] read_miss_queue_word_offset_i
    , input [word_width_p-1:0] read_miss_queue_mshr_data_i
    , input [word_mask_width_lp-1:0] read_miss_queue_mshr_data_mask_i

    // TODO:should use an external mux to select the right one from readq's v_o output
    , input read_miss_queue_serve_v_i
    , input read_miss_queue_read_in_progress_i

    , output logic [bsg_cache_nb_dma_pkt_width_lp-1:0] dma_pkt_o
    , output logic dma_pkt_v_o
    , input dma_pkt_yumi_i

    , input [dma_data_width_p-1:0] dma_data_i
    , input [lg_mshr_els_lp-1:0] dma_refill_mshr_id_i  
    , input dma_data_v_i
    , output logic dma_data_ready_o
    , input dma_refill_hold_i
    , output logic [lg_mshr_els_lp-1:0] dma_refill_mshr_id_o

    // for MGMT refill
    , input [addr_width_p-1:0] addr_v_i
    , input [lg_ways_lp-1:0] mgmt_chosen_way_i

    , input [`BSG_SAFE_MINUS(block_data_width_lp,1):0] mshr_data_i
    , input [`BSG_SAFE_MINUS(block_data_mask_width_lp,1):0] mshr_data_byte_mask_i
    , output logic mshr_cam_r_v_o

    , output logic [dma_data_width_p-1:0] dma_data_o
    , output logic dma_data_v_o
    , input dma_data_yumi_i

    , input transmitter_refill_ready_i
    , output logic [1:0][`BSG_SAFE_MINUS(dma_data_width_p,1):0] transmitter_refill_data_o
    , output logic transmitter_track_miss_o
    , output logic [block_size_in_words_p-1:0] transmitter_track_data_way_picked_o
    , output logic transmitter_refill_v_o
    , output logic [lg_ways_lp-1:0] transmitter_refill_way_o
    , output logic [lg_sets_lp-1:0] transmitter_refill_addr_index_o
    , output logic [`BSG_SAFE_MINUS(block_data_mask_width_lp,1):0] transmitter_refill_mshr_data_byte_mask_o
    , input transmitter_refill_done_i

    // This could be later used for pipeline's data combination before writing into sipo
    // which could help reduce the numebr of stall cycles to some degree
    // (if there's a store instruction which wants to write data into the line which is being refilled)
    , output logic [`BSG_WIDTH(num_of_burst_lp)-1:0] dma_refill_data_out_to_sipo_counter_o
    , output logic dma_refill_data_in_done_o
    , output logic dma_refill_in_progress_o
    , output logic transmitter_refill_done_o

    , input transmitter_evict_v_i
    , input [`BSG_SAFE_MINUS(dma_data_width_p,1):0] transmitter_evict_data_i
    , output logic transmitter_evict_yumi_o
    , input [lg_mshr_els_lp-1:0] transmitter_evict_mshr_id_i

  );

  // localparam
  //
  localparam counter_width_lp=`BSG_SAFE_CLOG2(num_of_burst_lp+1);
  localparam byte_offset_width_lp=`BSG_SAFE_CLOG2(word_width_p>>3);
  localparam block_offset_width_lp=(block_size_in_words_p > 1) ? byte_offset_width_lp+lg_block_size_in_words_lp : byte_offset_width_lp;


  // dma packet
  //
  `declare_bsg_cache_nb_dma_pkt_s(addr_width_p, block_size_in_words_p, mshr_els_p);
  bsg_cache_nb_dma_pkt_s dma_pkt;

  // in fifo
  //
  logic in_fifo_v_lo;
  logic [dma_data_width_p-1:0] in_fifo_data_lo;
  logic in_fifo_yumi_li;
  logic in_fifo_valid_li;
  logic in_fifo_ready_lo;
  logic sipo_ready_lo;
  logic [dma_data_width_p-1:0] sipo_data_li;
  logic [lg_mshr_els_lp-1:0] dma_refill_mshr_id_r;

  // dma refill data in counter
  //
  logic refill_data_in_counter_clear;
  logic refill_data_in_counter_up;
  logic [counter_width_lp-1:0] dma_refill_data_in_counter_r;
  logic transmitter_refill_done_r;
  logic dma_refill_data_in_counter_max;

  // dma refill data out to sipo counter
  //
  logic refill_data_out_to_sipo_counter_clear;
  logic refill_data_out_to_sipo_counter_up;
  logic [counter_width_lp-1:0] dma_refill_data_out_to_sipo_counter_r;
  wire [lg_num_of_burst_lp-1:0] dma_refill_data_out_to_sipo_counter_low_bits = dma_refill_data_out_to_sipo_counter_r[0+:lg_num_of_burst_lp];

  bsg_fifo_1r1w_small #(
    .width_p(dma_data_width_p)
    ,.els_p((num_of_burst_lp<2) ? 2 : num_of_burst_lp)
  ) in_fifo (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.data_i(dma_data_i)
    ,.v_i(in_fifo_valid_li)
    ,.ready_o(in_fifo_ready_lo)
    ,.v_o(in_fifo_v_lo)
    ,.data_o(in_fifo_data_lo)
    ,.yumi_i(in_fifo_yumi_li)
  );

  assign in_fifo_valid_li = dma_data_v_i 
                          & (dma_refill_data_in_counter_r == 0 
                            ? ~dma_refill_hold_i 
                            : ~dma_refill_data_in_counter_max);
  assign dma_data_ready_o = in_fifo_ready_lo 
                          & (dma_refill_data_in_counter_r == 0 
                            ? ~dma_refill_hold_i 
                            : ~dma_refill_data_in_counter_max);
  assign in_fifo_yumi_li = in_fifo_v_lo & sipo_ready_lo;

  // use mshr data if that byte is written in mshr cam
  logic [`BSG_SAFE_MINUS(block_data_width_lp,1):0] mshr_data_r;
  logic [`BSG_SAFE_MINUS(block_data_mask_width_lp,1):0] mshr_data_byte_mask_r;

  bsg_mux_segmented #(
    .segments_p(dma_data_mask_width_lp)
    ,.segment_width_p(8)
  ) combine_mshr_data (
    .data0_i(in_fifo_data_lo)
    ,.data1_i(mshr_data_r[dma_refill_data_out_to_sipo_counter_low_bits*dma_data_width_p +: dma_data_width_p])
    ,.sel_i(mshr_data_byte_mask_r[dma_refill_data_out_to_sipo_counter_low_bits*dma_data_mask_width_lp +: dma_data_mask_width_lp])
    ,.data_o(sipo_data_li)
  );

  bsg_serial_in_parallel_out_full #(
    .width_p(dma_data_width_p)
    ,.els_p(2)
  ) sipo (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.v_i(in_fifo_v_lo)
    ,.ready_o(sipo_ready_lo)
    ,.data_i(sipo_data_li) 
    ,.data_o(transmitter_refill_data_o)
    ,.v_o(transmitter_refill_v_o)
    ,.yumi_i(sipo_yumi_li)
  );

  assign sipo_yumi_li = transmitter_refill_v_o & transmitter_refill_ready_i;

  wire dma_refill_done = ~serve_read_miss_queue_v_o & transmitter_refill_done_r; 

  logic [`BSG_SAFE_MINUS(mshr_els_p,1):0] dma_refill_done_v_lo;

  bsg_counter_clear_up #(
    .max_val_p(num_of_burst_lp)
   ,.init_val_p('0)
  ) dma_refill_data_in_counter (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.clear_i(refill_data_in_counter_clear)
    ,.up_i(refill_data_in_counter_up)
    ,.count_o(dma_refill_data_in_counter_r)
  );

  assign dma_refill_data_in_counter_max = (dma_refill_data_in_counter_r == num_of_burst_lp);
  assign refill_data_in_counter_up = in_fifo_valid_li & in_fifo_ready_lo;
  assign refill_data_in_counter_clear = mgmt_v_i ? dma_refill_done : (|dma_refill_done_v_lo);

  assign serve_read_miss_queue_v_o = ~mgmt_v_i & dma_refill_data_in_counter_max & read_miss_queue_serve_v_i;
  assign dma_refill_in_progress_o = (dma_refill_data_in_counter_r>0);
  assign dma_refill_data_in_done_o = dma_refill_data_in_counter_max;
  assign dma_refill_data_in_counter_o = dma_refill_data_in_counter_r;

  bsg_counter_clear_up #(
    .max_val_p(num_of_burst_lp)
   ,.init_val_p('0)
  ) dma_refill_data_out_to_sipo_counter (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.clear_i(refill_data_out_to_sipo_counter_clear)
    ,.up_i(refill_data_out_to_sipo_counter_up)
    ,.count_o(dma_refill_data_out_to_sipo_counter_r)
  );

  //wire dma_refill_data_out_to_sipo_counter_max = (dma_refill_data_out_to_sipo_counter_r == num_of_burst_lp);
  assign refill_data_out_to_sipo_counter_up = in_fifo_v_lo & sipo_ready_lo;
  assign refill_data_out_to_sipo_counter_clear = refill_data_in_counter_clear;


  //for(genvar i=0; i<safe_mshr_els_lp; i++) begin
  //  assign mhu_refill_done_o[i] = (i==dma_refill_mshr_id_r) ? dma_refill_done : 1'b0;
  //end


  bsg_dff_reset_en_bypass #(
    .width_p(1)
  ) transmitter_refill_done_dff_bypass (
    .clk_i(clk_i)
    ,.reset_i(reset_i | refill_data_in_counter_clear)
    ,.en_i(transmitter_refill_done_i)
    ,.data_i(1'b1)
    ,.data_o(transmitter_refill_done_r)
  );


  // out fifo
  //
  logic out_fifo_valid_li;
  logic out_fifo_ready_lo;
  logic [dma_data_width_p-1:0] out_fifo_data_li;
  logic out_fifo_valid_o;
  logic [lg_mshr_els_lp-1:0] dma_evict_mshr_id_r;

  // dma evict data in counter
  //
  logic evict_data_in_counter_clear;
  logic evict_data_in_counter_up;
  logic dma_evict_in_counter_max;
  logic [counter_width_lp-1:0] dma_evict_in_counter_r;

  bsg_fifo_1r1w_small #(
    .width_p(dma_data_width_p)
    ,.els_p((num_of_burst_lp<2) ? 2 : num_of_burst_lp)
  ) out_fifo (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.data_i(out_fifo_data_li)
    ,.v_i(out_fifo_valid_li)
    ,.ready_o(out_fifo_ready_lo)
    ,.v_o(out_fifo_valid_o)
    ,.data_o(dma_data_o)
    ,.yumi_i(dma_data_yumi_i)
  );
  assign out_fifo_data_li = transmitter_evict_data_i;
  assign dma_data_v_o = out_fifo_valid_o & dma_evict_in_counter_max;
  assign out_fifo_valid_li = transmitter_evict_v_i & ~dma_evict_in_counter_max;

  bsg_counter_clear_up #(
    .max_val_p(num_of_burst_lp)
   ,.init_val_p('0)
  ) dma_evict_data_in_counter (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.clear_i(evict_data_in_counter_clear)
    ,.up_i(evict_data_in_counter_up)
    ,.count_o(dma_evict_in_counter_r)
  );

  // TODO: we could add another counter which counts the number of fifo entries that have been sent out of cache
  // and use that to determine when to set the evict done signal to 1
  // In this way we can take in new evicted data in the right next cycle after last round of eviction is done
  // Currently it has to wait for an extra cycle before next round of evicted data can be taken in

  assign dma_evict_in_counter_max = (dma_evict_in_counter_r == num_of_burst_lp);
  wire dma_evict_done = dma_evict_in_counter_max & ~out_fifo_valid_o;

  assign evict_data_in_counter_up = transmitter_evict_v_i & out_fifo_ready_lo & ~dma_evict_in_counter_max;
  assign evict_data_in_counter_clear = dma_evict_done;

  assign transmitter_evict_yumi_o = evict_data_in_counter_up;

  //for(genvar i=0; i<safe_mshr_els_lp; i++) begin
  //  assign mhu_evict_done_o[i] = (i==dma_evict_mshr_id_r) ? dma_evict_done : 1'b0;
  //end


  // dma pkt
  assign dma_pkt_o = dma_pkt;
  logic dma_req_done;

  always_comb begin
    dma_req_done = 1'b0;

    dma_pkt_v_o = 1'b0;
    dma_pkt.write_not_read = 1'b0;
    dma_pkt.addr = {
      mhu_or_mgmt_req_addr_i[addr_width_p-1:block_offset_width_lp],
      {(block_offset_width_lp){1'b0}}
    };
    dma_pkt.mask = '0;
    dma_pkt.mshr_id = mhu_req_mshr_id_i;

    case (mhu_or_mgmt_cmd_i)
      e_dma_send_refill_addr: begin
        dma_pkt_v_o = 1'b1;
        dma_pkt.write_not_read = 1'b0;
        dma_req_done = dma_pkt_yumi_i;
      end

      e_dma_send_evict_addr: begin
        dma_pkt_v_o = 1'b1;
        dma_pkt.write_not_read = 1'b1;
        dma_pkt.mask = track_mem_data_tl_way_picked_i;
        dma_req_done = dma_pkt_yumi_i;
      end
          
      e_dma_nop: begin
        // nothing happens.
      end

      default: begin
        // this should never happen.
      end      

    endcase
  end

  //for(genvar i=0; i<safe_mshr_els_lp; i++) begin
  //  assign mhu_req_done_o[i] = (i==mhu_req_mshr_id_i) ? dma_req_done : 1'b0;
  //end


  //logic [`BSG_SAFE_MINUS(block_size_in_words_p,1):0] dma_refill_track_data_way_picked_r;
  //logic dma_refill_track_miss_r;
  //logic [addr_width_p-1:0] dma_refill_addr_r;
  //logic [lg_ways_lp-1:0] dma_refill_way_r;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      dma_refill_mshr_id_r <= '0;
      dma_evict_mshr_id_r <= '0;
      //dma_refill_track_miss_r <= 1'b0;
    end else begin
      if (mshr_cam_r_v_o) begin
        dma_refill_mshr_id_r <= dma_refill_mshr_id_i;
        mshr_data_r <= mshr_data_i;
        mshr_data_byte_mask_r <= mshr_data_byte_mask_i;
        //dma_refill_track_data_way_picked_r <= mhu_refill_track_data_way_picked_i;
        //dma_refill_track_miss_r <= mhu_refill_track_miss_i;
        //dma_refill_addr_r <= mhu_refill_addr_index_i;
       // dma_refill_way_r <= mhu_refill_way_i;
      end

      if (out_fifo_valid_li & out_fifo_ready_lo & (dma_evict_in_counter_r == 0)) begin
        dma_evict_mshr_id_r <= transmitter_evict_mshr_id_i;
      end
    end
  end

  //assign transmitter_track_data_way_picked_o = dma_refill_track_data_way_picked_r;
  //assign transmitter_track_miss_o = dma_refill_track_miss_r;
  //assign transmitter_refill_way_o = dma_refill_way_r;
  //assign transmitter_refill_addr_index_o = dma_refill_addr_r;

  assign transmitter_track_data_way_picked_o = mgmt_v_i ? track_mem_data_tl_way_picked_i : mhu_refill_track_data_way_picked_i;
  assign transmitter_track_miss_o = mgmt_v_i ? 1'b0 : mhu_refill_track_miss_i; //FIXME:mgmt track miss not always 0
  assign transmitter_refill_way_o = mgmt_v_i ? mgmt_chosen_way_i : mhu_refill_way_i;
  assign transmitter_refill_addr_index_o = mgmt_v_i ? addr_v_i[block_offset_width_lp+:lg_sets_lp] : mhu_refill_addr_index_i;
  assign transmitter_refill_mshr_data_byte_mask_o = mgmt_v_i ? '0 : mshr_data_byte_mask_r;
  assign transmitter_refill_done_o = transmitter_refill_done_r;
  assign dma_refill_data_out_to_sipo_counter_o = dma_refill_data_out_to_sipo_counter_r;
  assign dma_refill_mshr_id_o = dma_refill_mshr_id_r;
  assign mshr_cam_r_v_o = ~dma_refill_hold_i & in_fifo_valid_li & in_fifo_ready_lo & (dma_refill_data_in_counter_r == 0);

  for(genvar i=0; i<safe_mshr_els_lp; i++) begin: done_signal

    assign dma_refill_done_v_lo[i] = ((i==dma_refill_mshr_id_r) & dma_refill_done & mhu_write_fill_data_in_progress_i[i] & ~dma_refill_hold_i & ~(|transmitter_mhu_store_tag_miss_done_i));
    assign mhu_dma_done_o[i] = (~mgmt_v_i & (i==mhu_req_mshr_id_i) & dma_req_done)
                               | (~mgmt_v_i & (i==dma_evict_mshr_id_r) & dma_evict_done)
                               | (~mgmt_v_i & dma_refill_done_v_lo[i]);
  end

  assign mgmt_dma_done_o = mgmt_v_i & (dma_req_done | dma_evict_done | dma_refill_done);

  
  // snoop_data register
  logic [block_data_width_lp-1:0] snoop_data_r;
  logic [lg_num_of_burst_lp-1:0] dma_refill_counter_low_bits;
  assign dma_refill_counter_low_bits = dma_refill_data_in_counter_r[0+:lg_num_of_burst_lp];

  always_ff @(posedge clk_i) begin
      if (reset_i) begin
        snoop_data_r <= '0;
      end else begin
        if (in_fifo_valid_li & in_fifo_ready_lo) begin
          snoop_data_r[(dma_refill_counter_low_bits*dma_data_width_p) +: dma_data_width_p] <= dma_data_i;
        end
      end
  end

  logic [word_width_p-1:0] snoop_data_offset_picked;
  logic [word_width_p-1:0] snoop_data_offset_picked_combined;
  bsg_mux #(
    .width_p(word_width_p)
    ,.els_p(block_size_in_words_p)
  ) snoop_mux (
    .data_i(snoop_data_r)
    ,.sel_i(read_miss_queue_read_in_progress_i ? read_miss_queue_word_offset_i : addr_block_offset_v_i)
    ,.data_o(snoop_data_offset_picked)
  );

  bsg_mux_segmented #(
    .segments_p(word_mask_width_lp)
    ,.segment_width_p(8)
  ) snoop_word_combine (
    .data0_i(snoop_data_offset_picked)
    ,.data1_i(read_miss_queue_mshr_data_i)
    ,.sel_i(read_miss_queue_mshr_data_mask_i)
    ,.data_o(snoop_data_offset_picked_combined)
  );  

  assign snoop_word_o = read_miss_queue_read_in_progress_i 
                      ? snoop_data_offset_picked_combined 
                      : snoop_data_offset_picked;

  // synopsys translate_off
  
  always_ff @ (posedge clk_i) begin
    if (debug_p) begin
      if (dma_pkt_v_o & dma_pkt_yumi_i) begin
        $display("<VCACHE> DMA_PKT we:%0d addr:%8h // %8t",
          dma_pkt.write_not_read, dma_pkt.addr, dma_pkt.mshr_id, $time);
      end
    end
  end
  // synopsys translate_on

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_dma)
