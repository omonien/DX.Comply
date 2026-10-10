/// <summary>
/// DX.Comply.CycloneDx.Writer
/// Generates CycloneDX 1.6 SBOM documents in JSON format.
/// </summary>
///
/// <remarks>
/// This unit provides TCycloneDxJsonWriter which generates CycloneDX 1.6 JSON SBOMs:
/// - Full metadata section with tool information
/// - Component list with hashes (SHA-256 and SHA-512 when the file could be opened)
/// - Dependency graph grouped by deliverable, runtime packages, external DLLs and linked units
/// - Direct uses edges between units whose Pascal source was read
/// - Schema validation support
///
/// CycloneDX 1.6 specification: https://cyclonedx.org/specification/overview/
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.CycloneDx.Writer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Generics.Collections,
  System.DateUtils,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Implementation of ISbomWriter for CycloneDX JSON format.
  /// </summary>
  TCycloneDxJsonWriter = class(TInterfacedObject, ISbomWriter)
  private
    const
      /// <summary>CycloneDX specification version.</summary>
      cSpecVersion = '1.6';
      /// <summary>Tool name.</summary>
      cToolName = 'DX.Comply';
  private
    function GenerateUuid: string;
    function BuildMetadata(const AMetadata: TSbomMetadata; const AProjectInfo: TProjectInfo): TJSONObject;
    function BuildProperties(const AProperties: TArray<TSbomProperty>): TJSONArray;
    function BuildComponent(const AArtefact: TArtefactInfo; const AIndex: Integer;
      AUnresolvedSource: Boolean): TJSONObject;
    function BuildDependencies(const AArtefacts: TArtefactList; const AProjectBomRef: string): TJSONArray;
  public
    // ISbomWriter
    function Write(const AOutputPath: string;
      const AMetadata: TSbomMetadata;
      const AArtefacts: TArtefactList;
      const AProjectInfo: TProjectInfo): Boolean;
    function GetFormat: TSbomFormat;
    function Validate(const AContent: string): Boolean;
  end;

implementation

uses
  DX.Comply.ComponentManifest,
  DX.Comply.DependencyGraph,
  DX.Comply.VersionInfo;

{ TCycloneDxJsonWriter }

function TCycloneDxJsonWriter.GenerateUuid: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := LowerCase(GUIDToString(LGuid));
  // Remove braces for CycloneDX format
  Result := Result.Substring(1, Result.Length - 2);
end;

function TCycloneDxJsonWriter.BuildProperties(
  const AProperties: TArray<TSbomProperty>): TJSONArray;
var
  LProperty: TSbomProperty;
  LPropertyObject: TJSONObject;
begin
  Result := TJSONArray.Create;
  for LProperty in AProperties do
  begin
    if Trim(LProperty.Name) = '' then
      Continue;

    LPropertyObject := TJSONObject.Create;
    LPropertyObject.AddPair('name', LProperty.Name);
    LPropertyObject.AddPair('value', LProperty.Value);
    Result.Add(LPropertyObject);
  end;
end;

function TCycloneDxJsonWriter.BuildMetadata(const AMetadata: TSbomMetadata;
  const AProjectInfo: TProjectInfo): TJSONObject;
var
  LMetadata, LComponent, LTool, LTools, LSupplier, LManufacture, LContact: TJSONObject;
  LToolArray, LSupplierUrls, LContacts: TJSONArray;
  LKind: string;
