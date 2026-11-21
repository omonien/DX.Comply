/// <summary>
/// DX.Comply.Report.HtmlWriter
/// Generates human-readable SBOM reports in HTML format.
/// </summary>
///
/// <remarks>
/// The HTML report presents the same report payload as the Markdown writer,
/// with cards, badges and readable tables. Long lists start collapsed
/// (issue #198). Printing the page, or saving it as PDF, shows them expanded.
/// The Markdown report is unchanged.
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
    /// <summary>
    /// "1 file" or "42 files". The singular word is AOne, the plural is AMany.
    /// </summary>
    function ItemCountText(ACount: Integer; const AOne, AMany: string): string;
    /// <summary>
    /// Collapsed heading text, for example "MIT (42 files)". The title is escaped.
    /// </summary>
    function FoldSummary(const ATitle: string; ACount: Integer;
      const AOne, AMany: string): string;
    /// <summary>
    /// Opens a collapsed details element. ASummaryHtml is already HTML.
    /// </summary>
    procedure BeginFold(Lines: TStrings; const ASummaryHtml: string);
    procedure EndFold(Lines: TStrings);
    procedure AddArtefacts(Lines: TStrings; const AData: TComplianceReportData);
    procedure AddUnitEvidence(Lines: TStrings; const AData: TComplianceReportData;
      const AConfig: THumanReadableReportConfig);
    procedure AddSummaryCard(Lines: TStrings; const ATitle, AValue, ACssClass: string);
    procedure AddValidation(Lines: TStrings; const AData: TComplianceReportData);
    procedure AddWarnings(Lines: TStrings; const AData: TComplianceReportData);
    procedure AddOverview(Lines: TStrings; const AData: TComplianceReportData;
      const AConfig: THumanReadableReportConfig);
  public
    function Write(const AOutputPath: string; const AData: TComplianceReportData;
      const AConfig: THumanReadableReportConfig): Boolean;
    function GetFormat: THumanReadableReportFormat;
  end;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  DX.Comply.ComponentManifest,
  DX.Comply.Report.Overview,
  DX.Comply.Report.Support;

procedure THtmlReportWriter.AddArtefacts(Lines: TStrings; const AData: TComplianceReportData);
var
  LArtefact: TArtefactInfo;
  LBody: TStringList;
  LCount: Integer;
  LDeliverable: Integer;
  LPathCell: string;
  LVersion: string;
  I: Integer;
begin
  // Issue #90: Version is already stored on the artefact. That value is the
  // numeric file version, then the FileVersion string, then the ProductVersion
  // string. The built program with no version of its own uses the product
  // version, the same value as the SBOM and the licence table.
  // Issue #198: the file list starts collapsed. The heading carries the count.
  LBody := TStringList.Create;
  try
    LCount := 0;
    LDeliverable := FindDeliverableTargetIndex(AData.Artefacts,
      AData.ProjectInfo.ProjectName, AData.ProjectInfo.OutputFilePath);
    for I := 0 to AData.Artefacts.Count - 1 do
    begin
      LArtefact := AData.Artefacts[I];
      if LArtefact.ArtefactType = 'unit-evidence' then
        Continue;
      Inc(LCount);
      // Issue #208: a file-date version is an RFC 3339 timestamp. The report
      // spells out UTC. Any other version text stays as stored.
      LVersion := FormatReportUtcTimestamp(ComponentVersionFor(LArtefact,
        IsSameDeliverableFile(AData.Artefacts, I, LDeliverable),
        AData.Metadata.ProductVersion, AData.ProjectInfo.Version));
      LPathCell := EscapeHtml(SafeText(SafeText(LArtefact.RelativePath, LArtefact.ComponentName), LArtefact.FilePath));
      // Issue #59: a DLL found only in a system directory has no hash. Show
      // where it was found instead.
      if LArtefact.Location <> '' then
        LPathCell := LPathCell + '<br><small>System directory: ' +
          EscapeHtml(LArtefact.Location) + '</small>';
      if LArtefact.FileSize >= 0 then
        LBody.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>%d</td><td><code>%s</code></td></tr>', [
          LPathCell,
          EscapeHtml(SafeText(LArtefact.ArtefactType)),
          EscapeHtml(SafeText(LVersion)),
          LArtefact.FileSize,
          EscapeHtml(SafeText(LArtefact.Hash))]))
      else
        LBody.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>n/a</td><td><code>%s</code></td></tr>', [
          LPathCell,
          EscapeHtml(SafeText(LArtefact.ArtefactType)),
          EscapeHtml(SafeText(LVersion)),
          EscapeHtml(SafeText(LArtefact.Hash))]));
    end;
    Lines.Add('<section id="artefacts" class="flat">');
    BeginFold(Lines, 'Artefacts (' + ItemCountText(LCount, 'file', 'files') + ')');
    Lines.Add('<div class="table-wrap"><table><thead><tr><th>Relative Path</th><th>Type</th><th>Version</th><th>Size</th><th>SHA-256</th></tr></thead><tbody>');
    for I := 0 to LBody.Count - 1 do
      Lines.Add(LBody[I]);
    Lines.Add('</tbody></table></div>');
    EndFold(Lines);
    Lines.Add('</section>');
  finally
    LBody.Free;
  end;
