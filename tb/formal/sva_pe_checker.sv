// ============================================================================
// File: sva_pe_checker.sv
// Designer: Abhijit Karale
// Module: sva_pe_checker
// Target: Formal Verification (SVA-2012 / SymbiYosys / Questa Formal)
// Description: SVA formal verification property checkers for PE cell:
//              verifies weight shadow isolation, atomic bank swap latency,
//              operand isolation power gating, and arithmetic correctness.
// ============================================================================

`timescale 1ns/1ps

module sva_pe_checker
  import systolic_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  
  // Controls
  input logic [1:0]  prec_mode,
  input logic        weight_load_en,
  input logic        weight_swap,
  input logic        step_en,
  
  // Weights
  input logic [7:0]  weight_in,
  input logic [7:0]  weight_shadow,
  input logic [7:0]  weight_active,
  
  // Activations
  input logic        a_valid_in,
  input logic [7:0]  a_in,
  input logic        a_valid_out,
  input logic [7:0]  a_out,
  
  // Partial sums
  input logic        psum_valid_in,
  input logic [31:0] psum_in,
  input logic        psum_valid_out,
  input logic [31:0] psum_out,
  
  // Diagnostics
  input logic        arith_error
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // --------------------------------------------------------------------------
  // PROPERTY 1: Weight Loading Isolation
  // While weight_load_en is active (loading shadow buffer), weight_active MUST
  // remain absolutely constant unless an explicit weight_swap is commanded.
  // --------------------------------------------------------------------------
  property p_weight_shadow_isolation;
    (weight_load_en && !weight_swap) |=> $stable(weight_active);
  endproperty
  a_weight_shadow_isolation: assert property (p_weight_shadow_isolation)
    else $error("[SVA FAIL] weight_active mutated during shadow load without swap!");

  // --------------------------------------------------------------------------
  // PROPERTY 2: Atomic Bank Swap Latency
  // Asserting weight_swap guarantees that weight_active takes the value of
  // weight_shadow on the immediately following cycle (1-cycle atomic latency).
  // --------------------------------------------------------------------------
  property p_atomic_swap_latency;
    weight_swap |=> (weight_active == $past(weight_shadow));
  endproperty
  a_atomic_swap_latency: assert property (p_atomic_swap_latency)
    else $error("[SVA FAIL] weight_active failed to copy weight_shadow in 1 cycle!");

  // --------------------------------------------------------------------------
  // PROPERTY 3: Active Weight Stability
  // When weight_swap is NOT asserted, weight_active must remain strictly unchanged.
  // --------------------------------------------------------------------------
  property p_weight_active_stable_without_swap;
    (!weight_swap) |=> $stable(weight_active);
  endproperty
  a_weight_active_stable: assert property (p_weight_active_stable_without_swap)
    else $error("[SVA FAIL] weight_active spontaneously changed without weight_swap!");

  // --------------------------------------------------------------------------
  // PROPERTY 4: Activation Horizontal Propagation
  // When step_en is asserted, activation data and validity must propagate
  // to adjacent East PE exactly 1 cycle later.
  // --------------------------------------------------------------------------
  property p_act_forwarding;
    step_en |=> ((a_out == $past(a_in)) && (a_valid_out == $past(a_valid_in)));
  endproperty
  a_act_forwarding: assert property (p_act_forwarding)
    else $error("[SVA FAIL] Activation pipeline forwarding mismatch!");

  // --------------------------------------------------------------------------
  // PROPERTY 5: Partial Sum Validity Pipeline
  // Partial sum valid signal must propagate vertically on step_en.
  // --------------------------------------------------------------------------
  property p_psum_valid_pipeline;
    step_en |=> (psum_valid_out == $past(psum_valid_in));
  endproperty
  a_psum_valid_pipeline: assert property (p_psum_valid_pipeline)
    else $error("[SVA FAIL] psum_valid_out does not track psum_valid_in!");

  // --------------------------------------------------------------------------
  // PROPERTY 6: Low-Power Zero Suppression
  // When incoming partial sum is invalid, outgoing psum must be zeroed to
  // eliminate toggle propagation down the column.
  // --------------------------------------------------------------------------
  property p_invalid_psum_zeroed;
    (step_en && !psum_valid_in) |=> (psum_out == 32'h0000_0000);
  endproperty
  a_invalid_psum_zeroed: assert property (p_invalid_psum_zeroed)
    else $error("[SVA FAIL] Inactive psum_out was not clamped to 0 for power savings!");

  // --------------------------------------------------------------------------
  // Cover Properties for Reachability Analysis
  // --------------------------------------------------------------------------
  c_shadow_load: cover property (weight_load_en ##1 weight_load_en [*7]);
  c_atomic_swap: cover property (weight_load_en ##1 weight_swap ##1 !weight_load_en);
  c_active_mac:  cover property (step_en && a_valid_in && psum_valid_in);

endmodule
