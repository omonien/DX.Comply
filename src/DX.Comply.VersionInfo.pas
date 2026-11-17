/// <summary>
/// DX.Comply.VersionInfo
/// Reads the DX.Comply tool version from the running module version resource.
/// </summary>
///
/// <remarks>
/// GetDxComplyToolVersion uses HInstance, the module that contains this unit.
/// Linked into the IDE design package, that handle is the BPL. It is not
/// ParamStr(0), which inside the IDE is bds.exe. The CLI and the test runner
/// read their own executable the same way. GetDxComplyToolVersion is the
/// helper the CLI --version path can call later.
/// GetFileVersionText prefers the numeric file version (a.b.c.d). It uses
/// the FileVersion string, then the ProductVersion string, only when the
/// file has no fixed file info. The SBOM and the reports share that value.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.VersionInfo;

interface

uses
  Winapi.Windows;

/// <summary>
/// ProductVersion string from AModule. Pass 0 to read the module that
/// contains this unit (HInstance), not the host process executable.
/// Returns an empty string when the module has no version resource.
/// </summary>
function GetModuleProductVersion(AModule: HMODULE): string;

/// <summary>
/// Named string from AModule's version resource, for example CompanyName.
/// Pass 0 for HInstance. Returns an empty string when the value is absent.
/// </summary>
function GetModuleVersionString(AModule: HMODULE; const AName: string): string;

/// <summary>
/// Chooses the version text for a binary. When AHasFixedFileInfo is true,
/// dwFileVersionMS and dwFileVersionLS are formatted as a.b.c.d, including
/// 0.0.0.0. Otherwise AFileVersion is used, then AProductVersion. Blank
/// strings are skipped.
/// </summary>
function SelectFileVersionText(AHasFixedFileInfo: Boolean;
  const AFixedInfo: TVSFixedFileInfo; const AFileVersion, AProductVersion: string): string;

/// <summary>
/// Version of the file at APath from its version resource. The numeric file
/// version (a.b.c.d) is used when fixed file info is present. Otherwise the
/// FileVersion string is used, then the ProductVersion string. Returns an
/// empty string when the file is missing or has no version resource. Used
/// for binaries listed in a build SBOM and in the reports.
/// </summary>
function GetFileVersionText(const APath: string): string;

/// <summary>
/// Tool version of the module that contains this unit.
/// Falls back to 1.0.0 when the version resource is missing.
/// </summary>
function GetDxComplyToolVersion: string;

/// <summary>
/// Version written into an SBOM. A non-empty metadata value wins, so the
/// engine can supply GetDxComplyToolVersion. Otherwise the running module
/// version is used.
/// </summary>
function ResolveDxComplyToolVersion(const AMetadataToolVersion: string): string;

/// <summary>
/// Caption for the About dialog version line.
/// An empty product version stays unavailable. It is not replaced with a constant.
/// </summary>
function FormatDXComplyVersionCaption(const AProductVersion, ACompanyName: string): string;

implementation

uses
  System.SysUtils;

const
  cFallbackToolVersion = '1.0.0';
  cFallbackTranslations: array[0..2] of string = ('040704E4', '040904E4', '040904B0');

type
  TTranslationInfo = packed record
    Language: Word;
    CodePage: Word;
  end;

function EffectiveModule(AModule: HMODULE): HMODULE;
begin
  // A zero handle would make GetModuleFileName return the host executable.
  // Inside the IDE package that is bds.exe, so use this module instead.
  if AModule = 0 then
    Result := HInstance
  else
    Result := AModule;
end;

function ModuleFilePath(AModule: HMODULE): string;
var
  LLength: DWORD;
begin
  SetLength(Result, 4096);
  LLength := GetModuleFileName(EffectiveModule(AModule), PChar(Result), Length(Result));
  if LLength = 0 then
    Exit('');
  SetLength(Result, LLength);
end;

function LoadFileVersionData(const LPath: string): TBytes;
var
  LDummy: DWORD;
  LSize: DWORD;
begin
  SetLength(Result, 0);
  if LPath = '' then
    Exit;

  LSize := GetFileVersionInfoSize(PChar(LPath), LDummy);
  if LSize = 0 then
    Exit;

  SetLength(Result, LSize);
  if not GetFileVersionInfo(PChar(LPath), 0, LSize, @Result[0]) then
    SetLength(Result, 0);
end;

function LoadVersionData(AModule: HMODULE): TBytes;
begin
  Result := LoadFileVersionData(ModuleFilePath(AModule));
end;

function QueryVersionString(const AVersionData: TBytes; const AName: string): string;
var
  I: Integer;
  LQueryPath: string;
  LTextLength: UINT;
  LTextPointer: PChar;
  LTranslation: ^TTranslationInfo;
  LTranslationId: string;
  LTranslationLength: UINT;

  function TryQueryString(const ATranslationId: string): Boolean;
  begin
    LQueryPath := Format('\StringFileInfo\%s\%s', [ATranslationId, AName]);
    Result := VerQueryValue(@AVersionData[0], PChar(LQueryPath), Pointer(LTextPointer),
      LTextLength) and (LTextLength > 0);
    if Result then
      Result := Trim(string(LTextPointer)) <> '';
  end;