end;

function UnitOriginRank(const AOrigin: string): Integer;
begin
  // A stable order so Embarcadero RTL, then VCL and FMX, then the project's
  // own units (local project), sit above the third-party list.
  if SameText(AOrigin, 'Embarcadero RTL') then
    Exit(0);
  if SameText(AOrigin, 'Embarcadero VCL') then
    Exit(1);
  if SameText(AOrigin, 'Embarcadero FMX') then
    Exit(2);
  if SameText(AOrigin, 'Local project') then
    Exit(3);
  if SameText(AOrigin, 'Third party') then
    Exit(4);
  if SameText(AOrigin, 'Unknown') or SameText(AOrigin, 'n/a') then
    Exit(6);
  Result := 5;
end;

function CompareOrigins(const ALeft, ARight: string): Integer;
begin
  Result := UnitOriginRank(ALeft) - UnitOriginRank(ARight);
  if Result = 0 then
    Result := CompareText(ALeft, ARight);
end;

procedure SortOriginNames(AOrder: TList<string>);
var
  i: Integer;
  j: Integer;
  LKey: string;
begin
  // A handful of origin names. Insertion sort leaves the unit order inside
  // each list alone. That order comes from BuildConsolidatedUnitEvidenceRows.
  for i := 1 to AOrder.Count - 1 do
  begin
    LKey := AOrder[i];
    j := i;
    while (j > 0) and (CompareOrigins(AOrder[j - 1], LKey) > 0) do
    begin
      AOrder[j] := AOrder[j - 1];
      Dec(j);
    end;
    AOrder[j] := LKey;
  end;
end;

procedure THtmlReportWriter.AddUnitEvidence(Lines: TStrings;
  const AData: TComplianceReportData; const AConfig: THumanReadableReportConfig);
