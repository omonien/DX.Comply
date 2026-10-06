/// <summary>
/// DX.Comply.Tests.CycloneDx.Writer
/// DUnitX tests for TCycloneDxJsonWriter.
/// </summary>
///
/// <remarks>
/// Verifies CycloneDX 1.5 JSON output: required top-level fields,
/// component entries, hash embedding, metadata, dependency section,
/// serial-number uniqueness, validation logic, and edge cases such as
/// supplier names that contain characters requiring JSON escaping.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.CycloneDx.Writer;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Winapi.Windows,
  DUnitX.TestFramework,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// DUnitX test fixture for TCycloneDxJsonWriter.
  /// </summary>
  [TestFixture]
  TCycloneDxWriterTests = class
  private
    FWriter: ISbomWriter;
    FOutputFile: string;
    FArtefacts: TArtefactList;
    FMetadata: TSbomMetadata;
    FProjectInfo: TProjectInfo;
    /// <summary>Loads FOutputFile content, parses it as JSON and returns the root object. Caller owns the result.</summary>
    function LoadOutputJson: TJSONObject;
    /// <summary>Builds a minimal TArtefactInfo for use in tests.</summary>
    function MakeArtefact(const ARelativePath, AArtefactType, AHash: string;
      AFileSize: Int64): TArtefactInfo;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    /// <summary>GetFormat must return sfCycloneDxJson.</summary>
    [Test]
    procedure GetFormat_ReturnsCycloneDxJson;

    /// <summary>Writing with an empty artefact list must produce a file on disk.</summary>
    [Test]
    procedure Write_EmptyArtefacts_CreatesValidFile;

    /// <summary>Top-level required CycloneDX fields must be present.</summary>
    [Test]
    procedure Write_EmptyArtefacts_HasRequiredFields;

    /// <summary>A supplied artefact must appear in the components array.</summary>
    [Test]
    procedure Write_WithArtefact_ComponentInOutput;

    /// <summary>An artefact hash must be surfaced as an SHA-256 entry in the component hashes array.</summary>
    [Test]
    procedure Write_ComponentHasHashEntry;

    /// <summary>An artefact of type 'application' must produce type='application' in the component.</summary>
    [Test]
    procedure Write_ComponentType_Application;

    /// <summary>An artefact of type 'library' must produce type='library' in the component.</summary>
    [Test]
    procedure Write_ComponentType_Library;

    /// <summary>An artefact with an unrecognised type must produce type='file'.</summary>
    [Test]
    procedure Write_ComponentType_File;

    /// <summary>metadata.timestamp must be present in the output JSON.</summary>
    [Test]
    procedure Write_MetadataContainsTimestamp;

    /// <summary>metadata.tools must be present in the output JSON.</summary>
    [Test]
    procedure Write_MetadataContainsToolInfo;

    /// <summary>DX.Comply metadata properties must be written to metadata.properties and metadata.component.properties.</summary>
    [Test]
    procedure Write_MetadataContainsDxComplyProperties;

    /// <summary>A dependencies array must be present in the output JSON.</summary>
    [Test]
    procedure Write_DependenciesSection_Exists;

    /// <summary>
    /// With a deliverable, a runtime package and an external DLL, the
    /// project and the deliverable must both be dependsOn parents.
    /// Issue #42.
    /// </summary>
    [Test]
    procedure Write_Dependencies_GroupedWhenPackagesAndExternalRefsPresent;

    /// <summary>
    /// A package output must be the deliverable. A runtime package of
    /// the same extension must stay a dependency of that deliverable.
    /// </summary>
    [Test]
    procedure Write_Dependencies_PackageTargetPreferredOverRuntimePackage;

    /// <summary>
    /// Without an exe, dll or bpl deliverable the project keeps a direct
    /// edge to every component.
    /// </summary>
    [Test]
    procedure Write_Dependencies_WithoutDeliverable_ProjectDependsOnAll;

    /// <summary>
    /// A source-scanned DLL with no file on disk must keep evidence,
    /// confidence and the conditional property. Issue #45.
    /// </summary>
    [Test]
    procedure Write_ExternalDll_MissingFile_KeepsEvidenceAndConditional;

    /// <summary>The output file must contain valid parseable JSON.</summary>
    [Test]
    procedure Write_OutputIsValidJson;

    /// <summary>Each call to Write must produce a unique serialNumber.</summary>
    [Test]
    procedure Write_SerialNumber_UniquePerCall;

    /// <summary>Validate must return True for a minimal valid CycloneDX JSON string.</summary>
    [Test]
    procedure Validate_ValidCycloneDxJson_ReturnsTrue;

    /// <summary>Validate must return False for non-JSON input.</summary>
    [Test]
    procedure Validate_InvalidJson_ReturnsFalse;

    /// <summary>Validate must return False when bomFormat is absent.</summary>
    [Test]
    procedure Validate_MissingBomFormat_ReturnsFalse;

    /// <summary>Write must complete without raising when supplier contains a backslash.</summary>
    [Test]
    procedure Write_FileWithSpecialChars_NoException;

    /// <summary>CLI --product override (Metadata.ProductName) must appear in metadata.component.name.</summary>
    [Test]
    procedure Write_ProductOverride_AppearsInComponentName;

    /// <summary>CLI --version override (Metadata.ProductVersion) must appear in metadata.component.version.</summary>
    [Test]
    procedure Write_VersionOverride_AppearsInComponentVersion;
  end;

