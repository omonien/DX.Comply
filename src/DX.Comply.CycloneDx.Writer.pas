/// <summary>
/// DX.Comply.CycloneDx.Writer
/// Generates CycloneDX 1.5 SBOM documents in JSON format.
/// </summary>
///
/// <remarks>
/// This unit provides TCycloneDxJsonWriter which generates CycloneDX 1.5 JSON SBOMs:
/// - Full metadata section with tool information
/// - Component list with hashes (SHA-256)
/// - Basic dependency graph
/// - Schema validation support
///
/// CycloneDX 1.5 specification: https://cyclonedx.org/specification/overview/
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
      cSpecVersion = '1.5';
      /// <summary>Tool name.</summary>
      cToolName = 'DX.Comply';
      /// <summary>Tool version.</summary>
      cToolVersion = '1.0.0';
  private
    function GenerateUuid: string;
    function BuildMetadata(const AMetadata: TSbomMetadata; const AProjectInfo: TProjectInfo): TJSONObject;
    function BuildProperties(const AProperties: TArray<TSbomProperty>): TJSONArray;
    function BuildComponent(const AArtefact: TArtefactInfo; const AIndex: Integer): TJSONObject;
    function BuildDependencies(const AArtefacts: TArtefactList; const AProjectBomRef: string): TJSONArray;
    function EscapeJsonString(const AValue: string): string;
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

{ TCycloneDxJsonWriter }

function TCycloneDxJsonWriter.GenerateUuid: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := GUIDToString(LGuid);
  // Remove braces for CycloneDX format
  Result := Result.Substring(1, Result.Length - 2);
end;

function TCycloneDxJsonWriter.EscapeJsonString(const AValue: string): string;
begin
  Result := AValue;
  Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
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
    LPropertyObject.AddPair('name', EscapeJsonString(LProperty.Name));
    LPropertyObject.AddPair('value', EscapeJsonString(LProperty.Value));
    Result.Add(LPropertyObject);
  end;
end;

function TCycloneDxJsonWriter.BuildMetadata(const AMetadata: TSbomMetadata;
  const AProjectInfo: TProjectInfo): TJSONObject;
var
  LMetadata, LComponent, LTool, LTools, LSupplier: TJSONObject;
  LToolArray: TJSONArray;
begin
  LMetadata := TJSONObject.Create;

  // Timestamp
  if AMetadata.Timestamp <> '' then
    LMetadata.AddPair('timestamp', AMetadata.Timestamp)
  else
    LMetadata.AddPair('timestamp', DateToISO8601(Now, False));

  // Component (the project being documented)
  LComponent := TJSONObject.Create;
  LComponent.AddPair('type', 'application');
  LComponent.AddPair('name', EscapeJsonString(AProjectInfo.ProjectName));
  if AProjectInfo.Version <> '' then
    LComponent.AddPair('version', EscapeJsonString(AProjectInfo.Version));
  LComponent.AddPair('bom-ref', EscapeJsonString(AProjectInfo.ProjectName));

  if AMetadata.Supplier <> '' then
  begin
    LSupplier := TJSONObject.Create;
    LSupplier.AddPair('name', EscapeJsonString(AMetadata.Supplier));
    LComponent.AddPair('supplier', LSupplier);
  end;

  if Length(AMetadata.ComponentProperties) > 0 then
    LComponent.AddPair('properties', BuildProperties(AMetadata.ComponentProperties));

  LMetadata.AddPair('component', LComponent);

  if Length(AMetadata.Properties) > 0 then
    LMetadata.AddPair('properties', BuildProperties(AMetadata.Properties));

  // Tool information
  LTool := TJSONObject.Create;
  LTool.AddPair('vendor', 'Olaf Monien');
  LTool.AddPair('name', cToolName);
  LTool.AddPair('version', cToolVersion);

  LToolArray := TJSONArray.Create;
  LToolArray.Add(LTool);

  LTools := TJSONObject.Create;
  LTools.AddPair('components', LToolArray);
  LMetadata.AddPair('tools', LTools);

  Result := LMetadata;
