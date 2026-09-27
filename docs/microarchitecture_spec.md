# INT8/FP8 Weight-Stationary Systolic Array AI Accelerator
## Microarchitectural Specification & Architecture Manual
**Architect & Verification Lead:** Abhijit Karale  
**Target Technology:** SkyWater 130nm (`sky130_fd_sc_hd`) @ 200 MHz ($T_{clk} = 5.0\,\text{ns}$)  
**Target Array Topology:** 8x8 2D Mesh Processing Element Grid  

---

## 1. Executive Architecture Summary

The accelerator is a specialized 2D hardware matrix multiplication engine optimized for edge AI inference and training acceleration. Operating on the **Weight-Stationary (WS)** dataflow principle, weights are held stationary inside Processing Elements (PEs) during dot product accumulation, while activation vectors stream horizontally from the left and partial sums accumulate vertically from top to bottom.

### Key Architectural Highlights:
1. **8x8 PE Grid**: 64 high-efficiency MAC units computing 64 multiply-accumulate operations per clock cycle. At 200 MHz, peak compute throughput is **25.6 GOPS (INT8)** or **12.8 GFLOPS (FP8)**.
2. **Dual-Precision Hardware**:
   - **INT8**: 8-bit signed two's complement multiplication with 32-bit signed accumulation ($[-128, 127] \times [-128, 127] + \text{INT32}$).
   - **FP8 E4M3**: 1-bit sign, 4-bit exponent, 3-bit mantissa (bias 7). Supports subnormal numbers and values up to $\pm 448$.
   - **FP8 E5M2**: 1-bit sign, 5-bit exponent, 2-bit mantissa (bias 15). Supports subnormal numbers, IEEE-754 style infinities and NaNs, up to $\pm 57344$.
   - **Accumulation Format**: Unified 32-bit register holding either INT32 or IEEE-754 single-precision FP32.
3. **Double-Buffered Weight & Input Banks**:
   - Every PE integrates an active weight register (`weight_active`) and a shadow weight register (`weight_shadow`).
   - The shadow register bank can be loaded concurrently via a dedicated streaming channel while active tensor calculations occur without stalling.
   - An atomic single-cycle bank swap (`weight_swap`) switches the active weights with **zero pipeline bubble cycles**.
4. **Pipelined Post-Processing & Activation Engine**:
   - Integrated downstream activation units supporting **Pass-through**, **ReLU**, **Leaky ReLU** (configurable slope), and **Saturation/Clipping** down to 8-bit quantized or 32-bit wide representations.
5. **Low-Power Toggle Reduction Architecture**:
   - Dynamic operand isolation gates multiplier inputs to zero during invalid cycles or zero-valued operands.
   - Integrated Clock Gating (ICG) hooks per PE register stage.
   - Dual-precision datapath silencing (FP8 datapath fully quieted during INT8 execution and vice-versa).

---

## 2. 2D Systolic Array Top-Level Schematic

The 8x8 array receives skewed activation inputs from the West, skewed partial sums (or zero seeds) from the North, and outputs accumulated results to the South. Weights are preloaded into shadow registers vertically.

