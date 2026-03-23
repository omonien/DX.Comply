/// <summary>
/// DX.Comply.Report.HtmlWriter
/// Generates human-readable compliance reports in HTML format.
/// </summary>
///
/// <remarks>
/// The HTML report presents the same normalized report payload as the Markdown writer,
/// but with cards, badges and readable tables for auditor-friendly consumption.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Report.HtmlWriter;

interface

uses
  System.Classes,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf;

type
  /// <summary>
  /// Writes an HTML companion report.
  /// </summary>
  THtmlReportWriter = class(TInterfacedObject, IHumanReadableReportWriter)
  private
    function EscapeHtml(const AValue: string): string;
    procedure AddArtefacts(Lines: TStrings; const AData: TComplianceReportData);
    procedure AddUnitEvidence(Lines: TStrings; const AData: TComplianceReportData;
      const AConfig: THumanReadableReportConfig);
    procedure AddSummaryCard(Lines: TStrings; const ATitle, AValue, ACssClass: string);
    procedure AddValidation(Lines: TStrings; const AData: TComplianceReportData);
    procedure AddWarnings(Lines: TStrings; const AData: TComplianceReportData);
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

procedure THtmlReportWriter.AddArtefacts(Lines: TStrings; const AData: TComplianceReportData);
var
  LArtefact: TArtefactInfo;
begin
  Lines.Add('<section><h2>Artefacts</h2><div class="table-wrap"><table><thead><tr><th>Relative Path</th><th>Type</th><th>Size</th><th>SHA-256</th></tr></thead><tbody>');
  for LArtefact in AData.Artefacts do
  begin
    if LArtefact.ArtefactType = 'unit-evidence' then
      Continue;
    Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%d</td><td><code>%s</code></td></tr>', [
      EscapeHtml(SafeText(LArtefact.RelativePath, LArtefact.FilePath)),
      EscapeHtml(SafeText(LArtefact.ArtefactType)),
      LArtefact.FileSize,
      EscapeHtml(SafeText(LArtefact.Hash))]));
  end;
  Lines.Add('</tbody></table></div></section>');
end;

procedure THtmlReportWriter.AddUnitEvidence(Lines: TStrings;
  const AData: TComplianceReportData; const AConfig: THumanReadableReportConfig);
var
  LRow: TConsolidatedUnitEvidenceRow;
  LRows: TConsolidatedUnitEvidenceRowList;
  function Checkmark(const AValue: Boolean): string;
  begin
    if AValue then
      Exit('&#10003;');
    Result := '';
  end;
begin
  LRows := BuildConsolidatedUnitEvidenceRows(AData);
  try
    Lines.Add('<section><h2>Unit Evidence</h2><div class="table-wrap"><table><thead>');
    if AConfig.IncludeCompositionEvidence and AConfig.IncludeBuildEvidence then
      Lines.Add('<tr><th>Unit</th><th>Origin</th><th>Evidence</th><th>Confidence</th><th>SHA-256</th><th>SBOM Trace</th><th>Build Trace</th><th>Location</th></tr>')
    else if AConfig.IncludeCompositionEvidence then
      Lines.Add('<tr><th>Unit</th><th>Origin</th><th>Evidence</th><th>Confidence</th><th>SHA-256</th><th>SBOM Trace</th><th>Location</th></tr>')
    else
      Lines.Add('<tr><th>Unit</th><th>Origin</th><th>Evidence</th><th>Confidence</th><th>SHA-256</th><th>Build Trace</th><th>Location</th></tr>');
    Lines.Add('</thead><tbody>');

    for LRow in LRows do
    begin
      if AConfig.IncludeCompositionEvidence and AConfig.IncludeBuildEvidence then
        Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td><td style="text-align:center">%s</td><td style="text-align:center">%s</td><td>%s</td></tr>', [
          EscapeHtml(SafeText(LRow.UnitName)),
          EscapeHtml(SafeText(LRow.Origin)),
          EscapeHtml(SafeText(LRow.Evidence)),
          EscapeHtml(SafeText(LRow.Confidence)),
          EscapeHtml(SafeText(LRow.HashSha256, '')),
          Checkmark(LRow.HasCompositionEvidence),
          Checkmark(LRow.HasBuildEvidence),
          EscapeHtml(SafeText(LRow.Location))]))
      else if AConfig.IncludeCompositionEvidence and LRow.HasCompositionEvidence then
        Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td><td style="text-align:center">%s</td><td>%s</td></tr>', [
          EscapeHtml(SafeText(LRow.UnitName)),
          EscapeHtml(SafeText(LRow.Origin)),
          EscapeHtml(SafeText(LRow.Evidence)),
          EscapeHtml(SafeText(LRow.Confidence)),
          EscapeHtml(SafeText(LRow.HashSha256, '')),
          Checkmark(True),
          EscapeHtml(SafeText(LRow.Location))]))
      else if AConfig.IncludeBuildEvidence and LRow.HasBuildEvidence then
        Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td><td style="text-align:center">%s</td><td>%s</td></tr>', [
          EscapeHtml(SafeText(LRow.UnitName)),
          EscapeHtml(SafeText(LRow.Origin)),
          EscapeHtml(SafeText(LRow.Evidence)),
          EscapeHtml(SafeText(LRow.Confidence)),
          EscapeHtml(SafeText(LRow.HashSha256, '')),
          Checkmark(True),
          EscapeHtml(SafeText(LRow.Location))]));
    end;

    Lines.Add('</tbody></table></div></section>');
  finally
    LRows.Free;
  end;
