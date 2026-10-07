// ============================================================================
// File: tb_top.sv
// Designer: Abhijit Karale
// Module: tb_top
// Target: UVM 1.2 Verification Suite
// Description: Top-level UVM testbench module generating 200 MHz clock,
//              instantiating interface, DUT, and invoking run_test().
// ============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

`include "systolic_seq_item.sv"
`include "systolic_sequencer.sv"
`include "systolic_driver.sv"
`include "systolic_monitor.sv"
`include "systolic_scoreboard.sv"
`include "systolic_coverage.sv"
`include "systolic_agent.sv"
`include "systolic_env.sv"
`include "systolic_test_base.sv"
`include "test_int8_directed.sv"
`include "test_fp8_directed.sv"
`include "test_random_continuous.sv"

module tb_top;

  // --------------------------------------------------------------------------
  // Clock & Reset Generator (200 MHz Clock: Period = 5.0ns)
  // --------------------------------------------------------------------------
  logic clk;
  initial begin
    clk = 1'b0;
    forever #2.5ns clk = ~clk;
  end

  // --------------------------------------------------------------------------
  // Interface Instantiation
  // --------------------------------------------------------------------------
  systolic_if sys_if (.clk(clk));

  // --------------------------------------------------------------------------
  // DUT Instantiation
  // --------------------------------------------------------------------------
  systolic_array_top dut (
    .clk                  (sys_if.clk),
    .rst_n                (sys_if.rst_n),
    .step_en              (sys_if.step_en),
    
    .cfg_prec_mode        (sys_if.cfg_prec_mode),
    .cfg_act_mode         (sys_if.cfg_act_mode),
    .weight_swap_cmd      (sys_if.weight_swap_cmd),
    
    .s_axis_weight_tvalid (sys_if.s_axis_weight_tvalid),
    .s_axis_weight_tready (sys_if.s_axis_weight_tready),
    .s_axis_weight_tdata  (sys_if.s_axis_weight_tdata),
    .s_axis_weight_tlast  (sys_if.s_axis_weight_tlast),
    
    .s_axis_act_tvalid    (sys_if.s_axis_act_tvalid),
    .s_axis_act_tready    (sys_if.s_axis_act_tready),
    .s_axis_act_tdata     (sys_if.s_axis_act_tdata),
    .s_axis_act_tlast     (sys_if.s_axis_act_tlast),
    
    .seed_valid_in        (sys_if.seed_valid_in),
    .seed_psum_in         (sys_if.seed_psum_in),
    
    .m_axis_out_tvalid    (sys_if.m_axis_out_tvalid),
    .m_axis_out_tready    (sys_if.m_axis_out_tready),
    .m_axis_raw_tdata     (sys_if.m_axis_raw_tdata),
    .m_axis_quant_tdata   (sys_if.m_axis_quant_tdata),
    .m_axis_out_tlast     (sys_if.m_axis_out_tlast),
    
    .status_shadow_ready  (sys_if.status_shadow_ready),
    .status_busy          (sys_if.status_busy),
    .status_arith_error   (sys_if.status_arith_error)
  );

  // --------------------------------------------------------------------------
  // Simulation Setup and UVM Entry Point
  // --------------------------------------------------------------------------
  initial begin
    // Waveform VCD dump for debug
    $dumpfile("systolic_uvm.vcd");
    $dumpvars(0, tb_top);

    // Register virtual interface handle in UVM configuration database
    uvm_config_db#(virtual systolic_if)::set(null, "*", "vif", sys_if);

    // Run test from command line (+UVM_TESTNAME=...)
    run_test("test_int8_directed");
  end

endmodule