```
                     Column Partial-Sum Inputs (North: C_in[0..7])
                               [31:0] x 8 (Normally 0)
                                  │   │   │   │   │   │   │   │
                                  ▼   ▼   ▼   ▼   ▼   ▼   ▼   ▼
                     ┌──────────┬───┬───┬───┬───┬───┬───┬───┬───┐
                     │          │C0 │C1 │C2 │C3 │C4 │C5 │C6 │C7 │
                     ├──────────┼───┴───┴───┴───┴───┴───┴───┴───┤
Row Activation       │          │                               │
Inputs (West)        │  Row 0   │ [PE00]─>[PE01]─>[PE02]─> ... ─>[PE07]
  A_in[0] ───────────►(Delay 0) │   │       │       │               │
                     │          │   ▼       ▼       ▼               ▼
  A_in[1] ───────────►(Delay 1) │ [PE10]─>[PE11]─>[PE12]─> ... ─>[PE17]
                     │          │   │       │       │               │
  A_in[2] ───────────►(Delay 2) │   ▼       ▼       ▼               ▼
                     │          │ [PE20]─>[PE21]─>[PE22]─> ... ─>[PE27]
  A_in[3] ───────────►(Delay 3) │   │       │       │               │
                     │          │   ▼       ▼       ▼               ▼
  A_in[4] ───────────►(Delay 4) │ [PE30]─>[PE31]─>[PE32]─> ... ─>[PE37]
                     │          │   │       │       │               │
  A_in[5] ───────────►(Delay 5) │   ▼       ▼       ▼               ▼
                     │          │ [PE40]─>[PE41]─>[PE42]─> ... ─>[PE47]
  A_in[6] ───────────►(Delay 6) │   │       │       │               │
                     │          │   ▼       ▼       ▼               ▼
  A_in[7] ───────────►(Delay 7) │ [PE50]─>[PE51]─>[PE52]─> ... ─>[PE57]
                     │          │   │       │       │               │
                     │  Row 6   │   ▼       ▼       ▼               ▼
                     │          │ [PE60]─>[PE61]─>[PE62]─> ... ─>[PE67]
                     │          │   │       │       │               │
                     │  Row 7   │   ▼       ▼       ▼               ▼
                     │          │ [PE70]─>[PE71]─>[PE72]─> ... ─>[PE77]
                     └──────────┼───┬───┬───┬───┬───┬───┬───┬───┤
                                │   │   │   │   │   │   │   │   │
                                └───┼───┼───┼───┼───┼───┼───┼───┘
                                    ▼   ▼   ▼   ▼   ▼   ▼   ▼   ▼
                               ┌─────────────────────────────────┐
                               │     Column Deskew Buffers       │
                               │  (Delay 7, 6, 5, 4, 3, 2, 1, 0) │
                               └────────────────┬────────────────┘
                                                ▼
                               ┌─────────────────────────────────┐
                               │    Pipelined Activation Unit    │
                               │   (ReLU, Leaky ReLU, Clip/Sat)  │
                               └────────────────┬────────────────┘
                                                ▼
                                   Parallel Result Vector [7:0]
```

---

## 3. Processing Element (PE) Microarchitecture

Each Processing Element $PE_{i,j}$ contains:
- Horizontal activation pass-through register.
- Vertical partial sum accumulation register.
- Double-buffered weight storage (`weight_shadow` + `weight_active`).
- Dual-mode low-power MAC core.

```
                            Vertical Partial Sum In: psum_in [31:0]
                            Vertical Weight In:      weight_in [7:0] (Preload)
                                              │      │
                                              │      ▼
                                              │   ┌────────────────────┐
                                              │   │ Shadow Weight Reg  │◄── weight_en
                                              │   │ (weight_shadow)    │
                                              │   └─────────┬──────────┘
                                              │             │
                                              │             ▼ (weight_swap)
                                              │   ┌────────────────────┐
                                              │   │ Active Weight Reg  │
                                              │   │ (weight_active)    │
                                              │   └─────────┬──────────┘
                                              │             │
                                              │     W_is_zero?
Horizontal                                    │             │
Activation In ───►[ Operand Isolation ]──────┼─────────┐   │
a_in [7:0]        [ Clamp to 0 if idle ]      │         │   │
     │                      │                 │         ▼   ▼
     │                      ▼                 │     ┌──────────────┐
     │            ┌──────────────────┐        │     │  Precision   │◄── prec_mode
     │            │ a_reg Register   │        │     │  Multiplexed │    (INT8 / FP8)
     │            └─────────┬────────┘        │     │   MAC Core   │
     │                      │                 │     └───────┬──────┘
     │                      ▼                 │             │ product [31:0]
     │                 a_out [7:0]            │             │
     │               (to East PE)             ▼             ▼
     │                                     ┌──────────────────┐
     │                                     │ 32-bit INT/FP32  │
     │                                     │ Accumulator Tree │
     │                                     └────────┬─────────┘
     │                                              │
     │                                              ▼
     │                                     ┌──────────────────┐
     │                                     │ psum_reg [31:0]  │
     │                                     └────────┬─────────┘
     │                                              │
     │                                              ▼
     ▼                                        psum_out [31:0]
   weight_out [7:0]                            (to South PE)
   (to South PE for cascade loading)
```

