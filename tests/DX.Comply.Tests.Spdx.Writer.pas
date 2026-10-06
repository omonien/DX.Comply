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
  DUnitX.TestFramework,
  DX.Comply.Spdx.Writer,
  DX.Comply.Engine.Intf,
  DX.Comply.VersionInfo;

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
  FMetadata.ToolVersion := '';

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
    Assert.AreEqual('Tool: DX.Comply-' + GetDxComplyToolVersion, LCreators.Items[0].Value,
      'The SPDX creator tool token must use the running module version');
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

    Assert.IsTrue(HasRelationship(
      'SPDXRef-Package-TestProject.exe', 'DEPENDS_ON', 'SPDXRef-Package-rtl.bpl'),
      'the deliverable must DEPENDS_ON the runtime package');
    Assert.IsTrue(HasRelationship(
      'SPDXRef-Package-TestProject.exe', 'DEPENDS_ON', 'SPDXRef-Package-vendor.dll'),
      'the deliverable must DEPENDS_ON the external DLL');
    Assert.IsTrue(HasRelationship(
      'SPDXRef-Package-TestProject.exe', 'CONTAINS', 'SPDXRef-Package-System.dcu'),
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

end.
