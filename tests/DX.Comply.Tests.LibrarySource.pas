/// <summary>
/// DX.Comply.Tests.LibrarySource
/// DUnitX tests for library mode (issue #64).
/// </summary>
///
/// <remarks>
/// The fixture package is tests\fixtures\library, located through RepoRoot.
/// The engine test writes into a temporary directory and deletes it.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.LibrarySource;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.LibrarySource,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.CycloneDx.XmlWriter,
  DX.Comply.CLI.Options;

type
  [TestFixture]
  TLibrarySourceTests = class
  private
    function FixtureDir: string;
    function RelativePaths(const AFiles: TArray<TLibrarySourceFile>): TArray<string>;
    function Contains(const AValues: TArray<string>; const AValue: string): Boolean;
    function PropertyValue(AComponent: TJSONObject; const AName: string): string;
    procedure WriteMixedArtefacts(const AWriter: ISbomWriter; const AOutput: string);
  public
    [Test]
    procedure ParsePackage_ContainsAndRequires;
    [Test]
    procedure ParseProgram_UsesIn_SkipsUnitsWithoutPath;
    [Test]
    procedure GithubPurl_FromRepoUrl;
    [Test]
    procedure FrameworkPackages_AreRtlVclFmx;
    [Test]
    procedure Collect_PackageOnly_ListsContainedUnitsFormsAndPackage;
    [Test]
    procedure Collect_PackageAndSourceDir_FiltersAndDeduplicates;
    [Test]
    procedure Generate_LibraryMode_WritesLibrarySbom;
    [Test]
    procedure CycloneDxJson_LibraryFile_NoHashVersionNoPurl;
    [Test]
    procedure CycloneDxXml_LibraryFile_NoHashVersionNoPurl;
    [Test]
    procedure CliOptions_LibraryMode_ProjectOptionalWithSourceDir;
    [Test]
    procedure CliOptions_BuildMode_StillRequiresProject;
  end;

implementation

uses
  DX.Comply.Tests.Paths;

function TLibrarySourceTests.FixtureDir: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests' + PathDelim + 'fixtures' + PathDelim + 'library');
end;

function TLibrarySourceTests.RelativePaths(
  const AFiles: TArray<TLibrarySourceFile>): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(AFiles));
  for I := 0 to High(AFiles) do
    Result[I] := AFiles[I].RelativePath;
end;

function TLibrarySourceTests.Contains(const AValues: TArray<string>;
  const AValue: string): Boolean;
var
  LValue: string;
begin
  Result := False;
  for LValue in AValues do
    if SameText(LValue, AValue) then
      Exit(True);
end;

function TLibrarySourceTests.PropertyValue(AComponent: TJSONObject;
  const AName: string): string;
var
  LProps: TJSONArray;
  I: Integer;
begin
  Result := '';
  LProps := AComponent.GetValue('properties') as TJSONArray;
  if LProps = nil then
    Exit;
  for I := 0 to LProps.Count - 1 do
    if (LProps.Items[I] as TJSONObject).GetValue<string>('name') = AName then
      Exit((LProps.Items[I] as TJSONObject).GetValue<string>('value'));
end;

procedure TLibrarySourceTests.WriteMixedArtefacts(const AWriter: ISbomWriter;
  const AOutput: string);
var
  LMetadata: TSbomMetadata;
  LProjectInfo: TProjectInfo;
  LArtefacts: TArtefactList;
  LArtefact: TArtefactInfo;
begin
  LMetadata := Default(TSbomMetadata);
  LMetadata.ProductName := 'Lib';
  LMetadata.Timestamp := '2026-01-01T00:00:00Z';
  LMetadata.ToolName := 'DX.Comply';
  LMetadata.ComponentType := 'library';
  LProjectInfo := TProjectInfo.Create;
  LArtefacts := TArtefactList.Create;
  try
    // A library source file without a known release version.
    LArtefact := Default(TArtefactInfo);
    LArtefact.FilePath := 'C:\Lib\src\A.pas';
    LArtefact.RelativePath := 'src/A.pas';
    LArtefact.ComponentName := 'src/A.pas';
    LArtefact.ArtefactType := 'file';
    LArtefact.LibrarySourceFile := True;
    LArtefact.Hash := StringOfChar('a', 64);
    LArtefact.FileSize := 10;
    LArtefacts.Add(LArtefact);
    // A build mode file keeps the hash prefix version and the file: purl.
    LArtefact := Default(TArtefactInfo);
    LArtefact.FilePath := 'C:\Build\data.res';
    LArtefact.RelativePath := 'data.res';
    LArtefact.ArtefactType := 'resource';
    LArtefact.Hash := StringOfChar('b', 64);
    LArtefact.FileSize := 20;
    LArtefacts.Add(LArtefact);
    Assert.IsTrue(AWriter.Write(AOutput, LMetadata, LArtefacts, LProjectInfo));
  finally
    LArtefacts.Free;
    LProjectInfo.Free;
  end;
