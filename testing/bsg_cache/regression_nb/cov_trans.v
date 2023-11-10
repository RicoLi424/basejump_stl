
module cov_trans
  (

    input clk_i
    , input reset_i

    , input refill_in_progress_o
    , input evict_in_progress_o
    , input store_tag_miss_fill_in_progress_o

    , input even_fifo_priority_o
    , input odd_fifo_priority_o

    , input dma_refill_v_i
    , input dma_refill_ready_o
    , input dma_evict_v_o
    , input dma_evict_yumi_i
    
    , input even_bank_v_i
    , input odd_bank_v_i

    , input even_bank_v_o
    , input even_bank_w_o
    , input odd_bank_v_o
    , input odd_bank_w_o

    , input track_miss_i

    , input evict_we_i
    , input refill_we_i
    , input store_tag_miss_we_i

  );


  covergroup cg_curr_mode @ (negedge clk_i iff ~reset_i);

    coverpoint refill_in_progress_o;
    coverpoint evict_in_progress_o;
    coverpoint store_tag_miss_fill_in_progress_o {
      bins zero = {1'b0};
      illegal_bins one = {1'b1};
    }

    cross refill_in_progress_o, evict_in_progress_o, store_tag_miss_fill_in_progress_o {
      illegal_bins both_one = 
        binsof(refill_in_progress_o) intersect {1'b1} && 
        binsof(evict_in_progress_o) intersect {1'b1};
    }

  endgroup

  
  covergroup cg_mode_we @ (negedge clk_i iff ~reset_i);
  
    coverpoint evict_we_i;
    coverpoint refill_we_i;
    coverpoint store_tag_miss_we_i {
      bins zero = {1'b0};
      illegal_bins one = {1'b1};
    }
    coverpoint track_miss_i {
      bins z = {1'b0};
      illegal_bins o = {1'b1};
    }

    cross evict_we_i, refill_we_i, store_tag_miss_we_i, track_miss_i {
      illegal_bins evict_refill = 
        binsof(evict_we_i) intersect {1'b1} && 
        binsof(refill_we_i) intersect {1'b1};
    }

  endgroup


  covergroup cg_even_odd_priority @ (negedge clk_i);

    coverpoint even_fifo_priority_o;
    coverpoint odd_fifo_priority_o;

    cross even_fifo_priority_o, odd_fifo_priority_o {
      illegal_bins two_priorities = 
        binsof(even_fifo_priority_o) intersect {1'b1} && 
        binsof(odd_fifo_priority_o) intersect {1'b1};
    }
    
  endgroup


  covergroup cg_dma_evict_refill @ (negedge clk_i);
    
    coverpoint dma_refill_v_i;
    coverpoint dma_refill_ready_o;
    coverpoint dma_evict_v_o;
    coverpoint dma_evict_yumi_i;

    cross dma_refill_v_i, dma_refill_ready_o, dma_evict_v_o, dma_evict_yumi_i {
      illegal_bins dma_evict_refill = 
        binsof(dma_refill_ready_o) intersect {1'b1} && 
        (binsof(dma_evict_v_o) intersect {1'b1} ||
         binsof(dma_evict_yumi_i) intersect {1'b1});

      ignore_bins n_evict_v = 
        binsof(dma_evict_v_o) intersect {1'b0} &&
        binsof(dma_evict_yumi_i) intersect {1'b1};

      // Current design will have always finished sending all the data out of fifo
      // before next round of data is ready on transmitter side
      ignore_bins n_evict_yumi =
        binsof(dma_evict_v_o) intersect {1'b1} &&
        binsof(dma_evict_yumi_i) intersect {1'b0};
    }

  endgroup


  covergroup cg_bank @ (negedge clk_i iff ~reset_i );

    coverpoint even_bank_v_i;
    coverpoint odd_bank_v_i;
    coverpoint even_bank_v_o;
    coverpoint even_bank_w_o;
    coverpoint odd_bank_v_o;
    coverpoint odd_bank_w_o;

    cross even_bank_v_i, odd_bank_v_i;
    cross even_bank_v_o, even_bank_w_o, odd_bank_v_o, odd_bank_w_o {
      illegal_bins write_read = 
        (binsof(even_bank_w_o) intersect {1'b1} && 
        binsof(odd_bank_w_o) intersect {1'b0}) ||
        (binsof(odd_bank_w_o) intersect {1'b1} && 
        binsof(even_bank_w_o) intersect {1'b0});
    }

  endgroup

  initial begin
    cg_curr_mode ccm = new;
    cg_mode_we cmw = new;
    cg_even_odd_priority ceop = new;
    cg_dma_evict_refill cder = new;
    cg_bank cb = new;
  end

endmodule
