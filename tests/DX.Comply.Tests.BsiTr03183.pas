/// <summary>
/// DX.Comply.Tests.BsiTr03183
/// DUnitX tests for BSI TR-03183-2 fields on CycloneDX 1.6 and SPDX 2.3.
/// </summary>
///
/// <remarks>
/// Checks SHA-512 next to SHA-256, the filename and executable, archive and
/// structured properties, the SBOM creator contact, the incomplete dependency
/// mark, and manifest library creator, version and licence fields.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.BsiTr03183;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  DUnitX.TestFramework,
  DX.Comply.CLI.Options,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.CycloneDx.XmlWriter,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.Schema.Validator,
  DX.Comply.Spdx.Writer;

type
  /// <summary>
  /// DUnitX tests for the TR-03183-2 fields DX.Comply can fill from evidence.
  /// </summary>
  [TestFixture]
  TBsiTr03183Tests = class
  private
    const
      cSha256 = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      cSha512 = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789' +
        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
  private
    FOutputFile: string;
    FArtefacts: TArtefactList;
    FMetadata: TSbomMetadata;
    FProjectInfo: TProjectInfo;
    function MakeArtefact(const ARelativePath, AArtefactType, AHash, AHashSha512: string;
      AFileSize: Int64): TArtefactInfo;
    function LoadJson: TJSONObject;
    function ReadOutput: string;
    function SliceBetween(const AText, AStart, AEnd: string): string;
    function PropertyValue(AProperties: TJSONArray; const AName: string): string;
    function FindNamed(AItems: TJSONArray; const AName: string): TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Classify_EmailUrlExecutableAndArchive;
    [Test]
    procedure Json_FileComponent_HasSha512AndTrProperties;
    [Test]
    procedure Json_MissingDll_OmitsHashes_KeepsTrProperties;
    [Test]
    procedure Json_CreatorEmail_WritesManufacturerAndIncomplete;
    [Test]
    procedure Json_CreatorUrl_WritesManufacturerUrl;
    [Test]
    procedure Json_EmptyCreator_OmitsManufacturer;
    [Test]
    procedure Xml_FileComponent_HashAndPropertyOrder;
    [Test]
    procedure Xml_CreatorEmail_FollowsMetadataComponent;
    [Test]
    procedure Xml_CreatorUrl_WritesManufacturerUrl;
    [Test]
    procedure Spdx_FileComponent_HasSha512FileNameAndComment;
    [Test]
    procedure Spdx_CreatorEmail_AddsPerson;
    [Test]
    procedure Spdx_CreatorUrl_AddsComment;
    [Test]
    procedure Schema_AcceptsSha512_RejectsShortValue;
    [Test]
    procedure Manifest_Library_HasCreatorVersionLicence_NotFileFields;
    [Test]
    procedure Cli_SbomCreator_AcceptsEmailAndUrl;
    [Test]
    procedure Config_SbomCreator_TrimsAndKeepsInvalidText;
    [Test]
    procedure Generate_InvalidSbomCreator_Stops;
  end;

implementation

function TBsiTr03183Tests.MakeArtefact(const ARelativePath, AArtefactType, AHash,
  AHashSha512: string; AFileSize: Int64): TArtefactInfo;
begin
  Result := Default(TArtefactInfo);
  Result.RelativePath := ARelativePath;
  Result.ArtefactType := AArtefactType;
  Result.Hash := AHash;
  Result.HashSha512 := AHashSha512;
  Result.FileSize := AFileSize;
end;

function TBsiTr03183Tests.LoadJson: TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(ReadOutput) as TJSONObject;
  Assert.IsNotNull(Result, 'The written document must be JSON');
end;

function TBsiTr03183Tests.ReadOutput: string;
begin
  Result := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
end;

function TBsiTr03183Tests.SliceBetween(const AText, AStart, AEnd: string): string;
var
  LFrom, LTo: Integer;
begin
  LFrom := Pos(AStart, AText);
  Assert.IsTrue(LFrom > 0, 'Missing ' + AStart);
  LTo := Pos(AEnd, AText, LFrom);
  Assert.IsTrue(LTo > LFrom, 'Missing ' + AEnd + ' after ' + AStart);
  Result := Copy(AText, LFrom, LTo - LFrom);
end;

function TBsiTr03183Tests.PropertyValue(AProperties: TJSONArray; const AName: string): string;
var
  I: Integer;
  LProp: TJSONObject;
begin
  Result := '';
  Assert.IsNotNull(AProperties);
  for I := 0 to AProperties.Count - 1 do
  begin
    LProp := AProperties.Items[I] as TJSONObject;
    if LProp.GetValue<string>('name') = AName then
      Exit(LProp.GetValue<string>('value'));
  end;
  Assert.Fail('Missing property ' + AName);
