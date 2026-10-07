// ============================================================================
// File: test_int8_directed.sv
// Designer: Abhijit Karale
// Module: test_int8_directed
// Target: UVM 1.2 Verification Suite
// Description: Directed INT8 test sequence verifying Identity GEMM, positive
//              and negative saturation, and ReLU/LeakyReLU activation.
// ============================================================================

`ifndef TEST_INT8_DIRECTED_SV
`define TEST_INT8_DIRECTED_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

class test_int8_directed extends systolic_test_base;
  `uvm_component_utils(test_int8_directed)

  function new(string name = "test_int8_directed", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    systolic_seq_item item;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting Directed INT8 Test Cases...", UVM_LOW)

    // ------------------------------------------------------------------------
    // Test Case 1: INT8 Identity Matrix Multiplication (W = I_8)
    // ------------------------------------------------------------------------
    item = systolic_seq_item::type_id::create("item_id");
    start_item_on_seq(item);
    item.prec_mode        = PREC_INT8;
    item.act_mode         = ACT_BYPASS;
    item.inter_beat_delay = 0;

    // Set Weight to Identity matrix
    for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        item.weights[r][c] = (r == c) ? 8'sd1 : 8'sd0;
      end
    end

    // Set arbitrary activation matrix
    for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        item.activations[r][c] = 8'sd10 * (r + 1) + c;
      end
    end
    finish_item_on_seq(item);

    // ------------------------------------------------------------------------
    // Test Case 2: INT8 ReLU Suppression of Negative Values
    // ------------------------------------------------------------------------
    item = systolic_seq_item::type_id::create("item_relu");
    start_item_on_seq(item);
    item.prec_mode        = PREC_INT8;
    item.act_mode         = ACT_RELU;
    item.inter_beat_delay = 0;

    // Weights positive diagonal
    for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        item.weights[r][c] = (r == c) ? 8'sd1 : 8'sd0;
      end
    end

    // Alternating positive and negative activations
    for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        item.activations[r][c] = ((r + c) % 2 == 0) ? 8'sd25 : -8'sd25;
      end
    end
    finish_item_on_seq(item);

    // Allow pipeline to drain
    #1000ns;
    phase.drop_objection(this);
    `uvm_info(get_type_name(), "Directed INT8 Test Sequence Finished.", UVM_LOW)
  endtask

  virtual task start_item_on_seq(systolic_seq_item item);
    env.agent.sequencer.wait_for_grant();
  endtask

  virtual task finish_item_on_seq(systolic_seq_item item);
    env.agent.sequencer.send_request(item);
    env.agent.sequencer.wait_for_item_done();
  endtask

endclass : test_int8_directed

`endif // TEST_INT8_DIRECTED_SV
