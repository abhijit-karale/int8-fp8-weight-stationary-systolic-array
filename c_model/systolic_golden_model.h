// ============================================================================
// File: systolic_golden_model.h
// Designer: Abhijit Karale
// Description: C++ Header for bit-exact golden reference model of the
//              INT8/FP8 Weight-Stationary Systolic Array AI Accelerator.
// ============================================================================

#ifndef SYSTOLIC_GOLDEN_MODEL_H
#define SYSTOLIC_GOLDEN_MODEL_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Precision modes matching SystemVerilog package
#define PREC_INT8     0
#define PREC_FP8_E4M3 1
#define PREC_FP8_E5M2 2

// Activation modes matching SystemVerilog package
#define ACT_BYPASS     0
#define ACT_RELU       1
#define ACT_LEAKY_RELU 2
#define ACT_CLIP       3

// Dimensions
#define ROWS 8
#define COLS 8

// Golden reference GEMM: C = A x W + Bias/Seed
// Follows Weight-Stationary mapping:
// C[k][j] = sum_{i=0..7} (A[k][i] * W[i][j])
void c_systolic_gemm(
    int prec_mode,
    int act_mode,
    const uint8_t a_matrix[ROWS][ROWS],     // Activations [row][col]
    const uint8_t w_matrix[ROWS][COLS],     // Weights [row][col]
    const int32_t seed_matrix[ROWS][COLS],  // Initial psum (or 0)
    int32_t raw_output[ROWS][COLS],         // 32-bit activated outputs
    uint8_t quant_output[ROWS][COLS]        // 8-bit quantized outputs
);

// DPI-C wrapper functions for direct SystemVerilog import
void c_dpi_int8_gemm(
    int act_mode,
    const uint8_t *a_flat,
    const uint8_t *w_flat,
    int32_t *raw_out_flat,
    uint8_t *quant_out_flat
);

void c_dpi_fp8_gemm(
    int prec_mode,
    int act_mode,
    const uint8_t *a_flat,
    const uint8_t *w_flat,
    int32_t *raw_out_flat,
    uint8_t *quant_out_flat
);

#ifdef __cplusplus
}
#endif

#endif // SYSTOLIC_GOLDEN_MODEL_H