implementation

{ TCycloneDxWriterTests }

procedure TCycloneDxWriterTests.Setup;
begin
  FWriter := TCycloneDxJsonWriter.Create;

  FOutputFile := TPath.Combine(TPath.GetTempPath,
    'dx_comply_sbom_' + IntToStr(GetTickCount) + '.json');

  FArtefacts := TArtefactList.Create;

  FMetadata.ProductName    := 'TestApp';
  FMetadata.ProductVersion := '1.0.0';
  FMetadata.Supplier       := 'Test Supplier';
  FMetadata.Timestamp      := '2026-01-01T00:00:00';
  FMetadata.ToolName       := 'DX.Comply';
  FMetadata.ToolVersion    := '1.0.0';

  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'TestApp';
  FProjectInfo.Version     := '1.0.0';
  FProjectInfo.ProjectDir  := TPath.GetTempPath;
  FProjectInfo.OutputDir   := TPath.GetTempPath;
end;

procedure TCycloneDxWriterTests.TearDown;
begin
  if TFile.Exists(FOutputFile) then
    TFile.Delete(FOutputFile);
  FArtefacts.Free;
  FProjectInfo.Free;
  FWriter := nil;
end;

function TCycloneDxWriterTests.LoadOutputJson: TJSONObject;
var
  LContent: string;
begin
  LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  Result := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
end;

function TCycloneDxWriterTests.MakeArtefact(const ARelativePath, AArtefactType,
  AHash: string; AFileSize: Int64): TArtefactInfo;
begin
  Result := Default(TArtefactInfo);
  Result.FilePath     := TPath.Combine(TPath.GetTempPath, ARelativePath);
  Result.RelativePath := ARelativePath;
  Result.ArtefactType := AArtefactType;
  Result.Hash         := AHash;
  Result.FileSize     := AFileSize;
end;

// ---- Format -----------------------------------------------------------------

procedure TCycloneDxWriterTests.GetFormat_ReturnsCycloneDxJson;
begin
  Assert.AreEqual(Ord(sfCycloneDxJson), Ord(FWriter.GetFormat),
    'GetFormat must return sfCycloneDxJson');
end;

// ---- Write — file creation --------------------------------------------------

procedure TCycloneDxWriterTests.Write_EmptyArtefacts_CreatesValidFile;
var
  LResult: Boolean;
begin
  LResult := FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  Assert.IsTrue(LResult, 'Write must return True on success');
  Assert.IsTrue(TFile.Exists(FOutputFile), 'Output file must exist after Write');
