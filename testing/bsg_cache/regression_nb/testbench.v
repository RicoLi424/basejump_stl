/**
 *  testbench.v
 */

`include "bsg_cache_nb.vh"

module testbench();
  import bsg_cache_nb_pkg::*;

  // parameters
  //
  parameter src_id_width_p = 30;
  parameter addr_width_p = 32;
  parameter word_width_p = 32;
  parameter dma_data_width_p = 128;
  parameter block_size_in_words_p = 16;
  parameter sets_p = 64;
  parameter ways_p = 8;
  parameter mshr_els_p = `MSHR_ELS_P;
  parameter read_miss_els_per_mshr_p = `READ_MISS_ELS_PER_MSHR_P;
  parameter word_tracking_p = 0;
  parameter mem_size_p = 2**15;

  parameter dma_read_delay_p  = `DMA_READ_DELAY_P;
  parameter dma_write_delay_p = `DMA_WRITE_DELAY_P;
  parameter dma_data_delay_p  = `DMA_DATA_DELAY_P;
  parameter dma_req_delay_p   = `DMA_REQ_DELAY_P;
  parameter yumi_max_delay_p  = `YUMI_MAX_DELAY_P;
  parameter yumi_min_delay_p  = `YUMI_MIN_DELAY_P;

  localparam lg_ways_lp = `BSG_SAFE_CLOG2(ways_p);
  localparam lg_sets_lp = `BSG_SAFE_CLOG2(sets_p);
  localparam lg_block_size_in_words_lp = `BSG_SAFE_CLOG2(block_size_in_words_p);
  localparam block_size_in_bursts_lp = (block_size_in_words_p*word_width_p/dma_data_width_p);
  localparam lg_block_size_in_bursts_lp=`BSG_SAFE_CLOG2(block_size_in_bursts_lp);
  localparam lg_mshr_els_lp = `BSG_SAFE_CLOG2(mshr_els_p);
  localparam byte_sel_width_lp = `BSG_SAFE_CLOG2(word_width_p>>3);
  localparam tag_width_lp = (addr_width_p-lg_sets_lp-lg_block_size_in_words_lp-byte_sel_width_lp);
  localparam block_offset_width_lp = lg_block_size_in_words_lp+byte_sel_width_lp;

  localparam bsg_cache_nb_dma_pkt_width_lp=`bsg_cache_nb_dma_pkt_width(addr_width_p, block_size_in_words_p, mshr_els_p);

  // synopsys translate_off
  integer status;
  integer wave;
  string checker;

  initial begin
    status = $value$plusargs("wave=%d",wave);
    status = $value$plusargs("checker=%s",checker);
    if (wave) $vcdpluson;
  end


  // clock and reset
  //
  logic clk;
  logic reset;

  bsg_nonsynth_clock_gen #(
    .cycle_time_p(100)
  ) clock_gen (
    .o(clk)
  );

  bsg_nonsynth_reset_gen #(
    .num_clocks_p(1)
    ,.reset_cycles_lo_p(0)
    ,.reset_cycles_hi_p(8)
  ) reset_gen (
    .clk_i(clk)
    ,.async_reset_o(reset)
  );
  // synopsys translate_on


  // non-blocking cache
  //
  `declare_bsg_cache_nb_pkt_s(addr_width_p,word_width_p,src_id_width_p);
  bsg_cache_nb_pkt_s cache_pkt;

  logic cache_v_li;
  logic cache_yumi_lo;

  logic [src_id_width_p:0] cache_src_id_lo;
  logic [word_width_p-1:0] cache_data_lo;
  logic cache_v_lo;
  logic cache_yumi_li;

  logic [bsg_cache_nb_dma_pkt_width_lp-1:0] cache_dma_pkt_lo;
  logic cache_dma_pkt_v_lo, cache_dma_pkt_yumi_li;

  logic [dma_data_width_p-1:0] dma_data_li;
  logic [lg_mshr_els_lp-1:0] dma_mshr_id_li;
  logic dma_data_v_li;
  logic dma_data_ready_lo;

  logic [dma_data_width_p-1:0] dma_data_lo;
  logic dma_data_v_lo;
  logic dma_data_yumi_li;

  logic cache_v_we_lo;

  // evict_req_fifo
  //
  logic [bsg_cache_nb_dma_pkt_width_lp-1:0] evict_req_fifo_pkt_lo;
  logic evict_req_fifo_valid_li, evict_req_fifo_ready_lo;
  logic evict_req_fifo_valid_lo, evict_req_fifo_yumi_li;

  // evict_data_fifo
  //
  logic evict_data_fifo_ready_lo, evict_data_fifo_v_lo;
  logic evict_data_fifo_yumi_li;
  logic [dma_data_width_p-1:0] evict_data_fifo_data_lo;

  // dma
  //
  logic dma_read_pkt_v_li, dma_read_pkt_yumi_lo;
  logic dma_write_pkt_v_li, dma_write_pkt_yumi_lo;
  logic [dma_data_width_p-1:0] dma_refill_data_lo;
  logic [lg_mshr_els_lp-1:0] dma_refill_mshr_id_lo;
  logic dma_refill_data_v_lo;

  // refill_data_fifo
  //
  logic refill_data_fifo_ready_lo, refill_data_fifo_yumi_li;

  // refill_mshr_id_fifo
  //
  logic refill_mshr_id_fifo_ready_lo, refill_mshr_id_fifo_v_lo;


  bsg_cache_nb #(
    .addr_width_p(addr_width_p)
    ,.word_width_p(word_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.sets_p(sets_p)
    ,.ways_p(ways_p)
    ,.mshr_els_p(mshr_els_p)
    ,.read_miss_els_per_mshr_p(read_miss_els_per_mshr_p)
    ,.src_id_width_p(src_id_width_p)
    ,.word_tracking_p(word_tracking_p)
    ,.dma_data_width_p(dma_data_width_p)
    ,.amo_support_p(amo_support_level_arithmetic_lp)
    ,.debug_p(0)
  ) DUT (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.cache_pkt_i(cache_pkt)
    ,.v_i(cache_v_li)
    ,.yumi_o(cache_yumi_lo)

    ,.data_o(cache_data_lo)
    ,.src_id_o(cache_src_id_lo)
    ,.v_o(cache_v_lo)
    ,.yumi_i(cache_yumi_li)

    ,.dma_pkt_o(cache_dma_pkt_lo)
    ,.dma_pkt_v_o(cache_dma_pkt_v_lo)
    ,.dma_pkt_yumi_i(cache_dma_pkt_yumi_li)
  
    ,.dma_data_i(dma_data_li)
    ,.dma_mshr_id_i(dma_mshr_id_li)
    ,.dma_data_v_i(dma_data_v_li)
    ,.dma_data_ready_o(dma_data_ready_lo)

    ,.dma_data_o(dma_data_lo)
    ,.dma_data_v_o(dma_data_v_lo)
    ,.dma_data_yumi_i(dma_data_yumi_li)

    ,.v_we_o(cache_v_we_lo)
  );

  //assign dma_data_yumi_li = dma_data_v_lo & evict_data_fifo_ready_lo;

  // synopsys translate_off

  // random yumi generator
  //
  bsg_nonsynth_random_yumi_gen #(
    .yumi_min_delay_p(yumi_min_delay_p)
    ,.yumi_max_delay_p(yumi_max_delay_p)
  ) yumi_gen (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.v_i(cache_v_lo)
    ,.yumi_o(cache_yumi_li)
  ); 


  bsg_fifo_1r1w_small #(
    .width_p(bsg_cache_nb_dma_pkt_width_lp)
    ,.els_p(mshr_els_p)
  ) evict_req_fifo (
    .clk_i(clk)
    ,.reset_i(reset)
    ,.data_i(cache_dma_pkt_lo)
    ,.v_i(evict_req_fifo_valid_li)
    ,.ready_o(evict_req_fifo_ready_lo)
    ,.v_o(evict_req_fifo_valid_lo)
    ,.data_o(evict_req_fifo_pkt_lo)
    ,.yumi_i(evict_req_fifo_yumi_li)
  );

  // bsg_fifo_1r1w_large #(
  //   .width_p(dma_data_width_p)
  //   ,.els_p(mshr_els_p*block_size_in_bursts_lp)
  // ) evict_data_fifo (
  //   .clk_i(clk)
  //   ,.reset_i(reset)
  //   ,.data_i(dma_data_lo)
  //   ,.v_i(dma_data_v_lo)
  //   ,.ready_o(evict_data_fifo_ready_lo) 
  //   ,.v_o(evict_data_fifo_v_lo)
  //   ,.data_o(evict_data_fifo_data_lo)
  //   ,.yumi_i(evict_data_fifo_yumi_li)
  // );

  // evict data counter
  //
  logic [lg_block_size_in_bursts_lp-1:0] evict_data_counter_r, evict_data_counter_n;
  assign evict_data_counter_n = (dma_data_v_lo & dma_data_yumi_li) //(evict_data_fifo_v_lo & evict_data_fifo_yumi_li)
                              ? (evict_data_counter_r==(block_size_in_bursts_lp-1)
                                ? 0
                                : evict_data_counter_r+1)
                              : evict_data_counter_r;
  //wire cache_line_evict_done = (evict_data_counter_r==(block_size_in_bursts_lp-1)) & evict_data_fifo_v_lo & evict_data_fifo_yumi_li;
  wire cache_line_evict_done = (evict_data_counter_r==(block_size_in_bursts_lp-1)) & dma_data_v_lo & dma_data_yumi_li;

  `declare_bsg_cache_nb_dma_pkt_s(addr_width_p,block_size_in_words_p,mshr_els_p);
  bsg_cache_nb_dma_pkt_s cache_dma_pkt, dma_read_pkt, dma_write_pkt;
  assign cache_dma_pkt = cache_dma_pkt_lo;
  assign dma_read_pkt = cache_dma_pkt;
  assign dma_write_pkt = evict_req_fifo_pkt_lo;

  assign cache_dma_pkt_yumi_li = cache_dma_pkt_v_lo
                               & ( cache_dma_pkt.write_not_read
                                 ? evict_req_fifo_ready_lo
                                 : dma_read_pkt_yumi_lo );

  assign evict_req_fifo_valid_li = cache_dma_pkt_v_lo & cache_dma_pkt.write_not_read;
  assign evict_req_fifo_yumi_li = cache_line_evict_done;


  // DMA model
  bsg_nonsynth_nb_dma_model #(
    .addr_width_p(addr_width_p)
    ,.word_width_p(word_width_p)
    ,.dma_data_width_p(dma_data_width_p)
    ,.mask_width_p(block_size_in_words_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.mshr_els_p(mshr_els_p)
    ,.els_p(mem_size_p)

    ,.read_delay_p(dma_read_delay_p)
    ,.write_delay_p(dma_write_delay_p)
    ,.dma_req_delay_p(dma_req_delay_p)
    ,.dma_data_delay_p(dma_data_delay_p)

  ) dma0 (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.dma_read_pkt_i(dma_read_pkt) 
    ,.dma_read_pkt_v_i(dma_read_pkt_v_li)
    ,.dma_read_pkt_yumi_o(dma_read_pkt_yumi_lo)

    ,.dma_write_pkt_i(dma_write_pkt)
    ,.dma_write_pkt_v_i(dma_write_pkt_v_li)
    ,.dma_write_pkt_yumi_o(dma_write_pkt_yumi_lo)

    ,.dma_data_o(dma_refill_data_lo)
    ,.dma_mshr_id_o(dma_refill_mshr_id_lo)
    ,.dma_data_v_o(dma_refill_data_v_lo)
    ,.dma_data_ready_i(refill_data_fifo_ready_lo & refill_mshr_id_fifo_ready_lo)

    //,.dma_data_i(evict_data_fifo_data_lo)
    ,.dma_data_i(dma_data_lo)
    
    //,.dma_data_v_i(evict_data_fifo_v_lo)
    ,.dma_data_v_i(dma_data_v_lo)

    //,.dma_data_yumi_o(evict_data_fifo_yumi_li)
    ,.dma_data_yumi_o(dma_data_yumi_li)
  );

  assign dma_read_pkt_v_li = cache_dma_pkt_v_lo & ~cache_dma_pkt.write_not_read & ~evict_req_fifo_valid_lo;
  assign dma_write_pkt_v_li = evict_req_fifo_valid_lo;

  bsg_fifo_1r1w_large #(
    .width_p(dma_data_width_p)
    ,.els_p(mshr_els_p*block_size_in_bursts_lp)
  ) refill_data_fifo (
    .clk_i(clk)
    ,.reset_i(reset)
    ,.data_i(dma_refill_data_lo)
    ,.v_i(dma_refill_data_v_lo)
    ,.ready_o(refill_data_fifo_ready_lo)
    ,.v_o(dma_data_v_li)
    ,.data_o(dma_data_li)
    ,.yumi_i(refill_data_fifo_yumi_li)
  );

  assign refill_data_fifo_yumi_li = dma_data_v_li & dma_data_ready_lo;

  bsg_fifo_1r1w_large #(
    .width_p(lg_mshr_els_lp)
    ,.els_p(mshr_els_p*block_size_in_bursts_lp)
  ) refill_mshr_id_fifo (
    .clk_i(clk)
    ,.reset_i(reset)
    ,.data_i(dma_refill_mshr_id_lo)
    ,.v_i(dma_refill_data_v_lo)
    ,.ready_o(refill_mshr_id_fifo_ready_lo)
    ,.v_o(refill_mshr_id_fifo_v_lo)
    ,.data_o(dma_mshr_id_li)
    ,.yumi_i(refill_data_fifo_yumi_li)
  );


  // trace replay
  //
  localparam rom_addr_width_lp = 26; 
  localparam ring_width_lp =
    `bsg_cache_nb_pkt_width(addr_width_p,word_width_p,src_id_width_p);

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
  ) test_rom (
    .addr_i(trace_rom_addr)
    ,.data_o(trace_rom_data)
  );


  assign cache_pkt = tr_data_lo;
  assign cache_v_li = tr_v_lo;
  assign tr_yumi_li = tr_v_lo & cache_yumi_lo;


  bind bsg_cache_nb basic_checker #(
    .word_width_p(word_width_p)
    ,.src_id_width_p(src_id_width_p)
    ,.addr_width_p(addr_width_p)
    ,.mem_size_p($root.testbench.mem_size_p)
  ) bc (
    .*
    ,.en_i($root.testbench.checker == "basic")
  );


  bind bsg_cache_nb tag_checker #(
    .word_width_p(word_width_p)
    ,.src_id_width_p(src_id_width_p)
    ,.addr_width_p(addr_width_p)
    ,.tag_width_lp(tag_width_lp)
    ,.ways_p(ways_p)
    ,.sets_p(sets_p)
    ,.block_size_in_words_p(block_size_in_words_p)
  ) tc (
    .*
    ,.en_i($root.testbench.checker == "tag")
  );

  bind bsg_cache_nb ainv_checker #(
    .word_width_p(word_width_p)
    ,.src_id_width_p(src_id_width_p)
  ) ac (
    .*
    ,.en_i($root.testbench.checker == "ainv")
  );


  //                        //
  //  FUNCTIONAL COVERAGE   //
  //                        //

  bind bsg_cache_nb cov_top #(.mshr_els_p(mshr_els_p)) _cov_top (.*);
  bind bsg_cache_nb_evict_fill_transmitter cov_trans _cov_trans (.*);
  bind bsg_cache_nb_tag_mgmt_unit cov_mgmt #(.ways_p(ways_p)) _cov_mgmt (.*);
  bind bsg_cache_nb_dma cov_dma #(.block_size_in_bursts_p(block_size_in_bursts_lp)) _cov_dma (.*);
  bind bsg_cache_nb_mhu cov_mhu #(.ways_p(ways_p)) _cov_mhu (.*);
  // bind mhu[0].miss_handling_unit cov_mhu _cov_mhu_inst[0] (.*);





  always_ff @ (posedge clk) begin
    if (reset) begin
      evict_data_counter_r <= '0;
    end
    else begin
      evict_data_counter_r <= evict_data_counter_n;
    end
  end


  // waiting for all responses to be received.
  //
  integer sent_r, recv_r;

  always_ff @ (posedge clk) begin
    if (reset) begin
      sent_r <= '0;
      recv_r <= '0;
    end
    else begin

      if (cache_v_li & cache_yumi_lo)
        sent_r <= sent_r + 1;

      if (cache_v_lo & (cache_src_id_lo[src_id_width_p]) & cache_yumi_li)
        recv_r <= recv_r + 1;
     //$display("done=%d, sent_r=%d, recv_r=%d", done, sent_r, recv_r);
     //$display("cache_v_lo=%d, cache_yumi_li=%d", cache_v_lo, cache_yumi_li);
    end
  end

  initial begin
    wait(done & (sent_r == recv_r));
    $display("[BSG_FINISH] Test Successful.");
    //for (integer i = 0; i < 1000000; i++)
    //  @(posedge clk);
    #500;
    $finish;
  end

  // synopsys translate_on

endmodule


