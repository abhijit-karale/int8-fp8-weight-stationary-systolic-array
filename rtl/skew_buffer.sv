// ============================================================================
// File: skew_buffer.sv
// Designer: Abhijit Karale
// Module: skew_buffer
// Target: SkyWater 130nm @ 200 MHz
// Description: Triangular input skew buffer for 8x8 Systolic Array. Delays
//              row i by i clock cycles to create diagonal activation wavefronts.
// ============================================================================

`timescale 1ns/1ps

module skew_buffer
  import systolic_pkg::*;
(
  input  logic                           clk,
  input  logic                           rst_n,
  input  logic                           enable,          // Step enable
  
  // Streaming Activation Input (Parallel 8 rows)
  input  logic                           valid_in,
  input  wire logic [ARRAY_ROWS-1:0][7:0]     data_in,
  output logic                           ready_out,
  
  // Skewed Activation Outputs to PE Array
  output logic [ARRAY_ROWS-1:0]          valid_out,
  output logic [ARRAY_ROWS-1:0][7:0]     data_out
);

  // Ready is high whenever enable is high
  assign ready_out = enable;

  // --------------------------------------------------------------------------
  // Shift Register Pipelines: Row i has depth i (0 <= i < ARRAY_ROWS)
  // --------------------------------------------------------------------------
  genvar r;
  generate
    for (r = 0; r < ARRAY_ROWS; r = r + 1) begin : gen_skew_row
      if (r == 0) begin : gen_row0
        // Row 0 has 0 delay cycles
        assign data_out[0]  = data_in[0];
        assign valid_out[0] = valid_in & enable;
      end else begin : gen_row_delayed
        // Row r has r register stages
        logic [r-1:0][7:0] sr_data;
        logic [r-1:0]      sr_val;

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            sr_data <= '0;
            sr_val  <= '0;
          end else if (enable) begin
            sr_val[0]  <= valid_in;
            sr_data[0] <= data_in[r];
            for (int k = 1; k < r; k = k + 1) begin
              sr_val[k]  <= sr_val[k-1];
              sr_data[k] <= sr_data[k-1];
            end
          end
        end

        assign data_out[r]  = sr_data[r-1];
        assign valid_out[r] = sr_val[r-1];
      end
    end
  endgenerate

endmodule
