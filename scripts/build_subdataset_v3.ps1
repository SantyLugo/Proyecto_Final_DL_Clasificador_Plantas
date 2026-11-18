param(
    [string]$Archive = 'C:\Users\User\Downloads\PlantCLEF2024singleplanttrainingdata_800_max_side_size.tar',
    [string]$Metadata = 'C:\Users\User\Downloads\PlantCLEF2024singleplanttrainingdata.csv',
    [string]$OutputRoot = 'C:\Users\User\Documents\Clases\DeepLearning\Proyecto Final\PlantCLEF_Subdataset_4000_v3'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$selectionFile = Join-Path $projectRoot 'configs\selection_v3.csv'
$outputRoot = $OutputRoot
$stagingRoot = Join-Path $outputRoot '_staging'
$tempList = Join-Path $outputRoot '_tar_members.txt'
$seed = 'PlantCLEF-v3-4000-profile-family-seed-42'
$organs = @('leaf', 'flower', 'fruit', 'habit')
$redistributionOrder = @('flower', 'fruit', 'habit', 'leaf')

if (Test-Path $outputRoot) {
    throw "La ruta de salida ya existe; no se sobrescribirá: $outputRoot"
}
foreach ($path in @($Archive, $Metadata, $selectionFile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "No se encontró el archivo requerido: $path" }
}

New-Item -ItemType Directory -Path $outputRoot, $stagingRoot | Out-Null
$selection = Import-Csv -LiteralPath $selectionFile
$byId = @{}
foreach ($item in $selection) {
    if ($byId.ContainsKey($item.species_id)) { throw "ID duplicado en selection_v3.csv: $($item.species_id)" }
    $byId[$item.species_id] = $item
}
if ($selection.Count -ne 20) { throw "La selección debe tener exactamente 20 clases; tiene $($selection.Count)." }

Add-Type -AssemblyName Microsoft.VisualBasic
$parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($Metadata)
$parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
$parser.SetDelimiters(';')
$parser.HasFieldsEnclosedInQuotes = $true
$header = $parser.ReadFields()
$columns = @{}
for ($i = 0; $i -lt $header.Length; $i++) { $columns[$header[$i]] = $i }
foreach ($column in @('image_name','organ','species_id','obs_id','license','author','species','family','learn_tag','url')) {
    if (-not $columns.ContainsKey($column)) { throw "La metadata no contiene el campo requerido: $column" }
}

$recordsById = @{}
foreach ($id in $byId.Keys) { $recordsById[$id] = [System.Collections.Generic.List[object]]::new() }
$readCount = 0
try {
    while (-not $parser.EndOfData) {
        $row = $parser.ReadFields()
        $readCount++
        if ($row[$columns['learn_tag']] -ne 'train') { continue }
        $id = $row[$columns['species_id']]
        if (-not $recordsById.ContainsKey($id)) { continue }
        $organ = $row[$columns['organ']]
        if ($organs -notcontains $organ) { continue }
        $recordsById[$id].Add([pscustomobject]@{
            image_name = $row[$columns['image_name']]
            organ = $organ
            species_id = $id
            obs_id = $row[$columns['obs_id']]
            license = $row[$columns['license']]
            author = $row[$columns['author']]
            scientific_name = $row[$columns['species']]
            family = $row[$columns['family']]
            source_url = $row[$columns['url']]
        })
        if ($readCount % 250000 -eq 0) { Write-Host "Metadata revisada: $readCount filas" }
    }
} finally { $parser.Close() }

$sha = [System.Security.Cryptography.SHA256]::Create()
$selected = [System.Collections.Generic.List[object]]::new()
$classRows = [System.Collections.Generic.List[object]]::new()
$memberPaths = [System.Collections.Generic.List[string]]::new()
foreach ($item in $selection) {
    $id = $item.species_id
    $records = @($recordsById[$id])
    if ($records.Count -lt 200) { throw "La clase $id solo tiene $($records.Count) imágenes elegibles." }
    $orderedByOrgan = @{}
    foreach ($organ in $organs) {
        $orderedByOrgan[$organ] = @($records | Where-Object organ -eq $organ | ForEach-Object {
            $keyText = "$seed|$id|$organ|$($_.image_name)"
            $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($keyText))).Replace('-', '')
            [pscustomobject]@{ Key = $hash; Row = $_ }
        } | Sort-Object Key | ForEach-Object Row)
    }
    $chosenForClass = [System.Collections.Generic.List[object]]::new()
    $chosenNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $perOrgan = @{ leaf = 0; flower = 0; fruit = 0; habit = 0 }
    foreach ($organ in $organs) {
        $take = [Math]::Min(50, $orderedByOrgan[$organ].Count)
        for ($i = 0; $i -lt $take; $i++) {
            $row = $orderedByOrgan[$organ][$i]
            $chosenForClass.Add($row); [void]$chosenNames.Add($row.image_name); $perOrgan[$organ]++
        }
    }
    $remaining = 200 - $chosenForClass.Count
    foreach ($organ in $redistributionOrder) {
        if ($remaining -le 0) { break }
        $available = @($orderedByOrgan[$organ] | Where-Object { -not $chosenNames.Contains($_.image_name) })
        $take = [Math]::Min($remaining, $available.Count)
        for ($i = 0; $i -lt $take; $i++) {
            $row = $available[$i]
            $chosenForClass.Add($row); [void]$chosenNames.Add($row.image_name); $perOrgan[$organ]++; $remaining--
        }
    }
    if ($remaining -ne 0) { throw "No fue posible completar 200 imágenes para la clase $id." }
    $metadataNames = @($chosenForClass | ForEach-Object image_name | Sort-Object -Unique)
    if ($metadataNames.Count -ne 200) { throw "Nombres de imagen repetidos en la selección de $id." }
    $reference = $chosenForClass[0]
    $families = @($records | ForEach-Object family | Sort-Object -Unique)
    $names = @($records | ForEach-Object scientific_name | Sort-Object -Unique)
    if ($families.Count -ne 1 -or $names.Count -ne 1) { throw "Taxonomía inconsistente en metadata para $id." }
    $classFolder = $names[0] -replace '[^A-Za-z0-9]+', '_'
    $classFolder = $classFolder.Trim('_')
    $classFolder = "${id}_${classFolder}_$($item.toxicological_profile -replace '[^A-Za-z0-9]+','_')"
    foreach ($row in $chosenForClass) {
        $member = "images_max_side_800/$id/$($row.image_name)"
        $memberPaths.Add($member)
        $selected.Add([pscustomobject]@{
            image_path = "imagenes/$classFolder/$($row.image_name)"
            filename = $row.image_name
            species_id = $id
            scientific_name = $names[0]
            family = $families[0]
            toxicological_profile = $item.toxicological_profile
            toxicological_note = $item.toxicological_note
            toxicity_evidence_url = $item.evidence_url
            organ = $row.organ
            obs_id = $row.obs_id
            source_partition = 'train'
            source_tar_path = $member
            license = $row.license
            author = $row.author
            source_url = $row.source_url
        })
    }
    $classRows.Add([pscustomobject]@{
        species_id = $id
        scientific_name = $names[0]
        family = $families[0]
        toxicological_profile = $item.toxicological_profile
        image_count = 200
        leaf_count = $perOrgan.leaf
        flower_count = $perOrgan.flower
        fruit_count = $perOrgan.fruit
        habit_count = $perOrgan.habit
        source_train_images_allowed_organs = $records.Count
        source_unique_obs_allowed_organs = @($records | ForEach-Object obs_id | Sort-Object -Unique).Count
        class_folder = $classFolder
        toxicological_note = $item.toxicological_note
        toxicity_evidence_url = $item.evidence_url
    })
    Write-Host "$id $($names[0]) [$($item.toxicological_profile)]: leaf=$($perOrgan.leaf), flower=$($perOrgan.flower), fruit=$($perOrgan.fruit), habit=$($perOrgan.habit)"
}
$sha.Dispose()

