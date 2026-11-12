/// <summary>
/// DX.Comply.Report.Support
/// Shared formatting helpers for human-readable SBOM reports.
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
    HashSha256: string;
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
function SafeText(const AValue: string; const AFallback: string = 'n/a'): string;
/// <summary>
/// True when AValue starts with http:// or https://. The reports only make
/// such a value a link, so a value like "javascript:..." stays plain text.
/// </summary>
function IsHttpUrl(const AValue: string): Boolean;
function DelphiRuntimeUnitsText(const AProjectInfo: TProjectInfo): string;
/// <summary>
/// Report title. The project name is the prefix, so several open reports
/// can be told apart. The product name is used when the project name is
/// empty. With neither name the title stays "DX.Comply SBOM Report".
/// </summary>
function HumanReadableReportTitle(const AProjectName, AProductName: string): string;
function HumanReadableReportSubtitle: string;
function HumanReadableReportGenerator: string;
function RelativeOutputReference(const ABaseFilePath, ATargetFilePath: string): string;
function RepositoryReferenceText(const AProjectInfo: TProjectInfo): string;
function PrimaryArtefactCount(const AArtefacts: TArtefactList): Integer;
function BuildConsolidatedUnitEvidenceRows(const ABuildEvidence: TBuildEvidence;
  const ACompositionEvidence: TCompositionEvidence): TConsolidatedUnitEvidenceRowList; overload;
function BuildConsolidatedUnitEvidenceRows(
  const AData: TComplianceReportData): TConsolidatedUnitEvidenceRowList; overload;

implementation

uses
  System.Generics.Defaults;

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
    besUsesClause: Result := 'Uses-clause analysis';
    besManualOverride: Result := 'Manual override';
  else
    Result := 'Unknown';
  end;
end;

function IsHttpUrl(const AValue: string): Boolean;
var
  LValue: string;
begin
  LValue := LowerCase(Trim(AValue));
  Result := LValue.StartsWith('http://') or LValue.StartsWith('https://');
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
  Result := 'This report lists the units, packages and DLL names DX.Comply could see in the build, with a hash where the file could be opened. ' +
    'It sits beside the SBOM. The status below is an internal structural check.';
end;

function HumanReadableReportTitle(const AProjectName, AProductName: string): string;
var
  LName: string;
begin
  LName := Trim(AProjectName);
  if LName = '' then
    LName := Trim(AProductName);
  Result := 'DX.Comply SBOM Report';
  if LName <> '' then
    Result := LName + ' - ' + Result;
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

function PrimaryArtefactCount(const AArtefacts: TArtefactList): Integer;
var
  LArtefact: TArtefactInfo;
begin
  Result := 0;
  if not Assigned(AArtefacts) then
    Exit;
  for LArtefact in AArtefacts do
    if LArtefact.ArtefactType <> 'unit-evidence' then
      Inc(Result);
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
    LRow.HashSha256 := LCompositionUnit.SecondaryHashSha256;
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
    sfCycloneDxJson: Result := 'CycloneDX 1.6 JSON';
    sfCycloneDxXml: Result := 'CycloneDX 1.6 XML';
    sfSpdxJson: Result := 'SPDX 2.3 JSON';
    sfSpdx3Json: Result := 'SPDX 3.0.1 JSON-LD';
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
    uekMap: Result := 'MAP';
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
    Exit('Internal structural check passed');
  Result := 'Internal structural check failed';
end;

end.