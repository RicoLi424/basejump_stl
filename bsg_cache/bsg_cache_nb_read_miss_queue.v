/*
 * Non blocking cache Read Miss Queue
 */

`include "bsg_defines.v"

module bsg_cache_nb_read_miss_queue
 #(parameter `BSG_INV_PARAM(block_size_in_words_p)
   , parameter `BSG_INV_PARAM(word_width_p)
   , parameter `BSG_INV_PARAM(src_id_width_p)
   , parameter `BSG_INV_PARAM(mshr_els_p)
   , parameter `BSG_INV_PARAM(read_miss_els_per_mshr_p)

   , parameter lg_block_size_in_words_lp=`BSG_SAFE_CLOG2(block_size_in_words_p) 
   , parameter data_mask_width_lp = word_width_p>>3
   , parameter byte_sel_width_lp=`BSG_SAFE_CLOG2(data_mask_width_lp)

   , parameter lg_mshr_els_lp = `BSG_SAFE_CLOG2(mshr_els_p)
   , parameter lg_read_miss_els_per_mshr_lp = `BSG_SAFE_CLOG2(read_miss_els_per_mshr_p)
   
   , parameter safe_mshr_els_lp = `BSG_MAX(mshr_els_p,1)
   , parameter safe_read_miss_els_per_mshr_lp = `BSG_MAX(read_miss_els_per_mshr_p,1)
   , parameter total_els_p = safe_mshr_els_lp*safe_read_miss_els_per_mshr_lp

   , parameter lg_total_els_lp = `BSG_SAFE_CLOG2(total_els_p)
   , parameter mem_width_lp = src_id_width_p+lg_block_size_in_words_lp+byte_sel_width_lp+data_mask_width_lp+word_width_p+data_mask_width_lp+2+1+1
   )
  (input clk_i
   , input reset_i

   , input [lg_mshr_els_lp-1:0] mshr_id_i
   // For read, v_i should be set to 0 right after read_done_o[i] is set to 1
   , input v_i
   , output logic [`BSG_SAFE_MINUS(mshr_els_p, 1):0] ready_o
   , input write_not_read_i

   , input [`BSG_SAFE_MINUS(src_id_width_p, 1):0] src_id_i
   , input [lg_block_size_in_words_lp-1:0] word_offset_i
   , input mask_op_i
   , input [data_mask_width_lp-1:0] mask_i
   , input [1:0] size_op_i // 0: 1B, 1: 2B, 2: 4B, 3: 8B
   , input sigext_op_i
   , input [byte_sel_width_lp-1:0] byte_sel_i
   // This is for cases where some of the bytes that you want to 
   // read are valid in MSHR entry's data storage, but the others are not
   // So we have to keep these valid words and combine them with the fetched 
   // data when we serve the read miss queue
   , input [word_width_p-1:0] mshr_data_i
   , input [data_mask_width_lp-1:0] mshr_data_mask_i

   
   , output logic [`BSG_SAFE_MINUS(src_id_width_p, 1):0] src_id_o
   , output logic [lg_block_size_in_words_lp-1:0] word_offset_o
   , output logic mask_op_o
   , output logic [data_mask_width_lp-1:0] mask_o
   , output logic [1:0] size_op_o
   , output logic sigext_op_o
   , output logic [byte_sel_width_lp-1:0] byte_sel_o
   , output logic [word_width_p-1:0] mshr_data_o
   , output logic [data_mask_width_lp-1:0] mshr_data_mask_o

   // user should not IDLE reading if v_o[i] is 0  
   , output logic [`BSG_SAFE_MINUS(mshr_els_p, 1):0] v_o
   , input yumi_i

   , output logic read_done_o
   , output logic read_in_progress_o
   );  

  // Write pointer, it always points to the next empty read miss entry
  // It can get to 'read_miss_els_per_mshr_p', at which point it means this MSHR Read Miss Field is full
  // If it is full, it will not be able to accept any more read misses, 
  // and any following read misses in this field will cause the pipeline to be stalled
  // If it is 0, then no read miss has been allocated yet, we don't need to serve any read miss  
  // Write pointer will be set back to 0 when all the read misses in this field are served
  logic [safe_mshr_els_lp-1:0][`BSG_WIDTH(read_miss_els_per_mshr_p)-1:0] w_counter_r;

  // Read pointer, it always points to the next read miss entry to be read
  // It can get to 'w_counter_r'-1, at which point it means all the read misses will have been served when yumi_i comes
  // And read_done_o will be set to 1 right away after that
  // Read pointer will be set back to 0 when all the read misses in this field are served, along with write counter
  logic [safe_mshr_els_lp-1:0][`BSG_WIDTH(read_miss_els_per_mshr_p)-1:0] r_counter_r;
  logic r_counter_en_li;
  logic read_mem_v_li, read_mem_v_r;
  logic [`BSG_SAFE_MINUS(src_id_width_p, 1):0] src_id_r, src_id_lo;
  logic [lg_block_size_in_words_lp-1:0] word_offset_r, word_offset_lo;
  logic mask_op_r, mask_op_lo;
  logic [data_mask_width_lp-1:0] mask_r, mask_lo;
  logic [1:0] size_op_r, size_op_lo;
  logic sigext_op_r, sigext_op_lo;
  logic [byte_sel_width_lp-1:0] byte_sel_r, byte_sel_lo;
  logic [word_width_p-1:0] mshr_data_r, mshr_data_lo;
  logic [data_mask_width_lp-1:0] mshr_data_mask_r, mshr_data_mask_lo;  
  
  logic [lg_total_els_lp-1:0] mem_addr_li;
  assign mem_addr_li = mshr_id_i * safe_read_miss_els_per_mshr_lp
                       + (write_not_read_i ? w_counter_r[mshr_id_i][0+:lg_read_miss_els_per_mshr_lp] 
                         : r_counter_r[mshr_id_i][0+:lg_read_miss_els_per_mshr_lp]);


  logic [lg_mshr_els_lp-1:0] mshr_id_r;

  bsg_dff_reset_en_bypass #(
    .width_p(lg_mshr_els_lp)
  ) transmitter_refill_done_dff_bypass (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.en_i(v_i & ~write_not_read_i)
    ,.data_i(mshr_id_i)
    ,.data_o(mshr_id_r)
  );

  for(genvar i=0; i<safe_mshr_els_lp; i++) 
    begin : counter

      bsg_counter_set_en #(
        .max_val_p(safe_read_miss_els_per_mshr_lp)
      ) w_counter (
        .clk_i(clk_i)
        ,.reset_i(reset_i)
        ,.set_i((mshr_id_r==i) & read_done_o)
        ,.en_i(v_i & write_not_read_i & (mshr_id_i==i))
        ,.val_i('0)
        ,.count_o(w_counter_r[i])
      );

      bsg_counter_set_en #(
        .max_val_p(safe_read_miss_els_per_mshr_lp)
      ) r_counter (
        .clk_i(clk_i)
        ,.reset_i(reset_i)
        ,.set_i((mshr_id_r==i) & read_done_o)
        ,.en_i((mshr_id_r==i) & r_counter_en_li)
        ,.val_i('0)
        ,.count_o(r_counter_r[i])
      );

      assign ready_o[i] = ~(w_counter_r[i] == safe_read_miss_els_per_mshr_lp);
      assign v_o[i] = (w_counter_r[i]!=0);
    end 


  logic [`BSG_WIDTH(read_miss_els_per_mshr_p)-1:0] target_r_counter;
  logic [`BSG_WIDTH(read_miss_els_per_mshr_p)-1:0] target_w_counter;

  bsg_mux #(
    .width_p(`BSG_WIDTH(read_miss_els_per_mshr_p))
    ,.els_p(safe_mshr_els_lp)
  ) r_counter_mux (
    .data_i(r_counter_r)
    ,.sel_i(mshr_id_r)
    ,.data_o(target_r_counter)
  );

  bsg_mux #(
    .width_p(`BSG_WIDTH(read_miss_els_per_mshr_p))
    ,.els_p(safe_mshr_els_lp)
  ) w_counter_mux (
    .data_i(w_counter_r)
    ,.sel_i(mshr_id_r)
    ,.data_o(target_w_counter)
  );

  typedef enum logic {
    IDLE
    ,SERVE
  } serve_state_e;

  serve_state_e serve_state_r;
  serve_state_e serve_state_n;

  always_comb begin

    r_counter_en_li = 1'b0;
    read_done_o = 1'b0;
    read_in_progress_o = 1'b0;
    read_mem_v_li = 1'b1;
    serve_state_n = serve_state_r;

    case (serve_state_r)
      IDLE: begin
        serve_state_n = (v_i & ~write_not_read_i)
                      ? SERVE
                      : IDLE;
        r_counter_en_li = (v_i & ~write_not_read_i);
      end

      SERVE: begin
        read_in_progress_o = 1'b1;
        read_done_o = (target_r_counter == target_w_counter) & yumi_i;
        r_counter_en_li = yumi_i;
        read_mem_v_li = yumi_i & ~read_done_o;
        serve_state_n = (read_done_o) ? IDLE : SERVE;
      end

      // this should never happen, but if it does, go back to IDLE;
      default: begin
        serve_state_n = IDLE;
      end

    endcase
  end

  always_ff @ (posedge clk_i) begin
    if (reset_i) begin
      serve_state_r <= IDLE;
      read_mem_v_r <= 1'b0;
      {src_id_r,
      word_offset_r,
      byte_sel_r,
      mask_r,
      mshr_data_r,
      mshr_data_mask_r,
      size_op_r,
      sigext_op_r,
      mask_op_r} <= '0;
    end else begin
      serve_state_r <= serve_state_n;
      read_mem_v_r <= ~write_not_read_i & read_mem_v_li;
      if(read_mem_v_r) begin 
        {src_id_r,
        word_offset_r,
        byte_sel_r,
        mask_r,
        mshr_data_r,
        mshr_data_mask_r,
        size_op_r,
        sigext_op_r,
        mask_op_r} <= {src_id_lo,
                      word_offset_lo,
                      byte_sel_lo,
                      mask_lo,
                      mshr_data_lo,
                      mshr_data_mask_lo,
                      size_op_lo,
                      sigext_op_lo,
                      mask_op_lo};
      end
    end
  end

  if (total_els_p == 0)
    begin : zero
      assign ready_o = '0;
      assign v_o = '0;
      assign read_done_o = 1'b0;
      assign read_in_progress_o = 1'b0;
      assign src_id_o = '0;
      assign word_offset_o = '0;
      assign byte_sel_o = '0;
      assign mask_o = '0;
      assign size_op_o = 1'b0;
      assign mask_op_o = 1'b0;
      assign sigext_op_o = 1'b0;
    end
  else
    begin : nz
      bsg_mem_1rw_sync #(
        .width_p(mem_width_lp)
        ,.els_p(total_els_p)
      ) read_miss_mem (
        .clk_i(clk_i)
        ,.reset_i(reset_i)
        ,.data_i({src_id_i,word_offset_i,byte_sel_i,mask_i,mshr_data_i,mshr_data_mask_i,size_op_i,sigext_op_i,mask_op_i})
        ,.addr_i(mem_addr_li)
        ,.v_i(write_not_read_i ? v_i : read_mem_v_li)
        ,.w_i(write_not_read_i)
        ,.data_o({src_id_lo,word_offset_lo,byte_sel_lo,mask_lo,mshr_data_lo,mshr_data_mask_lo,size_op_lo,sigext_op_lo,mask_op_lo})
      );
    end

  assign {src_id_o, word_offset_o, byte_sel_o, mask_o, mshr_data_o, mshr_data_mask_o, size_op_o, sigext_op_o, mask_op_o} = 
         read_mem_v_r 
         ? {src_id_lo, word_offset_lo, byte_sel_lo, mask_lo, mshr_data_lo, mshr_data_mask_lo, size_op_lo, sigext_op_lo, mask_op_lo}
         : {src_id_r, word_offset_r, byte_sel_r, mask_r, mshr_data_r, mshr_data_mask_r, size_op_r, sigext_op_r, mask_op_r};


  //synopsys translate_off
  // always_ff @(negedge clk_i) begin
  //   // $display("read_done_o:%d, target_r_counter:%d, target_w_counter:%d, yumi_i:%d, serve_state_n:%d, serve_state_r:%d, write_not_read_i:%d", 
  //             // read_done_o, target_r_counter, target_w_counter, yumi_i, serve_state_n, serve_state_r, write_not_read_i);
  //   assert(reset_i || ~v_i || write_not_read_i || v_o[mshr_id_i])
  //     else $error("No entries in read miss field %d while a read opeartion is being tried", mshr_id_i);      	
  // end 
  //synopsys translate_on

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_nb_read_miss_queue)