end;

function TBsiTr03183Tests.FindNamed(AItems: TJSONArray; const AName: string): TJSONObject;
var
  I: Integer;
  LItem: TJSONObject;
begin
  Result := nil;
  if not Assigned(AItems) then
    Exit;
  for I := 0 to AItems.Count - 1 do
  begin
    if not (AItems.Items[I] is TJSONObject) then
      Continue;
    LItem := TJSONObject(AItems.Items[I]);
    if (LItem.GetValue('name') <> nil) and (LItem.GetValue<string>('name') = AName) then
      Exit(LItem);
  end;
end;

procedure TBsiTr03183Tests.Setup;
begin
  FOutputFile := TPath.Combine(TPath.GetTempPath, 'dxcomply-bsi-tr03183.out');
  FArtefacts := TArtefactList.Create;
  FMetadata := Default(TSbomMetadata);
  FMetadata.Timestamp := '2026-08-20T12:00:00Z';
  FMetadata.ToolName := 'DX.Comply';
  FMetadata.ToolVersion := '1.3.0';
  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'TestApp';
  FProjectInfo.Version := '1.0.0';
end;

procedure TBsiTr03183Tests.TearDown;
begin
  if TFile.Exists(FOutputFile) then
    TFile.Delete(FOutputFile);
  FArtefacts.Free;
  FProjectInfo.Free;
end;

procedure TBsiTr03183Tests.Classify_EmailUrlExecutableAndArchive;
var
  LExe, LUnit, LDll, LZip: TArtefactInfo;
begin
  Assert.IsTrue(IsBsiEmailAddress('dev@example.com'));
  Assert.IsFalse(IsBsiEmailAddress('Acme GmbH'));
  Assert.IsFalse(IsBsiEmailAddress('not-an-email'));
  Assert.IsTrue(IsBsiHttpUrl('https://example.com/sbom'));
  Assert.IsTrue(IsBsiHttpUrl('http://example.com'));
  Assert.IsFalse(IsBsiHttpUrl('ftp://example.com/sbom'));
  Assert.IsTrue(IsAcceptableBsiCreator(''));
  Assert.IsFalse(IsAcceptableBsiCreator('Acme GmbH'));
  Assert.AreEqual('email', BsiCreatorKind(' dev@example.com '));
  Assert.AreEqual('url', BsiCreatorKind('https://example.com/sbom'));

  LExe := MakeArtefact('build\TestApp.exe', 'application', '', '', 1);
  LUnit := MakeArtefact('System.SysUtils.pas', 'unit-evidence', '', '', 1);
  LDll := MakeArtefact('vendor.dll', 'external-reference', '', '', -1);
  LZip := MakeArtefact('redist\notes.tar.gz', 'unknown', '', '', 1);

  Assert.AreEqual('TestApp.exe', BsiComponentFileName(LExe.RelativePath));
  Assert.AreEqual('notes.tar.gz', BsiComponentFileName(LZip.RelativePath));
  Assert.AreEqual('executable', BsiExecutableValue(LExe));
  Assert.AreEqual('non-executable', BsiExecutableValue(LUnit));
  Assert.AreEqual('executable', BsiExecutableValue(LDll));
  Assert.AreEqual('archive', BsiArchiveValue(BsiComponentFileName(LZip.RelativePath)));
  Assert.AreEqual('structured', BsiStructuredValue(BsiComponentFileName(LZip.RelativePath)));
  Assert.AreEqual('no archive', BsiArchiveValue('TestApp.exe'));
  Assert.AreEqual('unstructured', BsiStructuredValue('TestApp.exe'));
  Assert.IsTrue(IsBsiArchiveFileName('pack.nupkg'));
  Assert.IsTrue(IsBsiArchiveFileName('image.iso'));
end;

procedure TBsiTr03183Tests.Json_FileComponent_HasSha512AndTrProperties;
var
  LWriter: ISbomWriter;
  LJson, LComponent, LHash, LRef: TJSONObject;
  LHashes, LProperties, LRefs, LRefHashes: TJSONArray;
  LMetaComponent: TJSONObject;
