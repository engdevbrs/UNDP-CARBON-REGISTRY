param(
    [switch]$SkipYarnInstall = $false,
    [switch]$SkipDockerBuild = $false
)

$ErrorActionPreference = "Stop"

function Write-Info($Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Invoke-InRepo($ScriptBlock) {
    $repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    Push-Location $repoRoot
    try {
        & $ScriptBlock
    }
    finally {
        Pop-Location
    }
}

Invoke-InRepo {
    Write-Info "Creando archivos CSV requeridos"
    foreach ($file in @("users.csv", "organisations.csv")) {
        if (Test-Path $file) {
            if ((Get-Item $file).PSIsContainer) {
                Write-Info "Eliminando directorio existente $file"
                Remove-Item $file -Recurse -Force
            }
        }
        if (-not (Test-Path $file)) {
            Write-Info "Creando $file"
            New-Item $file -ItemType File | Out-Null
        }
    }

    if (-not $SkipYarnInstall) {
        Write-Info "Instalando dependencias de backend con yarn"
        Push-Location ".\backend\services"
        try {
            yarn install
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Info "Saltando instalación de dependencias (SkipYarnInstall)"
    }

    Write-Info "Deteniendo contenedores previos"
    docker compose down --remove-orphans | Out-Null

    $composeArgs = @("compose", "up", "-d")
    if (-not $SkipDockerBuild) {
        $composeArgs += "--build"
    }

    Write-Info "Levantando base de datos"
    & docker @composeArgs "db"

    Write-Info "Esperando a que PostgreSQL responda"
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        docker exec db pg_isready -U root -d postgres | Out-Null 2>$null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
    }

    if (-not $ready) {
        throw "PostgreSQL no respondió a tiempo. Revisa el contenedor 'db'."
    }

    Write-Info "Levantando servicios national, stats, replicator y web"
    & docker @composeArgs "national" "stats" "replicator" "web"

    Write-Host ""
    Write-Info "Servicios disponibles:"
    Write-Host "  Frontend:   http://localhost:3030/" -ForegroundColor Green
    Write-Host "  API:        http://localhost:3000/national#/" -ForegroundColor Green
    Write-Host "  Estadísticas: http://localhost:3100/stats#/" -ForegroundColor Green
}