end;

procedure TLibrarySourceTests.CycloneDxJson_LibraryFile_NoHashVersionNoPurl;
var
  LOutput: string;
  LWriter: ISbomWriter;
  LJson, LLib, LBuild: TJSONObject;
  LComponents: TJSONArray;
begin
  LOutput := TPath.Combine(TPath.GetTempPath, 'dxc-libfile-' + TGUID.NewGuid.ToString + '.json');
  try
    LWriter := TCycloneDxJsonWriter.Create;
    WriteMixedArtefacts(LWriter, LOutput);
    LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(LOutput, TEncoding.UTF8)) as TJSONObject;
    try
      LComponents := LJson.GetValue('components') as TJSONArray;
      LLib := LComponents.Items[0] as TJSONObject;
      LBuild := LComponents.Items[1] as TJSONObject;
      Assert.IsNull(LLib.GetValue('version'), 'no hash prefix as version');
      Assert.IsNull(LLib.GetValue('purl'), 'no file: purl');
      Assert.AreEqual('comp-0', LLib.GetValue<string>('bom-ref'));
      Assert.AreEqual('src/A.pas',
        PropertyValue(LLib, 'net.developer-experts.dx-comply:relativePath'));
      Assert.AreEqual(StringOfChar('b', 12), LBuild.GetValue<string>('version'),
        'build mode unchanged');
      Assert.AreEqual('file:data.res', LBuild.GetValue<string>('purl'),
        'build mode unchanged');
      Assert.AreEqual('',
        PropertyValue(LBuild, 'net.developer-experts.dx-comply:relativePath'));
    finally
      LJson.Free;
    end;
  finally
    if TFile.Exists(LOutput) then
      TFile.Delete(LOutput);
  end;
end;

procedure TLibrarySourceTests.CycloneDxXml_LibraryFile_NoHashVersionNoPurl;
var
  LOutput, LText: string;
  LWriter: ISbomWriter;
begin
  LOutput := TPath.Combine(TPath.GetTempPath, 'dxc-libfile-' + TGUID.NewGuid.ToString + '.xml');
  try
    LWriter := TCycloneDxXmlWriter.Create;
    WriteMixedArtefacts(LWriter, LOutput);
    LText := TFile.ReadAllText(LOutput, TEncoding.UTF8);
    Assert.IsFalse(LText.Contains('<version>' + StringOfChar('a', 12)));
    Assert.IsFalse(LText.Contains('file:src/A.pas'));
    Assert.IsTrue(LText.Contains(
      '<property name="net.developer-experts.dx-comply:relativePath">src/A.pas</property>'));
    Assert.IsTrue(LText.Contains('<version>' + StringOfChar('b', 12) + '</version>'),
      'build mode unchanged');
    Assert.IsTrue(LText.Contains('<purl>file:data.res</purl>'), 'build mode unchanged');
  finally
    if TFile.Exists(LOutput) then
      TFile.Delete(LOutput);
  end;
end;

procedure TLibrarySourceTests.ParsePackage_ContainsAndRequires;
const
  cText =
    'package Demo;'#13#10 +
    '{ requires inside a comment: ignored }'#13#10 +
    'requires'#13#10 +
    '  rtl,'#13#10 +
    '  vcl, // trailing comment'#13#10 +
    '  RTL;'#13#10 +
    'contains'#13#10 +
    '  Demo.A in ''Demo.A.pas'','#13#10 +
    '  Demo.B in ''sub\Demo.B.pas'','#13#10 +
    '  Demo.C;'#13#10 +
    'end.';
var
  LRequires: TArray<string>;
  LFound: Boolean;
  LUnits: TArray<TLibraryUnitRef>;
begin
  LRequires := ParsePackageRequires(cText, LFound);
  Assert.IsTrue(LFound);
  Assert.AreEqual(2, Integer(Length(LRequires)), 'rtl is listed once');
  Assert.AreEqual('rtl', LRequires[0]);
  Assert.AreEqual('vcl', LRequires[1]);

  LUnits := ParsePackageContains(cText);
  Assert.AreEqual(3, Integer(Length(LUnits)));
  Assert.AreEqual('Demo.A', LUnits[0].Name);
  Assert.AreEqual('Demo.A.pas', LUnits[0].WrittenPath);
  Assert.AreEqual('sub\Demo.B.pas', LUnits[1].WrittenPath);
  Assert.AreEqual('', LUnits[2].WrittenPath);
end;

