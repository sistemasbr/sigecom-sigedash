param(
    [string]$BackendUrl,
    [string]$AdminKey,
    [string]$ClienteNome,
    [string]$FdbPath,
    [string]$Sysdba      = "masterkey",
    [string]$UserLogin,
    [string]$UserSenha,
    [string]$Departamento = "Administradores",
    [string]$ConfigDir    = "$PSScriptRoot\Config"
)

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg"
    Add-Content "$ConfigDir\setup.log" "[$ts] $msg" -ErrorAction SilentlyContinue
}

Log "=== SigeDash — Configuração do Cliente ==="
Log "Backend  : $BackendUrl"
Log "Cliente  : $ClienteNome"
Log "Banco FDB: $FdbPath"

# ── 1. Valida banco FDB ───────────────────────────────────────────────────────
if (-not (Test-Path $FdbPath)) {
    Log "ERRO: Arquivo FDB não encontrado: $FdbPath"
    exit 1
}

# ── 2. Registra o cliente no backend ─────────────────────────────────────────
try {
    $bodyCliente = @{
        nome           = $ClienteNome
        codigoEmpresa  = 1
        nomeLoja       = "Matriz"
    } | ConvertTo-Json

    $respCliente = Invoke-RestMethod `
        -Uri     "$BackendUrl/admin/clientes" `
        -Method  POST `
        -Headers @{ "X-Admin-Key" = $AdminKey; "Content-Type" = "application/json" } `
        -Body    $bodyCliente

    $chaveApi = $respCliente.chaveApi
    Log "Cliente registrado. ChaveApi: $chaveApi"
}
catch {
    # Se cliente já existe, tenta buscar a chave existente
    if ($_.Exception.Response.StatusCode -eq 409) {
        Log "Cliente já existe no backend — usando cadastro existente."
        try {
            $todos = Invoke-RestMethod `
                -Uri     "$BackendUrl/admin/clientes" `
                -Method  GET `
                -Headers @{ "X-Admin-Key" = $AdminKey }
            $chaveApi = ($todos | Where-Object { $_.nome -eq $ClienteNome }).chaveApi
            Log "ChaveApi recuperada: $chaveApi"
        }
        catch {
            Log "ERRO ao recuperar cliente existente: $_"
            exit 2
        }
    }
    else {
        Log "ERRO ao registrar cliente: $_"
        exit 2
    }
}

# ── 3. Cria usuário do app ────────────────────────────────────────────────────
try {
    $bodyUser = @{
        clienteNome  = $ClienteNome
        login        = $UserLogin.ToUpper()
        senha        = $UserSenha
        departamento = $Departamento
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Uri     "$BackendUrl/admin/usuarios" `
        -Method  POST `
        -Headers @{ "X-Admin-Key" = $AdminKey; "Content-Type" = "application/json" } `
        -Body    $bodyUser | Out-Null

    Log "Usuário '$($UserLogin.ToUpper())' criado."
}
catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Log "Usuário já existe — mantido sem alteração."
    }
    else {
        Log "AVISO ao criar usuário: $_ (continuando...)"
    }
}

# ── 4. Grava agente.config.json ───────────────────────────────────────────────
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

$fdbEscaped = $FdbPath -replace '\\', '\\'
$connStr    = "User=SYSDBA;Password=$Sysdba;Database=$fdbEscaped;" +
              "DataSource=localhost;Port=3050;Dialect=3;Charset=ISO8859_1;" +
              "Pooling=true;ConnectionLifetime=60"

$config = [ordered]@{
    FirebirdConnectionString = $connStr
    CodigoEmpresa            = 1
    BackendUrl               = $BackendUrl
    ChaveCliente             = $chaveApi
    PastaSql                 = "Indicadores/sql"
}

$config | ConvertTo-Json -Depth 3 | Set-Content "$ConfigDir\agente.config.json" -Encoding UTF8
Log "agente.config.json gravado em $ConfigDir"

# ── 5. Reinicia o serviço (se já instalado) ───────────────────────────────────
$svc = Get-Service "SigeDashAgente" -ErrorAction SilentlyContinue
if ($svc) {
    Restart-Service "SigeDashAgente" -Force -ErrorAction SilentlyContinue
    Log "Serviço SigeDashAgente reiniciado."
}

Log "=== Configuração concluída com sucesso! ==="
Log "Acesso: $BackendUrl"
Log "Empresa: $ClienteNome  |  Login: $($UserLogin.ToUpper())"
