
`include "bsg_defines.v"
`include "bsg_cache_nb.vh"

module bsg_cache_nb_to_test_dram 
  import bsg_cache_nb_pkg::*;
  #(parameter `BSG_INV_PARAM(num_cache_p)
    , parameter `BSG_INV_PARAM(addr_width_p) // cache addr (byte)
    , parameter `BSG_INV_PARAM(data_width_p) // cache data width
    , parameter `BSG_INV_PARAM(block_size_in_words_p) // cache block_size (word)
    , parameter `BSG_INV_PARAM(cache_bank_addr_width_p) // actual number of bits used for address (byte)

    , parameter `BSG_INV_PARAM(mshr_els_p) 

    , parameter `BSG_INV_PARAM(dram_channel_addr_width_p) // dram channel addr
    , parameter `BSG_INV_PARAM(dram_data_width_p) // dram channel data width

    , parameter dma_data_width_p=data_width_p // cache dma data width 

    , parameter evict_lut_size_lp = 4*mshr_els_p  //TODO: not sure what would be the best size for this
    , parameter lg_evict_lut_size_lp = `BSG_SAFE_CLOG2(evict_lut_size_lp)

    , parameter num_req_lp = (block_size_in_words_p*data_width_p/dram_data_width_p) // number of DRAM requests sent per cache miss.
    , parameter lg_num_req_lp = `BSG_SAFE_CLOG2(num_req_lp)
    , parameter lg_mshr_els_lp = `BSG_SAFE_CLOG2(mshr_els_p)
    , parameter dram_byte_offset_width_lp = `BSG_SAFE_CLOG2(dram_data_width_p>>3)

    , parameter lg_num_cache_lp=`BSG_SAFE_CLOG2(num_cache_p)
    , parameter dma_pkt_width_lp=`bsg_cache_nb_dma_pkt_width(addr_width_p, block_size_in_words_p, mshr_els_p)
  )
  (
    // vcache dma interface
    input core_clk_i
    , input core_reset_i

    , input [num_cache_p-1:0][dma_pkt_width_lp-1:0] dma_pkt_i
    , input [num_cache_p-1:0] dma_pkt_v_i
    , output logic [num_cache_p-1:0] dma_pkt_yumi_o

    , output logic [num_cache_p-1:0][dma_data_width_p-1:0] dma_data_o
    , output logic [num_cache_p-1:0][lg_mshr_els_lp-1:0] dma_mshr_id_o
    , output logic [num_cache_p-1:0] dma_data_v_o
    , input [num_cache_p-1:0] dma_data_ready_i

    , input [num_cache_p-1:0][dma_data_width_p-1:0] dma_data_i
    , input [num_cache_p-1:0] dma_data_v_i
    , output logic [num_cache_p-1:0] dma_data_yumi_o

    // dram
    , input dram_clk_i
    , input dram_reset_i

    // dram request channel (valid-yumi)
    , output logic dram_req_v_o
    , output logic dram_write_not_read_o
    , output logic [dram_channel_addr_width_p-1:0] dram_ch_addr_o // read done addr
    , input dram_req_yumi_i

    // dram write data channel (valid-yumi)
    , output logic dram_data_v_o
    , output logic [dram_data_width_p-1:0] dram_data_o
    , output logic [(dram_data_width_p>>3)-1:0] dram_mask_o
    , input dram_data_yumi_i

    , input dram_write_done_i // write done signal
    , input [dram_channel_addr_width_p-1:0] dram_wd_ch_addr_i // write done addr    

    // dram read data channel (valid-only)
    , input dram_data_v_i
    , input [dram_data_width_p-1:0] dram_data_i
    , input [dram_channel_addr_width_p-1:0] dram_rd_ch_addr_i // the address of incoming data
  );

  //localparam dram_cache_line_addr_offset_lp = num_req_lp == 1 ? dram_byte_offset_width_lp : dram_byte_offset_width_lp+lg_num_req_lp;
  localparam dram_cache_line_addr_offset_lp = dram_byte_offset_width_lp+lg_num_req_lp;
  localparam dram_cache_line_addr_width_lp = cache_bank_addr_width_p-dram_cache_line_addr_offset_lp;

  // dma pkt
  //
  `declare_bsg_cache_nb_dma_pkt_s(addr_width_p, block_size_in_words_p, mshr_els_p);
  bsg_cache_nb_dma_pkt_s [num_cache_p-1:0] dma_pkt;
  assign dma_pkt = dma_pkt_i;

  // request async fifo
  //
  logic req_afifo_enq;
  logic req_afifo_full;
  logic req_afifo_valid_lo, req_afifo_yumi_li;
  logic [lg_mshr_els_lp-1:0] send_mshr_id_lo;

  logic [lg_num_cache_lp-1:0] return_rd_cache_id, return_wd_cache_id, send_cache_id;
  if (num_cache_p == 1) begin
    assign return_rd_cache_id = 1'b0;
    assign return_wd_cache_id = 1'b0;
    assign send_cache_id = 1'b0;
  end
  else begin
    assign return_rd_cache_id = dram_rd_ch_addr_i[dram_channel_addr_width_p-1-:lg_num_cache_lp];
    assign return_wd_cache_id = dram_wd_ch_addr_i[dram_channel_addr_width_p-1-:lg_num_cache_lp];
    assign send_cache_id = dram_ch_addr_o[dram_channel_addr_width_p-1-:lg_num_cache_lp];
  end

  // refill mshr_id LUT
  logic [num_cache_p-1:0][mshr_els_p-1:0] lut_refill_tag_v_r;
  logic [num_cache_p-1:0][mshr_els_p-1:0][dram_cache_line_addr_width_lp-1:0] lut_refill_cache_addr_offset_r;
  logic [num_cache_p-1:0][mshr_els_p-1:0][lg_num_req_lp-1:0] lut_refill_enq_count_r;
  
  wire [dram_cache_line_addr_width_lp-1:0] dram_rd_ch_addr_cache_line_addr_picked = dram_rd_ch_addr_i[dram_cache_line_addr_offset_lp+:dram_cache_line_addr_width_lp];
  logic [mshr_els_p-1:0] rd_cache_line_addr_hit;

  for (genvar i = 0; i < mshr_els_p; i++) begin: rd_cache_line_addr_hit_bits
    assign rd_cache_line_addr_hit[i] = (dram_rd_ch_addr_cache_line_addr_picked == lut_refill_cache_addr_offset_r[return_rd_cache_id][i]) & lut_refill_tag_v_r[return_rd_cache_id][i];
  end

  logic [lg_mshr_els_lp-1:0] rd_cache_line_addr_hit_mshr_id;
  logic [lg_mshr_els_lp-1:0] dram_mshr_id_li;
  logic rd_cache_line_addr_hit_found;

  bsg_priority_encode #(
    .width_p(mshr_els_p)
    ,.lo_to_hi_p(1)
  ) rd_cache_line_addr_hit_pe (
    .i(rd_cache_line_addr_hit)
    ,.addr_o(rd_cache_line_addr_hit_mshr_id)
    ,.v_o(rd_cache_line_addr_hit_found)
  );

  assign dram_mshr_id_li = rd_cache_line_addr_hit_mshr_id;


  // evict addr LUT 
  logic [num_cache_p-1:0][evict_lut_size_lp-1:0] lut_evict_tag_v_r;
  logic [num_cache_p-1:0][lg_evict_lut_size_lp-1:0] lut_evict_next_alloc_index;
  logic [num_cache_p-1:0] lut_evict_avail;
  logic [num_cache_p-1:0][evict_lut_size_lp-1:0][dram_cache_line_addr_width_lp-1:0] lut_evict_cache_addr_offset_r;
  logic [num_cache_p-1:0][evict_lut_size_lp-1:0][lg_num_req_lp-1:0] lut_evict_enq_count_r;

  logic req_stall;

  wire [dram_cache_line_addr_width_lp-1:0] dram_wd_ch_addr_cache_line_addr_picked = dram_wd_ch_addr_i[dram_cache_line_addr_offset_lp+:dram_cache_line_addr_width_lp];
  logic [evict_lut_size_lp-1:0] wd_cache_line_addr_hit;

  for (genvar i = 0; i < evict_lut_size_lp; i++) begin: wd_cache_line_addr_hit_bits
    assign wd_cache_line_addr_hit[i] = (dram_wd_ch_addr_cache_line_addr_picked == lut_evict_cache_addr_offset_r[return_wd_cache_id][i]) & lut_evict_tag_v_r[return_wd_cache_id][i];
  end

  logic [lg_evict_lut_size_lp-1:0] wd_cache_line_addr_hit_index;
  logic wd_cache_line_addr_hit_found;


  // It's possible to have more than one 1s in wd_cache_line_addr_hit since we have AFL & TAGFL
  // it doesn't matter which one we pick, since the purpose of evict LUT is to make sure refill
  // request won't be sent out until there're no pending evict requests to the same address, so 
  // to make refill request able to go, it should have no pending evict requests to the same address
  // so we have to wait for all those evictions to be done. Thus we don't care which index to clear
  // every time a write done signal comes,  we only care if we have cleared all the req to that addr
  // or not
  bsg_priority_encode #(
    .width_p(evict_lut_size_lp)
    ,.lo_to_hi_p(1)
  ) wd_cache_line_addr_hit_pe (
    .i(wd_cache_line_addr_hit)
    ,.addr_o(wd_cache_line_addr_hit_index)
    ,.v_o(wd_cache_line_addr_hit_found)
  );

  for (genvar i = 0 ; i < num_cache_p; i++) begin: evict_alloc_pe
    bsg_priority_encode #(
      .width_p(evict_lut_size_lp)
      ,.lo_to_hi_p(1)
    ) lut_evict_allocate_enc (
      .i((~lut_evict_tag_v_r[i]))
      ,.addr_o(lut_evict_next_alloc_index[i])
      ,.v_o(lut_evict_avail[i])
    );
  end


  logic [evict_lut_size_lp-1:0] read_after_write_hit;

  for (genvar i = 0; i < evict_lut_size_lp; i++) begin: read_after_write_check
    assign read_after_write_hit[i] = lut_evict_tag_v_r[send_cache_id][i]
                                   & (dram_ch_addr_o[dram_cache_line_addr_offset_lp+:dram_cache_line_addr_width_lp] == lut_evict_cache_addr_offset_r[send_cache_id][i]);
  end
  
  wire read_after_write_hit_found = (|read_after_write_hit) & req_afifo_valid_lo & ~dram_write_not_read_o;


  // request round robin
  //
  logic rr_v_lo;
  logic rr_yumi_li;
  bsg_cache_nb_dma_pkt_s rr_dma_pkt_lo;
  logic [lg_num_cache_lp-1:0] rr_tag_lo;

  logic [lg_num_cache_lp-1:0] rr_tag_r, rr_tag_n;
  bsg_cache_nb_dma_pkt_s dma_pkt_r, dma_pkt_n;

  bsg_round_robin_n_to_1 #(
    .width_p(dma_pkt_width_lp)
    ,.num_in_p(num_cache_p)
    ,.strict_p(0)
    ,.use_scan_p(1)
  ) rr0 (
    .clk_i(core_clk_i)
    ,.reset_i(core_reset_i)

    ,.data_i(dma_pkt)
    ,.v_i(dma_pkt_v_i)
    ,.yumi_o(dma_pkt_yumi_o)

    ,.v_o(rr_v_lo)
    ,.data_o(rr_dma_pkt_lo)
    ,.tag_o(rr_tag_lo)
    ,.yumi_i(rr_yumi_li)
  );



  logic enq_counter_clear;
  logic enq_counter_up;
  logic [lg_num_req_lp-1:0] enq_count_r; // this counts the number of DRAM requests enqueued.

  bsg_counter_clear_up #(
    .max_val_p(num_req_lp-1)
    ,.init_val_p(0)
  ) ccu0 (
    .clk_i(core_clk_i)
    ,.reset_i(core_reset_i)
    ,.clear_i(enq_counter_clear)
    ,.up_i(enq_counter_up)
    ,.count_o(enq_count_r)
  );

  logic deq_counter_clear;
  logic deq_counter_up;
  logic [lg_num_req_lp-1:0] deq_count_r; // this counts the number of DRAM requests dequeued.

  bsg_counter_clear_up #(
    .max_val_p(num_req_lp-1)
    ,.init_val_p(0)
  ) ccu1 (
    .clk_i(dram_clk_i)
    ,.reset_i(dram_reset_i)
    ,.clear_i(deq_counter_clear)
    ,.up_i(deq_counter_up)
    ,.count_o(deq_count_r)
  );
  
  assign deq_counter_up = dram_req_v_o & dram_req_yumi_i & (deq_count_r!=num_req_lp-1);
  assign deq_counter_clear = dram_req_v_o & dram_req_yumi_i & (deq_count_r==num_req_lp-1);


  logic [dram_channel_addr_width_p-1:0] dram_req_addr;

  bsg_async_fifo #(
    .lg_size_p(`BSG_SAFE_CLOG2(2*num_req_lp*num_cache_p*mshr_els_p))
    ,.width_p(1+lg_mshr_els_lp+dram_channel_addr_width_p)
  ) req_afifo (
    .w_clk_i(core_clk_i)
    ,.w_reset_i(core_reset_i)
    ,.w_enq_i(req_afifo_enq)
    ,.w_data_i({dma_pkt_n.write_not_read, dma_pkt_n.mshr_id, dram_req_addr})
    ,.w_full_o(req_afifo_full)

    ,.r_clk_i(dram_clk_i)
    ,.r_reset_i(dram_reset_i)
    ,.r_deq_i(req_afifo_yumi_li)
    ,.r_data_o({dram_write_not_read_o, send_mshr_id_lo, dram_ch_addr_o})
    ,.r_valid_o(req_afifo_valid_lo)
  );
  
  wire evict_lut_alloc_full = (deq_count_r==0) & req_afifo_valid_lo & dram_write_not_read_o & (~lut_evict_avail[send_cache_id]);
  assign req_stall = read_after_write_hit_found | evict_lut_alloc_full;
  assign dram_req_v_o = req_afifo_valid_lo & ~req_stall;
  assign req_afifo_yumi_li = dram_req_yumi_i & ~req_stall; // for safety


  // RX
  //
  bsg_cache_nb_to_test_dram_rx #(
    .num_cache_p(num_cache_p)
    ,.data_width_p(data_width_p)
    ,.dma_data_width_p(dma_data_width_p)
    ,.dram_data_width_p(dram_data_width_p)
    ,.dram_channel_addr_width_p(dram_channel_addr_width_p)
    ,.mshr_els_p(mshr_els_p)
    ,.block_size_in_words_p(block_size_in_words_p)
  ) rx0 (
    .core_clk_i(core_clk_i)
    ,.core_reset_i(core_reset_i)

    ,.dma_data_o(dma_data_o)
    ,.dma_mshr_id_o(dma_mshr_id_o)
    ,.dma_data_v_o(dma_data_v_o)
    ,.dma_data_ready_i(dma_data_ready_i)

    ,.dram_clk_i(dram_clk_i)
    ,.dram_reset_i(dram_reset_i)

    ,.dram_data_v_i(dram_data_v_i)
    ,.dram_data_i(dram_data_i)
    ,.dram_mshr_id_i(dram_mshr_id_li)
    ,.dram_ch_addr_i(dram_rd_ch_addr_i)
  );


  // TX
  //
  logic tx_v_li;
  logic tx_ready_lo;
  logic [(block_size_in_words_p/num_req_lp)-1:0] tx_mask_li;

  bsg_cache_nb_to_test_dram_tx #(
    .num_cache_p(num_cache_p)
    ,.data_width_p(data_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.dma_data_width_p(dma_data_width_p)
    ,.dram_data_width_p(dram_data_width_p)
    ,.mshr_els_p(mshr_els_p)
  ) tx0 (
    .core_clk_i(core_clk_i)
    ,.core_reset_i(core_reset_i)

    ,.v_i(tx_v_li)
    ,.tag_i(rr_tag_n)
    ,.mask_i(tx_mask_li)
    ,.ready_o(tx_ready_lo)

    ,.dma_data_i(dma_data_i)
    ,.dma_data_v_i(dma_data_v_i)
    ,.dma_data_yumi_o(dma_data_yumi_o)

    ,.dram_clk_i(dram_clk_i)
    ,.dram_reset_i(dram_reset_i)

    ,.dram_data_v_o(dram_data_v_o)
    ,.dram_data_o(dram_data_o)
    ,.dram_mask_o(dram_mask_o)
    ,.dram_data_yumi_i(dram_data_yumi_i)
  );
 
  
  if (num_req_lp == 1) begin: req1
    assign enq_counter_up = 1'b0;
    assign enq_counter_clear = 1'b0;
    assign rr_yumi_li = rr_v_lo & ~req_afifo_full & (rr_dma_pkt_lo.write_not_read ? tx_ready_lo : 1'b1);
    assign req_afifo_enq = rr_v_lo & ~req_afifo_full & (rr_dma_pkt_lo.write_not_read ? tx_ready_lo : 1'b1);
    assign tx_v_li = rr_v_lo & ~req_afifo_full & rr_dma_pkt_lo.write_not_read & tx_ready_lo;
    assign rr_tag_n = rr_tag_lo;
    assign dma_pkt_n = rr_dma_pkt_lo;
    assign tx_mask_li = rr_dma_pkt_lo.mask;
  end
  else begin: reqn
    
    always_comb begin
      enq_counter_up = 1'b0;
      enq_counter_clear = 1'b0;
      rr_yumi_li = 1'b0;
      req_afifo_enq = 1'b0;
      tx_v_li = 1'b0;
      rr_tag_n = rr_tag_r;
      dma_pkt_n = dma_pkt_r;

      if (enq_count_r == 0) begin
        if (rr_v_lo & ~req_afifo_full & (rr_dma_pkt_lo.write_not_read ? tx_ready_lo : 1'b1)) begin
          enq_counter_up = 1'b1;
          rr_yumi_li = 1'b1;
          req_afifo_enq = 1'b1;
          tx_v_li = rr_dma_pkt_lo.write_not_read;
          rr_tag_n = rr_tag_lo;
          dma_pkt_n = rr_dma_pkt_lo;
        end
      end
      else if (enq_count_r == num_req_lp-1) begin
        if (~req_afifo_full & (dma_pkt_r.write_not_read ? tx_ready_lo : 1'b1)) begin
          enq_counter_clear = 1'b1;
          req_afifo_enq = 1'b1;
          tx_v_li = dma_pkt_r.write_not_read;
        end
      end
      else begin
        if (~req_afifo_full & (dma_pkt_r.write_not_read ? tx_ready_lo : 1'b1)) begin
          enq_counter_up = 1'b1;
          req_afifo_enq = 1'b1;
          tx_v_li = dma_pkt_r.write_not_read;
        end
      end      
    end

    bsg_mux #(
      .els_p(num_req_lp)
      ,.width_p(block_size_in_words_p/num_req_lp)
    ) mask_mux (
      .data_i(dma_pkt_n.mask)
      ,.sel_i(enq_count_r)
      ,.data_o(tx_mask_li)
    );

  end


  always_ff @ (posedge core_clk_i) begin
    if (core_reset_i) begin
      dma_pkt_r <= '0;
      rr_tag_r <= '0;
    end
    else begin
      dma_pkt_r <= dma_pkt_n;
      rr_tag_r <= rr_tag_n;
    end
  end

  // address logic
  if (num_cache_p == 1) begin
    if (num_req_lp == 1) begin
      assign dram_req_addr = {
        {(dram_channel_addr_width_p-cache_bank_addr_width_p){1'b0}},
        dma_pkt_n.addr[cache_bank_addr_width_p-1:dram_byte_offset_width_lp],
        {dram_byte_offset_width_lp{1'b0}}
      };
    end
    else begin
      assign dram_req_addr = {
        {(dram_channel_addr_width_p-cache_bank_addr_width_p){1'b0}},
        dma_pkt_n.addr[cache_bank_addr_width_p-1:dram_byte_offset_width_lp+lg_num_req_lp],
        enq_count_r,
        {dram_byte_offset_width_lp{1'b0}}
      };
    end
  end
  else begin
    if (num_req_lp == 1) begin
      assign dram_req_addr = {
        rr_tag_n,
        {(dram_channel_addr_width_p-cache_bank_addr_width_p-lg_num_cache_lp){1'b0}},
        dma_pkt_n.addr[cache_bank_addr_width_p-1:dram_byte_offset_width_lp],
        {dram_byte_offset_width_lp{1'b0}}
      };
    end
    else begin
      assign dram_req_addr = {
        rr_tag_n,
        {(dram_channel_addr_width_p-cache_bank_addr_width_p-lg_num_cache_lp){1'b0}},
        dma_pkt_n.addr[cache_bank_addr_width_p-1:dram_byte_offset_width_lp+lg_num_req_lp],
        enq_count_r,
        {dram_byte_offset_width_lp{1'b0}}
      };
    end
  end


  always_ff @ (posedge dram_clk_i) begin
    if (dram_reset_i) begin
      lut_refill_tag_v_r <= '0;
      lut_refill_cache_addr_offset_r <= '0;
      lut_refill_enq_count_r <= '0;
      lut_evict_tag_v_r <= '0;
      lut_evict_cache_addr_offset_r <= '0;
      lut_evict_enq_count_r <= '0;
    end
    else begin

      if (dram_req_v_o & req_afifo_yumi_li & (deq_count_r==0)) begin
        if(~dram_write_not_read_o) begin
          lut_refill_tag_v_r[send_cache_id][send_mshr_id_lo] <= 1'b1;
          lut_refill_cache_addr_offset_r[send_cache_id][send_mshr_id_lo] <= dram_ch_addr_o[dram_cache_line_addr_offset_lp+:dram_cache_line_addr_width_lp];
        end
        else begin
          lut_evict_tag_v_r[send_cache_id][lut_evict_next_alloc_index[send_cache_id]] <= 1'b1;
          lut_evict_cache_addr_offset_r[send_cache_id][lut_evict_next_alloc_index[send_cache_id]] <= dram_ch_addr_o[dram_cache_line_addr_offset_lp+:dram_cache_line_addr_width_lp];
        end
      end

      if (dram_data_v_i) begin
        if ((lut_refill_enq_count_r[return_rd_cache_id][rd_cache_line_addr_hit_mshr_id]==num_req_lp-1)) begin
          lut_refill_tag_v_r[return_rd_cache_id][rd_cache_line_addr_hit_mshr_id] <= 1'b0;
          lut_refill_enq_count_r[return_rd_cache_id][rd_cache_line_addr_hit_mshr_id] <= '0;
        end 
        else begin
          lut_refill_enq_count_r[return_rd_cache_id][rd_cache_line_addr_hit_mshr_id] <= lut_refill_enq_count_r[return_rd_cache_id][rd_cache_line_addr_hit_mshr_id] + 1'b1;
        end
      end

      if (dram_write_done_i) begin
        if ((lut_evict_enq_count_r[return_wd_cache_id][wd_cache_line_addr_hit_index]==num_req_lp-1)) begin
          lut_evict_tag_v_r[return_wd_cache_id][wd_cache_line_addr_hit_index] <= 1'b0;
          lut_evict_enq_count_r[return_wd_cache_id][wd_cache_line_addr_hit_index] <= '0;
        end 
        else begin
          lut_evict_enq_count_r[return_wd_cache_id][wd_cache_line_addr_hit_index] <= lut_evict_enq_count_r[return_wd_cache_id][wd_cache_line_addr_hit_index] + 1'b1;
        end
      end
          
    end
  end

      


  // synopsys translate_off
  
  always_ff @ (negedge dram_clk_i) begin
    if (~dram_reset_i & dram_data_v_i) begin
      assert(rd_cache_line_addr_hit_found) else $fatal(1, "can't find matched mshr id in refill LUT!");
      assert($countones(rd_cache_line_addr_hit) <= 1) else $fatal(1, "there's no way you can find two matches in LUT at the same time!");
    end
    if (~dram_reset_i & dram_write_done_i) begin
      assert(wd_cache_line_addr_hit_found) else $fatal(1, "can't find matched mshr id in evict LUT!");
    end
  end

  // synopsys translate_on




endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_to_test_dram)
