/// <summary>
/// DX.Comply.Tests.Report.HtmlWriter
/// DUnitX tests for the HTML compliance report writer.
/// </summary>
///
/// <remarks>
/// The HTML report targets human auditors, so these tests assert that the generated
/// document contains the expected semantic sections and status markers.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Report.HtmlWriter;

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf;

type
  /// <summary>
  /// DUnitX fixture for HTML report rendering.
  /// </summary>
  [TestFixture]
  THtmlReportWriterTests = class
  private
    FArtefacts: TArtefactList;
    FBuildEvidence: TBuildEvidence;
    FCompositionEvidence: TCompositionEvidence;
    FData: TComplianceReportData;
    FOutputPath: string;
    FProjectInfo: TProjectInfo;
    FTempDir: string;
    FWarnings: TList<string>;
    procedure InitializeReportData;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetFormat_ReturnsHtml;

    [Test]
    procedure Write_CreatesReadableHtmlReport;

    /// <summary>
    /// An external DLL recorded by the source scan has no file on disk
    /// (size -1, empty hash) and must still appear in the Artefacts table.
    /// Issue #45.
    /// </summary>
    [Test]
    procedure Write_ExternalDllReference_AppearsInArtefactsTable;
    /// <summary>
    /// A DLL found in the output directory shows its size and SHA-256, and a
    /// DLL found only in a system directory shows where it was found.
    /// Issue #59.
    /// </summary>
    [Test]
    procedure Write_ExternalDll_ShowsSizeHashAndSystemLocation;

    /// <summary>
    /// EXE/DLL artefact versions appear in the Artefacts table. Issue #90.
    /// </summary>
    [Test]
    procedure Write_ArtefactVersion_AppearsInArtefactsTable;

    /// <summary>
    /// SBOM header data (creator, supplier, supplier URL, licence, product)
    /// appears in Project Overview when set, and is omitted when empty.
    /// </summary>
    [Test]
    procedure Write_SbomHeaderData_AppearsInProjectOverview;
    /// <summary>A supplier URL that is not http(s) is shown as text, not as a link.</summary>
    [Test]
    procedure Write_SupplierUrlWithOtherScheme_IsNotALink;
    [Test]
    procedure Write_EmptySbomHeaderData_IsOmitted;
    [Test]
    procedure Write_Overview_ShowsOriginsLicencesAndUnitsWithoutManifest;
    /// <summary>
    /// The Unknown supplier row lists its units by prefix. A known supplier
    /// stays a count. Issue #176.
    /// </summary>
    [Test]
    procedure Write_UnknownSupplier_ListsUnitsByPrefix;
    /// <summary>
    /// An Android shared library with no version resource shows the product
    /// version in the licence table and in the artefacts table. A third-party
    /// DLL keeps its own version in the artefacts table and does not inherit
    /// the product version in the licence table.
    /// </summary>
    [Test]
    procedure Write_DeliverableWithoutVersion_UsesProductVersion;
    /// <summary>Content overview writes the overview sections without the unit list. Issue #126.</summary>
    [Test]
    procedure Write_ContentOverview_OmitsUnitList;
    /// <summary>Content units writes the unit list without the overview sections. Issue #126.</summary>
    [Test]
    procedure Write_ContentUnits_OmitsOverview;
    /// <summary>
    /// The licence table has one row per component, sorted by name, with
    /// version and copyright columns. Issue #156.
    /// </summary>
    [Test]
    procedure Write_LicenceTable_OneRowPerComponent;
    /// <summary>
    /// The browser title and the top heading start with the project name.
    /// The product name is used when the project name is empty. Issue #167.
    /// </summary>
    [Test]
    procedure Write_Title_PrefixesProjectName;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Report.HtmlWriter,
  DX.Comply.Schema.Validator;

procedure THtmlReportWriterTests.GetFormat_ReturnsHtml;
var
  LWriter: IHumanReadableReportWriter;
begin
  LWriter := THtmlReportWriter.Create;
  Assert.AreEqual(NativeInt(Ord(hrfHtml)), NativeInt(Ord(LWriter.GetFormat)));
end;

procedure THtmlReportWriterTests.InitializeReportData;
var
  LArtefact: TArtefactInfo;
  LEvidenceItem: TBuildEvidenceItem;
  LResolvedUnit: TResolvedUnitInfo;