end;

procedure TCycloneDxWriterTests.Write_EmptyArtefacts_HasRequiredFields;
var
  LJson: TJSONObject;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson, 'Output must be parseable JSON');
  try
    Assert.AreEqual('CycloneDX', LJson.GetValue<string>('bomFormat'),
      'bomFormat must be CycloneDX');
    Assert.AreEqual('1.5', LJson.GetValue<string>('specVersion'),
      'specVersion must be 1.5');
    Assert.IsNotNull(LJson.GetValue('components'),
      'components array must be present');
    Assert.IsNotNull(LJson.GetValue('metadata'),
      'metadata object must be present');
    Assert.IsTrue(LJson.GetValue<string>('serialNumber').StartsWith('urn:uuid:'),
      'serialNumber must start with urn:uuid:');
  finally
    LJson.Free;
  end;
end;

// ---- Write — component contents ---------------------------------------------

procedure TCycloneDxWriterTests.Write_WithArtefact_ComponentInOutput;
var
  LJson: TJSONObject;
  LComponents: TJSONArray;
begin
  FArtefacts.Add(MakeArtefact('test.exe', 'application', 'abcd1234ef', 1024));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    Assert.IsNotNull(LComponents, 'components array must be present');
    Assert.IsTrue(LComponents.Count >= 1, 'components array must contain at least one entry');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_ComponentHasHashEntry;
var
  LJson: TJSONObject;
  LComponents: TJSONArray;
  LComponent: TJSONObject;
  LHashes: TJSONArray;
  LHashObj: TJSONObject;
  LAlg: string;
begin
  FArtefacts.Add(MakeArtefact('test.exe', 'application', 'deadbeefcafe1234', 512));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    LComponent  := LComponents.Items[0] as TJSONObject;
    LHashes     := LComponent.GetValue('hashes') as TJSONArray;
    Assert.IsNotNull(LHashes, 'Component with hash must have a hashes array');
    Assert.IsTrue(LHashes.Count > 0, 'hashes array must not be empty');
    LHashObj := LHashes.Items[0] as TJSONObject;
    LAlg     := LHashObj.GetValue<string>('alg');
    Assert.AreEqual('SHA-256', LAlg, 'Hash algorithm must be SHA-256');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_ComponentType_Application;
var
  LJson: TJSONObject;
  LComponents: TJSONArray;
  LComponent: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('app.exe', 'application', '', 0));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    LComponent  := LComponents.Items[0] as TJSONObject;
    Assert.AreEqual('application', LComponent.GetValue<string>('type'),
      'application artefact type must map to type=application');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_ComponentType_Library;
var
  LJson: TJSONObject;
  LComponents: TJSONArray;
  LComponent: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('lib.dll', 'library', '', 0));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    LComponent  := LComponents.Items[0] as TJSONObject;
    Assert.AreEqual('library', LComponent.GetValue<string>('type'),
      'library artefact type must map to type=library');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_ComponentType_File;
var
  LJson: TJSONObject;
  LComponents: TJSONArray;
  LComponent: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('data.xyz', 'unknown', '', 0));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    LComponent  := LComponents.Items[0] as TJSONObject;
    Assert.AreEqual('file', LComponent.GetValue<string>('type'),
      'unknown artefact type must map to type=file');
  finally
    LJson.Free;
  end;
end;

// ---- Write — metadata -------------------------------------------------------

procedure TCycloneDxWriterTests.Write_MetadataContainsTimestamp;
var
  LJson, LMeta: TJSONObject;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LMeta := LJson.GetValue('metadata') as TJSONObject;
    Assert.IsNotNull(LMeta, 'metadata object must be present');
    Assert.IsNotNull(LMeta.GetValue('timestamp'),
      'metadata.timestamp must be present');
    // CycloneDX keeps the supplied timestamp, including offset form.
    // SPDX is the format that must be rewritten to UTC Z (issue #40).
    Assert.AreEqual('2026-01-01T00:00:00', LMeta.GetValue<string>('timestamp'),
      'CycloneDX must pass metadata.timestamp through unchanged');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_MetadataContainsToolInfo;
