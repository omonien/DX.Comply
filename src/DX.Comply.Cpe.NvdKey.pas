/// <summary>
/// DX.Comply.Cpe.NvdKey
/// Resolves the optional NVD API key without writing it to a project file.
/// </summary>
///
/// <remarks>
/// The order is the command-line option, then the NVD_API_KEY environment
/// variable, then HKCU\Software\Developer Experts\DX.Comply\NIST value
/// ApiKey. DX.Comply stores its other IDE settings in an INI file under
/// the user profile, not in the registry, so this key has its own registry
/// path. The key is never read from .dxcomply.json. Log lines name the
/// source and do not include the key.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Cpe.NvdKey;

interface

uses
  System.SysUtils;

const
  /// <summary>Environment variable read when no command-line key was passed.</summary>
  cNvdApiKeyEnvironmentVariable = 'NVD_API_KEY';
  /// <summary>
  /// HKCU path of the per-user key. Other DX.Comply settings are not stored
  /// under this key.
  /// </summary>
  cNvdApiKeyRegistryPath = '\Software\Developer Experts\DX.Comply\NIST';
  /// <summary>Registry value name. The data is a string.</summary>
  cNvdApiKeyRegistryValue = 'ApiKey';
  /// <summary>Page where NIST issues an NVD API key.</summary>
  cNvdApiKeyRequestUrl = 'https://nvd.nist.gov/developers/request-an-api-key';

type
  /// <summary>Where the NVD API key that will be sent was found.</summary>
  TNvdApiKeyOrigin = (
    /// <summary>No key. The request goes out without an apiKey header.</summary>
    akoNone,
    /// <summary>The command-line option, or the value typed for this search.</summary>
    akoOption,
    /// <summary>The NVD_API_KEY environment variable.</summary>
    akoEnvironment,
    /// <summary>The per-user registry value.</summary>
    akoRegistry
  );

  /// <summary>Resolved key and the source that supplied it.</summary>
  TNvdApiKeyResolution = record
    /// <summary>The key to send. Empty when Origin is akoNone.</summary>
    Key: string;
    /// <summary>Which source won. Later sources are not consulted.</summary>
    Origin: TNvdApiKeyOrigin;
  end;

  /// <summary>
  /// Environment and registry reads. Tests pass a stand-in so the order
  /// can be checked without touching the process environment or HKCU.
  /// </summary>
  INvdApiKeySources = interface
    ['{8B6E1C4A-5F0D-4C3E-9A71-2D4E6B8C0F15}']
    /// <summary>NVD_API_KEY, or the test stand-in. Empty when unset.</summary>
    function ReadEnvironmentValue: string;
    /// <summary>Registry ApiKey, or the test stand-in. Empty when unset.</summary>
    function ReadRegistryValue: string;
  end;

/// <summary>
/// Option, then environment, then registry. A blank option is skipped.
/// ASources nil uses the process environment and HKCU. The result Key is
/// for the request header only. Do not write it to a log.
/// </summary>
function ResolveNvdApiKey(const AOption: string;
  const ASources: INvdApiKeySources): TNvdApiKeyResolution;

/// <summary>
/// "option", "environment", "registry", or "none". Never the key itself.
/// </summary>
function NvdApiKeyOriginLabel(AOrigin: TNvdApiKeyOrigin): string;

/// <summary>
/// One log line, for example "NVD API key: registry" or "NVD API key: none".
/// The key value is not included.
/// </summary>
function NvdApiKeyLogLine(const AResolution: TNvdApiKeyResolution): string;

/// <summary>
/// Reads ApiKey from HKCU. Empty when the value is missing or the registry
/// cannot be opened. Does not raise.
/// </summary>
function ReadNvdApiKeyFromRegistry: string;

/// <summary>
/// Writes ApiKey for the current user. An empty AKey removes the value.
/// AError does not contain the key. Does not write .dxcomply.json.
/// </summary>
function TryWriteNvdApiKeyToRegistry(const AKey: string; out AError: string): Boolean;

