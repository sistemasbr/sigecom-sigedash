<#
.SYNOPSIS
    Instala o SigeDash Backend como Windows Service no servidor do cliente.
.DESCRIPTION
    - Copia os arquivos publicados para C:\SigeDash\Backend\
    - Gera appsettings.Production.json com senhas informadas
    - Registra e inicia o Windows Service "SigeDashBackend"
.PARAMETER PostgresSenha
    Senha do usuário 'sigedash' no PostgreSQL local.
.PARAMETER AdminKey
    Chave de administração para criar/listar clientes no backend.
    Se omitida, será gerada automaticamente.
.PARAMETER PublishDir
    Pasta com os arquivos do dotnet publish. Padrão: pasta onde este script está.
.PARAMETER InstallDir
    Pasta de instalação no servidor. Padrão: C:\SigeDash\Backend
.EXAMPLE
    .\instalar-backend.ps1 -PostgresSenha "minhasenha123" -AdminKey "chaveforte"
#>
param(
    [Parameter(Mandatory)]
    [string]$PostgresSenha,

    [string]$AdminKey   = "",
    [string]$PublishDir = $PSScriptRoot,
    [string]$InstallDir = "C:\SigeDash\Backend"
)

$ErrorActionPreference = "Stop"
$SVC_NAME = "SigeDashBackend"
$SVC_EXE  = Join-Path $InstallDir "SigeDash.Api.exe"
$LOG_FILE = Join-Path $InstallDir "install.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content $LOG_FILE $line -Encoding UTF8 } catch {}
}

# ── Verifica privilégio de admin ──────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador."
    exit 1
}

Log "=== SigeDash Backend — Instalação ==="
Log "PublishDir : $PublishDir"
Log "InstallDir : $InstallDir"

# ── Para e remove serviço existente ──────────────────────────────────────────
$svc = Get-Service $SVC_NAME -ErrorAction SilentlyContinue
if ($svc) {
    Log "Serviço $SVC_NAME encontrado — parando..."
    Stop-Service $SVC_NAME -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    sc.exe delete $SVC_NAME | Out-Null
    Log "Serviço removido."
}

# ── Copia arquivos do publish ─────────────────────────────────────────────────
Log "Copiando arquivos para $InstallDir ..."
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item "$PublishDir\*" $InstallDir -Recurse -Force
Log "Arquivos copiados."

# ── Gera chaves se não fornecidas ─────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    $AdminKey = [Convert]::ToBase64String((1..32 | ForEach-Object { [byte](Get-Random -Max 256) }))
    Log "AdminKey gerada automaticamente."
}

# JWT key: 48 chars aleatórios base64
$jwtBytes = 1..36 | ForEach-Object { [byte](Get-Random -Max 256) }
$JwtKey   = [Convert]::ToBase64String($jwtBytes)

# ── Grava appsettings.Production.json ────────────────────────────────────────
$config = @{
    Urls = "http://localhost:5000"
    ConnectionStrings = @{
        Postgres = "Host=localhost;Port=5432;Database=sigedash;Username=sigedash;Password=$PostgresSenha"
    }
    Jwt = @{
        Issuer    = "sigedash"
        Audience  = "sigedash-pwa"
        SecretKey = $JwtKey
    }
    AdminKey       = $AdminKey
    AllowedOrigins = @()
    Logging = @{
        LogLevel = @{
            Default                   = "Information"
            "Microsoft.AspNetCore"    = "Warning"
        }
    }
}

$configPath = Join-Path $InstallDir "appsettings.Production.json"
$config | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
Log "appsettings.Production.json gerado."

# ── Registra o Windows Service ────────────────────────────────────────────────
Log "Registrando serviço $SVC_NAME ..."
$binPath = "`"$SVC_EXE`""
sc.exe create $SVC_NAME binPath= $binPath start= auto obj= LocalSystem | Out-Null
sc.exe description $SVC_NAME "SigeDash Backend API + PWA (SistemasBr)" | Out-Null

# Configura variável de ambiente ASPNETCORE_ENVIRONMENT=Production para o serviço
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$SVC_NAME"
New-ItemProperty -Path $regPath -Name "Environment" -PropertyType MultiString `
    -Value @("ASPNETCORE_ENVIRONMENT=Production") -Force | Out-Null

Log "Serviço registrado."

# ── Inicia o serviço ──────────────────────────────────────────────────────────
Log "Iniciando $SVC_NAME ..."
Start-Service $SVC_NAME
Start-Sleep -Seconds 4

$svc = Get-Service $SVC_NAME
if ($svc.Status -eq "Running") {
    Log "Serviço iniciado com sucesso."
} else {
    Log "AVISO: serviço não está em Running (status: $($svc.Status)). Verifique o Event Viewer."
}

# ── Testa o endpoint de saúde ─────────────────────────────────────────────────
Start-Sleep -Seconds 3
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:5000/auth/empresas" -UseBasicParsing -TimeoutSec 10
    Log "Backend respondendo na porta 5000. Status: $($resp.StatusCode)"
} catch {
    Log "AVISO: backend ainda não respondeu na porta 5000. Aguarde alguns segundos e tente novamente."
}

# ── Agendador de atualizações automáticas ─────────────────────────────────────
$TASK_NAME    = "SigeDash-Atualizar"
$atualizarSrc = Join-Path $PublishDir "atualizar.ps1"
$atualizarDst = Join-Path $InstallDir "atualizar.ps1"

if (Test-Path $atualizarSrc) {
    Copy-Item $atualizarSrc $atualizarDst -Force

    # Remove tarefa anterior se existir
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue

    $action  = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$atualizarDst`""

    # Toda segunda-feira às 03:00
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "03:00"

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable

    Register-ScheduledTask `
        -TaskName    $TASK_NAME `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -RunLevel    Highest `
        -User        "SYSTEM" `
        -Description "Verifica e aplica atualizacoes automaticas do SigeDash" | Out-Null

    Log "Tarefa agendada: $TASK_NAME (toda segunda as 03:00)"
} else {
    Log "AVISO: atualizar.ps1 nao encontrado — agendamento ignorado."
}

# ── Resumo ────────────────────────────────────────────────────────────────────
Log ""
Log "=== Instalacao concluida! ==="
Log "Servico  : $SVC_NAME"
Log "Diretorio: $InstallDir"
Log "AdminKey : $AdminKey"
Log "URL local: http://localhost:5000"
Log ""
Log "IMPORTANTE: guarde a AdminKey acima — ela e necessaria para criar usuarios."
Log "Proximo passo: executar configurar-cliente.ps1 com esta AdminKey."
