// ============================================================================
// File: systolic_if.sv
// Designer: Abhijit Karale
// Module: systolic_if
// Target: UVM 1.2 Verification Suite
// Description: SystemVerilog interface for INT8/FP8 Systolic Array with
//              clocking blocks, modports, and protocol checkers.
// ============================================================================

`timescale 1ns/1ps

interface systolic_if
  import systolic_pkg::*;
(
  input logic clk
);

  // Reset and Master Step Enable
  logic                       rst_n;
  logic                       step_en;

  // Configuration
  logic [1:0]                 cfg_prec_mode;
  logic [1:0]                 cfg_act_mode;
  logic                       weight_swap_cmd;

  // Weight AXI-Stream Slave Interface
  logic                       s_axis_weight_tvalid;
  logic                       s_axis_weight_tready;
  logic [WT_BUS_WIDTH-1:0]    s_axis_weight_tdata;
  logic                       s_axis_weight_tlast;

  // Activation AXI-Stream Slave Interface
  logic                       s_axis_act_tvalid;
  logic                       s_axis_act_tready;
  logic [ACT_BUS_WIDTH-1:0]   s_axis_act_tdata;
  logic                       s_axis_act_tlast;

  // Partial Sum Seed Interface
  logic                       seed_valid_in;
  logic [ARRAY_COLS-1:0][31:0] seed_psum_in;

  // Output AXI-Stream Master Interface
  logic                       m_axis_out_tvalid;
  logic                       m_axis_out_tready;
  logic [OUT_RAW_WIDTH-1:0]   m_axis_raw_tdata;
  logic [OUT_QUANT_WIDTH-1:0] m_axis_quant_tdata;
  logic                       m_axis_out_tlast;

  // Status & Diagnostics
  logic                       status_shadow_ready;
  logic                       status_busy;
  logic                       status_arith_error;

  // --------------------------------------------------------------------------
  // Driver Clocking Block
  // --------------------------------------------------------------------------
  clocking cb_drv @(posedge clk);
    default input #1ns output #1ns;
    output rst_n, step_en;
    output cfg_prec_mode, cfg_act_mode, weight_swap_cmd;
    output s_axis_weight_tvalid, s_axis_weight_tdata, s_axis_weight_tlast;
    output s_axis_act_tvalid, s_axis_act_tdata, s_axis_act_tlast;
    output seed_valid_in, seed_psum_in;
    output m_axis_out_tready;
    input  s_axis_weight_tready, s_axis_act_tready;
    input  m_axis_out_tvalid, m_axis_raw_tdata, m_axis_quant_tdata, m_axis_out_tlast;
    input  status_shadow_ready, status_busy, status_arith_error;
  endclocking

  // --------------------------------------------------------------------------
  // Monitor Clocking Block
  // --------------------------------------------------------------------------
  clocking cb_mon @(posedge clk);
    default input #1ns output #1ns;
    input rst_n, step_en;
    input cfg_prec_mode, cfg_act_mode, weight_swap_cmd;
    input s_axis_weight_tvalid, s_axis_weight_tready, s_axis_weight_tdata, s_axis_weight_tlast;
    input s_axis_act_tvalid, s_axis_act_tready, s_axis_act_tdata, s_axis_act_tlast;
    input seed_valid_in, seed_psum_in;
    input m_axis_out_tvalid, m_axis_out_tready, m_axis_raw_tdata, m_axis_quant_tdata, m_axis_out_tlast;
    input status_shadow_ready, status_busy, status_arith_error;
  endclocking

  // --------------------------------------------------------------------------
  // Modports
  // --------------------------------------------------------------------------
  modport driver_mp (
    clocking cb_drv,
    input clk
  );

  modport monitor_mp (
    clocking cb_mon,
    input clk
  );

  modport dut_mp (
    input  clk, rst_n, step_en,
    input  cfg_prec_mode, cfg_act_mode, weight_swap_cmd,
    input  s_axis_weight_tvalid, s_axis_weight_tdata, s_axis_weight_tlast,
    output s_axis_weight_tready,
    input  s_axis_act_tvalid, s_axis_act_tdata, s_axis_act_tlast,
    output s_axis_act_tready,
    input  seed_valid_in, seed_psum_in,
    output m_axis_out_tvalid, m_axis_raw_tdata, m_axis_quant_tdata, m_axis_out_tlast,
    input  m_axis_out_tready,
    output status_shadow_ready, status_busy, status_arith_error
  );

endinterface : systolic_if