var
  LJson, LMeta: TJSONObject;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LMeta := LJson.GetValue('metadata') as TJSONObject;
    Assert.IsNotNull(LMeta.GetValue('tools'),
      'metadata.tools must be present');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_MetadataContainsDxComplyProperties;
var
  LBomProperties: TJSONArray;
  LComponent: TJSONObject;
  LJson: TJSONObject;
  LMeta: TJSONObject;
  LProperties: TJSONArray;
begin
  SetLength(FMetadata.Properties, 2);
  FMetadata.Properties[0] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:document.profile', 'cra-compliance-assessment');
  FMetadata.Properties[1] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:assessment.warning-count', '0');
  SetLength(FMetadata.ComponentProperties, 1);
  FMetadata.ComponentProperties[0] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:build.configuration', 'Release');

  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LMeta := LJson.GetValue('metadata') as TJSONObject;
    LBomProperties := LMeta.GetValue('properties') as TJSONArray;
    LComponent := LMeta.GetValue('component') as TJSONObject;
    LProperties := LComponent.GetValue('properties') as TJSONArray;

    Assert.IsNotNull(LBomProperties,
      'metadata.properties must be present when BOM metadata properties are provided');
    Assert.IsNotNull(LProperties,
      'metadata.component.properties must be present when component properties are provided');
    Assert.AreEqual('net.developer-experts.dx-comply:document.profile',
      (LBomProperties.Items[0] as TJSONObject).GetValue<string>('name'));
    Assert.AreEqual('cra-compliance-assessment',
      (LBomProperties.Items[0] as TJSONObject).GetValue<string>('value'));
    Assert.AreEqual('net.developer-experts.dx-comply:assessment.warning-count',
      (LBomProperties.Items[1] as TJSONObject).GetValue<string>('name'));
    Assert.AreEqual('net.developer-experts.dx-comply:build.configuration',
      (LProperties.Items[0] as TJSONObject).GetValue<string>('name'));
  finally
    LJson.Free;
  end;
end;

// ---- Write — dependencies ---------------------------------------------------

procedure TCycloneDxWriterTests.Write_DependenciesSection_Exists;
var
  LJson: TJSONObject;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    Assert.IsNotNull(LJson.GetValue('dependencies'),
      'dependencies array must be present in the output');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_Dependencies_GroupedWhenPackagesAndExternalRefsPresent;
var
  LJson: TJSONObject;
  LDeps: TJSONArray;
  LDependsOn: TJSONArray;
  LDep: TJSONObject;
  I: Integer;
  LParents: Integer;
  LProjectDepends: TJSONArray;
  LTargetDepends: TJSONArray;

  function DependsOnContains(const ADepends: TJSONArray; const ARef: string): Boolean;
  var
    J: Integer;
  begin
    Result := False;
    if not Assigned(ADepends) then
      Exit;
    for J := 0 to ADepends.Count - 1 do
      if ADepends.Items[J].Value = ARef then
        Exit(True);
  end;

