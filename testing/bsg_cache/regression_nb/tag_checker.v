
`include "bsg_cache_nb.vh"

module tag_checker 
  import bsg_cache_nb_pkg::*;
  #(parameter `BSG_INV_PARAM(src_id_width_p)
    , parameter `BSG_INV_PARAM(word_width_p)
    , parameter `BSG_INV_PARAM(addr_width_p)
    , parameter `BSG_INV_PARAM(ways_p)
    , parameter `BSG_INV_PARAM(sets_p)
    , parameter `BSG_INV_PARAM(tag_width_lp)
    , parameter `BSG_INV_PARAM(block_size_in_words_p)

    , parameter block_offset_width_lp=`BSG_SAFE_CLOG2(word_width_p>>3)+`BSG_SAFE_CLOG2(block_size_in_words_p)
    , parameter lg_ways_lp=`BSG_SAFE_CLOG2(ways_p)
    , parameter lg_sets_lp=`BSG_SAFE_CLOG2(sets_p)

    , parameter bsg_cache_nb_pkt_width_lp=`bsg_cache_nb_pkt_width(addr_width_p,word_width_p,src_id_width_p)
  )
  (
    input clk_i
    , input reset_i

    , input en_i

    , input v_i
    , input yumi_o
    , input [bsg_cache_nb_pkt_width_lp-1:0] cache_pkt_i

    , input v_o
    , input yumi_i
    , input [word_width_p-1:0] data_o
    , input [src_id_width_p:0] src_id_o
  );


  `declare_bsg_cache_nb_pkt_s(addr_width_p,word_width_p,src_id_width_p);
  bsg_cache_nb_pkt_s cache_pkt;
  assign cache_pkt = cache_pkt_i;


  `declare_bsg_cache_nb_tag_info_s(tag_width_lp);
  bsg_cache_nb_tag_info_s [ways_p-1:0][sets_p-1:0] shadow_tag;
  logic [word_width_p-1:0] result [*]; // indexed by id.

  wire [lg_ways_lp-1:0] addr_way = cache_pkt.addr[block_offset_width_lp+lg_sets_lp+:lg_ways_lp];
  wire [lg_sets_lp-1:0] addr_index = cache_pkt.addr[block_offset_width_lp+:lg_sets_lp];




  always_ff @ (posedge clk_i) begin
    if (reset_i) begin

      for (integer i = 0; i < ways_p; i++)
        for (integer j = 0; j < ways_p; j++)
          shadow_tag[i][j] <= '0;

    end
    else begin 
      if (v_i & yumi_o & en_i) begin
        case (cache_pkt.opcode)

          TAGST: begin
            result[cache_pkt.src_id] = '0;
            shadow_tag[addr_way][addr_index].tag <= cache_pkt.data[0+:tag_width_lp];
            shadow_tag[addr_way][addr_index].valid <= cache_pkt.data[word_width_p-1];
            shadow_tag[addr_way][addr_index].lock <= cache_pkt.data[word_width_p-2];
          end

          TAGLV: begin
            result[cache_pkt.src_id] = '0;
            result[cache_pkt.src_id][1] = shadow_tag[addr_way][addr_index].lock;
            result[cache_pkt.src_id][0] = shadow_tag[addr_way][addr_index].valid;
          end
      
          TAGLA: begin
            result[cache_pkt.src_id] = {
              shadow_tag[addr_way][addr_index].tag,
              addr_index,
              {block_offset_width_lp{1'b0}}
            };
          end

        endcase
      end
    end


    if (~reset_i & v_o & src_id_o[src_id_width_p] & yumi_i & en_i) begin
      $display("src_id_o=%d, data_o=%x", src_id_o[0+:src_id_width_p], data_o);
      assert(result[src_id_o[0+:src_id_width_p]] == data_o)
        else $fatal(1, "[BSG_FATAL] Output does not match expected result. Id= %d, Expected: %x. Actual: %x",
              src_id_o[0+:src_id_width_p], result[src_id_o[0+:src_id_width_p]], data_o);
    end

  end
endmodule

`BSG_ABSTRACT_MODULE(tag_checker)