end;

function TCycloneDxJsonWriter.BuildComponent(const AArtefact: TArtefactInfo;
  const AIndex: Integer): TJSONObject;
var
  LComponent, LHashes: TJSONObject;
  LHashArray, LProperties: TJSONArray;
  LProp: TJSONObject;
begin
  LComponent := TJSONObject.Create;

  // Component type
  if AArtefact.ArtefactType = 'application' then
    LComponent.AddPair('type', 'application')
  else if (AArtefact.ArtefactType = 'library') or
    (AArtefact.ArtefactType = 'unit-evidence') or
    (AArtefact.ArtefactType = 'package') then
    LComponent.AddPair('type', 'library')
  else
    LComponent.AddPair('type', 'file');

  // Name (filename without path)
  LComponent.AddPair('name', EscapeJsonString(TPath.GetFileName(AArtefact.RelativePath)));

  // Version (use hash prefix as pseudo-version for files)
  if AArtefact.Hash <> '' then
    LComponent.AddPair('version', Copy(AArtefact.Hash, 1, 12));

  // BOM reference
  LComponent.AddPair('bom-ref', 'comp-' + IntToStr(AIndex));

  // File path
  LComponent.AddPair('purl', 'file:' + EscapeJsonString(AArtefact.RelativePath));

  // Hashes
  if AArtefact.Hash <> '' then
  begin
    LHashArray := TJSONArray.Create;

    LHashes := TJSONObject.Create;
    LHashes.AddPair('alg', 'SHA-256');
    LHashes.AddPair('content', LowerCase(AArtefact.Hash));
    LHashArray.Add(LHashes);

    LComponent.AddPair('hashes', LHashArray);
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
    LProp.AddPair('value', EscapeJsonString(AArtefact.Origin));
    LProperties.Add(LProp);
  end;
  if Trim(AArtefact.Evidence) <> '' then
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('name', 'net.developer-experts.dx-comply:evidence');
    LProp.AddPair('value', EscapeJsonString(AArtefact.Evidence));
    LProperties.Add(LProp);
  end;
  if Trim(AArtefact.Confidence) <> '' then
  begin
    LProp := TJSONObject.Create;
    LProp.AddPair('name', 'net.developer-experts.dx-comply:confidence');
    LProp.AddPair('value', EscapeJsonString(AArtefact.Confidence));
    LProperties.Add(LProp);
  end;

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
  I: Integer;
begin
  Result := TJSONArray.Create;

  // Root dependency (project depends on all components)
  LDep := TJSONObject.Create;
  LDep.AddPair('ref', EscapeJsonString(AProjectBomRef));

  LDependsOn := TJSONArray.Create;
  for I := 0 to AArtefacts.Count - 1 do
    LDependsOn.Add('comp-' + IntToStr(I));

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
    LRoot.AddPair('$schema', 'https://cyclonedx.org/schema/bom-1.5.schema.json');
    LRoot.AddPair('bomFormat', 'CycloneDX');
    LRoot.AddPair('specVersion', cSpecVersion);
    LRoot.AddPair('serialNumber', 'urn:uuid:' + GenerateUuid);

    // Version (always 1 for new SBOMs)
    LRoot.AddPair('version', TJSONNumber.Create(1));

    // Metadata
    LMetadataObj := BuildMetadata(AMetadata, AProjectInfo);
    LRoot.AddPair('metadata', LMetadataObj);

    // Components
    LComponents := TJSONArray.Create;
    for I := 0 to AArtefacts.Count - 1 do
      LComponents.Add(BuildComponent(AArtefacts[I], I));
    LRoot.AddPair('components', LComponents);

    // Dependencies
    LDependencies := BuildDependencies(AArtefacts, AProjectInfo.ProjectName);
    LRoot.AddPair('dependencies', LDependencies);

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