procedure TLibrarySourceTests.ParseProgram_UsesIn_SkipsUnitsWithoutPath;
const
  cText =
    'program Demo;'#13#10 +
    'uses'#13#10 +
    '  System.SysUtils,'#13#10 +
    '  Demo.A in ''Demo.A.pas'','#13#10 +
    '  Demo.B in ''lib\Demo.B.pas'';'#13#10 +
    'begin'#13#10 +
    'end.';
var
  LUnits: TArray<TLibraryUnitRef>;
begin
  LUnits := ParseProgramUsesIn(cText);
  Assert.AreEqual(2, Integer(Length(LUnits)));
  Assert.AreEqual('Demo.A', LUnits[0].Name);
  Assert.AreEqual('lib\Demo.B.pas', LUnits[1].WrittenPath);
end;

procedure TLibrarySourceTests.GithubPurl_FromRepoUrl;
begin
  Assert.AreEqual('pkg:github/MHumm/DelphiEncryptionCompendium@6.4.1',
    GithubPurlFromRepoUrl('https://github.com/MHumm/DelphiEncryptionCompendium', '6.4.1'));
  Assert.AreEqual('pkg:github/acme/lib@1.0',
    GithubPurlFromRepoUrl('https://github.com/acme/lib.git', '1.0'));
  Assert.AreEqual('pkg:github/acme/lib@1.0',
    GithubPurlFromRepoUrl('https://github.com/acme/lib/', '1.0'));
  Assert.AreEqual('', GithubPurlFromRepoUrl('https://github.com/acme/lib', ''),
    'no purl without a version');
  Assert.AreEqual('', GithubPurlFromRepoUrl('https://example.com/acme/lib', '1.0'),
    'only GitHub URLs are derived');
end;

procedure TLibrarySourceTests.FrameworkPackages_AreRtlVclFmx;
begin
  Assert.IsTrue(IsDelphiFrameworkPackage('rtl'));
  Assert.IsTrue(IsDelphiFrameworkPackage('VCL'));
  Assert.IsTrue(IsDelphiFrameworkPackage('fmx'));
  Assert.IsFalse(IsDelphiFrameworkPackage('vclimg'));
  Assert.IsFalse(IsDelphiFrameworkPackage('dbrtl'));
end;

procedure TLibrarySourceTests.Collect_PackageOnly_ListsContainedUnitsFormsAndPackage;
var
  LFiles: TArray<TLibrarySourceFile>;
  LRequires, LWarnings, LPaths: TArray<string>;
  LFound: Boolean;
begin
  LFiles := CollectLibrarySourceFiles(TPath.Combine(FixtureDir, 'FixtureLib.dpk'),
    nil, FixtureDir, nil, nil, LRequires, LFound, LWarnings);
  LPaths := RelativePaths(LFiles);

  Assert.AreEqual(0, Integer(Length(LWarnings)));
  Assert.IsTrue(LFound);
  Assert.AreEqual(2, Integer(Length(LRequires)));
  Assert.AreEqual(5, Integer(Length(LFiles)), string.Join(', ', LPaths));
  Assert.IsTrue(Contains(LPaths, 'FixtureLib.dpk'));
  Assert.IsTrue(Contains(LPaths, 'FixtureLib.Core.pas'));
  Assert.IsTrue(Contains(LPaths, 'FixtureLib.Form.pas'));
  Assert.IsTrue(Contains(LPaths, 'FixtureLib.Form.dfm'), 'sibling form');
  Assert.IsTrue(Contains(LPaths, 'sub/FixtureLib.Sub.pas'), 'forward slashes');
end;

procedure TLibrarySourceTests.Collect_PackageAndSourceDir_FiltersAndDeduplicates;
var
  LFiles: TArray<TLibrarySourceFile>;
  LRequires, LWarnings, LPaths: TArray<string>;
  LFound: Boolean;
  I: Integer;
begin
  LFiles := CollectLibrarySourceFiles(TPath.Combine(FixtureDir, 'FixtureLib.dpk'),
    [FixtureDir], FixtureDir, nil, nil, LRequires, LFound, LWarnings);
  LPaths := RelativePaths(LFiles);

  Assert.AreEqual(7, Integer(Length(LFiles)), string.Join(', ', LPaths));
  Assert.IsTrue(Contains(LPaths, 'FixtureLib.Shared.inc'));
  Assert.IsTrue(Contains(LPaths, 'FixtureLib.dproj'));
  Assert.IsFalse(Contains(LPaths, 'ignore.dcu'));
  Assert.IsFalse(Contains(LPaths, 'notes.txt'));
  for I := 1 to High(LPaths) do
    Assert.IsTrue(CompareText(LPaths[I - 1], LPaths[I]) < 0,
      'sorted and without duplicates: ' + string.Join(', ', LPaths));
end;

