# Experimentos PlantCLEF

Se comparan cuatro EfficientNet-B0 multitarea. El objetivo principal es el perfil toxicológico (4 clases); familia botánica (10 clases) es una salida auxiliar. La pérdida total es `1.0 * CE(toxicidad) + 0.25 * CE(familia)`.

## Entorno

El equipo detectado tiene una NVIDIA GeForce GT 730 de 4 GB. El entrenamiento se configura en CPU porque esa GPU no es compatible con los kernels CUDA modernos de PyTorch usados por este proyecto. Se requiere Python 3.11 y conexión a Internet para instalar dependencias y descargar los pesos ImageNet de EfficientNet-B0. La configuración actual usa imágenes de 192 × 192, batch de 32 y 30 épocas.

Desde PowerShell, dentro de esta carpeta del proyecto:

```powershell
$env:UV_CACHE_DIR = Join-Path $PWD ".uv-cache"
$env:UV_PYTHON_INSTALL_DIR = Join-Path $PWD ".uv-python"
uv python install 3.11
uv venv --python 3.11 .venv
uv pip install --python .venv\Scripts\python.exe -r requirements.txt --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple
```

## Ejecutar los cuatro experimentos

```powershell
.scripts\run_experiments.ps1
```

El script crea primero `outputs/splits.csv`, asignando juntas todas las imágenes de una misma observación para evitar fuga de vistas entre train, validación y test. Después entrena **un modelo a la vez**, en este orden: base, dropout, tasa 0.01 y ajuste parcial. Cada experimento tiene hasta 30 épocas. Tras terminar cada modelo, guarda su historial, mejor checkpoint según macro-F1 de toxicidad en validación, métricas y matriz de confusión de test; también actualiza `comparison.csv`. Los archivos temporales se reemplazan de forma atómica para preservar los últimos resultados completos ante una interrupción.

Si la ejecución se interrumpe, al volver a correr el script los experimentos que ya tengan `summary.json` se omiten y sus resultados se conservan. Para forzar el reentrenamiento de todos, añade `--force` al comando de `plantclef.train`.

Para reanudar o ejecutar un experimento concreto:

```powershell
$env:PYTHONPATH = Join-Path $PWD "src"
.\.venv\Scripts\python.exe -u -m plantclef.train --only baseline_frozen_lr001
```

Los resultados quedan en `outputs/experiments/` y la comparación conjunta en `outputs/experiments/comparison.csv`. Los splits y los resultados son artefactos del proyecto; el subdataset original no se modifica.
