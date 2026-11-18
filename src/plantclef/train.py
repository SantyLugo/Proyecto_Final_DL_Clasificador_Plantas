"""Entrena y compara los cuatro experimentos multitarea de PlantCLEF."""

from __future__ import annotations

import argparse
import csv
import json
import random
import time
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from PIL import ImageFile
from torch import nn
from torch.utils.data import DataLoader
from torchvision import transforms

from plantclef.data import TOXICITY_CLASSES, PlantCLEFDataset, build_family_index, load_metadata
from plantclef.models import PlantCLEFMultiTaskModel

ImageFile.LOAD_TRUNCATED_IMAGES = False


def seed_everything(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def make_transforms(image_size: int):
    mean = (0.485, 0.456, 0.406)
    std = (0.229, 0.224, 0.225)
    resize_size = round(image_size * 256 / 224)
    train_transform = transforms.Compose([
        transforms.RandomResizedCrop(image_size, scale=(0.80, 1.0), ratio=(0.90, 1.10)),
        transforms.RandomHorizontalFlip(p=0.5),
        transforms.ColorJitter(brightness=0.10, contrast=0.10, saturation=0.05, hue=0.01),
        transforms.ToTensor(),
        transforms.Normalize(mean, std),
    ])
    evaluation_transform = transforms.Compose([
        transforms.Resize(resize_size),
        transforms.CenterCrop(image_size),
        transforms.ToTensor(),
        transforms.Normalize(mean, std),
    ])
    return train_transform, evaluation_transform


def metrics_for(logits: torch.Tensor, target: torch.Tensor, class_count: int) -> dict:
    predictions = logits.argmax(dim=1)
    matrix = torch.bincount(target * class_count + predictions, minlength=class_count**2)
    matrix = matrix.reshape(class_count, class_count).double()
    tp = matrix.diag()
    precision = tp / matrix.sum(dim=0).clamp_min(1)
    recall = tp / matrix.sum(dim=1).clamp_min(1)
    f1 = 2 * precision * recall / (precision + recall).clamp_min(1e-12)
    return {
        "accuracy": float(tp.sum().item() / matrix.sum().clamp_min(1).item()),
        "macro_f1": float(f1.mean().item()),
        "macro_recall": float(recall.mean().item()),
        "confusion_matrix": matrix.to(torch.int64).tolist(),
        "per_class": [
            {"precision": float(precision[i]), "recall": float(recall[i]), "f1": float(f1[i])}
            for i in range(class_count)
        ],
    }


def make_optimizer(model: PlantCLEFMultiTaskModel, experiment: dict) -> torch.optim.Optimizer:
    head_params = list(model.toxicity_head.parameters()) + list(model.family_head.parameters())
    groups = [{"params": head_params, "lr": float(experiment["head_learning_rate"])}]
    backbone_params = [p for p in model.backbone.parameters() if p.requires_grad]
    if backbone_params:
        groups.append({"params": backbone_params, "lr": float(experiment["backbone_learning_rate"])})
    return torch.optim.Adam(groups)


def run_epoch(model, loader, device, optimizer, toxicity_loss, family_loss,
              toxicity_weight: float, family_weight: float):
    training = optimizer is not None
    model.train(training)
    # EfficientNet has BatchNorm layers; keep their running statistics fixed when
    # the backbone is frozen, including in the partial fine-tuning experiment.
    if model.freeze_strategy in {"all", "last_block"}:
        model.backbone.eval()
    total_loss = 0.0
    toxicity_logits, toxicity_targets = [], []
    family_logits, family_targets = [], []
    context = torch.enable_grad() if training else torch.no_grad()
    with context:
        for batch in loader:
            images = batch["image"].to(device, non_blocking=True)
            y_toxicity = batch["toxicity"].to(device, dtype=torch.long, non_blocking=True)
            y_family = batch["family"].to(device, dtype=torch.long, non_blocking=True)
            if training:
                optimizer.zero_grad(set_to_none=True)
            outputs = model(images)
            loss_t = toxicity_loss(outputs["toxicity"], y_toxicity)
            loss_f = family_loss(outputs["family"], y_family)
            loss = toxicity_weight * loss_t + family_weight * loss_f
            if training:
                loss.backward()
                optimizer.step()
            total_loss += float(loss.detach()) * len(images)
            toxicity_logits.append(outputs["toxicity"].detach().cpu())
            toxicity_targets.append(y_toxicity.detach().cpu())
            family_logits.append(outputs["family"].detach().cpu())
            family_targets.append(y_family.detach().cpu())
    tox = metrics_for(torch.cat(toxicity_logits), torch.cat(toxicity_targets), len(TOXICITY_CLASSES))
    fam = metrics_for(torch.cat(family_logits), torch.cat(family_targets), model.family_head[-1].out_features)
    return total_loss / len(loader.dataset), tox, fam


def save_confusion(path: Path, matrix: list[list[int]], names: list[str]) -> None:
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    with temporary_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["real/predicho", *names])
        for name, row in zip(names, matrix):
            writer.writerow([name, *row])
    temporary_path.replace(path)


