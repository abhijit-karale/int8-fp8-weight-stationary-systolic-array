// ============================================================================
// File: systolic_agent.sv
// Designer: Abhijit Karale
// Module: systolic_agent
// Target: UVM 1.2 Verification Suite
// Description: UVM agent encapsulating sequencer, driver, and monitor.
// ============================================================================

`ifndef SYSTOLIC_AGENT_SV
`define SYSTOLIC_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class systolic_agent extends uvm_agent;
  `uvm_component_utils(systolic_agent)

  systolic_sequencer sequencer;
  systolic_driver    driver;
  systolic_monitor   monitor;

  uvm_analysis_port #(systolic_seq_item) ap;

  function new(string name = "systolic_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = systolic_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = systolic_sequencer::type_id::create("sequencer", this);
      driver    = systolic_driver::type_id::create("driver", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
    ap = monitor.ap;
  endfunction

endclass : systolic_agent

`endif // SYSTOLIC_AGENT_SV
