/// <summary>
/// DX.Comply.Report.MarkdownWriter
/// Generates human-readable compliance reports in Markdown format.
/// </summary>
///
/// <remarks>
/// The Markdown report complements the formal SBOM with a concise summary for humans:
/// project context, build/evidence quality, artefacts, resolved units and warnings.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Report.MarkdownWriter;

interface

uses
  System.Classes,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf;

type
  /// <summary>
  /// Writes a Markdown companion report.
  /// </summary>
  TMarkdownReportWriter = class(TInterfacedObject, IHumanReadableReportWriter)
  private
    function EscapeMarkdown(const AValue: string): string;
    procedure AddKeyValue(Lines: TStrings; const AKey, AValue: string);
    procedure AddArtefacts(Lines: TStrings; const AData: TComplianceReportData);
    procedure AddUnitEvidence(Lines: TStrings; const AData: TComplianceReportData;
      const AConfig: THumanReadableReportConfig);
    procedure AddWarnings(Lines: TStrings; const AData: TComplianceReportData);
    procedure AddValidation(Lines: TStrings; const AData: TComplianceReportData);
  public
    function Write(const AOutputPath: string; const AData: TComplianceReportData;
      const AConfig: THumanReadableReportConfig): Boolean;
    function GetFormat: THumanReadableReportFormat;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Report.Support;

procedure TMarkdownReportWriter.AddArtefacts(Lines: TStrings; const AData: TComplianceReportData);
var
  LArtefact: TArtefactInfo;
begin
  Lines.Add('## Artefacts');
  Lines.Add('| Relative Path | Type | Size | SHA-256 |');
  Lines.Add('| --- | --- | ---: | --- |');
  for LArtefact in AData.Artefacts do
  begin
    if LArtefact.ArtefactType = 'unit-evidence' then
      Continue;
    Lines.Add(Format('| %s | %s | %d | %s |', [
      EscapeMarkdown(SafeText(LArtefact.RelativePath, LArtefact.FilePath)),
      EscapeMarkdown(SafeText(LArtefact.ArtefactType)),
      LArtefact.FileSize,
      EscapeMarkdown(SafeText(LArtefact.Hash))]));
  end;
  Lines.Add('');
end;

procedure TMarkdownReportWriter.AddUnitEvidence(Lines: TStrings;
  const AData: TComplianceReportData; const AConfig: THumanReadableReportConfig);
var
  LRow: TConsolidatedUnitEvidenceRow;
  LRows: TConsolidatedUnitEvidenceRowList;
  function Checkmark(const AValue: Boolean): string;
  begin
    if AValue then
      Exit('✓');
    Result := '';
  end;
