// ============================================================================
// File: systolic_driver.sv
// Designer: Abhijit Karale
// Module: systolic_driver
// Target: UVM 1.2 Verification Suite
// Description: UVM driver implementing AXI-Stream protocol handshaking for
//              weight preloading, atomic swapping, and activation streaming.
// ============================================================================

`ifndef SYSTOLIC_DRIVER_SV
`define SYSTOLIC_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import systolic_pkg::*;

class systolic_driver extends uvm_driver #(systolic_seq_item);
  `uvm_component_utils(systolic_driver)

  virtual systolic_if vif;

  function new(string name = "systolic_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual systolic_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("DRV_VIF_ERR", "Could not get virtual interface handle for driver")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    reset_dut();
    forever begin
      seq_item_port.get_next_item(req);
      drive_transaction(req);
      seq_item_port.item_done();
    end
  endtask

  // --------------------------------------------------------------------------
  // Reset Task
  // --------------------------------------------------------------------------
  virtual task reset_dut();
    `uvm_info(get_type_name(), "Initiating System Reset...", UVM_LOW)
    vif.cb_drv.rst_n                <= 1'b0;
    vif.cb_drv.step_en              <= 1'b1;
    vif.cb_drv.cfg_prec_mode        <= 2'b00;
    vif.cb_drv.cfg_act_mode         <= 2'b00;
    vif.cb_drv.weight_swap_cmd      <= 1'b0;
    vif.cb_drv.s_axis_weight_tvalid <= 1'b0;
    vif.cb_drv.s_axis_weight_tdata  <= '0;
    vif.cb_drv.s_axis_weight_tlast  <= 1'b0;
    vif.cb_drv.s_axis_act_tvalid    <= 1'b0;
    vif.cb_drv.s_axis_act_tdata     <= '0;
    vif.cb_drv.s_axis_act_tlast     <= 1'b0;
    vif.cb_drv.seed_valid_in        <= 1'b0;
    vif.cb_drv.seed_psum_in         <= '0;
    vif.cb_drv.m_axis_out_tready    <= 1'b1; // Default sink ready

    repeat (5) @(vif.cb_drv);
    vif.cb_drv.rst_n <= 1'b1;
    repeat (2) @(vif.cb_drv);
    `uvm_info(get_type_name(), "Reset Complete. DUT operational.", UVM_LOW)
  endtask

  // --------------------------------------------------------------------------
  // Transaction Drive Protocol
  // --------------------------------------------------------------------------
  virtual task drive_transaction(systolic_seq_item item);
    `uvm_info(get_type_name(), item.convert2string(), UVM_MEDIUM)

    // 1. Configure Precision and Activation Modes
    vif.cb_drv.cfg_prec_mode <= item.prec_mode;
    vif.cb_drv.cfg_act_mode  <= item.act_mode;

    // 2. Preload Weights into Shadow Bank (8 beats)
    for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
      bit [WT_BUS_WIDTH-1:0] row_bytes;
      for (int c = 0; c < ARRAY_COLS; c = c + 1) begin
        row_bytes[(c*8) +: 8] = item.weights[r][c];
      end

      vif.cb_drv.s_axis_weight_tvalid <= 1'b1;
      vif.cb_drv.s_axis_weight_tdata  <= row_bytes;
      vif.cb_drv.s_axis_weight_tlast  <= (r == ARRAY_ROWS - 1);

      do begin
        @(vif.cb_drv);
      end while (!vif.cb_drv.s_axis_weight_tready);
    end

    vif.cb_drv.s_axis_weight_tvalid <= 1'b0;
    vif.cb_drv.s_axis_weight_tlast  <= 1'b0;

    // 3. Atomic Bank Swap (Transfer shadow weights to active registers)
    @(vif.cb_drv);
    vif.cb_drv.weight_swap_cmd <= 1'b1;
    @(vif.cb_drv);
    vif.cb_drv.weight_swap_cmd <= 1'b0;

    // 4. Stream Activations (8 beats with potential inter-beat delay)
    for (int k = 0; k < ARRAY_ROWS; k = k + 1) begin
      bit [ACT_BUS_WIDTH-1:0] act_bytes;
      for (int r = 0; r < ARRAY_ROWS; r = r + 1) begin
        act_bytes[(r*8) +: 8] = item.activations[k][r];
      end

      vif.cb_drv.s_axis_act_tvalid <= 1'b1;
      vif.cb_drv.s_axis_act_tdata  <= act_bytes;
      vif.cb_drv.s_axis_act_tlast  <= (k == ARRAY_ROWS - 1);

      do begin
        @(vif.cb_drv);
      end while (!vif.cb_drv.s_axis_act_tready);

      if (item.inter_beat_delay > 0) begin
        vif.cb_drv.s_axis_act_tvalid <= 1'b0;
        repeat (item.inter_beat_delay) @(vif.cb_drv);
      end
    end

    vif.cb_drv.s_axis_act_tvalid <= 1'b0;
    vif.cb_drv.s_axis_act_tlast  <= 1'b0;

  endtask

endclass : systolic_driver

`endif // SYSTOLIC_DRIVER_SV
