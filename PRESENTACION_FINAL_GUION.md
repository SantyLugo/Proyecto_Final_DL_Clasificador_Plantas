# Guion de presentación final

## Referencias de estructura y diseño

Seguir el orden narrativo de BloodMNIST, en 14 diapositivas: contexto y pregunta, diseño experimental, comparación de validación, curvas individuales, comparación conjunta, test y conclusiones. Adaptar ese orden a las dos salidas de PlantCLEF. Para la apariencia, seguir la presentación de avances: formato 16:9, Aptos y paleta azul petróleo, naranja y verde. Sustituir las cifras del piloto de 500 imágenes por la versión final y preservar el aviso de que la etiqueta de riesgo es informativa, no certifica seguridad.

## Hilo narrativo

1. **Portada** — Clasificación de plantas por perfil toxicológico, con familia botánica auxiliar. Entrega final.
2. **PlantCLEF y pregunta** — 4.000 imágenes, 20 especies, 4 perfiles y 10 familias. Explicar toxicidad como salida principal y familia como salida auxiliar.
3. **Evolución del EDA** — Versiones v1, v2, borrador v3 y dataset v3 final, con los problemas que motivaron cada cambio.
4. **Diseño experimental** — EfficientNet-B0 multitarea, objetivos/pérdidas y cuatro configuraciones comparadas.
5. **Comparación de validación** — Macro-F1 toxicológico en el mejor checkpoint de cada experimento; destacar el ganador provisional.
6. **Curvas del modelo base** — Pérdida y macro-F1 de train/validación durante las épocas.
7. **Curvas con dropout 0,3** — Mismas métricas para comparar con la base.
8. **Curvas con tasa 0,01** — Mismas métricas, señalando la diferencia entre convergencia y generalización.
9. **Curvas con ajuste parcial** — Gráfica final al completar las 30 épocas.
10. **Comparación conjunta** — Evolución de las curvas de validación de los cuatro experimentos.
11. **Evaluación de test** — Métricas finales del modelo seleccionado y resultados por perfil toxicológico; reservar actualización tras test.
12. **Errores de toxicidad** — Matriz de confusión y confusiones más frecuentes del objetivo principal.
13. **Salida auxiliar de familia** — Macro-F1 y matriz de confusión de las diez familias; interpretar su relación con la salida principal.
14. **Conclusiones y alcance** — Ganador por validación, evaluación final, dificultades, límites y próximos pasos.

## Estado de los resultados

- Tres experimentos terminaron las 30 épocas y tienen evaluación en test.
- `last_block_finetune` sigue entrenándose; en el último registro visible llegó a la época 23/30. Su mejor checkpoint guardado corresponde a la época 18, con macro-F1 de validación 0,778.
- Mantener marcadores explícitos para completar las cifras de test y la gráfica del modelo seleccionado. No reutilizar las métricas de validación como resultados de test.

## Fuentes internas para completar la presentación

- Composición y criterios: `PlantCLEF_Subdataset_4000_v3/README.md` y `sampling_manifest.json`.
- Dificultades y evidencia toxicológica: `PlantCLEF_Subdataset_4000_v3/toxicology_evidence.md`.
- Partición: `outputs/splits.csv`.
- Métricas: `outputs/experiments/comparison.csv` y `outputs/experiments/*/summary.json`.