begin
  FArtefacts.Add(MakeArtefact('TestApp.exe', 'application', cSha256, cSha512, 100));
  FArtefacts.Add(MakeArtefact('notes.zip', 'unknown', '', '', 20));
  FArtefacts.Add(MakeArtefact('System.SysUtils.pas', 'unit-evidence', cSha256, cSha512, 30));
  FArtefacts.Add(MakeArtefact('redist\pack.zip', 'unknown', cSha256, cSha512, 40));
  FArtefacts.Add(MakeArtefact('MyPkg.dcp', 'unknown', cSha256, cSha512, 50));

  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    LComponent := (LJson.GetValue('components') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual(Copy(cSha256, 1, 12), LComponent.GetValue<string>('version'),
      'A file with no assigned version keeps the hash prefix');
    LHashes := LComponent.GetValue('hashes') as TJSONArray;
    Assert.AreEqual(NativeInt(2), NativeInt(LHashes.Count));
    LHash := LHashes.Items[0] as TJSONObject;
    Assert.AreEqual('SHA-256', LHash.GetValue<string>('alg'));
    Assert.AreEqual(cSha256, LHash.GetValue<string>('content'));
    LHash := LHashes.Items[1] as TJSONObject;
    Assert.AreEqual('SHA-512', LHash.GetValue<string>('alg'));
    Assert.AreEqual(cSha512, LHash.GetValue<string>('content'));
    LRefs := LComponent.GetValue('externalReferences') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LRefs.Count));
    LRef := LRefs.Items[0] as TJSONObject;
    Assert.AreEqual('distribution', LRef.GetValue<string>('type'));
    Assert.AreEqual('file:TestApp.exe', LRef.GetValue<string>('url'));
    LRefHashes := LRef.GetValue('hashes') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LRefHashes.Count));
    LHash := LRefHashes.Items[0] as TJSONObject;
    Assert.AreEqual('SHA-512', LHash.GetValue<string>('alg'));
    Assert.AreEqual(cSha512, LHash.GetValue<string>('content'));
    LProperties := LComponent.GetValue('properties') as TJSONArray;
    Assert.AreEqual('TestApp.exe', PropertyValue(LProperties, 'bsi:component:filename'));
    Assert.AreEqual('executable', PropertyValue(LProperties, 'bsi:component:executable'));
    Assert.AreEqual('no archive', PropertyValue(LProperties, 'bsi:component:archive'));
    Assert.AreEqual('unstructured', PropertyValue(LProperties, 'bsi:component:structured'));
    Assert.IsTrue(Pos('file:size', LComponent.ToString) <
      Pos('bsi:component:filename', LComponent.ToString));

    LComponent := (LJson.GetValue('components') as TJSONArray).Items[1] as TJSONObject;
    Assert.IsNull(LComponent.GetValue('hashes'), 'A zip without a hash must not invent one');
    Assert.IsNull(LComponent.GetValue('externalReferences'),
      'A file without a SHA-512 has no distribution reference');
    LProperties := LComponent.GetValue('properties') as TJSONArray;
    Assert.AreEqual('notes.zip', PropertyValue(LProperties, 'bsi:component:filename'));
    Assert.AreEqual('non-executable', PropertyValue(LProperties, 'bsi:component:executable'));
    Assert.AreEqual('archive', PropertyValue(LProperties, 'bsi:component:archive'));
    Assert.AreEqual('structured', PropertyValue(LProperties, 'bsi:component:structured'));

    LComponent := (LJson.GetValue('components') as TJSONArray).Items[2] as TJSONObject;
    LProperties := LComponent.GetValue('properties') as TJSONArray;
    Assert.AreEqual('non-executable', PropertyValue(LProperties, 'bsi:component:executable'));
    Assert.IsNull(LComponent.GetValue('externalReferences'),
      'Unit evidence is not a deployable file');

    LComponent := (LJson.GetValue('components') as TJSONArray).Items[3] as TJSONObject;
    LRefs := LComponent.GetValue('externalReferences') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LRefs.Count));
    Assert.AreEqual('distribution', (LRefs.Items[0] as TJSONObject).GetValue<string>('type'));
    Assert.AreEqual('file:redist\pack.zip', (LRefs.Items[0] as TJSONObject).GetValue<string>('url'));
    LHashes := LComponent.GetValue('hashes') as TJSONArray;
    Assert.AreEqual(NativeInt(2), NativeInt(LHashes.Count));

    LComponent := (LJson.GetValue('components') as TJSONArray).Items[4] as TJSONObject;
    Assert.IsNotNull(LComponent.GetValue('hashes'), 'A DCP still keeps component hashes');
    Assert.IsNull(LComponent.GetValue('externalReferences'),
      'A DCP is not the deployable file');

    LMetaComponent := (LJson.GetValue('metadata') as TJSONObject).GetValue('component') as TJSONObject;
    Assert.IsNull(LMetaComponent.GetValue('properties'),
      'The primary component is logical and has no file properties in this test');
    Assert.IsNull((LJson.GetValue('metadata') as TJSONObject).GetValue('manufacturer'));
    Assert.IsNull((LJson.GetValue('metadata') as TJSONObject).GetValue('manufacture'));
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Json_MissingDll_OmitsHashes_KeepsTrProperties;
var
  LWriter: ISbomWriter;
  LJson, LComponent: TJSONObject;
  LProperties: TJSONArray;
  LArtefact: TArtefactInfo;
