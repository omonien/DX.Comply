/// <summary>
/// DX.Comply.Tests.DependencyGraph
/// DUnitX tests for direct uses edges in CycloneDX and SPDX.
/// </summary>
///
/// <remarks>
/// The Pascal fixtures are written into a small temp directory for each test.
/// They are not files from the repository, so RepoRoot is not used.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.DependencyGraph;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  DUnitX.TestFramework,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.CycloneDx.XmlWriter,
  DX.Comply.DependencyGraph,
  DX.Comply.Engine.Intf,
  DX.Comply.Spdx.Writer;

type
  /// <summary>
  /// Direct uses edges, completeness, and the matching SPDX relationships.
  /// </summary>
  [TestFixture]
  TDependencyGraphTests = class
  private
    FTempDir: string;
    FJsonFile: string;
    FXmlFile: string;
    FSpdxFile: string;
    FArtefacts: TArtefactList;
    FMetadata: TSbomMetadata;
    FProjectInfo: TProjectInfo;
    procedure WriteUnit(const AUnitName: string); overload;
    procedure WriteUnit(const AUnitName: string; const AUses: array of string); overload;
    procedure AddExe;
    procedure AddUnit(const AUnitName: string);
    procedure AddFile(const ARelativePath, AArtefactType: string);
    function WriteJson: TJSONObject;
    function WriteXml: string;
    function WriteSpdx: TJSONObject;
    function DependsOf(ADeps: TJSONArray; const ARef: string): TJSONArray;
    function CompositionRefs(AJson: TJSONObject; const AAggregate: string): TJSONArray;
    function PackageId(AJson: TJSONObject; const AName: string): string;
    function HasRelationship(AJson: TJSONObject; const AFrom, AKind, ATo: string): Boolean;
    function XmlDependencyBody(const AContent, ARef: string): string;
    function PropertyValue(AProperties: TJSONArray; const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    /// <summary>A uses B and B uses C. The root depends on the program, not on C directly.</summary>
    [Test]
    procedure Json_Chain_WritesDirectUsesEdges;

    /// <summary>The B edge is inside A's dependency element, not the first dependency in the file.</summary>
    [Test]
    procedure Xml_Chain_ScopesEdgesToTheSourceElement;

    /// <summary>SPDX keeps CONTAINS on the program and adds DEPENDS_ON for each uses edge.</summary>
    [Test]
    procedure Spdx_Chain_DependsOnAndContains;

    /// <summary>A DCU with no source is a leaf, marked unresolved, and stays incomplete.</summary>
    [Test]
    procedure Json_DcuWithoutSource_IsUnresolvedAndIncomplete;

    /// <summary>The unresolved property is on the DCU element, not on the executable.</summary>
    [Test]
    procedure Xml_DcuWithoutSource_WritesUnresolvedProperty;

    /// <summary>A uses name that is not in the SBOM is omitted. The unit stays incomplete.</summary>
    [Test]
    procedure Json_UnmatchedName_OmitsEdgeAndStaysIncomplete;

    /// <summary>A uses B and B uses A. Both edges are kept.</summary>
    [Test]
    procedure Json_Cycle_KeepsBothDirections;

    /// <summary>Targets are sorted by unit name, not by the order written in the uses clause.</summary>
    [Test]
    procedure Json_UsesTargets_AreSortedByUnitName;

    /// <summary>Runtime packages and DLLs stay grouped on the program. The uses edge is separate.</summary>
    [Test]
    procedure Json_GroupedDeliverableOrder_StaysGrouped;

    /// <summary>SysUtils is not linked when two units share that short name.</summary>
    [Test]
    procedure Json_AmbiguousShortName_DoesNotPickAnEdge;

    /// <summary>SysUtils matches System.SysUtils when that short name is unique.</summary>
    [Test]
    procedure Json_UniqueShortName_MatchesTheOnlyUnit;

    /// <summary>Cached uses names are used even when the .pas is no longer on disk.</summary>
    [Test]
    procedure Json_CachedUses_DoesNotNeedTheFileOnDisk;

    /// <summary>A manifest library is complete. A matched DCU stays incomplete.</summary>
    [Test]
    procedure Json_ManifestLibrary_IsComplete;
  end;

implementation

procedure TDependencyGraphTests.Setup;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FTempDir := TPath.Combine(TPath.GetTempPath, 'dxcomply-graph-' +
    Copy(GUIDToString(LGuid), 2, 36));
  TDirectory.CreateDirectory(FTempDir);
  FJsonFile := TPath.Combine(FTempDir, 'bom.json');
  FXmlFile := TPath.Combine(FTempDir, 'bom.xml');
  FSpdxFile := TPath.Combine(FTempDir, 'bom.spdx.json');
  FArtefacts := TArtefactList.Create;
  FMetadata := Default(TSbomMetadata);
  FMetadata.ProductName := 'TestApp';
  FMetadata.ProductVersion := '1.0.0';
  FMetadata.Timestamp := '2026-01-01T00:00:00Z';
  FMetadata.ToolName := 'DX.Comply';
  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'TestApp';
  FProjectInfo.Version := '1.0.0';
end;

procedure TDependencyGraphTests.TearDown;
begin
  FArtefacts.Free;
  FProjectInfo.Free;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TDependencyGraphTests.WriteUnit(const AUnitName: string);
begin
  WriteUnit(AUnitName, ['']);
end;

procedure TDependencyGraphTests.WriteUnit(const AUnitName: string;
  const AUses: array of string);
var
  LText, LUses: string;
  I: Integer;
begin
  LUses := '';
  if (Length(AUses) > 0) and (AUses[0] <> '') then
  begin
    LUses := 'uses ';
    for I := 0 to High(AUses) do
    begin
      if I > 0 then
        LUses := LUses + ', ';
      LUses := LUses + AUses[I];
    end;
    LUses := LUses + ';' + sLineBreak;
  end;
  LText :=
    'unit ' + AUnitName + ';' + sLineBreak +
    'interface' + sLineBreak +
    LUses +
    'implementation' + sLineBreak +
    'end.' + sLineBreak;
  TFile.WriteAllText(TPath.Combine(FTempDir, AUnitName + '.pas'), LText, TEncoding.UTF8);
end;

procedure TDependencyGraphTests.AddFile(const ARelativePath, AArtefactType: string);
var
  LInfo: TArtefactInfo;
begin
  LInfo := Default(TArtefactInfo);
  LInfo.RelativePath := ARelativePath;
  LInfo.FilePath := TPath.Combine(FTempDir, ARelativePath);
  LInfo.ArtefactType := AArtefactType;
  LInfo.FileSize := 10;
  LInfo.Hash := 'aa';
  FArtefacts.Add(LInfo);
end;

procedure TDependencyGraphTests.AddExe;
begin
  AddFile('TestApp.exe', 'application');
end;

procedure TDependencyGraphTests.AddUnit(const AUnitName: string);
begin
  AddFile(AUnitName + '.pas', 'unit-evidence');
end;

function TDependencyGraphTests.WriteJson: TJSONObject;
var
  LWriter: ISbomWriter;
  LText: string;
begin
  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FJsonFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FJsonFile, TEncoding.UTF8);
  Result := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(Result, 'CycloneDX JSON must parse');
