/// <summary>
/// DX.Comply.IDE.Settings
/// Stores and loads global IDE settings for the DX.Comply wizard.
/// </summary>
///
/// <remarks>
/// The settings are persisted independently from project-local .dxcomply.json files so
/// the IDE plugin can provide global defaults such as optional Deep-Evidence auto-builds.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.Settings;

interface

uses
  System.SysUtils;

type
  /// <summary>
  /// Controls whether the IDE plugin triggers a Deep-Evidence build.
  /// </summary>
  TIDEAutoBuildMode = (abmDisabled, abmWhenMapMissing, abmAlways);

  /// <summary>
  /// Global IDE settings for DX.Comply.
  /// </summary>
  TDXComplyIDESettings = record
    AutoBuildMode: TIDEAutoBuildMode;
    PromptBeforeBuild: Boolean;
    SaveAllModifiedFilesBeforeBuild: Boolean;
    UseActiveBuildConfiguration: Boolean;
    ContinueWithoutDeepEvidenceOnBuildFailure: Boolean;
    WarnWhenCompositionEvidenceIsEmpty: Boolean;
    BuildScriptPath: string;
    DelphiVersionOverride: Integer;
    class function Default: TDXComplyIDESettings; static;
  end;

  /// <summary>
  /// Persists DX.Comply IDE settings in a user-scoped INI file.
  /// </summary>
  TDXComplyIDESettingsStore = class sealed
  private
    class function GetAppDataDirectory: string; static;
    class function GetDefaultFilePath: string; static;
    class function AutoBuildModeToString(const AValue: TIDEAutoBuildMode): string; static;
    class function StringToAutoBuildMode(const AValue: string): TIDEAutoBuildMode; static;
  public
    class function Load: TDXComplyIDESettings; static;
    class function LoadFromFile(const AFilePath: string): TDXComplyIDESettings; static;
    class procedure Save(const ASettings: TDXComplyIDESettings); static;
    class procedure SaveToFile(const AFilePath: string;
      const ASettings: TDXComplyIDESettings); static;
  end;

implementation

uses
  System.IniFiles,
  System.IOUtils;

const
  cSettingsSection = 'DX.Comply';

{ TDXComplyIDESettings }

class function TDXComplyIDESettings.Default: TDXComplyIDESettings;
begin
  Result.AutoBuildMode := abmDisabled;
  Result.PromptBeforeBuild := True;
  Result.SaveAllModifiedFilesBeforeBuild := True;
  Result.UseActiveBuildConfiguration := True;
  Result.ContinueWithoutDeepEvidenceOnBuildFailure := True;
  Result.WarnWhenCompositionEvidenceIsEmpty := True;
  Result.BuildScriptPath := '';
  Result.DelphiVersionOverride := 0;
end;

{ TDXComplyIDESettingsStore }

class function TDXComplyIDESettingsStore.AutoBuildModeToString(
  const AValue: TIDEAutoBuildMode): string;
begin
  case AValue of
    abmWhenMapMissing: Result := 'missing';
    abmAlways: Result := 'always';
  else
    Result := 'disabled';
  end;
end;

class function TDXComplyIDESettingsStore.GetAppDataDirectory: string;
begin
  Result := GetEnvironmentVariable('APPDATA');
  if Result = '' then
    Result := TPath.Combine(TPath.GetHomePath, 'AppData\Roaming');

  Result := TPath.Combine(Result, 'DX.Comply');
end;

class function TDXComplyIDESettingsStore.GetDefaultFilePath: string;
begin
  Result := TPath.Combine(GetAppDataDirectory, 'DX.Comply.IDE.ini');
end;

class function TDXComplyIDESettingsStore.Load: TDXComplyIDESettings;
begin
  Result := LoadFromFile(GetDefaultFilePath);
end;

class function TDXComplyIDESettingsStore.LoadFromFile(
  const AFilePath: string): TDXComplyIDESettings;
var
  LIniFile: TMemIniFile;