$selected | Export-Csv -LiteralPath (Join-Path $outputRoot 'labels.csv') -NoTypeInformation -Encoding UTF8
$classRows | Export-Csv -LiteralPath (Join-Path $outputRoot 'classes.csv') -NoTypeInformation -Encoding UTF8
Write-Host 'Extrayendo temporalmente solo las carpetas de las 20 clases del TAR...'
# 20 patrones de carpeta son mucho más eficientes que comparar 4.000 rutas
# concretas contra cada entrada del archivo TAR. Solo las 4.000 filas elegidas
# se copian al subdataset final; el staging se borra al terminar.
$classPatterns = @($selection | ForEach-Object { "images_max_side_800/$($_.species_id)/*" })
& tar.exe -x -f $Archive -C $stagingRoot @classPatterns
if ($LASTEXITCODE -ne 0) { throw "tar.exe terminó con código $LASTEXITCODE" }

foreach ($row in $selected) {
    $source = Join-Path $stagingRoot ($row.source_tar_path -replace '/', '\')
    $target = Join-Path $outputRoot ($row.image_path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "No se extrajo un archivo esperado: $source" }
    $targetDirectory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDirectory)) { New-Item -ItemType Directory -Path $targetDirectory | Out-Null }
    Copy-Item -LiteralPath $source -Destination $target
}
Remove-Item -LiteralPath $stagingRoot -Recurse -Force
Remove-Item -LiteralPath $tempList -Force -ErrorAction SilentlyContinue

