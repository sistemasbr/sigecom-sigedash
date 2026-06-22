<#
.SYNOPSIS
    Verifica e aplica atualizacoes automaticas do SigeDash Backend.
.DESCRIPTION
    - Consulta GitHub Releases para verificar se ha versao mais nova
    - Compara com a versao instalada (version.txt)
    - Baixa, para o servico, atualiza e reinicia automaticamente
.PARAMETER InstallDir
    Pasta de instalacao do backend. Padrao: C:\SigeDash\Backend
.PARAMETER Repo
    Repositorio GitHub no formato "dono/repo".
.PARAMETER Forcar
    Aplica a atualizacao mesmo se a versao for a mesma.
.EXAMPLE
    .\atualizar.ps1
    .\atualizar.ps1 -Forcar
#>
param(
    [string]$InstallDir = "C:\SigeDash\Backend",
    [string]$Repo       = "sistemasbr/sigecom-sigedash",
    [switch]$Forcar
)

$ErrorActionPreference = "Stop"
$SVC_NAME   = "SigeDashBackend"
$VERSION_TXT = Join-Path $InstallDir "version.txt"
$LOG_FILE    = Join-Path $InstallDir "atualizar.log"
$TEMP_DIR    = Join-Path $env:TEMP "sigedash-update"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content $LOG_FILE $line -Encoding UTF8 } catch {}
}

function VeraoParaNumero($v) {
    # Converte "1.2.3" em [System.Version] para comparacao
    try { return [System.Version]$v } catch { return [System.Version]"0.0.0" }
}

Log "=== SigeDash - Verificacao de Atualizacao ==="

# Le versao instalada
$versaoAtual = "0.0.0"
if (Test-Path $VERSION_TXT) {
    $versaoAtual = (Get-Content $VERSION_TXT -Raw).Trim()
    Log "Versao instalada : $versaoAtual"
} else {
    Log "version.txt nao encontrado — assumindo 0.0.0"
}

# Consulta ultima release no GitHub
Log "Consultando GitHub Releases..."
$apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
try {
    $headers = @{ "User-Agent" = "SigeDash-Updater/1.0" }
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 30
} catch {
    Log "AVISO: Nao foi possivel contatar o GitHub: $_"
    Log "Verifique a conexao com a internet. Nenhuma atualizacao aplicada."
    exit 0
}

$tagLatest = $release.tag_name.TrimStart("v")
Log "Versao disponivel: $tagLatest"

# Compara versoes
$verAtual  = VeraoParaNumero $versaoAtual
$verLatest = VeraoParaNumero $tagLatest

if (-not $Forcar -and $verLatest -le $verAtual) {
    Log "Sistema ja esta na versao mais recente. Nenhuma acao necessaria."
    exit 0
}

Log "Nova versao disponivel: $tagLatest (atual: $versaoAtual)"

# Localiza o asset ZIP na release
$asset = $release.assets | Where-Object { $_.name -like "SigeDash-Deploy-v*.zip" } | Select-Object -First 1
if (-not $asset) {
    Log "ERRO: Nao encontrei arquivo ZIP na release $tagLatest."
    exit 1
}

$downloadUrl = $asset.browser_download_url
$zipName     = $asset.name
$zipPath     = Join-Path $TEMP_DIR $zipName
$extractPath = Join-Path $TEMP_DIR "extracted"

Log "Baixando: $zipName ..."
New-Item -ItemType Directory -Path $TEMP_DIR    -Force | Out-Null
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

try {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($downloadUrl, $zipPath)
    Log "Download concluido."
} catch {
    Log "ERRO ao baixar: $_"
    exit 1
}

# Para o servico
Log "Parando servico $SVC_NAME ..."
$svc = Get-Service $SVC_NAME -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Stop-Service $SVC_NAME -Force
    Start-Sleep -Seconds 3
}

# Extrai e copia — preserva appsettings.Production.json
Log "Extraindo pacote..."
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Copia tudo exceto appsettings.Production.json (que contem senhas do cliente)
$arquivos = Get-ChildItem $extractPath -Recurse -File |
    Where-Object { $_.Name -ne "appsettings.Production.json" }

$qtd = 0
foreach ($f in $arquivos) {
    $relativo = $f.FullName.Substring($extractPath.Length + 1)
    $destino  = Join-Path $InstallDir $relativo
    $pasta    = Split-Path $destino
    New-Item -ItemType Directory -Path $pasta -Force | Out-Null
    Copy-Item $f.FullName $destino -Force
    $qtd++
}
Log "$qtd arquivos atualizados (appsettings.Production.json preservado)."

# Reinicia o servico
Log "Iniciando servico $SVC_NAME ..."
Start-Service $SVC_NAME
Start-Sleep -Seconds 4

$svc = Get-Service $SVC_NAME
if ($svc.Status -eq "Running") {
    Log "Servico reiniciado com sucesso."
} else {
    Log "AVISO: servico nao voltou a Running (status: $($svc.Status)). Verifique o Event Viewer."
}

# Limpa temporarios
try {
    Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

Log ""
Log "=== Atualizacao concluida: $versaoAtual -> $tagLatest ==="
