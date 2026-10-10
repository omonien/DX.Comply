/// <summary>
/// DX.Comply.Tests.CycloneDx.XmlWriter
/// DUnitX tests for TCycloneDxXmlWriter.
/// </summary>
///
/// <remarks>
/// Verifies CycloneDX 1.6 XML output: namespace, required elements,
/// component entries, hash embedding, metadata, dependency section,
/// serial-number uniqueness, validation logic, and XML escaping.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.CycloneDx.XmlWriter;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.CycloneDx.XmlWriter,
  DX.Comply.Engine.Intf,
  DX.Comply.Schema.Validator,
  DX.Comply.VersionInfo;

type
  [TestFixture]
  TCycloneDxXmlWriterTests = class
  private
    FWriter: ISbomWriter;
    FOutputFile: string;
    FArtefacts: TArtefactList;
    FMetadata: TSbomMetadata;
    FProjectInfo: TProjectInfo;
    function LoadOutputContent: string;
    function MakeArtefact(const ARelativePath, AArtefactType, AHash: string;
      AFileSize: Int64): TArtefactInfo;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetFormat_ReturnsCycloneDxXml;

    [Test]
    procedure Write_EmptyArtefacts_CreatesFile;

    [Test]
    procedure Write_ContainsXmlDeclaration;

    [Test]
    procedure Write_ContainsCycloneDxNamespace;

    [Test]
    procedure Write_ContainsSerialNumber;

    [Test]
    procedure Write_ContainsMetadata;

    [Test]
    procedure Write_ContainsTimestamp;

    [Test]
    procedure Write_ContainsToolInfo;

    [Test]
    procedure Write_ContainsDxComplyProperties;

    [Test]
    procedure Write_SingleArtefact_ContainsComponent;

    [Test]
    procedure Write_SingleArtefact_ContainsHash;

    [Test]
    procedure Write_ContainsDependencies;

    [Test]
    procedure Write_Dependencies_GroupedUnderDeliverable;

    /// <summary>
    /// A source-scanned DLL has no file on disk. Evidence, confidence and
    /// the conditional flag must still be written. Issue #45.
    /// </summary>
    [Test]
    procedure Write_ExternalDll_MissingFile_KeepsEvidence;

    [Test]
    procedure Validate_ValidXml_ReturnsTrue;

    [Test]
    procedure Validate_InvalidXml_ReturnsFalse;

    [Test]
    procedure Validate_EmptyString_ReturnsFalse;

    [Test]
    procedure Write_SpecialChars_AreEscaped;

    /// <summary>
    /// Metadata children must follow the CycloneDX 1.6 sequence.
    /// The metadata component may contain its own properties element, so the
    /// check uses the properties element that is a direct child of metadata.
    /// </summary>
    [Test]
    procedure Write_MetadataElementOrder_MatchesSchema;

    /// <summary>
    /// The product licence sits between version and properties on the
    /// metadata component. An empty licence writes no licenses element.
    /// </summary>
    [Test]
    procedure Write_RootLicence_BetweenVersionAndProperties;

    /// <summary>Component hashes must precede purl.</summary>
    [Test]
    procedure Write_ComponentElementOrder_HashesBeforePurl;

    /// <summary>A document with the old element order must fail validation.</summary>
    [Test]
    procedure Validate_OutOfOrderElements_ReturnsFalse;
  end;

implementation

{ TCycloneDxXmlWriterTests }

procedure TCycloneDxXmlWriterTests.Setup;
begin
  FWriter := TCycloneDxXmlWriter.Create;
  FOutputFile := TPath.Combine(TPath.GetTempPath, 'test_bom_' +
    FormatDateTime('yyyymmddhhnnsszzz', Now) + '.xml');

  FArtefacts := TArtefactList.Create;

  FMetadata.ProductName := 'TestProduct';
  FMetadata.ProductVersion := '1.0.0';
  FMetadata.Supplier := 'Test GmbH';
  FMetadata.SupplierUrl := '';
  FMetadata.Licence := '';
  FMetadata.Timestamp := '2026-02-24T10:00:00+01:00';
  FMetadata.ToolName := 'DX.Comply';
  FMetadata.ToolVersion := '';
  // DUnitX reuses one fixture instance. Drop property arrays left by an earlier test.
  SetLength(FMetadata.Properties, 0);
  SetLength(FMetadata.ComponentProperties, 0);

  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'TestProject';
  FProjectInfo.ProjectPath := 'C:\Projects\TestProject.dproj';
  FProjectInfo.ProjectDir := 'C:\Projects';
  FProjectInfo.Platform := 'Win32';
  FProjectInfo.Configuration := 'Release';
  FProjectInfo.OutputDir := 'C:\Projects\build\Win32\Release';
  FProjectInfo.Version := '1.0.0.0';
