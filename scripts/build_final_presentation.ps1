param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ReferenceDeck = "C:\Users\User\Downloads\Proyecto_Clasificacion_Jerarquica_Plantas.pptx",
    [string]$OutputName = "Presentacion_Final_PlantCLEF.pptx"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$Source = [IO.Path]::GetFullPath($ReferenceDeck)
$Output = Join-Path $ProjectRoot $OutputName
if (-not (Test-Path $Source)) { throw "Reference deck not found: $Source" }
if (Test-Path $Output) { throw "Output already exists; choose another OutputName: $Output" }
$ExperimentRoot = Join-Path $ProjectRoot "outputs\experiments"
$Names = @("baseline_frozen_lr001", "frozen_dropout03", "frozen_lr01", "last_block_finetune")
$Summaries = @{}
$Histories = @{}
foreach ($name in $Names) {
    $dir = Join-Path $ExperimentRoot $name
    $Summaries[$name] = Get-Content (Join-Path $dir "summary.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $Histories[$name] = @(Import-Csv (Join-Path $dir "history.csv") -Encoding UTF8)
    if ($Summaries[$name].epochs_completed -ne 30) { throw "$name has not completed all 30 epochs." }
}
$Comparison = @(Import-Csv (Join-Path $ExperimentRoot "comparison.csv") -Encoding UTF8)
$FamilyNames = @("Amaryllidaceae", "Apiaceae", "Asparagaceae", "Caprifoliaceae", "Moraceae", "Plantaginaceae", "Ranunculaceae", "Rosaceae", "Solanaceae", "Urticaceae")
$Colors = @{ Dark="304B32"; Olive="638A4D"; Bright="7CCF4B"; Ink="41443E"; Paper="F8F7F2"; Pale="E8E9E1"; Orange="D9822B"; Mid="9AA38D"; White="FFFFFF"; Red="A94E3F" }
$Culture = [Globalization.CultureInfo]::InvariantCulture

function U {
    param([string]$Text)
    return [regex]::Replace($Text, '\\u([0-9a-fA-F]{4})', { param($m) [char][Convert]::ToInt32($m.Groups[1].Value, 16) })
}
function Fmt {
    param([double]$Value, [int]$Digits=3)
    return $Value.ToString("0." + ("0" * $Digits), $Culture).Replace('.', ',')
}
function XmlEsc { param([string]$Text) return [System.Security.SecurityElement]::Escape($Text) }
function Px { param([double]$Value) return [long][math]::Round($Value * 9525) }
function ResetSlide { $script:Parts = [System.Collections.Generic.List[string]]::new(); $script:ShapeId = 2 }
function AddText {
    param([double]$X,[double]$Y,[double]$W,[double]$H,[string]$Text,[int]$Pt=18,[string]$Color="41443E",[bool]$Bold=$false,[string]$Align="l")
    $script:ShapeId++
    $id=$script:ShapeId; $escaped=XmlEsc (U $Text); $boldValue=if($Bold){"1"}else{"0"}; $fontSize=$Pt*100
    $paragraphs = foreach($line in ($escaped -split "`n")) {
        "<a:p><a:pPr algn='$Align' marL='0' indent='0'><a:lnSpc><a:spcPct val='110000'/></a:lnSpc><a:buNone/></a:pPr><a:r><a:rPr lang='es-CO' sz='$fontSize' b='$boldValue' dirty='0'><a:solidFill><a:srgbClr val='$Color'/></a:solidFill><a:latin typeface='Aptos'/></a:rPr><a:t xml:space='preserve'>$line</a:t></a:r><a:endParaRPr lang='es-CO' sz='$fontSize'/></a:p>"
    }
    $part="<p:sp><p:nvSpPr><p:cNvPr id='$id' name='Text $id'/><p:cNvSpPr txBox='1'/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x='$(Px $X)' y='$(Px $Y)'/><a:ext cx='$(Px $W)' cy='$(Px $H)'/></a:xfrm><a:prstGeom prst='rect'><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap='square' lIns='0' rIns='0' tIns='0' bIns='0' anchor='t'><a:normAutofit/></a:bodyPr><a:lstStyle/>$($paragraphs -join '')</p:txBody></p:sp>"
    $script:Parts.Add($part)
}
function AddRect {
    param([double]$X,[double]$Y,[double]$W,[double]$H,[string]$Fill,[string]$Geom="rect")
    $script:ShapeId++; $id=$script:ShapeId
    $script:Parts.Add("<p:sp><p:nvSpPr><p:cNvPr id='$id' name='Shape $id'/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x='$(Px $X)' y='$(Px $Y)'/><a:ext cx='$(Px $W)' cy='$(Px $H)'/></a:xfrm><a:prstGeom prst='$Geom'><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val='$Fill'/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>")
}
function AddLine {
    param([double]$X1,[double]$Y1,[double]$X2,[double]$Y2,[string]$Color="638A4D",[int]$Width=2)
    $script:ShapeId++; $id=$script:ShapeId
    $left=[math]::Min($X1,$X2); $top=[math]::Min($Y1,$Y2); $w=[math]::Max(1,[math]::Abs($X2-$X1)); $h=[math]::Max(1,[math]::Abs($Y2-$Y1))
    $flip=if(($X2-$X1)*($Y2-$Y1) -lt 0){" flipV='1'"}else{""}
    $script:Parts.Add("<p:cxnSp><p:nvCxnSpPr><p:cNvPr id='$id' name='Line $id'/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr><a:xfrm$flip><a:off x='$(Px $left)' y='$(Px $top)'/><a:ext cx='$(Px $w)' cy='$(Px $h)'/></a:xfrm><a:prstGeom prst='line'><a:avLst/></a:prstGeom><a:ln w='$(($Width*12700))'><a:solidFill><a:srgbClr val='$Color'/></a:solidFill><a:prstDash val='solid'/></a:ln></p:spPr></p:cxnSp>")
}
function AddHeader {
    param([string]$Title,[int]$Page,[string]$Section="PROYECTO DE INVESTIGACION",[string]$Sub="")
    AddText 58 28 680 24 $Section 11 $Colors.Olive $true
    AddText 58 64 1160 58 $Title 26 $Colors.Dark $true
    AddRect 58 130 1160 2 $Colors.Pale
    if($Sub){AddText 60 142 1120 42 $Sub 14 $Colors.Ink $false}
    AddText 58 680 920 20 (U "Santiago Lugo Camacho  ·  Universidad El Bosque") 10 $Colors.Ink
    AddText 1130 680 80 20 ("{0:D2}" -f $Page) 10 $Colors.Olive $true "r"
}
function DrawPlotFrame {
    param([double]$X,[double]$Y,[double]$W,[double]$H,[double]$Min,[double]$Max,[string]$Label)
    AddText $X ($Y-30) $W 22 $Label 13 $Colors.Dark $true
    foreach($tick in 0..4){
        $yy=$Y+$H-($H*$tick/4)
        AddLine $X $yy ($X+$W) $yy $Colors.Pale 1
        $value=$Min+($Max-$Min)*$tick/4
        AddText ($X-42) ($yy-10) 38 18 (Fmt $value 1) 9 $Colors.Ink $false "r"
    }
    AddLine $X $Y $X ($Y+$H) $Colors.Mid 1
    AddLine $X ($Y+$H) ($X+$W) ($Y+$H) $Colors.Mid 1
    AddText $X ($Y+$H+5) 60 17 "1" 9 $Colors.Ink
    AddText ($X+$W-52) ($Y+$H+5) 52 17 "30" 9 $Colors.Ink $false "r"
}
function AddSeries {
    param([double[]]$Values,[double]$X,[double]$Y,[double]$W,[double]$H,[double]$Min,[double]$Max,[string]$Color,[int]$Width=2)
    if($Values.Count -lt 2){return}
    for($i=1;$i -lt $Values.Count;$i++){
        $x1=$X+($i-1)*$W/($Values.Count-1); $x2=$X+$i*$W/($Values.Count-1)
        $v1=[math]::Min($Max,[math]::Max($Min,$Values[$i-1])); $v2=[math]::Min($Max,[math]::Max($Min,$Values[$i]))
        $y1=$Y+$H-(($v1-$Min)/($Max-$Min))*$H; $y2=$Y+$H-(($v2-$Min)/($Max-$Min))*$H
        AddLine $x1 $y1 $x2 $y2 $Color $Width
    }
}
function FinishSlide {
    $shapes=$script:Parts -join ''
    return "<?xml version='1.0' encoding='UTF-8' standalone='yes'?><p:sld xmlns:a='http://schemas.openxmlformats.org/drawingml/2006/main' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships' xmlns:p='http://schemas.openxmlformats.org/presentationml/2006/main' showMasterSp='0'><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val='$($Colors.Paper)'/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id='1' name=''/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x='0' y='0'/><a:ext cx='0' cy='0'/><a:chOff x='0' y='0'/><a:chExt cx='0' cy='0'/></a:xfrm></p:grpSpPr>$shapes</p:spTree><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:cSld></p:sld>"
}
function AddLegend { param([double]$X,[double]$Y,[string]$Color,[string]$Text); AddLine $X ($Y+8) ($X+28) ($Y+8) $Color 3; AddText ($X+36) $Y 180 20 $Text 10 $Colors.Ink }
function Get-Values { param($Rows,[string]$Column); return [double[]]@($Rows | ForEach-Object {[double]::Parse($_.$Column,$Culture)}) }
function AddCurveSlide {
    param([string]$Name,[int]$Page,[string]$Title,[string]$Descriptor)
    ResetSlide; AddHeader $Title $Page "CURVAS DE ENTRENAMIENTO" $Descriptor
    $rows=$Histories[$Name]
    $lossTrain=Get-Values $rows "train_loss"; $lossVal=Get-Values $rows "validation_loss"; $f1=Get-Values $rows "validation_toxicity_macro_f1"
    $lossMax=[math]::Max(1.5, [math]::Ceiling((($lossTrain+$lossVal)|Measure-Object -Maximum).Maximum*2)/2)
    DrawPlotFrame 100 250 600 300 0 $lossMax "Pérdida"
    AddSeries $lossTrain 100 250 600 300 0 $lossMax $Colors.Olive 2
    AddSeries $lossVal 100 250 600 300 0 $lossMax $Colors.Orange 2
    AddLegend 120 575 $Colors.Olive "Entrenamiento"; AddLegend 310 575 $Colors.Orange "Validación"
    DrawPlotFrame 790 250 390 300 0 1 "Macro-F1 toxicológico en validación"
    AddSeries $f1 790 250 390 300 0 1 $Colors.Dark 3
    $summary=$Summaries[$Name]
    AddText 790 580 380 35 ((U "Mejor época: ")+ $summary.best_epoch + (U "  ·  macro-F1: ")+ (Fmt ([double]$summary.best_validation_toxicity_macro_f1) 3)) 12 $Colors.Dark $true
    AddText 60 615 1120 28 (U "El checkpoint guardado corresponde a la mejor macro-F1 toxicológica de validación.") 11 $Colors.Ink
    return FinishSlide
}

$ToxicityNames = @("Comestible", (U 'Comestible con precauci\u00f3n'), (U 'Levemente t\u00f3xica'), (U 'Altamente t\u00f3xica'))

$slideXmls=[System.Collections.Generic.List[string]]::new()

# 1. Portada
ResetSlide
AddRect 0 0 18 720 $Colors.Olive
AddText 62 42 520 24 (U "INVESTIGACIÓN EN VISIÓN COMPUTACIONAL") 12 $Colors.White $true
AddText 585 72 580 25 (U "DEEP LEARNING  ·  BOTÁNICA") 12 $Colors.Olive $true
AddText 585 132 630 135 (U "Clasificación de plantas") 42 $Colors.Dark $true
AddText 588 278 610 80 (U "Perfil toxicológico principal y familia botánica auxiliar") 21 $Colors.Ink
AddText 590 410 570 78 (U "PlantCLEF 2024  ·  4.000 imágenes  ·  20 especies") 17 $Colors.Olive $true
AddText 590 520 520 82 (U "Santiago Lugo Camacho`nUniversidad El Bosque`nIntroducción al Deep Learning") 14 $Colors.Ink
AddText 588 664 590 25 (U "Entrega final  ·  evaluación en conjunto de prueba") 12 $Colors.Olive $true
$slideXmls.Add((FinishSlide))

# 2. Contexto, datos y pregunta
ResetSlide; AddHeader (U "PlantCLEF 2024 y pregunta de investigación") 2
AddText 68 178 500 46 (U "4.000 imágenes") 33 $Colors.Dark $true
AddText 68 229 500 34 (U "20 especies · 200 imágenes por especie") 16 $Colors.Ink
AddText 68 292 500 46 (U "4 perfiles toxicológicos") 26 $Colors.Olive $true
AddText 68 335 500 32 (U "1.000 imágenes en cada perfil") 16 $Colors.Ink
AddText 68 396 500 46 (U "10 familias botánicas") 26 $Colors.Dark $true
AddText 68 440 500 32 (U "2 especies y 400 imágenes por familia") 16 $Colors.Ink
AddRect 622 180 4 390 $Colors.Bright
AddText 660 180 520 31 (U "PREGUNTA") 13 $Colors.Olive $true
AddText 660 225 520 150 (U "¿Cómo clasificar imágenes de plantas priorizando el perfil toxicológico y mostrando como información adicional la familia botánica?") 22 $Colors.Dark $true
AddText 660 410 520 128 (U "PlantCLEF aporta imágenes y taxonomía. La evidencia de riesgo se documentó por especie con fuentes botánicas y toxicológicas externas.") 16 $Colors.Ink
$slideXmls.Add((FinishSlide))

# 3. EDA evolution and challenges
ResetSlide; AddHeader (U "Evolución del EDA y dificultades") 3
$stages=@(
    @{X=58; N="01"; T="v1 · 20 clases"; C=$Colors.Olive; B=(U "200 imágenes por especie, pero perfiles desbalanceados: 4 comestibles, 5 con precaución, 1 levemente tóxica y 10 altamente tóxicas.")},
    @{X=350; N="02"; T="v2 · órganos"; C=$Colors.Bright; B=(U "Se equilibraron hoja, flor, fruto y planta completa. Hyoscyamus niger solo tenía 44 imágenes de planta completa; se redistribuyeron seis plazas.")},
    @{X=642; N="03"; T="v3 borrador"; C=$Colors.Orange; B=(U "El primer diseño tenía 16 familias para 20 especies. Algunas familias tenían una sola especie, lo que limitaba la tarea auxiliar.")},
    @{X=934; N="04"; T="v3 final"; C=$Colors.Dark; B=(U "Se eligieron 10 familias con dos especies cada una y cinco especies por perfil toxicológico. Total: 4.000 imágenes.")}
)
foreach($s in $stages){ AddText $s.X 180 250 38 $s.N 24 $s.C $true; AddRect $s.X 222 252 4 $s.C; AddText $s.X 241 260 48 $s.T 18 $Colors.Dark $true; AddText $s.X 300 260 260 $s.B 14 $Colors.Ink }
AddRect 58 585 1160 2 $Colors.Pale
AddText 60 601 1130 58 (U "Dificultades clave: obtener la metadata oficial; justificar el riesgo con evidencia externa; manejar la disponibilidad desigual por órgano; y distinguir vistas distintas de duplicados exactos. Las vistas de una misma observación se conservaron y se agruparon por obs_id en los splits.") 13 $Colors.Ink
$slideXmls.Add((FinishSlide))

# 4. Design
ResetSlide; AddHeader (U "Diseño experimental") 4 (U "MODELO Y CONDICIONES COMUNES") (U "Objetivo principal: perfil toxicológico · salida auxiliar: familia")
AddText 64 203 220 48 (U "EfficientNet-B0") 22 $Colors.Dark $true
AddText 64 254 250 75 (U "Pesos ImageNet`nDos cabezas de salida") 15 $Colors.Ink
AddText 360 203 220 48 (U "30 épocas") 22 $Colors.Olive $true
AddText 360 254 250 75 (U "Adam · batch 32`nImágenes 192 × 192") 15 $Colors.Ink
AddText 650 203 220 48 (U "Pérdida multitarea") 22 $Colors.Dark $true
AddText 650 254 250 75 (U "Toxicidad 1,0`nFamilia 0,25") 15 $Colors.Ink
AddText 940 203 250 48 (U "Split por observación") 21 $Colors.Olive $true
AddText 940 254 260 75 (U "70 / 15 / 15`n2.800 / 600 / 600 imágenes") 15 $Colors.Ink
AddRect 60 360 1150 2 $Colors.Pale
$rows=@(
    @("Base", "Backbone congelado", "LR 0,001", "Sin dropout"),
    @("Dropout", "Backbone congelado", "LR 0,001", "p = 0,3"),
    @("LR alta", "Backbone congelado", "LR 0,01", "Sin dropout"),
    @("Ajuste parcial", "Último bloque libre", "Cabeza 0,001 · bloque 0,0001", "Sin dropout")
)
$heads=@("EXPERIMENTO", "CONGELAMIENTO", "TASA DE APRENDIZAJE", "DROPOUT")
$xs=@(66,285,590,935); $ws=@(205,285,330,240)
for($i=0;$i -lt 4;$i++){AddText $xs[$i] 382 $ws[$i] 24 $heads[$i] 10 $Colors.Olive $true}
for($r=0;$r -lt $rows.Count;$r++){ $yy=419+$r*46; for($c=0;$c -lt 4;$c++){AddText $xs[$c] $yy $ws[$c] 30 $rows[$r][$c] 13 $Colors.Ink ($c -eq 0)}; if($r -lt 3){AddRect 64 ($yy+34) 1135 1 $Colors.Pale} }
$slideXmls.Add((FinishSlide))

# 5. Validation ranking
ResetSlide; AddHeader (U "Validación: el ajuste parcial lidera") 5 (U "COMPARACIÓN DE EXPERIMENTOS") (U "Macro-F1 del perfil toxicológico en el mejor checkpoint de validación")
$valRows=@(); foreach($name in $Names){$s=$Summaries[$name];$valRows+= [pscustomobject]@{Name=$name; Score=[double]$s.best_validation_toxicity_macro_f1; Epoch=$s.best_epoch}}
$labels=@("Base", "Dropout 0,3", "LR 0,01", "Ajuste parcial")
$barX=280; $barY=230; $maxW=750; $barH=42
for($i=0;$i -lt 4;$i++){
    $yy=$barY+$i*82; AddText 66 ($yy+7) 198 32 $labels[$i] 16 $Colors.Dark ($i -eq 3)
    AddRect $barX $yy $maxW $barH $Colors.Pale
    $width=$maxW*$valRows[$i].Score
    $fill=if($i -eq 3){$Colors.Bright}else{$Colors.Olive}
    AddRect $barX $yy $width $barH $fill
    AddText ($barX+$maxW+18) ($yy+5) 130 35 ((Fmt $valRows[$i].Score 3)+"  ·  ep "+$valRows[$i].Epoch) 14 $Colors.Dark $true
}
AddText 66 575 1120 58 (U "El ajuste parcial obtuvo macro-F1 0,778 en validación. Se eligió por esta métrica antes de interpretar su resultado de test.") 16 $Colors.Ink
$slideXmls.Add((FinishSlide))

# 6-9. Four per-model learning curve slides
$curveTitles=@(
    (U "A1 · EfficientNet-B0 congelada"),
    (U "A2 · Backbone congelado + dropout"),
    (U "A3 · Tasa de aprendizaje 0,01"),
    (U "A4 · Ajuste parcial del último bloque")
)
$curveDesc=@(
    (U "Referencia · Adam 0,001 · sin dropout"),
    (U "Dropout 0,3 en ambas cabezas · Adam 0,001"),
    (U "Prueba de una tasa diez veces mayor · Adam 0,01"),
    (U "Último bloque descongelado · LR 0,0001 en backbone")
)
for($i=0;$i -lt 4;$i++){ $slideXmls.Add((AddCurveSlide $Names[$i] (6+$i) $curveTitles[$i] $curveDesc[$i])) }

# 10. Joint validation curves
ResetSlide; AddHeader (U "Comparación conjunta de validación") 10 (U "EVOLUCIÓN POR ÉPOCA") (U "Macro-F1 toxicológico · una curva por configuración")
DrawPlotFrame 135 230 900 340 0 1 (U "Macro-F1 de validación")
$lineColors=@($Colors.Olive,$Colors.Orange,$Colors.Mid,$Colors.Dark)
for($i=0;$i -lt 4;$i++){ $vals=Get-Values $Histories[$Names[$i]] "validation_toxicity_macro_f1"; AddSeries $vals 135 230 900 340 0 1 $lineColors[$i] 3; AddLegend (82+($i%2)*250) (592+[math]::Floor($i/2)*24) $lineColors[$i] $labels[$i] }
AddText 1060 244 150 84 (U "Mejor valor") 12 $Colors.Ink
AddText 1060 274 155 48 "0,778" 26 $Colors.Dark $true
AddText 1060 326 155 58 (U "Época 18 · ajuste parcial") 12 $Colors.Ink
$slideXmls.Add((FinishSlide))

# 11. Test results comparison
ResetSlide; AddHeader 'Test final: ajuste parcial con mejor macro-F1' 11 'EVALUACION COMPARATIVA' 'Checkpoint elegido con validacion; test reportado por separado'
$tableRows=@()
foreach($i in 0..3){$s=$Summaries[$Names[$i]];$tableRows+=,@($labels[$i],(Fmt ([double]$s.test_toxicity.accuracy) 3),(Fmt ([double]$s.test_toxicity.macro_f1) 3),(Fmt ([double]$s.test_family.accuracy) 3),(Fmt ([double]$s.test_family.macro_f1) 3))}
$head=@("MODELO", "ACC. TOX.", "F1 TOX.", "ACC. FAMILIA", "F1 FAMILIA");$tx=@(66,340,525,710,930);$tw=@(250,165,165,195,190)
for($c=0;$c -lt 5;$c++){AddText $tx[$c] 222 $tw[$c] 28 $head[$c] 11 $Colors.Olive $true}
AddRect 64 252 1120 2 $Colors.Olive
for($r=0;$r -lt 4;$r++){ $yy=271+$r*61; if($r -eq 3){AddRect 62 ($yy-5) 1130 50 "E7EEDC"}; for($c=0;$c -lt 5;$c++){AddText $tx[$c] $yy $tw[$c] 35 $tableRows[$r][$c] 15 $Colors.Dark ($r -eq 3 -or $c -eq 0)}; AddRect 64 ($yy+42) 1120 1 $Colors.Pale }
$s=$Summaries["last_block_finetune"]
AddText 66 540 1110 57 ((U "Ganador por validación y mejor resultado observado en test: macro-F1 toxicológico ")+ (Fmt ([double]$s.test_toxicity.macro_f1) 3) + (U "; accuracy ")+ (Fmt ([double]$s.test_toxicity.accuracy) 3) + (U ".")) 16 $Colors.Dark $true
$slideXmls.Add((FinishSlide))

# 12. Toxicology confusion matrix
ResetSlide; AddHeader 'Errores del objetivo principal: perfil toxicologico' 12 'MATRIZ DE CONFUSION · TEST' 'Filas: etiqueta real · columnas: prediccion · 600 imagenes'
$matrixPath=Join-Path $ExperimentRoot "last_block_finetune\toxicity_confusion_test.csv"
$matrix=@(Import-Csv $matrixPath -Encoding UTF8)
$mx=365;$my=258;$cell=150
AddText 300 210 900 25 'PREDICCION' 11 $Colors.Olive $true 'c'
AddText 58 394 150 60 (U "REAL") 11 $Colors.Olive $true
for($c=0;$c -lt 4;$c++){AddText ($mx+$c*$cell) 226 $cell 28 $ToxicityNames[$c] 11 $Colors.Dark $true "c"}
for($r=0;$r -lt 4;$r++){
    AddText 65 ($my+$r*$cell+52) 290 46 $ToxicityNames[$r] 13 $Colors.Dark $true
    for($c=0;$c -lt 4;$c++){
        $value=[int]$matrix[$r].($ToxicityNames[$c]); $fill=if($r -eq $c){$Colors.Bright}else{if($value -ge 20){"EBC5B9"}else{$Colors.Pale}}
        AddRect ($mx+$c*$cell) ($my+$r*$cell) ($cell-8) ($cell-8) $fill
        AddText ($mx+$c*$cell) ($my+$r*$cell+42) ($cell-8) 40 ([string]$value) 22 $Colors.Dark $true "c"
    }
}
AddText 66 620 1130 32 'F1 mas bajo: comestible con precaucion (0,652); mas alto: altamente toxica (0,770).' 14 $Colors.Ink
$slideXmls.Add((FinishSlide))

# 13. Family auxiliary head
ResetSlide; AddHeader (U "Salida auxiliar: familia botánica") 13 (U "10 FAMILIAS · TEST") (U "Accuracy 0,782 · macro-F1 0,783 · 600 imágenes")
$famPath=Join-Path $ExperimentRoot "last_block_finetune\family_confusion_test.csv"; $famRows=@(Import-Csv $famPath -Encoding UTF8)
$abbr=@("Amar","Api","Aspar","Capri","Mora","Plant","Ranun","Rosa","Sola","Urtica")
$fx=290;$fy=254;$fc=50
AddText 288 218 520 23 'PREDICCION' 10 $Colors.Olive $true 'c'
for($c=0;$c -lt 10;$c++){AddText ($fx+$c*$fc) 232 $fc 18 $abbr[$c] 8 $Colors.Dark $true "c"}
for($r=0;$r -lt 10;$r++){
    AddText 62 ($fy+$r*$fc+12) 210 25 $FamilyNames[$r] 10 $Colors.Dark $true
    for($c=0;$c -lt 10;$c++){
        $value=[int]$famRows[$r].($FamilyNames[$c]); $fill=if($r -eq $c){$Colors.Bright}else{if($value -ge 5){"EBC5B9"}else{$Colors.Pale}}
        AddRect ($fx+$c*$fc) ($fy+$r*$fc) ($fc-2) ($fc-2) $fill
        AddText ($fx+$c*$fc) ($fy+$r*$fc+12) ($fc-2) 20 ([string]$value) 9 $Colors.Dark $false "c"
    }
}
AddText 850 275 350 45 (U "Familias con mayor F1") 15 $Colors.Olive $true
AddText 850 324 350 140 (U "Moraceae: 0,822`nPlantaginaceae: 0,810`nAmaryllidaceae: 0,831`nMenor F1: Urticaceae 0,757") 13 $Colors.Ink
AddText 850 490 350 94 (U "La cabeza auxiliar también mejoró con el ajuste parcial frente a las tres alternativas congeladas.") 14 $Colors.Ink
$slideXmls.Add((FinishSlide))

# 14. Conclusions
ResetSlide
AddRect 0 0 1280 720 $Colors.Dark
AddText 64 52 1120 55 (U "Conclusiones y alcance") 30 $Colors.White $true
AddText 64 128 1050 34 (U "MODELO SELECCIONADO · AJUSTE PARCIAL DEL ÚLTIMO BLOQUE") 13 $Colors.Bright $true
AddText 64 188 1050 112 (U "Mejor macro-F1 toxicológico de validación (0,778) y mayor macro-F1 toxicológico en test (0,728) entre los cuatro experimentos.") 24 $Colors.White $true
AddText 64 350 1040 90 (U "En test obtuvo accuracy 0,732 y macro-F1 de familia 0,783. Frente a la base, el macro-F1 toxicológico aumentó 4,5 puntos porcentuales.") 18 $Colors.White
AddText 64 472 1050 82 'Los perfiles son etiquetas operativas respaldadas por fuentes por especie. El modelo no certifica comestibilidad ni seguridad.' 15 $Colors.White
AddText 64 590 1120 52 (U "Una sola semilla y una división. Próximos pasos: repetir con varias semillas, revisar confusiones y documentar incertidumbre.") 15 $Colors.Bright
AddText 64 674 1120 24 (U "Santiago Lugo Camacho  ·  Universidad El Bosque  ·  PlantCLEF 2024") 11 $Colors.White
$slideXmls.Add((FinishSlide))

# Create a working copy of the PlantCLEF progress deck, replace its slides, and add slide 14.
[IO.File]::Copy($Source,$Output,$false)
$zip=[IO.Compression.ZipFile]::Open($Output,[IO.Compression.ZipArchiveMode]::Update)
try {
    $utf8=[Text.UTF8Encoding]::new($false)
    for($i=1;$i -le 14;$i++){
        $entryName="ppt/slides/slide$i.xml"
        $old=$zip.GetEntry($entryName); if($old){$old.Delete()}
        $new=$zip.CreateEntry($entryName,[IO.Compression.CompressionLevel]::Optimal);$stream=$new.Open();$writer=[IO.StreamWriter]::new($stream,$utf8);$writer.Write($slideXmls[$i-1]);$writer.Dispose()
    }
    $relsName="ppt/slides/_rels/slide14.xml.rels"; $old=$zip.GetEntry($relsName); if($old){$old.Delete()}
    $rels="<?xml version='1.0' encoding='UTF-8' standalone='yes'?><Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout' Target='../slideLayouts/slideLayout6.xml'/></Relationships>"
    $e=$zip.CreateEntry($relsName);$w=[IO.StreamWriter]::new($e.Open(),$utf8);$w.Write($rels);$w.Dispose()

    $presEntry=$zip.GetEntry('ppt/presentation.xml');$r=[IO.StreamReader]::new($presEntry.Open());$pres=$r.ReadToEnd();$r.Close();$presEntry.Delete()
    $pres=$pres.Replace('</p:sldIdLst>', "<p:sldId id='269' r:id='rId20'/></p:sldIdLst>")
    $e=$zip.CreateEntry('ppt/presentation.xml');$w=[IO.StreamWriter]::new($e.Open(),$utf8);$w.Write($pres);$w.Dispose()

    $relEntry=$zip.GetEntry('ppt/_rels/presentation.xml.rels');$r=[IO.StreamReader]::new($relEntry.Open());$presRels=$r.ReadToEnd();$r.Close();$relEntry.Delete()
    $presRels=$presRels.Replace('</Relationships>', "<Relationship Id='rId20' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide' Target='slides/slide14.xml'/></Relationships>")
    $e=$zip.CreateEntry('ppt/_rels/presentation.xml.rels');$w=[IO.StreamWriter]::new($e.Open(),$utf8);$w.Write($presRels);$w.Dispose()

    $ctEntry=$zip.GetEntry('[Content_Types].xml');$r=[IO.StreamReader]::new($ctEntry.Open());$ct=$r.ReadToEnd();$r.Close();$ctEntry.Delete()
    $ct=$ct.Replace('</Types>', "<Override PartName='/ppt/slides/slide14.xml' ContentType='application/vnd.openxmlformats-officedocument.presentationml.slide+xml'/></Types>")
    $e=$zip.CreateEntry('[Content_Types].xml');$w=[IO.StreamWriter]::new($e.Open(),$utf8);$w.Write($ct);$w.Dispose()
} finally { $zip.Dispose() }
Write-Output "Created: $Output"
Write-Output ('Slides: {0} | Checkpoint selected by validation macro-F1 | four experiments complete' -f $slideXmls.Count)