begin
  LArtefact := MakeArtefact('vendor.dll', 'external-reference', '', '', -1);
  LArtefact.Evidence := 'DLL';
  LArtefact.Confidence := 'Source-scan';
  FArtefacts.Add(LArtefact);

  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    LComponent := (LJson.GetValue('components') as TJSONArray).Items[0] as TJSONObject;
    Assert.IsNull(LComponent.GetValue('hashes'));
    Assert.IsNull(LComponent.GetValue('externalReferences'));
    Assert.IsNull(LComponent.GetValue('version'));
    LProperties := LComponent.GetValue('properties') as TJSONArray;
    Assert.AreEqual('vendor.dll', PropertyValue(LProperties, 'bsi:component:filename'));
    Assert.AreEqual('executable', PropertyValue(LProperties, 'bsi:component:executable'));
    Assert.AreEqual('DLL', PropertyValue(LProperties, 'net.developer-experts.dx-comply:evidence'));
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Json_CreatorEmail_WritesManufacturerAndIncomplete;
var
  LWriter: ISbomWriter;
  LJson, LManufacture, LContact, LComposition: TJSONObject;
  LContacts, LCompositions, LDeps: TJSONArray;
begin
  FMetadata.SbomCreator := 'sbom@example.com';
  FArtefacts.Add(MakeArtefact('TestApp.exe', 'application', cSha256, cSha512, 10));
  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    Assert.IsNull((LJson.GetValue('metadata') as TJSONObject).GetValue('manufacture'),
      'The deprecated manufacture element is not written');
    LManufacture := (LJson.GetValue('metadata') as TJSONObject).GetValue('manufacturer') as TJSONObject;
    Assert.IsNotNull(LManufacture);
    Assert.IsNull(LManufacture.GetValue('name'), 'An email contact must not invent a name');
    LContacts := LManufacture.GetValue('contact') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LContacts.Count));
    LContact := LContacts.Items[0] as TJSONObject;
    Assert.AreEqual('sbom@example.com', LContact.GetValue<string>('email'));

    LCompositions := LJson.GetValue('compositions') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LCompositions.Count));
    LComposition := LCompositions.Items[0] as TJSONObject;
    Assert.AreEqual('incomplete', LComposition.GetValue<string>('aggregate'));
    LDeps := LComposition.GetValue('dependencies') as TJSONArray;
    Assert.AreEqual('TestApp', LDeps.Items[0].Value);
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Json_CreatorUrl_WritesManufacturerUrl;
var
  LWriter: ISbomWriter;
  LJson, LManufacture: TJSONObject;
  LUrls: TJSONArray;
begin
  FMetadata.SbomCreator := 'https://example.com/sbom';
  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    Assert.IsNull((LJson.GetValue('metadata') as TJSONObject).GetValue('manufacture'));
    LManufacture := (LJson.GetValue('metadata') as TJSONObject).GetValue('manufacturer') as TJSONObject;
    LUrls := LManufacture.GetValue('url') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LUrls.Count));
    Assert.AreEqual('https://example.com/sbom', LUrls.Items[0].Value);
    Assert.IsNull(LManufacture.GetValue('contact'));
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Json_EmptyCreator_OmitsManufacturer;
var
  LWriter: ISbomWriter;
  LJson: TJSONObject;
begin
  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    Assert.IsNull((LJson.GetValue('metadata') as TJSONObject).GetValue('manufacturer'));
    Assert.IsNull((LJson.GetValue('metadata') as TJSONObject).GetValue('manufacture'));
    Assert.IsNotNull(LJson.GetValue('compositions'));
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Xml_FileComponent_HashAndPropertyOrder;
var
  LWriter: ISbomWriter;
  LContent, LComponent, LRefs: string;
  LHash256, LHash512, LPurl, LFileName, LExecutable, LExt: Integer;