end;

procedure TCycloneDxXmlWriterTests.TearDown;
begin
  FArtefacts.Free;
  FProjectInfo.Free;
  if TFile.Exists(FOutputFile) then
    TFile.Delete(FOutputFile);
end;

function TCycloneDxXmlWriterTests.LoadOutputContent: string;
var
  LList: TStringList;
begin
  LList := TStringList.Create;
  try
    LList.LoadFromFile(FOutputFile, TEncoding.UTF8);
    Result := LList.Text;
  finally
    LList.Free;
  end;
end;

function TCycloneDxXmlWriterTests.MakeArtefact(const ARelativePath, AArtefactType,
  AHash: string; AFileSize: Int64): TArtefactInfo;
begin
  Result := Default(TArtefactInfo);
  Result.FilePath := 'C:\Projects\build\' + ARelativePath;
  Result.RelativePath := ARelativePath;
  Result.ArtefactType := AArtefactType;
  Result.Hash := AHash;
  Result.FileSize := AFileSize;
end;

procedure TCycloneDxXmlWriterTests.GetFormat_ReturnsCycloneDxXml;
begin
  Assert.AreEqual(Ord(sfCycloneDxXml), Ord(FWriter.GetFormat));
end;

procedure TCycloneDxXmlWriterTests.Write_EmptyArtefacts_CreatesFile;
begin
  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  Assert.IsTrue(TFile.Exists(FOutputFile));
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsXmlDeclaration;
var
  LContent: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(LContent.StartsWith('<?xml version="1.0"'));
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsCycloneDxNamespace;
var
  LContent: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(Pos('http://cyclonedx.org/schema/bom/1.6', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsSerialNumber;
var
  LContent: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(Pos('serialNumber="urn:uuid:', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsMetadata;
var
  LContent: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(Pos('<metadata>', LContent) > 0);
  Assert.IsTrue(Pos('</metadata>', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsTimestamp;
var
  LContent: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  // The +01:00 input is written as UTC with a Z suffix.
  Assert.IsTrue(Pos('<timestamp>2026-02-24T09:00:00Z</timestamp>', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsToolInfo;
var
  LContent: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(Pos('<name>DX.Comply</name>', LContent) > 0);
  Assert.IsTrue(Pos('<vendor>Olaf Monien</vendor>', LContent) > 0);
  Assert.IsTrue(Pos('<version>' + GetDxComplyToolVersion + '</version>', LContent) > 0,
    'The tool version must come from the running module');
end;

function MetadataDirectChildPos(const AMetadata, AElementName: string): Integer;
var
  I: Integer;
  J: Integer;
  LDepth: Integer;
  LName: string;
  LQuote: Char;
  LSelfClosing: Boolean;
begin
  // 1-based position of an opening tag that is a direct child of <metadata>.
  // Nested elements, including properties inside metadata/component, are ignored.
  Result := 0;
  LDepth := 0;
  I := 1;
  while I <= Length(AMetadata) do
  begin
    if AMetadata[I] <> '<' then
    begin
      Inc(I);
      Continue;
    end;

    if (I < Length(AMetadata)) and (AMetadata[I + 1] = '/') then
    begin
      if LDepth > 0 then
        Dec(LDepth);
      Inc(I);
      Continue;
    end;

    if (I < Length(AMetadata)) and
      ((AMetadata[I + 1] = '!') or (AMetadata[I + 1] = '?')) then
    begin
      Inc(I);
      Continue;
    end;

    J := I + 1;
    while (J <= Length(AMetadata)) and
      (AMetadata[J] <> ' ') and (AMetadata[J] <> #9) and
      (AMetadata[J] <> #10) and (AMetadata[J] <> #13) and
      (AMetadata[J] <> '>') and (AMetadata[J] <> '/') do
      Inc(J);
    LName := Copy(AMetadata, I + 1, J - I - 1);

    LSelfClosing := False;
    LQuote := #0;
    while (J <= Length(AMetadata)) and (AMetadata[J] <> '>') do
    begin
      if LQuote <> #0 then
      begin
        if AMetadata[J] = LQuote then
          LQuote := #0;
      end
      else if (AMetadata[J] = '"') or (AMetadata[J] = '''') then
        LQuote := AMetadata[J]
      else if AMetadata[J] = '/' then
        LSelfClosing := True;
      Inc(J);
    end;

    if (LDepth = 1) and SameText(LName, AElementName) then
      Exit(I);

    if not LSelfClosing then
      Inc(LDepth);
    if J <= Length(AMetadata) then
      I := J + 1
    else
      I := J;
  end;
end;

procedure TCycloneDxXmlWriterTests.Write_MetadataElementOrder_MatchesSchema;
var
  LComponent, LComponentAt, LContent, LMetadata, LNameAt, LPropertiesAt, LSupplierAt, LToolsAt: string;
  LComponentEnd, LComponentStart, LMetaEnd, LMetaStart, LPropertiesPos: Integer;
begin
  SetLength(FMetadata.Properties, 1);
  FMetadata.Properties[0] := TSbomProperty.Create('dx:profile', 'cra');
  // Component properties are nested inside metadata/component. They must not
  // be treated as the metadata-level properties element.
  SetLength(FMetadata.ComponentProperties, 1);
  FMetadata.ComponentProperties[0] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:build.configuration', 'Release');
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;

  LMetaStart := Pos('<metadata>', LContent);
  LMetaEnd := Pos('</metadata>', LContent);
  Assert.IsTrue((LMetaStart > 0) and (LMetaEnd > LMetaStart),
    'The document must contain a metadata element');
  LMetadata := Copy(LContent, LMetaStart, LMetaEnd - LMetaStart);

  LToolsAt := IntToStr(Pos('<tools>', LMetadata));
  LComponentAt := IntToStr(Pos('<component ', LMetadata));
  LPropertiesPos := MetadataDirectChildPos(LMetadata, 'properties');
  LPropertiesAt := IntToStr(LPropertiesPos);
  Assert.IsTrue(Pos('<tools>', LMetadata) < Pos('<component ', LMetadata),
    'metadata tools must precede metadata component. tools at ' + LToolsAt +
    ', component at ' + LComponentAt);
  Assert.IsTrue(LPropertiesPos > 0,
    'metadata must contain a properties element that is a direct child. properties at ' +
    LPropertiesAt);
  Assert.IsTrue(Pos('</component>', LMetadata) < LPropertiesPos,
    'metadata properties must follow the metadata component. properties at ' + LPropertiesAt);

  // <tools><tool><name> sits before the metadata component, so supplier and
  // name must be compared inside that component. CycloneDX 1.6 places
  // supplier before name there.
  LComponentStart := Pos('<component ', LMetadata);
  LComponentEnd := Pos('</component>', LMetadata);
  Assert.IsTrue((LComponentStart > 0) and (LComponentEnd > LComponentStart),
    'metadata must contain a component element');
  LComponent := Copy(LMetadata, LComponentStart,
    LComponentEnd - LComponentStart + Length('</component>'));
  LSupplierAt := IntToStr(Pos('<supplier>', LComponent));
  LNameAt := IntToStr(Pos('<name>', LComponent));
  Assert.IsTrue((Pos('<supplier>', LComponent) > 0) and
    (Pos('<supplier>', LComponent) < Pos('<name>', LComponent)),
    'component supplier must precede name. supplier at ' + LSupplierAt +
    ', name at ' + LNameAt);
  Assert.AreEqual(NativeInt(0), NativeInt(Length(CycloneDxXmlSequenceErrors(LContent))),
    'The written document must satisfy the CycloneDX 1.6 element order');
end;

procedure TCycloneDxXmlWriterTests.Write_RootLicence_BetweenVersionAndProperties;
var
  LComponent, LContent, LMetadata: string;
  LComponentEnd, LComponentStart, LMetaEnd, LMetaStart: Integer;
  LLicencesAt, LPropertiesAt, LVersionAt: Integer;
begin
  FMetadata.Supplier := 'Test GmbH';
  FMetadata.Licence := 'MIT';
  SetLength(FMetadata.ComponentProperties, 1);
  FMetadata.ComponentProperties[0] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:build.configuration', 'Release');
  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LContent := LoadOutputContent;

  LMetaStart := Pos('<metadata>', LContent);
  LMetaEnd := Pos('</metadata>', LContent);
  Assert.IsTrue((LMetaStart > 0) and (LMetaEnd > LMetaStart),
    'The document must contain a metadata element');
  LMetadata := Copy(LContent, LMetaStart, LMetaEnd - LMetaStart);
  LComponentStart := Pos('<component ', LMetadata);
  LComponentEnd := Pos('</component>', LMetadata);
  Assert.IsTrue((LComponentStart > 0) and (LComponentEnd > LComponentStart),
    'metadata must contain a component element');
  LComponent := Copy(LMetadata, LComponentStart,
    LComponentEnd - LComponentStart + Length('</component>'));

  LVersionAt := Pos('<version>', LComponent);
  LLicencesAt := Pos('<licenses>', LComponent);
  LPropertiesAt := Pos('<properties>', LComponent);
  Assert.IsTrue(LVersionAt > 0, 'The metadata component must have a version');
  Assert.IsTrue(LLicencesAt > LVersionAt, 'licenses must follow version');
  Assert.IsTrue(LPropertiesAt > LLicencesAt, 'properties must follow licenses');
  Assert.IsTrue(Pos('<id>MIT</id>', LComponent) > LLicencesAt);
  Assert.IsTrue(Pos('<license acknowledgement="concluded">', LComponent) <
    Pos('<license acknowledgement="declared">', LComponent));
  Assert.AreEqual(0, Integer(Length(CycloneDxXmlSequenceErrors(LContent))),
    'A root licence must keep the CycloneDX 1.6 element order');

  FMetadata.Licence := '';
  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LContent := LoadOutputContent;
  Assert.AreEqual(0, Pos('<licenses>', LContent),
    'An empty licence writes no licenses element');
end;

procedure TCycloneDxXmlWriterTests.Write_ComponentElementOrder_HashesBeforePurl;
var
  LComponents: string;
  LContent: string;
  LEnd, LStart: Integer;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application',
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789', 102400));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  LStart := Pos('<components>', LContent);
  LEnd := Pos('</components>', LContent);
  LComponents := Copy(LContent, LStart, LEnd - LStart);
  Assert.IsTrue(Pos('<hashes>', LComponents) < Pos('<purl>', LComponents),
    'component hashes must precede purl');
  Assert.IsTrue(Pos('<purl>', LComponents) < Pos('<properties>', LComponents),
    'component purl must precede properties');
end;

procedure TCycloneDxXmlWriterTests.Validate_OutOfOrderElements_ReturnsFalse;
const
  cOutOfOrder =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<bom xmlns="http://cyclonedx.org/schema/bom/1.6" version="1" ' +
    'serialNumber="urn:uuid:12345678-1234-1234-1234-123456789012">' +
    '<metadata>' +
    '<timestamp>2026-02-24T10:00:00+01:00</timestamp>' +
    '<properties><property name="dx:profile">cra</property></properties>' +
    '<tools><tool><vendor>Olaf Monien</vendor><name>DX.Comply</name>' +
    '<version>2.0.0.0</version></tool></tools>' +
    '<component type="application" bom-ref="App"><name>App</name></component>' +
    '</metadata>' +
    '<components><component type="application" bom-ref="comp-0">' +
    '<name>App.exe</name><purl>file:App.exe</purl>' +
    '<hashes><hash alg="SHA-256">' +
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789' +
    '</hash></hashes></component></components>' +
    '</bom>';
begin
  Assert.IsFalse(FWriter.Validate(cOutOfOrder),
    'Validation must reject metadata properties before tools and purl before hashes');
  Assert.IsTrue(Length(CycloneDxXmlSequenceErrors(cOutOfOrder)) > 0,
    'The sequence check must report the old element order');
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsDxComplyProperties;
var
  LContent: string;
begin
  SetLength(FMetadata.Properties, 2);
  FMetadata.Properties[0] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:document.profile', 'build-evidence');
  FMetadata.Properties[1] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:assessment.warning-count', '0');
  SetLength(FMetadata.ComponentProperties, 1);
  FMetadata.ComponentProperties[0] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:build.configuration', 'Release');

  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;

  Assert.IsTrue(Pos('<properties>', LContent) > 0);
  Assert.IsTrue(Pos('<property name="net.developer-experts.dx-comply:document.profile">build-evidence</property>', LContent) > 0);
  Assert.IsTrue(Pos('<property name="net.developer-experts.dx-comply:assessment.warning-count">0</property>', LContent) > 0);
  Assert.IsTrue(Pos('<property name="net.developer-experts.dx-comply:build.configuration">Release</property>', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_SingleArtefact_ContainsComponent;
var
  LContent: string;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application',
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789', 102400));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(Pos('<name>MyApp.exe</name>', LContent) > 0);
  Assert.IsTrue(Pos('type="application"', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_SingleArtefact_ContainsHash;
var
  LContent: string;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application',
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789', 102400));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(Pos('alg="SHA-256"', LContent) > 0);
  Assert.IsTrue(Pos('abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsDependencies;
var
  LContent: string;
begin
  FArtefacts.Add(MakeArtefact('MyApp.exe', 'application', '', 1024));
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(Pos('<dependencies>', LContent) > 0);
  Assert.IsTrue(Pos('ref="TestProject"', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_Dependencies_GroupedUnderDeliverable;
var
  LContent: string;
  LTargetOpen: Integer;
begin
  FArtefacts.Add(MakeArtefact('TestProject.exe', 'application', '', 1024));
  FArtefacts.Add(MakeArtefact('rtl.bpl', 'runtime-package', '', -1));
  FArtefacts.Add(MakeArtefact('vendor.dll', 'external-reference', '', -1));
  FArtefacts.Add(MakeArtefact('System.dcu', 'unit-evidence', '', 100));

  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LContent := LoadOutputContent;

  Assert.IsTrue(Pos('<dependency ref="comp-0"/>', LContent) > 0,
    'the project must depend on the deliverable');
  LTargetOpen := Pos('<dependency ref="comp-0">', LContent);
  Assert.IsTrue(LTargetOpen > 0, 'the deliverable must have its own dependency entry');
  Assert.IsTrue(Pos('<dependency ref="comp-1"/>', LContent) > LTargetOpen,
    'the runtime package must be a dependency of the deliverable');
  Assert.IsTrue(Pos('<dependency ref="comp-2"/>', LContent) > LTargetOpen,
    'the external DLL must be a dependency of the deliverable');
  Assert.IsTrue(Pos('<dependency ref="comp-3"/>', LContent) > LTargetOpen,
    'the linked unit must be a dependency of the deliverable');
end;

procedure TCycloneDxXmlWriterTests.Write_ExternalDll_MissingFile_KeepsEvidence;
var
  LArtefact: TArtefactInfo;
  LContent: string;
begin
  LArtefact := MakeArtefact('uastack_64.dll', 'external-reference', '', -1);
  LArtefact.Origin := '';
  LArtefact.Evidence := 'DLL';
  LArtefact.Confidence := 'Source-scan';
  LArtefact.Conditional := True;
  FArtefacts.Add(LArtefact);

  Assert.IsTrue(FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LContent := LoadOutputContent;

  Assert.IsTrue(Pos('<name>uastack_64.dll</name>', LContent) > 0,
    'the DLL must be a component even when the file is absent');
  Assert.IsTrue(Pos('net.developer-experts.dx-comply:evidence">DLL</property>', LContent) > 0,
    'evidence must be written when size is unknown and origin is empty');
  Assert.IsTrue(Pos('net.developer-experts.dx-comply:confidence">Source-scan</property>', LContent) > 0,
    'confidence must be written when size is unknown and origin is empty');
  Assert.IsTrue(Pos('net.developer-experts.dx-comply:conditional">true</property>', LContent) > 0,
    'a conditional DLL name must be marked in the XML properties');
  Assert.AreEqual(0, Pos('file:size', LContent),
    'an absent file must not invent a size');
end;

procedure TCycloneDxXmlWriterTests.Validate_ValidXml_ReturnsTrue;
var
  LContent: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(FWriter.Validate(LContent));
end;

procedure TCycloneDxXmlWriterTests.Validate_InvalidXml_ReturnsFalse;
begin
  Assert.IsFalse(FWriter.Validate('<html><body>Not a BOM</body></html>'));
end;

procedure TCycloneDxXmlWriterTests.Validate_EmptyString_ReturnsFalse;
begin
  Assert.IsFalse(FWriter.Validate(''));
end;

procedure TCycloneDxXmlWriterTests.Write_SpecialChars_AreEscaped;
var
  LContent: string;
begin
  FProjectInfo.Free;
  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'Test&App<1>';
  FProjectInfo.ProjectPath := 'C:\Projects\Test.dproj';
  FProjectInfo.ProjectDir := 'C:\Projects';
  FProjectInfo.Version := '1.0.0.0';

  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  // The special characters should be escaped in XML
  Assert.IsTrue(Pos('Test&amp;App&lt;1&gt;', LContent) > 0);
end;

end.