begin
  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'Demo';
  FProjectInfo.ProjectPath := TPath.Combine(FTempDir, 'src', 'Demo.dproj');
  FProjectInfo.ProjectDir := TPath.GetDirectoryName(FProjectInfo.ProjectPath);
  FProjectInfo.Platform := 'Win32';
  FProjectInfo.Configuration := 'Debug';
  FProjectInfo.UsesDebugDCUs := True;
  FProjectInfo.Version := '2.0.0';
  FProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
  FProjectInfo.Toolchain.Version := '37.0';
  FProjectInfo.Toolchain.BuildVersion := '37.0.57242.3601';
  FProjectInfo.Toolchain.RootDir := 'C:\Program Files (x86)\Embarcadero\Studio\37.0';

  FBuildEvidence := TBuildEvidence.Create;
  LEvidenceItem.SourceKind := besCompilerResponseFile;
  LEvidenceItem.DisplayName := 'dcc32.rsp';
  LEvidenceItem.FilePath := 'Y:\Build\dcc32.rsp';
  LEvidenceItem.UnitName := 'Demo.Html';
  LEvidenceItem.Detail := '-U search path';
  FBuildEvidence.EvidenceItems.Add(LEvidenceItem);

  FCompositionEvidence := TCompositionEvidence.Create;
  FCompositionEvidence.GeneratedAt := '2026-03-07T13:00:00Z';
  LResolvedUnit.UnitName := 'Demo.Html';
  LResolvedUnit.EvidenceKind := uekDcu;
  LResolvedUnit.OriginKind := uokThirdParty;
  LResolvedUnit.Confidence := rcStrong;
  LResolvedUnit.ContainerPath := 'Y:\Lib\Demo.Html.dcu';
  FCompositionEvidence.Units.Add(LResolvedUnit);

  FArtefacts := TArtefactList.Create;
  LArtefact := Default(TArtefactInfo);
  LArtefact.FilePath := 'Y:\Build\Demo.dll';
  LArtefact.RelativePath := 'build\Win32\Debug\Demo.dll';
  LArtefact.FileSize := 2048;
  LArtefact.Hash := '1234567890ABCDEF';
  LArtefact.ArtefactType := 'library';
  LArtefact.Version := '2.0.0.1';
  FArtefacts.Add(LArtefact);

  FWarnings := TList<string>.Create;
  FWarnings.Add('One third-party unit was resolved heuristically.');

  FData := Default(TComplianceReportData);
  FData.SbomOutputPath := TPath.Combine(FTempDir, 'bom.json');
  FData.SbomFormat := sfCycloneDxJson;
  FData.Metadata.ProductName := 'Demo';
  FData.Metadata.ProductVersion := '2.0.0';
  FData.Metadata.Timestamp := '2026-03-07T13:00:00Z';
  FData.ProjectInfo := FProjectInfo;
  FData.BuildEvidence := FBuildEvidence;
  FData.CompositionEvidence := FCompositionEvidence;
  FData.Artefacts := FArtefacts;
  FData.Warnings := FWarnings;
  FData.ValidationResult := TValidationResult.CreateValid;
end;

procedure THtmlReportWriterTests.Setup;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FTempDir := TPath.Combine(TPath.GetTempPath, GUIDToString(LGuid).Trim(['{', '}']));
  TDirectory.CreateDirectory(FTempDir);
  FOutputPath := TPath.Combine(FTempDir, 'report.html');
  InitializeReportData;
end;

procedure THtmlReportWriterTests.TearDown;
begin
  FWarnings.Free;
  FArtefacts.Free;
  FCompositionEvidence.Free;
  FBuildEvidence.Free;
  FProjectInfo.Free;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure THtmlReportWriterTests.Write_CreatesReadableHtmlReport;