begin
  LRows := BuildConsolidatedUnitEvidenceRows(AData);
  try
    Lines.Add('## Unit Evidence');
    if (not AConfig.IncludeCompositionEvidence) and (not AConfig.IncludeBuildEvidence) then
    begin
      Lines.Add('- Unit evidence output is disabled.');
      Lines.Add('');
      Exit;
    end;

    if AConfig.IncludeCompositionEvidence and AConfig.IncludeBuildEvidence then
    begin
      Lines.Add('| Unit | Origin | Evidence | Confidence | SHA-256 | SBOM Trace | Build Trace | Location |');
      Lines.Add('| --- | --- | --- | --- | --- | :---: | :---: | --- |');
      for LRow in LRows do
        Lines.Add(Format('| %s | %s | %s | %s | %s | %s | %s | %s |', [
          EscapeMarkdown(SafeText(LRow.UnitName)),
          EscapeMarkdown(SafeText(LRow.Origin)),
          EscapeMarkdown(SafeText(LRow.Evidence)),
          EscapeMarkdown(SafeText(LRow.Confidence)),
          EscapeMarkdown(SafeText(LRow.HashSha256, '')),
          Checkmark(LRow.HasCompositionEvidence),
          Checkmark(LRow.HasBuildEvidence),
          EscapeMarkdown(SafeText(LRow.Location))]));
    end
    else if AConfig.IncludeCompositionEvidence then
    begin
      Lines.Add('| Unit | Origin | Evidence | Confidence | SHA-256 | SBOM Trace | Location |');
      Lines.Add('| --- | --- | --- | --- | --- | :---: | --- |');
      for LRow in LRows do
        if LRow.HasCompositionEvidence then
          Lines.Add(Format('| %s | %s | %s | %s | %s | %s | %s |', [
            EscapeMarkdown(SafeText(LRow.UnitName)),
            EscapeMarkdown(SafeText(LRow.Origin)),
            EscapeMarkdown(SafeText(LRow.Evidence)),
            EscapeMarkdown(SafeText(LRow.Confidence)),
            EscapeMarkdown(SafeText(LRow.HashSha256, '')),
            Checkmark(True),
            EscapeMarkdown(SafeText(LRow.Location))]));
    end
    else
    begin
      Lines.Add('| Unit | Origin | Evidence | Confidence | SHA-256 | Build Trace | Location |');
      Lines.Add('| --- | --- | --- | --- | --- | :---: | --- |');
      for LRow in LRows do
        if LRow.HasBuildEvidence then
          Lines.Add(Format('| %s | %s | %s | %s | %s | %s | %s |', [
            EscapeMarkdown(SafeText(LRow.UnitName)),
            EscapeMarkdown(SafeText(LRow.Origin)),
            EscapeMarkdown(SafeText(LRow.Evidence)),
            EscapeMarkdown(SafeText(LRow.Confidence)),
            EscapeMarkdown(SafeText(LRow.HashSha256, '')),
            Checkmark(True),
            EscapeMarkdown(SafeText(LRow.Location))]));
    end;
    Lines.Add('');
  finally
    LRows.Free;
  end;
end;

procedure TMarkdownReportWriter.AddKeyValue(Lines: TStrings; const AKey, AValue: string);
begin
  Lines.Add(Format('| %s | %s |', [EscapeMarkdown(AKey), EscapeMarkdown(AValue)]));
end;

procedure TMarkdownReportWriter.AddValidation(Lines: TStrings; const AData: TComplianceReportData);
var
  LEntry: string;
begin
  Lines.Add('## Validation');
  Lines.Add('| Field | Value |');
  Lines.Add('| --- | --- |');
  AddKeyValue(Lines, 'Status', ValidationStatusText(AData));
  AddKeyValue(Lines, 'Warnings', IntToStr(Length(AData.ValidationResult.Warnings)));
  AddKeyValue(Lines, 'Errors', IntToStr(Length(AData.ValidationResult.Errors)));
  Lines.Add('');
  for LEntry in AData.ValidationResult.Errors do
    Lines.Add('- Error: ' + EscapeMarkdown(LEntry));
  for LEntry in AData.ValidationResult.Warnings do
    Lines.Add('- Warning: ' + EscapeMarkdown(LEntry));
  Lines.Add('');
end;

procedure TMarkdownReportWriter.AddWarnings(Lines: TStrings; const AData: TComplianceReportData);
var
  LWarning: string;
begin
  Lines.Add('## Warnings');
  if (not Assigned(AData.Warnings)) or (AData.Warnings.Count = 0) then
    Lines.Add('- No warnings were recorded.')
  else
    for LWarning in AData.Warnings do
      Lines.Add('- ' + EscapeMarkdown(LWarning));
  Lines.Add('');
end;

function TMarkdownReportWriter.EscapeMarkdown(const AValue: string): string;
begin
  Result := StringReplace(AValue, '|', '\|', [rfReplaceAll]);
  Result := StringReplace(Result, sLineBreak, '<br>', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '<br>', [rfReplaceAll]);
end;

function TMarkdownReportWriter.GetFormat: THumanReadableReportFormat;
begin
  Result := hrfMarkdown;
end;

function TMarkdownReportWriter.Write(const AOutputPath: string;
  const AData: TComplianceReportData; const AConfig: THumanReadableReportConfig): Boolean;
var
  Lines: TStringList;
  LFormalSbomReference: string;
  LWarningsCount: Integer;
