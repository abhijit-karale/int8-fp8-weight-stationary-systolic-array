// ============================================================================
// File: pe_int8_mac.sv
// Designer: Abhijit Karale
// Module: pe_int8_mac
// Target: SkyWater 130nm @ 200 MHz
// Description: Synthesizable signed INT8 Multiply-Accumulate unit with 
//              dynamic operand isolation for dynamic power reduction.
// ============================================================================

`timescale 1ns/1ps

module pe_int8_mac
  import systolic_pkg::*;
(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,       // Datapath enable
  input  logic               isolate,      // Force multiplier operands to 0
  input  logic signed [7:0]  a_in,         // Activation input (signed INT8)
  input  logic signed [7:0]  w_in,         // Weight input (signed INT8)
  input  logic signed [31:0] psum_in,      // Incoming 32-bit partial sum
  output logic signed [31:0] psum_out,     // Outgoing 32-bit partial sum
  output logic               overflow_flag // Flag for signed 32-bit overflow
);

  // --------------------------------------------------------------------------
  // Low-Power Operand Isolation
  // Suppresses multiplier switching toggle whenever MAC is idle or isolated
  // --------------------------------------------------------------------------
  logic signed [7:0] a_gated;
  logic signed [7:0] w_gated;

  wire gate_operands = ~enable | isolate;

  always_comb begin
    if (gate_operands) begin
      a_gated = 8'sd0;
      w_gated = 8'sd0;
    end else begin
      a_gated = a_in;
      w_gated = w_in;
    end
  end

  // --------------------------------------------------------------------------
  // Signed 8-bit x 8-bit Multiplication
  // --------------------------------------------------------------------------
  logic signed [15:0] mult_product;
  always_comb begin
    mult_product = a_gated * w_gated;
  end

  // --------------------------------------------------------------------------
  // 32-bit Accumulator Stage
  // --------------------------------------------------------------------------
  logic signed [31:0] product_ext;
  assign product_ext = {{16{mult_product[15]}}, mult_product};

  always_comb begin
    psum_out = psum_in + product_ext;
    
    // Signed overflow detection:
    // Occurs when two positive numbers produce a negative result, or
    // two negative numbers produce a positive result.
    overflow_flag = (~product_ext[31] & ~psum_in[31] &  psum_out[31]) |
                    ( product_ext[31] &  psum_in[31] & ~psum_out[31]);
  end

endmodule
