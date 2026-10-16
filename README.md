# CNN Accelerator (Verilog RTL)

Verilog implementation of a configurable 2D convolution accelerator built around a PE array, with support for max pooling. This is the RTL accompanying the article:

> **IEEE Xplore:** https://ieeexplore.ieee.org/document/11706755

## Overview

- **PE array:** `HEIGHT × WIDTH` processing elements (default 5×5); each PE does signed MAC (convolution) or compare (max pooling).
- **Memory hierarchy:** global buffers for ifmap/ofmap, plus per-PE scratchpads for ifmap and filter rows.
- **Runtime-configurable:** ifmap, filter and ofmap sizes, stride, and conv/pooling mode are set at run time, up to the synthesis-time maxima.
- **Defaults:** 8-bit inputs, 20-bit partial sums, ifmap/ofmap up to 28×28, filters up to 5×5.

## Repository layout

| File | Description |
|------|-------------|
| `rtl/top.v` | Top level and control FSM (IDLE → CONF → RUN → DONE) |
| `rtl/pe_array.v` | PE array and data distribution |
| `rtl/pe.v` | Processing element (MAC / max-pool) |
| `rtl/id_controller.v` | Row-ID routing of ifmap/filter data to PEs |
| `rtl/ifmap_glb.v`, `rtl/ofmap_glb.v` | Global buffers for input and output feature maps |
| `rtl/ifmap_spad.v`, `rtl/filter_spad.v` | Per-PE scratchpads |
| `rtl/fifo.v` | Generic FIFO |
| `rtl/top_tb.v` | Self-checking testbench |

## Simulation

The testbench generates a random ifmap and filter (or loads `ifmap.mem` / `filter.mem` when `LOAD_FROM_FILE = 1`), runs the accelerator, and checks the output against a reference model.

```bash
cd rtl
iverilog -g2012 -o sim top_tb.v
vvp sim
```

On success it prints `All OFMAP values match!` and writes a waveform to `top_tb.vcd`.

To try other configurations, edit the parameters at the top of `top_tb.v`:

- **Convolution parameters:** `STRIDE`, `FILTER_SIZE`, `IFMAP_SIZE`
- **Hardware parameters:** PE array size (`PE_ARRAY_WIDTH`, `PE_ARRAY_HEIGHT`), maximum supported sizes (`MAX_IFMAP_SIZE`, `MAX_FILTER_SIZE`, `MAX_OFMAP_SIZE`, `MAX_STRIDE`) and data widths (`DWIDTH`, `OUPUT_DWIDTH`)
