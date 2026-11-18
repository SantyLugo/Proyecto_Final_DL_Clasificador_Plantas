"""Modelo con perfil toxicológico principal y familia botánica auxiliar."""

from __future__ import annotations

import torch
from torch import nn
from torchvision.models import EfficientNet_B0_Weights, efficientnet_b0


class PlantCLEFMultiTaskModel(nn.Module):
    """EfficientNet-B0 con cabezas para riesgo prioritario y familia auxiliar."""

    def __init__(
        self,
        num_families: int,
        num_toxicity_profiles: int = 4,
        pretrained: bool = True,
        freeze_backbone: bool = True,
        freeze_strategy: str | None = None,
        dropout: float = 0.0,
    ) -> None:
        super().__init__()
        if num_families < 2 or num_toxicity_profiles != 4:
            raise ValueError("Se requieren al menos 2 familias y exactamente 4 perfiles toxicológicos.")
        weights = EfficientNet_B0_Weights.DEFAULT if pretrained else None
        if not 0.0 <= dropout < 1.0:
            raise ValueError("dropout debe estar en el rango [0, 1).")
        strategy = freeze_strategy or ("all" if freeze_backbone else "none")
        if strategy not in {"all", "last_block", "none"}:
            raise ValueError("freeze_strategy debe ser all, last_block o none.")
        self.freeze_strategy = strategy
        self.backbone = efficientnet_b0(weights=weights)
        feature_count = self.backbone.classifier[1].in_features
        self.backbone.classifier = nn.Identity()
        for parameter in self.backbone.parameters():
            parameter.requires_grad = strategy == "none"
        if strategy == "last_block":
            for parameter in self.backbone.features[-1].parameters():
                parameter.requires_grad = True
        self.toxicity_head = nn.Sequential(
            nn.Dropout(dropout), nn.Linear(feature_count, num_toxicity_profiles)
        )
        self.family_head = nn.Sequential(nn.Dropout(dropout), nn.Linear(feature_count, num_families))

    def forward(self, images: torch.Tensor) -> dict[str, torch.Tensor]:
        features = self.backbone(images)
        return {
            "toxicity": self.toxicity_head(features),
            "family": self.family_head(features),
        }
