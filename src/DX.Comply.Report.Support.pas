/// <summary>
/// DX.Comply.Report.Support
/// Shared formatting helpers for human-readable compliance reports.
/// </summary>
///
/// <remarks>
/// The helper functions centralize enum-to-text mappings and summary labels so the
/// Markdown and HTML writers stay focused on layout concerns.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Report.Support;

interface

uses
  System.IOUtils,
  System.SysUtils,
  System.Generics.Collections,
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.Report.Intf;

type
  /// <summary>
  /// Consolidated human-readable evidence row for one unit.
  /// </summary>
  TConsolidatedUnitEvidenceRow = record
    UnitName: string;
    Origin: string;
    Evidence: string;
    Confidence: string;
    Location: string;
    HasCompositionEvidence: Boolean;
    HasBuildEvidence: Boolean;
  end;

  /// <summary>
  /// List of consolidated human-readable evidence rows.
  /// </summary>
  TConsolidatedUnitEvidenceRowList = TList<TConsolidatedUnitEvidenceRow>;

function HumanReadableReportFormatToString(AValue: THumanReadableReportFormat): string;
function SbomFormatToString(AValue: TSbomFormat): string;
function BuildEvidenceSourceKindToString(AValue: TBuildEvidenceSourceKind): string;
function UnitEvidenceKindToString(AValue: TUnitEvidenceKind): string;
function UnitOriginKindToString(AValue: TUnitOriginKind): string;
function ResolutionConfidenceToString(AValue: TResolutionConfidence): string;
function ValidationStatusText(const AData: TComplianceReportData): string;
function DeepEvidenceStatusText(const AData: TComplianceReportData): string;
function SafeText(const AValue: string; const AFallback: string = 'n/a'): string;
function DelphiRuntimeUnitsText(const AProjectInfo: TProjectInfo): string;
function HumanReadableReportTitle: string;
function HumanReadableReportSubtitle: string;
function HumanReadableReportGenerator: string;
function RelativeOutputReference(const ABaseFilePath, ATargetFilePath: string): string;
function RepositoryReferenceText(const AProjectInfo: TProjectInfo): string;
function BuildConsolidatedUnitEvidenceRows(const ABuildEvidence: TBuildEvidence;
  const ACompositionEvidence: TCompositionEvidence): TConsolidatedUnitEvidenceRowList; overload;
function BuildConsolidatedUnitEvidenceRows(
  const AData: TComplianceReportData): TConsolidatedUnitEvidenceRowList; overload;

implementation

uses
  System.Generics.Defaults,
  DX.Comply.BuildOrchestrator;

function BuildEvidenceSourceKindToString(AValue: TBuildEvidenceSourceKind): string;
begin
  case AValue of
    besProjectMetadata: Result := 'Project metadata';
    besCompilerCommandLine: Result := 'Compiler invocation';
    besCompilerResponseFile: Result := 'Compiler options file';
    besCompileNotification: Result := 'Compiler notification';
    besMapFile: Result := 'MAP file';
    besDcuFile: Result := 'DCU file';
    besDcpFile: Result := 'DCP file';
    besBplFile: Result := 'BPL file';
    besSearchPathFallback: Result := 'Search path inference';
    besManualOverride: Result := 'Manual override';
  else
    Result := 'Unknown';
  end;
end;

function DeepEvidenceStatusText(const AData: TComplianceReportData): string;
begin
  if not AData.DeepEvidenceRequested then
    Exit('Not requested');
  if not AData.DeepEvidenceResult.Success then
    Exit('Failed');
  if AData.DeepEvidenceResult.Executed then
    Exit('Executed successfully');
  Result := SafeText(AData.DeepEvidenceResult.Message, 'Skipped');
end;

function DelphiRuntimeUnitsText(const AProjectInfo: TProjectInfo): string;
begin
  if AProjectInfo.UsesDebugDCUs then
    Exit('Debug DCUs');
  Result := 'Release DCUs';
