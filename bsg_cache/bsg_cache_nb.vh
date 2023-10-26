 // Enum values in the structs come from bsg_cache_pkg.v

`ifndef BSG_CACHE_NB_VH
`define BSG_CACHE_NB_VH
  // bsg_cache_nb_pkt_s
  //
  `define declare_bsg_cache_nb_pkt_s(addr_width_mp, word_width_mp, src_id_width_mp) \
    typedef struct packed {                                     \
      bsg_cache_nb_opcode_e opcode;                             \
      logic [addr_width_mp-1:0] addr;                           \
      logic [word_width_mp-1:0] data;                           \
      logic [(word_width_mp>>3)-1:0] mask;                      \
      logic [src_id_width_mp-1:0] src_id;                        \
    } bsg_cache_nb_pkt_s

  `define bsg_cache_nb_pkt_width(addr_width_mp, word_width_mp, src_id_width_mp) \
    ($bits(bsg_cache_nb_opcode_e)+addr_width_mp+word_width_mp+(word_width_mp>>3)+src_id_width_mp)

  // bsg_cache_nb_dma_pkt_s
  //
  `define declare_bsg_cache_nb_dma_pkt_s(addr_width_mp, mask_width_mp, mshr_els_mp) \
    typedef struct packed {                                         \
      logic write_not_read;                                         \
      logic [addr_width_mp-1:0] addr;                               \
      logic [mask_width_mp-1:0] mask;                               \
      logic [`BSG_SAFE_CLOG2(mshr_els_mp)-1:0] mshr_id;             \
    } bsg_cache_nb_dma_pkt_s

  `define bsg_cache_nb_dma_pkt_width(addr_width_mp, mask_width_mp, mshr_els_mp)     \
    (1+addr_width_mp+mask_width_mp+`BSG_SAFE_CLOG2(mshr_els_mp))

  // tag info s
  //
  `define declare_bsg_cache_nb_tag_info_s(tag_width_mp) \
    typedef struct packed {                   \
      logic valid;                            \
      logic lock;                             \
      logic [tag_width_mp-1:0] tag;           \
    } bsg_cache_nb_tag_info_s

  `define bsg_cache_nb_tag_info_width(tag_width_mp) (tag_width_mp+2)

  // stat info s
  //
  `define declare_bsg_cache_nb_stat_info_s(ways_mp)    \
    typedef struct packed {                         \
      logic [ways_mp-1:0] dirty;                    \
      logic [ways_mp-2:0] lru_bits;                 \
      logic [ways_mp-1:0] waiting_for_fill_data;    \
    } bsg_cache_nb_stat_info_s

  `define bsg_cache_nb_stat_info_width(ways_mp) \
    (ways_mp+ways_mp-1+ways_mp) 

  // sbuf entry s
  //
  `define declare_bsg_cache_nb_sbuf_entry_s(addr_width_mp, word_width_mp, ways_mp) \
    typedef struct packed {                       \
      logic [addr_width_mp-1:0] addr;             \
      logic [word_width_mp-1:0] data;             \
      logic [(word_width_mp>>3)-1:0] mask;        \
      logic [`BSG_SAFE_CLOG2(ways_mp)-1:0] way_id;\
    } bsg_cache_nb_sbuf_entry_s

  `define bsg_cache_nb_sbuf_entry_width(addr_width_mp, word_width_mp, ways_mp) \
    (addr_width_mp+word_width_mp+(word_width_mp>>3)+`BSG_SAFE_CLOG2(ways_mp))

  // evict fifo entry s
  //
  `define declare_bsg_cache_nb_evict_fifo_entry_s(ways_mp, sets_mp, mshr_els_mp) \
    typedef struct packed {                             \
      logic [`BSG_SAFE_CLOG2(ways_mp)-1:0] way;         \
      logic [`BSG_SAFE_CLOG2(sets_mp)-1:0] index;       \
      logic [`BSG_SAFE_CLOG2(mshr_els_mp)-1:0] mshr_id; \
    } bsg_cache_nb_evict_fifo_entry_s

  `define bsg_cache_nb_evict_fifo_entry_width(ways_mp, sets_mp, mshr_els_mp) \
    (`BSG_SAFE_CLOG2(ways_mp)+`BSG_SAFE_CLOG2(sets_mp)+`BSG_SAFE_CLOG2(mshr_els_mp))

  // store tag miss fifo entry s
  //
  `define declare_bsg_cache_nb_store_tag_miss_fifo_entry_s(ways_mp, sets_mp, mshr_els_mp, word_width_mp, block_size_in_words_mp) \
    typedef struct packed {                                              \
      logic [`BSG_SAFE_CLOG2(ways_mp)-1:0] way;                          \
      logic [`BSG_SAFE_CLOG2(sets_mp)-1:0] index;                        \
      logic [`BSG_SAFE_CLOG2(mshr_els_mp)-1:0] mshr_id;                  \
      logic [(block_size_in_words_mp*word_width_mp)-1:0] mshr_data;      \
      logic [((block_size_in_words_mp*word_width_mp)>>3)-1:0] mshr_mask; \
    } bsg_cache_nb_store_tag_miss_fifo_entry_s

  `define bsg_cache_nb_store_tag_miss_fifo_entry_width(ways_mp, sets_mp, mshr_els_mp, word_width_mp, block_size_in_words_mp) \
    (`BSG_SAFE_CLOG2(ways_mp)+`BSG_SAFE_CLOG2(sets_mp)+`BSG_SAFE_CLOG2(mshr_els_mp)+(block_size_in_words_mp*word_width_mp)+((block_size_in_words_mp*word_width_mp)>>3))


  // wormhole
  //
  `define declare_bsg_cache_nb_wh_header_flit_s(wh_flit_width_mp,wh_cord_width_mp,wh_len_width_mp,wh_cid_width_mp) \
    typedef struct packed { \
      logic [wh_flit_width_mp-(wh_cord_width_mp*2)-$bits(bsg_cache_wh_opcode_e)-wh_len_width_mp-(wh_cid_width_mp*2)-1:0] unused; \
      bsg_cache_wh_opcode_e opcode; \
      logic [wh_cid_width_mp-1:0] src_cid; \
      logic [wh_cord_width_mp-1:0] src_cord; \
      logic [wh_cid_width_mp-1:0] cid; \
      logic [wh_len_width_mp-1:0] len; \
      logic [wh_cord_width_mp-1:0] cord; \
    } bsg_cache_nb_wh_header_flit_s

`endif //  `ifndef BSG_CACHE_NB_VH
