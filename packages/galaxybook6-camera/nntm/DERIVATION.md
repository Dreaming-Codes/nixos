# What the Windows tone-mapping stage computes

This is the derivation behind `reference.py` and the `nntm` element. It was read out of
Samsung's Windows camera driver (Intel camera driver 71.26100.23.20550); nothing from the
driver was executed. There is no Windows output to compare against, so this document is the
fidelity argument: each formula names where it was read from so it can be checked.

Sources, by short name:

- **nntm.spv**: blob `5536108348999601368` of `intelic_data.bin`, SYCL SPIR-V with the
  kernels `preprocess`, `ltm_gain`, `postprocess`. `%N` is a result id as `spirv-dis` prints it.
- **resize.spv**: blob `18038158106866911913`, kernels `precomputeCoeffs`, `resample_w`,
  `resample_h`.
- **intelic.dll**: the CPU side of the graph runtime. Functions are named by address
  (image base 0x180000000) and by the log string that identifies them.
- **MFT**: `IntelDeviceMFT64.dll`, which holds the parameter kernel `nntm_1_0` and the
  executor that feeds its output to the graph.
- **graph**: `nntm_sycl_onednn` in `intelic_data.bin`, the build the MFT loads (graph id 1).
- **aiqb**: Samsung's tuning file `SC200PC_KAFC917_PTL.aiqb`.

Each kernel exists twice in the SPIR-V (a `__pf_kernel_wrapper` build for rounded ranges and
a plain one). The ids below are from the plain ones: `_ZTS10preprocess` (function
`%_ZTS10preprocess`, ids 457 to 698), `_ZTS8ltm_gain` (4006 to 5531), `_ZTS11postprocess`
(1691 to 2356) and its inner lambda `%1272` (1273 to 1688).

## Arithmetic

Every pixel operation is IEEE half precision (`OpTypeFloat 16`). Each kernel works on one
2x2 block per invocation: rows `2j, 2j+1`, columns `2i, 2i+1`, one chroma pair. All float
operations carry `FPFastMathMode NSZ|AllowRecip|AllowContract|AllowReassoc`, so Intel's GPU
compiler may fuse or reorder them. The reference performs them in the order written, one
rounding per operation.

Constants: `K_Y = 0x1.2ap+0` (1.1640625), `K_Y0 = -0x1.2ap+4` (-18.625),
`K_C = 0x1.248p+0` (1.142578125), `K_C0 = -0x1.248p+4` (-18.28125),
`INV255 = 0x1.01p-8`, `THIRD = 0x1.554p-2`.

## 1. preprocess: NV12 to luma (`to_rgb`, `planes`)

Arguments (ids 457 to 465): input bytes, output halves, `offset[3]` ints, `matrix[9]` floats,
`input_range_restricted`, width, height. Chroma is read at `in + W*H + j*W + 2i` (%528 to
%540), so the stride equals the width.

1. If `input_range_restricted != 0` (%564): `Y = clamp(Y*K_Y + K_Y0, 0, 255)` (%571 to %582)
   and `C = clamp(C*K_C + K_C0, 0, 255)` (%565 to %570).
2. `yn = (Y - offset[0]) * INV255`, `un = (U - offset[1]) * INV255`,
   `vn = (V - offset[2]) * INV255` (%599 to %610).
3. `R = clamp(vn*m2 + (un*m1 + yn*m0), 0, 1)`, G with `m3..m5`, B with `m6..m8`
   (%611 to %628).
4. `luma = (B + (G + R)) * THIRD` (%671 to %673), stored as a W x H half plane.

The guide and the network input are therefore the mean of the clamped RGB channels, not Y.

CPU side: `ZeSyclNNTMPreprocessCalculator::Open` (intelic.dll 0x1800b65f0) divides the nine
matrix entries by entry 0 before they reach the kernel.

## 2. resize: luma to 256x256 (`resize_coeffs`, `resize`)

`ZeSyclPillowResizeCalculator::Process` (0x1800bc710) sets, per axis,
`scale = (float)in / (float)out`, `support = max(1, scale)`,
`ksize = (int)ceil(support)*2 + 1`. `pillow_resize_f` (0x1800c0220) runs `resample_w`
(input to `in_h x 256`) and then `resample_h`.

`precomputeCoeffs` (ids 178 to 288), per output index `xx`, in half precision:

