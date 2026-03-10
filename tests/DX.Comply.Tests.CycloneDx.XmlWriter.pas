/// <summary>
/// DX.Comply.Tests.CycloneDx.XmlWriter
/// DUnitX tests for TCycloneDxXmlWriter.
/// </summary>
///
/// <remarks>
/// Verifies CycloneDX 1.5 XML output: namespace, required elements,
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
  DX.Comply.Engine.Intf;

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
    procedure Validate_ValidXml_ReturnsTrue;

    [Test]
    procedure Validate_InvalidXml_ReturnsFalse;

    [Test]
    procedure Validate_EmptyString_ReturnsFalse;

    [Test]
    procedure Write_SpecialChars_AreEscaped;
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
  Assert.IsTrue(Pos('http://cyclonedx.org/schema/bom/1.5', LContent) > 0);
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
  Assert.IsTrue(Pos('<timestamp>2026-02-24T10:00:00+01:00</timestamp>', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsToolInfo;
var
  LContent: string;
begin
  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;
  Assert.IsTrue(Pos('<name>DX.Comply</name>', LContent) > 0);
  Assert.IsTrue(Pos('<vendor>Olaf Monien</vendor>', LContent) > 0);
end;

procedure TCycloneDxXmlWriterTests.Write_ContainsDxComplyProperties;
var
  LContent: string;
begin
  SetLength(FMetadata.Properties, 2);
  FMetadata.Properties[0] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:deep-evidence.requested', 'true');
  FMetadata.Properties[1] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:deep-evidence.command-line', 'powershell -File build.ps1');
  SetLength(FMetadata.ComponentProperties, 1);
  FMetadata.ComponentProperties[0] := TSbomProperty.Create(
    'net.developer-experts.dx-comply:build.configuration', 'Release');

  FWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo);
  LContent := LoadOutputContent;

  Assert.IsTrue(Pos('<properties>', LContent) > 0);
  Assert.IsTrue(Pos('<property name="net.developer-experts.dx-comply:deep-evidence.requested">true</property>', LContent) > 0);
  Assert.IsTrue(Pos('<property name="net.developer-experts.dx-comply:deep-evidence.command-line">powershell -File build.ps1</property>', LContent) > 0);
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