end;

function TDependencyGraphTests.WriteXml: string;
var
  LWriter: ISbomWriter;
begin
  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FXmlFile, FMetadata, FArtefacts, FProjectInfo));
  Result := TFile.ReadAllText(FXmlFile, TEncoding.UTF8);
end;

function TDependencyGraphTests.WriteSpdx: TJSONObject;
var
  LWriter: ISbomWriter;
  LText: string;
begin
  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FSpdxFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FSpdxFile, TEncoding.UTF8);
  Result := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(Result, 'SPDX JSON must parse');
end;

function TDependencyGraphTests.DependsOf(ADeps: TJSONArray; const ARef: string): TJSONArray;
var
  I: Integer;
  LDep: TJSONObject;
begin
  Result := nil;
  if not Assigned(ADeps) then
    Exit;
  for I := 0 to ADeps.Count - 1 do
  begin
    LDep := ADeps.Items[I] as TJSONObject;
    if LDep.GetValue<string>('ref') = ARef then
      Exit(LDep.GetValue('dependsOn') as TJSONArray);
  end;
end;

function TDependencyGraphTests.CompositionRefs(AJson: TJSONObject;
  const AAggregate: string): TJSONArray;
var
  LCompositions: TJSONArray;
  LComposition: TJSONObject;
  I: Integer;
