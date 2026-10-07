// ============================================================================
// File: systolic_sequencer.sv
// Designer: Abhijit Karale
// Module: systolic_sequencer
// Target: UVM 1.2 Verification Suite
// Description: UVM sequencer for passing systolic sequence items to driver.
// ============================================================================

`ifndef SYSTOLIC_SEQUENCER_SV
`define SYSTOLIC_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class systolic_sequencer extends uvm_sequencer #(systolic_seq_item);
  `uvm_component_utils(systolic_sequencer)

  function new(string name = "systolic_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass : systolic_sequencer

`endif // SYSTOLIC_SEQUENCER_SV
