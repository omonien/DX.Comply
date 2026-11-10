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
    [Test]
    procedure Suppliers_FromManifestVendor_UnknownOtherwise;
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
  end;

implementation

uses
  System.SysUtils,
  DX.Comply.Report.Overview;

const
  cManifest = '{"components":[{"name":"JVCL","version":"3.5","vendor":"Project JEDI",' +
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
  cRows = '{"components":[' +
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

procedure TReportOverviewTests.WithoutManifestLine_CountsAndEmptyWithoutThirdParty;
begin
  AddUnit('Main', 'Local project');
  Assert.AreEqual('', ThirdPartyWithoutManifestLine(FArtefacts, ''));
  AddUnit('JvComponent', 'Third party');
  AddUnit('XyzGrid', 'Third party');
  var LLine := ThirdPartyWithoutManifestLine(FArtefacts, cManifest);
  Assert.IsTrue(LLine.StartsWith('1 of 2 third-party units have no component manifest row.'), LLine);
end;

initialization
  TDUnitX.RegisterTestFixture(TReportOverviewTests);

end.