end;

procedure THtmlReportWriter.AddSummaryCard(Lines: TStrings; const ATitle, AValue, ACssClass: string);
begin
  Lines.Add(Format('<article class="card %s"><span class="card-title">%s</span><strong class="card-value">%s</strong></article>', [
    ACssClass,
    EscapeHtml(ATitle),
    EscapeHtml(AValue)]));
end;

procedure THtmlReportWriter.AddValidation(Lines: TStrings; const AData: TComplianceReportData);
var
  LEntry: string;
begin
  Lines.Add('<section><h2>Validation</h2>');
  Lines.Add(Format('<p><span class="badge %s">%s</span></p>', [
    LowerCase(ValidationStatusText(AData)),
    EscapeHtml(ValidationStatusText(AData))]));
  if Length(AData.ValidationResult.Errors) > 0 then
  begin
    Lines.Add('<h3>Errors</h3><ul>');
    for LEntry in AData.ValidationResult.Errors do
      Lines.Add('<li>' + EscapeHtml(LEntry) + '</li>');
    Lines.Add('</ul>');
  end;
  if Length(AData.ValidationResult.Warnings) > 0 then
  begin
    Lines.Add('<h3>Warnings</h3><ul>');
    for LEntry in AData.ValidationResult.Warnings do
      Lines.Add('<li>' + EscapeHtml(LEntry) + '</li>');
    Lines.Add('</ul>');
  end;
  Lines.Add('</section>');
end;

procedure THtmlReportWriter.AddWarnings(Lines: TStrings; const AData: TComplianceReportData);
var
  LWarning: string;
begin
  Lines.Add('<section><h2>Warnings</h2><ul>');
  if (not Assigned(AData.Warnings)) or (AData.Warnings.Count = 0) then
    Lines.Add('<li>No warnings were recorded.</li>')
  else
    for LWarning in AData.Warnings do
      Lines.Add('<li>' + EscapeHtml(LWarning) + '</li>');
  Lines.Add('</ul></section>');
end;

function THtmlReportWriter.EscapeHtml(const AValue: string): string;
begin
  Result := StringReplace(AValue, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '<br>', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '<br>', [rfReplaceAll]);
end;

function THtmlReportWriter.GetFormat: THumanReadableReportFormat;
begin
  Result := hrfHtml;
end;

