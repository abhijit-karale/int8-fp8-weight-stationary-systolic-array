// ============================================================================
// File: systolic_coverage.sv
// Designer: Abhijit Karale
// Module: systolic_coverage
// Target: UVM 1.2 Verification Suite
// Description: Functional coverage collector tracking precision modes,
//              activation modes, cross coverage, and arithmetic corner cases.
// ============================================================================

`ifndef SYSTOLIC_COVERAGE_SV
`define SYSTOLIC_COVERAGE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

class systolic_coverage extends uvm_subscriber #(systolic_seq_item);
  `uvm_component_utils(systolic_coverage)

  systolic_seq_item cov_item;

  // --------------------------------------------------------------------------
  // Covergroup: Precision & Activation Configurations
  // --------------------------------------------------------------------------
  covergroup cg_config;
    option.per_instance = 1;
    option.name         = "cg_systolic_config";

    cp_prec_mode: coverpoint cov_item.prec_mode {
      bins b_int8     = {PREC_INT8};
      bins b_fp8_e4m3 = {PREC_FP8_E4M3};
      bins b_fp8_e5m2 = {PREC_FP8_E5M2};
    }

    cp_act_mode: coverpoint cov_item.act_mode {
      bins b_bypass     = {ACT_BYPASS};
      bins b_relu       = {ACT_RELU};
      bins b_leaky_relu = {ACT_LEAKY_RELU};
      bins b_clip       = {ACT_CLIP};
    }

    cp_delay: coverpoint cov_item.inter_beat_delay {
      bins b_zero_delay = {0};
      bins b_short_delay = {[1:2]};
    }

    // Comprehensive Cross Coverage
    cross_prec_act: cross cp_prec_mode, cp_act_mode;

  endgroup

  function new(string name = "systolic_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_config = new();
  endfunction

  virtual function void write(systolic_seq_item t);
    cov_item = t;
    cg_config.sample();
  endfunction

endclass : systolic_coverage

`endif // SYSTOLIC_COVERAGE_SV