begin
  LMetadata := TJSONObject.Create;

  // Timestamp in UTC with a Z suffix (BSI TR-03183-2 section 5.2.1).
  LMetadata.AddPair('timestamp', FormatUtcTimestamp(AMetadata.Timestamp));

  // Component (the project being documented).
  // Prefer metadata overrides (CLI --product / --version) over values parsed
  // from the .dproj — issue #26.
  LComponent := TJSONObject.Create;
  LComponent.AddPair('type', 'application');
  if AMetadata.ProductName <> '' then
    LComponent.AddPair('name', AMetadata.ProductName)
  else
    LComponent.AddPair('name', AProjectInfo.ProjectName);
  if AMetadata.ProductVersion <> '' then
    LComponent.AddPair('version', AMetadata.ProductVersion)
  else if AProjectInfo.Version <> '' then
    LComponent.AddPair('version', AProjectInfo.Version);
  LComponent.AddPair('bom-ref', AProjectInfo.ProjectName);

  if AMetadata.Supplier <> '' then
  begin
    LSupplier := TJSONObject.Create;
    LSupplier.AddPair('name', AMetadata.Supplier);
    if AMetadata.SupplierUrl <> '' then
    begin
      LSupplierUrls := TJSONArray.Create;
      LSupplier.AddPair('url', LSupplierUrls);
      LSupplierUrls.Add(AMetadata.SupplierUrl);
    end;
    if IsBsiEmailAddress(Trim(AMetadata.Supplier)) then
    begin
      LContacts := TJSONArray.Create;
      LContact := TJSONObject.Create;
      LContact.AddPair('email', Trim(AMetadata.Supplier));
      LContacts.Add(LContact);
      LSupplier.AddPair('contact', LContacts);
    end;
    LComponent.AddPair('supplier', LSupplier);
  end;

  // Same classification as a manifest library. Empty writes nothing.
  // licences sit before properties, matching the component sequence.
  AddCycloneDxLicences(LComponent, AMetadata.Licence, '');

  if Length(AMetadata.ComponentProperties) > 0 then
    LComponent.AddPair('properties', BuildProperties(AMetadata.ComponentProperties));

  LMetadata.AddPair('component', LComponent);

  // CycloneDX 1.6 names the SBOM creator metadata.manufacturer. It is one
  // organizational entity, not an array. The contact is written only when
  // the caller supplied an email or an http(s) URL. The deprecated
  // manufacture element is not written.
  LKind := BsiCreatorKind(AMetadata.SbomCreator);
  if LKind <> '' then
  begin
    LManufacture := TJSONObject.Create;
    if LKind = 'email' then
    begin
      LContacts := TJSONArray.Create;
      LContact := TJSONObject.Create;
      LContact.AddPair('email', Trim(AMetadata.SbomCreator));
      LContacts.Add(LContact);
      LManufacture.AddPair('contact', LContacts);
    end
    else
    begin
      LSupplierUrls := TJSONArray.Create;
      LSupplierUrls.Add(Trim(AMetadata.SbomCreator));
      LManufacture.AddPair('url', LSupplierUrls);
    end;
    LMetadata.AddPair('manufacturer', LManufacture);
  end;

  if Length(AMetadata.Properties) > 0 then
    LMetadata.AddPair('properties', BuildProperties(AMetadata.Properties));

  // Tool information (CycloneDX 1.6 tools.components format)
  LTool := TJSONObject.Create;
  LTool.AddPair('type', 'application');
  LTool.AddPair('author', 'Olaf Monien');
  LTool.AddPair('name', cToolName);
  LTool.AddPair('version', ResolveDxComplyToolVersion(AMetadata.ToolVersion));

  LToolArray := TJSONArray.Create;
  LToolArray.Add(LTool);

  LTools := TJSONObject.Create;
  LTools.AddPair('components', LToolArray);
  LMetadata.AddPair('tools', LTools);

  Result := LMetadata;
end;

function TCycloneDxJsonWriter.BuildComponent(const AArtefact: TArtefactInfo;
  const AIndex: Integer; AUnresolvedSource: Boolean): TJSONObject;
var
  LComponent, LHashes, LRef, LRefHash: TJSONObject;
  LHashArray, LProperties, LRefs, LRefHashes: TJSONArray;
  LProp: TJSONObject;
  LFileName: string;

  procedure AddProperty(const AName, AValue: string);
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('name', AName);
    LProp.AddPair('value', AValue);
    LProperties.Add(LProp);
  end;

