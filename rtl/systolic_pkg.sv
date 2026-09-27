// ============================================================================
// File: systolic_pkg.sv
// Designer: Abhijit Karale
// Module: systolic_pkg
// Target: SkyWater 130nm @ 200 MHz
// Description: Package defining global types, parameters, enums, and utility
//              functions for the INT8/FP8 Weight-Stationary Systolic Array.
// ============================================================================

`ifndef SYSTOLIC_PKG_SV
`define SYSTOLIC_PKG_SV

package systolic_pkg;

  // --------------------------------------------------------------------------
  // Array & Datapath Parameters
  // --------------------------------------------------------------------------
  localparam int ARRAY_ROWS       = 8;
  localparam int ARRAY_COLS       = 8;
  localparam int DATA_WIDTH       = 8;
  localparam int ACC_WIDTH        = 32;
  localparam int INT16_WIDTH      = 16;
  
  // AXI-Stream bus bit widths
  localparam int ACT_BUS_WIDTH    = ARRAY_ROWS * DATA_WIDTH; // 64 bits
  localparam int WT_BUS_WIDTH     = ARRAY_COLS * DATA_WIDTH; // 64 bits
  localparam int OUT_RAW_WIDTH    = ARRAY_COLS * ACC_WIDTH;  // 256 bits
  localparam int OUT_QUANT_WIDTH  = ARRAY_COLS * DATA_WIDTH; // 64 bits

  // --------------------------------------------------------------------------
  // Precision Modes
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    PREC_INT8     = 2'b00,  // Two's complement signed 8-bit integer
    PREC_FP8_E4M3 = 2'b01,  // OCP FP8 E4M3: 1 sign, 4 exp (bias 7), 3 mantissa
    PREC_FP8_E5M2 = 2'b10,  // OCP/IEEE FP8 E5M2: 1 sign, 5 exp (bias 15), 2 mantissa
    PREC_RESERVED = 2'b11
  } prec_mode_e;

  // --------------------------------------------------------------------------
  // Activation Modes
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    ACT_BYPASS     = 2'b00,  // Linear pass-through (no activation)
    ACT_RELU       = 2'b01,  // ReLU: max(0, x)
    ACT_LEAKY_RELU = 2'b10,  // Leaky ReLU: x >= 0 ? x : (x >>> 3)
    ACT_CLIP       = 2'b11   // Saturation / Clipping to configured bounds
  } act_mode_e;

  // --------------------------------------------------------------------------
  // FP8 E4M3 Bit Definitions & Constants
  // Format: [7] Sign, [6:3] Exponent, [2:0] Mantissa. Bias = 7
  // --------------------------------------------------------------------------
  localparam int E4M3_SIGN_BIT = 7;
  localparam int E4M3_EXP_BITS = 4;
  localparam int E4M3_MAN_BITS = 3;
  localparam int E4M3_BIAS     = 7;
  localparam logic [7:0] FP8_E4M3_POS_ZERO = 8'h00;
  localparam logic [7:0] FP8_E4M3_NEG_ZERO = 8'h80;
  localparam logic [7:0] FP8_E4M3_MAX_POS  = 8'h7E; // Exponent 15, Mantissa 6 (+448)
  localparam logic [7:0] FP8_E4M3_MAX_NEG  = 8'hFE; // Exponent 15, Mantissa 6 (-448)
  localparam logic [7:0] FP8_E4M3_NAN      = 8'h7F; // Exponent 15, Mantissa 7

  // --------------------------------------------------------------------------
  // FP8 E5M2 Bit Definitions & Constants
  // Format: [7] Sign, [6:2] Exponent, [1:0] Mantissa. Bias = 15
  // --------------------------------------------------------------------------
  localparam int E5M2_SIGN_BIT = 7;
  localparam int E5M2_EXP_BITS = 5;
  localparam int E5M2_MAN_BITS = 2;
  localparam int E5M2_BIAS     = 15;
  localparam logic [7:0] FP8_E5M2_POS_ZERO = 8'h00;
  localparam logic [7:0] FP8_E5M2_NEG_ZERO = 8'h80;
  localparam logic [7:0] FP8_E5M2_POS_INF  = 8'h7C; // Exponent 31, Mantissa 0
  localparam logic [7:0] FP8_E5M2_NEG_INF  = 8'hFC; // Exponent 31, Mantissa 0
  localparam logic [7:0] FP8_E5M2_MAX_POS  = 8'h7B; // Exponent 30, Mantissa 3 (+57344)
  localparam logic [7:0] FP8_E5M2_MAX_NEG  = 8'hFB; // Exponent 30, Mantissa 3 (-57344)

  // --------------------------------------------------------------------------
  // IEEE-754 Single Precision (FP32) Constants
  // Format: [31] Sign, [30:23] Exponent, [22:0] Mantissa. Bias = 127
  // --------------------------------------------------------------------------
  localparam int FP32_EXP_BITS = 8;
  localparam int FP32_MAN_BITS = 23;
  localparam int FP32_BIAS     = 127;
  localparam logic [31:0] FP32_POS_ZERO = 32'h0000_0000;
  localparam logic [31:0] FP32_NEG_ZERO = 32'h8000_0000;
  localparam logic [31:0] FP32_POS_INF  = 32'h7F80_0000;
  localparam logic [31:0] FP32_NEG_INF  = 32'hFF80_0000;

  // --------------------------------------------------------------------------
  // Struct: Decoded FP8 Representation
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic       sign;
    logic [5:0] exp_unbiased; // Signed exponent (-15 to +16)
    logic [4:0] mantissa;     // Mantissa with explicit leading bit [4:0]
    logic       is_zero;
    logic       is_subnormal;
    logic       is_nan;
    logic       is_inf;
  } fp8_decoded_t;

endpackage : systolic_pkg

`endif // SYSTOLIC_PKG_SV