### Weight Shadow-Bank Isolation:
- Loading into `weight_shadow` is conditioned solely on `weight_load_en`.
- `weight_active` updates **strictly** when `weight_swap` is asserted on a positive clock edge.
- This creates total electrical and logical decoupling: changing `weight_shadow` causes 0 toggle propagation into the MAC logic.

---

## 4. Arithmetic Datapath Specification

### 4.1 INT8 Datapath
- **Multiplication**: $A \times W$ where $A, W \in [-128, 127]$ (two's complement signed 8-bit).
  $$\text{prod}_{16} = A[7:0] \times W[7:0]$$
- **Sign-Extension & Accumulation**:
  $$\text{psum}_{\text{next}}[31:0] = \text{psum}_{\text{in}}[31:0] + \text{sign\_ext}_{32}(\text{prod}_{16})$$
- Accumulator dynamic range: $\pm 2.14 \times 10^9$, guaranteeing over 130,000 continuous dot-product operations before any potential overflow.

### 4.2 FP8 Datapath (E4M3 and E5M2)

#### FP8 Formats Summary:
| Format | Sign ($S$) | Exponent ($E$) | Mantissa ($M$) | Bias ($B$) | Min Normal | Max Finite | Special Values |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **E4M3** | 1 bit [7] | 4 bits [6:3] | 3 bits [2:0] | 7 | $2^{-6} \approx 0.0156$ | 448 ($E=15, M=6$) | $E=15, M=7 \implies \text{NaN}$ |
| **E5M2** | 1 bit [7] | 5 bits [6:2] | 2 bits [1:0] | 15 | $2^{-14} \approx 6.1 \times 10^{-5}$ | 57344 ($E=30, M=3$) | $E=31, M=0 \implies \pm\infty$; $M\neq 0 \implies \text{NaN}$ |

#### Floating-Point Multiplication Algorithm:
1. **Unpack & Subnormal Detection**:
   - Extract sign: $S_A, S_B$. Product sign: $S_P = S_A \oplus S_B$.
   - For E4M3:
     - If $E = 0$: Subnormal; effective exponent is $-6$, implicit mantissa bit is $0$. $M_{eff} = \{1'b0, M\}$.
     - If $E > 0$: Normal; effective exponent is $E - 7$, implicit mantissa bit is $1$. $M_{eff} = \{1'b1, M\}$.
   - For E5M2:
     - If $E = 0$: Subnormal; effective exponent is $-14$, implicit mantissa bit is $0$. $M_{eff} = \{1'b0, M\}$.
     - If $E > 0$: Normal; effective exponent is $E - 15$, implicit mantissa bit is $1$. $M_{eff} = \{1'b1, M\}$.
2. **Mantissa Multiplication**:
   - E4M3: 4-bit $\times$ 4-bit unsigned multiplication $\to$ 8-bit intermediate mantissa.
   - E5M2: 3-bit $\times$ 3-bit unsigned multiplication $\to$ 6-bit intermediate mantissa.
3. **Exponent Addition**:
   - $E_P = E_A^{eff} + E_B^{eff}$.
4. **Intermediate Normalization & FP32 Expansion**:
   - The product is normalized and mapped directly into standard IEEE-754 Single Precision (FP32: 1 sign, 8 exponent, 23 mantissa) without precision loss.
   - $E_{FP32} = E_P + 127 + \text{norm\_shift}$.
5. **FP32 Addition**:
   - High-speed 32-bit floating point adder computes $\text{psum}_{\text{next}} = \text{psum}_{\text{in}} + \text{prod}_{FP32}$.
   - Includes exponent alignment, mantissa addition/subtraction, leading-zero detection, normalization, and round-to-nearest-even (RNE).

---

## 5. Systolic Timing, Skewing & Bubble-Free Handshake

### 5.1 Diagonal Wavefront Scheduling
For an $N \times N$ array ($N=8$):
- **Activation Input Skew**:
  Row $i$ of the activation matrix $A$ is delayed by $i$ clock cycles:
  $$\Delta t_{\text{skew\_in}}(i) = i \quad (i \in [0..7])$$
- **Computation Schedule**:
  Processing Element $PE_{i,j}$ receives activation $A_{i, k}$ and partial sum from $PE_{i-1, j}$ at cycle:
  $$t_{\text{comp}}(i, j, k) = t_0 + i + j + k$$
- **Partial Sum Emergence**:
  The final accumulated value for output matrix element $C_{k, j}$ leaves row 7 at cycle:
  $$t_{\text{out\_raw}}(k, j) = t_0 + k + 7 + j$$
- **Deskewing Buffer**:
  To emit an entire row vector $C_{k, [0..7]}$ concurrently on the output bus, column $j$ is delayed by:
  $$\Delta t_{\text{deskew}}(j) = 7 - j \quad (j \in [0..7])$$
  Resulting in synchronous vector emergence at cycle:
  $$t_{\text{vector\_ready}}(k) = t_0 + k + 14$$

### 5.2 Bubble-Free Double Buffering Protocol
- Total latency for $8 \times 8$ matrix multiply: 8 cycles of streaming + 14 cycles of systolic propagation = 22 cycles.
- While the active matrix multiplication is executing, the weight streamer loads the shadow registers of all 64 PEs in 8 streaming cycles ($8 \times 8$ parallel/serial load).
- Once the last activation enters the array ($T_K$), the controller asserts `weight_swap` on the boundary of the next tile.
- **Bubble Count: 0 cycles**. The systolic array achieves $100\%$ datapath utilization across continuous tensor streams.

---

## 6. Activation & Saturation Pipeline

Each column output passes through a configurable post-processing activation stage:
1. **Pass-Through**: Returns 32-bit partial sum unmodified.
2. **ReLU**:
   $$\text{out} = \begin{cases} \text{psum}, & \text{if } \text{psum} \ge 0 \\ 0, & \text{if } \text{psum} < 0 \end{cases}$$
3. **Leaky ReLU**:
   $$\text{out} = \begin{cases} \text{psum}, & \text{if } \text{psum} \ge 0 \\ \text{psum} \gg \alpha, & \text{if } \text{psum} < 0 \quad (\alpha=3 \implies \text{slope } 0.125) \end{cases}$$
4. **Saturation & Quantization (Saturate to INT8 / FP8)**:
   - For INT8: Clamps 32-bit signed accumulator to $[-128, +127]$.
   - For FP8: Converts FP32 down to E4M3 or E5M2 with overflow clamping to max finite values and rounding to nearest even.

---

## 7. Power Optimization Architecture (SkyWater 130nm)

1. **Operand Isolation**:
   - Multiplier toggle suppression: if $A = 0$ or $W = 0$, the multiplier input registers are clamped to $0$ via AND gates before reaching the adder tree.
2. **Integrated Clock Gating (ICG)**:
   - Latched clock gating cells (`sky130_fd_sc_hd__dlclkp_1`) disable clock distribution to shadow registers during the compute phase and freeze PE pipeline registers when input valid is deasserted.
3. **Mode-Dependent Silencing**:
   - In INT8 mode, the FP8 exponent adder, normalizer, and FP32 aligner receive static 0s, resulting in zero dynamic switching power in the floating-point logic.
