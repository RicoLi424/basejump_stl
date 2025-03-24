`include "bsg_noc_links.svh"
// `include "bsg_cache.svh"

module testbench();

  import bsg_cache_pkg::*;
  import bsg_noc_pkg::*;

  // clock/reset
  bit clk;
  bit reset;

  bsg_nonsynth_clock_gen #(
    .cycle_time_p(20)
  ) cg (
    .o(clk)
  );

  bsg_nonsynth_reset_gen #(
    .reset_cycles_lo_p(0)
    ,.reset_cycles_hi_p(10)
  ) rg (
    .clk_i(clk)
    ,.async_reset_o(reset)
  );

  // DUT parameters
  localparam num_dma_p=`NUM_DMA_P; // 2+
  localparam dma_ratio_p=`DMA_RATIO_P; // 32*X
  localparam notification_en_p=`NOTIFICATION_EN_P;

  localparam dma_data_width_p=32*dma_ratio_p;
  localparam lg_num_dma_lp = `BSG_SAFE_CLOG2(num_dma_p);

  // TB parameters
  localparam addr_width_p = 30;
  localparam data_width_p = 32;
  localparam block_size_in_words_p = 8;
  localparam sets_p = 128;
  localparam ways_p = 8;
  localparam mem_size_p = block_size_in_words_p*sets_p*ways_p*4;
  localparam block_offset_width_p = `BSG_SAFE_CLOG2(data_width_p*block_size_in_words_p/8);
  localparam data_len_p=block_size_in_words_p*data_width_p/dma_data_width_p;
  localparam wh_len_width_p=`BSG_WIDTH(data_len_p+1);
  localparam wh_cid_width_p=4;  // ?
  localparam wh_cord_width_p=4;  // ?
  localparam wh_ruche_factor_p=1;
  localparam wh_flit_width_p=dma_data_width_p;
  localparam wh_dims_p = 1;
  localparam int wh_cord_markers_pos_p[1:0] = '{ wh_cord_width_p, 0 };

  localparam lg_sets_lp=`BSG_SAFE_CLOG2(sets_p);
  localparam tag_width_lp=addr_width_p-lg_sets_lp-block_offset_width_p;
  localparam tag_info_width_lp=tag_width_lp+2;
  localparam tag_mem_width_lp=tag_info_width_lp*ways_p;


  integer status;
  integer wave;
  string checker;
  initial begin
    status = $value$plusargs("wave=%d",wave);
    status = $value$plusargs("checker=%s",checker);
    $display("checker=%s", checker);
    if (wave) $vcdpluson;
  end



  `declare_bsg_cache_pkt_s(addr_width_p,data_width_p);
  `declare_bsg_cache_dma_pkt_s(addr_width_p, block_size_in_words_p, ways_p);

  bsg_cache_pkt_s [num_dma_p-1:0] cache_pkt;
  logic [num_dma_p-1:0] v_li;
  logic [num_dma_p-1:0] ready_lo;

  logic [num_dma_p-1:0][data_width_p-1:0] cache_data_lo;
  logic [num_dma_p-1:0] v_lo;
  logic [num_dma_p-1:0] yumi_li;

  bsg_cache_dma_pkt_s [num_dma_p-1:0] dma_pkt;
  logic [num_dma_p-1:0] dma_pkt_v_lo;
  logic [num_dma_p-1:0] dma_pkt_yumi_li;

  logic [num_dma_p-1:0][dma_data_width_p-1:0] dma_data_li;
  logic [num_dma_p-1:0] dma_data_v_li;
  logic [num_dma_p-1:0] dma_data_ready_and_lo;

  logic [num_dma_p-1:0][dma_data_width_p-1:0] dma_data_lo;
  logic [num_dma_p-1:0] dma_data_v_lo;
  logic [num_dma_p-1:0] dma_data_yumi_li;

  `declare_bsg_ready_and_link_sif_s(wh_flit_width_p, bsg_ready_and_link_sif_s);
  bsg_ready_and_link_sif_s [num_dma_p-1:0] wh_link_sif_li, wh_link_sif_lo;

  localparam [wh_cid_width_p-1:0] mem_cid_lp = 0;
  localparam [wh_cid_width_p-1:0] shadow_cid_lp = 1;
  localparam [wh_cord_width_p-1:0] mem_cord_lp = {{(wh_cord_width_p-1){1'b1}},1'b1}; 
  localparam [wh_cord_width_p-1:0] io_cord_lp = {{(wh_cord_width_p-1){1'b1}},1'b0};

  `declare_bsg_cache_wh_header_flit_s(wh_flit_width_p,wh_cord_width_p,wh_len_width_p,wh_cid_width_p);
  `declare_bsg_cache_wh_notify_info_s(wh_flit_width_p, wh_cord_width_p, wh_len_width_p, wh_cid_width_p, ways_p);
  // DUT
  for (genvar i = 0; i < num_dma_p; i++)
    begin : cache
      wire notification_en_li = notification_en_p;
      bsg_cache #(
        .addr_width_p(addr_width_p)
        ,.data_width_p(data_width_p)
        ,.dma_data_width_p(dma_data_width_p)
        ,.block_size_in_words_p(block_size_in_words_p)
        ,.sets_p(sets_p)
        ,.ways_p(ways_p)
        ,.word_tracking_p(1)
        ,.amo_support_p(amo_support_level_arithmetic_lp)
      ) cache (
        .clk_i(clk)
        ,.reset_i(reset)

        ,.cache_pkt_i(cache_pkt[i])
        ,.v_i(v_li[i])
        ,.yumi_o(ready_lo[i])

        ,.data_o(cache_data_lo[i])
        ,.v_o(v_lo[i])
        ,.yumi_i(yumi_li[i])

        ,.dma_pkt_o(dma_pkt[i])
        ,.dma_pkt_v_o(dma_pkt_v_lo[i])
        ,.dma_pkt_yumi_i(dma_pkt_yumi_li[i])

        ,.dma_data_i(dma_data_li[i])
        ,.dma_data_v_i(dma_data_v_li[i])
        ,.dma_data_ready_and_o(dma_data_ready_and_lo[i])

        ,.dma_data_o(dma_data_lo[i])
        ,.dma_data_v_o(dma_data_v_lo[i])
        ,.dma_data_yumi_i(dma_data_yumi_li[i])

        ,.v_we_o()
        ,.notification_en_i(notification_en_li)
      );

      // random yumi generator
      bsg_nonsynth_random_yumi_gen #(
        .yumi_min_delay_p(`YUMI_MIN_DELAY_P)
        ,.yumi_max_delay_p(`YUMI_MAX_DELAY_P)
      ) yumi_gen (
        .clk_i(clk)
        ,.reset_i(reset)

        ,.v_i(v_lo[i])
        ,.yumi_o(yumi_li[i])
      );

      bsg_cache_wh_header_flit_s header_flit;
      assign header_flit = wh_link_sif_lo[i].data;
      // TODO: make into opcode... or at least the header flit struct itself
      bsg_cache_wh_notify_info_s notify_info;
      assign notify_info = header_flit.unused;
      wire [wh_cord_width_p-1:0] dest_wh_cord_li = notify_info.io_op
        ? io_cord_lp
        : mem_cord_lp;
      wire [wh_cid_width_p-1:0] dest_wh_cid_li = notify_info.write_validate
        ? shadow_cid_lp
        : mem_cid_lp;
      bsg_cache_dma_to_wormhole #(
         .dma_addr_width_p(addr_width_p)
         ,.dma_burst_len_p(data_len_p)
         ,.dma_mask_width_p(block_size_in_words_p)
         ,.dma_ways_p(ways_p)
         ,.wh_flit_width_p(wh_flit_width_p)
         ,.wh_cid_width_p(wh_cid_width_p)
         ,.wh_cord_width_p(wh_cord_width_p)
         ,.wh_len_width_p(wh_len_width_p)
       ) dma2wh (
         .clk_i(clk)
         ,.reset_i(reset)

         ,.dma_pkt_i(dma_pkt[i])
         ,.dma_pkt_v_i(dma_pkt_v_lo[i])
         ,.dma_pkt_yumi_o(dma_pkt_yumi_li[i])

         ,.dma_data_o(dma_data_li[i])
         ,.dma_data_v_o(dma_data_v_li[i])
         ,.dma_data_ready_and_i(dma_data_ready_and_lo[i])

         ,.dma_data_i(dma_data_lo[i])
         ,.dma_data_v_i(dma_data_v_lo[i])
         ,.dma_data_yumi_o(dma_data_yumi_li[i])

         ,.wh_link_sif_i(wh_link_sif_li[i])
         ,.wh_link_sif_o(wh_link_sif_lo[i])

         ,.my_wh_cord_i('0)
         ,.dest_wh_cord_i(dest_wh_cord_li)
         ,.my_wh_cid_i(wh_cid_width_p'(i))
         ,.dest_wh_cid_i(dest_wh_cid_li)
         );
    end

  bsg_ready_and_link_sif_s wh_link_concentrated_li, wh_link_concentrated_lo;
  bsg_ready_and_link_sif_s mem_link_sif_li, mem_link_sif_lo;
  bsg_ready_and_link_sif_s dram_link_sif_li, dram_link_sif_lo;
  bsg_ready_and_link_sif_s shadow_link_sif_li, shadow_link_sif_lo;
  //bsg_ready_and_link_sif_s wh_link_concentrated_lo_filtered, wh_link_concentrated_li_filtered;
  //bsg_ready_and_link_sif_s wh_link_wh2dma_lo;

  bsg_wormhole_concentrator
   #(.flit_width_p(wh_flit_width_p)
     ,.len_width_p(wh_len_width_p)
     ,.cid_width_p(wh_cid_width_p)
     ,.cord_width_p(wh_cord_width_p)
     ,.num_in_p(num_dma_p)
     )
   dma_concentrator
    (.clk_i(clk)
     ,.reset_i(reset)

     ,.links_i(wh_link_sif_lo)
     ,.links_o(wh_link_sif_li)

     ,.concentrated_link_i(wh_link_concentrated_li)
     ,.concentrated_link_o(wh_link_concentrated_lo)
     );

  //`declare_bsg_cache_wh_header_flit_s(wh_flit_width_p,wh_cord_width_p,wh_len_width_p,wh_cid_width_p);
  //bsg_cache_wh_header_flit_s header_flit, io_read_header_flit_back;
  //assign header_flit = wh_link_concentrated_lo.data;

  //logic expecting_header_r_lo; 
  //bsg_wormhole_router_packet_parser
  // #(.payload_len_bits_p($bits(header_flit.len)))
  // parser
  //  (.clk_i(clk)
  //   ,.reset_i(reset)
  //   ,.fifo_v_i(wh_link_concentrated_lo.v)
  //   ,.fifo_payload_len_i(header_flit.len)
  //   ,.fifo_yumi_i(wh_link_concentrated_li.ready_and_rev & wh_link_concentrated_lo.v)
  //   ,.expecting_header_r_o(expecting_header_r_lo)
  //   );
  // TODO: make into opcode... or at least the header flit struct itself
  //`declare_bsg_cache_wh_notify_info_s(wh_flit_width_p, wh_cord_width_p, wh_len_width_p, wh_cid_width_p, ways_p);
  //bsg_cache_wh_notify_info_s notify_info;
  //assign notify_info = header_flit.unused;
  //wire is_eviction = expecting_header_r_lo & notify_info.write_validate;

  //assign wh_link_filtered_lo.data = wh_link_concentrated_lo.data;
  //assign wh_link_filtered_lo.v = wh_link_concentrated_lo.v && !is_eviction;
  //assign wh_link_concentrated_li.ready_and_rev = wh_link_filtered_li.ready_and_rev || is_eviction;

  //assign wh_link_concentrated_li.data = wh_link_filtered_li.data;
  //assign wh_link_concentrated_li.v = wh_link_filtered_li.v;
  //assign wh_link_filtered_lo.ready_and_rev = wh_link_concentrated_lo.ready_and_rev;

  

  bsg_ready_and_link_sif_s [E:P] io_router_link_sif_li, io_router_link_sif_lo;
  bsg_wormhole_router
   #(.flit_width_p(wh_flit_width_p)
	 ,.dims_p(wh_dims_p)
     ,.cord_markers_pos_p(wh_cord_markers_pos_p)
     ,.len_width_p(wh_len_width_p)
     ,.debug_lp(0)
     ,.hold_on_valid_p(0) // shouldn't matter, but better stress test
     )
   io_router
    (.clk_i(clk)
     ,.reset_i(reset)

     ,.link_i(io_router_link_sif_li)
     ,.link_o(io_router_link_sif_lo)

     ,.my_cord_i(io_cord_lp)
     );

  bsg_nonsynth_wormhole_test_mem
   #(.vcache_data_width_p(data_width_p)
     ,.vcache_block_size_in_words_p(block_size_in_words_p)
     ,.vcache_dma_data_width_p(dma_data_width_p)
     ,.num_vcaches_p(num_dma_p)
     ,.wh_cid_width_p(wh_cid_width_p)
     ,.wh_flit_width_p(wh_flit_width_p)
     ,.wh_cord_width_p(wh_cord_width_p)
     ,.wh_len_width_p(wh_len_width_p)
     ,.wh_ruche_factor_p(wh_ruche_factor_p)
     ,.no_concentration_p(1)
     ,.no_coordination_p(1)
     ,.is_io_mem_p(1)
     ,.mem_size_p(2**addr_width_p-1)
     )
   io_mem
    (.clk_i(clk)
     ,.reset_i(reset)
     ,.wh_link_sif_i(io_router_link_sif_lo[P])
     ,.wh_link_sif_o(io_router_link_sif_li[P])
     );

  assign io_router_link_sif_li[W] = wh_link_concentrated_lo;
  assign wh_link_concentrated_li = io_router_link_sif_lo[W];

  assign mem_link_sif_lo = io_router_link_sif_lo[E];
  assign io_router_link_sif_li[E] = mem_link_sif_li;