var
  LConfig: THumanReadableReportConfig;
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LConfig := THumanReadableReportConfig.Default;
  LWriter := THtmlReportWriter.Create;

  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));
  Assert.IsTrue(TFile.Exists(FOutputPath));

  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<!DOCTYPE html>', LContent) > 0);
  Assert.IsTrue(Pos('<title>Demo - DX.Comply SBOM Report</title>', LContent) > 0);
  Assert.IsTrue(Pos('<h1>Demo - DX.Comply SBOM Report</h1>', LContent) > 0);
  Assert.IsTrue(Pos('This report lists the units, packages and DLL names DX.Comply could see in the build', LContent) > 0);
  Assert.IsTrue(Pos('Internal structural check passed', LContent) > 0);
  Assert.IsTrue(Pos('Generated By', LContent) > 0);
  Assert.IsTrue(Pos('<a href="bom.json"><code>bom.json</code></a>', LContent) > 0);
  Assert.IsTrue(Pos('Repository / Project Root', LContent) > 0);
  Assert.IsTrue(Pos('Delphi Runtime Units', LContent) > 0);
  Assert.IsTrue(Pos('Debug DCUs', LContent) > 0);
  Assert.IsTrue(Pos('Unit Evidence', LContent) > 0);
  Assert.IsTrue(Pos('Demo.Html', LContent) > 0);
  Assert.IsTrue(Pos('37.0.57242.3601', LContent) > 0);
  Assert.AreEqual(0, Pos('Build Trace Records', LContent));
  Assert.AreEqual(0, Pos('Build Traceability', LContent));
  Assert.IsTrue(Pos('<th>Version</th>', LContent) > 0);
  Assert.IsTrue(Pos('>2.0.0.1<', LContent) > 0, 'artefact version must appear in the HTML table');
  Assert.IsTrue(Pos('class="table-wrap"', LContent) > 0);
  Assert.IsTrue(Pos('overflow-wrap:anywhere', LContent) > 0);
  Assert.IsTrue(Pos('One third-party unit was resolved heuristically.', LContent) > 0);
end;

procedure THtmlReportWriterTests.Write_ExternalDllReference_AppearsInArtefactsTable;
var
  LArtefact: TArtefactInfo;
  LConfig: THumanReadableReportConfig;
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := 'uastack_64.dll';
  LArtefact.ArtefactType := 'external-reference';
  LArtefact.FileSize := -1;
  LArtefact.Hash := '';
  LArtefact.Evidence := 'DLL';
  LArtefact.Confidence := 'Source-scan';
  FArtefacts.Add(LArtefact);

  LConfig := THumanReadableReportConfig.Default;
  LWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));

  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('uastack_64.dll', LContent) > 0,
    'an external DLL with no file on disk must be listed in the HTML report');
  Assert.IsTrue(Pos('external-reference', LContent) > 0,
    'the external DLL must be labelled as an external-reference artefact');
  Assert.IsTrue(Pos('>n/a<', LContent) > 0,
    'a missing file size must be shown as n/a rather than omitting the row');
end;

procedure THtmlReportWriterTests.Write_ExternalDll_ShowsSizeHashAndSystemLocation;
var
  LArtefact: TArtefactInfo;
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := 'vendor.dll';
  LArtefact.ArtefactType := 'external-reference';
  LArtefact.FileSize := 12345;
  LArtefact.Hash := StringOfChar('c', 64);
  LArtefact.LocationSource := 'output-directory';
  FArtefacts.Add(LArtefact);

  LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := 'ws2_32.dll';
  LArtefact.ArtefactType := 'external-reference';
  LArtefact.FileSize := -1;
  LArtefact.LocationSource := 'system-directory';
  LArtefact.Location := 'C:\Windows\SysWOW64\ws2_32.dll';
  FArtefacts.Add(LArtefact);

  LWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<td>12345</td>', LContent) > 0, 'size of a shipped DLL must be shown');
  Assert.IsTrue(Pos(StringOfChar('c', 64), LContent) > 0, 'SHA-256 of a shipped DLL must be shown');
  Assert.IsTrue(Pos('System directory: C:\Windows\SysWOW64\ws2_32.dll', LContent) > 0,
    'the system directory location must be shown');
end;

procedure THtmlReportWriterTests.Write_ArtefactVersion_AppearsInArtefactsTable;
var
  LArtefact: TArtefactInfo;
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := 'App.exe';
  LArtefact.ArtefactType := 'application';
  LArtefact.FileSize := 8192;
  LArtefact.Hash := StringOfChar('d', 64);
  LArtefact.Version := '3.1.0';
  FArtefacts.Add(LArtefact);

  LWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<td>3.1.0</td>', LContent) > 0,
    'application version stored on the artefact must appear in the HTML report');
  Assert.IsTrue(Pos('<td>2.0.0.1</td>', LContent) > 0,
    'DLL version stored on the artefact must appear in the HTML report');
end;

