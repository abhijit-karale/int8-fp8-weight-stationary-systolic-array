// ============================================================================
// File: systolic_golden_model.cpp
// Designer: Abhijit Karale
// Description: C++ Implementation of bit-exact golden reference model for
//              INT8 and FP8 (E4M3/E5M2) Weight-Stationary Systolic Array.
// ============================================================================

#include "systolic_golden_model.h"
#include <cmath>
#include <cstring>
#include <algorithm>

// ----------------------------------------------------------------------------
// Helper: FP8 E4M3 Decode to float
// Format: 1 sign, 4 exponent (bias 7), 3 mantissa. Max finite = 448
// ----------------------------------------------------------------------------
static float decode_fp8_e4m3(uint8_t val) {
    uint8_t sign_bit = (val >> 7) & 0x01;
    uint8_t exp_bits = (val >> 3) & 0x0F;
    uint8_t man_bits = val & 0x07;

    // Check for NaN: E=15, M=7
    if (exp_bits == 0x0F && man_bits == 0x07) {
        return NAN;
    }
    // Check for Zero
    if ((val & 0x7F) == 0) {
        return sign_bit ? -0.0f : 0.0f;
    }

    float mantissa;
    float exponent;

    if (exp_bits == 0) {
        // Subnormal: (-1)^S * 2^(-6) * (M / 8.0)
        mantissa = (float)man_bits / 8.0f;
        exponent = std::ldexp(1.0f, -6);
    } else {
        // Normal: (-1)^S * 2^(E - 7) * (1.0 + M / 8.0)
        mantissa = 1.0f + ((float)man_bits / 8.0f);
        exponent = std::ldexp(1.0f, (int)exp_bits - 7);
    }

    float result = mantissa * exponent;
    return sign_bit ? -result : result;
}

// ----------------------------------------------------------------------------
// Helper: FP8 E5M2 Decode to float
// Format: 1 sign, 5 exponent (bias 15), 2 mantissa. Max finite = 57344
// ----------------------------------------------------------------------------
static float decode_fp8_e5m2(uint8_t val) {
    uint8_t sign_bit = (val >> 7) & 0x01;
    uint8_t exp_bits = (val >> 2) & 0x1F;
    uint8_t man_bits = val & 0x03;

    // Check for NaN or Inf
    if (exp_bits == 0x1F) {
        if (man_bits == 0) return sign_bit ? -INFINITY : INFINITY;
        return NAN;
    }
    // Check for Zero
    if ((val & 0x7F) == 0) {
        return sign_bit ? -0.0f : 0.0f;
    }

    float mantissa;
    float exponent;

    if (exp_bits == 0) {
        // Subnormal: (-1)^S * 2^(-14) * (M / 4.0)
        mantissa = (float)man_bits / 4.0f;
        exponent = std::ldexp(1.0f, -14);
    } else {
        // Normal: (-1)^S * 2^(E - 15) * (1.0 + M / 4.0)
        mantissa = 1.0f + ((float)man_bits / 4.0f);
        exponent = std::ldexp(1.0f, (int)exp_bits - 15);
    }

    float result = mantissa * exponent;
    return sign_bit ? -result : result;
}

// ----------------------------------------------------------------------------
// Helper: Float to FP8 Quantization with Saturation
// ----------------------------------------------------------------------------
static uint8_t quantize_float_to_fp8(float val, int prec_mode) {
    if (std::isnan(val)) return (prec_mode == PREC_FP8_E4M3) ? 0x7F : 0x7E;
    
    uint8_t sign = std::signbit(val) ? 1 : 0;
    float abs_val = std::fabs(val);

    if (prec_mode == PREC_FP8_E4M3) {
        if (abs_val == 0.0f) return sign ? 0x80 : 0x00;
        if (abs_val >= 448.0f) return sign ? 0xFE : 0x7E; // Clamp to max finite

        int exp;
        float frac = std::frexp(abs_val, &exp); // frac in [0.5, 1.0), abs_val = frac * 2^exp
        // In IEEE style: 1.m * 2^(e_val) -> frac * 2 = 1.m, so e_val = exp - 1
        int e_val = exp - 1;
        int e_biased = e_val + 7;

        if (e_biased <= 0) {
            // Subnormal
            int m = (int)std::round(abs_val / std::ldexp(1.0f, -6) * 8.0f);
            if (m > 7) m = 7;
            return (sign << 7) | (uint8_t)m;
        } else if (e_biased >= 15) {
            return sign ? 0xFE : 0x7E;
        } else {
            // Normal
            float m_float = (frac * 2.0f - 1.0f) * 8.0f;
            int m = (int)std::round(m_float);
            if (m >= 8) { m = 0; e_biased++; }
            if (e_biased >= 15) return sign ? 0xFE : 0x7E;
            return (sign << 7) | ((e_biased & 0x0F) << 3) | (m & 0x07);
        }
    } else { // E5M2
        if (abs_val == 0.0f) return sign ? 0x80 : 0x00;
        if (abs_val >= 57344.0f) return sign ? 0xFB : 0x7B; // Clamp to max finite

        int exp;
        float frac = std::frexp(abs_val, &exp);
        int e_val = exp - 1;
        int e_biased = e_val + 15;

        if (e_biased <= 0) {
            int m = (int)std::round(abs_val / std::ldexp(1.0f, -14) * 4.0f);
            if (m > 3) m = 3;
            return (sign << 7) | (uint8_t)m;
        } else if (e_biased >= 31) {
            return sign ? 0xFB : 0x7B;
        } else {
            float m_float = (frac * 2.0f - 1.0f) * 4.0f;
            int m = (int)std::round(m_float);
            if (m >= 4) { m = 0; e_biased++; }
            if (e_biased >= 31) return sign ? 0xFB : 0x7B;
            return (sign << 7) | ((e_biased & 0x1F) << 2) | (m & 0x03);
        }
    }
}

