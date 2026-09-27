// ============================================================================
// File: pe.sv
// Designer: Abhijit Karale
// Module: pe
// Target: SkyWater 130nm @ 200 MHz
// Description: Processing Element (PE) with double-buffered weight registers
//              (shadow and active), horizontal activation forwarding, vertical
//              partial sum accumulation, and low-power operand isolation.
// ============================================================================

`timescale 1ns/1ps

module pe
  import systolic_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  
  // Control and Mode Configuration
  input  logic [1:0]  prec_mode,       // INT8, FP8_E4M3, FP8_E5M2
  input  logic        weight_load_en,  // Enable shift into weight_shadow
  input  logic        weight_swap,     // Atomic bank swap: active <= shadow
  input  logic        step_en,         // Array clock enable / step enable
  
  // Weight Cascade Path (North to South)
  input  logic [7:0]  weight_in,
  output logic [7:0]  weight_out,
  
  // Activation Streaming Path (West to East)
  input  logic        a_valid_in,
  input  logic [7:0]  a_in,
  output logic        a_valid_out,
  output logic [7:0]  a_out,
  
  // Partial Sum Accumulation Path (North to South)
  input  logic        psum_valid_in,
  input  logic [31:0] psum_in,
  output logic        psum_valid_out,
  output logic [31:0] psum_out,
  
  // Status and Arithmetic Diagnostics
  output logic        arith_error
);

  // --------------------------------------------------------------------------
  // Double-Buffered Weight Registers
  // --------------------------------------------------------------------------
  logic [7:0] weight_shadow;
  logic [7:0] weight_active;

  // Weight cascade loading into shadow buffer
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_shadow <= 8'h00;
    end else if (weight_load_en) begin
      weight_shadow <= weight_in;
    end
  end

  // Atomic bank swap: zero bubble cycles
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_active <= 8'h00;
    end else if (weight_swap) begin
      weight_active <= weight_shadow;
    end
  end

  // Forward shadow weight to South neighbor for column-wise shift loading
  assign weight_out = weight_shadow;

  // --------------------------------------------------------------------------
  // Activation Horizontal Pipeline Register (West to East)
  // --------------------------------------------------------------------------
  logic [7:0] a_reg;
  logic       a_val_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_reg     <= 8'h00;
      a_val_reg <= 1'b0;
    end else if (step_en) begin
      a_reg     <= a_in;
      a_val_reg <= a_valid_in;
    end
  end

  assign a_out       = a_reg;
  assign a_valid_out = a_val_reg;

  // --------------------------------------------------------------------------
  // Unified Multiply-Accumulate Logic
  // --------------------------------------------------------------------------
  // Enable MAC only when both activation and incoming partial sum are valid
  wire mac_enable = step_en & (a_valid_in & psum_valid_in);
  
  logic [31:0] mac_psum_next;
  logic        mac_error_next;

  mac_unit u_mac_unit (
    .clk        (clk),
    .rst_n      (rst_n),
    .enable     (mac_enable),
    .prec_mode  (prec_mode),
    .a_in       (a_in),
    .w_in       (weight_active),
    .psum_in    (psum_in),
    .psum_out   (mac_psum_next),
    .error_flag (mac_error_next)
  );

  // --------------------------------------------------------------------------
  // Partial Sum Vertical Pipeline Register (North to South)
  // --------------------------------------------------------------------------
  logic [31:0] psum_reg;
  logic        psum_val_reg;
  logic        error_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_reg     <= 32'h0000_0000;
      psum_val_reg <= 1'b0;
      error_reg    <= 1'b0;
    end else if (step_en) begin
      psum_val_reg <= psum_valid_in;
      error_reg    <= mac_error_next;
      
      if (a_valid_in & psum_valid_in) begin
        // Full MAC accumulation
        psum_reg <= mac_psum_next;
      end else if (psum_valid_in) begin
        // Pass-through partial sum if activation is not valid
        psum_reg <= psum_in;
      end else begin
        // Reset partial sum to zero when invalid to avoid spurious switching
        psum_reg <= 32'h0000_0000;
      end
    end
  end

  assign psum_out       = psum_reg;
  assign psum_valid_out = psum_val_reg;
  assign arith_error    = error_reg;

endmodule