var
  LGroups: TObjectDictionary<string, TList<TConsolidatedUnitEvidenceRow>>;
  LLabel: string;
  LList: TList<TConsolidatedUnitEvidenceRow>;
  LOrder: TList<string>;
  LOrigin: string;
  LRow: TConsolidatedUnitEvidenceRow;
  LRows: TConsolidatedUnitEvidenceRowList;

  function Checkmark(const AValue: Boolean): string;
  begin
    if AValue then
      Exit('&#10003;');
    Result := '';
  end;

  function RowIncluded(const ARow: TConsolidatedUnitEvidenceRow): Boolean;
  begin
    if AConfig.IncludeCompositionEvidence and AConfig.IncludeBuildEvidence then
      Exit(True);
    if AConfig.IncludeCompositionEvidence then
      Exit(ARow.HasCompositionEvidence);
    Result := AConfig.IncludeBuildEvidence and ARow.HasBuildEvidence;
  end;

  procedure EmitHeader;
  begin
    Lines.Add('<div class="table-wrap"><table><thead>');
    if AConfig.IncludeCompositionEvidence and AConfig.IncludeBuildEvidence then
      Lines.Add('<tr><th>Unit</th><th>Origin</th><th>Evidence</th><th>Confidence</th><th>SHA-256</th><th>SBOM Trace</th><th>Build Trace</th><th>Location</th></tr>')
    else if AConfig.IncludeCompositionEvidence then
      Lines.Add('<tr><th>Unit</th><th>Origin</th><th>Evidence</th><th>Confidence</th><th>SHA-256</th><th>SBOM Trace</th><th>Location</th></tr>')
    else
      Lines.Add('<tr><th>Unit</th><th>Origin</th><th>Evidence</th><th>Confidence</th><th>SHA-256</th><th>Build Trace</th><th>Location</th></tr>');
    Lines.Add('</thead><tbody>');
  end;

  procedure EmitRow(const ARow: TConsolidatedUnitEvidenceRow);
  begin
    if AConfig.IncludeCompositionEvidence and AConfig.IncludeBuildEvidence then
      Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td><td style="text-align:center">%s</td><td style="text-align:center">%s</td><td>%s</td></tr>', [
        EscapeHtml(SafeText(ARow.UnitName)),
        EscapeHtml(SafeText(ARow.Origin)),
        EscapeHtml(SafeText(ARow.Evidence)),
        EscapeHtml(SafeText(ARow.Confidence)),
        EscapeHtml(SafeText(ARow.HashSha256, '')),
        Checkmark(ARow.HasCompositionEvidence),
        Checkmark(ARow.HasBuildEvidence),
        EscapeHtml(SafeText(ARow.Location))]))
    else if AConfig.IncludeCompositionEvidence then
      Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td><td style="text-align:center">%s</td><td>%s</td></tr>', [
        EscapeHtml(SafeText(ARow.UnitName)),
        EscapeHtml(SafeText(ARow.Origin)),
        EscapeHtml(SafeText(ARow.Evidence)),
        EscapeHtml(SafeText(ARow.Confidence)),
        EscapeHtml(SafeText(ARow.HashSha256, '')),
        Checkmark(True),
        EscapeHtml(SafeText(ARow.Location))]))
    else
      Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td><td style="text-align:center">%s</td><td>%s</td></tr>', [
        EscapeHtml(SafeText(ARow.UnitName)),
        EscapeHtml(SafeText(ARow.Origin)),
        EscapeHtml(SafeText(ARow.Evidence)),
        EscapeHtml(SafeText(ARow.Confidence)),
        EscapeHtml(SafeText(ARow.HashSha256, '')),
        Checkmark(True),
        EscapeHtml(SafeText(ARow.Location))]));
  end;

begin
  // Issue #198: one collapsed list per origin, so the Embarcadero RTL list
  // and the project's own units (local project) can be opened on their own.
  LRows := BuildConsolidatedUnitEvidenceRows(AData);
  try
    LGroups := TObjectDictionary<string, TList<TConsolidatedUnitEvidenceRow>>.Create([doOwnsValues]);
    try
      LOrder := TList<string>.Create;
      try
        for LRow in LRows do
        begin
          if not RowIncluded(LRow) then
            Continue;
          LLabel := SafeText(LRow.Origin);
          if LGroups.TryGetValue(LLabel, LList) then
            LList.Add(LRow)
          else
          begin
            LList := TList<TConsolidatedUnitEvidenceRow>.Create;
            LGroups.Add(LLabel, LList);
            LOrder.Add(LLabel);
            LList.Add(LRow);
          end;
        end;
        SortOriginNames(LOrder);

        Lines.Add('<section id="unit-evidence" class="flat"><h2>Unit Evidence</h2>');
        if LOrder.Count = 0 then
          Lines.Add('<p>No unit evidence was recorded.</p>')
        else
          for LOrigin in LOrder do
          begin
            LList := LGroups[LOrigin];
            BeginFold(Lines, FoldSummary(LOrigin, LList.Count, 'unit', 'units'));
            EmitHeader;
            for LRow in LList do
              EmitRow(LRow);
            Lines.Add('</tbody></table></div>');
            EndFold(Lines);
          end;
        Lines.Add('</section>');
      finally
        LOrder.Free;
      end;
    finally
      LGroups.Free;
    end;
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
  LBadgeClass: string;
  LEntry: string;
