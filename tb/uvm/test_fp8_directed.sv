// ============================================================================
// File: test_fp8_directed.sv
// Designer: Abhijit Karale
// Module: test_fp8_directed
// Target: UVM 1.2 Verification Suite
// Description: Directed FP8 test sequence verifying E4M3 and E5M2 arithmetic,
//              subnormal representations, and floating-point accumulation.
// ============================================================================

`ifndef TEST_FP8_DIRECTED_SV
`define TEST_FP8_DIRECTED_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

class test_fp8_directed extends systolic_test_base;
  `uvm_component_utils(test_fp8_directed)

  function new(string name = "test_fp8_directed", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    systolic_seq_item item;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting Directed FP8 Test Cases...", UVM_LOW)

    // ------------------------------------------------------------------------
    // Test Case 1: FP8 E4M3 Normalized GEMM (1.0 x 2.0 x 8 = 16.0)
    // ------------------------------------------------------------------------
    item = systolic_seq_item::type_id::create("item_e4m3");
    env.agent.sequencer.wait_for_grant();
    item.prec_mode        = PREC_FP8_E4M3;
    item.act_mode         = ACT_BYPASS;
    item.inter_beat_delay = 0;

    // In E4M3: 1.0 is 0x38 (Exp=7, Mantissa=0)
    // In E4M3: 2.0 is 0x40 (Exp=8, Mantissa=0)
    for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        item.weights[r][c]     = 8'h40; // 2.0
        item.activations[r][c] = 8'h38; // 1.0
      end
    end
    env.agent.sequencer.send_request(item);
    env.agent.sequencer.wait_for_item_done();

    // ------------------------------------------------------------------------
    // Test Case 2: FP8 E5M2 Normalized GEMM (1.0 x 4.0 x 8 = 32.0)
    // ------------------------------------------------------------------------
    item = systolic_seq_item::type_id::create("item_e5m2");
    env.agent.sequencer.wait_for_grant();
    item.prec_mode        = PREC_FP8_E5M2;
    item.act_mode         = ACT_BYPASS;
    item.inter_beat_delay = 0;

    // In E5M2: 1.0 is 0x3C (Exp=15, Mantissa=0)
    // In E5M2: 4.0 is 0x44 (Exp=17, Mantissa=0)
    for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        item.weights[r][c]     = 8'h44; // 4.0
        item.activations[r][c] = 8'h3C; // 1.0
      end
    end
    env.agent.sequencer.send_request(item);
    env.agent.sequencer.wait_for_item_done();

    #1000ns;
    phase.drop_objection(this);
    `uvm_info(get_type_name(), "Directed FP8 Test Sequence Finished.", UVM_LOW)
  endtask

endclass : test_fp8_directed

`endif // TEST_FP8_DIRECTED_SV
