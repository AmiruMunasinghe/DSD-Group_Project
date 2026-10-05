import argparse
import random
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
import torch
from torch import nn
from torch.utils.data import Dataset, DataLoader


CLASS_COLORS = np.array(
    [
        [20, 20, 20],      # 0 background/dark
        [70, 150, 255],    # 1 bright/sky-like
        [50, 200, 80],     # 2 green/nature-like
        [255, 80, 60],     # 3 warm/object-like
    ],
    dtype=np.uint8,
)


class TinySegNet(nn.Module):
    def __init__(self, classes=4):
        super().__init__()
        self.enc1 = nn.Sequential(
            nn.Conv2d(3, 8, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(8, 16, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
        )
        self.pool = nn.MaxPool2d(kernel_size=2)
        self.mid = nn.Sequential(
            nn.Conv2d(16, 16, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
        )
        self.dec = nn.Sequential(
            nn.Conv2d(16, 8, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(8, classes, kernel_size=1),
        )

    def forward(self, x):
        x = self.enc1(x)
        x = self.pool(x)
        x = self.mid(x)
        x = nn.functional.interpolate(x, scale_factor=2, mode="nearest")
        return self.dec(x)


def count_parameters(model):
    return sum(parameter.numel() for parameter in model.parameters())


def estimate_macs(height, width, classes):
    # Conv MACs: output_h * output_w * out_channels * kernel_h * kernel_w * in_channels.
    macs = 0
    macs += height * width * 8 * 3 * 3 * 3       # conv 3 -> 8
    macs += height * width * 16 * 3 * 3 * 8      # conv 8 -> 16
    macs += (height // 2) * (width // 2) * 16 * 3 * 3 * 16
    macs += height * width * 8 * 3 * 3 * 16      # conv 16 -> 8
    macs += height * width * classes * 1 * 1 * 8 # conv 8 -> classes
    return macs


def pil_rgb_to_tensor(image):
    array = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    return torch.from_numpy(array).permute(2, 0, 1)


def pseudo_labels(image):
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    r = rgb[:, :, 0]
    g = rgb[:, :, 1]
    b = rgb[:, :, 2]
    brightness = (r + g + b) / 3.0

    labels = np.zeros(brightness.shape, dtype=np.int64)
    labels[brightness > 165] = 1
    labels[(g > r * 1.08) & (g > b * 1.08) & (brightness > 45)] = 2
    labels[(r > g * 1.10) & (r > b * 1.10) & (brightness > 45)] = 3
    return labels


def labels_to_rgb(labels):
    return Image.fromarray(CLASS_COLORS[labels], mode="RGB")


class SegmentationPatchDataset(Dataset):
    def __init__(self, image_paths, patch_size=64, patches_per_epoch=3000):
        self.images = [Image.open(path).convert("RGB") for path in image_paths]
        self.patch_size = patch_size
        self.patches_per_epoch = patches_per_epoch

    def __len__(self):
        return self.patches_per_epoch

    def __getitem__(self, index):
        image = random.choice(self.images)
        w, h = image.size
        if w < self.patch_size or h < self.patch_size:
            scale = max(self.patch_size / w, self.patch_size / h)
            image = image.resize((int(w * scale + 0.5), int(h * scale + 0.5)), Image.BICUBIC)
            w, h = image.size

        left = random.randint(0, w - self.patch_size)
        top = random.randint(0, h - self.patch_size)
        patch = image.crop((left, top, left + self.patch_size, top + self.patch_size))

        if random.random() < 0.5:
            patch = patch.transpose(Image.FLIP_LEFT_RIGHT)

        x = pil_rgb_to_tensor(patch)
        y = torch.from_numpy(pseudo_labels(patch))
        return x, y


def list_images(path):
    supported = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}
    path = Path(path)
    if path.is_file():
        return [path]
    return sorted(p for p in path.rglob("*") if p.suffix.lower() in supported)


def make_comparison(image, model, device, out_path):
    model.eval()
    w, h = image.size
    input_tensor = pil_rgb_to_tensor(image).unsqueeze(0).to(device)

    with torch.no_grad():
        logits = model(input_tensor)
        pred = torch.argmax(logits, dim=1).cpu().squeeze(0).numpy().astype(np.int64)

    target_mask = labels_to_rgb(pseudo_labels(image))
    cnn_mask = labels_to_rgb(pred)

    label_h = 30
    canvas = Image.new("RGB", (w * 3, h + label_h), color=(255, 255, 255))
    draw = ImageDraw.Draw(canvas)

    canvas.paste(image, (0, label_h))
    canvas.paste(target_mask, (w, label_h))
    canvas.paste(cnn_mask, (w * 2, label_h))

    draw.text((8, 8), "Input", fill=(0, 0, 0))
    draw.text((w + 8, 8), "Pseudo target mask", fill=(0, 0, 0))
    draw.text((w * 2 + 8, 8), "TinySegNet output", fill=(0, 0, 0))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)


def benchmark_inference(model, image, device, runs, warmup):
    model.eval()
    input_tensor = pil_rgb_to_tensor(image).unsqueeze(0).to(device)

    with torch.no_grad():
        for _ in range(warmup):
            _ = model(input_tensor)
        if device.type == "cuda":
            torch.cuda.synchronize()

        start = time.perf_counter()
        for _ in range(runs):
            logits = model(input_tensor)
            pred = torch.argmax(logits, dim=1)
        if device.type == "cuda":
            torch.cuda.synchronize()
        elapsed = time.perf_counter() - start

    latency_ms = (elapsed / runs) * 1000.0
    fps = runs / elapsed
    _, _, height, width = input_tensor.shape
    macs = estimate_macs(height, width, len(CLASS_COLORS))
    params = count_parameters(model)
    throughput = macs * fps

    print("")
    print("CPU/GPU inference benchmark")
    print("---------------------------")
    print(f"device              : {device}")
    print(f"input resolution    : {width}x{height}")
    print(f"parameters          : {params:,}")
    print(f"estimated MACs/run  : {macs:,}")
    print(f"benchmark runs      : {runs}")
    print(f"average latency     : {latency_ms:.3f} ms/image")
    print(f"throughput          : {fps:.2f} images/s")
    print(f"estimated MAC/s     : {throughput / 1e6:.2f} MMAC/s")
    print(f"last output shape   : {tuple(pred.shape)}")


def export_int8_weights(model, out_path):
    lines = []
    state = model.state_dict()
    for name, tensor in state.items():
        array = tensor.detach().cpu().numpy()
        scale = max(float(np.max(np.abs(array))) / 127.0, 1e-8)
        quantized = np.round(array / scale).clip(-127, 127).astype(np.int8)
        lines.append(f"# {name} shape={list(array.shape)} scale={scale:.10f}")
        lines.append(" ".join(str(int(v)) for v in quantized.flatten()))
    out_path.write_text("\n".join(lines) + "\n")


def train(args):
    image_paths = list_images(args.image or args.data_dir)
    if not image_paths:
        raise SystemExit("No input images found. Pass --image path/to/image.jpg or --data-dir path/to/images")

    device = torch.device(args.device if args.device else ("cuda" if torch.cuda.is_available() else "cpu"))
    print(f"Using device: {device}")
    print(f"Training images: {len(image_paths)}")

    dataset = SegmentationPatchDataset(
        image_paths=image_paths,
        patch_size=args.patch_size,
        patches_per_epoch=args.patches_per_epoch,
    )
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=True, num_workers=0)

    model = TinySegNet(classes=len(CLASS_COLORS)).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    loss_fn = nn.CrossEntropyLoss()

    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0
        correct = 0
        pixels = 0

        for x, y in loader:
            x = x.to(device)
            y = y.to(device)

            optimizer.zero_grad(set_to_none=True)
            logits = model(x)
            loss = loss_fn(logits, y)
            loss.backward()
            optimizer.step()

            total_loss += loss.item()
            pred = torch.argmax(logits, dim=1)
            correct += int((pred == y).sum().item())
            pixels += y.numel()

        accuracy = correct / pixels
        print(f"epoch {epoch:03d} | loss {total_loss / len(loader):.6f} | pixel_acc {accuracy:.3f}")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), out_dir / "tiny_segnet.pth")
    export_int8_weights(model, out_dir / "tiny_segnet_int8_weights.txt")

    demo_image = Image.open(image_paths[0]).convert("RGB")
    if max(demo_image.size) > args.demo_max_side:
        demo_image.thumbnail((args.demo_max_side, args.demo_max_side), Image.BICUBIC)

    make_comparison(demo_image, model, device, out_dir / "segmentation_comparison.png")
    benchmark_inference(model, demo_image, device, args.benchmark_runs, args.benchmark_warmup)
    print(f"Saved model: {out_dir / 'tiny_segnet.pth'}")
    print(f"Saved int8 weights: {out_dir / 'tiny_segnet_int8_weights.txt'}")
    print(f"Saved comparison: {out_dir / 'segmentation_comparison.png'}")


def parse_args():
    parser = argparse.ArgumentParser(description="Train a tiny FPGA-friendly segmentation CNN.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--image", help="Single image to train/demo on.")
    source.add_argument("--data-dir", help="Folder of images to train on.")
    parser.add_argument("--out-dir", default="runs/tiny_segnet")
    parser.add_argument("--device", choices=["cpu", "cuda"], help="Force CPU or CUDA. Default: auto.")
    parser.add_argument("--epochs", type=int, default=15)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--patch-size", type=int, default=64)
    parser.add_argument("--patches-per-epoch", type=int, default=3000)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--demo-max-side", type=int, default=320)
    parser.add_argument("--benchmark-runs", type=int, default=100)
    parser.add_argument("--benchmark-warmup", type=int, default=10)
    return parser.parse_args()


if __name__ == "__main__":
    train(parse_args())
