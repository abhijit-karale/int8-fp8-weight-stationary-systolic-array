// ============================================================================
// File: weight_loader.sv
// Designer: Abhijit Karale
// Module: weight_loader
// Target: SkyWater 130nm @ 200 MHz
// Description: Streaming AXI-Stream weight loader managing double-buffered
//              shadow weight preloading and atomic 1-cycle swap execution.
// ============================================================================

`timescale 1ns/1ps

module weight_loader
  import systolic_pkg::*;
(
  input  logic                           clk,
  input  logic                           rst_n,
  
  // AXI-Stream Slave Weight Interface (64-bit width = 8 columns x 8-bit)
  input  logic                           s_axis_weight_tvalid,
  output logic                           s_axis_weight_tready,
  input  logic [WT_BUS_WIDTH-1:0]        s_axis_weight_tdata,
  input  logic                           s_axis_weight_tlast,
  
  // Array Interface
  output logic [ARRAY_COLS-1:0][7:0]     weight_stream_out,
  output logic                           weight_load_en,
  output logic                           weight_swap_out,
  
  // Host Control & Status
  input  logic                           swap_trigger_cmd, // Pulse to swap
  output logic                           shadow_bank_ready, // Shadow has 8x8 loaded
  output logic                           loader_busy
);

  // Row counter for preloading 8 rows of weights
  logic [2:0] row_cnt;
  logic       shadow_valid;

  assign s_axis_weight_tready = ~shadow_valid; // Ready if shadow bank is not already armed
  assign loader_busy          = (row_cnt != 3'd0) || shadow_valid;
  assign shadow_bank_ready    = shadow_valid;

  // Unpack 64-bit bus into 8 byte lanes (one per column)
  genvar c;
  generate
    for (c = 0; c < ARRAY_COLS; c = c + 1) begin : gen_weight_lanes
      assign weight_stream_out[c] = s_axis_weight_tdata[(c*DATA_WIDTH) +: DATA_WIDTH];
    end
  endgenerate

  // Shift enable to array shadow registers
  wire shift_beat = s_axis_weight_tvalid & s_axis_weight_tready;
  assign weight_load_en = shift_beat;

  // Track weight loading progress
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      row_cnt      <= 3'd0;
      shadow_valid <= 1'b0;
    end else begin
      if (shift_beat) begin
        if (row_cnt == 3'd7 || s_axis_weight_tlast) begin
          row_cnt      <= 3'd0;
          shadow_valid <= 1'b1; // All 8 rows preloaded into shadow bank
        end else begin
          row_cnt <= row_cnt + 3'd1;
        end
      end

      // Clear shadow_valid when swapped into active registers
      if (weight_swap_out) begin
        shadow_valid <= 1'b0;
      end
    end
  end

  // Atomic swap signal generated upon host trigger when shadow is ready
  assign weight_swap_out = swap_trigger_cmd & shadow_valid;

endmodule
