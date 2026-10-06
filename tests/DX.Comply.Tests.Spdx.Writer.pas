/// <summary>
/// DX.Comply.Tests.Spdx.Writer
/// DUnitX tests for TSpdxJsonWriter.
/// </summary>
///
/// <remarks>
/// Verifies SPDX 2.3 JSON output: required top-level fields,
/// package entries, checksum embedding, creation info, relationships,
/// document namespace, and validation logic.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Spdx.Writer;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.RegularExpressions,
  DUnitX.TestFramework,
  DX.Comply.Spdx.Writer,
  DX.Comply.Engine.Intf;

type
  [TestFixture]
  TSpdxWriterTests = class
  private
    FWriter: ISbomWriter;
    FOutputFile: string;
    FArtefacts: TArtefactList;
    FMetadata: TSbomMetadata;
    FProjectInfo: TProjectInfo;
    function LoadOutputJson: TJSONObject;
    function MakeArtefact(const ARelativePath, AArtefactType, AHash: string;
      AFileSize: Int64): TArtefactInfo;
    function PackageAt(const AJson: TJSONObject; AIndex: Integer): TJSONObject;
    function IsSpdxId(const AId: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetFormat_ReturnsSpdxJson;

    [Test]
    procedure Write_EmptyArtefacts_CreatesFile;

    [Test]
    procedure Write_ContainsSpdxVersion;

    [Test]
    procedure Write_ContainsDataLicense;

    [Test]
    procedure Write_ContainsSpdxId;

    [Test]
    procedure Write_ContainsDocumentNamespace;

    [Test]
    procedure Write_ContainsCreationInfo;

    [Test]
    procedure Write_CreationInfo_HasCreators;

    [Test]
    procedure Write_SingleArtefact_ContainsPackage;

    [Test]
    procedure Write_SingleArtefact_ContainsChecksum;

    [Test]
    procedure Write_ContainsRelationships;

    [Test]
    procedure Write_Relationship_IsDescribes;

    [Test]
    procedure Write_Relationships_DeliverableDependsOnCategories;

    [Test]
    procedure Validate_ValidSpdx_ReturnsTrue;

    [Test]
    procedure Validate_InvalidJson_ReturnsFalse;

    [Test]
    procedure Validate_EmptyString_ReturnsFalse;

    [Test]
    procedure Write_Package_HasDownloadLocation;

    [Test]
    procedure Write_Package_SpdxIdStartsWithPrefix;

    /// <summary>
    /// Two artefacts with the same basename and different paths must get
    /// distinct SPDX IDs, and relationships must point at those IDs (issue #39).
    /// </summary>
    [Test]
    procedure Write_DuplicateBasename_SpdxIdsDiffer;

    /// <summary>
    /// The same relative path always yields the same ID, including when only
    /// the directory separator changes (issue #39).
    /// </summary>
    [Test]
    procedure Write_SpdxId_StableAcrossSeparators;

    /// <summary>Characters outside the SPDX ID alphabet are sanitized (issue #39).</summary>
    [Test]
    procedure Write_SpdxId_SanitizesIllegalCharacters;

    /// <summary>creationInfo.created matches YYYY-MM-DDThh:mm:ssZ (issue #40).</summary>
    [Test]
    procedure Write_Created_MatchesUtcPattern;

    /// <summary>
    /// Offset timestamps and fractional seconds are normalized to UTC Z (issue #40).
    /// </summary>
    [Test]
    procedure Write_Created_NormalizesOffsetTimestamp;

    /// <summary>No referenceLocator contains whitespace (issue #40).</summary>
    [Test]
    procedure Write_ReferenceLocator_ContainsNoWhitespace;

    /// <summary>
    /// Packages carry NOASSERTION licenses, and supplier follows metadata.
    /// </summary>
    [Test]
    procedure Write_Package_LicenseAndSupplier;
  end;

implementation

{ TSpdxWriterTests }

procedure TSpdxWriterTests.Setup;
begin
  FWriter := TSpdxJsonWriter.Create;
  FOutputFile := TPath.Combine(TPath.GetTempPath, 'test_spdx_' +
    FormatDateTime('yyyymmddhhnnsszzz', Now) + '.json');

  FArtefacts := TArtefactList.Create;

  FMetadata.ProductName := 'TestProduct';
  FMetadata.ProductVersion := '1.0.0';
  FMetadata.Supplier := 'Test GmbH';
  FMetadata.Timestamp := '2026-02-24T10:00:00+01:00';
  FMetadata.ToolName := 'DX.Comply';
  FMetadata.ToolVersion := '1.0.0';

  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'TestProject';
  FProjectInfo.ProjectPath := 'C:\Projects\TestProject.dproj';
  FProjectInfo.ProjectDir := 'C:\Projects';
  FProjectInfo.Platform := 'Win32';
  FProjectInfo.Configuration := 'Release';
  FProjectInfo.OutputDir := 'C:\Projects\build\Win32\Release';
  FProjectInfo.Version := '1.0.0.0';
end;

procedure TSpdxWriterTests.TearDown;
begin
  FArtefacts.Free;
  FProjectInfo.Free;
  if TFile.Exists(FOutputFile) then
    TFile.Delete(FOutputFile);
end;

function TSpdxWriterTests.LoadOutputJson: TJSONObject;
var
  LList: TStringList;
begin
  LList := TStringList.Create;
  try
    LList.LoadFromFile(FOutputFile, TEncoding.UTF8);
    Result := TJSONObject.ParseJSONValue(LList.Text) as TJSONObject;
  finally
    LList.Free;
  end;
end;

function TSpdxWriterTests.MakeArtefact(const ARelativePath, AArtefactType,
  AHash: string; AFileSize: Int64): TArtefactInfo;
begin
  Result := Default(TArtefactInfo);
  Result.FilePath := 'C:\Projects\build\' + ARelativePath;
  Result.RelativePath := ARelativePath;
  Result.ArtefactType := AArtefactType;
  Result.Hash := AHash;
  Result.FileSize := AFileSize;
end;

function TSpdxWriterTests.PackageAt(const AJson: TJSONObject; AIndex: Integer): TJSONObject;
var
  LPackages: TJSONArray;
begin
  LPackages := AJson.GetValue('packages') as TJSONArray;
  Result := LPackages.Items[AIndex] as TJSONObject;
end;

function TSpdxWriterTests.IsSpdxId(const AId: string): Boolean;
begin
  Result := TRegEx.IsMatch(AId, '^SPDXRef-[a-zA-Z0-9.\-]+$');
end;

procedure TSpdxWriterTests.GetFormat_ReturnsSpdxJson;
begin
  Assert.AreEqual(Ord(sfSpdxJson), Ord(FWriter.GetFormat));
end;

procedure TSpdxWriterTests.Write_EmptyArtefacts_CreatesFile;
begin
  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  Assert.IsTrue(TFile.Exists(FOutputFile));
end;

procedure TSpdxWriterTests.Write_ContainsSpdxVersion;
var
  LJson: TJSONObject;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    Assert.AreEqual('SPDX-2.3', LJson.GetValue<string>('spdxVersion'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_ContainsDataLicense;
var
  LJson: TJSONObject;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    Assert.AreEqual('CC0-1.0', LJson.GetValue<string>('dataLicense'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_ContainsSpdxId;
var
  LJson: TJSONObject;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    Assert.AreEqual('SPDXRef-DOCUMENT', LJson.GetValue<string>('SPDXID'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_ContainsDocumentNamespace;
var
  LJson: TJSONObject;
  LNamespace: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LNamespace := LJson.GetValue<string>('documentNamespace');
    Assert.IsTrue(LNamespace.StartsWith('https://spdx.org/spdxdocs/'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_ContainsCreationInfo;
var
  LJson: TJSONObject;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    Assert.IsNotNull(LJson.GetValue('creationInfo'));
    Assert.IsTrue(LJson.GetValue('creationInfo') is TJSONObject);
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_CreationInfo_HasCreators;
var
  LJson: TJSONObject;
  LCreationInfo: TJSONObject;
  LCreators: TJSONArray;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LCreationInfo := LJson.GetValue('creationInfo') as TJSONObject;
    LCreators := LCreationInfo.GetValue('creators') as TJSONArray;
    Assert.IsTrue(LCreators.Count > 0);
    Assert.IsTrue(LCreators.Items[0].Value.StartsWith('Tool: DX.Comply'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_SingleArtefact_ContainsPackage;
var
  LJson: TJSONObject;
  LPackages: TJSONArray;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application',
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789', 102400));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LPackages := LJson.GetValue('packages') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LPackages.Count));
    Assert.AreEqual('MyApp.exe', (LPackages.Items[0] as TJSONObject).GetValue<string>('name'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_SingleArtefact_ContainsChecksum;
var
  LJson: TJSONObject;
  LPackage: TJSONObject;
  LChecksums: TJSONArray;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application',
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789', 102400));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LPackage := (LJson.GetValue('packages') as TJSONArray).Items[0] as TJSONObject;
    LChecksums := LPackage.GetValue('checksums') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LChecksums.Count));
    Assert.AreEqual('SHA256',
      (LChecksums.Items[0] as TJSONObject).GetValue<string>('algorithm'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_ContainsRelationships;
var
  LJson: TJSONObject;
  LRelationships: TJSONArray;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application', '', 1024));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LRelationships := LJson.GetValue('relationships') as TJSONArray;
    Assert.IsTrue(LRelationships.Count > 0);
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_Relationship_IsDescribes;
var
  LJson: TJSONObject;
  LRel: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application', '', 1024));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LRel := (LJson.GetValue('relationships') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('DESCRIBES', LRel.GetValue<string>('relationshipType'));
    Assert.AreEqual('SPDXRef-DOCUMENT', LRel.GetValue<string>('spdxElementId'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_Relationships_DeliverableDependsOnCategories;
var
  LJson: TJSONObject;
  LRelationships: TJSONArray;
  LRel: TJSONObject;
  I: Integer;
  LAppId, LRtlId, LDllId, LUnitId: string;

  function HasRelationship(const AFrom, AType, ATo: string): Boolean;
  var
    J: Integer;
    LItem: TJSONObject;
  begin
    Result := False;
    for J := 0 to LRelationships.Count - 1 do
    begin
      LItem := LRelationships.Items[J] as TJSONObject;
      if (LItem.GetValue<string>('spdxElementId') = AFrom) and
         (LItem.GetValue<string>('relationshipType') = AType) and
         (LItem.GetValue<string>('relatedSpdxElement') = ATo) then
        Exit(True);
    end;
  end;

  function PackageId(const AName: string): string;
  var
    LPackages: TJSONArray;
    K: Integer;
    LPackage: TJSONObject;
  begin
    Result := '';
    LPackages := LJson.GetValue('packages') as TJSONArray;
    for K := 0 to LPackages.Count - 1 do
    begin
      LPackage := LPackages.Items[K] as TJSONObject;
      if SameText(LPackage.GetValue<string>('name'), AName) then
        Exit(LPackage.GetValue<string>('SPDXID'));
    end;
    Assert.AreNotEqual('', Result, AName + ' must appear as a package');
  end;

  function IsFilenameOnlyId(const AId, AFileName: string): Boolean;
  begin
    Result := SameText(AId, 'SPDXRef-Package-' + AFileName);
  end;

begin
  FArtefacts.Add(MakeArtefact('TestProject.exe', 'application', '', 1024));
  FArtefacts.Add(MakeArtefact('rtl.bpl', 'runtime-package', '', -1));
  FArtefacts.Add(MakeArtefact('vendor.dll', 'external-reference', '', -1));
  FArtefacts.Add(MakeArtefact('System.dcu', 'unit-evidence', '', 10));

  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadOutputJson;
  try
    LRelationships := LJson.GetValue('relationships') as TJSONArray;
    Assert.IsNotNull(LRelationships);
    LRel := LRelationships.Items[0] as TJSONObject;
    Assert.AreEqual('DESCRIBES', LRel.GetValue<string>('relationshipType'),
      'DESCRIBES entries must stay ahead of the dependency edges');

    LAppId := PackageId('TestProject.exe');
    LRtlId := PackageId('rtl.bpl');
    LDllId := PackageId('vendor.dll');
    LUnitId := PackageId('System.dcu');
    Assert.IsFalse(IsFilenameOnlyId(LAppId, 'TestProject.exe'),
      'relationship IDs must use the path-based package SPDX ID');

    Assert.IsTrue(HasRelationship(LAppId, 'DEPENDS_ON', LRtlId),
      'the deliverable must DEPENDS_ON the runtime package');
    Assert.IsTrue(HasRelationship(LAppId, 'DEPENDS_ON', LDllId),
      'the deliverable must DEPENDS_ON the external DLL');
    Assert.IsTrue(HasRelationship(LAppId, 'CONTAINS', LUnitId),
      'the deliverable must CONTAIN the linked unit');

    for I := 0 to LRelationships.Count - 1 do
    begin
      LRel := LRelationships.Items[I] as TJSONObject;
      if LRel.GetValue<string>('relationshipType') = 'DESCRIBES' then
        Assert.AreEqual('SPDXRef-DOCUMENT', LRel.GetValue<string>('spdxElementId'),
          'DESCRIBES must still originate at the document');
    end;
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Validate_ValidSpdx_ReturnsTrue;
var
  LContent: TStringList;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := TStringList.Create;
  try
    LContent.LoadFromFile(FOutputFile, TEncoding.UTF8);
    Assert.IsTrue(FWriter.Validate(LContent.Text));
  finally
    LContent.Free;
  end;
end;

procedure TSpdxWriterTests.Validate_InvalidJson_ReturnsFalse;
begin
  Assert.IsFalse(FWriter.Validate('{"foo": "bar"}'));
end;

procedure TSpdxWriterTests.Validate_EmptyString_ReturnsFalse;
begin
  Assert.IsFalse(FWriter.Validate(''));
end;

procedure TSpdxWriterTests.Write_Package_HasDownloadLocation;
var
  LJson: TJSONObject;
  LPackage: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application', '', 1024));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LPackage := (LJson.GetValue('packages') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('downloadLocation'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_Package_SpdxIdStartsWithPrefix;
var
  LJson: TJSONObject;
  LPackage: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application', '', 1024));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LPackage := (LJson.GetValue('packages') as TJSONArray).Items[0] as TJSONObject;
    Assert.IsTrue(LPackage.GetValue<string>('SPDXID').StartsWith('SPDXRef-'));
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_DuplicateBasename_SpdxIdsDiffer;
var
  LJson: TJSONObject;
  LFirstId, LSecondId: string;
  LRelationships: TJSONArray;
  LRel: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('setup\4dcompiler.exe', 'application', '', 1024));
  FArtefacts.Add(MakeArtefact('tools\4dcompiler.exe', 'application', '', 2048));
  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));

  LJson := LoadOutputJson;
  try
    LFirstId := PackageAt(LJson, 0).GetValue<string>('SPDXID');
    LSecondId := PackageAt(LJson, 1).GetValue<string>('SPDXID');

    Assert.AreNotEqual(LFirstId, LSecondId,
      'Same basename in different folders must not share an SPDX ID');
    Assert.AreNotEqual('SPDXRef-Package-4dcompiler.exe', LFirstId,
      'SPDX ID must not be derived from the basename alone');
    Assert.IsTrue(IsSpdxId(LFirstId), 'First SPDX ID must match SPDXRef-[A-Za-z0-9.-]+');
    Assert.IsTrue(IsSpdxId(LSecondId), 'Second SPDX ID must match SPDXRef-[A-Za-z0-9.-]+');
    Assert.IsTrue(LFirstId.Contains('setup-4dcompiler.exe'),
      'ID should keep the sanitized relative path');
    Assert.IsTrue(LSecondId.Contains('tools-4dcompiler.exe'),
      'ID should keep the sanitized relative path');

    LRelationships := LJson.GetValue('relationships') as TJSONArray;
    // Two DESCRIBES edges, plus DEPENDS_ON from the first application
    // (same score, first match is the deliverable) to the second.
    Assert.AreEqual(NativeInt(3), NativeInt(LRelationships.Count));
    LRel := LRelationships.Items[0] as TJSONObject;
    Assert.AreEqual('DESCRIBES', LRel.GetValue<string>('relationshipType'));
    Assert.AreEqual(LFirstId, LRel.GetValue<string>('relatedSpdxElement'),
      'Relationship must point at the first package ID');
    LRel := LRelationships.Items[1] as TJSONObject;
    Assert.AreEqual('DESCRIBES', LRel.GetValue<string>('relationshipType'));
    Assert.AreEqual(LSecondId, LRel.GetValue<string>('relatedSpdxElement'),
      'Relationship must point at the second package ID');
    LRel := LRelationships.Items[2] as TJSONObject;
    Assert.AreEqual('DEPENDS_ON', LRel.GetValue<string>('relationshipType'));
    Assert.AreEqual(LFirstId, LRel.GetValue<string>('spdxElementId'),
      'the first application is the deliverable');
    Assert.AreEqual(LSecondId, LRel.GetValue<string>('relatedSpdxElement'),
      'DEPENDS_ON must use the path-based package ID');
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_SpdxId_StableAcrossSeparators;
var
  LSlashId, LBackslashId, LAgain: string;
  LJson: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('setup/4dcompiler.exe', 'application', '', 1024));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LSlashId := PackageAt(LJson, 0).GetValue<string>('SPDXID');
  finally
    LJson.Free;
  end;

  FArtefacts.Clear;
  FArtefacts.Add(MakeArtefact('setup\4dcompiler.exe', 'application', '', 1024));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LBackslashId := PackageAt(LJson, 0).GetValue<string>('SPDXID');
  finally
    LJson.Free;
  end;

  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LAgain := PackageAt(LJson, 0).GetValue<string>('SPDXID');
  finally
    LJson.Free;
  end;

  Assert.AreEqual(LSlashId, LBackslashId,
    'Forward and back slashes of the same path must produce one ID');
  Assert.AreEqual(LBackslashId, LAgain,
    'Writing the same artefact again must keep the same SPDX ID');
  Assert.IsTrue(IsSpdxId(LSlashId));
end;

procedure TSpdxWriterTests.Write_SpdxId_SanitizesIllegalCharacters;
var
  LJson: TJSONObject;
  LId: string;
begin
  FArtefacts.Add(MakeArtefact('my tools\foo_bar.dll', 'library', '', 64));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LId := PackageAt(LJson, 0).GetValue<string>('SPDXID');
    Assert.IsTrue(IsSpdxId(LId), 'Sanitized SPDX ID must match the SPDX pattern');
    Assert.IsTrue(LId.Contains('my-tools-foo-bar.dll'),
      'Spaces, slashes and underscores must become hyphens');
    Assert.IsFalse(LId.Contains(' '), 'SPDX ID must not contain spaces');
    Assert.IsFalse(LId.Contains('_'), 'SPDX ID must not contain underscores');
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_Created_MatchesUtcPattern;
var
  LJson: TJSONObject;
  LCreated: string;
begin
  FMetadata.Timestamp := '';
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LCreated := (LJson.GetValue('creationInfo') as TJSONObject).GetValue<string>('created');
    Assert.IsTrue(TRegEx.IsMatch(LCreated, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'),
      'created must be UTC YYYY-MM-DDThh:mm:ssZ, got ' + LCreated);
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_Created_NormalizesOffsetTimestamp;
var
  LJson: TJSONObject;
  LCreated: string;
begin
  // The value reported by tools.spdx.org in issue #40.
  FMetadata.Timestamp := '2026-05-18T14:27:39.895+10:00';
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LCreated := (LJson.GetValue('creationInfo') as TJSONObject).GetValue<string>('created');
    Assert.AreEqual('2026-05-18T04:27:39Z', LCreated,
      'Fractional seconds are dropped and the offset is converted to UTC');
  finally
    LJson.Free;
  end;

  FMetadata.Timestamp := '2026-02-24T10:00:00.895Z';
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LCreated := (LJson.GetValue('creationInfo') as TJSONObject).GetValue<string>('created');
    Assert.AreEqual('2026-02-24T10:00:00Z', LCreated);
  finally
    LJson.Free;
  end;

  FMetadata.Timestamp := '2026-02-24T10:00:00-05:00';
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LCreated := (LJson.GetValue('creationInfo') as TJSONObject).GetValue<string>('created');
    Assert.AreEqual('2026-02-24T15:00:00Z', LCreated);
  finally
    LJson.Free;
  end;

  FMetadata.Timestamp := '2026-05-18T14:27:39+1000';
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LCreated := (LJson.GetValue('creationInfo') as TJSONObject).GetValue<string>('created');
    Assert.AreEqual('2026-05-18T04:27:39Z', LCreated);
  finally
    LJson.Free;
  end;

  FMetadata.Timestamp := '2026-01-01T01:30:00+10:00';
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LCreated := (LJson.GetValue('creationInfo') as TJSONObject).GetValue<string>('created');
    Assert.AreEqual('2025-12-31T15:30:00Z', LCreated,
      'Offset conversion must cross the day boundary');
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_ReferenceLocator_ContainsNoWhitespace;
var
  LJson: TJSONObject;
  LPackages: TJSONArray;
  LPackage, LRef: TJSONObject;
  LRefs: TJSONArray;
  LLocator: string;
  I: Integer;
begin
  FArtefacts.Add(MakeArtefact('workshop4\helper tool.dll', 'library', '', 32));
  FArtefacts.Add(MakeArtefact('tools\workshop4.exe', 'application', '', 64));
  FArtefacts.Add(MakeArtefact('dist\foo@bar.dll', 'library', '', 8));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LPackages := LJson.GetValue('packages') as TJSONArray;
    for I := 0 to LPackages.Count - 1 do
    begin
      LPackage := LPackages.Items[I] as TJSONObject;
      LRefs := LPackage.GetValue('externalRefs') as TJSONArray;
      Assert.IsNotNull(LRefs, 'Package must carry an external reference');
      LRef := LRefs.Items[0] as TJSONObject;
      LLocator := LRef.GetValue<string>('referenceLocator');
      Assert.IsFalse(LLocator.Contains(' '),
        'referenceLocator must not contain spaces: ' + LLocator);
      Assert.IsFalse(LLocator.Contains(#9), 'referenceLocator must not contain tabs');
      Assert.IsFalse(LLocator.Contains('\'), 'referenceLocator must use URI separators');
    end;

    LLocator := ((PackageAt(LJson, 0).GetValue('externalRefs') as TJSONArray)
      .Items[0] as TJSONObject).GetValue<string>('referenceLocator');
    Assert.AreEqual('pkg:generic/workshop4/helper%20tool.dll', LLocator,
      'Spaces in the path must be percent-encoded inside a generic PURL');
    Assert.IsTrue(LLocator.StartsWith('pkg:generic/'),
      'referenceLocator must be a Package URL');

    LLocator := ((PackageAt(LJson, 1).GetValue('externalRefs') as TJSONArray)
      .Items[0] as TJSONObject).GetValue<string>('referenceLocator');
    Assert.AreEqual('pkg:generic/tools/workshop4.exe', LLocator);

    LLocator := ((PackageAt(LJson, 2).GetValue('externalRefs') as TJSONArray)
      .Items[0] as TJSONObject).GetValue<string>('referenceLocator');
    Assert.AreEqual('pkg:generic/dist/foo%40bar.dll', LLocator,
      '@ must be percent-encoded so it is not read as a purl version');
  finally
    LJson.Free;
  end;
end;

procedure TSpdxWriterTests.Write_Package_LicenseAndSupplier;
var
  LJson: TJSONObject;
  LPackage: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application', '', 1024));
  FMetadata.Supplier := 'Test GmbH';
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LPackage := PackageAt(LJson, 0);
    Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('licenseConcluded'));
    Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('licenseDeclared'));
    Assert.AreEqual('Organization: Test GmbH', LPackage.GetValue<string>('supplier'));
  finally
    LJson.Free;
  end;

  FMetadata.Supplier := '';
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LJson := LoadOutputJson;
  try
    LPackage := PackageAt(LJson, 0);
    Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('supplier'),
      'An empty supplier stays NOASSERTION');
  finally
    LJson.Free;
  end;
end;

end.
