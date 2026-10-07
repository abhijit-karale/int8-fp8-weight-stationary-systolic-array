// ============================================================================
// File: test_random_continuous.sv
// Designer: Abhijit Karale
// Module: test_random_continuous
// Target: UVM 1.2 Verification Suite
// Description: Continuous randomized back-to-back matrix multiplications
//              stress-testing double-buffered weight swapping and continuous
//              zero-bubble systolic streaming.
// ============================================================================

`ifndef TEST_RANDOM_CONTINUOUS_SV
`define TEST_RANDOM_CONTINUOUS_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

class test_random_continuous extends systolic_test_base;
  `uvm_component_utils(test_random_continuous)

  localparam int NUM_TILES = 10;

  function new(string name = "test_random_continuous", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    systolic_seq_item item;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), $sformatf("Launching Continuous Stress Test (%0d Matrix Tiles)...", NUM_TILES), UVM_LOW)

    for (int t = 0; t < NUM_TILES; t = t + 1) begin
      item = systolic_seq_item::type_id::create($sformatf("rand_item_%0d", t));
      env.agent.sequencer.wait_for_grant();
      
      if (!item.randomize() with {
        prec_mode == PREC_INT8; // Stress INT8 full range
        inter_beat_delay == 0;  // Continuous zero-bubble streaming
      }) begin
        `uvm_fatal("RAND_FAIL", "Failed to randomize systolic sequence item")
      end

      env.agent.sequencer.send_request(item);
      env.agent.sequencer.wait_for_item_done();
    end

    // Allow systolic array pipeline to drain completely
    #2000ns;
    phase.drop_objection(this);
    `uvm_info(get_type_name(), "Continuous Stress Test Complete.", UVM_LOW)
  endtask

endclass : test_random_continuous

`endif // TEST_RANDOM_CONTINUOUS_SV
