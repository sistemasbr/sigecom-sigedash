<#
.SYNOPSIS
    Instala o PostgreSQL 16 e prepara o banco de dados para o SigeDash.
.DESCRIPTION
    - Verifica se o PostgreSQL ja esta instalado
    - Baixa e instala o PostgreSQL 16 via EDB (modo silencioso)
    - Cria o banco 'sigedash' e o usuario 'sigedash'
    - Configura o servico para iniciar automaticamente
.PARAMETER SigeDashSenha
    Senha do usuario 'sigedash' no banco (usada pelo backend).
.PARAMETER SuperSenha
    Senha do superusuario 'postgres'. Gerada automaticamente se omitida.
.PARAMETER InstallerExe
    Caminho para o installer EDB ja baixado. Se omitido, faz o download.
.EXAMPLE
    .\instalar-postgres.ps1 -SigeDashSenha "senhasegura123"
#>
param(
    [Parameter(Mandatory)]
    [string]$SigeDashSenha,

    [string]$SuperSenha   = "",
    [string]$InstallerExe = ""
)

$ErrorActionPreference = "Stop"

$PG_VERSION    = "16"
$PG_INSTALLDIR = "C:\Program Files\PostgreSQL\$PG_VERSION"
$PG_BIN        = "$PG_INSTALLDIR\bin"
$PG_SVC        = "postgresql-x64-$PG_VERSION"
$LOG_FILE      = "$env:TEMP\sigedash-postgres-install.log"

function Log($msg) {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content $LOG_FILE $line -Encoding UTF8 } catch {}
}

function Psql($sql, $db = "postgres") {
    $env:PGPASSWORD = $SuperSenha
    $out = & "$PG_BIN\psql.exe" -U postgres -d $db -c $sql 2>&1
    $env:PGPASSWORD = $null
    return $out
}

# Verifica privilegio de admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador."
    exit 1
}

Log "=== SigeDash - Instalacao do PostgreSQL $PG_VERSION ==="

# Gera SuperSenha se nao informada
if ([string]::IsNullOrWhiteSpace($SuperSenha)) {
    $bytes      = 1..18 | ForEach-Object { [byte](Get-Random -Max 256) }
    $SuperSenha = [Convert]::ToBase64String($bytes)
    Log "SuperSenha do postgres gerada automaticamente."
}

# Verifica se ja esta instalado
$psqlExe     = "$PG_BIN\psql.exe"
$jaInstalado = Test-Path $psqlExe

if ($jaInstalado) {
    Log "PostgreSQL $PG_VERSION ja instalado em $PG_BIN - pulando instalacao."
} else {
    # Baixa o installer se necessario
    if ([string]::IsNullOrWhiteSpace($InstallerExe) -or -not (Test-Path $InstallerExe)) {
        $downloadUrl  = "https://get.enterprisedb.com/postgresql/postgresql-16.9-1-windows-x64.exe"
        $InstallerExe = "$env:TEMP\postgresql-16-windows-x64.exe"

        Log "Baixando PostgreSQL $PG_VERSION..."
        Log "(Isso pode levar alguns minutos)"

        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($downloadUrl, $InstallerExe)
            Log "Download concluido: $InstallerExe"
        } catch {
            Log "ERRO ao baixar: $_"
            Log "Baixe manualmente em: https://www.enterprisedb.com/downloads/postgres-postgresql-downloads"
            Log "Escolha: PostgreSQL $PG_VERSION -> Windows x86-64"
            Log "Depois execute: .\instalar-postgres.ps1 -SigeDashSenha '...' -InstallerExe 'C:\caminho\installer.exe'"
            exit 1
        }
    } else {
        Log "Usando installer: $InstallerExe"
    }

    # Executa instalacao silenciosa
    Log "Instalando PostgreSQL $PG_VERSION (modo silencioso)..."
    $installerArgs = @(
        "--mode", "unattended",
        "--superpassword", $SuperSenha,
        "--servicename", $PG_SVC,
        "--servicepassword", $SuperSenha,
        "--serverport", "5432",
        "--datadir", "$PG_INSTALLDIR\data",
        "--install_runtimes", "0"
    )

    $proc = Start-Process -FilePath $InstallerExe -ArgumentList $installerArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Log "ERRO: instalador retornou codigo $($proc.ExitCode)."
        Log "Verifique os logs em %TEMP%\postgresql_installer_*.log"
        exit 1
    }
    Log "PostgreSQL instalado com sucesso."
}

# Garante que o servico esta rodando
$svc = Get-Service $PG_SVC -ErrorAction SilentlyContinue
if (-not $svc) {
    Log "ERRO: servico $PG_SVC nao encontrado apos instalacao."
    exit 1
}
if ($svc.Status -ne "Running") {
    Log "Iniciando servico $PG_SVC ..."
    Start-Service $PG_SVC
    Start-Sleep -Seconds 3
}
Log "Servico $PG_SVC rodando."

# Configura startup automatico
Set-Service $PG_SVC -StartupType Automatic | Out-Null

# Cria usuario e banco sigedash
Log "Criando usuario 'sigedash' no PostgreSQL..."

# Cria usuario (ignora erro se ja existir), depois atualiza a senha
Psql "CREATE USER sigedash WITH PASSWORD '$SigeDashSenha'" | Out-Null
$out = Psql "ALTER USER sigedash WITH PASSWORD '$SigeDashSenha'"
Log "Usuario: $out"

# Cria banco se nao existir
$dbExiste = Psql "SELECT 1 FROM pg_database WHERE datname='sigedash'"
if ($dbExiste -notmatch "1 row") {
    $out = Psql "CREATE DATABASE sigedash OWNER sigedash ENCODING 'UTF8'"
    Log "Banco criado: $out"
} else {
    Log "Banco 'sigedash' ja existe."
}

# Garante permissoes
$out = Psql "GRANT ALL PRIVILEGES ON DATABASE sigedash TO sigedash"
Log "Permissoes: $out"

# Testa conexao com o usuario sigedash
Log "Testando conexao com usuario 'sigedash'..."
$env:PGPASSWORD = $SigeDashSenha
$teste          = & "$PG_BIN\psql.exe" -U sigedash -d sigedash -c "SELECT version()" 2>&1
$env:PGPASSWORD = $null

if ($teste -match "PostgreSQL") {
    Log "Conexao OK - PostgreSQL respondendo para o usuario 'sigedash'."
} else {
    Log "AVISO: teste de conexao retornou: $teste"
    Log "Verifique manualmente: psql -U sigedash -d sigedash -h localhost"
}

# Resumo
Log ""
Log "=== PostgreSQL pronto! ==="
Log "Banco   : sigedash"
Log "Usuario : sigedash"
Log "Senha   : $SigeDashSenha"
Log "Porta   : 5432"
Log "Servico : $PG_SVC (automatico)"
Log ""
Log "String de conexao para o backend:"
Log "Host=localhost;Port=5432;Database=sigedash;Username=sigedash;Password=$SigeDashSenha"
Log ""
Log "Proximo passo: execute instalar-backend.ps1 -PostgresSenha '$SigeDashSenha'"