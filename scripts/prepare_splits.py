"""Crea una división reproducible por observación, evitando fuga entre grupos."""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

import pandas as pd


def assign_groups(rows: pd.DataFrame, fractions: dict[str, float], seed: int) -> dict[str, str]:
    """Asigna cada observación completa al split que mejor respeta las cuotas."""
    rng = random.Random(seed)
    assignments: dict[str, str] = {}
    for species_id, species_rows in rows.groupby("species_id", sort=True):
        group_sizes = species_rows.groupby("obs_id", dropna=False).size().to_dict()
        groups = list(group_sizes)
        rng.shuffle(groups)
        groups.sort(key=lambda group: group_sizes[group], reverse=True)
        targets = {name: len(species_rows) * fraction for name, fraction in fractions.items()}
        counts = {name: 0 for name in fractions}
        for group in groups:
            split = min(
                fractions,
                key=lambda name: (counts[name] / targets[name], counts[name]),
            )
            assignments[f"{species_id}:{group}"] = split
            counts[split] += group_sizes[group]
    return assignments


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="configs/plantclef.json")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    config = json.loads((root / args.config).read_text(encoding="utf-8"))
    dataset_dir = Path(config["dataset_dir"])
    if not dataset_dir.is_absolute():
        dataset_dir = (root / dataset_dir).resolve()
    labels = pd.read_csv(dataset_dir / config["labels_file"], dtype={"species_id": str, "obs_id": str})
    fractions = {
        "train": float(config["train_fraction"]),
        "validation": float(config["validation_fraction"]),
        "test": float(config["test_fraction"]),
    }
    if abs(sum(fractions.values()) - 1.0) > 1e-9:
        raise ValueError("Las fracciones de train/validation/test deben sumar 1.")
    groups = assign_groups(labels, fractions, int(config["seed"]))
    labels["split"] = [groups[f"{row.species_id}:{row.obs_id}"] for row in labels.itertuples()]
    output = root / config["split_file"]
    output.parent.mkdir(parents=True, exist_ok=True)
    labels.to_csv(output, index=False)
    summary = labels.groupby(["split", "species_id", "scientific_name"]).size().unstack("split", fill_value=0)
    print(f"Guardado: {output}")
    print(f"Imágenes: {len(labels)} | grupos obs_id: {labels['obs_id'].nunique()}")
    print(summary.to_string())


if __name__ == "__main__":
    main()
