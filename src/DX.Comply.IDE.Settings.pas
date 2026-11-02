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
  System.SysUtils,
  DX.Comply.Report.Intf;

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
    OpenHtmlReportAfterGenerate: Boolean;
    WarnWhenCompositionEvidenceIsEmpty: Boolean;
    BuildScriptPath: string;
    DelphiVersionOverride: Integer;
    HumanReadableReport: THumanReadableReportConfig;
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
    class function ReportFormatToString(
      const AValue: THumanReadableReportFormat): string; static;
    class function StringToAutoBuildMode(const AValue: string): TIDEAutoBuildMode; static;
    class function StringToReportFormat(
      const AValue: string): THumanReadableReportFormat; static;
  public
    class function Load: TDXComplyIDESettings; static;
    class function LoadFromFile(const AFilePath: string): TDXComplyIDESettings; static;
    class procedure Save(const ASettings: TDXComplyIDESettings); static;
    class procedure SaveToFile(const AFilePath: string;
      const ASettings: TDXComplyIDESettings); static;
  end;

/// <summary>
/// Returns the caption used for the single DX.Comply node in the IDE options tree.
/// </summary>
function DXComplyOptionsPageCaption: string;

/// <summary>
/// Scales a design-time pixel value from 96 PPI to the requested target PPI.
/// </summary>
function DXComplyScaleDesignValue(const AValue, APixelsPerInch: Integer): Integer;

implementation

uses
  Winapi.Windows,
  System.IniFiles,
  System.IOUtils;

const
  cSettingsSection = 'DX.Comply';

{ TDXComplyIDESettings }

class function TDXComplyIDESettings.Default: TDXComplyIDESettings;
begin
  Result.AutoBuildMode := abmAlways;
  Result.PromptBeforeBuild := True;
  Result.SaveAllModifiedFilesBeforeBuild := True;
  Result.UseActiveBuildConfiguration := True;
  Result.ContinueWithoutDeepEvidenceOnBuildFailure := False;
  Result.OpenHtmlReportAfterGenerate := True;
  Result.WarnWhenCompositionEvidenceIsEmpty := True;
  Result.BuildScriptPath := '';
  Result.DelphiVersionOverride := 0;
  Result.HumanReadableReport := THumanReadableReportConfig.Default;
  Result.HumanReadableReport.Enabled := True;
  Result.HumanReadableReport.Format := hrfBoth;
end;

function DXComplyOptionsPageCaption: string;
begin
  // ToolsAPI uses '.' as a hierarchy separator inside the options tree.
  Result := 'DX' + #$2024 + 'Comply';
end;

function DXComplyScaleDesignValue(const AValue, APixelsPerInch: Integer): Integer;
begin
  if APixelsPerInch <= 0 then
    Exit(AValue);

  Result := MulDiv(AValue, APixelsPerInch, USER_DEFAULT_SCREEN_DPI);
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

class function TDXComplyIDESettingsStore.ReportFormatToString(
  const AValue: THumanReadableReportFormat): string;
begin
  case AValue of
    hrfHtml: Result := 'html';
    hrfBoth: Result := 'both';
  else
    Result := 'markdown';
  end;
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
    Result.OpenHtmlReportAfterGenerate := LIniFile.ReadBool(cSettingsSection, 'OpenHtmlReportAfterGenerate', Result.OpenHtmlReportAfterGenerate);
    Result.WarnWhenCompositionEvidenceIsEmpty := LIniFile.ReadBool(cSettingsSection, 'WarnWhenCompositionEvidenceIsEmpty', Result.WarnWhenCompositionEvidenceIsEmpty);
    Result.BuildScriptPath := Trim(LIniFile.ReadString(cSettingsSection, 'BuildScriptPath', Result.BuildScriptPath));
    Result.DelphiVersionOverride := LIniFile.ReadInteger(cSettingsSection, 'DelphiVersionOverride', Result.DelphiVersionOverride);
    Result.HumanReadableReport.Enabled := LIniFile.ReadBool(cSettingsSection, 'ReportEnabled', Result.HumanReadableReport.Enabled);
    Result.HumanReadableReport.Format := StringToReportFormat(LIniFile.ReadString(cSettingsSection, 'ReportFormat', 'markdown'));
    Result.HumanReadableReport.OutputBasePath := Trim(LIniFile.ReadString(cSettingsSection, 'ReportOutputBasePath', Result.HumanReadableReport.OutputBasePath));
    Result.HumanReadableReport.IncludeWarnings := LIniFile.ReadBool(cSettingsSection, 'ReportIncludeWarnings', Result.HumanReadableReport.IncludeWarnings);
    Result.HumanReadableReport.IncludeCompositionEvidence := LIniFile.ReadBool(cSettingsSection, 'ReportIncludeCompositionEvidence', Result.HumanReadableReport.IncludeCompositionEvidence);
    Result.HumanReadableReport.IncludeBuildEvidence := LIniFile.ReadBool(cSettingsSection, 'ReportIncludeBuildEvidence', Result.HumanReadableReport.IncludeBuildEvidence);
    // Issue #126: all, overview or units. An unknown value keeps all.
    TryParseReportContent(LIniFile.ReadString(cSettingsSection, 'ReportContent', 'all'), Result.HumanReadableReport.Content);
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
    LIniFile.WriteBool(cSettingsSection, 'OpenHtmlReportAfterGenerate', ASettings.OpenHtmlReportAfterGenerate);
    LIniFile.WriteBool(cSettingsSection, 'WarnWhenCompositionEvidenceIsEmpty', ASettings.WarnWhenCompositionEvidenceIsEmpty);
    LIniFile.WriteString(cSettingsSection, 'BuildScriptPath', Trim(ASettings.BuildScriptPath));
    LIniFile.WriteInteger(cSettingsSection, 'DelphiVersionOverride', ASettings.DelphiVersionOverride);
    LIniFile.WriteBool(cSettingsSection, 'ReportEnabled', ASettings.HumanReadableReport.Enabled);
    LIniFile.WriteString(cSettingsSection, 'ReportFormat', ReportFormatToString(ASettings.HumanReadableReport.Format));
    LIniFile.WriteString(cSettingsSection, 'ReportOutputBasePath', Trim(ASettings.HumanReadableReport.OutputBasePath));
    LIniFile.WriteBool(cSettingsSection, 'ReportIncludeWarnings', ASettings.HumanReadableReport.IncludeWarnings);
    LIniFile.WriteBool(cSettingsSection, 'ReportIncludeCompositionEvidence', ASettings.HumanReadableReport.IncludeCompositionEvidence);
    LIniFile.WriteBool(cSettingsSection, 'ReportIncludeBuildEvidence', ASettings.HumanReadableReport.IncludeBuildEvidence);
    LIniFile.WriteString(cSettingsSection, 'ReportContent', ReportContentToString(ASettings.HumanReadableReport.Content));
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

class function TDXComplyIDESettingsStore.StringToReportFormat(
  const AValue: string): THumanReadableReportFormat;
begin
  if SameText(AValue, 'html') then
    Exit(hrfHtml);
  if SameText(AValue, 'both') then
    Exit(hrfBoth);

  Result := hrfMarkdown;
end;

end.