$profileMap = @('Comestible','Comestible con precaución','Levemente tóxica','Altamente tóxica')
$families = @($classRows | Group-Object family | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{ family_index = [array]::IndexOf(@($classRows | ForEach-Object family | Sort-Object -Unique), $_.Name); family = $_.Name; species_count = $_.Count; image_count = $_.Count * 200 }
})
$families | Export-Csv -LiteralPath (Join-Path $outputRoot 'families.csv') -NoTypeInformation -Encoding UTF8
for ($i = 0; $i -lt $profileMap.Count; $i++) {
    [pscustomobject]@{ profile_index = $i; toxicological_profile = $profileMap[$i] } | Export-Csv -LiteralPath (Join-Path $outputRoot 'toxicological_profiles.csv') -NoTypeInformation -Encoding UTF8 -Append:$($i -gt 0)
}

$manifest = [ordered]@{
    dataset_version = 'v3'
    source_dataset = 'PlantCLEF 2024 single-plant training data, max side 800'
    source_archive = [System.IO.Path]::GetFileName($Archive)
    source_metadata = [System.IO.Path]::GetFileName($Metadata)
    source_partition = 'train'
    image_count = $selected.Count
    class_count = $classRows.Count
    images_per_class = 200
    toxicological_profile_counts = @($selected | Group-Object toxicological_profile | Sort-Object Name | ForEach-Object { [ordered]@{profile=$_.Name; image_count=$_.Count; species_count=($_.Group | Select-Object -ExpandProperty species_id -Unique).Count} })
    family_counts = $families
    included_organs = [ordered]@{ leaf=($selected | Where-Object organ -eq 'leaf').Count; flower=($selected | Where-Object organ -eq 'flower').Count; fruit=($selected | Where-Object organ -eq 'fruit').Count; habit=($selected | Where-Object organ -eq 'habit').Count }
    excluded_organs = @('bark','branch','scan')
    selection_seed = $seed
    selection_method = 'Deterministic SHA-256 order without replacement, 200 images/class, approximately 50 per eligible organ; redistributes shortages flower, fruit, habit, then leaf.'
    observation_policy = 'Distinct photographs from the same obs_id are retained. Keep all rows sharing obs_id together in one train/validation/test split.'
    original_data_modified = $false
    image_root = 'imagenes/'
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'sampling_manifest.json') -Encoding UTF8

$readme = @'
# PlantCLEF Subdataset — versión 3

## Objetivo

Subconjunto para clasificación multitarea con **prioridad al perfil toxicológico** y una salida auxiliar para **familia botánica**. No identifica por sí solo la seguridad de una planta ni sustituye una consulta toxicológica.

## Composición y criterios conservados de v2