begin
  Result := '';
  if Length(AVersionData) = 0 then
    Exit;

  if VerQueryValue(@AVersionData[0], '\VarFileInfo\Translation', Pointer(LTranslation),
    LTranslationLength) and (LTranslationLength >= SizeOf(TTranslationInfo)) then
  begin
    LTranslationId := Format('%.4x%.4x', [LTranslation^.Language, LTranslation^.CodePage]);
    if TryQueryString(LTranslationId) then
      Exit(Trim(string(LTextPointer)));
  end;

  for I := Low(cFallbackTranslations) to High(cFallbackTranslations) do
    if TryQueryString(cFallbackTranslations[I]) then
      Exit(Trim(string(LTextPointer)));
end;

function QueryFixedProductVersion(const AVersionData: TBytes): string;
var
  LVersionInfo: PVSFixedFileInfo;
  LVersionLength: UINT;
begin
  Result := '';
  if (Length(AVersionData) = 0) or
    not VerQueryValue(@AVersionData[0], '\', Pointer(LVersionInfo), LVersionLength) or
    (LVersionLength < SizeOf(VS_FIXEDFILEINFO)) then
    Exit;

  Result := Format('%d.%d.%d.%d', [
    HiWord(LVersionInfo^.dwProductVersionMS),
    LoWord(LVersionInfo^.dwProductVersionMS),
    HiWord(LVersionInfo^.dwProductVersionLS),
    LoWord(LVersionInfo^.dwProductVersionLS)]);
end;

function TryReadFixedFileInfo(const AVersionData: TBytes;
  out AInfo: TVSFixedFileInfo): Boolean;
var
  LVersionInfo: PVSFixedFileInfo;
  LVersionLength: UINT;
begin
  AInfo := Default(TVSFixedFileInfo);
  Result := False;
  if Length(AVersionData) = 0 then
    Exit;
  if not VerQueryValue(@AVersionData[0], '\', Pointer(LVersionInfo), LVersionLength) then
    Exit;
  if LVersionLength < SizeOf(VS_FIXEDFILEINFO) then
    Exit;

  AInfo := LVersionInfo^;
  Result := True;
end;

function FormatFixedFileVersion(AVersionMS, AVersionLS: DWORD): string;
begin
  Result := Format('%d.%d.%d.%d', [
    HiWord(AVersionMS),
    LoWord(AVersionMS),
    HiWord(AVersionLS),
    LoWord(AVersionLS)]);
end;

function SelectFileVersionText(AHasFixedFileInfo: Boolean;
  const AFixedInfo: TVSFixedFileInfo; const AFileVersion, AProductVersion: string): string;
begin
  // Vendors edit the string values freely. The numeric fields are the
  // file version stored in the fixed file info.
  if AHasFixedFileInfo then
    Exit(FormatFixedFileVersion(AFixedInfo.dwFileVersionMS, AFixedInfo.dwFileVersionLS));

  Result := Trim(AFileVersion);
  if Result = '' then
    Result := Trim(AProductVersion);
end;

function GetFileVersionText(const APath: string): string;
var
  LFixedInfo: TVSFixedFileInfo;
  LHasFixedInfo: Boolean;
  LVersionData: TBytes;
begin
  Result := '';
  if (APath = '') or not FileExists(APath) then
    Exit;
  LVersionData := LoadFileVersionData(APath);
  if Length(LVersionData) = 0 then
    Exit;
  LHasFixedInfo := TryReadFixedFileInfo(LVersionData, LFixedInfo);
  Result := SelectFileVersionText(LHasFixedInfo, LFixedInfo,
    QueryVersionString(LVersionData, 'FileVersion'),
    QueryVersionString(LVersionData, 'ProductVersion'));
end;

function GetModuleVersionString(AModule: HMODULE; const AName: string): string;
begin
  Result := QueryVersionString(LoadVersionData(AModule), AName);
end;

function GetModuleProductVersion(AModule: HMODULE): string;
var
  LVersionData: TBytes;
begin
  LVersionData := LoadVersionData(AModule);
  Result := QueryVersionString(LVersionData, 'ProductVersion');
  if Result = '' then
    Result := QueryFixedProductVersion(LVersionData);
end;

function GetDxComplyToolVersion: string;
begin
  Result := GetModuleProductVersion(HInstance);
  if Result = '' then
    Result := cFallbackToolVersion;
end;

function ResolveDxComplyToolVersion(const AMetadataToolVersion: string): string;
begin
  Result := Trim(AMetadataToolVersion);
  if Result = '' then
    Result := GetDxComplyToolVersion;
end;

function FormatDXComplyVersionCaption(const AProductVersion, ACompanyName: string): string;
var
  LCompany: string;
  LVersion: string;
begin
  LVersion := Trim(AProductVersion);
  if LVersion = '' then
    Exit('Version unavailable');

  Result := 'Version ' + LVersion;
  LCompany := Trim(ACompanyName);
  if LCompany <> '' then
    Result := Result + ' · ' + LCompany;
end;

end.