def update_comparison(output_root: Path, experiments: list[dict]) -> None:
    """Actualiza el comparativo usando los resúmenes ya completados."""
    summaries = []
    for experiment in experiments:
        path = output_root / experiment["name"] / "summary.json"
        if path.exists():
            summaries.append(json.loads(path.read_text(encoding="utf-8")))
    if not summaries:
        return
    comparison = pd.DataFrame([{
        "experiment": item["experiment"]["name"], "best_epoch": item["best_epoch"],
        "validation_toxicity_macro_f1": item["best_validation_toxicity_macro_f1"],
        "test_toxicity_macro_f1": item["test_toxicity"]["macro_f1"],
        "test_toxicity_accuracy": item["test_toxicity"]["accuracy"],
        "test_family_macro_f1": item["test_family"]["macro_f1"],
        "elapsed_seconds": item["elapsed_seconds"],
    } for item in summaries])
    temporary_path = output_root / "comparison.csv.tmp"
    comparison.to_csv(temporary_path, index=False)
    temporary_path.replace(output_root / "comparison.csv")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="configs/plantclef.json")
    parser.add_argument("--experiments", default="configs/experiments.json")
    parser.add_argument("--only", nargs="*", help="Nombres opcionales de experimentos a ejecutar.")
    parser.add_argument("--force", action="store_true", help="Reentrena aun si ya hay resumen final.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    config = json.loads((root / args.config).read_text(encoding="utf-8"))
    exp_config = json.loads((root / args.experiments).read_text(encoding="utf-8"))
    defaults = exp_config["defaults"]
    experiments = exp_config["experiments"]
    if args.only:
        experiments = [exp for exp in experiments if exp["name"] in args.only]
        unknown = set(args.only) - {exp["name"] for exp in experiments}
        if unknown:
            raise ValueError(f"Experimentos desconocidos: {sorted(unknown)}")

    dataset_dir = Path(config["dataset_dir"])
    if not dataset_dir.is_absolute():
        dataset_dir = (root / dataset_dir).resolve()
    labels = load_metadata(dataset_dir)
    split_file = root / config["split_file"]
    if not split_file.exists():
        raise FileNotFoundError(f"No existe {split_file}; ejecuta scripts/prepare_splits.py primero.")
    split_rows = pd.read_csv(split_file, dtype={"species_id": str, "obs_id": str})
    labels = labels.merge(split_rows[["image_path", "split"]], on="image_path", how="left", validate="one_to_one")
    if labels["split"].isna().any():
        raise ValueError("Hay imágenes del dataset sin partición asignada.")
    if not {"train", "validation", "test"}.issubset(set(labels["split"])):
        raise ValueError("Las particiones deben contener train, validation y test.")
    family_to_index = build_family_index(labels)
    family_names = [name for name, _ in sorted(family_to_index.items(), key=lambda item: item[1])]
    image_size = int(defaults["image_size"])
    train_transform, evaluation_transform = make_transforms(image_size)
    batch_size = int(defaults["batch_size"])
    workers = int(config.get("num_workers", 0))
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Dispositivo: {device} | Imágenes: {len(labels)} | Familias: {len(family_names)}", flush=True)
    if device.type == "cuda":
        print(f"GPU: {torch.cuda.get_device_name(0)}", flush=True)
    output_root = root / "outputs" / "experiments"
    output_root.mkdir(parents=True, exist_ok=True)
    update_comparison(output_root, experiments)

    for experiment in experiments:
        run_dir = output_root / experiment["name"]
        if (run_dir / "summary.json").exists() and not args.force:
            print(f"\n=== {experiment['name']} ya está completo; se conserva y se omite. ===", flush=True)
            update_comparison(output_root, experiments)
            continue
        seed_everything(int(defaults["seed"]))
        run_dir.mkdir(parents=True, exist_ok=True)
        datasets = {
            split: PlantCLEFDataset(
                labels[labels["split"] == split], dataset_dir, family_to_index,
                train_transform if split == "train" else evaluation_transform,
            )
            for split in ("train", "validation", "test")
        }
        loaders = {
            split: DataLoader(
                datasets[split], batch_size=batch_size, shuffle=split == "train",
                num_workers=workers, pin_memory=device.type == "cuda",
                persistent_workers=workers > 0,
            )
            for split in datasets
        }
        model = PlantCLEFMultiTaskModel(
            num_families=len(family_names), pretrained=bool(defaults["pretrained"]),
            freeze_strategy=experiment["freeze_strategy"], dropout=float(experiment["dropout"]),
        ).to(device)
        optimizer = make_optimizer(model, experiment)
        toxicity_loss = nn.CrossEntropyLoss()
        family_loss = nn.CrossEntropyLoss()
        history = []
        best_f1 = -1.0
        best_epoch = 0
        start = time.time()
        print(f"\n=== {experiment['name']} ===\n{experiment['description']}", flush=True)
        for epoch in range(1, int(defaults["epochs"]) + 1):
            epoch_start = time.time()
            train_loss, train_tox, train_fam = run_epoch(
                model, loaders["train"], device, optimizer, toxicity_loss, family_loss,
                float(defaults["toxicity_loss_weight"]), float(defaults["family_auxiliary_loss_weight"]),
            )
            val_loss, val_tox, val_fam = run_epoch(
                model, loaders["validation"], device, None, toxicity_loss, family_loss,
                float(defaults["toxicity_loss_weight"]), float(defaults["family_auxiliary_loss_weight"]),
            )
            record = {
                "epoch": epoch, "train_loss": train_loss, "validation_loss": val_loss,
                "train_toxicity_accuracy": train_tox["accuracy"],
                "train_toxicity_macro_f1": train_tox["macro_f1"],
                "validation_toxicity_accuracy": val_tox["accuracy"],
                "validation_toxicity_macro_f1": val_tox["macro_f1"],
                "validation_toxicity_macro_recall": val_tox["macro_recall"],
                "validation_family_accuracy": val_fam["accuracy"],
                "validation_family_macro_f1": val_fam["macro_f1"],
            }
            history.append(record)
            history_tmp = run_dir / "history.csv.tmp"
            pd.DataFrame(history).to_csv(history_tmp, index=False)
            history_tmp.replace(run_dir / "history.csv")
            if val_tox["macro_f1"] > best_f1:
                best_f1, best_epoch = val_tox["macro_f1"], epoch
                checkpoint_path = run_dir / "best_model.pth"
                temporary_checkpoint = run_dir / "best_model.pth.tmp"
                torch.save({
                    "epoch": epoch, "model_state_dict": model.state_dict(),
                    "family_to_index": family_to_index, "toxicity_classes": TOXICITY_CLASSES,
                    "experiment": experiment, "config": defaults,
                }, temporary_checkpoint)
                temporary_checkpoint.replace(checkpoint_path)
            elapsed = time.time() - epoch_start
            print(
                f"Época {epoch:02d}/{defaults['epochs']} | loss {train_loss:.4f}/{val_loss:.4f} "
                f"| toxicidad val acc {val_tox['accuracy']:.3f} macro-F1 {val_tox['macro_f1']:.3f} "
                f"| familia val macro-F1 {val_fam['macro_f1']:.3f} | {elapsed:.1f}s",
                flush=True,
            )

        checkpoint = torch.load(run_dir / "best_model.pth", map_location=device, weights_only=False)
        model.load_state_dict(checkpoint["model_state_dict"])
        _, test_tox, test_fam = run_epoch(
            model, loaders["test"], device, None, toxicity_loss, family_loss,
            float(defaults["toxicity_loss_weight"]), float(defaults["family_auxiliary_loss_weight"]),
        )
        save_confusion(run_dir / "toxicity_confusion_test.csv", test_tox["confusion_matrix"], TOXICITY_CLASSES)
        save_confusion(run_dir / "family_confusion_test.csv", test_fam["confusion_matrix"], family_names)
        summary = {
            "experiment": experiment, "epochs_completed": len(history), "best_epoch": best_epoch,
            "best_validation_toxicity_macro_f1": best_f1,
            "test_toxicity": {k: v for k, v in test_tox.items() if k != "confusion_matrix"},
            "test_family": {k: v for k, v in test_fam.items() if k != "confusion_matrix"},
            "elapsed_seconds": time.time() - start, "device": str(device),
        }
        summary_path = run_dir / "summary.json"
        summary_tmp = run_dir / "summary.json.tmp"
        summary_tmp.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
        summary_tmp.replace(summary_path)
        update_comparison(output_root, experiments)
        print(
            f"Mejor época: {best_epoch}; test toxicidad macro-F1={test_tox['macro_f1']:.3f}, "
            f"familia macro-F1={test_fam['macro_f1']:.3f}; duración={summary['elapsed_seconds']/60:.1f} min",
            flush=True,
        )

    update_comparison(output_root, experiments)
    if (output_root / "comparison.csv").exists():
        print(f"\nComparación guardada: {output_root / 'comparison.csv'}", flush=True)


if __name__ == "__main__":
    main()