function THtmlReportWriter.Write(const AOutputPath: string;
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
    Lines.Add('<!DOCTYPE html>');
    Lines.Add('<html lang="en"><head><meta charset="utf-8">');
    Lines.Add('<meta name="viewport" content="width=device-width, initial-scale=1">');
    Lines.Add('<title>' + EscapeHtml(HumanReadableReportTitle) + '</title>');
    Lines.Add('<style>');
    Lines.Add('body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#0f172a;color:#e2e8f0}');
    Lines.Add('main{max-width:1200px;margin:0 auto;padding:32px}');
    Lines.Add('h1,h2,h3{color:#f8fafc}a{color:#38bdf8}');
    Lines.Add('section{background:#111827;border:1px solid #334155;border-radius:12px;padding:20px;margin-bottom:20px;overflow:hidden}');
    Lines.Add('.table-wrap{width:100%;max-width:100%;overflow-x:auto;overflow-y:hidden}');
    Lines.Add('table{width:100%;max-width:100%;border-collapse:collapse;table-layout:fixed}');
    Lines.Add('th,td{padding:10px;border-bottom:1px solid #334155;text-align:left;vertical-align:top;overflow-wrap:anywhere;word-break:break-word}');
    Lines.Add('th{background:#1e293b}');
    Lines.Add('.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:16px;margin:24px 0}');
    Lines.Add('.card{background:#111827;border:1px solid #334155;border-radius:12px;padding:16px;min-width:0}');
    Lines.Add('.card-title{display:block;color:#94a3b8;margin-bottom:8px}');
    Lines.Add('.card-value{display:block;overflow-wrap:anywhere;word-break:break-word}');
    Lines.Add('.good strong{color:#4ade80}.warn strong{color:#fbbf24}.bad strong{color:#f87171}');
    Lines.Add('.badge{display:inline-block;border-radius:999px;padding:4px 10px;font-size:12px;font-weight:600}');
    Lines.Add('.badge.passed{background:#14532d;color:#bbf7d0}.badge.failed{background:#7f1d1d;color:#fecaca}');
    Lines.Add('code{color:#cbd5e1;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word}');
    Lines.Add('.lede{color:#cbd5e1;font-size:1.05rem;line-height:1.6;max-width:88ch}');
    Lines.Add('li{overflow-wrap:anywhere;word-break:break-word}');
    Lines.Add('</style></head><body><main>');
    Lines.Add('<section>');
    Lines.Add('<h1>' + EscapeHtml(HumanReadableReportTitle) + '</h1>');
    Lines.Add('<p class="lede">' + EscapeHtml(HumanReadableReportSubtitle) + '</p>');
    Lines.Add('<div class="table-wrap"><table><tbody>');
    Lines.Add('<tr><th>Generated By</th><td>' + EscapeHtml(HumanReadableReportGenerator) + '</td></tr>');
    Lines.Add('<tr><th>Repository / Project Root</th><td><code>' + EscapeHtml(RepositoryReferenceText(AData.ProjectInfo)) + '</code></td></tr>');
    Lines.Add('<tr><th>Project File</th><td><code>' + EscapeHtml(SafeText(AData.ProjectInfo.ProjectPath)) + '</code></td></tr>');
    Lines.Add('<tr><th>Formal SBOM</th><td><a href="' + EscapeHtml(LFormalSbomReference) + '"><code>' +
      EscapeHtml(LFormalSbomReference) + '</code></a></td></tr>');
    Lines.Add('<tr><th>Generated At</th><td>' + EscapeHtml(SafeText(AData.Metadata.Timestamp, AData.CompositionEvidence.GeneratedAt)) + '</td></tr>');
    Lines.Add('</tbody></table></div>');
    Lines.Add('</section>');
    Lines.Add('<div class="cards">');
    AddSummaryCard(Lines, 'Artefacts', IntToStr(PrimaryArtefactCount(AData.Artefacts)), 'good');
    if AData.CompositionEvidenceIncluded then
      AddSummaryCard(Lines, 'Resolved Units', IntToStr(AData.CompositionEvidence.Units.Count), 'good')
    else
      AddSummaryCard(Lines, 'Composition Evidence', 'Excluded (binary-only)', 'warn');
    if LWarningsCount = 0 then
      AddSummaryCard(Lines, 'Warnings', '0', 'good')
    else
      AddSummaryCard(Lines, 'Warnings', IntToStr(LWarningsCount), 'warn');
    if AData.DeepEvidenceResult.Executed or not AData.DeepEvidenceResult.Success and AData.DeepEvidenceRequested then
    begin
      if AData.DeepEvidenceResult.Success then
        AddSummaryCard(Lines, 'Deep Evidence Build', DeepEvidenceStatusText(AData), 'good')
      else
        AddSummaryCard(Lines, 'Deep Evidence Build', DeepEvidenceStatusText(AData), 'bad');
    end;
    if AData.ValidationResult.IsValid then
      AddSummaryCard(Lines, 'Validation', ValidationStatusText(AData), 'good')
    else
      AddSummaryCard(Lines, 'Validation', ValidationStatusText(AData), 'bad');
    Lines.Add('</div>');
    Lines.Add('<section><h2>Project Overview</h2><div class="table-wrap"><table><tbody>');
    Lines.Add('<tr><th>Version</th><td>' + EscapeHtml(SafeText(AData.Metadata.ProductVersion, SafeText(AData.ProjectInfo.Version))) + '</td></tr>');
    Lines.Add('<tr><th>Platform</th><td>' + EscapeHtml(SafeText(AData.ProjectInfo.Platform)) + '</td></tr>');
    Lines.Add('<tr><th>Configuration</th><td>' + EscapeHtml(SafeText(AData.ProjectInfo.Configuration)) + '</td></tr>');
    Lines.Add('<tr><th>Delphi Runtime Units</th><td>' + EscapeHtml(DelphiRuntimeUnitsText(AData.ProjectInfo)) + '</td></tr>');
    Lines.Add('<tr><th>Delphi Toolchain</th><td>' + EscapeHtml(SafeText(AData.ProjectInfo.Toolchain.ProductName)) + '</td></tr>');
    Lines.Add('<tr><th>Delphi Version</th><td>' + EscapeHtml(SafeText(AData.ProjectInfo.Toolchain.Version)) + '</td></tr>');
    Lines.Add('<tr><th>Delphi Build</th><td>' + EscapeHtml(SafeText(AData.ProjectInfo.Toolchain.BuildVersion)) + '</td></tr>');
    Lines.Add('<tr><th>SBOM Format</th><td>' + EscapeHtml(SbomFormatToString(AData.SbomFormat)) + '</td></tr>');
    if Trim(AData.ProjectInfo.Toolchain.RootDir) <> '' then
      Lines.Add('<tr><th>Toolchain Root</th><td>' + EscapeHtml(AData.ProjectInfo.Toolchain.RootDir) + '</td></tr>');
    Lines.Add('</tbody></table></div></section>');
    AddValidation(Lines, AData);
    AddArtefacts(Lines, AData);
    if AConfig.IncludeCompositionEvidence or AConfig.IncludeBuildEvidence then
      AddUnitEvidence(Lines, AData, AConfig);
    if AConfig.IncludeWarnings then
      AddWarnings(Lines, AData);
    Lines.Add('</main></body></html>');
    Lines.SaveToFile(AOutputPath, TEncoding.UTF8);
    Result := True;
  finally
    Lines.Free;
  end;
end;

end.