begin
  if AData.ValidationResult.IsValid then
    LBadgeClass := 'passed'
  else
    LBadgeClass := 'failed';

  Lines.Add('<section><h2>Structural check</h2>');
  Lines.Add(Format('<p><span class="badge %s">%s</span></p>', [
    LBadgeClass,
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

procedure THtmlReportWriter.AddOverview(Lines: TStrings; const AData: TComplianceReportData;
  const AConfig: THumanReadableReportConfig);
begin
  var LOverview := BuildReportOverview(AData, AConfig.GroupByFolder);

  // Issue #113: where the components come from.
  Lines.Add('<section id="' + cAnchorOrigins + '"><h2>Origin summary</h2><div class="table-wrap"><table>');
  Lines.Add('<thead><tr><th>Origin</th><th>Components</th></tr></thead><tbody>');
  for var LGroup in LOverview.Origins do
  begin
    // Issue #126: without the unit list there is no target for the link.
    if (AConfig.Content = hrcOverview) and (LGroup.Anchor = cAnchorUnitEvidence) then
      Lines.Add(Format('<tr><td>%s</td><td>%d</td></tr>', [EscapeHtml(LGroup.Title), LGroup.Count]))
    else
      Lines.Add(Format('<tr><td><a href="#%s">%s</a></td><td>%d</td></tr>',
        [LGroup.Anchor, EscapeHtml(LGroup.Title), LGroup.Count]));
  end;
  Lines.Add(Format('<tr><th>Total SBOM components</th><th>%d</th></tr>', [LOverview.TotalComponents]));
  Lines.Add('</tbody></table></div>');
  if Length(LOverview.Suppliers) > 0 then
  begin
    Lines.Add('<p>Units by supplier (from the component manifest):</p>');
    Lines.Add('<div class="table-wrap"><table><thead><tr><th>Supplier</th><th>Units</th></tr></thead><tbody>');
    for var LGroup in LOverview.Suppliers do
    begin
      // Unknown supplier names sit under the title, grouped by prefix.
      // Issue #176.
      var LLabel := EscapeHtml(LGroup.Title);
      for var LLine in LGroup.Detail do
        LLabel := LLabel + '<br>' + EscapeHtml(LLine);
      Lines.Add(Format('<tr><td>%s</td><td>%d</td></tr>', [LLabel, LGroup.Count]));
    end;
    Lines.Add('</tbody></table></div>');
  end;
  Lines.Add('</section>');

  // Issue #112, #156: one row per component. Issue #198: each licence is a
  // collapsed list. The heading shows the licence and the file count. The
  // review note stays visible on that heading. The Markdown table is unchanged
  // and still fills the licence, the count and the note on the first row only.
  Lines.Add('<section id="' + cAnchorLicences + '" class="flat"><h2>Licences</h2>');
  Lines.Add('<p>Licences as declared in the SBOM. Review hints are not legal advice.</p>');
  for var LGroup in LOverview.Licences do
  begin
    var LSummary := FoldSummary(LGroup.Title, LGroup.Count, 'file', 'files');
    if LGroup.Note <> '' then
      LSummary := LSummary + '<span class="hint">' + EscapeHtml(LGroup.Note) + '</span>';
    BeginFold(Lines, LSummary);
    Lines.Add('<div class="table-wrap"><table>');
    Lines.Add('<thead><tr><th>Name</th><th>Version</th><th>Copyright</th></tr></thead><tbody>');
    for var i := 0 to High(LGroup.Components) do
    begin
      var LComponent := LGroup.Components[i];
      Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td></tr>', [
        EscapeHtml(LComponent.Name),
        EscapeHtml(FormatReportUtcTimestamp(LComponent.Version)),
        EscapeHtml(LComponent.Copyright)]));
    end;
    Lines.Add('</tbody></table></div>');
    EndFold(Lines);
  end;
  Lines.Add('</section>');

  // Issue #114: third-party units the component manifest does not cover.
  if LOverview.WithoutManifestCount > 0 then
  begin
    Lines.Add('<section id="' + cAnchorWithoutManifest + '" class="flat">');
    BeginFold(Lines, FoldSummary('Third-party units without manifest',
      LOverview.WithoutManifestCount, 'unit', 'units'));
    Lines.Add(Format('<p>%d of %d third-party units have no component manifest row. ' +
      'Add a row with supplier, version and licence for each library ' +
      '(see README, section Component manifest).</p>', [LOverview.WithoutManifestCount,
      LOverview.ThirdPartyUnitCount]));
    Lines.Add('<div class="table-wrap"><table><thead><tr><th>Unit prefix</th><th>Units</th>' +
      '<th>Missing</th><th>Names</th></tr></thead><tbody>');
    for var LGroup in LOverview.WithoutManifest do
    begin
      Lines.Add(Format('<tr><td>%s</td><td>%d</td><td>%s</td><td>%s</td></tr>',
        [EscapeHtml(LGroup.Title), LGroup.Count, EscapeHtml(LGroup.Note), EscapeHtml(LGroup.NamesText)]));
    end;
    Lines.Add('</tbody></table></div>');
    EndFold(Lines);
    Lines.Add('</section>');
  end;

  // A prefix that matched and was not applied. Omitted when there is none.
  if Length(LOverview.PrefixRejections) > 0 then
  begin
    Lines.Add('<section id="' + cAnchorPrefixRejections + '" class="flat">');
    BeginFold(Lines, FoldSummary('Prefix matches not applied',
      Length(LOverview.PrefixRejections), 'unit', 'units'));
    Lines.Add('<p>A prefix is not enough to assign these units. ' +
      'Add units_folder for the package directory, or units_exact for the unit. ' +
      'The origin below is the one that was kept.</p>');
    Lines.Add('<div class="table-wrap"><table><thead><tr><th>Unit</th><th>Prefix</th>' +
      '<th>Row</th><th>Kept origin</th></tr></thead><tbody>');
    for var LRejection in LOverview.PrefixRejections do
    begin
      Lines.Add(Format('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>', [
        EscapeHtml(LRejection.UnitName), EscapeHtml(LRejection.Prefix),
        EscapeHtml(LRejection.RowName), EscapeHtml(LRejection.KeptOrigin)]));
    end;
    Lines.Add('</tbody></table></div>');
    EndFold(Lines);
    Lines.Add('</section>');
  end;