begin
  FArtefacts.Add(MakeArtefact('TestApp.exe', 'application', '', 1024));
  FArtefacts.Add(MakeArtefact('rtl.bpl', 'runtime-package', '', -1));
  FArtefacts.Add(MakeArtefact('vendor.dll', 'external-reference', '', -1));
  FArtefacts.Add(MakeArtefact('System.dcu', 'unit-evidence', '', 100));

  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo),
    'Write must succeed');

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LDeps := LJson.GetValue('dependencies') as TJSONArray;
    Assert.IsNotNull(LDeps, 'dependencies array must be present');

    LParents := 0;
    LProjectDepends := nil;
    LTargetDepends := nil;
    for I := 0 to LDeps.Count - 1 do
    begin
      LDep := LDeps.Items[I] as TJSONObject;
      LDependsOn := LDep.GetValue('dependsOn') as TJSONArray;
      if Assigned(LDependsOn) and (LDependsOn.Count > 0) then
        Inc(LParents);
      if LDep.GetValue<string>('ref') = FProjectInfo.ProjectName then
        LProjectDepends := LDependsOn
      else if LDep.GetValue<string>('ref') = 'comp-0' then
        LTargetDepends := LDependsOn;
    end;

    Assert.IsTrue(LParents >= 2,
      'runtime packages and external refs must produce at least two dependsOn parents');
    Assert.IsNotNull(LProjectDepends, 'project dependency entry must exist');
    Assert.AreEqual(NativeInt(1), NativeInt(LProjectDepends.Count),
      'the project must depend only on the deliverable');
    Assert.AreEqual('comp-0', LProjectDepends.Items[0].Value,
      'the project must depend on the application');
    Assert.IsNotNull(LTargetDepends, 'application dependency entry must exist');
    Assert.IsTrue(DependsOnContains(LTargetDepends, 'comp-1'),
      'the application must depend on the runtime package');
    Assert.IsTrue(DependsOnContains(LTargetDepends, 'comp-2'),
      'the application must depend on the external DLL');
    Assert.IsTrue(DependsOnContains(LTargetDepends, 'comp-3'),
      'the application must depend on the linked unit');
    Assert.IsFalse(DependsOnContains(LProjectDepends, 'comp-1'),
      'the project must not depend directly on the runtime package');
    Assert.IsFalse(DependsOnContains(LProjectDepends, 'comp-2'),
      'the project must not depend directly on the external DLL');
    Assert.AreEqual('comp-1', LTargetDepends.Items[0].Value,
      'runtime packages must be grouped before external DLLs');
    Assert.AreEqual('comp-2', LTargetDepends.Items[1].Value,
      'external DLLs must be grouped before linked units');
    Assert.AreEqual('comp-3', LTargetDepends.Items[2].Value,
      'linked units must follow external DLLs');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_Dependencies_PackageTargetPreferredOverRuntimePackage;
var
  LJson: TJSONObject;
  LDeps: TJSONArray;
  LDep: TJSONObject;
  LProjectDepends: TJSONArray;
  LTargetDepends: TJSONArray;
  I: Integer;
begin
  FArtefacts.Add(MakeArtefact('rtl.bpl', 'runtime-package', '', -1));
  FArtefacts.Add(MakeArtefact('TestApp.bpl', 'package', '', 2048));
  FArtefacts.Add(MakeArtefact('helper.dll', 'library', '', 512));

  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LDeps := LJson.GetValue('dependencies') as TJSONArray;
    LProjectDepends := nil;
    LTargetDepends := nil;
    for I := 0 to LDeps.Count - 1 do
    begin
      LDep := LDeps.Items[I] as TJSONObject;
      if LDep.GetValue<string>('ref') = FProjectInfo.ProjectName then
        LProjectDepends := LDep.GetValue('dependsOn') as TJSONArray
      else if LDep.GetValue<string>('ref') = 'comp-1' then
        LTargetDepends := LDep.GetValue('dependsOn') as TJSONArray;
    end;

    Assert.IsNotNull(LProjectDepends);
    Assert.AreEqual('comp-1', LProjectDepends.Items[0].Value,
      'the package whose name matches the project must be the deliverable');
    Assert.IsNotNull(LTargetDepends);
    Assert.AreEqual('comp-0', LTargetDepends.Items[0].Value,
      'the runtime package must depend from the deliverable, not be the deliverable');
    Assert.AreEqual('comp-2', LTargetDepends.Items[1].Value,
      'a copied DLL must depend from the deliverable');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_Dependencies_WithoutDeliverable_ProjectDependsOnAll;
var
  LJson: TJSONObject;
  LDeps: TJSONArray;
  LDependsOn: TJSONArray;
