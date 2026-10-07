// ============================================================================
// File: systolic_monitor.sv
// Designer: Abhijit Karale
// Module: systolic_monitor
// Target: UVM 1.2 Verification Suite
// Description: UVM monitor observing input streams and output results,
//              assembling complete 8x8 matrix transactions for scoreboard.
// ============================================================================

`ifndef SYSTOLIC_MONITOR_SV
`define SYSTOLIC_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

class systolic_monitor extends uvm_monitor;
  `uvm_component_utils(systolic_monitor)

  virtual systolic_if vif;
  uvm_analysis_port #(systolic_seq_item) ap;

  function new(string name = "systolic_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual systolic_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("MON_VIF_ERR", "Could not get virtual interface handle for monitor")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    fork
      monitor_output_stream();
    join
  endtask

  // --------------------------------------------------------------------------
  // Output Collection Task
  // --------------------------------------------------------------------------
  virtual task monitor_output_stream();
    systolic_seq_item item;
    int row_idx = 0;

    forever begin
      @(vif.cb_mon);
      if (vif.cb_mon.rst_n && vif.cb_mon.m_axis_out_tvalid && vif.cb_mon.m_axis_out_tready) begin
        if (row_idx == 0) begin
          item = systolic_seq_item::type_id::create("mon_item");
          item.prec_mode = prec_mode_e'(vif.cb_mon.cfg_prec_mode);
          item.act_mode  = act_mode_e'(vif.cb_mon.cfg_act_mode);
        end

        // Unpack 8 columns for row_idx
        for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
          item.actual_raw[row_idx][c]   = vif.cb_mon.m_axis_raw_tdata[(c*ACC_WIDTH) +: ACC_WIDTH];
          item.actual_quant[row_idx][c] = vif.cb_mon.m_axis_quant_tdata[(c*DATA_WIDTH) +: DATA_WIDTH];
        end

        item.arith_error_observed = vif.cb_mon.status_arith_error;

        if (row_idx == ARRAY_ROWS - 1 || vif.cb_mon.m_axis_out_tlast) begin
          row_idx = 0;
          ap.write(item);
        end else begin
          row_idx = row_idx + 1;
        end
      end
    end
  endtask

endclass : systolic_monitor

`endif // SYSTOLIC_MONITOR_SV
