; ── SigeDash Agente — Script de Instalação (Inno Setup 6.x) ─────────────────────
; Gera: SigeDashAgente-Setup.exe
; Requer: binários compilados em deploy\agente\bin\
; O instalador registra o cliente no backend automaticamente — sem etapas manuais.
; ────────────────────────────────────────────────────────────────────────────────

#define AppName      "SigeDash Agente"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppPublisher "SistemasBr"
#define AppExe       "SigeDash.Agente.exe"
#define ServiceName  "SigeDashAgente"
#define ServiceLabel "SigeDash Agente"
#define InstallDir   "{autopf}\SistemasBr\SigeDash"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppId={{A3F7C2D1-8E4B-4F0A-9C6D-2B5E8F1A3C7D}
DefaultDirName={#InstallDir}
DefaultGroupName=SistemasBr\SigeDash
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=SigeDashAgente-Setup-v{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
CloseApplications=yes
RestartIfNeededByRun=no
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
; Binários do agente
Source: "bin\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
; Script de configuração automática
Source: "configurar-cliente.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"

; ────────────────────────────────────────────────────────────────────────────────
[Code]

var
  PageBackend : TInputQueryWizardPage;   // URL + chave admin
  PageCliente : TInputQueryWizardPage;   // dados do cliente e usuário

// ── Página 1: conexão com o backend ──────────────────────────────────────────
// ── Página 2: dados do cliente ────────────────────────────────────────────────
procedure InitializeWizard;
begin
  // Página 1 — backend
  PageBackend := CreateInputQueryPage(wpSelectDir,
    'Conexão com o Servidor SigeDash',
    'Informe os dados de acesso ao servidor SigeDash (fornecidos pela SistemasBr)',
    '');

  PageBackend.Add('URL do servidor SigeDash:', False);
  PageBackend.Values[0] := 'https://dash.sigedash.com.br';

  PageBackend.Add('Chave de administração (fornecida pela SistemasBr):', True);
  PageBackend.Values[1] := '';

  // Página 2 — cliente
  PageCliente := CreateInputQueryPage(PageBackend.ID,
    'Dados do Cliente',
    'Informe os dados da empresa. Os usuários serão sincronizados automaticamente do Sigecom.',
    '');

  PageCliente.Add('Nome da empresa (ex: Autopeças Silva):', False);
  PageCliente.Values[0] := '';

  PageCliente.Add('Caminho do banco Firebird (.FDB):', False);
  PageCliente.Values[1] := 'C:\Sigecom\dados\EMPRESA.FDB';
end;

// ── Validação dos campos antes de avançar ────────────────────────────────────
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if CurPageID = PageBackend.ID then
  begin
    if Trim(PageBackend.Values[0]) = '' then
    begin
      MsgBox('Informe a URL do servidor SigeDash.', mbError, MB_OK);
      Result := False; Exit;
    end;
    if Trim(PageBackend.Values[1]) = '' then
    begin
      MsgBox('Informe a Chave de Administração.', mbError, MB_OK);
      Result := False; Exit;
    end;
  end;

  if CurPageID = PageCliente.ID then
  begin
    if Trim(PageCliente.Values[0]) = '' then
    begin
      MsgBox('Informe o nome da empresa.', mbError, MB_OK);
      Result := False; Exit;
    end;
    if Trim(PageCliente.Values[1]) = '' then
    begin
      MsgBox('Informe o caminho do banco Firebird.', mbError, MB_OK);
      Result := False; Exit;
    end;
  end;
end;

// ── Para o serviço se já existir ─────────────────────────────────────────────
procedure PararServico;
var
  rc: Integer;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop {#ServiceName}',
    '', SW_HIDE, ewWaitUntilTerminated, rc);
  Sleep(1500);
end;

procedure RemoverServico;
var
  rc: Integer;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'delete {#ServiceName}',
    '', SW_HIDE, ewWaitUntilTerminated, rc);
  Sleep(500);
end;

// ── Registra e inicia o Windows Service ──────────────────────────────────────
procedure InstalarServico;
var
  exePath, params: String;
  resultCode: Integer;
begin
  exePath := ExpandConstant('{app}\{#AppExe}');

  params := 'create {#ServiceName} binPath= "' + exePath + '"';
  params := params + ' start= auto DisplayName= "{#ServiceLabel}"';
  Exec(ExpandConstant('{sys}\sc.exe'), params, '', SW_HIDE,
    ewWaitUntilTerminated, resultCode);

  Exec(ExpandConstant('{sys}\sc.exe'),
    'description {#ServiceName} "Sincroniza dados do Firebird com o painel SigeDash"',
    '', SW_HIDE, ewWaitUntilTerminated, resultCode);
end;

// ── Chama o script PowerShell que registra no backend e grava o config ───────
procedure ConfigurarViaScript;
var
  psArgs, appPath: String;
  backendUrl, adminKey, clienteNome, fdbPath: String;
  resultCode: Integer;
begin
  appPath     := ExpandConstant('{app}');
  backendUrl  := PageBackend.Values[0];
  adminKey    := PageBackend.Values[1];
  clienteNome := PageCliente.Values[0];
  fdbPath     := PageCliente.Values[1];

  psArgs := '-NoProfile -ExecutionPolicy Bypass -File "' + appPath + '\configurar-cliente.ps1"';
  psArgs := psArgs + ' -BackendUrl "' + backendUrl + '"';
  psArgs := psArgs + ' -AdminKey "' + adminKey + '"';
  psArgs := psArgs + ' -ClienteNome "' + clienteNome + '"';
  psArgs := psArgs + ' -FdbPath "' + fdbPath + '"';
  psArgs := psArgs + ' -ConfigDir "' + appPath + '\Config"';

  Exec('powershell.exe', psArgs, '', SW_HIDE, ewWaitUntilTerminated, resultCode);

  if resultCode <> 0 then
    MsgBox(
      'Aviso: não foi possível registrar o cliente no servidor automaticamente.' + #13#10 +
      'O agente foi instalado, mas pode ser necessário configurar manualmente.' + #13#10 +
      'Verifique o arquivo: ' + appPath + '\Config\setup.log',
      mbInformation, MB_OK);
end;

// ── Hook pós-instalação ───────────────────────────────────────────────────────
procedure CurStepChanged(CurStep: TSetupStep);
var
  resultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    PararServico;
    RemoverServico;
    ConfigurarViaScript;  // registra no backend + grava config
    InstalarServico;      // instala e inicia o serviço

    // Inicia o serviço (config já está pronta)
    Exec(ExpandConstant('{sys}\sc.exe'), 'start {#ServiceName}',
      '', SW_HIDE, ewWaitUntilTerminated, resultCode);
  end;
end;

// ── Desinstalação ─────────────────────────────────────────────────────────────
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    PararServico;
    RemoverServico;
  end;
end;