begin
  LComponent := TJSONObject.Create;

  // Component type
  if AArtefact.ArtefactType = 'application' then
    LComponent.AddPair('type', 'application')
  else if (AArtefact.ArtefactType = 'library') or
    (AArtefact.ArtefactType = 'unit-evidence') or
    (AArtefact.ArtefactType = 'package') or
    (AArtefact.ArtefactType = 'runtime-package') or
    (AArtefact.ArtefactType = 'external-reference') then
    LComponent.AddPair('type', 'library')
  else
    LComponent.AddPair('type', 'file');

  // Name (filename without path)
  LComponent.AddPair('name', TPath.GetFileName(AArtefact.RelativePath));

  // Version (use hash prefix as pseudo-version for files)
  if AArtefact.Hash <> '' then
    LComponent.AddPair('version', Copy(AArtefact.Hash, 1, 12));

  // BOM reference
  LComponent.AddPair('bom-ref', 'comp-' + IntToStr(AIndex));

  // File path
  LComponent.AddPair('purl', 'file:' + AArtefact.RelativePath);

  // Hashes. SHA-256 stays first. SHA-512 is added when the file was hashed.
  if (AArtefact.Hash <> '') or (AArtefact.HashSha512 <> '') then
  begin
    LHashArray := TJSONArray.Create;

    if AArtefact.Hash <> '' then
    begin
      LHashes := TJSONObject.Create;
      LHashes.AddPair('alg', 'SHA-256');
      LHashes.AddPair('content', LowerCase(AArtefact.Hash));
      LHashArray.Add(LHashes);
    end;
    if AArtefact.HashSha512 <> '' then
    begin
      LHashes := TJSONObject.Create;
      LHashes.AddPair('alg', 'SHA-512');
      LHashes.AddPair('content', LowerCase(AArtefact.HashSha512));
      LHashArray.Add(LHashes);
    end;

    LComponent.AddPair('hashes', LHashArray);
  end;

  // TR-03183-2 maps the deployable SHA-512 to externalReferences type
  // distribution. bom-1.6 requires a url, and no download URL is known, so
  // the url is the same file: locator already written as purl. The reference
  // is written for a hashed executable or archive. Unit evidence is not a
  // deployable file. The component hashes above stay as well.
  if (AArtefact.HashSha512 <> '') and
     (IsBsiExecutableArtefact(AArtefact) or
      IsBsiArchiveFileName(BsiComponentFileName(AArtefact.RelativePath))) then
  begin
    LRefs := TJSONArray.Create;
    LRef := TJSONObject.Create;
    LRefHashes := TJSONArray.Create;
    LRefHash := TJSONObject.Create;
    LRef.AddPair('type', 'distribution');
    LRef.AddPair('url', 'file:' + AArtefact.RelativePath);
    LRefHash.AddPair('alg', 'SHA-512');
    LRefHash.AddPair('content', LowerCase(AArtefact.HashSha512));
    LRefHashes.Add(LRefHash);
    LRef.AddPair('hashes', LRefHashes);
    LRefs.Add(LRef);
    LComponent.AddPair('externalReferences', LRefs);
  end;

  // Properties
  LProperties := TJSONArray.Create;

  if AArtefact.FileSize >= 0 then
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('name', 'file:size');
    LProp.AddPair('value', IntToStr(AArtefact.FileSize));
    LProperties.Add(LProp);
  end;
  if Trim(AArtefact.Origin) <> '' then
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('name', 'net.developer-experts.dx-comply:origin');
    LProp.AddPair('value', AArtefact.Origin);
    LProperties.Add(LProp);
  end;
  if Trim(AArtefact.Evidence) <> '' then
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('name', 'net.developer-experts.dx-comply:evidence');
    LProp.AddPair('value', AArtefact.Evidence);
    LProperties.Add(LProp);
  end;
  if Trim(AArtefact.Confidence) <> '' then
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('name', 'net.developer-experts.dx-comply:confidence');
    LProp.AddPair('value', AArtefact.Confidence);
    LProperties.Add(LProp);
  end;
  if AArtefact.Conditional then
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('name', 'net.developer-experts.dx-comply:conditional');
    LProp.AddPair('value', 'true');
    LProperties.Add(LProp);
  end;

  // BSI TR-03183-2 file properties. Omitted when there is no file name,
  // which is how a logical component is left without these fields.
  LFileName := BsiComponentFileName(AArtefact.RelativePath);
  if LFileName <> '' then
  begin
    AddProperty('bsi:component:filename', LFileName);
    AddProperty('bsi:component:executable', BsiExecutableValue(AArtefact));
    AddProperty('bsi:component:archive', BsiArchiveValue(LFileName));
    AddProperty('bsi:component:structured', BsiStructuredValue(LFileName));
  end;
  if AUnresolvedSource then
    AddProperty(cUnresolvedDependenciesProperty, cUnresolvedDependenciesValue);

  if LProperties.Count > 0 then
    LComponent.AddPair('properties', LProperties)
  else
    LProperties.Free;

  Result := LComponent;
