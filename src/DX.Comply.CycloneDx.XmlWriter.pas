/// <summary>
/// DX.Comply.CycloneDx.XmlWriter
/// Generates CycloneDX 1.6 SBOM documents in XML format.
/// </summary>
///
/// <remarks>
/// This unit provides TCycloneDxXmlWriter which generates CycloneDX 1.6 XML SBOMs:
/// - Full metadata section with tool information
/// - Component list with hashes (SHA-256 and SHA-512 when the file could be opened)
/// - Dependency graph grouped by deliverable, runtime packages, external DLLs and linked units
/// - Direct uses edges between units whose Pascal source was read
/// - Schema validation support
///
/// The XML output conforms to the CycloneDX 1.6 XSD schema:
/// https://cyclonedx.org/schema/bom-1.6.xsd
///
/// Uses lightweight string-based XML generation to avoid MSXML/COM dependencies,
/// ensuring the writer works in all environments (IDE, CLI, test runners).
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.CycloneDx.XmlWriter;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.DateUtils,
  DX.Comply.DependencyGraph,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Implementation of ISbomWriter for CycloneDX XML format.
  /// </summary>
  TCycloneDxXmlWriter = class(TInterfacedObject, ISbomWriter)
  private
    const
      cSpecVersion = '1.6';
      cNamespace = 'http://cyclonedx.org/schema/bom/1.6';
      cToolName = 'DX.Comply';
      cIndent = '  ';
  private
    FLines: TStringList;
    FIndentLevel: Integer;
    function GenerateUuid: string;
    function EscapeXml(const AValue: string): string;
    procedure AddLine(const ALine: string);
    procedure OpenTag(const ATag: string; const AAttributes: string = '');
    procedure CloseTag(const ATag: string);
    procedure AddElement(const ATag, AValue: string);
    procedure AddPropertyElements(const AProperties: TArray<TSbomProperty>);
    procedure BuildMetadata(const AMetadata: TSbomMetadata; const AProjectInfo: TProjectInfo);
    procedure BuildComponent(const AArtefact: TArtefactInfo; const AIndex: Integer;
      AUnresolvedSource: Boolean);
    procedure BuildComponents(const AArtefacts: TArtefactList; const AMetadata: TSbomMetadata;
      const AGraph: TUsesDependencyGraph);
    procedure BuildDependencies(const AArtefacts: TArtefactList; const AProjectBomRef: string;
      const AGraph: TUsesDependencyGraph);
  public
    function Write(const AOutputPath: string;
      const AMetadata: TSbomMetadata;
      const AArtefacts: TArtefactList;
      const AProjectInfo: TProjectInfo): Boolean;
    function GetFormat: TSbomFormat;
    function Validate(const AContent: string): Boolean;
  end;

implementation

uses
  System.RegularExpressions,
  DX.Comply.ComponentManifest,
  DX.Comply.Schema.Validator,
  DX.Comply.VersionInfo;

{ TCycloneDxXmlWriter }

function TCycloneDxXmlWriter.GenerateUuid: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := LowerCase(GUIDToString(LGuid));
  Result := Result.Substring(1, Result.Length - 2);
end;

function TCycloneDxXmlWriter.EscapeXml(const AValue: string): string;
begin
  Result := AValue;
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

procedure TCycloneDxXmlWriter.AddLine(const ALine: string);
var
  LPrefix: string;
  I: Integer;
begin
  LPrefix := '';
  for I := 1 to FIndentLevel do
    LPrefix := LPrefix + cIndent;
  FLines.Add(LPrefix + ALine);
end;

procedure TCycloneDxXmlWriter.OpenTag(const ATag: string; const AAttributes: string);
begin
  if AAttributes <> '' then
    AddLine('<' + ATag + ' ' + AAttributes + '>')
  else
    AddLine('<' + ATag + '>');
  Inc(FIndentLevel);
end;

procedure TCycloneDxXmlWriter.CloseTag(const ATag: string);
begin
  Dec(FIndentLevel);
  AddLine('</' + ATag + '>');
end;

procedure TCycloneDxXmlWriter.AddElement(const ATag, AValue: string);
begin
  AddLine('<' + ATag + '>' + EscapeXml(AValue) + '</' + ATag + '>');
end;

