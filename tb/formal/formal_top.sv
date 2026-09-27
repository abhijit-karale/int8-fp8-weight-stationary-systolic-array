// ============================================================================
// File: formal_top.sv
// Designer: Abhijit Karale
// Module: formal_top
// Target: Formal Verification (SymbiYosys / Questa Formal / JasperGold)
// Description: Top-level formal harness instantiating the design under test
//              (DUT) and binding all SVA assertion checkers.
// ============================================================================

`timescale 1ns/1ps

module formal_top (
  input logic clk,
  input logic rst_n
);

  import systolic_pkg::*;

  // --------------------------------------------------------------------------
  // Formal Free Inputs (Driven by Formal Solver)
  // --------------------------------------------------------------------------
  logic                      step_en;
  logic [1:0]                cfg_prec_mode;
  logic [1:0]                cfg_act_mode;
  logic                      weight_swap_cmd;

  logic                      s_axis_weight_tvalid;
  logic                      s_axis_weight_tready;
  logic [WT_BUS_WIDTH-1:0]   s_axis_weight_tdata;
  logic                      s_axis_weight_tlast;

  logic                      s_axis_act_tvalid;
  logic                      s_axis_act_tready;
  logic [ACT_BUS_WIDTH-1:0]  s_axis_act_tdata;
  logic                      s_axis_act_tlast;

  logic                      seed_valid_in;
  logic [ARRAY_COLS-1:0][31:0] seed_psum_in;

  logic                      m_axis_out_tvalid;
  logic                      m_axis_out_tready;
  logic [OUT_RAW_WIDTH-1:0]  m_axis_raw_tdata;
  logic [OUT_QUANT_WIDTH-1:0] m_axis_quant_tdata;
  logic                      m_axis_out_tlast;

  logic                      status_shadow_ready;
  logic                      status_busy;
  logic                      status_arith_error;

  // --------------------------------------------------------------------------
  // Design Under Test (DUT) Instantiation
  // --------------------------------------------------------------------------
  systolic_array_top dut (
    .clk                  (clk),
    .rst_n                (rst_n),
    .step_en              (step_en),
    .cfg_prec_mode        (cfg_prec_mode),
    .cfg_act_mode         (cfg_act_mode),
    .weight_swap_cmd      (weight_swap_cmd),
    
    .s_axis_weight_tvalid (s_axis_weight_tvalid),
    .s_axis_weight_tready (s_axis_weight_tready),
    .s_axis_weight_tdata  (s_axis_weight_tdata),
    .s_axis_weight_tlast  (s_axis_weight_tlast),
    
    .s_axis_act_tvalid    (s_axis_act_tvalid),
    .s_axis_act_tready    (s_axis_act_tready),
    .s_axis_act_tdata     (s_axis_act_tdata),
    .s_axis_act_tlast     (s_axis_act_tlast),
    
    .seed_valid_in        (seed_valid_in),
    .seed_psum_in         (seed_psum_in),
    
    .m_axis_out_tvalid    (m_axis_out_tvalid),
    .m_axis_out_tready    (m_axis_out_tready),
    .m_axis_raw_tdata     (m_axis_raw_tdata),
    .m_axis_quant_tdata   (m_axis_quant_tdata),
    .m_axis_out_tlast     (m_axis_out_tlast),
    
    .status_shadow_ready  (status_shadow_ready),
    .status_busy          (status_busy),
    .status_arith_error   (status_arith_error)
  );

  // --------------------------------------------------------------------------
  // Formal Assumptions (Environment Constraints)
  // --------------------------------------------------------------------------
  // Keep step_en enabled during formal trace
  assume property (@(posedge clk) disable iff (!rst_n) step_en == 1'b1);
  assume property (@(posedge clk) disable iff (!rst_n) m_axis_out_tready == 1'b1);
  assume property (@(posedge clk) disable iff (!rst_n) seed_valid_in == 1'b0);

  // Valid precision modes only (0, 1, or 2)
  assume property (@(posedge clk) disable iff (!rst_n) cfg_prec_mode != PREC_RESERVED);

  // --------------------------------------------------------------------------
  // Top-Level SVA Checker Bind
  // --------------------------------------------------------------------------
  sva_systolic_top u_sva_top (
    .clk                  (clk),
    .rst_n                (rst_n),
    .step_en              (step_en),
    .cfg_prec_mode        (cfg_prec_mode),
    .cfg_act_mode         (cfg_act_mode),
    .weight_swap_cmd      (weight_swap_cmd),
    
    .s_axis_weight_tvalid (s_axis_weight_tvalid),
    .s_axis_weight_tready (s_axis_weight_tready),
    .s_axis_weight_tdata  (s_axis_weight_tdata),
    .s_axis_weight_tlast  (s_axis_weight_tlast),
    
    .s_axis_act_tvalid    (s_axis_act_tvalid),
    .s_axis_act_tready    (s_axis_act_tready),
    .s_axis_act_tdata     (s_axis_act_tdata),
    .s_axis_act_tlast     (s_axis_act_tlast),
    
    .m_axis_out_tvalid    (m_axis_out_tvalid),
    .m_axis_out_tready    (m_axis_out_tready),
    .m_axis_raw_tdata     (m_axis_raw_tdata),
    .m_axis_quant_tdata   (m_axis_quant_tdata),
    .m_axis_out_tlast     (m_axis_out_tlast),
    
    .status_shadow_ready  (status_shadow_ready),
    .status_busy          (status_busy),
    .status_arith_error   (status_arith_error)
  );

  // --------------------------------------------------------------------------
  // Bind SVA Checker to each individual PE inside 8x8 Grid
  // --------------------------------------------------------------------------
  bind pe sva_pe_checker u_sva_pe (
    .clk            (clk),
    .rst_n          (rst_n),
    .prec_mode      (prec_mode),
    .weight_load_en (weight_load_en),
    .weight_swap    (weight_swap),
    .step_en        (step_en),
    .weight_in      (weight_in),
    .weight_shadow  (weight_shadow),
    .weight_active  (weight_active),
    .a_valid_in     (a_valid_in),
    .a_in           (a_in),
    .a_valid_out    (a_valid_out),
    .a_out          (a_out),
    .psum_valid_in  (psum_valid_in),
    .psum_in        (psum_in),
    .psum_valid_out (psum_valid_out),
    .psum_out       (psum_out),
    .arith_error    (arith_error)
  );

endmodule
