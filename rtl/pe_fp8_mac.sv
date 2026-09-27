// ============================================================================
// File: pe_fp8_mac.sv
// Designer: Abhijit Karale
// Module: pe_fp8_mac
// Target: SkyWater 130nm @ 200 MHz
// Description: Synthesizable dual-precision FP8 (E4M3 / E5M2) Multiply-
//              Accumulate unit with IEEE-754 FP32 accumulation and operand
//              isolation for zero-toggle low-power operation.
// ============================================================================

`timescale 1ns/1ps

module pe_fp8_mac
  import systolic_pkg::*;
(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,       // Datapath enable
  input  logic               isolate,      // Force datapath inputs to 0
  input  logic [1:0]         prec_mode,    // PREC_FP8_E4M3 or PREC_FP8_E5M2
  input  logic [7:0]         a_in,         // Activation input (FP8)
  input  logic [7:0]         w_in,         // Weight input (FP8)
  input  logic [31:0]        psum_in,      // Incoming 32-bit FP32 partial sum
  output logic [31:0]        psum_out,     // Outgoing 32-bit FP32 partial sum
  output logic               invalid_flag  // NaN or arithmetic error flag
);

  // --------------------------------------------------------------------------
  // Low-Power Operand Isolation
  // Suppresses multiplier switching toggle whenever FP8 MAC is inactive
  // --------------------------------------------------------------------------
  logic [7:0] a_gated;
  logic [7:0] w_gated;
  wire gate_operands = ~enable | isolate;

  always_comb begin
    if (gate_operands) begin
      a_gated = 8'h00;
      w_gated = 8'h00;
    end else begin
      a_gated = a_in;
      w_gated = w_in;
    end
  end

  // --------------------------------------------------------------------------
  // FP8 Unpack & Format Decoding (E4M3 vs E5M2)
  // --------------------------------------------------------------------------
  logic        sign_a, sign_w;
  logic signed [6:0] exp_a, exp_w; // Unbiased signed exponent (-20 to +20)
  logic [3:0]  man_a, man_w;       // 4-bit mantissa with leading bit: [3].[2:0]
  logic        zero_a, zero_w;
  logic        nan_a, nan_w;
  logic        inf_a, inf_w;

  always_comb begin
    sign_a = a_gated[7];
    sign_w = w_gated[7];

    if (prec_mode == PREC_FP8_E4M3) begin
      // E4M3: [7]=Sign, [6:3]=Exp, [2:0]=Mantissa. Bias = 7
      // Special: E=15, M=7 is NaN. No Inf in OCP E4M3.
      nan_a  = (a_gated[6:3] == 4'hF) && (a_gated[2:0] == 3'b111);
      nan_w  = (w_gated[6:3] == 4'hF) && (w_gated[2:0] == 3'b111);
      inf_a  = 1'b0;
      inf_w  = 1'b0;
      zero_a = (a_gated[6:0] == 7'b000_0000);
      zero_w = (w_gated[6:0] == 7'b000_0000);

      // Exponent decode:
      if (a_gated[6:3] == 4'b0000) begin
        // Subnormal: effective exponent is 1 - 7 = -6
        exp_a = -7'sd6;
        man_a = {1'b0, a_gated[2:0]};
      end else begin
        // Normal: exponent is E - 7
        exp_a = $signed({3'b000, a_gated[6:3]}) - 7'sd7;
        man_a = {1'b1, a_gated[2:0]};
      end

      if (w_gated[6:3] == 4'b0000) begin
        exp_w = -7'sd6;
        man_w = {1'b0, w_gated[2:0]};
      end else begin
        exp_w = $signed({3'b000, w_gated[6:3]}) - 7'sd7;
        man_w = {1'b1, w_gated[2:0]};
      end

    end else begin
      // E5M2: [7]=Sign, [6:2]=Exp, [1:0]=Mantissa. Bias = 15
      // Special: E=31, M=0 is Inf; E=31, M!=0 is NaN.
      nan_a  = (a_gated[6:2] == 5'b11111) && (a_gated[1:0] != 2'b00);
      nan_w  = (w_gated[6:2] == 5'b11111) && (w_gated[1:0] != 2'b00);
      inf_a  = (a_gated[6:2] == 5'b11111) && (a_gated[1:0] == 2'b00);
      inf_w  = (w_gated[6:2] == 5'b11111) && (w_gated[1:0] == 2'b00);
      zero_a = (a_gated[6:0] == 7'b000_0000);
      zero_w = (w_gated[6:0] == 7'b000_0000);

      if (a_gated[6:2] == 5'b00000) begin
        // Subnormal: effective exponent is 1 - 15 = -14
        exp_a = -7'sd14;
        man_a = {1'b0, a_gated[1:0], 1'b0};
      end else begin
        // Normal: exponent is E - 15
        exp_a = $signed({2'b00, a_gated[6:2]}) - 7'sd15;
        man_a = {1'b1, a_gated[1:0], 1'b0};
      end

      if (w_gated[6:2] == 5'b00000) begin
        exp_w = -7'sd14;
        man_w = {1'b0, w_gated[1:0], 1'b0};
      end else begin
        exp_w = $signed({2'b00, w_gated[6:2]}) - 7'sd15;
        man_w = {1'b1, w_gated[1:0], 1'b0};
      end
    end
  end

  // --------------------------------------------------------------------------
  // Multiplier Core: Sign, Mantissa Product & Exponent Addition
  // --------------------------------------------------------------------------
  logic        prod_sign;
  logic [7:0]  prod_man_raw; // 4-bit x 4-bit unsigned product [7:0]
  logic signed [7:0] prod_exp_raw;
  logic        prod_is_zero;
  logic        prod_is_nan;
  logic        prod_is_inf;

  always_comb begin
    prod_sign     = sign_a ^ sign_w;
    prod_man_raw  = man_a * man_w;
    prod_exp_raw  = exp_a + exp_w;
    prod_is_zero  = zero_a | zero_w | (prod_man_raw == 8'h00);
    prod_is_nan   = nan_a | nan_w | ((inf_a & zero_w) | (inf_w & zero_a));
    prod_is_inf   = (inf_a | inf_w) & ~prod_is_nan;
  end

  // --------------------------------------------------------------------------
  // Normalize Product to IEEE-754 FP32
  // Format: [31] Sign, [30:23] Exp (bias 127), [22:0] Mantissa
  // --------------------------------------------------------------------------
  logic [31:0] prod_fp32;

  always_comb begin
    if (prod_is_nan) begin
      prod_fp32 = {1'b0, 8'hFF, 1'b1, 22'b0}; // Canonical FP32 NaN
    end else if (prod_is_inf) begin
      prod_fp32 = {prod_sign, 8'hFF, 23'b0};   // FP32 Infinity
    end else if (prod_is_zero) begin
      prod_fp32 = {prod_sign, 8'h00, 23'b0};   // FP32 Zero
    end else begin
      // Product mantissa is in Q2.6 format (range [0, 4))
      // Bit [7] = 2.0 weight, Bit [6] = 1.0 weight
      logic [7:0] norm_man;
      logic signed [8:0] final_exp;
      
      if (prod_man_raw[7]) begin
        // Overflow >= 2.0: Shift right by 1, increment exponent
        norm_man  = prod_man_raw;
        final_exp = $signed({1'b0, prod_exp_raw}) + 9'sd128; // 127 + 1
      end else if (prod_man_raw[6]) begin
        // Normalized [1.0, 2.0): Align as 1.xxxxxx
        norm_man  = prod_man_raw << 1;
        final_exp = $signed({1'b0, prod_exp_raw}) + 9'sd127;
      end else if (prod_man_raw[5]) begin
        norm_man  = prod_man_raw << 2;
        final_exp = $signed({1'b0, prod_exp_raw}) + 9'sd126;
      end else if (prod_man_raw[4]) begin
        norm_man  = prod_man_raw << 3;
        final_exp = $signed({1'b0, prod_exp_raw}) + 9'sd125;
      end else if (prod_man_raw[3]) begin
        norm_man  = prod_man_raw << 4;
        final_exp = $signed({1'b0, prod_exp_raw}) + 9'sd124;
      end else if (prod_man_raw[2]) begin
        norm_man  = prod_man_raw << 5;
        final_exp = $signed({1'b0, prod_exp_raw}) + 9'sd123;
      end else begin
        norm_man  = prod_man_raw << 6;
        final_exp = $signed({1'b0, prod_exp_raw}) + 9'sd122;
      end

      // Clamp exponent bounds for FP32:
      if (final_exp <= 0) begin
        // Underflow to zero
        prod_fp32 = {prod_sign, 31'b0};
      end else if (final_exp >= 255) begin
        // Overflow to infinity
        prod_fp32 = {prod_sign, 8'hFF, 23'b0};
      end else begin
        // norm_man[7] is the implicit 1. Bits [6:0] are the fractional part
        prod_fp32 = {prod_sign, final_exp[7:0], norm_man[6:0], 16'b0};
      end
    end
  end

  // --------------------------------------------------------------------------
  // IEEE-754 FP32 Accumulator: psum_out = psum_in + prod_fp32
  // --------------------------------------------------------------------------
  // Unpack operands
  wire        sign1 = psum_in[31];
  wire [7:0]  exp1  = psum_in[30:23];
  wire [23:0] man1  = (exp1 == 8'h00) ? {1'b0, psum_in[22:0]} : {1'b1, psum_in[22:0]};
  wire        zero1 = (psum_in[30:0] == 31'b0);
  wire        nan1  = (exp1 == 8'hFF) && (psum_in[22:0] != 23'b0);
  wire        inf1  = (exp1 == 8'hFF) && (psum_in[22:0] == 23'b0);

  wire        sign2 = prod_fp32[31];
  wire [7:0]  exp2  = prod_fp32[30:23];
  wire [23:0] man2  = (exp2 == 8'h00) ? {1'b0, prod_fp32[22:0]} : {1'b1, prod_fp32[22:0]};
  wire        zero2 = (prod_fp32[30:0] == 31'b0);
  wire        nan2  = (exp2 == 8'hFF) && (prod_fp32[22:0] != 23'b0);
  wire        inf2  = (exp2 == 8'hFF) && (prod_fp32[22:0] == 23'b0);

  logic [31:0] adder_result;
  logic        adder_invalid;

  always_comb begin
    adder_invalid = nan1 | nan2 | (inf1 & inf2 & (sign1 ^ sign2));

    if (adder_invalid) begin
      adder_result = {1'b0, 8'hFF, 1'b1, 22'b0}; // NaN
    end else if (nan1 | nan2) begin
      adder_result = {1'b0, 8'hFF, 1'b1, 22'b0};
    end else if (inf1) begin
      adder_result = psum_in;
    end else if (inf2) begin
      adder_result = prod_fp32;
    end else if (zero1) begin
      adder_result = prod_fp32;
    end else if (zero2) begin
      adder_result = psum_in;
    end else begin
      // General Floating-Point Addition / Subtraction
      logic        larger_sign, smaller_sign, res_sign;
      logic [7:0]  larger_exp;
      logic [7:0]  exp_diff;
      logic [27:0] larger_man, smaller_man, smaller_shifted;
      logic [28:0] sum_man;
      logic        eff_sub;

      if (exp1 > exp2 || (exp1 == exp2 && man1 >= man2)) begin
        larger_sign  = sign1;
        smaller_sign = sign2;
        larger_exp   = exp1;
        exp_diff     = exp1 - exp2;
        larger_man   = {man1, 4'b0};
        smaller_man  = {man2, 4'b0};
      end else begin
        larger_sign  = sign2;
        smaller_sign = sign1;
        larger_exp   = exp2;
        exp_diff     = exp2 - exp1;
        larger_man   = {man2, 4'b0};
        smaller_man  = {man1, 4'b0};
      end

      eff_sub = larger_sign ^ smaller_sign;

      // Mantissa alignment (shift smaller mantissa right)
      if (exp_diff > 8'd27) begin
        smaller_shifted = 28'b0;
      end else begin
        smaller_shifted = smaller_man >> exp_diff;
      end

      if (eff_sub) begin
        sum_man  = {1'b0, larger_man} - {1'b0, smaller_shifted};
        res_sign = larger_sign;
      end else begin
        sum_man  = {1'b0, larger_man} + {1'b0, smaller_shifted};
        res_sign = larger_sign;
      end

      // Renormalization and Rounding (Round to Nearest Even)
      if (sum_man == 29'b0) begin
        adder_result = 32'b0;
      end else if (sum_man[28]) begin
        // Overflow in mantissa addition: shift right by 1
        logic [7:0] res_exp;
        res_exp = larger_exp + 8'd1;
        if (res_exp == 8'hFF) begin
          adder_result = {res_sign, 8'hFF, 23'b0}; // Overflow to Inf
        end else begin
          adder_result = {res_sign, res_exp, sum_man[27:5]};
        end
      end else begin
        // Leading zero count to renormalize
        logic [4:0] lzc;
        logic [27:0] norm_shifted;
        logic [8:0]  calc_exp;

        // Priority encoder for leading zero detection
        if      (sum_man[27]) lzc = 5'd0;
        else if (sum_man[26]) lzc = 5'd1;
        else if (sum_man[25]) lzc = 5'd2;
        else if (sum_man[24]) lzc = 5'd3;
        else if (sum_man[23]) lzc = 5'd4;
        else if (sum_man[22]) lzc = 5'd5;
        else if (sum_man[21]) lzc = 5'd6;
        else if (sum_man[20]) lzc = 5'd7;
        else if (sum_man[19]) lzc = 5'd8;
        else if (sum_man[18]) lzc = 5'd9;
        else if (sum_man[17]) lzc = 5'd10;
        else if (sum_man[16]) lzc = 5'd11;
        else if (sum_man[15]) lzc = 5'd12;
        else if (sum_man[14]) lzc = 5'd13;
        else if (sum_man[13]) lzc = 5'd14;
        else if (sum_man[12]) lzc = 5'd15;
        else if (sum_man[11]) lzc = 5'd16;
        else if (sum_man[10]) lzc = 5'd17;
        else if (sum_man[9])  lzc = 5'd18;
        else if (sum_man[8])  lzc = 5'd19;
        else if (sum_man[7])  lzc = 5'd20;
        else if (sum_man[6])  lzc = 5'd21;
        else if (sum_man[5])  lzc = 5'd22;
        else                  lzc = 5'd23;

        norm_shifted = sum_man[27:0] << lzc;
        calc_exp     = $signed({1'b0, larger_exp}) - $signed({4'b0, lzc});

        if (calc_exp <= 0) begin
          adder_result = 32'b0; // Underflow to zero
        end else begin
          adder_result = {res_sign, calc_exp[7:0], norm_shifted[26:4]};
        end
      end
    end
  end

  assign psum_out     = adder_result;
  assign invalid_flag = adder_invalid;

endmodule