end;

function HumanReadableReportGenerator: string;
begin
  Result := 'DX.Comply';
end;

function RelativeOutputReference(const ABaseFilePath, ATargetFilePath: string): string;
var
  LBaseDirectory: string;
begin
  if Trim(ATargetFilePath) = '' then
    Exit('n/a');

  LBaseDirectory := TPath.GetDirectoryName(ABaseFilePath);
  if Trim(LBaseDirectory) = '' then
    Result := TPath.GetFileName(ATargetFilePath)
  else
    Result := ExtractRelativePath(IncludeTrailingPathDelimiter(LBaseDirectory), ATargetFilePath);

  if Trim(Result) = '' then
    Result := TPath.GetFileName(ATargetFilePath);

  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
end;

function HumanReadableReportSubtitle: string;
begin
  Result := 'This DX.Comply Software Release Assessment summarizes the generated Software Bill of Materials (SBOM), build evidence and deliverable artefacts for the assessed release. ' +
    'It serves as the human-readable companion to the formal SBOM output for review, audit and release approval activities.';
end;

function HumanReadableReportTitle: string;
begin
  Result := 'DX.Comply Software Release Assessment (SRA) and SBOM Compliance Report';
end;

function HumanReadableReportFormatToString(AValue: THumanReadableReportFormat): string;
begin
  case AValue of
    hrfMarkdown: Result := 'Markdown';
    hrfHtml: Result := 'HTML';
    hrfBoth: Result := 'Markdown + HTML';
  else
    Result := 'Unknown';
  end;
end;

function ResolutionConfidenceToString(AValue: TResolutionConfidence): string;
begin
  case AValue of
    rcAuthoritative: Result := 'Authoritative';
    rcStrong: Result := 'Strong';
    rcHeuristic: Result := 'Heuristic';
    rcUnknown: Result := 'Unknown';
  else
    Result := 'Unknown';
  end;
end;

function SafeText(const AValue, AFallback: string): string;
begin
  if Trim(AValue) = '' then
    Exit(AFallback);
  Result := AValue;
end;

function RepositoryReferenceText(const AProjectInfo: TProjectInfo): string;
var
  LCandidate: string;
  LParent: string;
  LStartDirectory: string;
begin
  LStartDirectory := Trim(AProjectInfo.ProjectDir);
  if (LStartDirectory = '') and (Trim(AProjectInfo.ProjectPath) <> '') then
    LStartDirectory := TPath.GetDirectoryName(AProjectInfo.ProjectPath);

  if Trim(LStartDirectory) = '' then
    Exit('n/a');

  LCandidate := ExcludeTrailingPathDelimiter(TPath.GetFullPath(LStartDirectory));
  while LCandidate <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(LCandidate, '.git')) or
      TFile.Exists(TPath.Combine(LCandidate, '.git')) then
      Exit(LCandidate);

    LParent := TPath.GetDirectoryName(LCandidate);
    if SameText(LParent, LCandidate) then
      Break;
    LCandidate := LParent;
  end;

  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(LStartDirectory));
end;

function BuildConsolidatedUnitEvidenceRows(const ABuildEvidence: TBuildEvidence;
  const ACompositionEvidence: TCompositionEvidence): TConsolidatedUnitEvidenceRowList; overload;
var
  LBuildEvidenceItem: TBuildEvidenceItem;
  LCompositionUnit: TResolvedUnitInfo;
  LFound: Boolean;
  LRow: TConsolidatedUnitEvidenceRow;
  I: Integer;
