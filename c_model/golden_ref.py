#!/usr/bin/env python3
# ============================================================================
# File: golden_ref.py
# Designer: Abhijit Karale
# Description: Python/NumPy bit-exact golden reference generator for the
#              INT8/FP8 Weight-Stationary Systolic Array AI Accelerator.
# ============================================================================

import numpy as np
import struct
import math

ROWS = 8
COLS = 8

# Precision modes
PREC_INT8 = 0
PREC_FP8_E4M3 = 1
PREC_FP8_E5M2 = 2

# Activation modes
ACT_BYPASS = 0
ACT_RELU = 1
ACT_LEAKY_RELU = 2
ACT_CLIP = 3

def decode_fp8_e4m3(byte_val):
    sign = (byte_val >> 7) & 1
    exp = (byte_val >> 3) & 0x0F
    man = byte_val & 0x07

    if exp == 15 and man == 7:
        return float('nan')
    if (byte_val & 0x7F) == 0:
        return -0.0 if sign else 0.0

    if exp == 0:
        val = math.ldexp(man / 8.0, -6)
    else:
        val = math.ldexp(1.0 + (man / 8.0), exp - 7)
    return -val if sign else val

def decode_fp8_e5m2(byte_val):
    sign = (byte_val >> 7) & 1
    exp = (byte_val >> 2) & 0x1F
    man = byte_val & 0x03

    if exp == 31:
        if man == 0:
            return float('-inf') if sign else float('inf')
        return float('nan')
    if (byte_val & 0x7F) == 0:
        return -0.0 if sign else 0.0

    if exp == 0:
        val = math.ldexp(man / 4.0, -14)
    else:
        val = math.ldexp(1.0 + (man / 4.0), exp - 15)
    return -val if sign else val

def quantize_fp32_to_fp8_e4m3(val):
    if math.isnan(val):
        return 0x7F
    sign = 1 if math.copysign(1.0, val) < 0 else 0
    abs_val = abs(val)
    if abs_val == 0.0:
        return 0x80 if sign else 0x00
    if abs_val >= 448.0:
        return 0xFE if sign else 0x7E

    frac, exp = math.frexp(abs_val)
    e_val = exp - 1
    e_biased = e_val + 7

    if e_biased <= 0:
        m = int(round(abs_val / math.ldexp(1.0, -6) * 8.0))
        m = min(7, max(0, m))
        return (sign << 7) | m
    elif e_biased >= 15:
        return 0xFE if sign else 0x7E
    else:
        m = int(round((frac * 2.0 - 1.0) * 8.0))
        if m >= 8:
            m = 0
            e_biased += 1
        if e_biased >= 15:
            return 0xFE if sign else 0x7E
        return (sign << 7) | ((e_biased & 0x0F) << 3) | (m & 0x07)

def golden_gemm_int8(A, W, act_mode=ACT_BYPASS):
    """
    Bit-exact INT8 GEMM: C = A @ W
    A: 8x8 signed int8
    W: 8x8 signed int8
    """
    A_s32 = A.astype(np.int32)
    W_s32 = W.astype(np.int32)
    C_raw = np.matmul(A_s32, W_s32)

    if act_mode == ACT_RELU:
        C_act = np.maximum(0, C_raw)
    elif act_mode == ACT_LEAKY_RELU:
        C_act = np.where(C_raw >= 0, C_raw, np.right_shift(C_raw, 3))
    elif act_mode == ACT_CLIP:
        C_act = np.clip(C_raw, -128, 127)
    else:
        C_act = C_raw

    C_quant = np.clip(C_act, -128, 127).astype(np.int8)
    return C_act, C_quant

def golden_gemm_fp8(A_bytes, W_bytes, prec_mode=PREC_FP8_E4M3, act_mode=ACT_BYPASS):
    """
    Bit-exact FP8 GEMM
    """
    decoder = decode_fp8_e4m3 if prec_mode == PREC_FP8_E4M3 else decode_fp8_e5m2
    A_float = np.zeros((ROWS, ROWS), dtype=np.float32)
    W_float = np.zeros((ROWS, COLS), dtype=np.float32)

    for i in range(ROWS):
        for j in range(ROWS):
            A_float[i, j] = decoder(int(A_bytes[i, j]))
            W_float[i, j] = decoder(int(W_bytes[i, j]))

    C_raw = np.matmul(A_float, W_float)

    if act_mode == ACT_RELU:
        C_act = np.maximum(0.0, C_raw)
    elif act_mode == ACT_LEAKY_RELU:
        C_act = np.where(C_raw >= 0.0, C_raw, C_raw * 0.125)
    else:
        C_act = C_raw

    C_quant = np.zeros((ROWS, COLS), dtype=np.uint8)
    for i in range(ROWS):
        for j in range(COLS):
            C_quant[i, j] = quantize_fp32_to_fp8_e4m3(C_act[i, j])

    return C_act, C_quant

def self_test():
    print("[Python Golden Model] Running verification self-test...")
    np.random.seed(42)

    # Test 1: INT8 GEMM Identity Test
    A = np.random.randint(-128, 127, size=(8, 8), dtype=np.int8)
    W = np.eye(8, dtype=np.int8)
    C_act, C_quant = golden_gemm_int8(A, W, ACT_BYPASS)
    assert np.array_equal(A, C_quant), "Identity test failed!"
    print("  [PASS] INT8 Identity GEMM verified.")

    # Test 2: INT8 ReLU Test
    A_neg = -np.abs(A)
    C_act, C_quant = golden_gemm_int8(A_neg, W, ACT_RELU)
    assert np.all(C_act == 0), "ReLU negative suppression failed!"
    print("  [PASS] INT8 ReLU suppression verified.")

    # Test 3: FP8 E4M3 Decode & Multiply Test
    A_fp8 = np.full((8, 8), 0x38, dtype=np.uint8) # 1.0 in E4M3 (E=7, M=0)
    W_fp8 = np.full((8, 8), 0x40, dtype=np.uint8) # 2.0 in E4M3 (E=8, M=0)
    C_act_fp8, C_quant_fp8 = golden_gemm_fp8(A_fp8, W_fp8, PREC_FP8_E4M3, ACT_BYPASS)
    # 1.0 * 2.0 * 8 items = 16.0
    expected = 16.0
    assert np.allclose(C_act_fp8, expected), f"FP8 Expected {expected}, got {C_act_fp8[0,0]}"
    print("  [PASS] FP8 E4M3 GEMM verified (1.0 x 2.0 x 8 = 16.0).")

    print("[Python Golden Model] All self-tests passed cleanly!\n")

if __name__ == '__main__':
    self_test()
