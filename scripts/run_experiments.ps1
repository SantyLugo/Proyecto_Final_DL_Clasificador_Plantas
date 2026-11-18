param(
    [string]$Python = ".\.venv\Scripts\python.exe",
    [string]$Config = "configs/plantclef.json",
    [string]$Experiments = "configs/experiments.json"
)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
if (-not (Test-Path $Python)) {
    throw "Python no se encontro en '$Python'. Crea el entorno virtual e instala requirements.txt."
}
$OutputDir = Join-Path $ProjectRoot "outputs\experiments"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$TranscriptPath = Join-Path $OutputDir "run.log"
Start-Transcript -Path $TranscriptPath -Append | Out-Null
try {
    Write-Output "Inicio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Output "Python: $Python"
    & $Python scripts/prepare_splits.py --config $Config
    if ($LASTEXITCODE -ne 0) { throw "Fallo la preparacion de splits." }
    $env:PYTHONPATH = Join-Path $ProjectRoot "src"
    & $Python -u -m plantclef.train --config $Config --experiments $Experiments
    if ($LASTEXITCODE -ne 0) { throw "Fallo el entrenamiento de los experimentos." }
    Write-Output "Finalizado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}
finally {
    Stop-Transcript | Out-Null
}
