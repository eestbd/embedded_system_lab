# ADDRESS_MAP_CHECK

## bram_init.txt layout

- One line is one 128-bit BRAM word, or 16 bytes.
- The hex line is byte-reversed for `$readmemh`; in RTL, `mem[word][8*lane +: 8]` reads lane 0 from the LSB byte.
- Input and weight sections are stored as 16x16 pre-tiled row-major tiles.
- Intermediate and final activations are written feature-major: one BRAM word per feature, with lanes 0..15 holding batch rows 0..15.

## bram_init.txt memory map

| Section | Address Range |
| --- | --- |
| layer1_weights.bin | `14'h0000` to `14'h17FF` |
| layer2_weights.bin | `14'h1800` to `14'h1BFF` |
| layer3_weights.bin | `14'h1C00` to `14'h1FFF` |
| layer4_weights.bin | `14'h2000` to `14'h207F` |
| input_spectrogram.bin | `14'h2400` to `14'h26FF` |
| scratch0 activations | `14'h2700` to `14'h277F` |
| scratch1 activations | `14'h2780` to `14'h27FF` |
| final output | `14'h2880` to `14'h288F` |

## RTL address map

`mlp_4layer_sequencer_16x16.sv` now uses the same base addresses as `bram_init.txt`.

| Layer | Activation Base | Weight Base | Output Base | Expected | Match |
| --- | --- | --- | --- | --- | --- |
| L1 | `14'h2400` | `14'h0000` | `14'h2700` | A=`14'h2400`, W=`14'h0000`, O=scratch0 | PASS |
| L2 | `14'h2700` | `14'h1800` | `14'h2780` | A=L1 output, W=`14'h1800`, O=scratch1 | PASS |
| L3 | `14'h2780` | `14'h1C00` | `14'h2700` | A=L2 output, W=`14'h1C00`, O=scratch0 | PASS |
| L4 | `14'h2700` | `14'h2000` | `14'h2880` | A=L3 output, W=`14'h2000`, O=final | PASS |

## Reader and writer compatibility

- `bram_activation_reader_16x16.sv` reads L1 input with `row_major_layout=1'b1`, so a row-major pre-tiled input tile is emitted as raw lanes `A[row][k_inner]`.
- The same activation reader reads L2-L4 intermediate activations with `row_major_layout=1'b0`, matching the feature-major words produced by `bram_output_writer_feature_major_16x16.sv`.
- `bram_weight_reader_16x16.sv` reads pre-tiled row-major weight tiles and emits raw weight lanes as `W[out_feature][k_inner]`, matching the existing systolic array input convention.
- `output_tile_engine_feature_major_16x16.sv` now uses separate activation and weight readers, so Port A follows activation/output traffic and Port B follows weight traffic.
- `bram_output_writer_feature_major_16x16.sv` still writes one feature word with row lanes, which is compatible with the next layer activation reader in feature-major mode.

## Check result

`[CHECK] RTL sequencer address map matches bram_init.txt layout ... PASS`

`python numpy_reference/verify_bram_init_against_bins.py` result:

- `[CHECK] HDL bram_init.txt equals numpy_reference/weights/bram_init.txt ... PASS`
- `[CHECK] layer1_weights.bin ... PASS`
- `[CHECK] layer2_weights.bin ... PASS`
- `[CHECK] layer3_weights.bin ... PASS`
- `[CHECK] layer4_weights.bin ... PASS`
- `[CHECK] input_spectrogram.bin ... PASS`
- `[CHECK] Reconstructed BRAM numpy inference ... PASS`

Behavioral simulation of `finalprj_top_4layer_tb.sv` was not run in this shell because `xvlog`/`xsim` is not available on PATH. The expected Vivado test is:

- Design Sources: add `bram_activation_reader_16x16.sv` and `bram_weight_reader_16x16.sv` along with the existing RTL sources.
- Simulation Top: `finalprj_top_4layer_tb`
- Expected transcript markers: `NUMPY_REFERENCE_OUTPUT_MATCHED` and `FINALPRJ_TOP 4LAYER MLP test PASSED`.
