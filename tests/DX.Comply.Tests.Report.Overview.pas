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
    procedure Suppliers_FromManifestVendor_UnknownOtherwise;
    [Test]
    procedure WithoutManifest_GroupedByPrefix;
    [Test]
    procedure WithoutManifest_EmptyWhenManifestCoversAll;
    [Test]
    procedure NamesText_IsCapped;
    [Test]
    procedure WithoutManifestLine_CountsAndEmptyWithoutThirdParty;
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

function FindGroup(const AGroups: TArray<TReportGroup>; const ATitle: string): TReportGroup;
begin
  Result := Default(TReportGroup);
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
  Assert.AreEqual(FArtefacts.Count + 1, LOverview.TotalComponents);
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
  Assert.AreEqual(2, FindGroup(LOverview.Licences, 'MPL-1.1').Count, 'MPL-1.1 and mpl-1.1 form one group');
  Assert.AreEqual(1, FindGroup(LOverview.Licences, 'Proprietary').Count);
  Assert.AreEqual(cNoLicenceGroupTitle, LOverview.Licences[High(LOverview.Licences)].Title);
  Assert.AreEqual(1, LOverview.Licences[High(LOverview.Licences)].Count);
  Assert.AreEqual('Main', LOverview.Licences[High(LOverview.Licences)].Names[0]);
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
