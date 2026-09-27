// ============================================================================
// File: activation_unit.sv
// Designer: Abhijit Karale
// Module: activation_unit
// Target: SkyWater 130nm @ 200 MHz
// Description: Pipelined post-processing activation unit supporting Bypass,
//              ReLU, Leaky ReLU, and Saturation/Quantization to INT8/FP8.
// ============================================================================

`timescale 1ns/1ps

module activation_unit
  import systolic_pkg::*;
(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,
  
  input  logic [1:0]         prec_mode,       // INT8, FP8_E4M3, FP8_E5M2
  input  logic [1:0]         act_mode,        // BYPASS, RELU, LEAKY_RELU, CLIP
  
  input  logic               valid_in,
  input  logic signed [31:0] data_in,
  
  output logic               valid_out,
  output logic signed [31:0] data_out_raw,    // 32-bit activated value
  output logic [7:0]         data_out_quant   // 8-bit quantized/saturated value
);

  wire is_int_mode = (prec_mode == PREC_INT8);
  wire is_e4m3     = (prec_mode == PREC_FP8_E4M3);
  wire is_e5m2     = (prec_mode == PREC_FP8_E5M2);

  // --------------------------------------------------------------------------
  // Stage 1: Activation Function Calculation (Combinational)
  // --------------------------------------------------------------------------
  logic signed [31:0] act_raw_comb;
  logic [7:0]         quant_comb;

  // --- INT8 Activation Datapath ---
  logic signed [31:0] int_act;
  logic [7:0]         int_quant;

  always_comb begin
    case (act_mode)
      ACT_BYPASS:     int_act = data_in;
      ACT_RELU:       int_act = (data_in < 32'sd0) ? 32'sd0 : data_in;
      ACT_LEAKY_RELU: int_act = (data_in < 32'sd0) ? (data_in >>> 3) : data_in;
      ACT_CLIP: begin
        if (data_in > 32'sd127)        int_act = 32'sd127;
        else if (data_in < -32'sd128)  int_act = -32'sd128;
        else                           int_act = data_in;
      end
      default:        int_act = data_in;
    endcase

    // INT8 Quantization with saturation clamping [-128, +127]
    if (int_act > 32'sd127) begin
      int_quant = 8'sd127;
    end else if (int_act < -32'sd128) begin
      int_quant = -8'sd128;
    end else begin
      int_quant = int_act[7:0];
    end
  end

  // --- FP32/FP8 Activation Datapath ---
  logic [31:0] fp_act;
  logic [7:0]  fp_quant;

  // Decode FP32 components
  wire        fp_sign = data_in[31];
  wire [7:0]  fp_exp  = data_in[30:23];
  wire [22:0] fp_man  = data_in[22:0];

  always_comb begin
    case (act_mode)
      ACT_BYPASS: fp_act = data_in;
      ACT_RELU: begin
        // If negative and not pure zero, clamp to FP32 positive zero
        if (fp_sign && (data_in[30:0] != 31'b0)) begin
          fp_act = FP32_POS_ZERO;
        end else begin
          fp_act = data_in;
        end
      end
      ACT_LEAKY_RELU: begin
        // If negative, divide magnitude by 8 (subtract 3 from exponent)
        if (fp_sign && (data_in[30:0] != 31'b0)) begin
          if (fp_exp > 8'd3) begin
            fp_act = {fp_sign, fp_exp - 8'd3, fp_man};
          end else begin
            fp_act = FP32_POS_ZERO; // Underflow to zero
          end
        end else begin
          fp_act = data_in;
        end
      end
      ACT_CLIP: fp_act = data_in;
      default:  fp_act = data_in;
    endcase

    // FP32 to FP8 Quantization / Downcast
    if (is_e4m3) begin
      // Target E4M3: Bias = 7, Exp bits = 4, Man bits = 3. Max finite = 448
      // FP32 exponent bias is 127. Target exponent is (fp_exp - 127 + 7) = fp_exp - 120
      logic signed [9:0] target_exp;
      target_exp = $signed({2'b00, fp_exp}) - 10'sd120;

      if (fp_exp == 8'h00 || target_exp < 0) begin
        // Underflow to zero
        fp_quant = {fp_sign, 7'b0};
      end else if (target_exp >= 15) begin
        // Saturation to E4M3 maximum finite (+/- 448)
        fp_quant = fp_sign ? FP8_E4M3_MAX_NEG : FP8_E4M3_MAX_POS;
      end else begin
        // Normalized E4M3: take top 3 bits of FP32 mantissa with rounding
        logic [2:0] man_rounded;
        man_rounded = fp_man[22:20] + fp_man[19]; // Round to nearest
        fp_quant    = {fp_sign, target_exp[3:0], man_rounded};
      end

    end else begin
      // Target E5M2: Bias = 15, Exp bits = 5, Man bits = 2. Max finite = 57344
      // Target exponent is (fp_exp - 127 + 15) = fp_exp - 112
      logic signed [9:0] target_exp;
      target_exp = $signed({2'b00, fp_exp}) - 10'sd112;

      if (fp_exp == 8'h00 || target_exp < 0) begin
        fp_quant = {fp_sign, 7'b0};
      end else if (target_exp >= 31) begin
        // Saturation to E5M2 maximum finite (+/- 57344)
        fp_quant = fp_sign ? FP8_E5M2_MAX_NEG : FP8_E5M2_MAX_POS;
      end else begin
        logic [1:0] man_rounded;
        man_rounded = fp_man[22:21] + fp_man[20];
        fp_quant    = {fp_sign, target_exp[4:0], man_rounded};
      end
    end
  end

  // Multiplex INT8 and FP8 activation outputs
  always_comb begin
    if (is_int_mode) begin
      act_raw_comb = int_act;
      quant_comb   = int_quant;
    end else begin
      act_raw_comb = fp_act;
      quant_comb   = fp_quant;
    end
  end

  // --------------------------------------------------------------------------
  // Stage 2: Output Pipeline Register
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out      <= 1'b0;
      data_out_raw   <= 32'sd0;
      data_out_quant <= 8'h00;
    end else if (enable) begin
      valid_out      <= valid_in;
      data_out_raw   <= act_raw_comb;
      data_out_quant <= quant_comb;
    end
  end

endmodule
