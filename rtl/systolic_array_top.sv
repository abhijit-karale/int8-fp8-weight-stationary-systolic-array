// ============================================================================
// File: systolic_array_top.sv
// Designer: Abhijit Karale
// Module: systolic_array_top
// Target: SkyWater 130nm @ 200 MHz
// Description: Production-grade 8x8 Weight-Stationary Systolic Array AI
//              Accelerator top-level module with dual-precision (INT8/FP8)
//              compute, double-buffered weight preloading, triangular skew
//              and deskew buffers, and pipelined activation units.
// ============================================================================

`timescale 1ns/1ps

module systolic_array_top
  import systolic_pkg::*;
(
  input  logic                           clk,
  input  logic                           rst_n,
  input  logic                           step_en,             // Master clock/step enable
  
  // Configuration Registers
  input  logic [1:0]                     cfg_prec_mode,       // INT8, FP8_E4M3, FP8_E5M2
  input  logic [1:0]                     cfg_act_mode,        // BYPASS, RELU, LEAKY_RELU, CLIP
  input  logic                           weight_swap_cmd,     // Host trigger for atomic bank swap
  
  // AXI-Stream Slave: Weight Stream (64-bit = 8 columns x 8-bit)
  input  logic                           s_axis_weight_tvalid,
  output logic                           s_axis_weight_tready,
  input  logic [WT_BUS_WIDTH-1:0]        s_axis_weight_tdata,
  input  logic                           s_axis_weight_tlast,
  
  // AXI-Stream Slave: Activation Stream (64-bit = 8 rows x 8-bit)
  input  logic                           s_axis_act_tvalid,
  output logic                           s_axis_act_tready,
  input  logic [ACT_BUS_WIDTH-1:0]       s_axis_act_tdata,
  input  logic                           s_axis_act_tlast,
  
  // External Partial Sum Seed (For tile accumulation, default 0)
  input  logic                           seed_valid_in,
  input  wire logic [ARRAY_COLS-1:0][31:0]    seed_psum_in,

  // AXI-Stream Master: Output Stream
  output logic                           m_axis_out_tvalid,
  input  logic                           m_axis_out_tready,
  output logic [OUT_RAW_WIDTH-1:0]       m_axis_raw_tdata,    // 8 cols x 32-bit (256 bits)
  output logic [OUT_QUANT_WIDTH-1:0]     m_axis_quant_tdata,  // 8 cols x 8-bit (64 bits)
  output logic                           m_axis_out_tlast,
  
  // Diagnostic and Status Signals
  output logic                           status_shadow_ready, // Shadow weight bank armed
  output logic                           status_busy,
  output logic                           status_arith_error
);

  // --------------------------------------------------------------------------
  // Internal Interconnect Nets
  // --------------------------------------------------------------------------
  // Weight distribution
  logic [ARRAY_COLS-1:0][7:0] weight_stream;
  logic                       weight_load_en;
  logic                       weight_swap;
  logic [ARRAY_ROWS-1:0][ARRAY_COLS-1:0][7:0] weight_cascade;

  // Activation streaming (Skew buffer to PEs, and PE-to-PE horizontal)
  logic [ARRAY_ROWS-1:0][7:0]            act_unskewed;
  logic [ARRAY_ROWS-1:0]                 act_val_skewed;
  logic [ARRAY_ROWS-1:0][7:0]            act_skewed;
  logic [ARRAY_ROWS-1:0][ARRAY_COLS-1:0][7:0] a_horizontal;
  logic [ARRAY_ROWS-1:0][ARRAY_COLS-1:0]      a_val_horizontal;

  // Partial sum accumulation (PE-to-PE vertical)
  logic [ARRAY_ROWS-1:0][ARRAY_COLS-1:0][31:0] psum_cascade;
  logic [ARRAY_ROWS-1:0][ARRAY_COLS-1:0]       psum_val_cascade;
  logic [ARRAY_ROWS-1:0][ARRAY_COLS-1:0]       pe_error_grid;

  // Deskew buffer outputs
  logic                                  deskew_val;
  logic [ARRAY_COLS-1:0][31:0]           deskew_data;

  // Activation unit outputs
  logic [ARRAY_COLS-1:0]                 act_unit_val;
  logic [ARRAY_COLS-1:0][31:0]           act_unit_raw;
  logic [ARRAY_COLS-1:0][7:0]            act_unit_quant;

  // --------------------------------------------------------------------------
  // Submodule: Weight Loader & Double Buffer Controller
  // --------------------------------------------------------------------------
  weight_loader u_weight_loader (
    .clk                  (clk),
    .rst_n                (rst_n),
    .s_axis_weight_tvalid (s_axis_weight_tvalid),
    .s_axis_weight_tready (s_axis_weight_tready),
    .s_axis_weight_tdata  (s_axis_weight_tdata),
    .s_axis_weight_tlast  (s_axis_weight_tlast),
    .weight_stream_out    (weight_stream),
    .weight_load_en       (weight_load_en),
    .weight_swap_out      (weight_swap),
    .swap_trigger_cmd     (weight_swap_cmd),
    .shadow_bank_ready    (status_shadow_ready),
    .loader_busy          (status_busy)
  );

  // --------------------------------------------------------------------------
  // Submodule: Input Activation Skew Buffer
  // --------------------------------------------------------------------------
  genvar r_in;
  generate
    for (r_in = 0; r_in < ARRAY_ROWS; r_in = r_in + 1) begin : gen_act_lanes
      assign act_unskewed[r_in] = s_axis_act_tdata[(r_in*DATA_WIDTH) +: DATA_WIDTH];
    end
  endgenerate

  skew_buffer u_skew_buffer (
    .clk       (clk),
    .rst_n     (rst_n),
    .enable    (step_en),
    .valid_in  (s_axis_act_tvalid),
    .data_in   (act_unskewed),
    .ready_out (s_axis_act_tready),
    .valid_out (act_val_skewed),
    .data_out  (act_skewed)
  );

  // --------------------------------------------------------------------------
  // 8x8 Processing Element (PE) 2D Mesh Core
  // --------------------------------------------------------------------------
  genvar r, c;
  generate
    for (r = 0; r < ARRAY_ROWS; r = r + 1) begin : gen_pe_row
      for (c = 0; c < ARRAY_COLS; c = c + 1) begin : gen_pe_col

        // Weight Input connection
        logic [7:0] pe_weight_in;
        if (r == 0) begin : gen_w_top
          assign pe_weight_in = weight_stream[c];
        end else begin : gen_w_cascade
          assign pe_weight_in = weight_cascade[r-1][c];
        end

        // Activation Input connection (Horizontal: West to East)
        logic       pe_a_val_in;
        logic [7:0] pe_a_in;
        if (c == 0) begin : gen_a_left
          assign pe_a_in     = act_skewed[r];
          assign pe_a_val_in = act_val_skewed[r];
        end else begin : gen_a_forward
          assign pe_a_in     = a_horizontal[r][c-1];
          assign pe_a_val_in = a_val_horizontal[r][c-1];
        end

        // Partial Sum Input connection (Vertical: North to South)
        logic        pe_psum_val_in;
        logic [31:0] pe_psum_in;
        if (r == 0) begin : gen_psum_top
          assign pe_psum_in     = seed_valid_in ? seed_psum_in[c] : 32'h0000_0000;
          // Row 0 initiates psum calculation synchronously with activation presence
          assign pe_psum_val_in = pe_a_val_in;
        end else begin : gen_psum_cascade
          assign pe_psum_in     = psum_cascade[r-1][c];
          assign pe_psum_val_in = psum_val_cascade[r-1][c];
        end

        // Processing Element Instance
        pe u_pe_inst (
          .clk            (clk),
          .rst_n          (rst_n),
          .prec_mode      (cfg_prec_mode),
          .weight_load_en (weight_load_en),
          .weight_swap    (weight_swap),
          .step_en        (step_en),
          
          // Weight Cascade
          .weight_in      (pe_weight_in),
          .weight_out     (weight_cascade[r][c]),
          
          // Activation Forwarding
          .a_valid_in     (pe_a_val_in),
          .a_in           (pe_a_in),
          .a_valid_out    (a_val_horizontal[r][c]),
          .a_out          (a_horizontal[r][c]),
          
          // Partial Sum Forwarding
          .psum_valid_in  (pe_psum_val_in),
          .psum_in        (pe_psum_in),
          .psum_valid_out (psum_val_cascade[r][c]),
          .psum_out       (psum_cascade[r][c]),
          
          // Diagnostics
          .arith_error    (pe_error_grid[r][c])
        );

      end
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Submodule: Output Deskew Buffer
  // --------------------------------------------------------------------------
  logic [ARRAY_COLS-1:0]       array_out_val;
  logic [ARRAY_COLS-1:0][31:0] array_out_data;

  generate
    for (c = 0; c < ARRAY_COLS; c = c + 1) begin : gen_array_out
      assign array_out_val[c]  = psum_val_cascade[ARRAY_ROWS-1][c];
      assign array_out_data[c] = psum_cascade[ARRAY_ROWS-1][c];
    end
  endgenerate

  deskew_buffer u_deskew_buffer (
    .clk              (clk),
    .rst_n            (rst_n),
    .enable           (step_en),
    .valid_in         (array_out_val),
    .data_in          (array_out_data),
    .vector_valid_out (deskew_val),
    .data_out         (deskew_data)
  );

  // --------------------------------------------------------------------------
  // Submodule: Pipelined Activation Units (One per column)
  // --------------------------------------------------------------------------
  generate
    for (c = 0; c < ARRAY_COLS; c = c + 1) begin : gen_act_units
      activation_unit u_act_unit (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (step_en),
        .prec_mode      (cfg_prec_mode),
        .act_mode       (cfg_act_mode),
        .valid_in       (deskew_val),
        .data_in        (deskew_data[c]),
        .valid_out      (act_unit_val[c]),
        .data_out_raw   (act_unit_raw[c]),
        .data_out_quant (act_unit_quant[c])
      );
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Output Formatting & AXI-Stream Packaging
  // --------------------------------------------------------------------------
  assign m_axis_out_tvalid = act_unit_val[0];

  generate
    for (c = 0; c < ARRAY_COLS; c = c + 1) begin : gen_pack_out
      assign m_axis_raw_tdata[(c*ACC_WIDTH) +: ACC_WIDTH]    = act_unit_raw[c];
      assign m_axis_quant_tdata[(c*DATA_WIDTH) +: DATA_WIDTH] = act_unit_quant[c];
    end
  endgenerate

  // Output Row Counter for tlast Generation
  logic [2:0] out_row_cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_row_cnt <= 3'd0;
    end else if (m_axis_out_tvalid && (m_axis_out_tready || !m_axis_out_tvalid)) begin
      out_row_cnt <= out_row_cnt + 3'd1;
    end
  end

  assign m_axis_out_tlast = m_axis_out_tvalid & (out_row_cnt == 3'd7);

  // Consolidated Error Diagnostic
  logic grid_error_comb;
  always_comb begin
    grid_error_comb = 1'b0;
    for (int i = 0; i < ARRAY_ROWS; i = i + 1) begin
      for (int j = 0; j < ARRAY_COLS; j = j + 1) begin
        grid_error_comb = grid_error_comb | pe_error_grid[i][j];
      end
    end
  end

  assign status_arith_error = grid_error_comb;

endmodule
