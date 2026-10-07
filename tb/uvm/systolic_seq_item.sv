// ============================================================================
// File: systolic_seq_item.sv
// Designer: Abhijit Karale
// Module: systolic_seq_item
// Target: UVM 1.2 Verification Suite
// Description: UVM sequence item modeling an 8x8 matrix multiplication
//              transaction with configurable precision, activations, and weights.
// ============================================================================

`ifndef SYSTOLIC_SEQ_ITEM_SV
`define SYSTOLIC_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

class systolic_seq_item extends uvm_sequence_item;

  // --------------------------------------------------------------------------
  // Randomizable Transaction Fields
  // --------------------------------------------------------------------------
  rand prec_mode_e            prec_mode;
  rand act_mode_e             act_mode;
  rand bit [7:0]              weights [ARRAY_ROWS][ARRAY_COLS];
  rand bit [7:0]              activations [ARRAY_ROWS][ARRAY_ROWS];
  rand int unsigned           inter_beat_delay; // Delay cycles between activation beats
  rand bit                    seed_enable;
  rand bit signed [31:0]      seed_values [ARRAY_COLS];

  // --------------------------------------------------------------------------
  // Output and Scoreboard Fields
  // --------------------------------------------------------------------------
  bit signed [31:0]           actual_raw [ARRAY_ROWS][ARRAY_COLS];
  bit [7:0]                   actual_quant [ARRAY_ROWS][ARRAY_COLS];
  bit signed [31:0]           expected_raw [ARRAY_ROWS][ARRAY_COLS];
  bit [7:0]                   expected_quant [ARRAY_ROWS][ARRAY_COLS];
  bit                         arith_error_observed;

  // --------------------------------------------------------------------------
  // Constraints
  // --------------------------------------------------------------------------
  constraint c_prec_mode_valid {
    prec_mode inside {PREC_INT8, PREC_FP8_E4M3, PREC_FP8_E5M2};
  }

  constraint c_act_mode_valid {
    act_mode inside {ACT_BYPASS, ACT_RELU, ACT_LEAKY_RELU, ACT_CLIP};
  }

  constraint c_inter_beat_delay {
    inter_beat_delay inside {[0:2]};
  }

  constraint c_seed_default {
    seed_enable == 1'b0; // Default zero seed for standard GEMM
  }

  // UVM Object Utilities Macro
  `uvm_object_utils_begin(systolic_seq_item)
    `uvm_field_enum(prec_mode_e, prec_mode, UVM_ALL_ON)
    `uvm_field_enum(act_mode_e, act_mode, UVM_ALL_ON)
    `uvm_field_int(inter_beat_delay, UVM_ALL_ON)
    `uvm_field_int(seed_enable, UVM_ALL_ON)
    `uvm_field_int(arith_error_observed, UVM_ALL_ON)
  `uvm_object_utils_end

  // Constructor
  function new(string name = "systolic_seq_item");
    super.new(name);
  endfunction

  // Custom String Formatting for Clean Reporting
  virtual function string convert2string();
    string s = "";
    s = $sformatf("\n[Systolic Sequence Item] Prec: %s | Act: %s | Delay: %0d", 
                  prec_mode.name(), act_mode.name(), inter_beat_delay);
    return s;
  endfunction

endclass : systolic_seq_item

`endif // SYSTOLIC_SEQ_ITEM_SV
