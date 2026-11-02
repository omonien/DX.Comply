/// <summary>
/// DX.Comply.Tests.Spdx3.Writer
/// DUnitX tests for TSpdx3JsonWriter (issue #108).
/// </summary>
///
/// <remarks>
/// Verifies the SPDX 3.0.1 JSON-LD layout: context and graph, the shared
/// CreationInfo, SpdxDocument and software_Sbom, packages, licences,
/// relationships with completeness, and the version selection helpers.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Spdx3.Writer;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  DUnitX.TestFramework,
  DX.Comply.Engine.Intf,
  DX.Comply.Schema.Validator,
  DX.Comply.Spdx3.Writer;

type
  [TestFixture]
  TSpdx3WriterTests = class
  private
    FWriter: TSpdx3JsonWriter;
    FWriterRef: ISbomWriter;
    FArtefacts: TArtefactList;
    FMetadata: TSbomMetadata;
    FProjectInfo: TProjectInfo;
    procedure AddArtefact(const ARelativePath, AArtefactType, AHash: string);
    function Build: TJSONObject;
    function Elements(const ADoc: TJSONObject; const AType: string): TArray<TJSONObject>;
    function PackageId(const ADoc: TJSONObject; const AName: string): string;
    function FindRelationship(const ADoc: TJSONObject; const AFrom, AType: string): TJSONObject;
    function ArrayHas(const AArray: TJSONValue; const AValue: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetFormat_ReturnsSpdx3Json;
    [Test]
    procedure Build_HasContextAndGraph;
    [Test]
    procedure Build_CreationInfo_SpecVersionToolAndCreator;
    [Test]
    procedure Build_AllElementsShareCreationInfo;
    [Test]
    procedure Build_DocumentAndSbom_ReferenceRoot;
    [Test]
    procedure Build_Package_HasHashAndPurpose;
    [Test]
    procedure Build_Relationships_GroupedWithCompleteness;
    [Test]
    procedure Build_Licence_IsLicenseExpression;
    [Test]
    procedure Write_OutputPassesValidate;
    [Test]
    procedure Validate_RejectsSpdx23;
    [Test]
    procedure SchemaValidator_AcceptsOwnOutput;
    [Test]
    procedure SchemaValidator_ReportsDanglingRelationship;
    [Test]
    procedure ApplySpdxVersion_SelectsWriter;
    [Test]
    procedure IsSupportedSpdxVersion_KnownValues;
    [Test]
    procedure Spdx3RelationshipType_Maps;
  end;

implementation

{ TSpdx3WriterTests }

procedure TSpdx3WriterTests.Setup;
begin
  FWriter := TSpdx3JsonWriter.Create;
  FWriterRef := FWriter;
  FArtefacts := TArtefactList.Create;
  FMetadata := Default(TSbomMetadata);
  FMetadata.ProductName := 'TestProduct';
  FMetadata.ProductVersion := '1.0.0';
  FMetadata.Supplier := 'Test GmbH';
  FMetadata.Timestamp := '2026-02-24T10:00:00+01:00';
  FMetadata.ToolName := 'DX.Comply';
  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'TestProject';
  FProjectInfo.ProjectPath := 'C:\Projects\TestProject.dproj';
  FProjectInfo.ProjectDir := 'C:\Projects';
  FProjectInfo.Platform := 'Win32';
  FProjectInfo.Configuration := 'Release';
  FProjectInfo.OutputDir := 'C:\Projects\build\Win32\Release';
  FProjectInfo.Version := '1.0.0.0';
end;

procedure TSpdx3WriterTests.TearDown;
begin
  FArtefacts.Free;
  FProjectInfo.Free;
  FWriterRef := nil;
end;

procedure TSpdx3WriterTests.AddArtefact(const ARelativePath, AArtefactType, AHash: string);
begin
  var LArtefact := Default(TArtefactInfo);
  LArtefact.FilePath := 'C:\Projects\build\' + ARelativePath;
  LArtefact.RelativePath := ARelativePath;
  LArtefact.ArtefactType := AArtefactType;
  LArtefact.Hash := AHash;
  LArtefact.FileSize := 10;
  FArtefacts.Add(LArtefact);
end;

function TSpdx3WriterTests.Build: TJSONObject;
begin
  Result := FWriter.BuildDocument(FMetadata, FArtefacts, FProjectInfo);
  Assert.IsNotNull(Result, 'BuildDocument must return a document');
end;

function TSpdx3WriterTests.Elements(const ADoc: TJSONObject; const AType: string): TArray<TJSONObject>;
begin
  Result := [];
  var LGraph := ADoc.GetValue('@graph') as TJSONArray;
  for var i := 0 to LGraph.Count - 1 do
  begin
    var LItem := LGraph.Items[i] as TJSONObject;
    if LItem.GetValue<string>('type') = AType then
      Result := Result + [LItem];
  end;
end;

function TSpdx3WriterTests.PackageId(const ADoc: TJSONObject; const AName: string): string;
begin
  Result := '';
  for var LPackage in Elements(ADoc, 'software_Package') do
    if SameText(LPackage.GetValue<string>('name'), AName) then
      Exit(LPackage.GetValue<string>('spdxId'));
  Assert.Fail(AName + ' must appear as a software_Package');
end;

function TSpdx3WriterTests.FindRelationship(const ADoc: TJSONObject; const AFrom, AType: string): TJSONObject;
begin
  Result := nil;
  for var LRel in Elements(ADoc, 'Relationship') do
    if (LRel.GetValue<string>('from') = AFrom) and (LRel.GetValue<string>('relationshipType') = AType) then
      Exit(LRel);
end;

function TSpdx3WriterTests.ArrayHas(const AArray: TJSONValue; const AValue: string): Boolean;
begin
  Result := False;
  if not (AArray is TJSONArray) then
    Exit;
  for var i := 0 to TJSONArray(AArray).Count - 1 do
    if TJSONArray(AArray).Items[i].Value = AValue then
      Exit(True);
end;

procedure TSpdx3WriterTests.GetFormat_ReturnsSpdx3Json;
begin
  Assert.IsTrue(FWriter.GetFormat = sfSpdx3Json);
end;

procedure TSpdx3WriterTests.Build_HasContextAndGraph;
begin
  AddArtefact('TestProject.exe', 'application', 'abc');
  var LDoc := Build;
  try
    Assert.AreEqual(cSpdx3Context, LDoc.GetValue<string>('@context'));
    Assert.IsTrue(LDoc.GetValue('@graph') is TJSONArray, '@graph must be an array');
  finally
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.Build_CreationInfo_SpecVersionToolAndCreator;
begin
  AddArtefact('TestProject.exe', 'application', 'abc');
  var LDoc := Build;
  try
    var LInfos := Elements(LDoc, 'CreationInfo');
    Assert.AreEqual<Integer>(1, Length(LInfos), 'exactly one CreationInfo');
    Assert.AreEqual('3.0.1', LInfos[0].GetValue<string>('specVersion'));
    Assert.AreEqual('2026-02-24T09:00:00Z', LInfos[0].GetValue<string>('created'));
    Assert.IsTrue(TJSONArray(LInfos[0].GetValue('createdBy')).Count > 0, 'createdBy must not be empty');
    Assert.IsTrue(TJSONArray(LInfos[0].GetValue('createdUsing')).Count > 0, 'the tool is in createdUsing');
    Assert.AreEqual<Integer>(1, Length(Elements(LDoc, 'Tool')));
    var LOrgs := Elements(LDoc, 'Organization');
    Assert.AreEqual<Integer>(1, Length(LOrgs), 'the supplier is one Organization');
    Assert.AreEqual('Test GmbH', LOrgs[0].GetValue<string>('name'));
  finally
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.Build_AllElementsShareCreationInfo;
begin
  AddArtefact('TestProject.exe', 'application', 'abc');
  AddArtefact('rtl.bpl', 'runtime-package', '');
  var LDoc := Build;
  try
    var LInfoId := Elements(LDoc, 'CreationInfo')[0].GetValue<string>('@id');
    Assert.IsTrue(LInfoId.StartsWith('_:'), 'CreationInfo is a blank node');
    var LGraph := LDoc.GetValue('@graph') as TJSONArray;
    for var i := 0 to LGraph.Count - 1 do
    begin
      var LItem := LGraph.Items[i] as TJSONObject;
      if LItem.GetValue<string>('type') = 'CreationInfo' then
        Continue;
      Assert.AreEqual(LInfoId, LItem.GetValue<string>('creationInfo'),
        LItem.GetValue<string>('type') + ' must reference the CreationInfo');
      Assert.IsTrue(LItem.GetValue<string>('spdxId') <> '', 'every element has an spdxId');
    end;
  finally
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.Build_DocumentAndSbom_ReferenceRoot;
begin
  AddArtefact('TestProject.exe', 'application', 'abc');
  var LDoc := Build;
  try
    var LDocs := Elements(LDoc, 'SpdxDocument');
    var LSboms := Elements(LDoc, 'software_Sbom');
    Assert.AreEqual<Integer>(1, Length(LDocs));
    Assert.AreEqual<Integer>(1, Length(LSboms));
    var LAppId := PackageId(LDoc, 'TestProject.exe');
    Assert.IsTrue(ArrayHas(LSboms[0].GetValue('rootElement'), LAppId), 'the SBOM root is the deliverable');
    Assert.IsTrue(ArrayHas(LSboms[0].GetValue('element'), LAppId), 'the SBOM lists the deliverable');
    Assert.IsTrue(ArrayHas(LDocs[0].GetValue('rootElement'), LSboms[0].GetValue<string>('spdxId')),
      'the document root is the SBOM');
    var LDataLicence := '';
    for var LExpr in Elements(LDoc, 'simplelicensing_LicenseExpression') do
      if LExpr.GetValue<string>('spdxId') = LDocs[0].GetValue<string>('dataLicense') then
        LDataLicence := LExpr.GetValue<string>('simplelicensing_licenseExpression');
    Assert.AreEqual('CC0-1.0', LDataLicence, 'data licence stays CC0-1.0');
  finally
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.Build_Package_HasHashAndPurpose;
begin
  AddArtefact('TestProject.exe', 'application', 'abc123');
  var LDoc := Build;
  try
    for var LPackage in Elements(LDoc, 'software_Package') do
      if LPackage.GetValue<string>('name') = 'TestProject.exe' then
      begin
        Assert.AreEqual('application', LPackage.GetValue<string>('software_primaryPurpose'));
        var LHashes := LPackage.GetValue('verifiedUsing') as TJSONArray;
        Assert.IsNotNull(LHashes, 'verifiedUsing must carry the hash');
        var LHash := LHashes.Items[0] as TJSONObject;
        Assert.AreEqual('Hash', LHash.GetValue<string>('type'));
        Assert.AreEqual('sha256', LHash.GetValue<string>('algorithm'));
        Assert.AreEqual('abc123', LHash.GetValue<string>('hashValue'));
        Exit;
      end;
    Assert.Fail('TestProject.exe package missing');
  finally
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.Build_Relationships_GroupedWithCompleteness;
begin
  AddArtefact('TestProject.exe', 'application', '');
  AddArtefact('rtl.bpl', 'runtime-package', '');
  AddArtefact('vendor.dll', 'external-reference', '');
  AddArtefact('System.dcu', 'unit-evidence', '');
  var LDoc := Build;
  try
    var LAppId := PackageId(LDoc, 'TestProject.exe');
    var LDepends := FindRelationship(LDoc, LAppId, 'dependsOn');
    Assert.IsNotNull(LDepends, 'the deliverable has one dependsOn relationship');
    Assert.IsTrue(ArrayHas(LDepends.GetValue('to'), PackageId(LDoc, 'rtl.bpl')));
    Assert.IsTrue(ArrayHas(LDepends.GetValue('to'), PackageId(LDoc, 'vendor.dll')));
    Assert.AreEqual('incomplete', LDepends.GetValue<string>('completeness'),
      'the deliverable dependency list is not claimed complete');
    var LContains := FindRelationship(LDoc, LAppId, 'contains');
    Assert.IsNotNull(LContains, 'the deliverable contains the unit');
    Assert.IsTrue(ArrayHas(LContains.GetValue('to'), PackageId(LDoc, 'System.dcu')));
    for var LRel in Elements(LDoc, 'Relationship') do
      Assert.IsTrue(TJSONArray(LRel.GetValue('to')).Count > 0, 'to is never empty');
    Assert.IsNull(FindRelationship(LDoc, Elements(LDoc, 'SpdxDocument')[0].GetValue<string>('spdxId'),
      'describes'), 'SPDX 3 has no DESCRIBES relationship');
  finally
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.Build_Licence_IsLicenseExpression;
begin
  FMetadata.Licence := 'MIT';
  AddArtefact('TestProject.exe', 'application', '');
  var LDoc := Build;
  try
    var LFound := '';
    for var LExpr in Elements(LDoc, 'simplelicensing_LicenseExpression') do
      if LExpr.GetValue<string>('simplelicensing_licenseExpression') = 'MIT' then
        LFound := LExpr.GetValue<string>('spdxId');
    Assert.AreNotEqual('', LFound, 'MIT must be a licence expression');
    var LRel := FindRelationship(LDoc, PackageId(LDoc, 'TestProject.exe'), 'hasDeclaredLicense');
    Assert.IsNotNull(LRel, 'the deliverable declares its licence');
    Assert.IsTrue(ArrayHas(LRel.GetValue('to'), LFound));
  finally
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.Write_OutputPassesValidate;
begin
  AddArtefact('TestProject.exe', 'application', 'abc');
  var LPath := TPath.Combine(TPath.GetTempPath, 'test_spdx3_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '.json');
  try
    Assert.IsTrue(FWriter.Write(LPath, FMetadata, FArtefacts, FProjectInfo));
    Assert.IsTrue(FWriter.Validate(TFile.ReadAllText(LPath, TEncoding.UTF8)));
  finally
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
  end;
end;

procedure TSpdx3WriterTests.Validate_RejectsSpdx23;
begin
  Assert.IsFalse(FWriter.Validate('{"spdxVersion":"SPDX-2.3","packages":[]}'));
  Assert.IsFalse(FWriter.Validate('not json'));
end;

procedure TSpdx3WriterTests.SchemaValidator_AcceptsOwnOutput;
begin
  FMetadata.Licence := 'MIT';
  AddArtefact('TestProject.exe', 'application', 'abc');
  AddArtefact('rtl.bpl', 'runtime-package', '');
  AddArtefact('System.dcu', 'unit-evidence', '');
  var LDoc := Build;
  var LValidator := TSbomValidator.Create;
  try
    var LResult := LValidator.ValidateAuto(LDoc.ToJSON);
    Assert.IsTrue(LResult.IsValid, 'SPDX 3 output must pass: ' + string.Join('; ', LResult.Errors));
  finally
    LValidator.Free;
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.SchemaValidator_ReportsDanglingRelationship;
begin
  AddArtefact('TestProject.exe', 'application', 'abc');
  var LDoc := Build;
  var LValidator := TSbomValidator.Create;
  try
    var LRel := TJSONObject.Create;
    LRel.AddPair('type', 'Relationship');
    LRel.AddPair('spdxId', 'urn:test#rel');
    LRel.AddPair('creationInfo', '_:creationinfo');
    LRel.AddPair('from', 'urn:test#missing');
    LRel.AddPair('relationshipType', 'dependsOn');
    LRel.AddPair('to', TJSONArray.Create.Add('urn:test#other'));
    (LDoc.GetValue('@graph') as TJSONArray).Add(LRel);
    Assert.IsFalse(LValidator.ValidateAuto(LDoc.ToJSON).IsValid);
  finally
    LValidator.Free;
    LDoc.Free;
  end;
end;

procedure TSpdx3WriterTests.ApplySpdxVersion_SelectsWriter;
begin
  Assert.IsTrue(ApplySpdxVersion(sfSpdxJson, '3.0.1') = sfSpdx3Json);
  Assert.IsTrue(ApplySpdxVersion(sfSpdx3Json, '2.3') = sfSpdxJson);
  Assert.IsTrue(ApplySpdxVersion(sfSpdxJson, '') = sfSpdxJson);
  Assert.IsTrue(ApplySpdxVersion(sfSpdx3Json, '') = sfSpdx3Json, 'an empty version keeps the format');
  Assert.IsTrue(ApplySpdxVersion(sfCycloneDxJson, '3.0.1') = sfCycloneDxJson);
end;

procedure TSpdx3WriterTests.IsSupportedSpdxVersion_KnownValues;
begin
  Assert.IsTrue(IsSupportedSpdxVersion(''));
  Assert.IsTrue(IsSupportedSpdxVersion('2.3'));
  Assert.IsTrue(IsSupportedSpdxVersion('3.0.1'));
  Assert.IsFalse(IsSupportedSpdxVersion('3.0'));
  Assert.IsFalse(IsSupportedSpdxVersion('SPDX-2.3'));
end;

procedure TSpdx3WriterTests.Spdx3RelationshipType_Maps;
begin
  Assert.AreEqual('dependsOn', Spdx3RelationshipType('DEPENDS_ON'));
  Assert.AreEqual('contains', Spdx3RelationshipType('CONTAINS'));
end;

initialization
  TDUnitX.RegisterTestFixture(TSpdx3WriterTests);

end.