begin
  Result := nil;
  LCompositions := AJson.GetValue('compositions') as TJSONArray;
  if not Assigned(LCompositions) then
    Exit;
  for I := 0 to LCompositions.Count - 1 do
  begin
    LComposition := LCompositions.Items[I] as TJSONObject;
    if LComposition.GetValue<string>('aggregate') = AAggregate then
      Exit(LComposition.GetValue('dependencies') as TJSONArray);
  end;
end;

function TDependencyGraphTests.PackageId(AJson: TJSONObject; const AName: string): string;
var
  LPackages: TJSONArray;
  LPackage: TJSONObject;
  I: Integer;
begin
  Result := '';
  LPackages := AJson.GetValue('packages') as TJSONArray;
  for I := 0 to LPackages.Count - 1 do
  begin
    LPackage := LPackages.Items[I] as TJSONObject;
    if LPackage.GetValue<string>('name') = AName then
      Exit(LPackage.GetValue<string>('SPDXID'));
  end;
end;

function TDependencyGraphTests.HasRelationship(AJson: TJSONObject;
  const AFrom, AKind, ATo: string): Boolean;
var
  LRels: TJSONArray;
  LRel: TJSONObject;
  I: Integer;
begin
  Result := False;
  LRels := AJson.GetValue('relationships') as TJSONArray;
  for I := 0 to LRels.Count - 1 do
  begin
    LRel := LRels.Items[I] as TJSONObject;
    if (LRel.GetValue<string>('spdxElementId') = AFrom) and
       (LRel.GetValue<string>('relationshipType') = AKind) and
       (LRel.GetValue<string>('relatedSpdxElement') = ATo) then
      Exit(True);
  end;
end;

function TDependencyGraphTests.XmlDependencyBody(const AContent, ARef: string): string;
var
  LMarker: string;
  LStart, LEnd: Integer;
begin
  LMarker := '<dependency ref="' + ARef + '">';
  LStart := Pos(LMarker, AContent);
  Assert.IsTrue(LStart > 0, 'Missing open dependency for ' + ARef);
  LEnd := Pos('</dependency>', AContent, LStart);
  Assert.IsTrue(LEnd > LStart, 'Missing close dependency for ' + ARef);
  Result := Copy(AContent, LStart, LEnd - LStart);
end;

function TDependencyGraphTests.PropertyValue(AProperties: TJSONArray;
  const AName: string): string;
var
  I: Integer;
  LProp: TJSONObject;
begin
  Result := '';
  if not Assigned(AProperties) then
    Exit;
  for I := 0 to AProperties.Count - 1 do
  begin
    LProp := AProperties.Items[I] as TJSONObject;
    if LProp.GetValue<string>('name') = AName then
      Exit(LProp.GetValue<string>('value'));
  end;
end;

procedure TDependencyGraphTests.Json_Chain_WritesDirectUsesEdges;
var
  LJson: TJSONObject;
  LDeps, LDepends, LIncomplete, LComplete, LComponents: TJSONArray;