procedure THtmlReportWriterTests.Write_SbomHeaderData_AppearsInProjectOverview;
begin
  FData.Metadata.SbomCreator := 'sbom@example.com';
  FData.Metadata.Supplier := 'Example & Co GmbH';
  FData.Metadata.SupplierUrl := 'https://example.com';
  FData.Metadata.Licence := 'Proprietary';
  var LWriter: IHumanReadableReportWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<th>SBOM Creator</th><td>sbom@example.com</td>', LContent) > 0);
  Assert.IsTrue(Pos('<th>Supplier</th><td>Example &amp; Co GmbH</td>', LContent) > 0);
  Assert.IsTrue(Pos('<a href="https://example.com">https://example.com</a>', LContent) > 0);
  Assert.IsTrue(Pos('<th>Licence</th><td>Proprietary</td>', LContent) > 0);
  Assert.IsTrue(Pos('<th>Product</th><td>Demo</td>', LContent) > 0);
end;

procedure THtmlReportWriterTests.Write_SupplierUrlWithOtherScheme_IsNotALink;
begin
  FData.Metadata.SupplierUrl := 'javascript:alert(1)';
  var LWriter: IHumanReadableReportWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<th>Supplier URL</th><td>javascript:alert(1)</td>', LContent) > 0,
    'The value is still shown');
  Assert.AreEqual(0, Pos('href="javascript:', LContent), 'It must not become a link');
end;

procedure THtmlReportWriterTests.Write_EmptySbomHeaderData_IsOmitted;
begin
  var LWriter: IHumanReadableReportWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.AreEqual(0, Pos('SBOM Creator', LContent));
  Assert.AreEqual(0, Pos('<th>Supplier</th>', LContent));
  Assert.AreEqual(0, Pos('<th>Licence</th>', LContent));
end;

procedure THtmlReportWriterTests.Write_Overview_ShowsOriginsLicencesAndUnitsWithoutManifest;
begin
  var LUnit := Default(TArtefactInfo);
  LUnit.RelativePath := 'JvComponent.pas';
  LUnit.ArtefactType := 'unit-evidence';
  LUnit.Origin := 'Third party';
  FArtefacts.Add(LUnit);
  FData.Metadata.Licence := 'Proprietary';
  var LWriter: IHumanReadableReportWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<section id="origin-summary"><h2>Origin summary</h2>', LContent) > 0);
  Assert.IsTrue(Pos('<a href="#third-party-units-without-manifest">Third party</a></td><td>1</td>',
    LContent) > 0);
  Assert.IsTrue(Pos('<section id="licences"><h2>Licences</h2>', LContent) > 0);
  Assert.IsTrue(Pos('<th>Name</th><th>Version</th><th>Copyright</th><th>Note</th>', LContent) > 0);
  Assert.AreEqual(0, Pos('<th>Names</th><th>Note</th>', LContent));
  Assert.IsTrue(Pos('<td rowspan="2">Proprietary</td><td rowspan="2">2</td><td>Demo (product)</td><td></td><td></td><td rowspan="2"></td>',
    LContent) > 0);
  Assert.IsTrue(Pos('<tr><td>Demo.dll</td><td>2.0.0.1</td><td></td></tr>', LContent) > 0);
  Assert.IsTrue(Pos('<td>No licence information</td><td>1</td><td>JvComponent</td><td></td><td></td><td></td>',
    LContent) > 0);
  Assert.IsTrue(Pos('<section id="third-party-units-without-manifest">', LContent) > 0);
  Assert.IsTrue(Pos('<td>Jv</td><td>1</td><td>supplier, version, licence</td><td>JvComponent</td>',
    LContent) > 0);
  Assert.IsTrue(Pos('<section id="artefacts">', LContent) > 0);
  Assert.IsTrue(Pos('<section id="unit-evidence">', LContent) > 0);
  Assert.IsTrue(Pos('id="origin-summary"', LContent) < Pos('id="artefacts"', LContent),
    'the origin summary is near the top');
end;

