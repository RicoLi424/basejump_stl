
`include "bsg_noc_links.svh"

module testbench();

  import bsg_cache_pkg::*;

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
  localparam wh_cid_width_p=4;
  localparam wh_cord_width_p=4;
  localparam wh_flit_width_p=dma_data_width_p;


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

  // DUT
  for (genvar i = 0; i < num_dma_p; i++)
    begin : cache 
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
        ,.notification_en_i(1'b1)
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
         ,.dest_wh_cord_i({wh_cord_width_p{1'b1}})
         ,.my_wh_cid_i(wh_cid_width_p'(i))
         ,.dest_wh_cid_i(wh_cid_width_p'(i))
         ,.io_wh_cord_i({{(wh_cord_width_p-1){1'b1}},1'b0})
         );
    end

  bsg_ready_and_link_sif_s wh_link_concentrated_li, wh_link_concentrated_lo;
  bsg_ready_and_link_sif_s wh_link_concentrated_lo_filtered;
  bsg_ready_and_link_sif_s wh_link_wh2dma_lo;

  bsg_wormhole_concentrator
   #(.flit_width_p(wh_flit_width_p)
     ,.len_width_p(wh_len_width_p)
     ,.cid_width_p(wh_cid_width_p)
     ,.cord_width_p(wh_cord_width_p)
     ,.num_in_p(num_dma_p)
     )
   concentrator
    (.clk_i(clk)
     ,.reset_i(reset)

     ,.links_i(wh_link_sif_lo)
     ,.links_o(wh_link_sif_li)

     ,.concentrated_link_i(wh_link_concentrated_li)
     ,.concentrated_link_o(wh_link_concentrated_lo)
     );

 `declare_bsg_cache_wh_header_flit_s(wh_flit_width_p,wh_cord_width_p,wh_len_width_p,wh_cid_width_p);
  bsg_cache_wh_header_flit_s header_flit, io_read_header_flit_back;
  assign header_flit = wh_link_concentrated_lo.data;

  `declare_bsg_cache_wh_notify_info_s(wh_flit_width_p,wh_cord_width_p,wh_len_width_p,wh_cid_width_p,ways_p);
  bsg_cache_wh_notify_info_s notify_info, notify_info_n, notify_info_r;
  assign notify_info = header_flit.unused;

  bsg_cache_wh_opcode_e wh_opcode_r, wh_opcode_n;

  typedef enum logic [2:0] {
    TRANS_RESET
    , TRANS_READY
    , TRANS_COUNT
    , TRANS_IO_READ_REPLY_WAIT
    , TRANS_IO_READ_REPLY_READY
    , TRANS_IO_READ_REPLY_SEND
  } trans_state_e;

  trans_state_e trans_state_r, trans_state_n;

  localparam max_count_width_lp = `BSG_SAFE_CLOG2(data_len_p+2);
  logic trans_clear_li;
  logic trans_up_li;
  logic [max_count_width_lp-1:0] trans_count_lo;
  logic [max_count_width_lp-1:0] cnt_max_r, cnt_max_n;
  logic [wh_cord_width_p-1:0] src_cord_r, src_cord_n;
  logic [wh_cid_width_p-1:0] src_cid_r, src_cid_n;
  logic wh_link_concentrated_yumi_li;

  bsg_counter_clear_up #(
    .max_val_p(data_len_p+2-1)
    ,.init_val_p(0)
  ) trans_count (
    .clk_i(clk)
    ,.reset_i(reset)
    ,.clear_i(trans_clear_li)
    ,.up_i(trans_up_li)
    ,.count_o(trans_count_lo)
  );

  always_comb begin
    trans_state_n = trans_state_r;
    trans_clear_li = 1'b0;
    trans_up_li = 1'b0;
    cnt_max_n = cnt_max_r;
    wh_opcode_n = wh_opcode_r;

    wh_link_concentrated_li = wh_link_wh2dma_lo;

    src_cord_n = src_cord_r;
    src_cid_n = src_cid_r;

    notify_info_n = notify_info_r;

    wh_link_concentrated_yumi_li = 1'b0;

    io_read_header_flit_back.unused = '0;
    io_read_header_flit_back.opcode = e_cache_wh_read; // doesn't matter
    io_read_header_flit_back.src_cord = '0; // doesn't matter
    io_read_header_flit_back.src_cid = '0; // doesn't matter
    io_read_header_flit_back.len = 1; // only send one packet back for io read data reply
    io_read_header_flit_back.cord = src_cord_r;
    io_read_header_flit_back.cid = src_cid_r;

    case (trans_state_r)
      TRANS_RESET: begin
        trans_state_n = TRANS_READY;
      end

      TRANS_READY: begin
        wh_link_concentrated_yumi_li = wh_link_concentrated_lo.v & 
                                       ((notify_info.io_op || notify_info.write_validate)
                                        ? 1'b1
                                        : wh_link_wh2dma_lo.ready_and_rev);

        wh_link_concentrated_li.v = wh_link_wh2dma_lo.v;
        wh_link_concentrated_li.data = wh_link_wh2dma_lo.data;
        wh_link_concentrated_li.ready_and_rev = wh_link_concentrated_yumi_li;

        notify_info_n = (wh_link_concentrated_lo.v & wh_link_concentrated_yumi_li)
                      ? notify_info
                      : notify_info_r;

        cnt_max_n = (wh_link_concentrated_lo.v & wh_link_concentrated_yumi_li)
                  ? ((header_flit.opcode == e_cache_wh_read) 
                    ? 1      // regular read, io read, write validate notification
                    : ((header_flit.opcode == e_cache_wh_write_non_masked)
                      ? (notify_info.io_op 
                        ? 2   // io write
                        : (1 + data_len_p))  // regular non-masked write
                      : (2 + data_len_p)))   // regular masked write
                  : cnt_max_r;

        src_cid_n = (wh_link_concentrated_lo.v & wh_link_concentrated_yumi_li) ? header_flit.src_cid : src_cid_r;
        src_cord_n =(wh_link_concentrated_lo.v & wh_link_concentrated_yumi_li) ? header_flit.src_cord : src_cord_r;

        wh_opcode_n = (wh_link_concentrated_lo.v & wh_link_concentrated_yumi_li) ? header_flit.opcode : wh_opcode_r;

        trans_state_n = (wh_link_concentrated_lo.v & wh_link_concentrated_yumi_li)
          ? TRANS_COUNT
          : TRANS_READY;
      end

      TRANS_COUNT: begin
        wh_link_concentrated_yumi_li = wh_link_concentrated_lo.v & 
                                       ((notify_info_r.io_op || notify_info_r.write_validate)
                                        ? 1'b1
                                        : wh_link_wh2dma_lo.ready_and_rev);

        wh_link_concentrated_li.v = wh_link_wh2dma_lo.v;
        wh_link_concentrated_li.data = wh_link_wh2dma_lo.data;
        wh_link_concentrated_li.ready_and_rev = wh_link_concentrated_yumi_li;

        trans_up_li = (trans_count_lo != (cnt_max_r-1)) & wh_link_concentrated_lo.v & wh_link_concentrated_yumi_li;
        trans_clear_li = (trans_count_lo == (cnt_max_r-1)) & wh_link_concentrated_lo.v & wh_link_concentrated_yumi_li;
        trans_state_n = trans_clear_li
                      ? (((wh_opcode_r == e_cache_wh_read) & notify_info_r.io_op)
                        ? (((wh2dma.recv_state_r == 2'b01) || (wh2dma.recv_state_n == 2'b01))
                          ? TRANS_IO_READ_REPLY_READY
                          : TRANS_IO_READ_REPLY_WAIT)
                        : TRANS_READY)
                      : TRANS_COUNT;
      end

      TRANS_IO_READ_REPLY_WAIT: begin
        wh_link_concentrated_li.v = wh_link_wh2dma_lo.v;
        wh_link_concentrated_li.data = wh_link_wh2dma_lo.data;
        wh_link_concentrated_li.ready_and_rev = 1'b0;

        trans_state_n = (wh2dma.recv_state_n == 2'b01) ? TRANS_IO_READ_REPLY_READY : TRANS_IO_READ_REPLY_WAIT;
      end

      TRANS_IO_READ_REPLY_READY: begin
        wh_link_concentrated_li.v = 1'b1;
        wh_link_concentrated_li.data = io_read_header_flit_back;
        wh_link_concentrated_li.ready_and_rev = 1'b0;
        trans_state_n = wh_link_concentrated_lo.ready_and_rev
          ? TRANS_IO_READ_REPLY_SEND
          : TRANS_IO_READ_REPLY_READY;
      end

      TRANS_IO_READ_REPLY_SEND: begin
        wh_link_concentrated_li.v = 1'b1;
        wh_link_concentrated_li.data = wh_flit_width_p'({1'b0});
        wh_link_concentrated_li.ready_and_rev = 1'b0;
        trans_state_n = wh_link_concentrated_lo.ready_and_rev ? TRANS_READY : TRANS_IO_READ_REPLY_SEND;
      end

      default: begin
        trans_state_n = TRANS_READY;
      end
    endcase
  end


  // for write validate notification and io read/write, the wh packets don't go into wh_to_dma
  assign wh_link_concentrated_lo_filtered.data = header_flit;
  assign wh_link_concentrated_lo_filtered.ready_and_rev = (((trans_state_n == TRANS_IO_READ_REPLY_READY) && (wh2dma.recv_state_r == 2'b01))
                                                          || (trans_state_r == TRANS_IO_READ_REPLY_READY) 
                                                          || (trans_state_r == TRANS_IO_READ_REPLY_SEND))
                                                        ? 1'b0
                                                        : wh_link_concentrated_lo.ready_and_rev;
  // assign wh_link_concentrated_lo_filtered.v = (((trans_state_r == TRANS_COUNT) 
  //                                              && ((wh_opcode_r == e_cache_wh_read)
  //                                                 || (wh_opcode_r == e_cache_wh_write_non_masked)
  //                                                 || (wh_opcode_r == e_cache_wh_write_masked)))
  //                                             || ((trans_state_r == TRANS_READY) 
  //                                               && ((header_flit.opcode == e_cache_wh_read)
  //                                                 || (header_flit.opcode == e_cache_wh_write_non_masked) 
  //                                                 || (header_flit.opcode == e_cache_wh_write_masked))))
  //                                            && wh_link_concentrated_lo.v
  //                                           ? 1'b1
  //                                           : 1'b0;

  assign wh_link_concentrated_lo_filtered.v = wh_link_concentrated_lo.v &
                                            (((trans_state_r == TRANS_COUNT) & ~notify_info_r.write_validate & ~notify_info_r.io_op)
                                            || ((trans_state_r == TRANS_READY) & ~notify_info.write_validate & ~notify_info.io_op));

  bsg_cache_dma_pkt_s mem_dma_pkt;
  logic mem_dma_pkt_v_lo, mem_dma_pkt_yumi_li;
  logic [wh_flit_width_p-1:0] mem_dma_data_li;
  logic mem_dma_data_v_li, mem_dma_data_ready_and_lo;
  logic [dma_data_width_p-1:0] mem_dma_data_lo;
  logic mem_dma_data_v_lo, mem_dma_data_yumi_li;

  logic [wh_cord_width_p-1:0] wh_header_cord_lo;
  logic [wh_cid_width_p-1:0] wh_header_cid_lo;
  wire [lg_num_dma_lp-1:0] wh_dma_id_li = header_flit.src_cid[0+:lg_num_dma_lp];

  bsg_wormhole_to_cache_dma_inorder #(
     .num_dma_p(num_dma_p)
     ,.dma_addr_width_p(addr_width_p)
     ,.dma_burst_len_p(data_len_p)
     ,.dma_mask_width_p(block_size_in_words_p)
     ,.dma_ways_p(ways_p)
     ,.wh_flit_width_p(wh_flit_width_p)
     ,.wh_cid_width_p(wh_cid_width_p)
     ,.wh_cord_width_p(wh_cord_width_p)
     ,.wh_len_width_p(wh_len_width_p)
   ) wh2dma (
     .clk_i(clk)
     ,.reset_i(reset)

     ,.wh_link_sif_i(wh_link_concentrated_lo_filtered)
     ,.wh_dma_id_i(wh_dma_id_li)
     ,.wh_link_sif_o(wh_link_wh2dma_lo)

     ,.dma_pkt_o(mem_dma_pkt)
     ,.dma_pkt_v_o(mem_dma_pkt_v_lo)
     ,.dma_pkt_yumi_i(mem_dma_pkt_yumi_li)
     ,.dma_pkt_id_o()

     ,.dma_data_i(mem_dma_data_li)
     ,.dma_data_v_i(mem_dma_data_v_li)
     ,.dma_data_ready_and_o(mem_dma_data_ready_and_lo)

     ,.dma_data_o(mem_dma_data_lo)
     ,.dma_data_v_o(mem_dma_data_v_lo)
     ,.dma_data_yumi_i(mem_dma_data_yumi_li)
  );

  // DMA model
  bsg_nonsynth_dma_model #(
    .addr_width_p(addr_width_p)
    ,.data_width_p(dma_data_width_p)
    ,.block_size_in_words_p(data_len_p)
    ,.mask_width_p(block_size_in_words_p)
    ,.els_p(mem_size_p)
    ,.ways_p(ways_p)

    ,.read_delay_p(`DMA_READ_DELAY_P)
    ,.write_delay_p(`DMA_WRITE_DELAY_P)
    ,.dma_req_delay_p(`DMA_REQ_DELAY_P)
    ,.dma_data_delay_p(`DMA_DATA_DELAY_P)

  ) dma0 (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.dma_pkt_i(mem_dma_pkt)
    ,.dma_pkt_v_i(mem_dma_pkt_v_lo)
    ,.dma_pkt_yumi_o(mem_dma_pkt_yumi_li)

    ,.dma_data_o(mem_dma_data_li)
    ,.dma_data_v_o(mem_dma_data_v_li)
    ,.dma_data_ready_i(mem_dma_data_ready_and_lo)

    ,.dma_data_i(mem_dma_data_lo)
    ,.dma_data_v_i(mem_dma_data_v_lo)
    ,.dma_data_yumi_o(mem_dma_data_yumi_li)
  );

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

  always_ff @ (posedge clk) begin
    if (reset) begin
      sent_r <= '0;
      recv_r <= '0;
      trans_state_r <= TRANS_RESET;
      cnt_max_r <= '0;
      src_cord_r <= '0;
      src_cid_r <= '0;
      wh_opcode_r = e_cache_wh_read;
      notify_info_r <= '0;
    end
    else begin
      sent_r <= sent_r + $countones(v_li & ready_lo);
      recv_r <= recv_r + $countones(v_lo & yumi_li);
      trans_state_r <= trans_state_n;
      cnt_max_r <= cnt_max_n;
      src_cord_r <= src_cord_n;
      src_cid_r <= src_cid_n;
      wh_opcode_r <= wh_opcode_n;
      notify_info_r <= notify_info_n;
    end

    // $display("v=%0d, opcode=%0d, ready_and_rev=%0d", wh_link_concentrated_lo.v, header_flit.opcode, wh_link_concentrated_lo.ready_and_rev);
    // if((trans_state_r == TRANS_IO_READ_REPLY_READY) || (trans_state_r == TRANS_IO_READ_REPLY_SEND)) $fatal(1, "trans_state_r = %0d", trans_state_r);

  end

  initial begin
    wait(done & (sent_r == recv_r));
    $display("[BSG_FINISH] Test Successful.");
    #500;
    $finish;
  end

endmodule