begin
  FArtefacts.Add(MakeArtefact('TestApp.exe', 'application', cSha256, cSha512, 100));
  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LContent := ReadOutput;
  LComponent := SliceBetween(LContent, 'bom-ref="comp-0"', '</component>');
  LHash256 := Pos('<hash alg="SHA-256">' + cSha256 + '</hash>', LComponent);
  LHash512 := Pos('<hash alg="SHA-512">' + cSha512 + '</hash>', LComponent);
  LPurl := Pos('<purl>', LComponent);
  LExt := Pos('<externalReferences>', LComponent);
  LFileName := Pos('<property name="bsi:component:filename">TestApp.exe</property>', LComponent);
  LExecutable := Pos('<property name="bsi:component:executable">executable</property>', LComponent);
  Assert.IsTrue(LHash256 > 0, LComponent);
  Assert.IsTrue(LHash256 < LHash512, LComponent);
  Assert.IsTrue(LHash512 < LPurl, LComponent);
  Assert.IsTrue(LPurl < LExt, LComponent);
  Assert.IsTrue(LExt < LFileName, LComponent);
  LRefs := SliceBetween(LComponent, '<externalReferences>', '</externalReferences>');
  Assert.IsTrue(Pos('<reference type="distribution">', LRefs) > 0, LRefs);
  Assert.IsTrue(Pos('<url>file:TestApp.exe</url>', LRefs) <
    Pos('<hash alg="SHA-512">' + cSha512 + '</hash>', LRefs), LRefs);
  Assert.IsTrue(LFileName < LExecutable, LComponent);
  Assert.IsTrue(LExecutable < Pos('<property name="bsi:component:archive">no archive</property>', LComponent),
    LComponent);
  Assert.IsTrue(Pos('<property name="bsi:component:archive">no archive</property>', LComponent) <
    Pos('<property name="bsi:component:structured">unstructured</property>', LComponent), LComponent);
  Assert.IsTrue(Pos('<aggregate>incomplete</aggregate>', LContent) > 0);
  Assert.IsTrue(Pos('<compositions>', LContent) > Pos('</dependencies>', LContent));
  Assert.IsTrue(Pos('<dependency ref="TestApp"/>', LContent) > Pos('<compositions>', LContent));
end;

procedure TBsiTr03183Tests.Xml_CreatorEmail_FollowsMetadataComponent;
var
  LWriter: ISbomWriter;
  LContent, LMeta, LManufacture: string;
begin
  FMetadata.SbomCreator := 'sbom@example.com';
  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LContent := ReadOutput;
  LMeta := SliceBetween(LContent, '<metadata>', '</metadata>');
  Assert.IsTrue(Pos('</component>', LMeta) < Pos('<manufacturer>', LMeta), LMeta);
  Assert.AreEqual(0, Pos('<manufacture>', LMeta), LMeta);
  LManufacture := SliceBetween(LMeta, '<manufacturer>', '</manufacturer>');
  Assert.IsTrue(Pos('<email>sbom@example.com</email>', LManufacture) > 0, LManufacture);
  Assert.AreEqual(0, Pos('<name>', LManufacture), LManufacture);
end;

procedure TBsiTr03183Tests.Xml_CreatorUrl_WritesManufacturerUrl;
var
  LWriter: ISbomWriter;
  LMeta: string;
begin
  FMetadata.SbomCreator := 'https://example.com/sbom';
  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LMeta := SliceBetween(ReadOutput, '<metadata>', '</metadata>');
  Assert.IsTrue(Pos('<manufacturer>', LMeta) > Pos('</component>', LMeta), LMeta);
  Assert.AreEqual(0, Pos('<manufacture>', LMeta), LMeta);
  Assert.IsTrue(Pos('<url>https://example.com/sbom</url>',
    SliceBetween(LMeta, '<manufacturer>', '</manufacturer>')) > 0, LMeta);
end;

procedure TBsiTr03183Tests.Spdx_FileComponent_HasSha512FileNameAndComment;
var
  LWriter: ISbomWriter;
  LJson, LPackage, LChecksum: TJSONObject;
  LChecksums: TJSONArray;
begin
  FArtefacts.Add(MakeArtefact('TestApp.exe', 'application', cSha256, cSha512, 100));
  FArtefacts.Add(MakeArtefact('notes.zip', 'unknown', cSha256, '', 20));
  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    LPackage := (LJson.GetValue('packages') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('TestApp.exe', LPackage.GetValue<string>('packageFileName'));
    Assert.AreEqual(Copy(cSha256, 1, 12), LPackage.GetValue<string>('versionInfo'));
    Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('licenseConcluded'));
    Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('licenseDeclared'));
    Assert.AreEqual(
      'bsi:component:executable=executable; bsi:component:archive=no archive; ' +
      'bsi:component:structured=unstructured',
      LPackage.GetValue<string>('comment'));
    LChecksums := LPackage.GetValue('checksums') as TJSONArray;
    Assert.AreEqual(NativeInt(2), NativeInt(LChecksums.Count));
    LChecksum := LChecksums.Items[0] as TJSONObject;
    Assert.AreEqual('SHA256', LChecksum.GetValue<string>('algorithm'));
    LChecksum := LChecksums.Items[1] as TJSONObject;
    Assert.AreEqual('SHA512', LChecksum.GetValue<string>('algorithm'));
    Assert.AreEqual(cSha512, LChecksum.GetValue<string>('checksumValue'));

    LPackage := (LJson.GetValue('packages') as TJSONArray).Items[1] as TJSONObject;
    Assert.AreEqual(
      'bsi:component:executable=non-executable; bsi:component:archive=archive; ' +
      'bsi:component:structured=structured',
      LPackage.GetValue<string>('comment'));
    LChecksums := LPackage.GetValue('checksums') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LChecksums.Count));
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Spdx_CreatorEmail_AddsPerson;
var
  LWriter: ISbomWriter;
  LJson: TJSONObject;
  LCreators: TJSONArray;