begin
  Result := TDXComplyIDESettings.Default;
  if not TFile.Exists(AFilePath) then
    Exit;

  LIniFile := TMemIniFile.Create(AFilePath, TEncoding.UTF8);
  try
    Result.AutoBuildMode := StringToAutoBuildMode(LIniFile.ReadString(cSettingsSection, 'AutoBuildMode', 'disabled'));
    Result.PromptBeforeBuild := LIniFile.ReadBool(cSettingsSection, 'PromptBeforeBuild', Result.PromptBeforeBuild);
    Result.SaveAllModifiedFilesBeforeBuild := LIniFile.ReadBool(cSettingsSection, 'SaveAllModifiedFilesBeforeBuild', Result.SaveAllModifiedFilesBeforeBuild);
    Result.UseActiveBuildConfiguration := LIniFile.ReadBool(cSettingsSection, 'UseActiveBuildConfiguration', Result.UseActiveBuildConfiguration);
    Result.ContinueWithoutDeepEvidenceOnBuildFailure := LIniFile.ReadBool(cSettingsSection, 'ContinueWithoutDeepEvidenceOnBuildFailure', Result.ContinueWithoutDeepEvidenceOnBuildFailure);
    Result.WarnWhenCompositionEvidenceIsEmpty := LIniFile.ReadBool(cSettingsSection, 'WarnWhenCompositionEvidenceIsEmpty', Result.WarnWhenCompositionEvidenceIsEmpty);
    Result.BuildScriptPath := Trim(LIniFile.ReadString(cSettingsSection, 'BuildScriptPath', Result.BuildScriptPath));
    Result.DelphiVersionOverride := LIniFile.ReadInteger(cSettingsSection, 'DelphiVersionOverride', Result.DelphiVersionOverride);
  finally
    LIniFile.Free;
  end;
end;

class procedure TDXComplyIDESettingsStore.Save(const ASettings: TDXComplyIDESettings);
begin
  SaveToFile(GetDefaultFilePath, ASettings);
end;

class procedure TDXComplyIDESettingsStore.SaveToFile(const AFilePath: string;
  const ASettings: TDXComplyIDESettings);
var
  LIniFile: TMemIniFile;
begin
  ForceDirectories(TPath.GetDirectoryName(AFilePath));
  LIniFile := TMemIniFile.Create(AFilePath, TEncoding.UTF8);
  try
    LIniFile.WriteString(cSettingsSection, 'AutoBuildMode', AutoBuildModeToString(ASettings.AutoBuildMode));
    LIniFile.WriteBool(cSettingsSection, 'PromptBeforeBuild', ASettings.PromptBeforeBuild);
    LIniFile.WriteBool(cSettingsSection, 'SaveAllModifiedFilesBeforeBuild', ASettings.SaveAllModifiedFilesBeforeBuild);
    LIniFile.WriteBool(cSettingsSection, 'UseActiveBuildConfiguration', ASettings.UseActiveBuildConfiguration);
    LIniFile.WriteBool(cSettingsSection, 'ContinueWithoutDeepEvidenceOnBuildFailure', ASettings.ContinueWithoutDeepEvidenceOnBuildFailure);
    LIniFile.WriteBool(cSettingsSection, 'WarnWhenCompositionEvidenceIsEmpty', ASettings.WarnWhenCompositionEvidenceIsEmpty);
    LIniFile.WriteString(cSettingsSection, 'BuildScriptPath', Trim(ASettings.BuildScriptPath));
    LIniFile.WriteInteger(cSettingsSection, 'DelphiVersionOverride', ASettings.DelphiVersionOverride);
    LIniFile.UpdateFile;
  finally
    LIniFile.Free;
  end;
end;

class function TDXComplyIDESettingsStore.StringToAutoBuildMode(
  const AValue: string): TIDEAutoBuildMode;
begin
  if SameText(AValue, 'always') then
    Exit(abmAlways);
  if SameText(AValue, 'missing') then
    Exit(abmWhenMapMissing);

  Result := abmDisabled;
end;

end.