begin
  Result := TConsolidatedUnitEvidenceRowList.Create;

  for LCompositionUnit in ACompositionEvidence.Units do
  begin
    LRow := Default(TConsolidatedUnitEvidenceRow);
    LRow.UnitName := LCompositionUnit.UnitName;
    LRow.Origin := UnitOriginKindToString(LCompositionUnit.OriginKind);
    LRow.Evidence := UnitEvidenceKindToString(LCompositionUnit.EvidenceKind);
    LRow.Confidence := ResolutionConfidenceToString(LCompositionUnit.Confidence);
    if LCompositionUnit.ResolvedPath <> '' then
      LRow.Location := LCompositionUnit.ResolvedPath
    else
      LRow.Location := LCompositionUnit.ContainerPath;
    LRow.HasCompositionEvidence := True;
    Result.Add(LRow);
  end;

  for LBuildEvidenceItem in ABuildEvidence.EvidenceItems do
  begin
    if Trim(LBuildEvidenceItem.UnitName) = '' then
      Continue;

    LFound := False;
    for I := 0 to Result.Count - 1 do
    begin
      if not SameText(Result[I].UnitName, LBuildEvidenceItem.UnitName) then
        Continue;

      LRow := Result[I];
      LRow.HasBuildEvidence := True;
      if (LRow.Location = '') and (LBuildEvidenceItem.FilePath <> '') then
        LRow.Location := LBuildEvidenceItem.FilePath;
      if (LRow.Location = '') and (LBuildEvidenceItem.Detail <> '') then
        LRow.Location := LBuildEvidenceItem.Detail;
      Result[I] := LRow;
      LFound := True;
      Break;
    end;

    if LFound then
      Continue;

    LRow := Default(TConsolidatedUnitEvidenceRow);
    LRow.UnitName := LBuildEvidenceItem.UnitName;
    LRow.Origin := UnitOriginKindToString(uokUnknown);
    LRow.Evidence := UnitEvidenceKindToString(uekUnknown);
    LRow.Confidence := ResolutionConfidenceToString(rcStrong);
    if LBuildEvidenceItem.FilePath <> '' then
      LRow.Location := LBuildEvidenceItem.FilePath
    else
      LRow.Location := LBuildEvidenceItem.Detail;
    LRow.HasBuildEvidence := True;
    Result.Add(LRow);
  end;

  Result.Sort(TComparer<TConsolidatedUnitEvidenceRow>.Construct(
    function(const Left, Right: TConsolidatedUnitEvidenceRow): Integer
    begin
      Result := CompareText(Left.UnitName, Right.UnitName);
    end));
end;

function BuildConsolidatedUnitEvidenceRows(
  const AData: TComplianceReportData): TConsolidatedUnitEvidenceRowList; overload;
begin
  Result := BuildConsolidatedUnitEvidenceRows(AData.BuildEvidence,
    AData.CompositionEvidence);
end;

function SbomFormatToString(AValue: TSbomFormat): string;
begin
  case AValue of
    sfCycloneDxJson: Result := 'CycloneDX JSON';
    sfCycloneDxXml: Result := 'CycloneDX XML';
    sfSpdxJson: Result := 'SPDX JSON';
  else
    Result := 'Unknown';
  end;
end;

function UnitEvidenceKindToString(AValue: TUnitEvidenceKind): string;
begin
  case AValue of
    uekPas: Result := 'PAS';
    uekDcu: Result := 'DCU';
    uekDcp: Result := 'DCP';
    uekBpl: Result := 'BPL';
  else
    Result := 'Unknown';
  end;
end;

function UnitOriginKindToString(AValue: TUnitOriginKind): string;
begin
  case AValue of
    uokEmbarcaderoRtl: Result := 'Embarcadero RTL';
    uokEmbarcaderoVcl: Result := 'Embarcadero VCL';
    uokEmbarcaderoFmx: Result := 'Embarcadero FMX';
    uokLocalProject: Result := 'Local project';
    uokThirdParty: Result := 'Third party';
  else
    Result := 'Unknown';
  end;
end;

function ValidationStatusText(const AData: TComplianceReportData): string;
begin
  if AData.ValidationResult.IsValid then
    Exit('Passed');
  Result := 'Failed';
end;

end.