// `declare_bsg_cache_wh_header_flit_s(wh_flit_width_p,wh_cord_width_p,wh_len_width_p,wh_cid_width_p);
//  bsg_cache_wh_header_flit_s header_flit, io_read_header_flit_back;
//  assign header_flit = mem_link_sif_lo.data;
//
//  `declare_bsg_cache_wh_notify_info_s(wh_flit_width_p,wh_cord_width_p,wh_len_width_p,wh_cid_width_p,ways_p);
//  bsg_cache_wh_notify_info_s notify_info, notify_info_n, notify_info_r;
//  assign notify_info = header_flit.unused;
//
//  bsg_cache_wh_opcode_e wh_opcode_r, wh_opcode_n;
//
//  typedef enum logic [2:0] {
//    TRANS_RESET
//    , TRANS_READY
//    , TRANS_COUNT
//    , TRANS_IO_READ_REPLY_WAIT
//    , TRANS_IO_READ_REPLY_READY
//    , TRANS_IO_READ_REPLY_SEND
//  } trans_state_e;
//
//  trans_state_e trans_state_r, trans_state_n;
//
//  localparam max_count_width_lp = `BSG_SAFE_CLOG2(data_len_p+2);
//  logic trans_clear_li;
//  logic trans_up_li;
//  logic [max_count_width_lp-1:0] trans_count_lo;
//  logic [max_count_width_lp-1:0] cnt_max_r, cnt_max_n;
//  logic [wh_cord_width_p-1:0] src_cord_r, src_cord_n;
//  logic [wh_cid_width_p-1:0] src_cid_r, src_cid_n;
//  logic wh_link_concentrated_yumi_li;
//
//  bsg_counter_clear_up #(
//    .max_val_p(data_len_p+2-1)
//    ,.init_val_p(0)
//  ) trans_count (
//    .clk_i(clk)
//    ,.reset_i(reset)
//    ,.clear_i(trans_clear_li)
//    ,.up_i(trans_up_li)
//    ,.count_o(trans_count_lo)
//  );
//
//  always_comb begin
//    trans_state_n = trans_state_r;
//    trans_clear_li = 1'b0;
//    trans_up_li = 1'b0;
//    cnt_max_n = cnt_max_r;
//    wh_opcode_n = wh_opcode_r;
//
//    mem_link_sif_li = wh_link_wh2dma_lo;
//
//    src_cord_n = src_cord_r;
//    src_cid_n = src_cid_r;
//
//    notify_info_n = notify_info_r;
//
//    wh_link_concentrated_yumi_li = 1'b0;
//
//    io_read_header_flit_back.unused = '0;
//    io_read_header_flit_back.opcode = e_cache_wh_read; // doesn't matter
//    io_read_header_flit_back.src_cord = '0; // doesn't matter
//    io_read_header_flit_back.src_cid = '0; // doesn't matter
//    io_read_header_flit_back.len = 1; // only send one packet back for io read data reply
//    io_read_header_flit_back.cord = src_cord_r;
//    io_read_header_flit_back.cid = src_cid_r;
//
//    case (trans_state_r)
//      TRANS_RESET: begin
//        trans_state_n = TRANS_READY;
//      end
//
//      TRANS_READY: begin
//        wh_link_concentrated_yumi_li = mem_link_sif_lo.v & 
//                                       ((notify_info.io_op || notify_info.write_validate)
//                                        ? 1'b1
//                                        : wh_link_wh2dma_lo.ready_and_rev);
//
//        mem_link_sif_li.v = wh_link_wh2dma_lo.v;
//        mem_link_sif_li.data = wh_link_wh2dma_lo.data;
//        mem_link_sif_li.ready_and_rev = wh_link_concentrated_yumi_li;
//
//        notify_info_n = (mem_link_sif_lo.v & wh_link_concentrated_yumi_li)
//                      ? notify_info
//                      : notify_info_r;
//
//        cnt_max_n = (mem_link_sif_lo.v & wh_link_concentrated_yumi_li)
//                  ? ((header_flit.opcode == e_cache_wh_read) 
//                    ? 1      // regular read, io read, write validate notification
//                    : ((header_flit.opcode == e_cache_wh_write_non_masked)
//                      ? (notify_info.io_op 
//                        ? 2   // io write
//                        : (1 + data_len_p))  // regular non-masked write
//                      : (2 + data_len_p)))   // regular masked write
//                  : cnt_max_r;
//
//        src_cid_n = (mem_link_sif_lo.v & wh_link_concentrated_yumi_li) ? header_flit.src_cid : src_cid_r;
//        src_cord_n =(mem_link_sif_lo.v & wh_link_concentrated_yumi_li) ? header_flit.src_cord : src_cord_r;
//
//        wh_opcode_n = (mem_link_sif_lo.v & wh_link_concentrated_yumi_li) ? header_flit.opcode : wh_opcode_r;
//
//        trans_state_n = (mem_link_sif_lo.v & wh_link_concentrated_yumi_li)
//          ? TRANS_COUNT
//          : TRANS_READY;
//      end
//
//      TRANS_COUNT: begin
//        wh_link_concentrated_yumi_li = mem_link_sif_lo.v & 
//                                       ((notify_info_r.io_op || notify_info_r.write_validate)
//                                        ? 1'b1
//                                        : wh_link_wh2dma_lo.ready_and_rev);
//
//        mem_link_sif_li.v = wh_link_wh2dma_lo.v;
//        mem_link_sif_li.data = wh_link_wh2dma_lo.data;
//        mem_link_sif_li.ready_and_rev = wh_link_concentrated_yumi_li;
//
//        trans_up_li = (trans_count_lo != (cnt_max_r-1)) & mem_link_sif_lo.v & wh_link_concentrated_yumi_li;
//        trans_clear_li = (trans_count_lo == (cnt_max_r-1)) & mem_link_sif_lo.v & wh_link_concentrated_yumi_li;
//        trans_state_n = trans_clear_li
//                      ? (((wh_opcode_r == e_cache_wh_read) & notify_info_r.io_op)
//                        ? (((wh2dma.recv_state_r == 2'b01) || (wh2dma.recv_state_n == 2'b01))
//                          ? TRANS_IO_READ_REPLY_READY
//                          : TRANS_IO_READ_REPLY_WAIT)
//                        : TRANS_READY)
//                      : TRANS_COUNT;
//      end
//
//      TRANS_IO_READ_REPLY_WAIT: begin
//        mem_link_sif_li.v = wh_link_wh2dma_lo.v;
//        mem_link_sif_li.data = wh_link_wh2dma_lo.data;
//        mem_link_sif_li.ready_and_rev = 1'b0;
//
//        trans_state_n = (wh2dma.recv_state_n == 2'b01) ? TRANS_IO_READ_REPLY_READY : TRANS_IO_READ_REPLY_WAIT;
//      end
//
//      TRANS_IO_READ_REPLY_READY: begin
//        mem_link_sif_li.v = 1'b1;
//        mem_link_sif_li.data = io_read_header_flit_back;
//        mem_link_sif_li.ready_and_rev = 1'b0;
//        trans_state_n = mem_link_sif_lo.ready_and_rev
//          ? TRANS_IO_READ_REPLY_SEND
//          : TRANS_IO_READ_REPLY_READY;
//      end
//
//      TRANS_IO_READ_REPLY_SEND: begin
//        mem_link_sif_li.v = 1'b1;
//        mem_link_sif_li.data = wh_flit_width_p'({1'b0});
//        mem_link_sif_li.ready_and_rev = 1'b0;
//        trans_state_n = mem_link_sif_lo.ready_and_rev ? TRANS_READY : TRANS_IO_READ_REPLY_SEND;
//      end
//
//      default: begin
//        trans_state_n = TRANS_READY;
//      end
//    endcase
//  end
//
//
//  // DWP RESTORE
//  // for write validate notification and io read/write, the wh packets don't go into wh_to_dma
//  //assign wh_link_concentrated_lo_filtered.data = header_flit;
//  //assign wh_link_concentrated_lo_filtered.ready_and_rev = (((trans_state_n == TRANS_IO_READ_REPLY_READY) && (wh2dma.recv_state_r == 2'b01))
//  //                                                        || (trans_state_r == TRANS_IO_READ_REPLY_READY) 
//  //                                                        || (trans_state_r == TRANS_IO_READ_REPLY_SEND))
//  //                                                      ? 1'b0
//  //                                                      : mem_link_sif_lo.ready_and_rev;
//  // assign wh_link_concentrated_lo_filtered.v = (((trans_state_r == TRANS_COUNT) 
//  //                                              && ((wh_opcode_r == e_cache_wh_read)
//  //                                                 || (wh_opcode_r == e_cache_wh_write_non_masked)
//  //                                                 || (wh_opcode_r == e_cache_wh_write_masked)))
//  //                                             || ((trans_state_r == TRANS_READY) 
//  //                                               && ((header_flit.opcode == e_cache_wh_read)
//  //                                                 || (header_flit.opcode == e_cache_wh_write_non_masked) 
//  //                                                 || (header_flit.opcode == e_cache_wh_write_masked))))
//  //                                            && mem_link_sif_lo.v
//  //                                           ? 1'b1
//  //                                           : 1'b0;
//
//  assign wh_link_concentrated_lo_filtered.v = mem_link_sif_lo.v &
//                                            (((trans_state_r == TRANS_COUNT) & ~notify_info_r.write_validate & ~notify_info_r.io_op)
//                                            || ((trans_state_r == TRANS_READY) & ~notify_info.write_validate & ~notify_info.io_op));

   bsg_wormhole_concentrator
    #(.flit_width_p(wh_flit_width_p)
      ,.len_width_p(wh_len_width_p)
      ,.cid_width_p(wh_cid_width_p)
      ,.cord_width_p(wh_cord_width_p)
      ,.num_in_p(2)
      )
    shadow_concentrator
     (.clk_i(clk)
      ,.reset_i(reset)
 
      ,.links_i({shadow_link_sif_li, dram_link_sif_li})
      ,.links_o({shadow_link_sif_lo, dram_link_sif_lo})
 
      ,.concentrated_link_i(mem_link_sif_lo)
      ,.concentrated_link_o(mem_link_sif_li)
      );

  // TODO: Hookup, currently just a sink
  // assign shadow_link_sif_li = '1;
  assign shadow_link_sif_li.v = 1'b0;
  assign shadow_link_sif_li.ready_and_rev = 1'b1;
  assign shadow_link_sif_li.data = '0;


  bsg_cache_wh_header_flit_s shadow_header_flit;
  assign shadow_header_flit = shadow_link_sif_lo.data;
  bsg_cache_wh_notify_info_s shadow_notify_info;
  assign shadow_notify_info = shadow_header_flit.unused;
  logic shadow_expecting_header_r_lo;
  bsg_wormhole_router_packet_parser
   #(.payload_len_bits_p($bits(shadow_header_flit.len)))
   shadow_header_parser
    (.clk_i(clk)
     ,.reset_i(reset)
     ,.fifo_v_i(shadow_link_sif_lo.v)
     ,.fifo_payload_len_i(shadow_header_flit.len)
     ,.fifo_yumi_i(shadow_link_sif_lo.v & shadow_link_sif_li.ready_and_rev)
     ,.expecting_header_r_o(shadow_expecting_header_r_lo)
     );

  always_ff @(negedge clk) begin
    if (shadow_expecting_header_r_lo && shadow_link_sif_lo.v && !shadow_notify_info.write_validate) begin
      $error("write_validate !set for shadow link packet");
    end
  end

  bsg_nonsynth_wormhole_test_mem
   #(.vcache_data_width_p(data_width_p)
     ,.vcache_block_size_in_words_p(block_size_in_words_p)
     ,.vcache_dma_data_width_p(dma_data_width_p)
     ,.num_vcaches_p(num_dma_p)
     ,.wh_cid_width_p(wh_cid_width_p)
     ,.wh_flit_width_p(wh_flit_width_p)
     ,.wh_cord_width_p(wh_cord_width_p)
     ,.wh_len_width_p(wh_len_width_p)
     ,.wh_ruche_factor_p(wh_ruche_factor_p)
     //,.no_concentration_p(0)
     //,.no_coordination_p(0)
     ,.no_concentration_p(1)
     ,.no_coordination_p(1)
     ,.is_io_mem_p(0)
     ,.mem_size_p(2**addr_width_p-1)
     )
   dram_mem
    (.clk_i(clk)
     ,.reset_i(reset)
     ,.wh_link_sif_i(dram_link_sif_lo)
     ,.wh_link_sif_o(dram_link_sif_li)
     );

   bsg_cache_wh_header_flit_s dram_header_flit;
   assign dram_header_flit = dram_link_sif_lo.data;
   bsg_cache_wh_notify_info_s dram_notify_info;
   assign dram_notify_info = dram_header_flit.unused;
   logic dram_expecting_header_r_lo;
   bsg_wormhole_router_packet_parser
    #(.payload_len_bits_p($bits(dram_header_flit.len)))
    dram_header_parser
     (.clk_i(clk)
      ,.reset_i(reset)
      ,.fifo_v_i(dram_link_sif_lo.v)
      ,.fifo_payload_len_i(dram_header_flit.len)
      ,.fifo_yumi_i(dram_link_sif_lo.v & dram_link_sif_li.ready_and_rev)
      ,.expecting_header_r_o(dram_expecting_header_r_lo)
      );
 
   always_ff @(negedge clk) begin
     if (dram_expecting_header_r_lo && dram_link_sif_lo.v && dram_notify_info.write_validate) begin
       $error("write_validate set for dram link packet");
     end
   end

