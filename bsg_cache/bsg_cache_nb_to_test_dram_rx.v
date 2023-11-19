/**
 *    bsg_cache_nb_to_test_dram_rx.v
 *
 */


`include "bsg_defines.v"

module bsg_cache_nb_to_test_dram_rx
  #(parameter `BSG_INV_PARAM(num_cache_p)
    , parameter `BSG_INV_PARAM(data_width_p)
    , parameter `BSG_INV_PARAM(dma_data_width_p)
    , parameter `BSG_INV_PARAM(block_size_in_words_p)

    , parameter `BSG_INV_PARAM(dram_data_width_p)
    , parameter `BSG_INV_PARAM(dram_channel_addr_width_p)

    , parameter `BSG_INV_PARAM(mshr_els_p)

    , parameter lg_mshr_els_lp = `BSG_SAFE_CLOG2(mshr_els_p)
    , parameter lg_num_cache_lp = `BSG_SAFE_CLOG2(num_cache_p)
    , parameter num_req_lp = (block_size_in_words_p*data_width_p/dram_data_width_p)
    , parameter lg_num_req_lp = `BSG_SAFE_CLOG2(num_req_lp)

    , parameter block_size_in_bursts_lp = (block_size_in_words_p*data_width_p/dma_data_width_p)
    , parameter lg_block_size_in_bursts_lp = `BSG_SAFE_CLOG2(block_size_in_bursts_lp)

  )
  (
    input core_clk_i
    , input core_reset_i

    , output logic [num_cache_p-1:0][dma_data_width_p-1:0] dma_data_o
    , output logic [num_cache_p-1:0][lg_mshr_els_lp-1:0] dma_mshr_id_o
    , output logic [num_cache_p-1:0] dma_data_v_o
    , input [num_cache_p-1:0] dma_data_ready_i

    , input dram_clk_i
    , input dram_reset_i
    
    , input dram_data_v_i
    , input [lg_mshr_els_lp-1:0] dram_mshr_id_i
    , input [dram_data_width_p-1:0] dram_data_i
    , input [dram_channel_addr_width_p-1:0] dram_ch_addr_i
  );


  // ch_addr CDC
  //
  logic ch_addr_afifo_full;
  logic ch_addr_afifo_deq;
  logic [dram_channel_addr_width_p-1:0] ch_addr_lo;
  logic [lg_mshr_els_lp-1:0] mshr_id_lo;
  logic ch_addr_v_lo;

  bsg_async_fifo #(
    .lg_size_p(`BSG_SAFE_CLOG2(`BSG_MAX(num_req_lp*num_cache_p*mshr_els_p,4)))
    ,.width_p(dram_channel_addr_width_p+lg_mshr_els_lp)
  ) ch_addr_afifo (
    .w_clk_i(dram_clk_i)
    ,.w_reset_i(dram_reset_i)
    ,.w_enq_i(dram_data_v_i)
    ,.w_data_i({dram_ch_addr_i,dram_mshr_id_i})
    ,.w_full_o(ch_addr_afifo_full)

    ,.r_clk_i(core_clk_i)
    ,.r_reset_i(core_reset_i)
    ,.r_deq_i(ch_addr_afifo_deq)
    ,.r_data_o({ch_addr_lo,mshr_id_lo})
    ,.r_valid_o(ch_addr_v_lo)
  );



  // data CDC
  //
  logic data_afifo_full;
  logic data_afifo_deq;
  logic [dram_data_width_p-1:0] dram_data_lo;
  logic dram_data_v_lo;

  bsg_async_fifo #(
    .lg_size_p(`BSG_SAFE_CLOG2(`BSG_MAX(num_req_lp*num_cache_p*mshr_els_p,4)))
    ,.width_p(dram_data_width_p)
  ) data_afifo (
    .w_clk_i(dram_clk_i)
    ,.w_reset_i(dram_reset_i)
    ,.w_enq_i(dram_data_v_i)
    ,.w_data_i(dram_data_i)
    ,.w_full_o(data_afifo_full)

    ,.r_clk_i(core_clk_i)
    ,.r_reset_i(core_reset_i)
    ,.r_deq_i(data_afifo_deq)
    ,.r_data_o(dram_data_lo)
    ,.r_valid_o(dram_data_v_lo)
  );



  // reorder buffer
  //

  // using the ch address, forward the data to the correct cache.
  logic [lg_num_cache_lp-1:0] cache_id;

  if (num_cache_p == 1) begin
    assign cache_id = 1'b0;
  end
  else begin
    assign cache_id = ch_addr_lo[dram_channel_addr_width_p-1-:lg_num_cache_lp];
  end

  logic [num_cache_p-1:0] cache_id_decode;
  bsg_decode_with_v #(
    .num_out_p(num_cache_p)
  ) demux0 (
    .i(cache_id)
    ,.v_i(ch_addr_v_lo & dram_data_v_lo)
    ,.o(cache_id_decode)
  );

  logic [mshr_els_p-1:0] mshr_id_decode;
  bsg_decode_with_v #(
    .num_out_p(mshr_els_p)
  ) demux1 (
    .i(mshr_id_lo)
    ,.v_i(ch_addr_v_lo & dram_data_v_lo)
    ,.o(mshr_id_decode)
  );

  // round robin arbiter to decide for each cache which mshr to send data back to cache
  //
  logic [num_cache_p-1:0] rr_yumi_li;
  logic [num_cache_p-1:0][mshr_els_p-1:0] rr_grants_lo;

  logic [num_cache_p-1:0][lg_mshr_els_lp-1:0] rr_grants_mshr_id;
  logic [num_cache_p-1:0] rr_grants_v_found;

  logic [num_cache_p-1:0][lg_mshr_els_lp-1:0] rr_grants_mshr_id_r, rr_grants_mshr_id_n;  

  // send counter to count the number of bursts each cache has sent back to cache
  //
  logic [num_cache_p-1:0] send_counter_clear;
  logic [num_cache_p-1:0] send_counter_up;
  logic [num_cache_p-1:0] [`BSG_WIDTH(block_size_in_bursts_lp)-1:0] send_count_r;

  // recv counter to count the number of request results each mshr in each cache has received
  //
  logic [num_cache_p-1:0][mshr_els_p-1:0] recv_counter_clear;
  logic [num_cache_p-1:0][mshr_els_p-1:0] recv_counter_up;
  logic [num_cache_p-1:0][mshr_els_p-1:0] [`BSG_WIDTH(num_req_lp)-1:0] recv_count_r; 
  logic [num_cache_p-1:0][mshr_els_p-1:0] recv_done;

  // reorder buffer
  //
  logic [num_cache_p-1:0][mshr_els_p-1:0] reorder_v_li, reorder_v_lo;
  logic [num_cache_p-1:0][mshr_els_p-1:0][dma_data_width_p-1:0] reorder_data_lo;
  logic [num_cache_p-1:0][mshr_els_p-1:0] reorder_ready_li;
  logic [num_cache_p-1:0] reorder_cache_ready;

  for (genvar i = 0 ; i < num_cache_p; i++) begin: reorder_v
    assign reorder_v_li[i] = cache_id_decode[i] ? mshr_id_decode : '0;
  end


  for (genvar i = 0; i < num_cache_p; i++) begin: re_cache_index
    for (genvar j = 0; j < mshr_els_p; j++) begin: re_mshr_index
      bsg_cache_to_test_dram_rx_reorder #(
        .data_width_p(data_width_p)
        ,.dma_data_width_p(dma_data_width_p)
        ,.block_size_in_words_p(block_size_in_words_p)

        ,.dram_data_width_p(dram_data_width_p)
        ,.dram_channel_addr_width_p(dram_channel_addr_width_p)
      ) reorder0 (
        .core_clk_i(core_clk_i)
        ,.core_reset_i(core_reset_i)

        ,.dram_v_i(reorder_v_li[i][j])
        ,.dram_data_i(dram_data_lo)
        ,.dram_ch_addr_i(ch_addr_lo)

        ,.dma_data_o(reorder_data_lo[i][j])
        ,.dma_data_v_o(reorder_v_lo[i][j])
        ,.dma_data_ready_i(reorder_ready_li[i][j])
      );

      assign reorder_ready_li[i][j] = reorder_cache_ready[i] & (j==rr_grants_mshr_id_r[i]);

    end
  end


  for (genvar i = 0; i < num_cache_p; i++) begin: recv_cnt_cache_index
    for (genvar j = 0; j < mshr_els_p; j++) begin: recv_cnt_mshr_index
      bsg_counter_clear_up #(
        .max_val_p(num_req_lp)
        ,.init_val_p(0)
      ) recv_cnt (
        .clk_i(core_clk_i)
        ,.reset_i(core_reset_i)
        ,.clear_i(recv_counter_clear[i][j])
        ,.up_i(recv_counter_up[i][j])
        ,.count_o(recv_count_r[i][j])
      );

      assign recv_done[i][j] = recv_count_r[i][j]==num_req_lp; //TODO: || recv_count_r[i][j]==num_req_lp-1 && recv_counter_up[i][j]
      assign recv_counter_clear[i][j] = send_counter_clear[i] & (rr_grants_mshr_id_r[i]==j);
      assign recv_counter_up[i][j] = reorder_v_li[i][j];
    end
  end


  for (genvar i = 0; i < num_cache_p; i++) begin: rr_ccu

    bsg_arb_round_robin #(
      .width_p(mshr_els_p)
    ) rr (
      .clk_i(core_clk_i)
      ,.reset_i(core_reset_i)

      ,.reqs_i(recv_done[i] & reorder_v_lo[i])
      ,.grants_o(rr_grants_lo[i])
      ,.yumi_i(rr_yumi_li[i])
    );

    bsg_priority_encode #(
      .width_p(mshr_els_p)
      ,.lo_to_hi_p(1)
    ) rr_grants_pe (
      .i(rr_grants_lo[i])
      ,.addr_o(rr_grants_mshr_id[i])
      ,.v_o(rr_grants_v_found[i])
    );

    bsg_counter_clear_up #(
      .max_val_p(block_size_in_bursts_lp)
      ,.init_val_p(0)
    ) send_cnt (
      .clk_i(core_clk_i)
      ,.reset_i(core_reset_i)
      ,.clear_i(send_counter_clear[i])
      ,.up_i(send_counter_up[i])
      ,.count_o(send_count_r[i])
    );
  end

  always_comb begin
    for (integer i = 0; i < num_cache_p; i++) begin: def
      send_counter_up[i] = 1'b0;
      send_counter_clear[i] = 1'b0;
      rr_yumi_li[i] = 1'b0;
      dma_data_v_o[i] = 1'b0;
      rr_grants_mshr_id_n[i] = rr_grants_mshr_id_r[i];
      reorder_cache_ready[i] = 1'b0;

      if (send_count_r[i]==0) begin
        if (|(recv_done[i] & reorder_v_lo[i])) begin
          rr_grants_mshr_id_n[i] = rr_grants_mshr_id[i];
          send_counter_up[i] = 1'b1;  // It hasn't sent data but we increment the counter here
          rr_yumi_li[i] = 1'b1;
          dma_data_v_o[i] = 1'b1;
        end
      end
      else begin
        dma_data_v_o[i] = reorder_v_lo[i][rr_grants_mshr_id_n[i]];
        reorder_cache_ready[i] = dma_data_ready_i[i];

        if (dma_data_ready_i[i] & dma_data_v_o[i]) begin
          if (send_count_r[i]==block_size_in_bursts_lp) send_counter_clear[i] = 1'b1;
          else send_counter_up[i] = 1'b1;
        end

      end

    end
  end

  for (genvar i = 0 ; i < num_cache_p; i++) begin: out_val
    assign dma_data_o[i] = reorder_data_lo[i][rr_grants_mshr_id_n[i]];
    assign dma_mshr_id_o[i] = rr_grants_mshr_id_n[i];
  end


  assign data_afifo_deq = ch_addr_v_lo & dram_data_v_lo;
  assign ch_addr_afifo_deq = ch_addr_v_lo & dram_data_v_lo;

  always_ff @ (posedge core_clk_i) begin
    if (core_reset_i) begin
      rr_grants_mshr_id_r <= '0;
    end
    else begin
      rr_grants_mshr_id_r <= rr_grants_mshr_id_n;
    end
  end


  // synopsys translate_off
  
  always_ff @ (negedge dram_clk_i) begin
    if (~dram_reset_i & dram_data_v_i) begin
      assert(~data_afifo_full) else $fatal(1, "data async_fifo full!");
      assert(~ch_addr_afifo_full) else $fatal(1, "ch_addr async_fifo full!");
    end
  end

  // synopsys translate_on


endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_to_test_dram_rx)