- 4.000 imágenes JPG: 20 especies, 200 por especie.
- 1.000 imágenes por perfil toxicológico: 5 especies por perfil.
- Solo la partición `train` de PlantCLEF 2024.
- Solo órganos `leaf`, `flower`, `fruit` y `habit`; se excluyeron `bark`, `branch` y `scan`.
- Muestreo reproducible sin reemplazo y aproximadamente equilibrado por órgano (50 por órgano cuando hay disponibilidad; las faltantes se redistribuyen).
- Se permiten distintas fotografías de una observación. `obs_id` se conserva: todas las imágenes con el mismo `obs_id` deben quedar en el mismo split.
- El dataset fuente y las versiones v1/v2 no se modifican.

- 10 familias: dos especies y 400 imágenes por familia.

## Archivos

- `imagenes/`: imágenes organizadas por ID, nombre científico y perfil.
- `labels.csv`: una fila por imagen con especie, familia, perfil, órgano, `obs_id`, licencia y procedencia.
- `classes.csv`: inventario por especie y conteo de imágenes.
- `families.csv`: codificación de las familias para la cabeza auxiliar.
- `toxicological_profiles.csv`: codificación del objetivo toxicológico principal.
- `sampling_manifest.json`: fuente, semilla, reglas y conteos.
- `toxicology_evidence.md`: criterios, límites y referencias de respaldo.

## Etiquetas y límites

Los cuatro perfiles son categorías operativas para este experimento, no una escala clínica universal. La toxicidad varía por órgano vegetal, dosis, vía, preparación y organismo. Los perfiles de comestibilidad se refieren a las partes/preparaciones documentadas. Los perfiles leve/alta resumen el peligro toxicológico conocido y no son una garantía de seguridad. `PlantCLEF` aporta taxonomía e imágenes; la evidencia de toxicidad procede de las fuentes indicadas en `toxicology_evidence.md`.
'@
$readme | Set-Content -LiteralPath (Join-Path $outputRoot 'README.md') -Encoding UTF8

$evidence = @(
    '# Evidencia toxicológica y criterios de etiqueta',
    '',
    'Las etiquetas son categorías operativas para clasificación académica, no una escala clínica universal. La toxicidad depende de parte, cantidad, preparación, vía y organismo; el riesgo descrito se anota por especie y no puede inferirse de una foto. La salida del modelo no certificará comestibilidad ni seguridad.',
    '',
    '## Clases seleccionadas',
    '',
    '| ID | Especie | Familia | Perfil | Nota por parte/vía | Fuente |',
    '|---:|---|---|---|---|---|'
)
foreach ($row in $classRows) {
    $note = $row.toxicological_note -replace '\|', '\|'
    $evidence += "| $($row.species_id) | *$($row.scientific_name)* | $($row.family) | $($row.toxicological_profile) | $note | [Fuente]($($row.toxicity_evidence_url)) |"
}
$evidence += @(
    '',
    '## Fundamento del balance',
    '',
    'Cada perfil tiene cinco especies y 1.000 imágenes; cada una de diez familias tiene dos especies y 400 imágenes. Las familias proceden de la metadata PlantCLEF, y el diseño auxiliar incluye más de una especie por familia.',
    '',
    '## Fuentes transversales',
    '',
    '- PlantCLEF 2024 y su metadata: https://www.imageclef.org/PlantCLEF2024',
    '- Revisión clínica de intoxicaciones por plantas: Wendt et al., “Poisoning by Plants”, https://pmc.ncbi.nlm.nih.gov/articles/PMC9453220/',
    '- Potato glycoalkaloids: German Federal Institute for Risk Assessment (BfR), https://www.bfr.bund.de/cm/349/table-potatoes-should-contain-low-levels-of-glycoalkaloids-solanine.pdf',
    '- La metadata original, organ, partición, licencia, autor e identificador `obs_id` quedan documentados por imagen en `labels.csv`.'
)
$evidence -join "`r`n" | Set-Content -LiteralPath (Join-Path $outputRoot 'toxicology_evidence.md') -Encoding UTF8

Write-Host "v3 creada en $outputRoot"
Write-Host "Imágenes: $($selected.Count); especies: $($classRows.Count); familias: $($families.Count)"
$selected | Group-Object toxicological_profile | Sort-Object Name | ForEach-Object { Write-Host "$($_.Name): $($_.Count) imágenes / $(($_.Group | Select-Object -ExpandProperty species_id -Unique).Count) especies" }