- `center = (xx + 0.5) * scale` (%219 to %221)
- `xmin = clamp(int(center - support + 0.5), 0, in)`, `xmax` likewise with `+ support`
  (%223 to %230), `n = xmax - xmin`
- `w_i = max(0, 1 - |((i + xmin) - center + 0.5) / support|)` (%242 to %253, the division is
  a multiplication by `1/support`, %232)
- `coeff_i = w_i / sum(w)` (%269)

`resample_w` (ids 495 to 578): `out[yy][xx] = sum_i coeff[xx][i] * in[yy][xmin + i]`,
accumulated left to right from zero (%550, %568, %549). `resample_h` (760 to 843) is the same
down the columns.

This is Pillow's antialiased bilinear filter. For 1920x1080 the supports are 7.5 and
4.21875, 17 and 11 taps. In half precision `center` is only exact to 1 above 1024.

## 3. The network

OpenVINO IR v11, `static_coeff_aug25_strongest_haigh_fr_L2_br_p_fp16`, input
`1x1x256x256` FP16 (the resized luma in 0..1), output `1x16x16x8x2` FP16. The last layers
reshape a `1x16x16x16` map (channels, rows, columns) so that the output index is
`[row][column][depth][coefficient]`, which is how `ltm_gain` reads it.

Windows runs it through oneDNN on the GPU in FP16. The element runs the same file through
OpenVINO's CPU plugin.

## 4. Temporal filter (`temporal_filter`)

`GridFilterCalculator::Process` (intelic.dll 0x18008f510). The graph sets
`filter_only = true`, `strength = 0.3`, `coeff_dim = 2`.

- First grid (the output buffer has no size yet): copied through.
- Afterwards, for each of the 4096 values:
  `state = half((1.0f - (float)a) * (float)state + (float)half(new * a))` with
  `a = half((float)0.3)`. The product `new * a` is a half multiplication; the rest is single
  precision.

So the new grid has weight 0.3 and the history 0.7. With `filter_only = true` the motion test
that would let the runtime skip the network (`skip_thresh`) is not evaluated: the network
runs on every frame.

## 5. ltm_gain: grid to per-pixel gain (`axis`, `ltm_gain`)

Arguments (ids 4006 to 4022): luma, grid, blend map (ints), output gain plane, six floats and
three ints. `ZeSyclNNTMLtmGainCalculator` (Open 0x1800b08b0, Process 0x1800b0ed0, argument
order in 0x1800b2c90) supplies:

| kernel argument | value |
| --- | --- |
| %4014 guide weight | `guide_weight / 8192` |
| %4015 guide bias | `guide_bias / 8192` |
| %4016 row scale | `15.0f / (H - 1)` |
| %4017 column scale | `15.0f / (W - 1)` |
| %4018 blend row scale | `(blend_h - 1) / (float)(H - 1)` |
| %4019 blend column scale | `(blend_w - 1) / (float)(W - 1)` |
| %4020, %4021 | blend map height and width |
| %4022 | W |

Per pixel `(y, x)` with luma `L`:

- Space: `gy = row_scale * y`, `fy = floor(gy)`, cells `clamp(fy, 0, 15)` and
  `clamp(fy + 1, 0, 15)`, weights `(fy + 1) - gy` and `gy - fy` (%4120 to %4130; columns
  %4142 to %4152). Pixel 0 sits on cell 0 and the last pixel on cell 15: corners aligned, no
  half-pixel offset.
- Guide: `z = 7 / (1 + exp(-(L*weight + bias)))` (%4164 to %4169, `0x1.cp+2` is 7), cells
  `clamp(floor(z), 0, 7)` and `clamp(floor(z) + 1, 0, 7)`, weights the same way (%4170 to
  %4177).
- Grid index `(row << 8) + (column << 4) + (depth << 1) + coefficient` (%4258 to %4265): the
  first axis of 16 is image rows, the second columns, the 8 is the guide.
- Trilinear weights `wz * (wx * wy)` (%5227 to %5238). Each coefficient is the sum of eight
  `weight * grid` products, accumulated in the order (x0,y0,z0), (x0,y0,z1), (x1,y0,z0),
  (x1,y0,z1), (x0,y1,z0), (x0,y1,z1), (x1,y1,z0), (x1,y1,z1) (%5239 to %5253 for coefficient
  0, %5254 to %5268 for coefficient 1).
