// ============================================================================
// File: sva_systolic_top.sv
// Designer: Abhijit Karale
// Module: sva_systolic_top
// Target: Formal Verification (SVA-2012 / SymbiYosys / Questa Formal)
// Description: System-level SVA formal property checkers for the 8x8 Systolic
//              Array top level: verifies calculation latency determinism,
//              streaming handshake safety, and output vector synchronization.
// ============================================================================

`timescale 1ns/1ps

module sva_systolic_top
  import systolic_pkg::*;
(
  input logic                        clk,
  input logic                        rst_n,
  input logic                        step_en,
  
  // Configuration
  input logic [1:0]                  cfg_prec_mode,
  input logic [1:0]                  cfg_act_mode,
  input logic                        weight_swap_cmd,
  
  // Weight Stream Slave
  input logic                        s_axis_weight_tvalid,
  input logic                        s_axis_weight_tready,
  input logic [WT_BUS_WIDTH-1:0]     s_axis_weight_tdata,
  input logic                        s_axis_weight_tlast,
  
  // Activation Stream Slave
  input logic                        s_axis_act_tvalid,
  input logic                        s_axis_act_tready,
  input logic [ACT_BUS_WIDTH-1:0]    s_axis_act_tdata,
  input logic                        s_axis_act_tlast,
  
  // Output Stream Master
  input logic                        m_axis_out_tvalid,
  input logic                        m_axis_out_tready,
  input logic [OUT_RAW_WIDTH-1:0]    m_axis_raw_tdata,
  input logic [OUT_QUANT_WIDTH-1:0]  m_axis_quant_tdata,
  input logic                        m_axis_out_tlast,
  
  // Diagnostics
  input logic                        status_shadow_ready,
  input logic                        status_busy,
  input logic                        status_arith_error
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // --------------------------------------------------------------------------
  // PROPERTY 1: AXI-Stream Protocol Stability
  // When m_axis_out_tvalid is asserted without ready, data must remain stable.
  // --------------------------------------------------------------------------
  property p_axis_master_stable;
    (m_axis_out_tvalid && !m_axis_out_tready) |=> 
      (m_axis_out_tvalid && 
       $stable(m_axis_raw_tdata) && 
       $stable(m_axis_quant_tdata) && 
       $stable(m_axis_out_tlast));
  endproperty
  a_axis_master_stable: assert property (p_axis_master_stable)
    else $error("[SVA FAIL] m_axis master output mutated while waiting for ready!");

  // --------------------------------------------------------------------------
  // PROPERTY 2: Weight Preload Ready Determinism
  // After exactly 8 valid weight shift beats, status_shadow_ready MUST be high.
  // --------------------------------------------------------------------------
  sequence seq_8_weight_beats;
    (s_axis_weight_tvalid && s_axis_weight_tready) [*8];
  endsequence

  property p_weight_preloaded;
    seq_8_weight_beats |=> status_shadow_ready;
  endproperty
  a_weight_preloaded: assert property (p_weight_preloaded)
    else $error("[SVA FAIL] status_shadow_ready was not asserted after 8 weight beats!");

  // --------------------------------------------------------------------------
  // PROPERTY 3: Deterministic Systolic Array Pipeline Latency
  // Given continuous step_en, an activation pulse at s_axis_act_tvalid reaches
  // m_axis_out_tvalid with deterministic cycle latency of 16 cycles.
  // (1 cycle PE00 + 7 cycles vertical cascade + 7 cycles deskew + 1 cycle activation)
  // --------------------------------------------------------------------------
  property p_deterministic_latency;
    (step_en && $rose(s_axis_act_tvalid)) |-> ##16 (m_axis_out_tvalid);
  endproperty
  a_deterministic_latency: assert property (p_deterministic_latency)
    else $error("[SVA FAIL] Systolic array pipeline output latency violation (expected 16 cycles)!");

  // --------------------------------------------------------------------------
  // PROPERTY 4: Shadow-to-Active Swap Isolation
  // Asserting weight_swap_cmd when shadow is ready clears shadow_ready on next cycle.
  // --------------------------------------------------------------------------
  property p_swap_clears_shadow;
    (status_shadow_ready && weight_swap_cmd) |=> !status_shadow_ready;
  endproperty
  a_swap_clears_shadow: assert property (p_swap_clears_shadow)
    else $error("[SVA FAIL] status_shadow_ready was not cleared after swap!");

  // --------------------------------------------------------------------------
  // Cover Properties for Verification Closure
  // --------------------------------------------------------------------------
  c_complete_matrix_multiply: cover property (
    s_axis_act_tvalid [*8] ##[8:24] (m_axis_out_tvalid && m_axis_out_tlast)
  );

  c_continuous_double_buffering: cover property (
    // Preloading weights concurrently while output stream is active
    m_axis_out_tvalid && s_axis_weight_tvalid && s_axis_weight_tready
  );

endmodule