end;

function TCycloneDxJsonWriter.BuildDependencies(const AArtefacts: TArtefactList;
  const AProjectBomRef: string): TJSONArray;
var
  LDependsOn: TJSONArray;
  LDep: TJSONObject;
  LTargetIndex: Integer;
  LGroup: Integer;
  I: Integer;
begin
  Result := TJSONArray.Create;

  // Project -> deliverable (exe/dll/bpl). When the output has no deliverable,
  // keep a single edge list so components are not dropped from the graph.
  LTargetIndex := FindDeliverableTargetIndex(AArtefacts, AProjectBomRef);

  LDep := TJSONObject.Create;
  LDep.AddPair('ref', AProjectBomRef);
  LDependsOn := TJSONArray.Create;
  if LTargetIndex >= 0 then
    LDependsOn.Add('comp-' + IntToStr(LTargetIndex))
  else if Assigned(AArtefacts) then
    for I := 0 to AArtefacts.Count - 1 do
      LDependsOn.Add('comp-' + IntToStr(I));
  LDep.AddPair('dependsOn', LDependsOn);
  Result.Add(LDep);

  if (LTargetIndex < 0) or not Assigned(AArtefacts) then
    Exit;

  // Deliverable -> runtime packages, then external DLLs, then linked
  // units, then any other output. Keeping each category together is the
  // grouped graph from issue #42.
  LDependsOn := TJSONArray.Create;
  for LGroup := 0 to 3 do
    for I := 0 to AArtefacts.Count - 1 do
      if (I <> LTargetIndex) and
         (ArtefactDependencyGroup(AArtefacts[I]) = LGroup) then
        LDependsOn.Add('comp-' + IntToStr(I));

  if LDependsOn.Count = 0 then
  begin
    LDependsOn.Free;
    Exit;
  end;

  LDep := TJSONObject.Create;
  LDep.AddPair('ref', 'comp-' + IntToStr(LTargetIndex));
  LDep.AddPair('dependsOn', LDependsOn);
  Result.Add(LDep);
end;

function TCycloneDxJsonWriter.Write(const AOutputPath: string;
  const AMetadata: TSbomMetadata;
  const AArtefacts: TArtefactList;
  const AProjectInfo: TProjectInfo): Boolean;
var
  LRoot, LMetadataObj: TJSONObject;
  LComponents: TJSONArray;
  LDependencies: TJSONArray;
  LOutput: TStringList;
  LGraph: TUsesDependencyGraph;
  I: Integer;