- `mapped = clamp(coeff1 + coeff0 * L, 0, 1)` (%5428, %5429, %5440). The grid is an affine
  map of luma.
- Blend: the map value is `int * 2^-16` (%5139 to %5141); it is interpolated bilinearly at
  `blend_scale * (y, x)` the same corners-aligned way (%4220 to %4257, %5395 to %5405).
- `out = clamp(L + blend * (mapped - L), 0, 1)`; `gain = out / L`, or 0 where `L` is not
  positive (%5444 to %5446, %5453, %5500 to %5503).

`blend_map_value` with one element fills the whole map (0x1800b0ed0, the branch that sets the
flag at `this + 400`).

## 6. postprocess: apply the gain (`apply_gain`, `postprocess`)

Arguments (ids 1691 to 1713): input, gain plane, output, yuv2rgb offset and matrix, a second
offset and the rgb2yuv matrix, `input_range_restricted`, `output_range_restricted`, `a`
(int), `b`, `c` (floats), width, height. `ZeSyclNNTMPostprocessCalculator` (Open
0x1800b4890, Process 0x1800b5190, arguments 0x1800b5ab0) divides yuv2rgb by its entry 0,
divides rgb2yuv by the sum of its first row, passes `b/255` and `c/255`, and passes the
yuv2rgb offset for both offsets.

The kernel repeats steps 1 to 4 of preprocess for the four pixels (%1981 to %2094), then
calls the lambda `%1272` with (RGB, luma `L`, gain `g`):

- `g < 1` (%1534): `RGB' = min(g * RGB, 1)` (%1537 to %1548).
- otherwise, with `Lg = g * L` (%1550):
  - `R == G == B` (%1556, %1563): all three become `min(Lg, 1)` (%1564).
  - else `d = RGB - L` (%1566 to %1568), `dmax = max(dR, dB, dG)`,
    `smax = (1 - Lg) / dmax` if `dmax > 0` else 255 (%1571 to %1574),
    `p = (max(b + 1 - Lg, 0) * (1 / (b + 1 - L)))^a` by repeated multiplication (%1585 to
    %1597, %1616, %1594), `s = min(smax, (c + g) * p / (c + 1))` (%1605 to %1609),
    `RGB' = Lg + s * d` (%1610 to %1615).

  So luma is scaled by `g` and the colour difference by `s`, which falls below `g` as the
  result approaches white and is capped where a channel would clip.
- `YUV = M_rgb2yuv * RGB'` as `m2*B + (m1*G + m0*R)` per row, times 255 (%1627 to %1681).

Back in the kernel: `Y8 = clamp(round(Y) + offset[0], 0, 255)` per pixel (%2188 to %2213),
`U8 = clamp(round(0.25 * (U11 + (U10 + (U01 + U00)))) + offset[1], 0, 255)` (%2158 to %2167,
%2216 to %2220), V likewise. `round` is OpenCL's, halves away from zero. If
`output_range_restricted != 0` (%2228): `Y8 = clamp(rhe(Y8*220/256) + 16, 16, 235)` and
`C8 = clamp(rhe(C8*224/256) + 16, 16, 240)`, where `rhe` rounds halves to even (%2229 to
%2294).

## 7. Parameters

### Where they come from

The parameter kernel `nntm_1_0` (uuid 46539) in the MFT has an init function (0x180370300)
that copies the tuning record to its output and a per-frame function (0x18036fa70). The
executor `CSubwayV2NntmExecutor` (0x180085210) writes the output to the graph every frame:
range flags, `a`, `b`, `c`, the yuv2rgb offset and matrix, the rgb2yuv matrix, and the blend
map with its size. It resolves handles for the tone-map LUT and the guide weight and bias but
never writes them, so those keep the graph's values.

Samsung's `nntm_control` record (aiqb, LISP record uuid 0xe153, identical for the three
tuning modes; field names from the validator at MFT 0x1801c56b0):