procedure TCycloneDxXmlWriter.AddPropertyElements(
  const AProperties: TArray<TSbomProperty>);
var
  LHasProperties: Boolean;
  LProperty: TSbomProperty;
begin
  LHasProperties := False;
  for LProperty in AProperties do
  begin
    if Trim(LProperty.Name) = '' then
      Continue;

    if not LHasProperties then
    begin
      OpenTag('properties');
      LHasProperties := True;
    end;

    AddLine('<property name="' + EscapeXml(LProperty.Name) + '">' +
      EscapeXml(LProperty.Value) + '</property>');
  end;

  if LHasProperties then
    CloseTag('properties');
end;

procedure TCycloneDxXmlWriter.BuildMetadata(const AMetadata: TSbomMetadata;
  const AProjectInfo: TProjectInfo);
begin
  OpenTag('metadata');

  // Timestamp in UTC with a Z suffix (BSI TR-03183-2 section 5.2.1).
  AddElement('timestamp', FormatUtcTimestamp(AMetadata.Timestamp));

  // CycloneDX 1.6 metadata sequence: timestamp, lifecycles, tools, authors,
  // component, manufacturer, manufacture, supplier, licenses, properties.
  // tools/tool is still accepted by bom-1.6.xsd and is marked deprecated there.
  OpenTag('tools');
  OpenTag('tool');
  AddElement('vendor', 'Olaf Monien');
  AddElement('name', cToolName);
  AddElement('version', ResolveDxComplyToolVersion(AMetadata.ToolVersion));
  CloseTag('tool');
  CloseTag('tools');

  // Component (the project being documented). Prefer metadata overrides
  // (CLI --product / --version) over values from the .dproj. Issue #26.
  // Component sequence places supplier before name and version.
  OpenTag('component', 'type="' + EscapeXml(SbomRootComponentType(AMetadata)) +
    '" bom-ref="' + EscapeXml(AProjectInfo.ProjectName) + '"');
  if AMetadata.Supplier <> '' then
  begin
    OpenTag('supplier');
    AddElement('name', AMetadata.Supplier);
    if AMetadata.SupplierUrl <> '' then
      AddElement('url', AMetadata.SupplierUrl);
    if IsBsiEmailAddress(Trim(AMetadata.Supplier)) then
    begin
      OpenTag('contact');
      AddElement('email', Trim(AMetadata.Supplier));
      CloseTag('contact');
    end;
    CloseTag('supplier');
  end;
  if AMetadata.ProductName <> '' then
    AddElement('name', AMetadata.ProductName)
  else
    AddElement('name', AProjectInfo.ProjectName);
  if AMetadata.ProductVersion <> '' then
    AddElement('version', AMetadata.ProductVersion)
  else if AProjectInfo.Version <> '' then
    AddElement('version', AProjectInfo.Version);
  // bom-1.6 component order: version, then licenses, then purl, then properties.
  AppendCycloneDxLicencesXml(FLines, AMetadata.Licence, '', FIndentLevel);
  if Trim(AMetadata.Purl) <> '' then
    AddElement('purl', AMetadata.Purl);
  AddPropertyElements(AMetadata.ComponentProperties);
  CloseTag('component');

  // manufacturer follows component in the CycloneDX 1.6 metadata sequence.
  // It is one organizational entity. The deprecated manufacture element is
  // not written.
  if BsiCreatorKind(AMetadata.SbomCreator) = 'email' then
  begin
    OpenTag('manufacturer');
    OpenTag('contact');
    AddElement('email', Trim(AMetadata.SbomCreator));
    CloseTag('contact');
    CloseTag('manufacturer');
  end
  else if BsiCreatorKind(AMetadata.SbomCreator) = 'url' then
  begin
    OpenTag('manufacturer');
    AddElement('url', Trim(AMetadata.SbomCreator));
    CloseTag('manufacturer');
  end;

  AddPropertyElements(AMetadata.Properties);

  CloseTag('metadata');
end;

procedure TCycloneDxXmlWriter.BuildComponent(const AArtefact: TArtefactInfo;
  const AIndex: Integer; AUnresolvedSource: Boolean);
var
  LComponentType: string;
  LBomRef: string;
  LFileName: string;
