`include "bsg_defines.v"
module cov_dma 
  #(parameter `BSG_INV_PARAM(block_size_in_bursts_p)
  )
  (
    input clk_i
    , input reset_i

    , input mshr_cam_r_v_o
    , input dma_refill_hold_i
    , input in_fifo_valid_li
    , input in_fifo_ready_lo
    , input [`BSG_WIDTH(block_size_in_bursts_p)-1:0] dma_refill_data_in_counter_r

    , input serve_read_miss_queue_v_o
    , input mgmt_v_i
    , input dma_refill_data_in_counter_max
    , input read_miss_queue_serve_v_i

    , input dma_refill_done
    , input transmitter_refill_done_r
  );

  wire dma_refill_data_in_counter_zero = dma_refill_data_in_counter_r==0;

  covergroup cg_dma_refill_done @ (negedge clk_i iff ~reset_i); 

    coverpoint dma_refill_done;
    coverpoint serve_read_miss_queue_v_o;
    coverpoint transmitter_refill_done_r;

    cross dma_refill_done, serve_read_miss_queue_v_o, transmitter_refill_done_r {
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
    coverpoint dma_refill_data_in_counter_zero;

    cross mshr_cam_r_v_o, dma_refill_hold_i, in_fifo_valid_li, dma_refill_data_in_counter_zero {
      ignore_bins v_o = 
        binsof(mshr_cam_r_v_o) intersect {1'b1};

      illegal_bins il4 = 
        binsof(mshr_cam_r_v_o) intersect {1'b0} &&
        binsof(dma_refill_hold_i) intersect {1'b0} &&
        binsof(in_fifo_valid_li) intersect {1'b1} &&
        binsof(dma_refill_data_in_counter_zero) intersect {1'b1};

      illegal_bins il5 = 
        binsof(dma_refill_hold_i) intersect {1'b1} &&
        binsof(in_fifo_valid_li) intersect {1'b1} &&
        binsof(dma_refill_data_in_counter_zero) intersect {1'b1};
    }

  endgroup


  initial begin
    cg_dma_refill_done cdrd = new;
    cg_serve_readq csr = new;
    cg_mshr_r_v cmrv = new;
  end


endmodule