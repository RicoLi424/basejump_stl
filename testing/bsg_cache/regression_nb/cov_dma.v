module cov_dma 
  #(parameter `BSG_INV_PARAM(dma_data_width_p)
    ,parameter `BSG_INV_PARAM(word_width_p)
    ,parameter `BSG_INV_PARAM(block_size_in_words_p)
    ,parameter num_of_burst_lp=(block_size_in_words_p*word_width_p/dma_data_width_p)
    ,parameter counter_width_lp=`BSG_SAFE_CLOG2(num_of_burst_lp+1);
  )
  (
    input clk_i
    , input reset_i

    , input mshr_cam_r_v_o
    , input dma_refill_hold_i
    , input in_fifo_valid_li
    , input in_fifo_ready_lo
    , input [counter_width_lp-1:0] dma_refill_data_in_counter_r

    , input serve_read_miss_queue_v_o
    , input mgmt_v_i
    , input dma_refill_data_in_counter_max
    , input read_miss_queue_serve_v_i

    , input dma_refill_done
    , input transmitter_refill_done_r
  )


  covergroup cg_dma_refill_done @ (negedge clk_i iff ~reset_i);  

    coverpoint dma_refill_done;
    coverpoint serve_read_miss_queue_v_o;
    coverpoint transmitter_refill_done_r;

    cross serve_read_miss_queue_v_o, transmitter_refill_done_r {
      illegal_bins il0 = 
        binsof(dma_refill_done) intersect {1'b0} &&
        binsof(serve_read_miss_queue_v_o) intersect {1'b0} &&
        binsof(transmitter_refill_done_r) intersect {1'b1};

      ignore_bins refill_done = 
        binsof(dma_refill_done) intersect {1'b1};
    }

  endgroup


  covergroup cg_serve_readq @ (negedge clk_i iff ~reset_i);  

    coverpoint serve_read_miss_queue_v_o;
    coverpoint mgmt_v_i;
    coverpoint dma_refill_data_in_counter_max;
    coverpoint read_miss_queue_serve_v_i;

    cross serve_read_miss_queue_v_o, mgmt_v_i, dma_refill_data_in_counter_max, read_miss_queue_serve_v_i {
      ignore_bins v_o = 
        binsof(serve_read_miss_queue_v_o) intersect {1'b1};

      illegal_bins il1 = 
        binsof(mgmt_v_i) intersect {1'b1} &&
        binsof(read_miss_queue_serve_v_i) intersect {1'b1};

      illegal_bins il2 = 
        binsof(serve_read_miss_queue_v_o) intersect {1'b0} &&
        binsof(mgmt_v_i) intersect {1'b0} &&
        binsof(dma_refill_data_in_counter_max) intersect {1'b1} &&
        binsof(read_miss_queue_serve_v_i) intersect {1'b1};   
    }

  endgroup


  covergroup cg_mshr_r_v @ (negedge clk_i iff ~reset_i);  

    coverpoint mshr_cam_r_v_o;
    coverpoint dma_refill_hold_i;
    coverpoint in_fifo_valid_li;
    coverpoint in_fifo_ready_lo;
    coverpoint dma_refill_data_in_counter_r {
      bins zero = {0};
      bins nz = {[(1 << counter_width_lp) - 1:1]};
    }

    cross mshr_cam_r_v_o, dma_refill_hold_i, in_fifo_valid_li, in_fifo_ready_lo, dma_refill_data_in_counter_r {
      ignore_bins v_o = 
        binsof(mshr_cam_r_v_o) intersect {1'b1};

      ignore_bins n_ready = 
        binsof(mshr_cam_r_v_o) intersect {1'b0} &&
        binsof(in_fifo_ready_lo) intersect {1'b0};

      ignore_bins full_and_v_i = 
        binsof(dma_refill_data_in_counter_r) intersect {nz} &&
        binsof(in_fifo_valid_li) intersect {1'b1};

      illegal_bins il4 = 
        binsof(mshr_cam_r_v_o) intersect {1'b0} &&
        binsof(dma_refill_hold_i) intersect {1'b0} &&
        binsof(in_fifo_valid_li) intersect {1'b1} &&
        binsof(in_fifo_ready_lo) intersect {1'b1} &&
        binsof(dma_refill_data_in_counter_r) intersect {zero};
    }

  endgroup


  initial begin
    cg_dma_refill_done cdrd = new;
    cg_serve_readq csr = new;
    cg_mshr_r_v cmrv = new;
  end


endmodule