implementation

uses
  System.Win.Registry,
  Winapi.Windows;

type
  TDefaultNvdApiKeySources = class(TInterfacedObject, INvdApiKeySources)
  public
    function ReadEnvironmentValue: string;
    function ReadRegistryValue: string;
  end;

function TDefaultNvdApiKeySources.ReadEnvironmentValue: string;
begin
  Result := GetEnvironmentVariable(cNvdApiKeyEnvironmentVariable);
end;

function TDefaultNvdApiKeySources.ReadRegistryValue: string;
begin
  Result := ReadNvdApiKeyFromRegistry;
end;

function ResolveNvdApiKey(const AOption: string;
  const ASources: INvdApiKeySources): TNvdApiKeyResolution;
var
  LSources: INvdApiKeySources;
  LValue: string;
begin
  Result.Key := '';
  Result.Origin := akoNone;
  LValue := Trim(AOption);
  if LValue <> '' then
  begin
    Result.Key := LValue;
    Result.Origin := akoOption;
    Exit;
  end;

  if ASources <> nil then
    LSources := ASources
  else
    LSources := TDefaultNvdApiKeySources.Create;

  LValue := Trim(LSources.ReadEnvironmentValue);
  if LValue <> '' then
  begin
    Result.Key := LValue;
    Result.Origin := akoEnvironment;
    Exit;
  end;

  LValue := Trim(LSources.ReadRegistryValue);
  if LValue <> '' then
  begin
    Result.Key := LValue;
    Result.Origin := akoRegistry;
  end;
end;

function NvdApiKeyOriginLabel(AOrigin: TNvdApiKeyOrigin): string;
begin
  case AOrigin of
    akoOption: Result := 'option';
    akoEnvironment: Result := 'environment';
    akoRegistry: Result := 'registry';
  else
    Result := 'none';
  end;
end;

function NvdApiKeyLogLine(const AResolution: TNvdApiKeyResolution): string;
begin
  Result := 'NVD API key: ' + NvdApiKeyOriginLabel(AResolution.Origin);
end;

function ReadNvdApiKeyFromRegistry: string;
var
  LRegistry: TRegistry;
begin
  Result := '';
  LRegistry := TRegistry.Create(KEY_READ);
  try
    try
      LRegistry.RootKey := HKEY_CURRENT_USER;
      if not LRegistry.OpenKeyReadOnly(cNvdApiKeyRegistryPath) then
        Exit;
      try
        if LRegistry.ValueExists(cNvdApiKeyRegistryValue) then
          Result := Trim(LRegistry.ReadString(cNvdApiKeyRegistryValue));
      finally
        LRegistry.CloseKey;
      end;
    except
      on Exception do
        Result := '';
    end;
  finally
    LRegistry.Free;
  end;
end;

function TryWriteNvdApiKeyToRegistry(const AKey: string; out AError: string): Boolean;
var
  LRegistry: TRegistry;
  LKey: string;
begin
  AError := '';
  LKey := Trim(AKey);
  LRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      LRegistry.RootKey := HKEY_CURRENT_USER;
      if not LRegistry.OpenKey(cNvdApiKeyRegistryPath, True) then
      begin
        AError := 'The NVD API key could not be saved in the registry.';
        Exit(False);
      end;
      try
        if LKey = '' then
        begin
          if LRegistry.ValueExists(cNvdApiKeyRegistryValue) then
            LRegistry.DeleteValue(cNvdApiKeyRegistryValue);
        end
        else
          LRegistry.WriteString(cNvdApiKeyRegistryValue, LKey);
      finally
        LRegistry.CloseKey;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        // The registry message does not include the value we tried to write.
        AError := 'The NVD API key could not be saved in the registry. ' + E.Message;
        Result := False;
      end;
    end;
  finally
    LRegistry.Free;
  end;
end;

end.
