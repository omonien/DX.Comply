/// <summary>
/// DX.Comply.Report.MarkdownWriter
/// Generates human-readable SBOM reports in Markdown format.
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
    procedure AddOverview(Lines: TStrings; const AData: TComplianceReportData;
      const AConfig: THumanReadableReportConfig);
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
  DX.Comply.ComponentManifest,
  DX.Comply.Report.Overview,
  DX.Comply.Report.Support;

procedure TMarkdownReportWriter.AddArtefacts(Lines: TStrings; const AData: TComplianceReportData);
var
  LArtefact: TArtefactInfo;
  LDeliverable: Integer;
  LVersion: string;
  I: Integer;
begin
  Lines.Add('## Artefacts');
  // Issue #90: Version is the PE FileVersion/ProductVersion already stored
  // on the artefact. The built program with no version of its own uses the
  // product version, the same value as the SBOM and the licence table.
  Lines.Add('| Relative Path | Type | Version | Size | SHA-256 |');
  Lines.Add('| --- | --- | --- | ---: | --- |');
  LDeliverable := FindDeliverableTargetIndex(AData.Artefacts,
    AData.ProjectInfo.ProjectName, AData.ProjectInfo.OutputFilePath);
  for I := 0 to AData.Artefacts.Count - 1 do
  begin
    LArtefact := AData.Artefacts[I];
    if LArtefact.ArtefactType = 'unit-evidence' then
      Continue;
    LVersion := ComponentVersionFor(LArtefact,
      IsSameDeliverableFile(AData.Artefacts, I, LDeliverable),
      AData.Metadata.ProductVersion, AData.ProjectInfo.Version);
    if LArtefact.FileSize >= 0 then
      Lines.Add(Format('| %s | %s | %s | %d | %s |', [
        EscapeMarkdown(SafeText(SafeText(LArtefact.RelativePath, LArtefact.ComponentName), LArtefact.FilePath)),
        EscapeMarkdown(SafeText(LArtefact.ArtefactType)),
        EscapeMarkdown(SafeText(LVersion)),
        LArtefact.FileSize,
        EscapeMarkdown(SafeText(LArtefact.Hash))]))
    else
      Lines.Add(Format('| %s | %s | %s | n/a | %s |', [
        EscapeMarkdown(SafeText(SafeText(LArtefact.RelativePath, LArtefact.ComponentName), LArtefact.FilePath)),
        EscapeMarkdown(SafeText(LArtefact.ArtefactType)),
        EscapeMarkdown(SafeText(LVersion)),
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
  Lines.Add('## Structural check');
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

procedure TMarkdownReportWriter.AddOverview(Lines: TStrings; const AData: TComplianceReportData;
  const AConfig: THumanReadableReportConfig);
begin
  var LOverview := BuildReportOverview(AData, AConfig.GroupByFolder);

  // Issue #113: where the components come from.
  Lines.Add('## Origin summary');
  Lines.Add('| Origin | Components |');
  Lines.Add('| --- | ---: |');
  for var LGroup in LOverview.Origins do
  begin
    // Issue #126: without the unit list there is no target for the link.
    if (AConfig.Content = hrcOverview) and (LGroup.Anchor = cAnchorUnitEvidence) then
      Lines.Add(Format('| %s | %d |', [EscapeMarkdown(LGroup.Title), LGroup.Count]))
    else
      Lines.Add(Format('| [%s](#%s) | %d |', [EscapeMarkdown(LGroup.Title), LGroup.Anchor, LGroup.Count]));
  end;
  Lines.Add(Format('| **Total SBOM components** | **%d** |', [LOverview.TotalComponents]));
  Lines.Add('');
  if Length(LOverview.Suppliers) > 0 then
  begin
    Lines.Add('Third-party units by supplier (from the component manifest):');
    Lines.Add('');
    Lines.Add('| Supplier | Units |');
    Lines.Add('| --- | ---: |');
    for var LGroup in LOverview.Suppliers do
    begin
      // Unknown supplier names sit under the title, grouped by prefix.
      // Issue #176. <br> is the line break already used in these tables.
      var LLabel := EscapeMarkdown(LGroup.Title);
      for var LLine in LGroup.Detail do
        LLabel := LLabel + '<br>' + EscapeMarkdown(LLine);
      Lines.Add(Format('| %s | %d |', [LLabel, LGroup.Count]));
    end;
    Lines.Add('');
  end;

  // Issue #112, #156: one row per component. The licence, the count and the
  // note are written on the first row of the group. Later rows leave those
  // cells empty so the group stays readable in Markdown, which has no rowspan.
  Lines.Add('## Licences');
  Lines.Add('Licences as declared in the SBOM. Review hints are not legal advice.');
  Lines.Add('');
  Lines.Add('| Declared licence | Components | Name | Version | Copyright | Note |');
  Lines.Add('| --- | ---: | --- | --- | --- | --- |');
  for var LGroup in LOverview.Licences do
  begin
    for var i := 0 to High(LGroup.Components) do
    begin
      var LComponent := LGroup.Components[i];
      if i = 0 then
        Lines.Add(Format('| %s | %d | %s | %s | %s | %s |', [
          EscapeMarkdown(LGroup.Title), LGroup.Count,
          EscapeMarkdown(LComponent.Name), EscapeMarkdown(LComponent.Version),
          EscapeMarkdown(LComponent.Copyright), EscapeMarkdown(LGroup.Note)]))
      else
        Lines.Add(Format('| | | %s | %s | %s | |', [
          EscapeMarkdown(LComponent.Name), EscapeMarkdown(LComponent.Version),
          EscapeMarkdown(LComponent.Copyright)]));
    end;
  end;
  Lines.Add('');

  // Issue #114: third-party units the component manifest does not cover.
  if LOverview.WithoutManifestCount > 0 then
  begin
    Lines.Add('## Third-party units without manifest');
    Lines.Add(Format('%d of %d third-party units have no component manifest row. ' +
      'Add a row with supplier, version and licence for each library ' +
      '(see README, section Component manifest).', [LOverview.WithoutManifestCount,
      LOverview.ThirdPartyUnitCount]));
    Lines.Add('');
    Lines.Add('| Unit prefix | Units | Missing | Names |');
    Lines.Add('| --- | ---: | --- | --- |');
    for var LGroup in LOverview.WithoutManifest do
    begin
      Lines.Add(Format('| %s | %d | %s | %s |', [EscapeMarkdown(LGroup.Title), LGroup.Count,
        LGroup.Note, EscapeMarkdown(LGroup.NamesText)]));
    end;
    Lines.Add('');
  end;
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
    Lines.Add('# ' + LTitle);
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
    if SameText(AData.Metadata.ComponentType, 'library') then
      AddKeyValue(Lines, 'Mode', 'library');
    AddKeyValue(Lines, 'Project', SafeText(AData.ProjectInfo.ProjectName));
    if Trim(AData.Metadata.ProductName) <> '' then
      AddKeyValue(Lines, 'Product', AData.Metadata.ProductName);
    AddKeyValue(Lines, 'Version', SafeText(AData.Metadata.ProductVersion, SafeText(AData.ProjectInfo.Version)));
    if Trim(AData.Metadata.SbomCreator) <> '' then
      AddKeyValue(Lines, 'SBOM Creator', AData.Metadata.SbomCreator);
    if Trim(AData.Metadata.Supplier) <> '' then
      AddKeyValue(Lines, 'Supplier', AData.Metadata.Supplier);
    if Trim(AData.Metadata.SupplierUrl) <> '' then
    begin
      var LSupplierUrl := EscapeMarkdown(Trim(AData.Metadata.SupplierUrl));
      // Only an http(s) address becomes a link.
      if IsHttpUrl(AData.Metadata.SupplierUrl) then
        Lines.Add(Format('| Supplier URL | [%s](%s) |', [LSupplierUrl, LSupplierUrl]))
      else
        Lines.Add(Format('| Supplier URL | %s |', [LSupplierUrl]));
    end;
    if Trim(AData.Metadata.Licence) <> '' then
      AddKeyValue(Lines, 'Licence', AData.Metadata.Licence);
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
    AddKeyValue(Lines, 'Structural check', ValidationStatusText(AData));
    Lines.Add('');
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
    Lines.SaveToFile(AOutputPath, TEncoding.UTF8);
    Result := True;
  finally
    Lines.Free;
  end;
end;

end.