procedure TLibrarySourceTests.Generate_LibraryMode_WritesLibrarySbom;
var
  LConfig: TSbomConfig;
  LGenerator: TDxComplyGenerator;
  LTempDir, LOutput: string;
  LMessages: TList<string>;
  LJson, LMeta, LRoot, LComponent: TJSONObject;
  LComponents, LHashes, LLicences: TJSONArray;
  LFiles, LFrameworks, I: Integer;
  LMessage: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'dxc-lib-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LTempDir);
  LOutput := TPath.Combine(LTempDir, 'lib.cdx.json');
  LMessages := TList<string>.Create;
  try
    LConfig := TSbomConfig.Default;
    LConfig.LibraryMode := True;
    LConfig.SourceDirs := [FixtureDir];
    LConfig.Licence := 'MIT';
    LConfig.Supplier := 'Acme';
    LConfig.SupplierUrl := 'https://acme.example';
    LConfig.SbomCreator := 'sbom@acme.example';
    LConfig.RepoUrl := 'https://github.com/acme/fixturelib.git';
    LConfig.OutputPath := LOutput;

    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress :=
        procedure(const AMessage: string; const AProgress: Integer)
        begin
          LMessages.Add(AMessage);
        end;
      Assert.IsTrue(LGenerator.Generate(TPath.Combine(FixtureDir, 'FixtureLib.dproj'),
        LOutput), string.Join(sLineBreak, LMessages.ToArray));
    finally
      LGenerator.Free;
    end;

    for LMessage in LMessages do
      Assert.IsFalse(LMessage.Contains('The built file'),
        'library mode has no deliverable binary: ' + LMessage);

    LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(LOutput)) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      LMeta := LJson.GetValue('metadata') as TJSONObject;
      LRoot := LMeta.GetValue('component') as TJSONObject;
      Assert.AreEqual('library', LRoot.GetValue<string>('type'));
      Assert.AreEqual('FixtureLib', LRoot.GetValue<string>('name'));
      Assert.AreEqual('1.2.3.0', LRoot.GetValue<string>('version'));
      Assert.AreEqual('pkg:github/acme/fixturelib@1.2.3.0', LRoot.GetValue<string>('purl'));
      LLicences := LRoot.GetValue('licenses') as TJSONArray;
      Assert.IsNotNull(LLicences, 'root licence');

      LComponents := LJson.GetValue('components') as TJSONArray;
      LFiles := 0;
      LFrameworks := 0;
      for I := 0 to LComponents.Count - 1 do
      begin
        LComponent := LComponents.Items[I] as TJSONObject;
        if LComponent.GetValue<string>('type') = 'framework' then
        begin
          Inc(LFrameworks);
          Assert.IsNull(LComponent.GetValue('hashes'), 'a requires package has no file');
        end
        else if LComponent.GetValue<string>('type') = 'file' then
        begin
          Inc(LFiles);
          LHashes := LComponent.GetValue('hashes') as TJSONArray;
          Assert.IsNotNull(LHashes, LComponent.GetValue<string>('name'));
          Assert.AreEqual(2, Integer(LHashes.Count), 'SHA-256 and SHA-512');
          Assert.AreEqual('1.2.3.0', LComponent.GetValue<string>('version'),
            'release version on every file');
          Assert.IsNull(LComponent.GetValue('purl'), 'no file: purl');
          Assert.AreEqual(LComponent.GetValue<string>('name'), PropertyValue(LComponent,
            'net.developer-experts.dx-comply:relativePath'));
        end;
      end;
      Assert.AreEqual(7, LFiles, 'one component per shipped file');
      Assert.AreEqual(2, LFrameworks, 'rtl and vcl');
      Assert.IsNotNull(LJson.GetValue('compositions'));
    finally
      LJson.Free;
    end;
  finally
    LMessages.Free;
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TLibrarySourceTests.CliOptions_LibraryMode_ProjectOptionalWithSourceDir;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--library', '--source-dir=Source',
      '--source-dir=Extra', '--purl=pkg:github/a/b@1', '--repo-url=https://github.com/a/b']),
      LOptions.ParseError);
    Assert.IsTrue(LOptions.LibraryMode);
    Assert.AreEqual(2, Integer(Length(LOptions.SourceDirs)));
    LConfig := LOptions.ToSbomConfig;
    Assert.IsTrue(LConfig.LibraryMode);
    Assert.AreEqual('Extra', LConfig.SourceDirs[1]);
    Assert.AreEqual('pkg:github/a/b@1', LConfig.Purl);
    Assert.AreEqual('https://github.com/a/b', LConfig.RepoUrl);
    Assert.IsTrue(scoLibraryMode in LConfig.ExplicitOverrides);
    Assert.IsTrue(scoSourceDirs in LConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
end;

procedure TLibrarySourceTests.CliOptions_BuildMode_StillRequiresProject;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--source-dir=Source']), 'build mode');
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--library']), 'library mode without a source dir');
  finally
    LOptions.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLibrarySourceTests);

end.
