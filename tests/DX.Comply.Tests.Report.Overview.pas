/// <summary>
/// DX.Comply.Tests.Report.Overview
/// Tests for the licence, origin and supplier overview of the reports.
/// </summary>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Report.Overview;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf;

type
  [TestFixture]
  TReportOverviewTests = class
  private
    FArtefacts: TArtefactList;
    FData: TComplianceReportData;
    procedure AddUnit(const AName, AOrigin: string);
    procedure AddFile(const APath, AType: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Origins_SumEqualsSbomComponentCount;
    [Test]
    procedure Licences_GroupedCaseInsensitive_NoLicenceLast;
    [Test]
    procedure Licences_CopyleftHint_OnlyWhenDifferentFromProduct;
    [Test]
    procedure Licences_BuiltProgram_UnderProductLicence;
    /// <summary>
    /// The project executable stays under the product licence when it was
    /// not stored as an application, library, or package (issue #155).
    /// A neighboring DLL, a local unit, and a file that only shares the
    /// product display name stay unlicensed.
    /// </summary>
    [Test]
    procedure Licences_UntypedProjectExe_UnderProductLicence;
    /// <summary>
    /// The project output path selects the product binary, and a second
    /// copy of that file name carries the same licence.
    /// </summary>
    [Test]
    procedure Licences_OutputPathAndSecondCopy_UnderProductLicence;
    /// <summary>
    /// A package binary with a numeric suffix is the product. Another
    /// package in the same list is not.
    /// </summary>
    [Test]
    procedure Licences_PackageSuffix_BeatsOtherPackage;
    /// <summary>
    /// Android and Linux output names use a lib prefix. That file is the
    /// product when the stem is the project name.
    /// </summary>
    [Test]
    procedure Licences_LibPrefix_MatchesProject;
    /// <summary>
    /// A product deliverable with no version of its own, such as an Android
    /// shared library, uses the product version in the licence table. A
    /// third-party file does not. A version already on the deliverable is kept.
    /// </summary>
    [Test]
    procedure Licences_DeliverableWithoutVersion_UsesProductVersion;
    /// <summary>
    /// Embarcadero RTL, VCL and FMX units are grouped under that origin
    /// label. A third-party unit and a neighboring file stay unlicensed.
    /// Issue #165.
    /// </summary>
    [Test]
    procedure Licences_EmbarcaderoUnits_UseOriginLabel;
    /// <summary>
    /// own_code_units, own_code_prefixes and own_code_folders inherit the
    /// product licence. With no product licence they stay unlicensed, and
    /// an Embarcadero unit still uses its origin label. Issue #166.
    /// </summary>
    [Test]
    procedure Licences_OwnCode_InheritsProductLicence;
    [Test]
    procedure Suppliers_FromManifestVendor_UnknownOtherwise;
    /// <summary>
    /// A third-party file that matches own_code_* is the project's own
    /// code, so it is not an unknown supplier. A unit that stays unknown
    /// is named on that row. Issue #176.
    /// </summary>
    [Test]
    procedure Suppliers_OwnCodeOutsideProject_IsNamedWhenUnknown;
    /// <summary>
    /// Unknown supplier lines group by prefix and shorten long lists the
    /// same way as the console warnings.
    /// </summary>
    [Test]
    procedure UnknownSupplierLines_GroupsByPrefix_AndShortens;
    [Test]
    procedure WithoutManifest_GroupedByPrefix;
    [Test]
    procedure WithoutManifest_EmptyWhenManifestCoversAll;
    [Test]
    procedure WithoutManifest_GroupByFolder_SplitsPrefixByFolder;
    [Test]
    procedure NamesText_IsCapped;
    [Test]
    procedure WithoutManifestLine_CountsAndEmptyWithoutThirdParty;
    /// <summary>
    /// Licence rows are one component each, sorted by name without regard to
    /// case, with version and copyright in their own fields. Issue #156.
    /// </summary>
    [Test]
    procedure Licences_OneRowPerComponent_SortedWithVersionAndCopyright;
    /// <summary>
    /// A library is listed when its units are classified as local project
    /// code and the file name is only the part after the last dot. Issue #172.
    /// </summary>
    [Test]
    procedure Licences_OwnCodeOrigin_ListsMatchedLibrary;
    [Test]
    procedure WithoutManifestLine_OmittedWhenNoneMissing;
    /// <summary>
    /// A vendor is listed when the matched units are Local project.
    /// A prefix that is not applied is a row of its own and is not that vendor.
    /// </summary>
    [Test]
    procedure Suppliers_ListsVendorsOfLocalProjectUnits;
    /// <summary>The prefix section is empty when no prefix was refused.</summary>
    [Test]
    procedure PrefixRejections_EmptyWhenNoneRefused;
  end;

implementation

uses
  System.SysUtils,
  DX.Comply.CraChecks,
  DX.Comply.Report.Overview;

const
  cManifest = '{"match":{"prefixes":"legacy"},"components":[{"name":"JVCL","version":"3.5","vendor":"Project JEDI",' +
    '"licence":"MPL-1.1","units_prefix":["Jv"]},{"name":"Other","version":"1.0",' +
    '"vendor":"Acme","licence":"mpl-1.1","units_prefix":["Acm"]}]}';

procedure TReportOverviewTests.AddUnit(const AName, AOrigin: string);
begin
  var LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := AName + '.pas';
  LArtefact.ArtefactType := 'unit-evidence';
  LArtefact.Origin := AOrigin;
  FArtefacts.Add(LArtefact);
end;

procedure TReportOverviewTests.AddFile(const APath, AType: string);
begin
  var LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := APath;
  LArtefact.ArtefactType := AType;
  FArtefacts.Add(LArtefact);
end;

procedure TReportOverviewTests.Setup;
begin
  FArtefacts := TArtefactList.Create;
  FData := Default(TComplianceReportData);
  FData.Metadata.ProductName := 'Demo';
  FData.Artefacts := FArtefacts;
end;

procedure TReportOverviewTests.TearDown;
begin
  FArtefacts.Free;
end;

function SetPath(const AArtefact: TArtefactInfo; const APath: string): TArtefactInfo;
begin
  Result := AArtefact;
  Result.FilePath := APath;
end;

function FindGroup(const AGroups: TArray<TReportGroup>; const ATitle: string): TReportGroup;
begin
  Result := Default(TReportGroup);
  for var LGroup in AGroups do
  begin
    if SameText(LGroup.Title, ATitle) then
      Exit(LGroup);
  end;
end;

function FindLicence(const AGroups: TArray<TLicenceGroup>; const ATitle: string): TLicenceGroup;
begin
  Result := Default(TLicenceGroup);
  for var LGroup in AGroups do
  begin
    if SameText(LGroup.Title, ATitle) then
      Exit(LGroup);
  end;
end;

function LicenceNames(const AGroup: TLicenceGroup): string;
begin
  Result := '';
  for var i := 0 to High(AGroup.Components) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + AGroup.Components[i].Name;
  end;
end;

procedure TReportOverviewTests.Origins_SumEqualsSbomComponentCount;
begin
  FData.Metadata.ComponentManifestJson := cManifest;
  AddFile('Demo.exe', 'application');
  AddFile('vendor.dll', 'library');
  AddFile('rtl290.bpl', 'runtime-package');
  AddUnit('System.SysUtils', 'Embarcadero RTL/VCL/FMX');
  AddUnit('Main', 'Local project');
  AddUnit('JvComponent', 'Third party');
  AddUnit('JvEdit', 'Third party');
  AddUnit('XyzGrid', 'Third party');
  var LOverview := BuildReportOverview(FData);
  // SBOM components: every artefact plus one component per manifest library.
  Assert.AreEqual<Integer>(FArtefacts.Count + 1, LOverview.TotalComponents);
  Assert.AreEqual(1, FindGroup(LOverview.Origins, cDllOrigin).Count);
  Assert.AreEqual(1, FindGroup(LOverview.Origins, cRuntimePackageOrigin).Count);
  Assert.AreEqual(1, FindGroup(LOverview.Origins, cOtherFileOrigin).Count);
  Assert.AreEqual(1, FindGroup(LOverview.Origins, cManifestLibraryOrigin).Count);
  Assert.AreEqual(3, FindGroup(LOverview.Origins, 'Third party').Count);
  Assert.AreEqual(cAnchorWithoutManifest, FindGroup(LOverview.Origins, 'Third party').Anchor);
  Assert.AreEqual(cAnchorArtefacts, FindGroup(LOverview.Origins, cDllOrigin).Anchor);
  Assert.AreEqual(cAnchorUnitEvidence, FindGroup(LOverview.Origins, 'Local project').Anchor);
end;

procedure TReportOverviewTests.Licences_GroupedCaseInsensitive_NoLicenceLast;
begin
  FData.Metadata.ComponentManifestJson := cManifest;
  FData.Metadata.Licence := 'Proprietary';
  AddUnit('JvComponent', 'Third party');
  AddUnit('AcmButton', 'Third party');
  AddUnit('Main', 'Local project');
  var LOverview := BuildReportOverview(FData);
  Assert.AreEqual<Integer>(3, Length(LOverview.Licences));
  var LMpl := FindLicence(LOverview.Licences, 'MPL-1.1');
  Assert.AreEqual(2, LMpl.Count, 'MPL-1.1 and mpl-1.1 form one group');
  Assert.AreEqual('JVCL', LMpl.Components[0].Name);
  Assert.AreEqual('3.5', LMpl.Components[0].Version);
  Assert.AreEqual('', LMpl.Components[0].Copyright);
  Assert.AreEqual('Other', LMpl.Components[1].Name);
  Assert.AreEqual('1.0', LMpl.Components[1].Version);
  Assert.AreEqual(1, FindLicence(LOverview.Licences, 'Proprietary').Count);
  Assert.AreEqual(cNoLicenceGroupTitle, LOverview.Licences[High(LOverview.Licences)].Title);
  Assert.AreEqual(1, LOverview.Licences[High(LOverview.Licences)].Count);
  Assert.AreEqual('Main', LOverview.Licences[High(LOverview.Licences)].Components[0].Name);
end;

procedure TReportOverviewTests.Licences_BuiltProgram_UnderProductLicence;
begin
  FData.Metadata.Licence := 'LicenseRef-Proprietary';
  FData.ProjectInfo.ProjectName := 'epMCOMLib';
  AddFile('epMCOMLib.dll', 'library');
  AddFile('vendor.dll', 'library');
  var LOverview := BuildReportOverview(FData);
  var LProduct := FindLicence(LOverview.Licences, 'LicenseRef-Proprietary');
  Assert.AreEqual(2, LProduct.Count, 'Product entry and built program');
  var LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(1, LNone.Count);
  Assert.AreEqual('vendor.dll', LNone.Components[0].Name);
  Assert.AreEqual('', LNone.Components[0].Version);
  Assert.AreEqual('', LNone.Components[0].Copyright);
end;

procedure TReportOverviewTests.Licences_UntypedProjectExe_UnderProductLicence;
begin
  FData.Metadata.Licence := 'Proprietary';
  FData.Metadata.ProductName := 'Demo';
  FData.ProjectInfo.ProjectName := 'XmlConvert';
  AddFile('Win64/Release/XmlConvert.exe', 'file');
  AddFile('bit.dll', 'library');
  AddUnit('XmlConvert', 'Local project');
  AddFile('Demo.exe', 'file');
  var LOverview := BuildReportOverview(FData);
  var LProduct := FindLicence(LOverview.Licences, 'Proprietary');
  Assert.AreEqual(2, LProduct.Count, 'Product entry and project executable');
  Assert.IsTrue(Pos('XmlConvert.exe', LicenceNames(LProduct)) > 0,
    'The project executable is under the product licence');
  Assert.AreEqual(0, Pos('bit.dll', LicenceNames(LProduct)),
    'A neighboring DLL does not inherit the product licence');
  Assert.AreEqual(0, Pos('Demo.exe', LicenceNames(LProduct)),
    'The product display name is not a file match');
  var LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(3, LNone.Count);
  Assert.AreEqual(0, Pos('XmlConvert.exe', LicenceNames(LNone)),
    'The project executable is not listed as unlicensed');
  Assert.IsTrue(Pos('bit.dll', LicenceNames(LNone)) > 0);
  Assert.IsTrue(Pos('Demo.exe', LicenceNames(LNone)) > 0);
end;

procedure TReportOverviewTests.Licences_OutputPathAndSecondCopy_UnderProductLicence;
begin
  FData.Metadata.Licence := 'Proprietary';
  FData.Metadata.ProductName := 'XmlConvert';
  FData.ProjectInfo.ProjectName := 'OtherApp';
  FData.ProjectInfo.OutputFilePath := 'C:\Build\XmlConvert.exe';
  AddFile('XmlConvert.exe', 'file');
  FArtefacts[0] := SetPath(FArtefacts[0], 'C:\Build\XmlConvert.exe');
  AddFile('setup\XmlConvert.exe', 'file');
  FArtefacts[1] := SetPath(FArtefacts[1], 'C:\Build\setup\XmlConvert.exe');
  AddFile('OtherApp.exe', 'application');
  var LOverview := BuildReportOverview(FData);
  var LProduct := FindLicence(LOverview.Licences, 'Proprietary');
  Assert.AreEqual(3, LProduct.Count,
    'Product entry and both copies of the output file');
  Assert.IsTrue(Pos('XmlConvert.exe', LicenceNames(LProduct)) > 0);
  var LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(1, LNone.Count);
  Assert.AreEqual('OtherApp.exe', LNone.Components[0].Name);
end;

procedure TReportOverviewTests.Licences_PackageSuffix_BeatsOtherPackage;
begin
  FData.Metadata.Licence := 'Proprietary';
  FData.Metadata.ProductName := 'MyPkg';
  FData.ProjectInfo.ProjectName := 'MyPkg';
  AddFile('MyPkg290.bpl', 'file');
  AddFile('other.bpl', 'package');
  var LOverview := BuildReportOverview(FData);
  var LProduct := FindLicence(LOverview.Licences, 'Proprietary');
  Assert.IsTrue(Pos('MyPkg290.bpl', LicenceNames(LProduct)) > 0,
    'The suffixed package is the product binary');
  var LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(1, LNone.Count);
  Assert.AreEqual('other.bpl', LNone.Components[0].Name);
end;

procedure TReportOverviewTests.Licences_LibPrefix_MatchesProject;
begin
  FData.Metadata.Licence := 'MIT';
  FData.Metadata.ProductName := 'Demo';
  FData.ProjectInfo.ProjectName := 'Demo';
  AddFile('libDemo.so', 'file');
  AddFile('vendor.dll', 'library');
  var LOverview := BuildReportOverview(FData);
  var LProduct := FindLicence(LOverview.Licences, 'MIT');
  Assert.IsTrue(Pos('libDemo.so', LicenceNames(LProduct)) > 0,
    'A lib-prefixed binary of the project is the product');
  var LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(1, LNone.Count);
  Assert.AreEqual('vendor.dll', LNone.Components[0].Name);
end;

procedure TReportOverviewTests.Licences_EmbarcaderoUnits_UseOriginLabel;
begin
  FData.Metadata.Licence := 'MIT';
  // Demo.exe is the product. vendor.dll is then a neighboring file.
  FData.ProjectInfo.ProjectName := 'Demo';
  AddFile('Demo.exe', 'application');
  AddUnit('System.SysUtils', 'Embarcadero RTL');
  AddUnit('Winapi.Windows', 'Embarcadero RTL');
  AddUnit('Vcl.Forms', 'Embarcadero VCL');
  AddUnit('FMX.Forms', 'Embarcadero FMX');
  AddUnit('JvComponent', 'Third party');
  AddFile('vendor.dll', 'library');
  var LOverview := BuildReportOverview(FData);
  var LRtl := FindLicence(LOverview.Licences, 'Embarcadero RTL');
  Assert.AreEqual(NativeInt(2), NativeInt(LRtl.Count), LicenceNames(LRtl));
  Assert.IsTrue(Pos('System.SysUtils', LicenceNames(LRtl)) > 0);
  Assert.IsTrue(Pos('Winapi.Windows', LicenceNames(LRtl)) > 0);
  var LVcl := FindLicence(LOverview.Licences, 'Embarcadero VCL');
  Assert.AreEqual(NativeInt(1), NativeInt(LVcl.Count));
  Assert.AreEqual('Vcl.Forms', LVcl.Components[0].Name);
  var LFmx := FindLicence(LOverview.Licences, 'Embarcadero FMX');
  Assert.AreEqual(NativeInt(1), NativeInt(LFmx.Count));
  Assert.AreEqual('FMX.Forms', LFmx.Components[0].Name);
  var LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(NativeInt(2), NativeInt(LNone.Count));
  Assert.IsTrue(Pos('JvComponent', LicenceNames(LNone)) > 0);
  Assert.IsTrue(Pos('vendor.dll', LicenceNames(LNone)) > 0);
  Assert.AreEqual(0, Pos('System.SysUtils', LicenceNames(LNone)));
  Assert.AreEqual(0, Pos('Vcl.Forms', LicenceNames(LNone)));
  Assert.AreEqual(0, Pos('FMX.Forms', LicenceNames(LNone)));
end;

procedure TReportOverviewTests.Licences_OwnCode_InheritsProductLicence;
  procedure SetSource(AIndex: Integer; const APath: string);
  var
    LArtefact: TArtefactInfo;
  begin
    LArtefact := FArtefacts[AIndex];
    LArtefact.SourcePath := APath;
    FArtefacts[AIndex] := LArtefact;
  end;
begin
  FData.Metadata.Licence := 'Apache-2.0';
  FData.Metadata.ComponentManifestJson :=
    '{"match":{"prefixes":"legacy"},"components":[],"own_code_units":["MainForm","System.SysUtils"],' +
    '"own_code_prefixes":["App"],"own_code_folders":["' +
    StringReplace('C:\DXComplyFolderTest\src', '\', '\\', [rfReplaceAll]) + '"]}';
  AddUnit('MainForm', 'Local project');
  AddUnit('AppSettings', 'Local project');
  AddUnit('Helper', 'Local project');
  SetSource(2, 'C:\DXComplyFolderTest\src\Helper.pas');
  AddUnit('LocalOnly', 'Local project');
  AddUnit('VendorUnit', 'Third party');
  AddUnit('System.SysUtils', 'Embarcadero RTL');

  var LOverview := BuildReportOverview(FData);
  var LProduct := FindLicence(LOverview.Licences, 'Apache-2.0');
  Assert.IsTrue(Pos('MainForm', LicenceNames(LProduct)) > 0, 'own_code_units');
  Assert.IsTrue(Pos('AppSettings', LicenceNames(LProduct)) > 0, 'own_code_prefixes');
  Assert.IsTrue(Pos('Helper', LicenceNames(LProduct)) > 0, 'own_code_folders');
  Assert.IsTrue(Pos('System.SysUtils', LicenceNames(LProduct)) > 0,
    'Own code wins over the Embarcadero origin');
  Assert.AreEqual(NativeInt(0), NativeInt(FindLicence(LOverview.Licences, 'Embarcadero RTL').Count));
  var LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(NativeInt(2), NativeInt(LNone.Count));
  Assert.IsTrue(Pos('LocalOnly', LicenceNames(LNone)) > 0);
  Assert.IsTrue(Pos('VendorUnit', LicenceNames(LNone)) > 0);
  Assert.AreEqual(0, Pos('MainForm', LicenceNames(LNone)));

  FData.Metadata.Licence := '';
  LOverview := BuildReportOverview(FData);
  Assert.AreEqual(NativeInt(0), NativeInt(FindLicence(LOverview.Licences, 'Apache-2.0').Count));
  var LRtl := FindLicence(LOverview.Licences, 'Embarcadero RTL');
  Assert.AreEqual(NativeInt(1), NativeInt(LRtl.Count));
  Assert.AreEqual('System.SysUtils', LRtl.Components[0].Name);
  LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.IsTrue(Pos('MainForm', LicenceNames(LNone)) > 0);
  Assert.IsTrue(Pos('AppSettings', LicenceNames(LNone)) > 0);
  Assert.IsTrue(Pos('Helper', LicenceNames(LNone)) > 0);
  Assert.AreEqual(0, Pos('System.SysUtils', LicenceNames(LNone)));
end;

procedure TReportOverviewTests.Licences_CopyleftHint_OnlyWhenDifferentFromProduct;
begin
  Assert.AreNotEqual('', LicenceReviewHint('GPL-3.0-only', 'Proprietary'));
  Assert.AreNotEqual('', LicenceReviewHint('MIT OR LGPL-2.1-or-later', 'Proprietary'));
  Assert.AreNotEqual('', LicenceReviewHint('(MPL-2.0)', ''));
  Assert.AreEqual('', LicenceReviewHint('GPL-3.0-only', 'gpl-3.0-only'));
  Assert.AreEqual('', LicenceReviewHint('MIT', 'Proprietary'));
  Assert.AreEqual('', LicenceReviewHint('Apache-2.0', 'Proprietary'));
end;

procedure TReportOverviewTests.Suppliers_FromManifestVendor_UnknownOtherwise;
begin
  FData.Metadata.ComponentManifestJson := cManifest;
  AddUnit('JvComponent', 'Third party');
  AddUnit('JvEdit', 'Third party');
  AddUnit('XyzGrid', 'Third party');
  AddUnit('Main', 'Local project');
  var LOverview := BuildReportOverview(FData);
  Assert.AreEqual(2, FindGroup(LOverview.Suppliers, 'Project JEDI').Count);
  Assert.AreEqual(1, FindGroup(LOverview.Suppliers, cUnknownSupplierTitle).Count);
  Assert.AreEqual(3, LOverview.ThirdPartyUnitCount);
end;

procedure TReportOverviewTests.WithoutManifest_GroupedByPrefix;
begin
  AddUnit('JvComponent', 'Third party');
  AddUnit('JvEdit', 'Third party');
  AddUnit('superobject', 'Third party');
  AddUnit('System.Classes', 'Embarcadero RTL/VCL/FMX');
  var LOverview := BuildReportOverview(FData);
  Assert.IsFalse(LOverview.ManifestUsed);
  Assert.AreEqual(3, LOverview.WithoutManifestCount);
  Assert.AreEqual<Integer>(2, Length(LOverview.WithoutManifest));
  Assert.AreEqual(2, FindGroup(LOverview.WithoutManifest, 'Jv').Count);
  Assert.AreEqual('JvComponent, JvEdit', FindGroup(LOverview.WithoutManifest, 'Jv').NamesText);
  Assert.AreEqual('supplier, version, licence', FindGroup(LOverview.WithoutManifest, 'Jv').Note);
  Assert.AreEqual(1, FindGroup(LOverview.WithoutManifest, 'superobject').Count);
end;

procedure TReportOverviewTests.WithoutManifest_GroupByFolder_SplitsPrefixByFolder;
begin
  AddUnit('JvComponent', 'Third party');
  AddUnit('JvEdit', 'Third party');
  AddUnit('JvOther', 'Third party');
  FArtefacts[0] := SetPath(FArtefacts[0], 'C:\Libs\JVCL\run\JvComponent.pas');
  FArtefacts[1] := SetPath(FArtefacts[1], 'C:\Libs\JVCL\run\JvEdit.pas');
  FArtefacts[2] := SetPath(FArtefacts[2], 'C:\Other\Jv\JvOther.pas');

  // Default: one group per prefix.
  var LOverview := BuildReportOverview(FData);
  Assert.AreEqual<Integer>(1, Length(LOverview.WithoutManifest));
  Assert.AreEqual(3, FindGroup(LOverview.WithoutManifest, 'Jv').Count);

  // With folder grouping: one group per prefix and folder.
  LOverview := BuildReportOverview(FData, True);
  Assert.AreEqual(3, LOverview.WithoutManifestCount);
  Assert.AreEqual<Integer>(2, Length(LOverview.WithoutManifest));
  Assert.AreEqual(2, FindGroup(LOverview.WithoutManifest, 'Jv (C:\Libs\JVCL\run)').Count);
  Assert.AreEqual(1, FindGroup(LOverview.WithoutManifest, 'Jv (C:\Other\Jv)').Count);
end;

procedure TReportOverviewTests.WithoutManifest_EmptyWhenManifestCoversAll;
begin
  FData.Metadata.ComponentManifestJson := cManifest;
  AddUnit('JvComponent', 'Third party');
  AddUnit('AcmButton', 'Third party');
  var LOverview := BuildReportOverview(FData);
  Assert.IsTrue(LOverview.ManifestUsed);
  Assert.AreEqual(0, LOverview.WithoutManifestCount);
  Assert.AreEqual<Integer>(0, Length(LOverview.WithoutManifest));
end;

procedure TReportOverviewTests.NamesText_IsCapped;
begin
  var LGroup := Default(TReportGroup);
  LGroup.Names := ['A', 'B', 'C', 'D'];
  Assert.AreEqual('A, B, C, D', LGroup.NamesText);
  Assert.AreEqual('A, B and 2 more', LGroup.NamesText(2));
end;

procedure TReportOverviewTests.Licences_OneRowPerComponent_SortedWithVersionAndCopyright;
const
  cRows = '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"SVG Icon Image List","version":"4.8.1","licence":"Apache-2.0","units_prefix":["Svg"]},' +
    '{"name":"Logger Pro","version":"2.1.2","licence":"Apache-2.0","copyright":"2020 | 2021","units_prefix":["Logger"]},' +
    '{"name":"delphi Event Bus","version":"2.1","licence":"apache-2.0","copyright":"A & B","units_prefix":["Event"]},' +
    '{"name":"VSoft Command Line Parser","version":"0.1.9","licence":"Apache-2.0","copyright":"   ","units_prefix":["VSoft"]},' +
    '{"name":"NoVersion Lib","licence":"Apache-2.0","copyright":"1999","units_prefix":["NvLib"]},' +
    '{"name":"Alpha","version":"2.0","licence":"MIT","copyright":"2018","units_exact":["AlphaTwo"]},' +
    '{"name":"alpha","version":"1.0","licence":"MIT","units_exact":["AlphaOne"]},' +
    '{"name":"Twin","version":"1","licence":"MIT","copyright":"first","units_exact":["TwinA"]},' +
    '{"name":"Twin","version":"1","licence":"MIT","copyright":"second","units_exact":["TwinB"]},' +
    '{"name":"JVCL","version":"3.5","licence":"MPL-1.1","units_prefix":["Jv"]}]}';
  procedure AssertComponent(const AGroup: TLicenceGroup; AIndex: Integer;
    const AName, AVersion, ACopyright: string);
  begin
    Assert.IsTrue(AIndex <= High(AGroup.Components), AGroup.Title + ' is missing a row');
    Assert.AreEqual(AName, AGroup.Components[AIndex].Name);
    Assert.AreEqual(AVersion, AGroup.Components[AIndex].Version);
    Assert.AreEqual(ACopyright, AGroup.Components[AIndex].Copyright);
  end;
begin
  FData.Metadata.ComponentManifestJson := cRows;
  FData.Metadata.Licence := 'Proprietary';
  AddUnit('SvgIcons', 'Third party');
  AddUnit('LoggerMain', 'Third party');
  AddUnit('EventBus', 'Third party');
  AddUnit('VSoftParser', 'Third party');
  AddUnit('NvLibCore', 'Third party');
  AddUnit('AlphaOne', 'Third party');
  AddUnit('AlphaTwo', 'Third party');
  AddUnit('TwinA', 'Third party');
  AddUnit('TwinB', 'Third party');
  AddUnit('JvComponent', 'Third party');
  var LOverview := BuildReportOverview(FData);
  Assert.AreEqual<Integer>(4, Length(LOverview.Licences));
  Assert.AreEqual('Apache-2.0', LOverview.Licences[0].Title);
  Assert.AreEqual('MIT', LOverview.Licences[1].Title);
  Assert.AreEqual('MPL-1.1', LOverview.Licences[2].Title);
  Assert.AreEqual('Proprietary', LOverview.Licences[3].Title);

  var LApache := LOverview.Licences[0];
  Assert.AreEqual(5, LApache.Count);
  Assert.AreEqual('', LApache.Note);
  AssertComponent(LApache, 0, 'delphi Event Bus', '2.1', 'A & B');
  AssertComponent(LApache, 1, 'Logger Pro', '2.1.2', '2020 | 2021');
  AssertComponent(LApache, 2, 'NoVersion Lib', '', '1999');
  AssertComponent(LApache, 3, 'SVG Icon Image List', '4.8.1', '');
  AssertComponent(LApache, 4, 'VSoft Command Line Parser', '0.1.9', '');

  var LMit := LOverview.Licences[1];
  Assert.AreEqual(4, LMit.Count);
  AssertComponent(LMit, 0, 'alpha', '1.0', '');
  AssertComponent(LMit, 1, 'Alpha', '2.0', '2018');
  AssertComponent(LMit, 2, 'Twin', '1', 'first');
  AssertComponent(LMit, 3, 'Twin', '1', 'second');

  var LMpl := LOverview.Licences[2];
  Assert.AreEqual(1, LMpl.Count);
  Assert.AreEqual('Copyleft licence. Check its terms for distribution with this product.', LMpl.Note);
  AssertComponent(LMpl, 0, 'JVCL', '3.5', '');

  var LProduct := LOverview.Licences[3];
  Assert.AreEqual(1, LProduct.Count);
  AssertComponent(LProduct, 0, 'Demo (product)', '', '');
  Assert.AreEqual('', LProduct.Note);
end;

procedure TReportOverviewTests.Licences_OwnCodeOrigin_ListsMatchedLibrary;
const
  cTms = '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"TMS FNC Core","version":"4.2.3.7","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNC"]},' +
    '{"name":"TMS FNC UI Pack","version":"7.1.2.2","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNC"]}]}';
begin
  FData.Metadata.ComponentManifestJson := cTms;
  FData.Metadata.Licence := 'MIT';
  var LButton := Default(TArtefactInfo);
  LButton.RelativePath := 'TMSFNCButton.dcu';
  LButton.UnitName := 'FMX.TMSFNCButton';
  LButton.ArtefactType := 'unit-evidence';
  LButton.Origin := 'Local project';
  FArtefacts.Add(LButton);
  var LTypes := Default(TArtefactInfo);
  LTypes.RelativePath := 'TMSFNCTypes.dcu';
  LTypes.UnitName := 'FMX.TMSFNCTypes';
  LTypes.ArtefactType := 'unit-evidence';
  LTypes.Origin := 'Local project';
  FArtefacts.Add(LTypes);

  var LOverview := BuildReportOverview(FData);
  Assert.AreEqual<Integer>(FArtefacts.Count + 1, LOverview.TotalComponents);
  var LLicence := FindLicence(LOverview.Licences, 'LicenseRef-Proprietary');
  Assert.AreEqual(1, LLicence.Count);
  Assert.AreEqual('TMS FNC Core', LLicence.Components[0].Name);
  Assert.AreEqual('4.2.3.7', LLicence.Components[0].Version);
  Assert.AreEqual('TMS FNC Core', LicenceNames(LLicence));
  var LNone := FindLicence(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(0, LNone.Count);
  var LLibrary := FindGroup(LOverview.Origins, cManifestLibraryOrigin);
  Assert.AreEqual(1, LLibrary.Count);
  Assert.AreEqual('TMS FNC Core 4.2.3.7', LLibrary.NamesText);
  Assert.AreEqual(2, FindGroup(LOverview.Origins, 'Local project').Count);
end;

procedure TReportOverviewTests.Suppliers_OwnCodeOutsideProject_IsNamedWhenUnknown;
const
  cJson = '{"match":{"prefixes":"legacy"},"components":[{"name":"JVCL","version":"3.5","vendor":"Project JEDI",' +
    '"licence":"MPL-1.1","units_prefix":["Jv"]}],' +
    '"own_code_units":["SharedHelper"],"own_code_prefixes":["Acme"],' +
    '"own_code_folders":["C:\\Libs\\Mine"]}';
begin
  FData.Metadata.ComponentManifestJson := cJson;
  FData.Metadata.Licence := 'MIT';
  AddUnit('JvComponent', 'Third party');
  AddUnit('SharedHelper', 'Third party');
  AddUnit('AcmeGrid', 'Third party');
  AddUnit('MineUnit', 'Third party');
  var LMine := FArtefacts[FArtefacts.Count - 1];
  LMine.SourcePath := 'C:\Libs\Mine\MineUnit.pas';
  FArtefacts[FArtefacts.Count - 1] := LMine;
  AddUnit('XyzGrid', 'Third party');

  var LOverview := BuildReportOverview(FData);
  Assert.AreEqual(2, LOverview.ThirdPartyUnitCount);
  Assert.AreEqual(1, FindGroup(LOverview.Suppliers, 'Project JEDI').Count);
  Assert.AreEqual('JvComponent', FindGroup(LOverview.Suppliers, 'Project JEDI').NamesText);
  Assert.AreEqual(NativeInt(0), NativeInt(Length(FindGroup(LOverview.Suppliers, 'Project JEDI').Detail)));

  var LUnknown := FindGroup(LOverview.Suppliers, cUnknownSupplierTitle);
  Assert.AreEqual(1, LUnknown.Count);
  Assert.AreEqual('XyzGrid', LUnknown.NamesText);
  Assert.AreEqual(NativeInt(1), NativeInt(Length(LUnknown.Detail)));
  Assert.AreEqual('Xyz: 1 unit (XyzGrid)', LUnknown.Detail[0]);
  Assert.AreEqual(0, Pos('SharedHelper', LUnknown.NamesText));
  Assert.AreEqual(0, Pos('AcmeGrid', LUnknown.NamesText));
  Assert.AreEqual(0, Pos('MineUnit', LUnknown.NamesText));

  Assert.AreEqual(1, LOverview.WithoutManifestCount);
  Assert.AreEqual('XyzGrid', FindGroup(LOverview.WithoutManifest, 'Xyz').NamesText);
  Assert.AreEqual(0, FindGroup(LOverview.WithoutManifest, 'Shared').Count);
  Assert.AreEqual(5, FindGroup(LOverview.Origins, 'Third party').Count);

  var LProduct := FindLicence(LOverview.Licences, 'MIT');
  Assert.IsTrue(Pos('SharedHelper', LicenceNames(LProduct)) > 0, 'own_code_units');
  Assert.IsTrue(Pos('AcmeGrid', LicenceNames(LProduct)) > 0, 'own_code_prefixes');
  Assert.IsTrue(Pos('MineUnit', LicenceNames(LProduct)) > 0, 'own_code_folders');
end;

procedure TReportOverviewTests.UnknownSupplierLines_GroupsByPrefix_AndShortens;
var
  LNames: TArray<string>;
  LLines: TArray<string>;
  i: Integer;
begin
  LLines := FormatUnknownSupplierLines(nil);
  Assert.AreEqual(NativeInt(0), NativeInt(Length(LLines)));

  LLines := FormatUnknownSupplierLines(['JvComponent', 'jvEdit', 'XyzGrid']);
  Assert.AreEqual(NativeInt(2), NativeInt(Length(LLines)));
  Assert.AreEqual('Jv: 2 units (JvComponent, jvEdit)', LLines[0]);
  Assert.AreEqual('Xyz: 1 unit (XyzGrid)', LLines[1]);

  LLines := FormatUnknownSupplierLines(['JvOne', 'JvTwo', 'JvThree', 'JvFour', 'JvFive', 'JvSix']);
  Assert.AreEqual(NativeInt(1), NativeInt(Length(LLines)));
  Assert.AreEqual('Jv: 6 units (JvOne, JvTwo, JvThree, JvFour, JvFive, ...)', LLines[0]);

  SetLength(LNames, 11);
  for i := 1 to 11 do
    LNames[i - 1] := 'Lib' + IntToStr(i) + '.Core';
  LLines := FormatUnknownSupplierLines(LNames);
  Assert.AreEqual(NativeInt(cMaxComponentWarningGroups + 1), NativeInt(Length(LLines)));
  Assert.AreEqual('Lib1: 1 unit (Lib1.Core)', LLines[0]);
  Assert.AreEqual('Lib10: 1 unit (Lib10.Core)', LLines[9]);
  Assert.AreEqual('1 more group, 1 unit', LLines[10]);
end;

procedure TReportOverviewTests.WithoutManifestLine_CountsAndEmptyWithoutThirdParty;
begin
  AddUnit('Main', 'Local project');
  Assert.AreEqual('', ThirdPartyWithoutManifestLine(FArtefacts, ''));
  AddUnit('JvComponent', 'Third party');
  AddUnit('XyzGrid', 'Third party');
  var LLine := ThirdPartyWithoutManifestLine(FArtefacts, cManifest);
  Assert.IsTrue(LLine.StartsWith('1 of 2 third-party units have no component manifest row.'), LLine);
end;

procedure TReportOverviewTests.Licences_DeliverableWithoutVersion_UsesProductVersion;

  function VersionOf(const AOverview: TReportOverview; const AName: string): string;
  var
    LGroup: TLicenceGroup;
    I: Integer;
  begin
    for LGroup in AOverview.Licences do
      for I := 0 to High(LGroup.Components) do
        if SameText(LGroup.Components[I].Name, AName) then
          Exit(LGroup.Components[I].Version);
    Assert.Fail(AName + ' must appear in the licence table');
  end;

  procedure AddVersioned(const APath, AType, AVersion: string; AFromFileDate: Boolean);
  var
    LArtefact: TArtefactInfo;
  begin
    LArtefact := Default(TArtefactInfo);
    LArtefact.RelativePath := APath;
    LArtefact.ArtefactType := AType;
    LArtefact.Version := AVersion;
    LArtefact.VersionFromFileDate := AFromFileDate;
    FArtefacts.Add(LArtefact);
  end;

var
  LOverview: TReportOverview;
  LGroup: TLicenceGroup;
  I, LCopies: Integer;
begin
  FData.Metadata.ProductName := 'WernigApp';
  FData.Metadata.ProductVersion := '16.0.0.7';
  FData.Metadata.Licence := 'MIT';
  FData.ProjectInfo.ProjectName := 'WernigApp';
  AddFile('Android\Release\libWernigApp.so', 'file');
  AddFile('copy\libWernigApp.so', 'file');
  AddVersioned('vendor.dll', 'library', '9.9.9', False);
  AddFile('plugin.dll', 'library');
  LOverview := BuildReportOverview(FData);
  LCopies := 0;
  for LGroup in LOverview.Licences do
    for I := 0 to High(LGroup.Components) do
      if SameText(LGroup.Components[I].Name, 'libWernigApp.so') then
      begin
        Assert.AreEqual('16.0.0.7', LGroup.Components[I].Version);
        Inc(LCopies);
      end;
  Assert.AreEqual(2, LCopies, 'Both copies of the built program use the product version');
  Assert.AreEqual('', VersionOf(LOverview, 'WernigApp (product)'));
  Assert.AreEqual('', VersionOf(LOverview, 'vendor.dll'),
    'A third-party DLL does not inherit the product version');
  Assert.AreEqual('', VersionOf(LOverview, 'plugin.dll'));

  FArtefacts.Clear;
  AddVersioned('libWernigApp.so', 'file', '2026-01-01T00:00:00Z', True);
  LOverview := BuildReportOverview(FData);
  Assert.AreEqual('16.0.0.7', VersionOf(LOverview, 'libWernigApp.so'),
    'A file-date stand-in is not a version of the built program');

  FArtefacts.Clear;
  AddVersioned('libWernigApp.so', 'file', '3.2.1', False);
  LOverview := BuildReportOverview(FData);
  Assert.AreEqual('3.2.1', VersionOf(LOverview, 'libWernigApp.so'),
    'A version already on the built program is kept');

  FArtefacts.Clear;
  FData.Metadata.ProductVersion := '';
  FData.ProjectInfo.Version := '4.5.6';
  AddFile('libWernigApp.so', 'file');
  LOverview := BuildReportOverview(FData);
  Assert.AreEqual('4.5.6', VersionOf(LOverview, 'libWernigApp.so'),
    'An empty header version falls back to the project version');
end;

procedure TReportOverviewTests.WithoutManifestLine_OmittedWhenNoneMissing;
begin
  // Issue #157: every third-party unit has a row, so "0 of 4" must not be logged.
  AddUnit('JvComponent', 'Third party');
  AddUnit('JvEdit', 'Third party');
  AddUnit('AcmButton', 'Third party');
  AddUnit('AcmGrid', 'Third party');
  Assert.AreEqual('', ThirdPartyWithoutManifestLine(FArtefacts, cManifest));
end;

procedure TReportOverviewTests.Suppliers_ListsVendorsOfLocalProjectUnits;

  procedure AddSourced(const AName, AOrigin, APath: string);
  var
    LArtefact: TArtefactInfo;
  begin
    LArtefact := Default(TArtefactInfo);
    LArtefact.UnitName := AName;
    LArtefact.RelativePath := AName + '.pas';
    LArtefact.SourcePath := APath;
    LArtefact.ArtefactType := 'unit-evidence';
    LArtefact.Origin := AOrigin;
    FArtefacts.Add(LArtefact);
  end;

var
  LJson: string;
  LOverview: TReportOverview;
  LTms: TReportGroup;
begin
  LJson :=
    '{"components":[' +
    '{"name":"Delphi Event Bus","version":"1","vendor":"Daniele Spinetti","licence":"MIT","type":"library","units_folder":["C:/DXComplyIssue176/delphi-event-bus"]},' +
    '{"name":"Logger Pro","version":"1","vendor":"Daniele Teti","licence":"MIT","type":"library","units_folder":["C:/DXComplyIssue176/loggerpro"]},' +
    '{"name":"SVG Icon Image List","version":"1","vendor":"Ethea S.r.l.","licence":"Apache-2.0","type":"library","units_folder":["C:/DXComplyIssue176/svg"]},' +
    '{"name":"VSoft Command Line Parser","version":"1","vendor":"Vincent Parrett","licence":"Apache-2.0","type":"library","units_folder":["C:/DXComplyIssue176/vsoft"]},' +
    '{"name":"Neslib","version":"1","vendor":"Erik van Bilsen","licence":"Apache-2.0","type":"library","units_folder":["C:/DXComplyIssue176/neslib"]},' +
    '{"name":"Neslib XML","version":"1","vendor":"Erik van Bilsen","licence":"Apache-2.0","type":"library","units_folder":["C:/DXComplyIssue176/neslibxml"]},' +
    '{"name":"Eurekalog","version":"1","vendor":"Neos Eureka S.r.l","licence":"Commercial","type":"library","units_folder":["C:/DXComplyIssue176/eurekalog"]},' +
    '{"name":"Delphi Console","version":"1","vendor":"Jens Borrisholt","licence":"MIT","type":"library","units_folder":["C:/DXComplyIssue176/console"]},' +
    '{"name":"TMS VCL UI Pack","version":"1","vendor":"tmssoftware.com","licence":"Commercial","type":"library",' +
    '"units_folder":["C:/DXComplyIssue176/TMS"],"units_prefix":["GDIP","HTML"]}]}';
  FData.Metadata.ComponentManifestJson := LJson;
  FData.ProjectInfo.Toolchain.RootDir := 'C:\DXProduct';
  AddSourced('EventBus', 'Local project',
    'C:\DXComplyIssue176\delphi-event-bus\src\EventBus.pas');
  AddSourced('LoggerPro', 'Local project',
    'C:\DXComplyIssue176\loggerpro\LoggerPro.pas');
  AddSourced('SVGIconImageList', 'Local project',
    'C:\DXComplyIssue176\svg\SVGIconImageList.pas');
  AddSourced('VSoft.CommandLineParser', 'Local project',
    'C:\DXComplyIssue176\vsoft\VSoft.CommandLineParser.pas');
  AddSourced('Neslib.SysUtils', 'Local project',
    'C:\DXComplyIssue176\neslib\Neslib.SysUtils.pas');
  AddSourced('Neslib.Xml', 'Local project',
    'C:\DXComplyIssue176\neslibxml\Neslib.Xml.pas');
  AddSourced('EurekaLog', 'Local project',
    'C:\DXComplyIssue176\eurekalog\EurekaLog.pas');
  AddSourced('DelphiConsole', 'Local project',
    'C:\DXComplyIssue176\console\DelphiConsole.pas');
  AddSourced('AdvGrid', 'Local project',
    'C:\DXComplyIssue176\TMS\AdvGrid.pas');
  AddSourced('Winapi.GDIPAPI', 'Embarcadero RTL',
    'C:\DXProduct\source\rtl\win\Winapi.GDIPAPI.pas');

  LOverview := BuildReportOverview(FData);
  Assert.AreEqual(1, FindGroup(LOverview.Suppliers, 'Daniele Spinetti').Count);
  Assert.AreEqual(1, FindGroup(LOverview.Suppliers, 'Daniele Teti').Count);
  Assert.AreEqual(1, FindGroup(LOverview.Suppliers, 'Ethea S.r.l.').Count);
  Assert.AreEqual(1, FindGroup(LOverview.Suppliers, 'Vincent Parrett').Count);
  Assert.AreEqual(2, FindGroup(LOverview.Suppliers, 'Erik van Bilsen').Count);
  Assert.AreEqual(1, FindGroup(LOverview.Suppliers, 'Neos Eureka S.r.l').Count);
  Assert.AreEqual(1, FindGroup(LOverview.Suppliers, 'Jens Borrisholt').Count);
  LTms := FindGroup(LOverview.Suppliers, 'tmssoftware.com');
  Assert.AreEqual(1, LTms.Count);
  Assert.AreEqual('AdvGrid', LTms.NamesText);
  Assert.AreEqual(0, LOverview.ThirdPartyUnitCount,
    'Local project units are not counted as third party');
  Assert.AreEqual(1, Length(LOverview.PrefixRejections));
  Assert.AreEqual('Winapi.GDIPAPI', LOverview.PrefixRejections[0].UnitName);
  Assert.AreEqual('GDIP', LOverview.PrefixRejections[0].Prefix);
  Assert.AreEqual('TMS VCL UI Pack', LOverview.PrefixRejections[0].RowName);
  Assert.AreEqual('Embarcadero RTL', LOverview.PrefixRejections[0].KeptOrigin);
end;

procedure TReportOverviewTests.PrefixRejections_EmptyWhenNoneRefused;
begin
  AddUnit('System.Classes', 'Embarcadero RTL');
  Assert.AreEqual(0, Length(BuildReportOverview(FData).PrefixRejections));
end;

initialization
  TDUnitX.RegisterTestFixture(TReportOverviewTests);

end.