begin
  if AArtefact.ArtefactType = 'application' then
    LComponentType := 'application'
  else if AArtefact.ArtefactType = 'framework' then
    LComponentType := 'framework'
  else if (AArtefact.ArtefactType = 'library') or (AArtefact.ArtefactType = 'unit-evidence') or
    (AArtefact.ArtefactType = 'package') or (AArtefact.ArtefactType = 'runtime-package') or
    (AArtefact.ArtefactType = 'external-reference') or
    (AArtefact.ArtefactType = 'required-package') then
    LComponentType := 'library'
  else
    LComponentType := 'file';

  LBomRef := 'comp-' + IntToStr(AIndex);

  OpenTag('component', 'type="' + LComponentType + '" bom-ref="' + EscapeXml(LBomRef) + '"');

  AddElement('name', ArtefactComponentName(AArtefact));

  if Trim(AArtefact.Version) <> '' then
    AddElement('version', Trim(AArtefact.Version))
  else if AArtefact.Hash <> '' then
    AddElement('version', Copy(AArtefact.Hash, 1, 12));

  // Component sequence: name, version, then hashes, then purl, then properties.
  if (AArtefact.Hash <> '') or (AArtefact.HashSha512 <> '') then
  begin
    OpenTag('hashes');
    if AArtefact.Hash <> '' then
      AddLine('<hash alg="SHA-256">' + LowerCase(AArtefact.Hash) + '</hash>');
    if AArtefact.HashSha512 <> '' then
      AddLine('<hash alg="SHA-512">' + LowerCase(AArtefact.HashSha512) + '</hash>');
    CloseTag('hashes');
  end;

  if AArtefact.RelativePath <> '' then
    AddElement('purl', 'file:' + AArtefact.RelativePath);

  // Component sequence places externalReferences after purl and before
  // properties. The distribution url is the file: locator. bom-1.6 requires
  // that url. The reference is written for a hashed executable or archive.
  if (AArtefact.HashSha512 <> '') and
     (IsBsiExecutableArtefact(AArtefact) or
      IsBsiArchiveFileName(BsiComponentFileName(AArtefact.RelativePath))) then
  begin
    OpenTag('externalReferences');
    OpenTag('reference', 'type="distribution"');
    AddElement('url', 'file:' + AArtefact.RelativePath);
    OpenTag('hashes');
    AddLine('<hash alg="SHA-512">' + LowerCase(AArtefact.HashSha512) + '</hash>');
    CloseTag('hashes');
    CloseTag('reference');
    CloseTag('externalReferences');
  end;

  // Evidence and confidence must be written for source-scanned DLLs, which
  // have no file on disk (size -1) and an empty origin. Gating the whole
  // block on size or origin dropped those properties. Issue #45.
  // A file name is enough on its own: the TR properties still apply when
  // the file could not be opened.
  LFileName := BsiComponentFileName(AArtefact.RelativePath);
  if (AArtefact.FileSize >= 0) or (Trim(AArtefact.Origin) <> '') or
     (Trim(AArtefact.Evidence) <> '') or (Trim(AArtefact.Confidence) <> '') or
     AArtefact.Conditional or (LFileName <> '') or AUnresolvedSource then
  begin
    OpenTag('properties');
    if AArtefact.FileSize >= 0 then
    begin
      OpenTag('property', 'name="file:size"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="file:size">' + IntToStr(AArtefact.FileSize) + '</property>';
    end;
    if Trim(AArtefact.Origin) <> '' then
    begin
      OpenTag('property', 'name="net.developer-experts.dx-comply:origin"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="net.developer-experts.dx-comply:origin">' + EscapeXml(AArtefact.Origin) + '</property>';
    end;
    if Trim(AArtefact.Evidence) <> '' then
    begin
      OpenTag('property', 'name="net.developer-experts.dx-comply:evidence"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="net.developer-experts.dx-comply:evidence">' + EscapeXml(AArtefact.Evidence) + '</property>';
    end;
    if Trim(AArtefact.Confidence) <> '' then
    begin
      OpenTag('property', 'name="net.developer-experts.dx-comply:confidence"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="net.developer-experts.dx-comply:confidence">' + EscapeXml(AArtefact.Confidence) + '</property>';
    end;
    if AArtefact.Conditional then
    begin
      OpenTag('property', 'name="net.developer-experts.dx-comply:conditional"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="net.developer-experts.dx-comply:conditional">true</property>';
    end;
    if LFileName <> '' then
    begin
      AddLine('<property name="bsi:component:filename">' + EscapeXml(LFileName) + '</property>');
      AddLine('<property name="bsi:component:executable">' +
        BsiExecutableValue(AArtefact) + '</property>');
      AddLine('<property name="bsi:component:archive">' +
        EscapeXml(BsiArchiveValue(LFileName)) + '</property>');
      AddLine('<property name="bsi:component:structured">' +
        BsiStructuredValue(LFileName) + '</property>');
    end;
    if AUnresolvedSource then
      AddLine('<property name="' + cUnresolvedDependenciesProperty + '">' +
        cUnresolvedDependenciesValue + '</property>');
    CloseTag('properties');
  end;

  CloseTag('component');
end;

procedure TCycloneDxXmlWriter.BuildComponents(const AArtefacts: TArtefactList;
  const AMetadata: TSbomMetadata; const AGraph: TUsesDependencyGraph);
var
  I: Integer;
begin
  OpenTag('components');
  for I := 0 to AArtefacts.Count - 1 do
    BuildComponent(AArtefacts[I], I, AGraph.Status[I] = uusMissingSource);
  // Library rows from a component manifest. Element order is owned by
  // DX.Comply.ComponentManifest so this writer stays a thin hook.
  if AMetadata.ComponentManifestJson <> '' then
    AppendManifestLibrariesXml(FLines, AMetadata.ComponentManifestJson,
      AArtefacts, FIndentLevel);
  CloseTag('components');
end;

procedure TCycloneDxXmlWriter.BuildDependencies(const AArtefacts: TArtefactList;
  const AProjectBomRef: string; const AGraph: TUsesDependencyGraph);
var
  I: Integer;
  LGroup: Integer;
  LTargetIndex: Integer;
begin
  // Same shape as the JSON writer: project -> deliverable, and the
  // deliverable depends on runtime packages, external DLLs and linked units.
  OpenTag('dependencies');
  LTargetIndex := FindDeliverableTargetIndex(AArtefacts, AProjectBomRef);

  OpenTag('dependency', 'ref="' + EscapeXml(AProjectBomRef) + '"');
  if LTargetIndex >= 0 then
    AddLine('<dependency ref="comp-' + IntToStr(LTargetIndex) + '"/>')
  else if Assigned(AArtefacts) then
    for I := 0 to AArtefacts.Count - 1 do
      AddLine('<dependency ref="comp-' + IntToStr(I) + '"/>');
  CloseTag('dependency');

  if (LTargetIndex >= 0) and Assigned(AArtefacts) and (AArtefacts.Count > 1) then
  begin
    OpenTag('dependency', 'ref="comp-' + IntToStr(LTargetIndex) + '"');
    for LGroup := 0 to 3 do
      for I := 0 to AArtefacts.Count - 1 do
        if (I <> LTargetIndex) and
           (ArtefactDependencyGroup(AArtefacts[I]) = LGroup) then
          AddLine('<dependency ref="comp-' + IntToStr(I) + '"/>');
    CloseTag('dependency');
  end;

  // FIndentLevel is the child level of <dependencies>. The helper indents
  // from the dependencies element itself.
  WriteUsesDependenciesXml(FLines, FIndentLevel - 1, AGraph);
  CloseTag('dependencies');
end;

function TCycloneDxXmlWriter.Write(const AOutputPath: string;
  const AMetadata: TSbomMetadata;
  const AArtefacts: TArtefactList;
  const AProjectInfo: TProjectInfo): Boolean;
var
  LOutputDir: string;
  LGraph: TUsesDependencyGraph;
  LLibraries, LIncomplete, LComplete: TArray<string>;
  LGroups: TArray<TLibraryCompositionGroup>;
  LGroup: TLibraryCompositionGroup;
  LRef: string;
begin
  Result := False;
  if AOutputPath = '' then
    Exit;

  LOutputDir := TPath.GetDirectoryName(AOutputPath);
  if (LOutputDir <> '') and not TDirectory.Exists(LOutputDir) then
    TDirectory.CreateDirectory(LOutputDir);

  FLines := TStringList.Create;
  try
    FIndentLevel := 0;

    // XML declaration
    FLines.Add('<?xml version="1.0" encoding="UTF-8"?>');

    // Root element with namespace and serial number
    OpenTag('bom', 'xmlns="' + cNamespace + '" version="1" serialNumber="urn:uuid:' +
      GenerateUuid + '"');

    LGraph := BuildUsesDependencyGraph(AArtefacts);
    BuildMetadata(AMetadata, AProjectInfo);
    BuildComponents(AArtefacts, AMetadata, LGraph);
    if AMetadata.ComponentManifestJson <> '' then
      AppendManifestDependenciesXml(FLines, AMetadata.ComponentManifestJson,
        AArtefacts, AProjectInfo.ProjectName, FIndentLevel, LGraph)
    else
      BuildDependencies(AArtefacts, AProjectInfo.ProjectName, LGraph);

    if AMetadata.LibraryCompositions then
    begin
      LGroups := BuildLibraryCompositionGroups(AArtefacts, AProjectInfo.ProjectName,
        AMetadata.LibraryFilesComplete, AMetadata.LibraryRequiresDeclared);
      if Length(LGroups) > 0 then
      begin
        OpenTag('compositions');
        for LGroup in LGroups do
        begin
          if Length(LGroup.Refs) = 0 then
            Continue;
          OpenTag('composition');
          AddElement('aggregate', LGroup.Aggregate);
          OpenTag('dependencies');
          for LRef in LGroup.Refs do
            AddLine('<dependency ref="' + EscapeXml(LRef) + '"/>');
          CloseTag('dependencies');
          CloseTag('composition');
        end;
        CloseTag('compositions');
      end;
    end
    else
    begin
    LLibraries := ManifestLibraryBomRefs(AMetadata.ComponentManifestJson, AArtefacts);
    BuildCompositionRefLists(AProjectInfo.ProjectName, LGraph, LLibraries,
      LIncomplete, LComplete);
    if Length(LIncomplete) > 0 then
    begin
      OpenTag('compositions');
      OpenTag('composition');
      AddElement('aggregate', 'incomplete');
      OpenTag('dependencies');
      for LRef in LIncomplete do
        AddLine('<dependency ref="' + EscapeXml(LRef) + '"/>');
      CloseTag('dependencies');
      CloseTag('composition');
      if Length(LComplete) > 0 then
      begin
        OpenTag('composition');
        AddElement('aggregate', 'complete');
        OpenTag('dependencies');
        for LRef in LComplete do
          AddLine('<dependency ref="' + EscapeXml(LRef) + '"/>');
        CloseTag('dependencies');
        CloseTag('composition');
      end;
      CloseTag('compositions');
    end;
    end;

    CloseTag('bom');

    FLines.WriteBOM := False;
    FLines.SaveToFile(AOutputPath, TEncoding.UTF8);
    Result := True;
  finally
    FLines.Free;
    FLines := nil;
  end;
end;

function TCycloneDxXmlWriter.GetFormat: TSbomFormat;
begin
  Result := sfCycloneDxXml;
end;

function TCycloneDxXmlWriter.Validate(const AContent: string): Boolean;
var
  LMatch: TMatch;
begin
  Result := False;
  if Trim(AContent) = '' then
    Exit;

  // Check for XML declaration
  if not AContent.StartsWith('<?xml') then
    Exit;

  // Check for CycloneDX namespace
  if Pos(cNamespace, AContent) = 0 then
    Exit;

  // Check for <bom element
  if Pos('<bom', AContent) = 0 then
    Exit;

  // Check for serialNumber with urn:uuid:
  LMatch := TRegEx.Match(AContent, 'serialNumber="urn:uuid:[^"]+?"', [roIgnoreCase]);
  if not LMatch.Success then
    Exit;

  // Check for components section
  if Pos('<components', AContent) = 0 then
    Exit;

  // Check for metadata section
  if Pos('<metadata', AContent) = 0 then
    Exit;

  // Presence of the expected tags is not enough: metadata.properties before
  // tools, or component.purl before hashes, is invalid against bom-1.6.xsd.
  if Length(CycloneDxXmlSequenceErrors(AContent)) > 0 then
    Exit;

  Result := True;
end;

end.