// ----------------------------------------------------------------------------
// Core Matrix Multiplication Engine
// ----------------------------------------------------------------------------
void c_systolic_gemm(
    int prec_mode,
    int act_mode,
    const uint8_t a_matrix[ROWS][ROWS],
    const uint8_t w_matrix[ROWS][COLS],
    const int32_t seed_matrix[ROWS][COLS],
    int32_t raw_output[ROWS][COLS],
    uint8_t quant_output[ROWS][COLS]
) {
    if (prec_mode == PREC_INT8) {
        // --- INT8 Mode Execution ---
        for (int k = 0; k < ROWS; ++k) {
            for (int j = 0; j < COLS; ++j) {
                int32_t acc = seed_matrix ? seed_matrix[k][j] : 0;
                for (int i = 0; i < ROWS; ++i) {
                    int8_t a_val = (int8_t)a_matrix[k][i];
                    int8_t w_val = (int8_t)w_matrix[i][j];
                    acc += (int32_t)a_val * (int32_t)w_val;
                }

                // Activation Unit
                int32_t activated = acc;
                if (act_mode == ACT_RELU) {
                    activated = (acc < 0) ? 0 : acc;
                } else if (act_mode == ACT_LEAKY_RELU) {
                    activated = (acc < 0) ? (acc >> 3) : acc;
                } else if (act_mode == ACT_CLIP) {
                    if (acc > 127) activated = 127;
                    else if (acc < -128) activated = -128;
                }

                raw_output[k][j] = activated;

                // Quantization to 8-bit
                int8_t quant;
                if (activated > 127) quant = 127;
                else if (activated < -128) quant = -128;
                else quant = (int8_t)activated;

                quant_output[k][j] = (uint8_t)quant;
            }
        }
    } else {
        // --- FP8 Mode Execution (E4M3 or E5M2) ---
        for (int k = 0; k < ROWS; ++k) {
            for (int j = 0; j < COLS; ++j) {
                float acc = 0.0f;
                if (seed_matrix) {
                    // Seed interpreted as raw IEEE FP32
                    int32_t seed_bits = seed_matrix[k][j];
                    memcpy(&acc, &seed_bits, sizeof(float));
                }

                for (int i = 0; i < ROWS; ++i) {
                    float a_val = (prec_mode == PREC_FP8_E4M3) ? 
                        decode_fp8_e4m3(a_matrix[k][i]) : decode_fp8_e5m2(a_matrix[k][i]);
                    float w_val = (prec_mode == PREC_FP8_E4M3) ? 
                        decode_fp8_e4m3(w_matrix[i][j]) : decode_fp8_e5m2(w_matrix[i][j]);
                    acc += a_val * w_val;
                }

                // Floating-Point Activation
                float activated = acc;
                if (act_mode == ACT_RELU) {
                    activated = (acc < 0.0f) ? 0.0f : acc;
                } else if (act_mode == ACT_LEAKY_RELU) {
                    activated = (acc < 0.0f) ? (acc * 0.125f) : acc;
                }

                int32_t raw_bits;
                memcpy(&raw_bits, &activated, sizeof(int32_t));
                raw_output[k][j] = raw_bits;

                quant_output[k][j] = quantize_float_to_fp8(activated, prec_mode);
            }
        }
    }
}

// ----------------------------------------------------------------------------
// DPI-C Bridges for SystemVerilog Direct Integration
// ----------------------------------------------------------------------------
extern "C" void c_dpi_int8_gemm(
    int act_mode,
    const uint8_t *a_flat,
    const uint8_t *w_flat,
    int32_t *raw_out_flat,
    uint8_t *quant_out_flat
) {
    uint8_t a_mat[ROWS][ROWS];
    uint8_t w_mat[ROWS][COLS];
    int32_t raw_mat[ROWS][COLS];
    uint8_t quant_mat[ROWS][COLS];

    memcpy(a_mat, a_flat, ROWS * ROWS * sizeof(uint8_t));
    memcpy(w_mat, w_flat, ROWS * COLS * sizeof(uint8_t));

    c_systolic_gemm(PREC_INT8, act_mode, a_mat, w_mat, nullptr, raw_mat, quant_mat);

    memcpy(raw_out_flat, raw_mat, ROWS * COLS * sizeof(int32_t));
    memcpy(quant_out_flat, quant_mat, ROWS * COLS * sizeof(uint8_t));
}

extern "C" void c_dpi_fp8_gemm(
    int prec_mode,
    int act_mode,
    const uint8_t *a_flat,
    const uint8_t *w_flat,
    int32_t *raw_out_flat,
    uint8_t *quant_out_flat
) {
    uint8_t a_mat[ROWS][ROWS];
    uint8_t w_mat[ROWS][COLS];
    int32_t raw_mat[ROWS][COLS];
    uint8_t quant_mat[ROWS][COLS];

    memcpy(a_mat, a_flat, ROWS * ROWS * sizeof(uint8_t));
    memcpy(w_mat, w_flat, ROWS * COLS * sizeof(uint8_t));

    c_systolic_gemm(prec_mode, act_mode, a_mat, w_mat, nullptr, raw_mat, quant_mat);

    memcpy(raw_out_flat, raw_mat, ROWS * COLS * sizeof(int32_t));
    memcpy(quant_out_flat, quant_mat, ROWS * COLS * sizeof(uint8_t));
}