procedure THtmlReportWriterTests.Write_UnknownSupplier_ListsUnitsByPrefix;
begin
  FData.Metadata.ComponentManifestJson :=
    '{"components":[{"name":"JVCL","version":"3.5","vendor":"Project JEDI",' +
    '"licence":"MPL-1.1","units_prefix":["Jv"]}]}';
  var LJv := Default(TArtefactInfo);
  LJv.RelativePath := 'JvComponent.pas';
  LJv.ArtefactType := 'unit-evidence';
  LJv.Origin := 'Third party';
  FArtefacts.Add(LJv);
  var LXyz := Default(TArtefactInfo);
  LXyz.RelativePath := 'XyzGrid.pas';
  LXyz.ArtefactType := 'unit-evidence';
  LXyz.Origin := 'Third party';
  FArtefacts.Add(LXyz);
  var LWriter: IHumanReadableReportWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<td>Unknown supplier<br>Xyz: 1 unit (XyzGrid)</td><td>1</td>', LContent) > 0,
    LContent);
  Assert.IsTrue(Pos('<td>Project JEDI</td><td>1</td>', LContent) > 0, LContent);
  Assert.AreEqual(0, Pos('Project JEDI<br>', LContent));
end;

procedure THtmlReportWriterTests.Write_DeliverableWithoutVersion_UsesProductVersion;
var
  LWriter: IHumanReadableReportWriter;
  LContent: string;
  LDll: TArtefactInfo;
begin
  FArtefacts.Clear;
  FData.ProjectInfo.ProjectName := 'WernigApp';
  FData.Metadata.ProductName := 'WernigApp';
  FData.Metadata.ProductVersion := '16.0.0.7';
  FData.Metadata.Licence := 'MIT';
  var LSo := Default(TArtefactInfo);
  LSo.RelativePath := 'Android\Release\libWernigApp.so';
  LSo.ArtefactType := 'file';
  LSo.FileSize := 4096;
  LSo.Hash := 'ABCDEF';
  FArtefacts.Add(LSo);
  LDll := Default(TArtefactInfo);
  LDll.RelativePath := 'vendor.dll';
  LDll.ArtefactType := 'library';
  LDll.Version := '9.9.9';
  LDll.FileSize := 2048;
  LDll.Hash := '123456';
  FArtefacts.Add(LDll);
  LWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<td>libWernigApp.so</td><td>16.0.0.7</td>', LContent) > 0,
    'The licence table uses the product version');
  Assert.IsTrue(Pos('<td>vendor.dll</td><td></td>', LContent) > 0,
    'A third-party DLL does not inherit the product version in the licence table');
  Assert.IsTrue(Pos('<td>Android\Release\libWernigApp.so</td><td>file</td><td>16.0.0.7</td>',
    LContent) > 0, 'The artefacts table uses the product version');
  Assert.IsTrue(Pos('<td>vendor.dll</td><td>library</td><td>9.9.9</td>', LContent) > 0,
    'The artefacts table keeps the third-party version');
end;

procedure THtmlReportWriterTests.Write_ContentOverview_OmitsUnitList;
begin
  var LConfig := THumanReadableReportConfig.Default;
  LConfig.Content := hrcOverview;
  var LWriter: IHumanReadableReportWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('id="origin-summary"', LContent) > 0);
  Assert.IsTrue(Pos('id="licences"', LContent) > 0);
  Assert.IsTrue(Pos('<th>Copyright</th>', LContent) > 0,
    'overview content still includes the licence table');
  Assert.AreEqual(0, Pos('id="unit-evidence"', LContent));
  Assert.AreEqual(0, Pos('#unit-evidence', LContent), 'no link to a missing section');
  Assert.IsTrue(Pos('1234567890ABCDEF', LContent) > 0, 'the artefact hashes stay');
end;

procedure THtmlReportWriterTests.Write_ContentUnits_OmitsOverview;
begin
  var LConfig := THumanReadableReportConfig.Default;
  LConfig.Content := hrcUnits;
  var LWriter: IHumanReadableReportWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('id="unit-evidence"', LContent) > 0);
  Assert.IsTrue(Pos('Demo.Html', LContent) > 0);
  Assert.AreEqual(0, Pos('id="origin-summary"', LContent));
  Assert.AreEqual(0, Pos('id="licences"', LContent));
  Assert.AreEqual(0, Pos('<th>Copyright</th>', LContent), 'units content has no licence table');
end;