begin
  FArtefacts.Add(MakeArtefact('System.dcu', 'unit-evidence', '', 100));
  FArtefacts.Add(MakeArtefact('rtl.bpl', 'runtime-package', '', -1));

  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LDeps := LJson.GetValue('dependencies') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LDeps.Count),
      'without a deliverable there is a single dependency entry');
    LDependsOn := (LDeps.Items[0] as TJSONObject).GetValue('dependsOn') as TJSONArray;
    Assert.AreEqual(NativeInt(2), NativeInt(LDependsOn.Count),
      'the project must still reference every component');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_ExternalDll_MissingFile_KeepsEvidenceAndConditional;
var
  LArtefact: TArtefactInfo;
  LJson: TJSONObject;
  LComponent: TJSONObject;
  LProperties: TJSONArray;
  LProp: TJSONObject;
  I: Integer;
  LHasEvidence: Boolean;
  LHasConfidence: Boolean;
  LHasConditional: Boolean;
  LHasSize: Boolean;
begin
  LArtefact := MakeArtefact('uastack_64.dll', 'external-reference', '', -1);
  LArtefact.Evidence := 'DLL';
  LArtefact.Confidence := 'Source-scan';
  LArtefact.Conditional := True;
  FArtefacts.Add(LArtefact);

  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LComponent := (LJson.GetValue('components') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('uastack_64.dll', LComponent.GetValue<string>('name'));
    Assert.IsNull(LComponent.GetValue('hashes'),
      'an absent DLL must not carry an empty hash');
    LProperties := LComponent.GetValue('properties') as TJSONArray;
    Assert.IsNotNull(LProperties);

    LHasEvidence := False;
    LHasConfidence := False;
    LHasConditional := False;
    LHasSize := False;
    for I := 0 to LProperties.Count - 1 do
    begin
      LProp := LProperties.Items[I] as TJSONObject;
      if LProp.GetValue<string>('name') = 'net.developer-experts.dx-comply:evidence' then
      begin
        LHasEvidence := True;
        Assert.AreEqual('DLL', LProp.GetValue<string>('value'));
      end;
      if LProp.GetValue<string>('name') = 'net.developer-experts.dx-comply:confidence' then
      begin
        LHasConfidence := True;
        Assert.AreEqual('Source-scan', LProp.GetValue<string>('value'));
      end;
      if LProp.GetValue<string>('name') = 'net.developer-experts.dx-comply:conditional' then
      begin
        LHasConditional := True;
        Assert.AreEqual('true', LProp.GetValue<string>('value'));
      end;
      if LProp.GetValue<string>('name') = 'file:size' then
        LHasSize := True;
    end;

    Assert.IsTrue(LHasEvidence, 'JSON must keep the evidence property');
    Assert.IsTrue(LHasConfidence, 'JSON must keep the confidence property');
    Assert.IsTrue(LHasConditional, 'JSON must mark the DLL name as conditional');
    Assert.IsFalse(LHasSize, 'an absent file must not invent a size');
  finally
    LJson.Free;
  end;
end;

// ---- Write — JSON validity --------------------------------------------------

procedure TCycloneDxWriterTests.Write_OutputIsValidJson;
var
  LContent: string;
  LJson: TJSONValue;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LJson := TJSONObject.ParseJSONValue(LContent);
  try
    Assert.IsNotNull(LJson, 'Output file must contain valid JSON');
  finally
    LJson.Free;
  end;
end;

// ---- Write — uniqueness -----------------------------------------------------

procedure TCycloneDxWriterTests.Write_SerialNumber_UniquePerCall;
var
  LFile2: string;
  LJson1, LJson2: TJSONObject;
  LSerial1, LSerial2: string;
begin
  LFile2 := FOutputFile + '.2.json';
  try
    FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
    FWriter.Write(LFile2, FMetadata, FArtefacts, FProjectInfo);

    LJson1 := LoadOutputJson;
    try
      LJson2 := TJSONObject.ParseJSONValue(
        TFile.ReadAllText(LFile2, TEncoding.UTF8)) as TJSONObject;
      try
        LSerial1 := LJson1.GetValue<string>('serialNumber');
        LSerial2 := LJson2.GetValue<string>('serialNumber');
        Assert.AreNotEqual(LSerial1, LSerial2,
          'Each Write call must produce a unique serialNumber');
      finally
        LJson2.Free;
      end;
    finally
      LJson1.Free;
    end;
  finally
    if TFile.Exists(LFile2) then
      TFile.Delete(LFile2);
  end;
end;

// ---- Validate ---------------------------------------------------------------

procedure TCycloneDxWriterTests.Validate_ValidCycloneDxJson_ReturnsTrue;
const
  cValidJson =
    '{"bomFormat":"CycloneDX","specVersion":"1.5","serialNumber":"urn:uuid:test",' +
    '"version":1,"metadata":{},"components":[],"dependencies":[]}';
begin
  Assert.IsTrue(FWriter.Validate(cValidJson),
    'Validate must return True for a minimal valid CycloneDX JSON string');
end;

procedure TCycloneDxWriterTests.Validate_InvalidJson_ReturnsFalse;
begin
  Assert.IsFalse(FWriter.Validate('not json at all'),
    'Validate must return False for non-JSON input');
end;

procedure TCycloneDxWriterTests.Validate_MissingBomFormat_ReturnsFalse;
const
  cJsonNoBomFormat = '{"specVersion":"1.5","serialNumber":"urn:uuid:test"}';
begin
  Assert.IsFalse(FWriter.Validate(cJsonNoBomFormat),
    'Validate must return False when bomFormat is absent');
end;

// ---- Edge cases -------------------------------------------------------------

procedure TCycloneDxWriterTests.Write_FileWithSpecialChars_NoException;
var
  LResult: Boolean;
begin
  // A supplier name with a backslash should not cause JSON serialisation to fail
  FMetadata.Supplier := 'Acme\Corp "Special"';
  Assert.WillNotRaise(
    procedure
    begin
      LResult := FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
    end,
    Exception,
    'Write must not raise an exception when supplier contains special characters');
  Assert.IsTrue(LResult, 'Write must return True even with special characters in supplier name');
end;

// ---- CLI overrides ----------------------------------------------------------

procedure TCycloneDxWriterTests.Write_ProductOverride_AppearsInComponentName;
var
  LJson, LMetadata, LComponent: TJSONObject;
begin
  // Simulate CLI --product overriding the project name from .dproj
  FMetadata.ProductName    := 'CLIProductOverride';
  FProjectInfo.ProjectName := 'DprojProjectName';

  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LMetadata := LJson.GetValue('metadata') as TJSONObject;
    Assert.IsNotNull(LMetadata, 'metadata object must be present');
    LComponent := LMetadata.GetValue('component') as TJSONObject;
    Assert.IsNotNull(LComponent, 'metadata.component must be present');
    Assert.AreEqual('CLIProductOverride', LComponent.GetValue<string>('name'),
      'metadata.component.name must reflect the CLI --product override');
  finally
    LJson.Free;
  end;
end;

procedure TCycloneDxWriterTests.Write_VersionOverride_AppearsInComponentVersion;
var
  LJson, LMetadata, LComponent: TJSONObject;
begin
  // Simulate CLI --version overriding the version from .dproj
  FMetadata.ProductVersion := '9.9.9-cli';
  FProjectInfo.Version     := '1.0.0';

  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);

  LJson := LoadOutputJson;
  Assert.IsNotNull(LJson);
  try
    LMetadata := LJson.GetValue('metadata') as TJSONObject;
    Assert.IsNotNull(LMetadata, 'metadata object must be present');
    LComponent := LMetadata.GetValue('component') as TJSONObject;
    Assert.IsNotNull(LComponent, 'metadata.component must be present');
    Assert.AreEqual('9.9.9-cli', LComponent.GetValue<string>('version'),
      'metadata.component.version must reflect the CLI --version override');
  finally
    LJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCycloneDxWriterTests);

end.
