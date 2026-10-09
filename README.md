# RISC-V FPGA CNN Accelerator Demo

This repository contains the early software workflow for a project that will implement a RISC-V CPU and a small CNN hardware accelerator on an FPGA board. The final demonstration goal is to process an image with a compact CNN and display the output using VGA.

## Project Goal

The FPGA board has external memory resources suitable for a small image-processing CNN:

- SRAM: 2 MB, 16-bit bus
- SDRAM: 128 MB total, two 64 MB chips with 16-bit buses
- Flash: 8-bit bus

The planned system is:

```text
input image / framebuffer
        |
RISC-V CPU configures accelerator
        |
CNN accelerator performs convolution inference
        |
output mask / processed image framebuffer
        |
VGA controller displays result
```

Training is done on a laptop. The FPGA will run inference only.

## Selected Demo Model

The strongest current demo choice is a tiny segmentation CNN called `TinySegNet`. It creates a large visible difference by converting an RGB input image into a colored segmentation-style mask.

Model structure:

```text
Input RGB image
Conv 3x3, 3 -> 8
ReLU
Conv 3x3, 8 -> 16
ReLU
MaxPool 2x2
Conv 3x3, 16 -> 16
ReLU
Upsample 2x2
Conv 3x3, 16 -> 8
ReLU
Conv 1x1, 8 -> 4 classes
Argmax
Color map for display
```

The important hardware operation is multiply-accumulate:

```text
acc = acc + input_value * weight
```

A convolution output value is calculated as:

```text
Y[y, x, oc] =
    bias[oc] +
    sum over ky, kx, ic (
        X[y + ky, x + kx, ic] * W[ky, kx, ic, oc]
    )
```

For the final class output, the model selects the highest score:

```text
class[y, x] = argmax(CNN_output[y, x, class])
```

Then the class ID is mapped to a display color for VGA.

## Pseudo Target Mask

The current laptop demo does not use manually labeled training data. Instead, it generates a pseudo target mask from RGB values using simple color and brightness rules.

Class meanings:

```text
0 = dark/background-like region
1 = bright/sky-like region
2 = green/nature-like region
3 = red/warm-object-like region
```

Display colors:

```text
0 -> dark gray
1 -> blue
2 -> green
3 -> red/orange
```

This is useful for the FPGA demonstration because it creates an obvious visual output while keeping the CNN small enough to implement.

## Current CPU Result

Captured CPU inference benchmark:

```text
device              : cpu
input resolution    : 320x213
parameters          : 4,908
estimated MACs/run  : 213,020,160
benchmark runs      : 100
average latency     : 21.385 ms/image
throughput          : 46.76 images/s
estimated MAC/s     : 9961.28 MMAC/s
last output shape   : (1, 212, 320)
```

These numbers measure inference only:

```text
input image -> trained CNN forward pass -> output segmentation mask
```

They do not include training, backpropagation, saving files, or comparison image generation.

For the final FPGA demo, image dimensions should preferably be divisible by 2 because of the `MaxPool 2x2` layer. A practical target resolution is:

```text
160x120
```

The result can then be scaled for VGA display.

## Running The Laptop Demo

Install dependencies:

```powershell
pip install torch pillow numpy
```

Run on CPU:

```powershell
python tiny_segmentation_demo.py --image "C:\Users\ROG\Downloads\images (11).jpg" --device cpu
```

Faster CPU test:

```powershell
python tiny_segmentation_demo.py --image "C:\Users\ROG\Downloads\images (11).jpg" --device cpu --epochs 5 --patches-per-epoch 1000
```

The script saves generated outputs under:

```text
runs/tiny_segnet/
```

That folder is ignored by Git because it contains generated artifacts.

## Files

- `tiny_segmentation_demo.py`: main TinySegNet segmentation demo and benchmark script
- `tiny_srcnn_demo.py`: earlier residual image-enhancement CNN experiment
- `fpga/riscv_core/`: DE2-115 RISC-V CPU project with M9K memories, SRAM interface, CNN control map, and VGA framebuffer
- `.gitignore`: excludes generated outputs and Python cache files

## FPGA Status

The FPGA project currently includes:

```text
RV32I-style 5-stage CPU
M9K instruction/data memories
memory-mapped CNN accelerator control registers
16 KB M9K CNN weight RAM
160x120 RGB565 M9K VGA framebuffer
external 2 MB SRAM controller at 0x4000_0000
VGA 160x120-to-640x480 scaler
```

The CPU self-test passes in ModelSim, and the top-level RTL compiles in ModelSim with no syntax errors.

## Next Steps

1. Train and test the tiny segmentation model on more images.
2. Fix the FPGA target resolution, likely `160x120`.
3. Quantize weights and activations to int8/int16.
4. Export trained weights in a hardware-friendly format.
5. Implement convolution, ReLU, maxpool, upsample, argmax, and color mapping in the accelerator.
6. Compare CPU inference latency/FPS against FPGA inference latency/FPS.
