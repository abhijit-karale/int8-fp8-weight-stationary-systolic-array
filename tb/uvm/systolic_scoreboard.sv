// ============================================================================
// File: systolic_scoreboard.sv
// Designer: Abhijit Karale
// Module: systolic_scoreboard
// Target: UVM 1.2 Verification Suite
// Description: Scoreboard with DPI-C golden model integration and bit-exact
//              matrix multiplication comparison engine.
// ============================================================================

`ifndef SYSTOLIC_SCOREBOARD_SV
`define SYSTOLIC_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

// DPI-C Golden Model Function Declarations
import "DPI-C" context function void c_dpi_int8_gemm(
  input  int   act_mode,
  input  byte  a_flat[],
  input  byte  w_flat[],
  output int   raw_out_flat[],
  output byte  quant_out_flat[]
);

class systolic_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(systolic_scoreboard)

  uvm_analysis_imp #(systolic_seq_item, systolic_scoreboard) item_export;

  int match_count;
  int mismatch_count;
  int total_matrices_checked;

  function new(string name = "systolic_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    item_export = new("item_export", this);
    match_count            = 0;
    mismatch_count          = 0;
    total_matrices_checked = 0;
  endfunction

  // --------------------------------------------------------------------------
  // Pure-SystemVerilog Bit-Exact Reference Algorithm
  // Ensures standalone execution capability in any simulation environment
  // --------------------------------------------------------------------------
  virtual function void compute_sv_reference(systolic_seq_item item);
    if (item.prec_mode == PREC_INT8) begin
      for (int k = 0; k < ARRAY_ROWS; k = k + 1) begin
        for (int j = 0; j < ARRAY_COLS; j = j + 1) begin
          int signed acc = 0;
          for (int i = 0; i < ARRAY_ROWS; i = i + 1) begin
            int signed a_val = $signed(item.activations[k][i]);
            int signed w_val = $signed(item.weights[i][j]);
            acc = acc + (a_val * w_val);
          end

          // Post-activation
          case (item.act_mode)
            ACT_BYPASS:     item.expected_raw[k][j] = acc;
            ACT_RELU:       item.expected_raw[k][j] = (acc < 0) ? 0 : acc;
            ACT_LEAKY_RELU: item.expected_raw[k][j] = (acc < 0) ? (acc >>> 3) : acc;
            ACT_CLIP: begin
              if (acc > 127)        item.expected_raw[k][j] = 127;
              else if (acc < -128)  item.expected_raw[k][j] = -128;
              else                  item.expected_raw[k][j] = acc;
            end
          endcase

          // Quantization
          if (item.expected_raw[k][j] > 127) begin
            item.expected_quant[k][j] = 8'sd127;
          end else if (item.expected_raw[k][j] < -128) begin
            item.expected_quant[k][j] = -8'sd128;
          end else begin
            item.expected_quant[k][j] = item.expected_raw[k][j][7:0];
          end
        end
      end
    end
  endfunction

  // --------------------------------------------------------------------------
  // Transaction Check Implementation
  // --------------------------------------------------------------------------
  virtual function void write(systolic_seq_item item);
    total_matrices_checked++;
    compute_sv_reference(item);

    `uvm_info(get_type_name(), $sformatf("Verifying Matrix %0d [%s | %s]...", 
              total_matrices_checked, item.prec_mode.name(), item.act_mode.name()), UVM_LOW)

    for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        if (item.actual_quant[r][c] !== item.expected_quant[r][c]) begin
          mismatch_count++;
          `uvm_error("SCB_MISMATCH", $sformatf(
            "Matrix %0d Mismatch at [%0d][%0d]! Actual: 0x%02h (%0d), Expected: 0x%02h (%0d)",
            total_matrices_checked, r, c, 
            item.actual_quant[r][c], $signed(item.actual_quant[r][c]),
            item.expected_quant[r][c], $signed(item.expected_quant[r][c])
          ))
        end else begin
          match_count++;
        end
      end
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), "==================================================", UVM_NONE)
    `uvm_info(get_type_name(), "           SYSTOLIC ARRAY SCOREBOARD REPORT       ", UVM_NONE)
    `uvm_info(get_type_name(), "==================================================", UVM_NONE)
    `uvm_info(get_type_name(), $sformatf("Total Matrices Checked: %0d", total_matrices_checked), UVM_NONE)
    `uvm_info(get_type_name(), $sformatf("Total Elements Matched: %0d", match_count), UVM_NONE)
    `uvm_info(get_type_name(), $sformatf("Total Elements Errored: %0d", mismatch_count), UVM_NONE)

    if (mismatch_count == 0 && total_matrices_checked > 0) begin
      `uvm_info(get_type_name(), ">>>>> [TEST STATUS: PASSED - 100% BIT-EXACT] <<<<<", UVM_NONE)
    end else begin
      `uvm_error(get_type_name(), ">>>>> [TEST STATUS: FAILED] <<<<<")
    end
    `uvm_info(get_type_name(), "==================================================", UVM_NONE)
  endfunction

endclass : systolic_scoreboard

`endif // SYSTOLIC_SCOREBOARD_SV