end;

procedure THtmlReportWriter.BeginFold(Lines: TStrings; const ASummaryHtml: string);
begin
  // No open attribute: the list starts collapsed (issue #198).
  Lines.Add('<details class="fold"><summary>' + ASummaryHtml + '</summary>');
end;

procedure THtmlReportWriter.EndFold(Lines: TStrings);
begin
  Lines.Add('</details>');
end;

function THtmlReportWriter.FoldSummary(const ATitle: string; ACount: Integer;
  const AOne, AMany: string): string;
begin
  Result := EscapeHtml(ATitle) + ' (' + ItemCountText(ACount, AOne, AMany) + ')';
end;

function THtmlReportWriter.ItemCountText(ACount: Integer; const AOne, AMany: string): string;
begin
  if ACount = 1 then
    Result := '1 ' + AOne
  else
    Result := IntToStr(ACount) + ' ' + AMany;
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
  LTitle: string;
begin
  ForceDirectories(TPath.GetDirectoryName(AOutputPath));
  LWarningsCount := 0;
  if Assigned(AData.Warnings) then
    LWarningsCount := AData.Warnings.Count;
  LFormalSbomReference := RelativeOutputReference(AOutputPath, AData.SbomOutputPath);
  LTitle := HumanReadableReportTitle(AData.ProjectInfo.ProjectName, AData.Metadata.ProductName);

  Lines := TStringList.Create;
  try
    Lines.Add('<!DOCTYPE html>');
    Lines.Add('<html lang="en"><head><meta charset="utf-8">');
    Lines.Add('<meta name="viewport" content="width=device-width, initial-scale=1">');
    Lines.Add('<title>' + EscapeHtml(LTitle) + '</title>');
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
    // Issue #198: long lists are native disclosure elements. The flat section
    // is only a heading plus those lists, so it is not a second card.
    Lines.Add('section.flat{background:transparent;border:none;padding:0;overflow:visible;margin-bottom:0}');
    Lines.Add('section.flat>h2{margin:8px 0}');
    Lines.Add('section.flat>p{margin:0 0 12px;color:#cbd5e1}');
    Lines.Add('details.fold{background:#111827;border:1px solid #334155;border-radius:12px;margin:0 0 20px;overflow:hidden}');
    Lines.Add('details.fold>summary{cursor:pointer;padding:16px 18px;font-size:1.25rem;font-weight:600;color:#f8fafc;list-style-position:inside;overflow-wrap:anywhere}');
    Lines.Add('details.fold>summary .hint{display:block;margin-top:6px;font-size:0.95rem;font-weight:400;color:#fbbf24}');
    Lines.Add('details.fold>summary:hover{background:#1e293b}');
    Lines.Add('details.fold .table-wrap{padding:0 12px 12px}');
    Lines.Add('details.fold>p{margin:12px 16px 0;color:#cbd5e1}');
    // Print and PDF show every list. CSS asks the browser to reveal the
    // contents and to drop the disclosure arrow. Some browsers ignore that
    // for a closed details element, so the script below opens them on
    // beforeprint and restores them on afterprint. Without the script the
    // lists still open and close on screen.
    Lines.Add('@media print{');
    Lines.Add('details.fold{display:block!important}');
    Lines.Add('details.fold>summary{display:block!important;list-style:none!important}');
    Lines.Add('details.fold>summary::-webkit-details-marker{display:none!important}');
    Lines.Add('details.fold>summary::marker{content:none!important;display:none!important}');
    Lines.Add('details.fold>summary~*{display:block!important}');
    Lines.Add('details.fold table{display:table!important}');
    Lines.Add('details.fold thead{display:table-header-group!important}');
    Lines.Add('details.fold tbody{display:table-row-group!important}');
    Lines.Add('details.fold tr{display:table-row!important}');
    Lines.Add('details.fold th,details.fold td{display:table-cell!important}');
    Lines.Add('}');
    Lines.Add('</style></head><body><main>');
    Lines.Add('<section>');
    Lines.Add('<h1>' + EscapeHtml(LTitle) + '</h1>');
    Lines.Add('<p class="lede">' + EscapeHtml(HumanReadableReportSubtitle) + '</p>');
    Lines.Add('<div class="table-wrap"><table><tbody>');
    Lines.Add('<tr><th>Generated By</th><td>' + EscapeHtml(HumanReadableReportGenerator) + '</td></tr>');
    Lines.Add('<tr><th>Repository / Project Root</th><td><code>' + EscapeHtml(RepositoryReferenceText(AData.ProjectInfo)) + '</code></td></tr>');
    Lines.Add('<tr><th>Project File</th><td><code>' + EscapeHtml(SafeText(AData.ProjectInfo.ProjectPath)) + '</code></td></tr>');
    Lines.Add('<tr><th>Formal SBOM</th><td><a href="' + EscapeHtml(LFormalSbomReference) + '"><code>' +
      EscapeHtml(LFormalSbomReference) + '</code></a></td></tr>');
    // Issue #208: the row label stays Generated At. The value names UTC.
    Lines.Add('<tr><th>Generated At</th><td>' + EscapeHtml(FormatReportUtcTimestamp(
      SafeText(AData.Metadata.Timestamp, AData.CompositionEvidence.GeneratedAt))) + '</td></tr>');
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
    if AData.ValidationResult.IsValid then
      AddSummaryCard(Lines, 'Structural check', ValidationStatusText(AData), 'good')
    else
      AddSummaryCard(Lines, 'Structural check', ValidationStatusText(AData), 'bad');
    Lines.Add('</div>');
    Lines.Add('<section><h2>Project Overview</h2><div class="table-wrap"><table><tbody>');
    if SameText(AData.Metadata.ComponentType, 'library') then
      Lines.Add('<tr><th>Mode</th><td>library</td></tr>');
    if Trim(AData.Metadata.ProductName) <> '' then
      Lines.Add('<tr><th>Product</th><td>' + EscapeHtml(AData.Metadata.ProductName) + '</td></tr>');
    Lines.Add('<tr><th>Version</th><td>' + EscapeHtml(SafeText(AData.Metadata.ProductVersion, SafeText(AData.ProjectInfo.Version))) + '</td></tr>');
    if Trim(AData.Metadata.SbomCreator) <> '' then
      Lines.Add('<tr><th>SBOM Creator</th><td>' + EscapeHtml(AData.Metadata.SbomCreator) + '</td></tr>');
    if Trim(AData.Metadata.Supplier) <> '' then
      Lines.Add('<tr><th>Supplier</th><td>' + EscapeHtml(AData.Metadata.Supplier) + '</td></tr>');
    if Trim(AData.Metadata.SupplierUrl) <> '' then
    begin
      var LSupplierUrl := EscapeHtml(Trim(AData.Metadata.SupplierUrl));
      // Only an http(s) address becomes a link.
      if IsHttpUrl(AData.Metadata.SupplierUrl) then
        Lines.Add('<tr><th>Supplier URL</th><td><a href="' + LSupplierUrl + '">' + LSupplierUrl + '</a></td></tr>')
      else
        Lines.Add('<tr><th>Supplier URL</th><td>' + LSupplierUrl + '</td></tr>');
    end;
    if Trim(AData.Metadata.Licence) <> '' then
      Lines.Add('<tr><th>Licence</th><td>' + EscapeHtml(AData.Metadata.Licence) + '</td></tr>');
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
    // Issue #126: --report-content / report.content selects the sections.
    if AConfig.Content <> hrcUnits then
      AddOverview(Lines, AData, AConfig);
    AddValidation(Lines, AData);
    AddArtefacts(Lines, AData);
    if (AConfig.Content <> hrcOverview) and
      (AConfig.IncludeCompositionEvidence or AConfig.IncludeBuildEvidence) then
      AddUnitEvidence(Lines, AData, AConfig);
    if AConfig.IncludeWarnings then
      AddWarnings(Lines, AData);
    Lines.Add('</main>');
    // Opens every collapsed list for print and PDF, then puts the screen
    // back. The lists still work when this script does not run.
    Lines.Add('<script>');
    Lines.Add('(function(){');
    Lines.Add('var saved=[];');
    Lines.Add('function expand(){');
    Lines.Add('var nodes=document.querySelectorAll("details.fold");');
    Lines.Add('saved=[];');
    Lines.Add('for(var i=0;i<nodes.length;i++){saved.push(nodes[i].open);nodes[i].open=true;}');
    Lines.Add('}');
    Lines.Add('function restore(){');
    Lines.Add('var nodes=document.querySelectorAll("details.fold");');
    Lines.Add('for(var i=0;i<nodes.length&&i<saved.length;i++)nodes[i].open=saved[i];');
    Lines.Add('}');
    Lines.Add('window.addEventListener("beforeprint",expand);');
    Lines.Add('window.addEventListener("afterprint",restore);');
    Lines.Add('})();');
    Lines.Add('</script>');
    Lines.Add('</body></html>');
    Lines.SaveToFile(AOutputPath, TEncoding.UTF8);
    Result := True;
  finally
    Lines.Free;
  end;
end;

end.