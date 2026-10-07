// ============================================================================
// File: systolic_env.sv
// Designer: Abhijit Karale
// Module: systolic_env
// Target: UVM 1.2 Verification Suite
// Description: UVM environment connecting agent, scoreboard, and coverage.
// ============================================================================

`ifndef SYSTOLIC_ENV_SV
`define SYSTOLIC_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class systolic_env extends uvm_env;
  `uvm_component_utils(systolic_env)

  systolic_agent      agent;
  systolic_scoreboard scoreboard;
  systolic_coverage   coverage;

  function new(string name = "systolic_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = systolic_agent::type_id::create("agent", this);
    scoreboard = systolic_scoreboard::type_id::create("scoreboard", this);
    coverage   = systolic_coverage::type_id::create("coverage", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.ap.connect(scoreboard.item_export);
    agent.ap.connect(coverage.analysis_export);
  endfunction

endclass : systolic_env

`endif // SYSTOLIC_ENV_SV