begin
  ForceDirectories(TPath.GetDirectoryName(AOutputPath));
  LWarningsCount := 0;
  if Assigned(AData.Warnings) then
    LWarningsCount := AData.Warnings.Count;
  LFormalSbomReference := RelativeOutputReference(AOutputPath, AData.SbomOutputPath);
  Lines := TStringList.Create;
  try
    Lines.Add('# ' + HumanReadableReportTitle);
    Lines.Add('');
    Lines.Add('_' + HumanReadableReportSubtitle + '_');
    Lines.Add('');
    Lines.Add('## Report Context');
    Lines.Add('| Field | Value |');
    Lines.Add('| --- | --- |');
    AddKeyValue(Lines, 'Generated By', HumanReadableReportGenerator);
    AddKeyValue(Lines, 'Repository / Project Root', RepositoryReferenceText(AData.ProjectInfo));
    AddKeyValue(Lines, 'Project File', SafeText(AData.ProjectInfo.ProjectPath));
    AddKeyValue(Lines, 'Formal SBOM', Format('[%s](%s)', [
      EscapeMarkdown(LFormalSbomReference),
      EscapeMarkdown(LFormalSbomReference)]));
    AddKeyValue(Lines, 'Generated At', SafeText(AData.Metadata.Timestamp, AData.CompositionEvidence.GeneratedAt));
    Lines.Add('');
    Lines.Add('## Project Overview');
    Lines.Add('| Field | Value |');
    Lines.Add('| --- | --- |');
    AddKeyValue(Lines, 'Project', SafeText(AData.ProjectInfo.ProjectName));
    AddKeyValue(Lines, 'Version', SafeText(AData.Metadata.ProductVersion, SafeText(AData.ProjectInfo.Version)));
    AddKeyValue(Lines, 'Platform', SafeText(AData.ProjectInfo.Platform));
    AddKeyValue(Lines, 'Configuration', SafeText(AData.ProjectInfo.Configuration));
    AddKeyValue(Lines, 'Delphi Runtime Units', DelphiRuntimeUnitsText(AData.ProjectInfo));
    AddKeyValue(Lines, 'Delphi Toolchain', SafeText(AData.ProjectInfo.Toolchain.ProductName));
    AddKeyValue(Lines, 'Delphi Version', SafeText(AData.ProjectInfo.Toolchain.Version));
    AddKeyValue(Lines, 'Delphi Build', SafeText(AData.ProjectInfo.Toolchain.BuildVersion));
    AddKeyValue(Lines, 'SBOM Format', SbomFormatToString(AData.SbomFormat));
    if Trim(AData.ProjectInfo.Toolchain.RootDir) <> '' then
      AddKeyValue(Lines, 'Toolchain Root', AData.ProjectInfo.Toolchain.RootDir);
    Lines.Add('');
    Lines.Add('## Summary');
    Lines.Add('| Metric | Value |');
    Lines.Add('| --- | ---: |');
    AddKeyValue(Lines, 'Artefacts', IntToStr(PrimaryArtefactCount(AData.Artefacts)));
    if AData.CompositionEvidenceIncluded then
      AddKeyValue(Lines, 'Resolved Units', IntToStr(AData.CompositionEvidence.Units.Count))
    else
      AddKeyValue(Lines, 'Composition Evidence', 'Excluded (binary-only)');
    AddKeyValue(Lines, 'Warnings', IntToStr(LWarningsCount));
    if AData.DeepEvidenceResult.Executed or not AData.DeepEvidenceResult.Success and AData.DeepEvidenceRequested then
      AddKeyValue(Lines, 'Deep Evidence Build', DeepEvidenceStatusText(AData));
    AddKeyValue(Lines, 'Validation', ValidationStatusText(AData));
    Lines.Add('');
    AddValidation(Lines, AData);
    AddArtefacts(Lines, AData);
    if AConfig.IncludeCompositionEvidence or AConfig.IncludeBuildEvidence then
      AddUnitEvidence(Lines, AData, AConfig);
    if AConfig.IncludeWarnings then
      AddWarnings(Lines, AData);
    Lines.SaveToFile(AOutputPath, TEncoding.UTF8);
    Result := True;
  finally
    Lines.Free;
  end;
end;

end.