begin
  FMetadata.SbomCreator := 'sbom@example.com';
  FMetadata.Supplier := 'Acme GmbH';
  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    LCreators := ((LJson.GetValue('creationInfo') as TJSONObject).GetValue('creators')) as TJSONArray;
    Assert.AreEqual(NativeInt(3), NativeInt(LCreators.Count));
    Assert.AreEqual('Organization: Acme GmbH', LCreators.Items[1].Value);
    Assert.AreEqual('Person: sbom@example.com (sbom@example.com)', LCreators.Items[2].Value);
    Assert.IsNull((LJson.GetValue('creationInfo') as TJSONObject).GetValue('comment'));
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Spdx_CreatorUrl_AddsComment;
var
  LWriter: ISbomWriter;
  LJson, LInfo: TJSONObject;
begin
  FMetadata.SbomCreator := 'https://example.com/sbom';
  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    LInfo := LJson.GetValue('creationInfo') as TJSONObject;
    Assert.AreEqual('SBOM creator URL: https://example.com/sbom', LInfo.GetValue<string>('comment'));
    Assert.AreEqual(NativeInt(1), NativeInt((LInfo.GetValue('creators') as TJSONArray).Count));
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Schema_AcceptsSha512_RejectsShortValue;
var
  LJsonWriter, LXmlWriter: ISbomWriter;
  LValidator: TSbomValidator;
  LResult: TValidationResult;
  LContent: string;
  I: Integer;
  LErrors: string;