| field | value | used as |
| --- | --- | --- |
| offset_yuv2rgb | 0, 128, 128 | offsets |
| yuv2rgb | 8192, -2, 11218, 8192, -1334, -3336, 8192, 13220, -2 | /8192: BT.709 with chroma / 1.15 |
| rgb2yuv | 3484, 11716, 1183, -2158, -7262, 9420, 9420, -8557, -863 | /16383: BT.709 with chroma x 1.15 |
| gtm_a, gtm_b, gtm_c | 2, 512, 0 | `a = 2`, `b = 512/255`, `c = 0` |
| guidence_weight, guidence_bias | 27955, -12919 | 3.4125, -1.5770 (the graph carries the same numbers) |
| input/output_range_restricted | 1, 1 | overwritten per frame, see below |
| global_weight | 350, 500, 500, 500, 500 at sensor gain 1, 2, 8, 16, 32 | /1023 |
| radial_dependency_weight | 572, 540, 540, 500, 500 at the same gains | /1023 |
| face_enable, face_weight | 1; 306, 306, 358, 358, 408 | /1023, needs a face detector |
| blend ellipses | inner 0, 40; outer 20, 60 | face region shape |

The two matrices cancel on chroma, so the 1.15 only lowers saturation inside the tone-mapping
domain. The interpolation variable of the three weight curves is the one every noise
reduction record of this file uses, with points up to 46.5 (3 x the sensor's 15.5x analogue
limit): total sensor gain.

### Per frame

- **Range flags** (0x18036fa70): both are 1 when a format field of the run request is 0x20
  or 0x30, else both are 0. The two always agree, so the element has one `range` property.
- **Blend map** (0x180370b60), from the 63x47 four-channel lens-shading grid `p`:
  `v = ((p3/c3 + p0/c0) * 0.5 + p1/c1 + p2/c2) / 3` with `c_k` the largest corner value of
  channel `k`, `vmin = min(v)`, and
  `blend = ((1 / (v / vmin)) * radial + (1 - radial)) * global`, stored as
  `(int)(blend * 65536)`. The tone mapping is at full `global` weight in the image centre and
  weaker towards the corners, where shading correction has already amplified noise.
- **Face region** (0x18036f6d0, 0x180370700): inside the largest detected face the blend map
  is multiplied by `1 - face_weight/1023`, ramped in and out over 2 s.

### What the element uses

Constants are Samsung's. For what varies with things the element cannot see:

- `strength` (global_weight / 1023), default 500/1023: the value for sensor gain 2 and above,
  which is every indoor scene. At gain 1 (bright daylight) Windows uses 350/1023.
- `radial` (radial_dependency_weight / 1023), default 540/1023: the value for gains 2 to 8.
  Windows moves to 500/1023 by gain 16.
- Lens shading: the F11 (4000 K fluorescent) table of the aiqb. The five light-source tables
  give blend maps within 0.005 of each other. Windows uses the grid the shading adaptor
  produced for the frame; if that adaptor lowers shading correction in low light, the map is
  flatter than the one used here.
- No face region: Linux runs no face detector, so faces get the full tone mapping where
  Windows would hold back 30 to 40 percent.

## 8. Where the reference could differ from Windows

1. Fast-math flags let the GPU compiler fuse multiply-adds and reorder sums; the reference
   does neither. Expected effect: under one code value.
2. `exp` in the guide is computed exactly and rounded once; the GPU's `exp` is an
   approximation of unknown rounding.
3. The network runs in FP32 on the CPU plugin instead of FP16 through oneDNN on the GPU.
4. The grid is assumed to be applied to the frame it was computed from.
5. The interpolation variable of the weight curves is taken to be total sensor gain.
6. The lens-shading grid given to the parameter kernel is taken to be the plain table for
   the light source, in the aiqb's channel order (greens in the middle).
7. The range flags are tied to a format field whose meaning was not traced.
8. No face region.

## 9. The element

`nntm.c` performs the operations of `reference.py` in the same order. Each one runs in single
precision and is rounded to half with the F16C conversions, which gives the half-precision
result for add, subtract, multiply and divide. The guide's `exp` comes from a table indexed by
the half bits of the luma. `check.py` therefore expects the element to equal the reference. It
allows one code value because OpenVINO's output can change with its thread count; the element
and the reference both use one inference thread.

Frames are processed 64 pixels at a time, so the width must be a multiple of 64.

An identity grid does not return every pixel unchanged. Step 3 of preprocess clamps RGB, so a
pixel whose YUV lies outside the RGB gamut comes back inside it. On the recorded clips that is
under 0.005 percent of pixels, moved by up to 9 code values; every other pixel returns within 1.
