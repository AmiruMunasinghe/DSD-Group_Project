import argparse
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import torch
from torch import nn
from torch.utils.data import Dataset, DataLoader


class TinyResidualCNN(nn.Module):
    def __init__(self, channels=8):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv2d(1, channels, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(channels, channels, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(channels, 1, kernel_size=3, padding=1),
        )

    def forward(self, x):
        return torch.clamp(x + self.net(x), 0.0, 1.0)


def load_grayscale(path):
    return Image.open(path).convert("L")


def pil_to_tensor(image):
    array = np.asarray(image, dtype=np.float32) / 255.0
    return torch.from_numpy(array).unsqueeze(0)


def tensor_to_pil(tensor):
    tensor = tensor.detach().cpu().clamp(0.0, 1.0)
    array = (tensor.squeeze(0).numpy() * 255.0).round().astype(np.uint8)
    return Image.fromarray(array, mode="L")


def degrade_image(image, noise_std=0.06):
    blurred = image.filter(ImageFilter.GaussianBlur(radius=random.uniform(0.4, 1.2)))
    x = pil_to_tensor(blurred)
    noise = torch.randn_like(x) * noise_std
    return torch.clamp(x + noise, 0.0, 1.0)


class RestorationPatchDataset(Dataset):
    def __init__(self, image_paths, patch_size=64, patches_per_epoch=3000):
        self.images = [load_grayscale(path) for path in image_paths]
        self.patch_size = patch_size
        self.patches_per_epoch = patches_per_epoch

    def __len__(self):
        return self.patches_per_epoch

    def __getitem__(self, index):
        image = random.choice(self.images)
        w, h = image.size

        if w < self.patch_size or h < self.patch_size:
            scale = max(self.patch_size / w, self.patch_size / h)
            image = image.resize((math.ceil(w * scale), math.ceil(h * scale)), Image.BICUBIC)
            w, h = image.size

        left = random.randint(0, w - self.patch_size)
        top = random.randint(0, h - self.patch_size)
        clean_patch = image.crop((left, top, left + self.patch_size, top + self.patch_size))

        if random.random() < 0.5:
            clean_patch = clean_patch.transpose(Image.FLIP_LEFT_RIGHT)
        if random.random() < 0.5:
            clean_patch = clean_patch.transpose(Image.FLIP_TOP_BOTTOM)

        clean = pil_to_tensor(clean_patch)
        degraded = degrade_image(clean_patch)
        return degraded, clean


def list_images(path):
    supported = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}
    path = Path(path)
    if path.is_file():
        return [path]
    return sorted(p for p in path.rglob("*") if p.suffix.lower() in supported)


def make_comparison(clean_image, model, device, out_path):
    model.eval()
    with torch.no_grad():
        degraded = degrade_image(clean_image).unsqueeze(0).to(device)
        enhanced = model(degraded).cpu().squeeze(0)

    degraded_img = tensor_to_pil(degraded.cpu().squeeze(0))
    enhanced_img = tensor_to_pil(enhanced)

    w, h = clean_image.size
    label_h = 28
    canvas = Image.new("L", (w * 3, h + label_h), color=255)
    draw = ImageDraw.Draw(canvas)

    canvas.paste(clean_image, (0, label_h))
    canvas.paste(degraded_img, (w, label_h))
    canvas.paste(enhanced_img, (w * 2, label_h))

    draw.text((8, 8), "Clean target", fill=0)
    draw.text((w + 8, 8), "Degraded input", fill=0)
    draw.text((w * 2 + 8, 8), "CNN output", fill=0)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)


def train(args):
    image_paths = list_images(args.image or args.data_dir)
    if not image_paths:
        raise SystemExit("No input images found. Pass --image path/to/image.png or --data-dir path/to/images")

    device = torch.device(args.device if args.device else ("cuda" if torch.cuda.is_available() else "cpu"))
    print(f"Using device: {device}")
    print(f"Training images: {len(image_paths)}")

    dataset = RestorationPatchDataset(
        image_paths=image_paths,
        patch_size=args.patch_size,
        patches_per_epoch=args.patches_per_epoch,
    )
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=True, num_workers=0)

    model = TinyResidualCNN(channels=args.channels).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    loss_fn = nn.L1Loss()

    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0
        for degraded, clean in loader:
            degraded = degraded.to(device)
            clean = clean.to(device)

            optimizer.zero_grad(set_to_none=True)
            output = model(degraded)
            loss = loss_fn(output, clean)
            loss.backward()
            optimizer.step()

            total_loss += loss.item()

        print(f"epoch {epoch:03d} | loss {total_loss / len(loader):.6f}")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), out_dir / "tiny_residual_cnn.pth")

    demo_image = load_grayscale(image_paths[0])
    max_side = args.demo_max_side
    if max(demo_image.size) > max_side:
        demo_image.thumbnail((max_side, max_side), Image.BICUBIC)

    make_comparison(demo_image, model, device, out_dir / "comparison.png")
    print(f"Saved model: {out_dir / 'tiny_residual_cnn.pth'}")
    print(f"Saved comparison: {out_dir / 'comparison.png'}")


def parse_args():
    parser = argparse.ArgumentParser(description="Train a tiny image-enhancement CNN for FPGA-friendly experiments.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--image", help="Single clean image to train/demo on.")
    source.add_argument("--data-dir", help="Folder of clean images to train on.")
    parser.add_argument("--out-dir", default="runs/tiny_srcnn", help="Output folder.")
    parser.add_argument("--device", choices=["cpu", "cuda"], help="Force CPU or CUDA. Default: auto.")
    parser.add_argument("--channels", type=int, default=8, help="Internal feature channels. Use 8 for FPGA-friendly demo.")
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--patch-size", type=int, default=64)
    parser.add_argument("--patches-per-epoch", type=int, default=3000)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--demo-max-side", type=int, default=320)
    return parser.parse_args()


if __name__ == "__main__":
    train(parse_args())
