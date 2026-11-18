# Clasificación de plantas con PlantCLEF 2024

Proyecto académico de clasificación multitarea con EfficientNet-B0. El perfil toxicológico es la predicción principal y la familia botánica es una salida auxiliar. Las etiquetas de riesgo son categorías operativas respaldadas por fuentes documentadas; no certifican seguridad ni comestibilidad.

## Estructura

```text
Proyecto_Final_Deep_Learning_Lugo/
├── configs/                 # Dataset, hiperparámetros y cuatro experimentos
├── scripts/                 # Preparación de splits y ejecución secuencial
├── src/plantclef/           # Dataset, modelo y ciclo de entrenamiento
├── outputs/                 # Splits, métricas, historiales y matrices de confusión
├── PRESENTACION_FINAL_GUION.md
├── ENTRENAMIENTO.md
└── README.md
```

## Datos

La configuración busca `../PlantCLEF_Subdataset_4000_v3` en relación con esta carpeta. El subdataset tiene 4.000 imágenes, 20 especies, cuatro perfiles toxicológicos balanceados y diez familias. Las imágenes permanecen fuera del repositorio para evitar incorporar cientos de MB de datos de PlantCLEF. Al clonar el proyecto, coloca la carpeta v3 junto a esta carpeta o cambia `dataset_dir` en `configs/plantclef.json`.

El TAR original y los subdatasets v1/v2 no forman parte de este repositorio y no se modificaron. La evolución de EDA/subdataset, criterios de selección y dificultades se resume en `PRESENTACION_FINAL_GUION.md`; evidencia toxicológica por especie está en `../PlantCLEF_Subdataset_4000_v3/toxicology_evidence.md`.

## Experimentos

Se ejecutan en serie cuatro configuraciones: base congelada, dropout 0,3, tasa de aprendizaje 0,01 y ajuste parcial del último bloque. La configuración común usa 30 épocas, Adam, batch 32 e imágenes de 192 × 192. La selección del checkpoint usa macro-F1 toxicológico de validación; el test se reporta por separado.

Consulta [ENTRENAMIENTO.md](ENTRENAMIENTO.md) para preparar el entorno y ejecutar. Los artefactos quedan bajo `outputs/experiments/`. Los pesos `.pth` se excluyen de Git mediante `.gitignore`; métricas, historiales y matrices de confusión se conservan.