//  1. header_flit.unused = {'0, dma_pkt_lo.read_pending, dma_pkt_lo.way_id}, for a fill wh header flit,
//     read_pending means it's followed by an evict request, the address that it's going to replace in 
//     the shadow tag memory needs to be put into the pending evict table
//  2. ignore the packets whose header_flit.cord = {(wh_cord_width_p-1){1'b1},1'b0}, bc they are uncached packets
//     we can also directly check if header_flit.opcode is e_cache_wh_io_read or e_cache_wh_io_write
//  3. when header_flit.opcode is e_cache_wh_write_validate, it means it's just a write validate notification that 
//     needs to update the shawdow tag memory, and there won't be following evict request
//  4. a counter should be put here so when header_flit.opcode = e_cache_wh_write_masked/e_cache_wh_write_non_masked is detected, 
//     it should start counting the flits, until the last flit is received, then we can clear the corresponding entry in the 
//     pending evict table


  // TODO: SHADOW TAG MODULE

  logic [tag_mem_width_lp-1:0] shadow_tag_mem [num_dma_p-1:0][sets_p-1:0] = '{default: '0};

  // TODO: PENDING EVICT TABLE




  // trace replay
  localparam rom_addr_width_lp = 26;
  localparam ring_width_lp = `bsg_cache_pkt_width(addr_width_p,data_width_p);

  logic [rom_addr_width_lp-1:0] trace_rom_addr;
  logic [ring_width_lp+4-1:0] trace_rom_data;

  logic tr_v_lo;
  logic [ring_width_lp-1:0] tr_data_lo;
  logic tr_yumi_li;
  logic done;

  bsg_fsb_node_trace_replay #(
    .ring_width_p(ring_width_lp)
    ,.rom_addr_width_p(rom_addr_width_lp)
  ) trace_replay (
    .clk_i(clk)
    ,.reset_i(reset)
    ,.en_i(1'b1)

    ,.v_i(1'b0)
    ,.data_i('0)
    ,.ready_o()

    ,.v_o(tr_v_lo)
    ,.data_o(tr_data_lo)
    ,.yumi_i(tr_yumi_li)

    ,.rom_addr_o(trace_rom_addr)
    ,.rom_data_i(trace_rom_data)

    ,.done_o(done)
    ,.error_o()
  );
  
  bsg_nonsynth_test_rom #(
    .filename_p("trace.tr")
    ,.data_width_p(ring_width_lp+4)
    ,.addr_width_p(rom_addr_width_lp)
  ) trom (
    .addr_i(trace_rom_addr)
    ,.data_o(trace_rom_data)
  );
  
  // slice cache packets across cache lines
  for (genvar i = 0; i < num_dma_p; i++)
    begin : tr_split
      assign cache_pkt[i] = tr_data_lo;
      assign v_li[i] = tr_v_lo & (i == (cache_pkt[0].addr[block_offset_width_p+:lg_num_dma_lp] % num_dma_p));
    end
  assign tr_yumi_li = tr_v_lo & |(v_li & ready_lo);

  bind bsg_cache basic_checker_32 #(
    .data_width_p(data_width_p)
    ,.addr_width_p(addr_width_p)
    ,.mem_size_p($root.testbench.mem_size_p)
  ) bc (
    .*
    ,.en_i($root.testbench.checker == "basic")
  );

  // wait for all responses to be received.
  integer sent_r, recv_r;
  logic test_done_r;

  always_ff @ (posedge clk) begin
    if (reset) begin
      sent_r <= '0;
      recv_r <= '0;
      //trans_state_r <= TRANS_RESET;
      //cnt_max_r <= '0;
      //src_cord_r <= '0;
      //src_cid_r <= '0;
      //wh_opcode_r = e_cache_wh_read;
      //notify_info_r <= '0;
      test_done_r <= '0;
    end
    else begin
      sent_r <= sent_r + $countones(v_li & ready_lo);
      recv_r <= recv_r + $countones(v_lo & yumi_li);
      //trans_state_r <= trans_state_n;
      //cnt_max_r <= cnt_max_n;
      //src_cord_r <= src_cord_n;
      //src_cid_r <= src_cid_n;
      //wh_opcode_r <= wh_opcode_n;
      //notify_info_r <= notify_info_n;
      test_done_r <= done & (sent_r == recv_r);
    end
  end

  // logic [tag_mem_width_lp-1:0] tag_mem_copy_lo [num_dma_p][sets_p];
  
//  for (genvar i = 0; i < num_dma_p; i++) 
//    begin : btag
//      bsg_tag_mem_check #(
//        .width_p(tag_mem_width_lp)
//        ,.sets_p(sets_p)
//        ,.num_dma_p(num_dma_p)
//      ) tag_mem_ck (
//        .clk_i(clk)
//        ,.reset_i(reset)
//        ,.data_i(cache[i].cache.tag_mem_data_li)
//        ,.v_i(cache[i].cache.tag_mem_v_li)
//        ,.w_i(cache[i].cache.tag_mem_w_li)
//        ,.w_mask_i(cache[i].cache.tag_mem_w_mask_li)
//        ,.addr_i(cache[i].cache.tag_mem_addr_li)
//        ,.shadow_tag_mem_i(shadow_tag_mem[i])
//        ,.check_en_i(done & (sent_r == recv_r))
//        ,.id_i(i)
//        // ,.tag_mem_copy_o(tag_mem_copy_lo[i])
//      );
//    end

  // integer dma_idx, set_idx;
  // integer mismatch_count = 0;

  initial begin

    // TODO: is it sufficient? do we need to check there's no wh packet in dma_to_wormhole or on the link?
    // wait(done & (sent_r == recv_r));
    wait(test_done_r);
    
    $display("[BSG_FINISH] Test Successful.");
    #500;
    $finish;
  end

endmodule