begin
  FArtefacts.Add(MakeArtefact('TestApp.exe', 'application', cSha256, cSha512, 100));
  FMetadata.SbomCreator := 'sbom@example.com';
  LValidator := TSbomValidator.Create;
  try
    LJsonWriter := TCycloneDxJsonWriter.Create;
    Assert.IsTrue(LJsonWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
    LResult := LValidator.ValidateCycloneDxJson(ReadOutput);
    LErrors := '';
    for I := 0 to High(LResult.Errors) do
      LErrors := LErrors + LResult.Errors[I] + sLineBreak;
    Assert.IsTrue(LResult.IsValid, LErrors);

    LContent := StringReplace(ReadOutput, cSha512, 'abcd', []);
    LResult := LValidator.ValidateCycloneDxJson(LContent);
    Assert.IsFalse(LResult.IsValid, 'A short SHA-512 value must be rejected');

    LXmlWriter := TCycloneDxXmlWriter.Create;
    Assert.IsTrue(LXmlWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
    LResult := LValidator.ValidateCycloneDxXml(ReadOutput);
    LErrors := '';
    for I := 0 to High(LResult.Errors) do
      LErrors := LErrors + LResult.Errors[I] + sLineBreak;
    Assert.IsTrue(LResult.IsValid, LErrors);

    LContent := StringReplace(ReadOutput, cSha512, 'abcd', []);
    LResult := LValidator.ValidateCycloneDxXml(LContent);
    Assert.IsFalse(LResult.IsValid, 'A short XML SHA-512 value must be rejected');

    Assert.IsTrue(TSpdxJsonWriter.Create.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
    LResult := LValidator.ValidateSpdxJson(ReadOutput);
    LErrors := '';
    for I := 0 to High(LResult.Errors) do
      LErrors := LErrors + LResult.Errors[I] + sLineBreak;
    Assert.IsTrue(LResult.IsValid, LErrors);
  finally
    LValidator.Free;
  end;
end;

procedure TBsiTr03183Tests.Manifest_Library_HasCreatorVersionLicence_NotFileFields;
const
  cManifest =
    '{"components":[' +
    '{"name":"MailLib","version":"1.2.3","vendor":"dev@example.com",' +
    '"vendor_url":"https://example.com/maillib","licence":"MIT","type":"library",' +
    '"units_exact":["MailUnit"]},' +
    '{"name":"PayLib","version":"9.0","vendor":"Pay Vendor","licence":"Commercial",' +
    '"type":"library","units_exact":["PayUnit"]}' +
    ']}';
var
  LJsonWriter, LXmlWriter, LSpdxWriter: ISbomWriter;
  LJson, LLibrary, LSupplier, LLicense, LPackage, LRef: TJSONObject;
  LContacts, LRefs, LLicences: TJSONArray;
  LContent, LLibraryXml: string;
  I: Integer;
  LSawWebsite: Boolean;
begin
  FMetadata.ComponentManifestJson := cManifest;
  FArtefacts.Add(MakeArtefact('TestApp.exe', 'application', cSha256, cSha512, 10));
  FArtefacts.Add(MakeArtefact('MailUnit.pas', 'unit-evidence', cSha256, cSha512, 10));
  FArtefacts.Add(MakeArtefact('PayUnit.pas', 'unit-evidence', cSha256, cSha512, 10));

  LJsonWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LJsonWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    LLibrary := FindNamed(LJson.GetValue('components') as TJSONArray, 'MailLib');
    Assert.IsNotNull(LLibrary);
    Assert.AreEqual('1.2.3', LLibrary.GetValue<string>('version'));
    Assert.IsNull(LLibrary.GetValue('hashes'));
    Assert.IsNull(LLibrary.GetValue('properties'),
      'A manifest library is a logical component and has no file properties');
    LSupplier := LLibrary.GetValue('supplier') as TJSONObject;
    LContacts := LSupplier.GetValue('contact') as TJSONArray;
    Assert.AreEqual('dev@example.com',
      (LContacts.Items[0] as TJSONObject).GetValue<string>('email'));
    LLicences := LLibrary.GetValue('licenses') as TJSONArray;
    Assert.AreEqual(NativeInt(2), NativeInt(LLicences.Count));
    LLicense := (LLicences.Items[0] as TJSONObject).GetValue('license') as TJSONObject;
    Assert.AreEqual('MIT', LLicense.GetValue<string>('id'));
    Assert.AreEqual('concluded', LLicense.GetValue<string>('acknowledgement'));
    LLicense := (LLicences.Items[1] as TJSONObject).GetValue('license') as TJSONObject;
    Assert.AreEqual('MIT', LLicense.GetValue<string>('id'));
    Assert.AreEqual('declared', LLicense.GetValue<string>('acknowledgement'));
    Assert.IsNull(LLibrary.GetValue('hashes'));
    LRefs := LLibrary.GetValue('externalReferences') as TJSONArray;
    Assert.AreEqual('website', (LRefs.Items[0] as TJSONObject).GetValue<string>('type'));

    LLibrary := FindNamed(LJson.GetValue('components') as TJSONArray, 'PayLib');
    LLicences := LLibrary.GetValue('licenses') as TJSONArray;
    Assert.AreEqual(NativeInt(2), NativeInt(LLicences.Count));
    LLicense := (LLicences.Items[0] as TJSONObject).GetValue('license') as TJSONObject;
    Assert.AreEqual('Commercial', LLicense.GetValue<string>('name'));
    Assert.AreEqual('concluded', LLicense.GetValue<string>('acknowledgement'));
    Assert.IsNull(LLicense.GetValue('id'));
    LLicense := (LLicences.Items[1] as TJSONObject).GetValue('license') as TJSONObject;
    Assert.AreEqual('declared', LLicense.GetValue<string>('acknowledgement'));
    Assert.IsNull((LLibrary.GetValue('supplier') as TJSONObject).GetValue('contact'));
  finally
    LJson.Free;
  end;

  LXmlWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LXmlWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LContent := ReadOutput;
  LLibraryXml := SliceBetween(LContent, 'bom-ref="manifest-0"', '</component>');
  Assert.IsTrue(Pos('<version>1.2.3</version>', LLibraryXml) > 0, LLibraryXml);
  Assert.IsTrue(Pos('<license acknowledgement="concluded">', LLibraryXml) <
    Pos('<id>MIT</id>', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<license acknowledgement="declared">', LLibraryXml) >
    Pos('<license acknowledgement="concluded">', LLibraryXml), LLibraryXml);
  Assert.AreEqual(0, Pos('type="distribution"', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<email>dev@example.com</email>', LLibraryXml) >
    Pos('</name>', LLibraryXml), LLibraryXml);
  Assert.AreEqual(0, Pos('bsi:component:filename', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<name>Commercial</name>', LContent) > 0);

  LSpdxWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LSpdxWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := LoadJson;
  try
    LPackage := FindNamed(LJson.GetValue('packages') as TJSONArray, 'MailLib');
    Assert.IsNotNull(LPackage);
    Assert.AreEqual('1.2.3', LPackage.GetValue<string>('versionInfo'));
    Assert.AreEqual('MIT', LPackage.GetValue<string>('licenseDeclared'));
    Assert.AreEqual('MIT', LPackage.GetValue<string>('licenseConcluded'));
    Assert.AreEqual('Person: dev@example.com (dev@example.com)',
      LPackage.GetValue<string>('originator'));
    Assert.IsNull(LPackage.GetValue('packageFileName'));
    Assert.IsNull(LPackage.GetValue('comment'));
    LRefs := LPackage.GetValue('externalRefs') as TJSONArray;
    LSawWebsite := False;
    for I := 0 to LRefs.Count - 1 do
    begin
      LRef := LRefs.Items[I] as TJSONObject;
      if LRef.GetValue<string>('referenceType') = 'website' then
      begin
        LSawWebsite := True;
        Assert.AreEqual('https://example.com/maillib', LRef.GetValue<string>('referenceLocator'));
        Assert.AreEqual('OTHER', LRef.GetValue<string>('referenceCategory'));
      end;
    end;
    Assert.IsTrue(LSawWebsite, 'vendor_url must be an SPDX website reference');

    LPackage := FindNamed(LJson.GetValue('packages') as TJSONArray, 'PayLib');
    Assert.AreEqual('Organization: Pay Vendor', LPackage.GetValue<string>('originator'));
    Assert.IsTrue(LPackage.GetValue<string>('licenseDeclared').StartsWith('LicenseRef-'),
      LPackage.GetValue<string>('licenseDeclared'));
  finally
    LJson.Free;
  end;
end;

procedure TBsiTr03183Tests.Cli_SbomCreator_AcceptsEmailAndUrl;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--sbom-creator=sbom@example.com')));
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('sbom@example.com', LConfig.SbomCreator);
    Assert.IsTrue(scoSbomCreator in LConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;

  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--sbom-creator=https://example.com/sbom')));
    Assert.AreEqual('https://example.com/sbom', LOptions.ToSbomConfig.SbomCreator);
  finally
    LOptions.Free;
  end;

  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--sbom-creator=')));
    Assert.IsTrue(Pos('sbom-creator', LOptions.ParseError) > 0, LOptions.ParseError);
  finally
    LOptions.Free;
  end;

  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--sbom-creator=Acme GmbH')));
    Assert.IsTrue(Pos('email', LOptions.ParseError) > 0, LOptions.ParseError);
  finally
    LOptions.Free;
  end;
end;

procedure TBsiTr03183Tests.Config_SbomCreator_TrimsAndKeepsInvalidText;
var
  LGen: TDxComplyGenerator;
  LPath: string;
  LConfig: TSbomConfig;
begin
  LPath := TPath.Combine(TPath.GetTempPath, 'dxcomply-bsi-tr03183.json');
  LGen := TDxComplyGenerator.Create;
  try
    TFile.WriteAllText(LPath, '{"sbomCreator":"  sbom@example.com  "}', TEncoding.UTF8);
    LConfig := LGen.LoadConfig(LPath);
    Assert.AreEqual('sbom@example.com', LConfig.SbomCreator);

    TFile.WriteAllText(LPath, '{"sbomCreator":"   "}', TEncoding.UTF8);
    LConfig := LGen.LoadConfig(LPath);
    Assert.AreEqual('', LConfig.SbomCreator);

    TFile.WriteAllText(LPath, '{"sbomCreator":"  Acme GmbH  "}', TEncoding.UTF8);
    LConfig := LGen.LoadConfig(LPath);
    Assert.AreEqual('Acme GmbH', LConfig.SbomCreator);
  finally
    LGen.Free;
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
  end;
end;

procedure TBsiTr03183Tests.Generate_InvalidSbomCreator_Stops;
var
  LGen: TDxComplyGenerator;
  LConfig: TSbomConfig;
  LMessages: TStringList;
begin
  LConfig := TSbomConfig.Default;
  LConfig.SbomCreator := 'Acme GmbH';
  LMessages := TStringList.Create;
  LGen := TDxComplyGenerator.Create(LConfig);
  try
    LGen.OnProgress := procedure(const AMessage: string; const AProgress: Integer)
      begin
        LMessages.Add(AMessage);
      end;
    Assert.IsFalse(LGen.Generate('missing.dproj'));
    Assert.IsTrue(LMessages.Count > 0, 'Generate must report the rejected creator');
    Assert.IsTrue(Pos('sbomCreator', LMessages[0]) > 0, LMessages.Text);
  finally
    LGen.Free;
    LMessages.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBsiTr03183Tests);

end.