begin
  Result := False;
  if AOutputPath = '' then
    Exit;

  // Ensure output directory exists
  var LOutputDir := TPath.GetDirectoryName(AOutputPath);
  if (LOutputDir <> '') and not TDirectory.Exists(LOutputDir) then
    TDirectory.CreateDirectory(LOutputDir);

  LRoot := TJSONObject.Create;
  try
    // CycloneDX version
    LRoot.AddPair('$schema', 'http://cyclonedx.org/schema/bom-1.6.schema.json');
    LRoot.AddPair('bomFormat', 'CycloneDX');
    LRoot.AddPair('specVersion', cSpecVersion);
    LRoot.AddPair('serialNumber', 'urn:uuid:' + GenerateUuid);

    // Version (always 1 for new SBOMs)
    LRoot.AddPair('version', TJSONNumber.Create(1));

    // Metadata
    LMetadataObj := BuildMetadata(AMetadata, AProjectInfo);
    LRoot.AddPair('metadata', LMetadataObj);

    // Uses edges are built once. Component properties and compositions share
    // that result, so an uncached .pas is not parsed twice.
    LGraph := BuildUsesDependencyGraph(AArtefacts);

    // Components
    LComponents := TJSONArray.Create;
    for I := 0 to AArtefacts.Count - 1 do
      LComponents.Add(BuildComponent(AArtefacts[I], I,
        LGraph.Status[I] = uusMissingSource));
    LRoot.AddPair('components', LComponents);

    // Dependencies. A component manifest groups matched units under one
    // library and links those units from that library. Uses edges are added
    // after that rewrite so they are not folded into the program.
    LDependencies := BuildDependencies(AArtefacts, AProjectInfo.ProjectName);
    if AMetadata.ComponentManifestJson <> '' then
      ApplyManifestCycloneDxJson(AMetadata.ComponentManifestJson, AArtefacts,
        LComponents, LDependencies, AProjectInfo.ProjectName);
    AppendUsesDependenciesJson(LDependencies, LGraph);
    LRoot.AddPair('dependencies', LDependencies);

    // Completeness is per component. A unit whose uses names all resolve is
    // complete. The program, a runtime package, a DLL, and a unit with no
    // source stay incomplete. See docs/BSI-TR-03183-2.md.
    WriteCompositionsJson(LRoot, AProjectInfo.ProjectName, LGraph,
      ManifestLibraryBomRefs(AMetadata.ComponentManifestJson, AArtefacts));

    // Write to file
    LOutput := TStringList.Create;
    try
      LOutput.Text := LRoot.Format(2);  // Pretty print with 2-space indent
      LOutput.SaveToFile(AOutputPath, TEncoding.UTF8);
      Result := True;
    finally
      LOutput.Free;
    end;
  finally
    LRoot.Free;
  end;
end;

function TCycloneDxJsonWriter.GetFormat: TSbomFormat;
begin
  Result := sfCycloneDxJson;
end;

function TCycloneDxJsonWriter.Validate(const AContent: string): Boolean;
var
  LJson: TJSONObject;
  LSerialNumber: string;
begin
  Result := False;
  if Trim(AContent) = '' then
    Exit;
  try
    LJson := TJSONObject.ParseJSONValue(AContent) as TJSONObject;
    try
      if not Assigned(LJson) then
        Exit;

      // bomFormat must be 'CycloneDX'
      if (LJson.GetValue('bomFormat') = nil) or
         (LJson.GetValue<string>('bomFormat') <> 'CycloneDX') then
        Exit;

      // specVersion must be present
      if LJson.GetValue('specVersion') = nil then
        Exit;

      // serialNumber must be present and start with 'urn:uuid:'
      if LJson.GetValue('serialNumber') <> nil then
      begin
        LSerialNumber := LJson.GetValue<string>('serialNumber');
        if not LSerialNumber.StartsWith('urn:uuid:') then
          Exit;
      end;

      // version must be a number
      if LJson.GetValue('version') = nil then
        Exit;

      // components array must be present
      if not (LJson.GetValue('components') is TJSONArray) then
        Exit;

      // metadata object must be present
      if not (LJson.GetValue('metadata') is TJSONObject) then
        Exit;

      Result := True;
    finally
      LJson.Free;
    end;
  except
    Result := False;
  end;
end;

end.
