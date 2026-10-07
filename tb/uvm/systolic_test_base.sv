// ============================================================================
// File: systolic_test_base.sv
// Designer: Abhijit Karale
// Module: systolic_test_base
// Target: UVM 1.2 Verification Suite
// Description: UVM base test providing environment instantiation, virtual
//              interface lookup, and simulation phase management.
// ============================================================================

`ifndef SYSTOLIC_TEST_BASE_SV
`define SYSTOLIC_TEST_BASE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class systolic_test_base extends uvm_test;
  `uvm_component_utils(systolic_test_base)

  systolic_env env;

  function new(string name = "systolic_test_base", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = systolic_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

endclass : systolic_test_base

`endif // SYSTOLIC_TEST_BASE_SV
