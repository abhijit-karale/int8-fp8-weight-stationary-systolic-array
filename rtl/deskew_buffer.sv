// ============================================================================
// File: deskew_buffer.sv
// Designer: Abhijit Karale
// Module: deskew_buffer
// Target: SkyWater 130nm @ 200 MHz
// Description: Output deskew buffer for 8x8 Systolic Array. Delays column j
//              by (7 - j) cycles to re-align diagonal outputs into a synchronized
//              parallel vector.
// ============================================================================

`timescale 1ns/1ps

module deskew_buffer
  import systolic_pkg::*;
(
  input  logic                           clk,
  input  logic                           rst_n,
  input  logic                           enable,          // Step enable
  
  // Skewed Partial-Sum Inputs emerging from Array bottom (Row 7)
  input  logic [ARRAY_COLS-1:0]          valid_in,
  input  logic [ARRAY_COLS-1:0][31:0]    data_in,
  
  // Deskewed Synchronized Vector Output
  output logic                           vector_valid_out,
  output logic [ARRAY_COLS-1:0][31:0]    data_out
);

  logic [ARRAY_COLS-1:0]       col_val_deskewed;
  logic [ARRAY_COLS-1:0][31:0] col_data_deskewed;

  // --------------------------------------------------------------------------
  // Delay Column j by (ARRAY_COLS - 1 - j) clock cycles
  // Column 7 delay = 0 cycles
  // Column 0 delay = 7 cycles
  // --------------------------------------------------------------------------
  genvar c;
  generate
    for (c = 0; c < ARRAY_COLS; c = c + 1) begin : gen_deskew_col
      localparam int DELAY = ARRAY_COLS - 1 - c;

      if (DELAY == 0) begin : gen_col_nodelay
        assign col_data_deskewed[c] = data_in[c];
        assign col_val_deskewed[c]  = valid_in[c];
      end else begin : gen_col_delayed
        logic [DELAY-1:0][31:0] sr_data;
        logic [DELAY-1:0]       sr_val;

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            sr_data <= '0;
            sr_val  <= '0;
          end else if (enable) begin
            sr_val[0]  <= valid_in[c];
            sr_data[0] <= data_in[c];
            for (int k = 1; k < DELAY; k = k + 1) begin
              sr_val[k]  <= sr_val[k-1];
              sr_data[k] <= sr_data[k-1];
            end
          end
        end

        assign col_data_deskewed[c] = sr_data[DELAY-1];
        assign col_val_deskewed[c]  = sr_val[DELAY-1];
      end
    end
  endgenerate

  assign data_out         = col_data_deskewed;
  // Vector valid is asserted when all columns are valid simultaneously
  assign vector_valid_out = &col_val_deskewed;

endmodule