procedure THtmlReportWriterTests.Write_LicenceTable_OneRowPerComponent;
const
  cRows = '{"components":[' +
    '{"name":"SVG Icon Image List","version":"4.8.1","licence":"Apache-2.0","units_prefix":["Svg"]},' +
    '{"name":"Logger Pro","version":"2.1.2","licence":"Apache-2.0","copyright":"2020 | 2021","units_prefix":["Logger"]},' +
    '{"name":"delphi Event Bus","version":"2.1","licence":"apache-2.0","copyright":"A & B","units_prefix":["Event"]},' +
    '{"name":"VSoft Command Line Parser","version":"0.1.9","licence":"Apache-2.0","copyright":"   ","units_prefix":["VSoft"]},' +
    '{"name":"NoVersion Lib","licence":"Apache-2.0","copyright":"1999","units_prefix":["NvLib"]},' +
    '{"name":"JVCL","version":"3.5","licence":"MPL-1.1","units_prefix":["Jv"]}]}';
  procedure AddUnit(const AName: string);
  var
    LUnit: TArtefactInfo;
  begin
    LUnit := Default(TArtefactInfo);
    LUnit.RelativePath := AName + '.pas';
    LUnit.ArtefactType := 'unit-evidence';
    LUnit.Origin := 'Third party';
    FArtefacts.Add(LUnit);
  end;
begin
  FData.Metadata.ComponentManifestJson := cRows;
  FData.Metadata.Licence := 'Proprietary';
  AddUnit('SvgIcons');
  AddUnit('LoggerMain');
  AddUnit('EventBus');
  AddUnit('VSoftParser');
  AddUnit('NvLibCore');
  AddUnit('JvComponent');
  var LWriter: IHumanReadableReportWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<th>Declared licence</th><th>Components</th><th>Name</th><th>Version</th><th>Copyright</th><th>Note</th>',
    LContent) > 0);
  Assert.AreEqual(0, Pos('Logger Pro 2.1.2', LContent), 'the version is not glued to the name');
  var LEvent := Pos('<td rowspan="5">Apache-2.0</td><td rowspan="5">5</td><td>delphi Event Bus</td><td>2.1</td><td>A &amp; B</td><td rowspan="5"></td>',
    LContent);
  var LLogger := Pos('<tr><td>Logger Pro</td><td>2.1.2</td><td>2020 | 2021</td></tr>', LContent);
  var LNoVersion := Pos('<tr><td>NoVersion Lib</td><td></td><td>1999</td></tr>', LContent);
  var LSvg := Pos('<tr><td>SVG Icon Image List</td><td>4.8.1</td><td></td></tr>', LContent);
  var LVsoft := Pos('<tr><td>VSoft Command Line Parser</td><td>0.1.9</td><td></td></tr>', LContent);
  Assert.IsTrue(LEvent > 0, 'the licence and the count span the group');
  Assert.IsTrue((LEvent < LLogger) and (LLogger < LNoVersion) and (LNoVersion < LSvg) and (LSvg < LVsoft),
    'components are sorted by name without regard to case');
  Assert.IsTrue(Pos('<tr><td>MPL-1.1</td><td>1</td><td>JVCL</td><td>3.5</td><td></td><td>Copyleft licence. Check its terms for distribution with this product.</td></tr>',
    LContent) > 0, 'a one-component group keeps the review note on its row');
  Assert.IsTrue(Pos('<td rowspan="2">Proprietary</td><td rowspan="2">2</td>', LContent) > 0);
  Assert.IsTrue(LVsoft < Pos('<td>MPL-1.1</td>', LContent), 'licence groups stay in title order');
end;

procedure THtmlReportWriterTests.Write_Title_PrefixesProjectName;
var
  LWriter: IHumanReadableReportWriter;
  LContent: string;
begin
  FData.ProjectInfo.ProjectName := 'A & B';
  FData.Metadata.ProductName := 'Ignored';
  LWriter := THtmlReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<title>A &amp; B - DX.Comply SBOM Report</title>', LContent) > 0);
  Assert.IsTrue(Pos('<h1>A &amp; B - DX.Comply SBOM Report</h1>', LContent) > 0);

  FData.ProjectInfo.ProjectName := '';
  FData.Metadata.ProductName := 'Catalog';
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<title>Catalog - DX.Comply SBOM Report</title>', LContent) > 0);
  Assert.IsTrue(Pos('<h1>Catalog - DX.Comply SBOM Report</h1>', LContent) > 0);

  FData.Metadata.ProductName := '';
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<title>DX.Comply SBOM Report</title>', LContent) > 0);
  Assert.IsTrue(Pos('<h1>DX.Comply SBOM Report</h1>', LContent) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(THtmlReportWriterTests);

end.