begin
  WriteUnit('UnitA', ['UnitB']);
  WriteUnit('UnitB', ['UnitC']);
  WriteUnit('UnitC');
  AddExe;
  AddUnit('UnitA');
  AddUnit('UnitB');
  AddUnit('UnitC');

  LJson := WriteJson;
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    Assert.AreEqual(NativeInt(4), NativeInt(LComponents.Count),
      'A uses name that is already a unit must not add another component');

    LDeps := LJson.GetValue('dependencies') as TJSONArray;
    LDepends := DependsOf(LDeps, 'TestApp');
    Assert.AreEqual(NativeInt(1), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-0', LDepends.Items[0].Value);

    LDepends := DependsOf(LDeps, 'comp-0');
    Assert.AreEqual(NativeInt(3), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-1', LDepends.Items[0].Value);
    Assert.AreEqual('comp-2', LDepends.Items[1].Value);
    Assert.AreEqual('comp-3', LDepends.Items[2].Value);

    LDepends := DependsOf(LDeps, 'comp-1');
    Assert.AreEqual(NativeInt(1), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-2', LDepends.Items[0].Value, 'UnitA depends on UnitB');

    LDepends := DependsOf(LDeps, 'comp-2');
    Assert.AreEqual(NativeInt(1), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-3', LDepends.Items[0].Value, 'UnitB depends on UnitC');

    Assert.IsNull(DependsOf(LDeps, 'comp-3'),
      'UnitC has an empty uses clause and is omitted, not written as an empty dependsOn');

    LIncomplete := CompositionRefs(LJson, 'incomplete');
    LComplete := CompositionRefs(LJson, 'complete');
    Assert.IsNotNull(LIncomplete);
    Assert.IsNotNull(LComplete);
    Assert.AreEqual('TestApp', LIncomplete.Items[0].Value);
    Assert.AreEqual(NativeInt(2), NativeInt(LIncomplete.Count));
    Assert.AreEqual('comp-0', LIncomplete.Items[1].Value);
    Assert.AreEqual(NativeInt(3), NativeInt(LComplete.Count));
    Assert.AreEqual('comp-1', LComplete.Items[0].Value);
    Assert.AreEqual('comp-2', LComplete.Items[1].Value);
    Assert.AreEqual('comp-3', LComplete.Items[2].Value);
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Xml_Chain_ScopesEdgesToTheSourceElement;
var
  LContent, LUnitA, LUnitB, LIncomplete, LComplete: string;
  LIncompleteAt, LCompleteAt: Integer;
begin
  WriteUnit('UnitA', ['UnitB']);
  WriteUnit('UnitB', ['UnitC']);
  WriteUnit('UnitC');
  AddExe;
  AddUnit('UnitA');
  AddUnit('UnitB');
  AddUnit('UnitC');

  LContent := WriteXml;
  LUnitA := XmlDependencyBody(LContent, 'comp-1');
  LUnitB := XmlDependencyBody(LContent, 'comp-2');
  Assert.IsTrue(Pos('<dependency ref="comp-2"/>', LUnitA) > 0, LUnitA);
  Assert.AreEqual(0, Pos('<dependency ref="comp-3"/>', LUnitA), LUnitA);
  Assert.IsTrue(Pos('<dependency ref="comp-3"/>', LUnitB) > 0, LUnitB);
  Assert.AreEqual(0, Pos('<dependency ref="comp-2"/>', LUnitB), LUnitB);

  LIncompleteAt := Pos('<aggregate>incomplete</aggregate>', LContent);
  LCompleteAt := Pos('<aggregate>complete</aggregate>', LContent);
  Assert.IsTrue(LIncompleteAt > 0);
  Assert.IsTrue(LCompleteAt > LIncompleteAt, 'The incomplete aggregate stays first');
  LIncomplete := Copy(LContent, LIncompleteAt, LCompleteAt - LIncompleteAt);
  LComplete := Copy(LContent, LCompleteAt, MaxInt);
  Assert.IsTrue(Pos('<dependency ref="TestApp"/>', LIncomplete) > 0, LIncomplete);
  Assert.IsTrue(Pos('<dependency ref="comp-0"/>', LIncomplete) > 0, LIncomplete);
  Assert.AreEqual(0, Pos('<dependency ref="comp-1"/>', LIncomplete), LIncomplete);
  Assert.IsTrue(Pos('<dependency ref="comp-1"/>', LComplete) > 0, LComplete);
  Assert.IsTrue(Pos('<dependency ref="comp-3"/>', LComplete) > 0, LComplete);
  Assert.AreEqual(0, Pos('<dependency ref="TestApp"/>', LComplete), LComplete);
end;

procedure TDependencyGraphTests.Spdx_Chain_DependsOnAndContains;
var
  LJson: TJSONObject;
  LExe, LA, LB, LC: string;
  LRels: TJSONArray;
begin
  WriteUnit('UnitA', ['UnitB']);
  WriteUnit('UnitB', ['UnitC']);
  WriteUnit('UnitC');
  AddExe;
  AddUnit('UnitA');
  AddUnit('UnitB');
  AddUnit('UnitC');

  LJson := WriteSpdx;
  try
    LExe := PackageId(LJson, 'TestApp.exe');
    LA := PackageId(LJson, 'UnitA.pas');
    LB := PackageId(LJson, 'UnitB.pas');
    LC := PackageId(LJson, 'UnitC.pas');
    Assert.AreNotEqual('', LExe);
    Assert.AreNotEqual('', LA);

    Assert.IsTrue(HasRelationship(LJson, LExe, 'CONTAINS', LA),
      'The program still contains the linked unit');
    Assert.IsTrue(HasRelationship(LJson, LExe, 'CONTAINS', LB));
    Assert.IsTrue(HasRelationship(LJson, LExe, 'CONTAINS', LC));
    Assert.IsTrue(HasRelationship(LJson, LA, 'DEPENDS_ON', LB),
      'UnitA DEPENDS_ON UnitB');
    Assert.IsTrue(HasRelationship(LJson, LB, 'DEPENDS_ON', LC),
      'UnitB DEPENDS_ON UnitC');
    Assert.IsFalse(HasRelationship(LJson, LA, 'DEPENDS_ON', LC),
      'The chain is not flattened to a direct edge from UnitA to UnitC');

    LRels := LJson.GetValue('relationships') as TJSONArray;
    // 4 DESCRIBES, 3 CONTAINS, 2 uses DEPENDS_ON.
    Assert.AreEqual(NativeInt(9), NativeInt(LRels.Count));
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Json_DcuWithoutSource_IsUnresolvedAndIncomplete;
var
  LJson, LComponent: TJSONObject;
  LDeps, LIncomplete, LProperties: TJSONArray;
begin
  AddExe;
  AddFile('System.dcu', 'unit-evidence');

  LJson := WriteJson;
  try
    LComponent := (LJson.GetValue('components') as TJSONArray).Items[1] as TJSONObject;
    LProperties := LComponent.GetValue('properties') as TJSONArray;
    Assert.AreEqual(cUnresolvedDependenciesValue,
      PropertyValue(LProperties, cUnresolvedDependenciesProperty));
    Assert.IsNull(DependsOf(LJson.GetValue('dependencies') as TJSONArray, 'comp-1'),
      'A DCU with no source has no dependsOn entry');

    LDeps := CompositionRefs(LJson, 'complete');
    Assert.IsNull(LDeps, 'Nothing in this document is a complete uses graph');
    LIncomplete := CompositionRefs(LJson, 'incomplete');
    Assert.AreEqual('TestApp', LIncomplete.Items[0].Value);
    Assert.AreEqual(NativeInt(3), NativeInt(LIncomplete.Count));
    Assert.AreEqual('comp-0', LIncomplete.Items[1].Value);
    Assert.AreEqual('comp-1', LIncomplete.Items[2].Value);
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Xml_DcuWithoutSource_WritesUnresolvedProperty;
var
  LContent, LExe, LDcu: string;
  LExeAt, LDcuAt: Integer;
begin
  AddExe;
  AddFile('System.dcu', 'unit-evidence');
  LContent := WriteXml;
  LExeAt := Pos('bom-ref="comp-0"', LContent);
  LDcuAt := Pos('bom-ref="comp-1"', LContent);
  Assert.IsTrue(LExeAt > 0);
  Assert.IsTrue(LDcuAt > LExeAt);
  LExe := Copy(LContent, LExeAt, LDcuAt - LExeAt);
  LDcu := Copy(LContent, LDcuAt, Pos('</component>', LContent, LDcuAt) - LDcuAt);
  Assert.AreEqual(0, Pos(cUnresolvedDependenciesProperty, LExe), LExe);
  Assert.IsTrue(Pos('<property name="' + cUnresolvedDependenciesProperty + '">' +
    cUnresolvedDependenciesValue + '</property>', LDcu) > 0, LDcu);
end;

procedure TDependencyGraphTests.Json_UnmatchedName_OmitsEdgeAndStaysIncomplete;
var
  LJson, LComponent: TJSONObject;
  LComponents, LIncomplete, LProperties: TJSONArray;
begin
  WriteUnit('UnitA', ['MissingUnit']);
  AddExe;
  AddUnit('UnitA');

  LJson := WriteJson;
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    Assert.AreEqual(NativeInt(2), NativeInt(LComponents.Count),
      'MissingUnit must not be invented');
    Assert.IsNull(DependsOf(LJson.GetValue('dependencies') as TJSONArray, 'comp-1'));
    Assert.IsNull(CompositionRefs(LJson, 'complete'));
    LIncomplete := CompositionRefs(LJson, 'incomplete');
    Assert.AreEqual(NativeInt(3), NativeInt(LIncomplete.Count));
    Assert.AreEqual('comp-1', LIncomplete.Items[2].Value);

    LComponent := LComponents.Items[1] as TJSONObject;
    LProperties := LComponent.GetValue('properties') as TJSONArray;
    Assert.AreEqual('', PropertyValue(LProperties, cUnresolvedDependenciesProperty),
      'A unit whose source was read is not unresolved-no-source');
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Json_Cycle_KeepsBothDirections;
var
  LJson: TJSONObject;
  LDeps, LDepends, LComplete: TJSONArray;
begin
  WriteUnit('UnitA', ['UnitB']);
  WriteUnit('UnitB', ['UnitA']);
  AddExe;
  AddUnit('UnitA');
  AddUnit('UnitB');

  LJson := WriteJson;
  try
    LDeps := LJson.GetValue('dependencies') as TJSONArray;
    LDepends := DependsOf(LDeps, 'comp-1');
    Assert.AreEqual(NativeInt(1), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-2', LDepends.Items[0].Value);
    LDepends := DependsOf(LDeps, 'comp-2');
    Assert.AreEqual(NativeInt(1), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-1', LDepends.Items[0].Value);
    LComplete := CompositionRefs(LJson, 'complete');
    Assert.AreEqual(NativeInt(2), NativeInt(LComplete.Count));
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Json_UsesTargets_AreSortedByUnitName;
var
  LJson: TJSONObject;
  LDepends: TJSONArray;
begin
  WriteUnit('UnitA', ['UnitC', 'UnitB']);
  WriteUnit('UnitB');
  WriteUnit('UnitC');
  AddExe;
  AddUnit('UnitA');
  AddUnit('UnitB');
  AddUnit('UnitC');

  LJson := WriteJson;
  try
    LDepends := DependsOf(LJson.GetValue('dependencies') as TJSONArray, 'comp-1');
    Assert.AreEqual(NativeInt(2), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-2', LDepends.Items[0].Value, 'UnitB sorts before UnitC');
    Assert.AreEqual('comp-3', LDepends.Items[1].Value);
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Json_GroupedDeliverableOrder_StaysGrouped;
var
  LJson: TJSONObject;
  LDeps, LProject, LProgram, LUses: TJSONArray;
begin
  WriteUnit('UnitA', ['UnitB']);
  WriteUnit('UnitB');
  AddExe;
  AddFile('rtl.bpl', 'runtime-package');
  AddFile('vendor.dll', 'external-reference');
  AddUnit('UnitA');
  AddUnit('UnitB');

  LJson := WriteJson;
  try
    LDeps := LJson.GetValue('dependencies') as TJSONArray;
    LProject := DependsOf(LDeps, 'TestApp');
    Assert.AreEqual(NativeInt(1), NativeInt(LProject.Count));
    Assert.AreEqual('comp-0', LProject.Items[0].Value);

    LProgram := DependsOf(LDeps, 'comp-0');
    Assert.AreEqual(NativeInt(4), NativeInt(LProgram.Count));
    Assert.AreEqual('comp-1', LProgram.Items[0].Value, 'runtime package stays first');
    Assert.AreEqual('comp-2', LProgram.Items[1].Value, 'external DLL stays second');
    Assert.AreEqual('comp-3', LProgram.Items[2].Value);
    Assert.AreEqual('comp-4', LProgram.Items[3].Value);

    LUses := DependsOf(LDeps, 'comp-3');
    Assert.AreEqual(NativeInt(1), NativeInt(LUses.Count));
    Assert.AreEqual('comp-4', LUses.Items[0].Value);
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Json_AmbiguousShortName_DoesNotPickAnEdge;
var
  LJson: TJSONObject;
  LIncomplete: TJSONArray;
begin
  WriteUnit('UnitA', ['SysUtils']);
  WriteUnit('System.SysUtils');
  WriteUnit('Vcl.SysUtils');
  AddExe;
  AddUnit('UnitA');
  AddUnit('System.SysUtils');
  AddUnit('Vcl.SysUtils');

  LJson := WriteJson;
  try
    Assert.IsNull(DependsOf(LJson.GetValue('dependencies') as TJSONArray, 'comp-1'),
      'An ambiguous short name must not pick either unit');
    LIncomplete := CompositionRefs(LJson, 'incomplete');
    Assert.AreEqual('comp-1', LIncomplete.Items[2].Value, 'UnitA stays incomplete');
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Json_UniqueShortName_MatchesTheOnlyUnit;
var
  LJson: TJSONObject;
  LDepends, LComplete: TJSONArray;
begin
  WriteUnit('UnitA', ['SysUtils']);
  WriteUnit('System.SysUtils');
  AddExe;
  AddUnit('UnitA');
  AddUnit('System.SysUtils');

  LJson := WriteJson;
  try
    LDepends := DependsOf(LJson.GetValue('dependencies') as TJSONArray, 'comp-1');
    Assert.AreEqual(NativeInt(1), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-2', LDepends.Items[0].Value);
    LComplete := CompositionRefs(LJson, 'complete');
    Assert.AreEqual(NativeInt(2), NativeInt(LComplete.Count));
    Assert.AreEqual('comp-1', LComplete.Items[0].Value);
    Assert.AreEqual('comp-2', LComplete.Items[1].Value);
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Json_CachedUses_DoesNotNeedTheFileOnDisk;
var
  LJson: TJSONObject;
  LInfo: TArtefactInfo;
  LDepends: TJSONArray;
begin
  AddExe;
  LInfo := Default(TArtefactInfo);
  LInfo.RelativePath := 'UnitA.pas';
  LInfo.FilePath := TPath.Combine(FTempDir, 'not-written', 'UnitA.pas');
  LInfo.ArtefactType := 'unit-evidence';
  LInfo.FileSize := 10;
  LInfo.UsesCached := True;
  SetLength(LInfo.UsedUnitNames, 1);
  LInfo.UsedUnitNames[0] := 'UnitB';
  FArtefacts.Add(LInfo);

  LInfo := Default(TArtefactInfo);
  LInfo.RelativePath := 'UnitB.pas';
  LInfo.FilePath := TPath.Combine(FTempDir, 'not-written', 'UnitB.pas');
  LInfo.ArtefactType := 'unit-evidence';
  LInfo.FileSize := 10;
  LInfo.UsesCached := True;
  FArtefacts.Add(LInfo);

  Assert.IsFalse(TFile.Exists(FArtefacts[1].FilePath));
  LJson := WriteJson;
  try
    LDepends := DependsOf(LJson.GetValue('dependencies') as TJSONArray, 'comp-1');
    Assert.AreEqual(NativeInt(1), NativeInt(LDepends.Count));
    Assert.AreEqual('comp-2', LDepends.Items[0].Value);
  finally
    LJson.Free;
  end;
end;

procedure TDependencyGraphTests.Json_ManifestLibrary_IsComplete;
var
  LJson: TJSONObject;
  LDeps, LLibrary, LComplete, LIncomplete: TJSONArray;
  I: Integer;
  LFoundUnit: Boolean;
begin
  AddExe;
  AddFile('UnitB.dcu', 'unit-evidence');
  FMetadata.ComponentManifestJson :=
    '{"schema_version":"1.0","components":[{"name":"LibA","version":"1.0.0",' +
    '"licence":"MIT","type":"library","units_exact":["UnitB"]}]}';

  LJson := WriteJson;
  try
    LDeps := LJson.GetValue('dependencies') as TJSONArray;
    LLibrary := DependsOf(LDeps, 'manifest-0');
    Assert.IsNotNull(LLibrary, 'The library still depends on the matched unit');
    Assert.AreEqual(NativeInt(1), NativeInt(LLibrary.Count));
    Assert.AreEqual('comp-1', LLibrary.Items[0].Value);

    LComplete := CompositionRefs(LJson, 'complete');
    Assert.AreEqual(NativeInt(1), NativeInt(LComplete.Count));
    Assert.AreEqual('manifest-0', LComplete.Items[0].Value);

    LIncomplete := CompositionRefs(LJson, 'incomplete');
    Assert.AreEqual('TestApp', LIncomplete.Items[0].Value);
    LFoundUnit := False;
    for I := 0 to LIncomplete.Count - 1 do
      if LIncomplete.Items[I].Value = 'comp-1' then
        LFoundUnit := True;
    Assert.IsTrue(LFoundUnit, 'The DCU stays in the incomplete set');
  finally
    LJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDependencyGraphTests);

end.
