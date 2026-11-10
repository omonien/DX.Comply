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
  Assert.AreEqual(2, FindGroup(LOverview.Licences, 'MPL-1.1').Count, 'MPL-1.1 and mpl-1.1 form one group');
  Assert.AreEqual(1, FindGroup(LOverview.Licences, 'Proprietary').Count);
  Assert.AreEqual(cNoLicenceGroupTitle, LOverview.Licences[High(LOverview.Licences)].Title);
  Assert.AreEqual(1, LOverview.Licences[High(LOverview.Licences)].Count);
  Assert.AreEqual('Main', LOverview.Licences[High(LOverview.Licences)].Names[0]);
end;

procedure TReportOverviewTests.Licences_BuiltProgram_UnderProductLicence;
begin
  FData.Metadata.Licence := 'LicenseRef-Proprietary';
  FData.ProjectInfo.ProjectName := 'epMCOMLib';
  AddFile('epMCOMLib.dll', 'library');
  AddFile('vendor.dll', 'library');
  var LOverview := BuildReportOverview(FData);
  var LProduct := FindGroup(LOverview.Licences, 'LicenseRef-Proprietary');
  Assert.AreEqual(2, LProduct.Count, 'Product entry and built program');
  var LNone := FindGroup(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(1, LNone.Count);
  Assert.AreEqual('vendor.dll', LNone.Names[0]);
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
  var LProduct := FindGroup(LOverview.Licences, 'Proprietary');
  Assert.AreEqual(2, LProduct.Count, 'Product entry and project executable');
  Assert.IsTrue(Pos('XmlConvert.exe', LProduct.NamesText) > 0,
    'The project executable is under the product licence');
  Assert.AreEqual(0, Pos('bit.dll', LProduct.NamesText),
    'A neighboring DLL does not inherit the product licence');
  Assert.AreEqual(0, Pos('Demo.exe', LProduct.NamesText),
    'The product display name is not a file match');
  var LNone := FindGroup(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(3, LNone.Count);
  Assert.AreEqual(0, Pos('XmlConvert.exe', LNone.NamesText),
    'The project executable is not listed as unlicensed');
  Assert.IsTrue(Pos('bit.dll', LNone.NamesText) > 0);
  Assert.IsTrue(Pos('Demo.exe', LNone.NamesText) > 0);
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
  var LProduct := FindGroup(LOverview.Licences, 'Proprietary');
  Assert.AreEqual(3, LProduct.Count,
    'Product entry and both copies of the output file');
  Assert.IsTrue(Pos('XmlConvert.exe', LProduct.NamesText) > 0);
  var LNone := FindGroup(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(1, LNone.Count);
  Assert.AreEqual('OtherApp.exe', LNone.Names[0]);
end;

procedure TReportOverviewTests.Licences_PackageSuffix_BeatsOtherPackage;
begin
  FData.Metadata.Licence := 'Proprietary';
  FData.Metadata.ProductName := 'MyPkg';
  FData.ProjectInfo.ProjectName := 'MyPkg';
  AddFile('MyPkg290.bpl', 'file');
  AddFile('other.bpl', 'package');
  var LOverview := BuildReportOverview(FData);
  var LProduct := FindGroup(LOverview.Licences, 'Proprietary');
  Assert.IsTrue(Pos('MyPkg290.bpl', LProduct.NamesText) > 0,
    'The suffixed package is the product binary');
  var LNone := FindGroup(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(1, LNone.Count);
  Assert.AreEqual('other.bpl', LNone.Names[0]);
end;

procedure TReportOverviewTests.Licences_LibPrefix_MatchesProject;
begin
  FData.Metadata.Licence := 'MIT';
  FData.Metadata.ProductName := 'Demo';
  FData.ProjectInfo.ProjectName := 'Demo';
  AddFile('libDemo.so', 'file');
  AddFile('vendor.dll', 'library');
  var LOverview := BuildReportOverview(FData);
  var LProduct := FindGroup(LOverview.Licences, 'MIT');
  Assert.IsTrue(Pos('libDemo.so', LProduct.NamesText) > 0,
    'A lib-prefixed binary of the project is the product');
  var LNone := FindGroup(LOverview.Licences, cNoLicenceGroupTitle);
  Assert.AreEqual(1, LNone.Count);
  Assert.AreEqual('vendor.dll', LNone.Names[0]);
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
