"""Carga de imágenes y etiquetas para los experimentos PlantCLEF."""

from __future__ import annotations

from pathlib import Path

import pandas as pd
from PIL import Image
from torch.utils.data import Dataset


TOXICITY_CLASSES = [
    "Comestible",
    "Comestible con precaución",
    "Levemente tóxica",
    "Altamente tóxica",
]


class PlantCLEFDataset(Dataset):
    """Devuelve el perfil toxicológico principal y la familia auxiliar."""

    def __init__(
        self,
        rows: pd.DataFrame,
        dataset_dir: str | Path,
        family_to_index: dict[str, int],
        transform=None,
    ) -> None:
        self.rows = rows.reset_index(drop=True)
        self.dataset_dir = Path(dataset_dir)
        self.family_to_index = family_to_index
        self.toxicity_to_index = {name: index for index, name in enumerate(TOXICITY_CLASSES)}
        self.transform = transform

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, index: int):
        row = self.rows.iloc[index]
        image_path = self.dataset_dir / Path(str(row["image_path"]))
        with Image.open(image_path) as image:
            image = image.convert("RGB")
        if self.transform is not None:
            image = self.transform(image)
        return {
            "image": image,
            "toxicity": self.toxicity_to_index[str(row["toxicological_profile"])],
            "family": self.family_to_index[str(row["family"])],
        }


def load_metadata(dataset_dir: str | Path) -> pd.DataFrame:
    """Carga y valida las etiquetas del subdataset sin modificarlo."""
    dataset_dir = Path(dataset_dir)
    labels = pd.read_csv(dataset_dir / "labels.csv", dtype={"species_id": str, "obs_id": str})
    required = {
        "image_path", "species_id", "scientific_name", "family", "toxicological_profile", "obs_id"
    }
    missing = required.difference(labels.columns)
    if missing:
        raise ValueError(f"Faltan columnas requeridas en labels.csv: {sorted(missing)}")
    unknown = sorted(set(labels["toxicological_profile"]) - set(TOXICITY_CLASSES))
    if unknown:
        raise ValueError(f"Perfiles toxicológicos no reconocidos: {unknown}")
    return labels


def build_family_index(labels: pd.DataFrame) -> dict[str, int]:
    """Construye un mapeo determinista de familias para la salida auxiliar."""
    families = sorted(labels["family"].dropna().astype(str).unique())
    if len(families) < 2:
        raise ValueError("Se necesitan al menos dos familias para el objetivo auxiliar.")
    return {family: index for index, family in enumerate(families)}
