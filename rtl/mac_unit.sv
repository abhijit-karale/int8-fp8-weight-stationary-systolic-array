// ============================================================================
// File: mac_unit.sv
// Designer: Abhijit Karale
// Module: mac_unit
// Target: SkyWater 130nm @ 200 MHz
// Description: Unified precision-multiplexed MAC unit integrating INT8 and
//              FP8 (E4M3/E5M2) execution with mutually-exclusive datapath
//              isolation for low dynamic power consumption.
// ============================================================================

`timescale 1ns/1ps

module mac_unit
  import systolic_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,      // Unit compute enable
  input  logic [1:0]  prec_mode,   // Precision mode
  input  logic [7:0]  a_in,        // Activation byte
  input  logic [7:0]  w_in,        // Weight byte
  input  logic [31:0] psum_in,     // Unified 32-bit partial sum input
  output logic [31:0] psum_out,    // Unified 32-bit partial sum output
  output logic        error_flag   // Arithmetic overflow or NaN flag
);

  // --------------------------------------------------------------------------
  // Datapath Isolation Signals
  // --------------------------------------------------------------------------
  wire is_int8_mode = (prec_mode == PREC_INT8);
  wire is_fp8_mode  = (prec_mode == PREC_FP8_E4M3) || (prec_mode == PREC_FP8_E5M2);

  // Mutually exclusive operand isolation
  wire int8_enable  = enable & is_int8_mode;
  wire int8_isolate = ~is_int8_mode;

  wire fp8_enable   = enable & is_fp8_mode;
  wire fp8_isolate  = ~is_fp8_mode;

  // --------------------------------------------------------------------------
  // INT8 MAC Submodule
  // --------------------------------------------------------------------------
  logic [31:0] int8_psum_out;
  logic        int8_overflow;

  pe_int8_mac u_int8_mac (
    .clk           (clk),
    .rst_n         (rst_n),
    .enable        (int8_enable),
    .isolate       (int8_isolate),
    .a_in          (a_in),
    .w_in          (w_in),
    .psum_in       (psum_in),
    .psum_out      (int8_psum_out),
    .overflow_flag (int8_overflow)
  );

  // --------------------------------------------------------------------------
  // FP8 MAC Submodule
  // --------------------------------------------------------------------------
  logic [31:0] fp8_psum_out;
  logic        fp8_invalid;

  pe_fp8_mac u_fp8_mac (
    .clk          (clk),
    .rst_n        (rst_n),
    .enable       (fp8_enable),
    .isolate      (fp8_isolate),
    .prec_mode    (prec_mode),
    .a_in         (a_in),
    .w_in         (w_in),
    .psum_in      (psum_in),
    .psum_out     (fp8_psum_out),
    .invalid_flag (fp8_invalid)
  );

  // --------------------------------------------------------------------------
  // Output Precision Multiplexing
  // --------------------------------------------------------------------------
  always_comb begin
    if (is_int8_mode) begin
      psum_out   = int8_psum_out;
      error_flag = int8_overflow;
    end else begin
      psum_out   = fp8_psum_out;
      error_flag = fp8_invalid;
    end
  end

endmodule
