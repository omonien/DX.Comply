/// <summary>
/// DX.Comply.Tests.LegacyProject
/// DUnitX tests for Delphi 7 .dpr, .dof, and .cfg project scans.
/// </summary>
///
/// <remarks>
/// Fixtures live in tests/fixtures/delphi7. Tests that change files use a
/// temporary directory so the fixtures stay as checked in.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.LegacyProject;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.BuildEvidence.Reader,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.LegacyProject,
  DX.Comply.ProjectScanner;

type
  /// <summary>
  /// Covers legacy project parsing, precedence, output paths, and the
  /// missing detailed MAP error.
  /// </summary>
  [TestFixture]
  TLegacyProjectTests = class
  private
    FTempDir: string;
    FScanner: IProjectScanner;
    FMessages: TStringList;
    procedure OnProgress(const AMessage: string; const AProgress: Integer);
    function FindRepoFile(const ARelative: string): string;
    function ListHas(const AValues: TList<string>; const AExpected: string): Boolean;
    function WarningsContain(const AProjectInfo: TProjectInfo;
      const AFragment: string): Boolean;
    procedure WriteProjectFile(const ADir, AName, AContents: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    /// <summary>The checked-in .dof parses the Delphi 7 sections we rely on.</summary>
    [Test]
    procedure ParseDof_SampleFixture_ReadsDirectoriesAndVersion;

    /// <summary>The checked-in .cfg parses -E, -U, -D, -LU, and -GD.</summary>
    [Test]
    procedure ParseCfg_SampleFixture_ReadsSwitches;

    /// <summary>A .cfg value on the next token is accepted.</summary>
    [Test]
    procedure ParseCfg_SplitSwitch_ReadsFollowingToken;

    /// <summary>Compiler directives such as -$E- are not output directories.</summary>
    [Test]
    procedure ParseCfg_Directive_IsNotAnOutputDir;

    /// <summary>.dof values win, including an explicit empty output directory.</summary>
    [Test]
    procedure Merge_DofWins_IncludingEmptyOutputDir;

    /// <summary>UsePackages=0 drops both the .dof package list and -LU.</summary>
    [Test]
    procedure RuntimePackages_UsePackagesOff_IgnoresCfg;

    /// <summary>-LU is used when the .dof does not set UsePackages.</summary>
    [Test]
    procedure RuntimePackages_CfgOnly_UsesLu;

    /// <summary>Scanning the sample .dpr fills the shared project model.</summary>
    [Test]
    procedure Scan_SampleDpr_FillsProjectModel;

    /// <summary>A leading comment does not hide the real header keyword.</summary>
    [Test]
    procedure Scan_CommentBeforeKeyword_DetectsLibrary;

    /// <summary>package in the header selects a .bpl in PackageDLLOutputDir.</summary>
    [Test]
    procedure Scan_PackageHeader_UsesBplDirectoryAndLibSuffix;

    /// <summary>program selects an .exe under OutputDir.</summary>
    [Test]
    procedure Scan_ProgramHeader_UsesExeOutputDir;

    /// <summary>With no .dof, the .cfg supplies output, defines, and packages.</summary>
    [Test]
    procedure Scan_CfgOnly_UsesCfgValues;

    /// <summary>An empty .dof OutputDir beats -E in the .cfg.</summary>
    [Test]
    procedure Scan_EmptyDofOutputDir_BeatsCfg;

    /// <summary>A .bdsproj is scanned through its main source and sibling .dof.</summary>
    [Test]
    procedure Scan_Bdsproj_UsesMainSourceAndDof;

    /// <summary>Win64 and Debug are ignored when the caller set them.</summary>
    [Test]
    procedure Scan_RequestedPlatformAndConfig_AreIgnored;

    /// <summary>The built-in Release default must not warn on a Delphi 7 scan.</summary>
    [Test]
    procedure Scan_DefaultRelease_DoesNotWarn;

    /// <summary>An explicit Release configuration is reported and ignored.</summary>
    [Test]
    procedure Scan_ExplicitRelease_Warns;

    /// <summary>
    /// A blank package output directory uses the registry value only when
    /// the Delphi 7 registry root was found.
    /// </summary>
    [Test]
    procedure ResolveBlankPackageOutputDir_UsesRegistryOnlyWhenRootFound;

    /// <summary>--delphi7-root expands $(DELPHI) and does not require a registry install.</summary>
    [Test]
    procedure Scan_Delphi7Root_ExpandsLibraryPath;

    /// <summary>A missing override directory warns and the scan still returns.</summary>
    [Test]
    procedure Scan_MissingDelphi7Root_WarnsAndContinues;

    /// <summary>A .dproj scan is not marked as a legacy project.</summary>
    [Test]
    procedure Scan_Dproj_IsNotLegacy;

    /// <summary>Validate accepts an existing .dpr and rejects a missing one.</summary>
    [Test]
    procedure Validate_Dpr_RequiresExistingFile;

    /// <summary>Generation stops when the MAP file is not next to the output binary.</summary>
    [Test]
    procedure Generate_MissingMap_ReturnsDelphi7Error;

    /// <summary>An explicit configuration on the engine config is reported.</summary>
    [Test]
    procedure Generate_ExplicitRelease_Warns;

    /// <summary>configuration in .dxcomply.json is treated as explicitly set.</summary>
    [Test]
    procedure Generate_ConfigFileConfiguration_Warns;

    /// <summary>A MAP file without unit entries explains how to enable Detailed.</summary>
    [Test]
    procedure ReadEvidence_MapWithoutUnits_WarnsAboutDetailed;
  end;

implementation

uses
  DX.Comply.Tests.Paths;

{ TLegacyProjectTests }

procedure TLegacyProjectTests.Setup;
begin
  FScanner := TProjectScanner.Create;
  FMessages := TStringList.Create;
  FTempDir := TPath.Combine(TPath.GetTempPath, 'dxcomply-d7-' + TPath.GetRandomFileName);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TLegacyProjectTests.TearDown;
begin
  FScanner := nil;
  FMessages.Free;
  if (FTempDir <> '') and TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TLegacyProjectTests.OnProgress(const AMessage: string; const AProgress: Integer);
begin
  FMessages.Add(AMessage);
  FMessages.Add(IntToStr(AProgress));
end;

function TLegacyProjectTests.FindRepoFile(const ARelative: string): string;
begin
  // RepoRoot covers the build server, where the exe is under builds\(id)\bin
  // and the checkout is elsewhere.
  Result := TPath.Combine(RepoRoot, ARelative);
  if not TFile.Exists(Result) then
    Result := '';
end;

function TLegacyProjectTests.ListHas(const AValues: TList<string>;
  const AExpected: string): Boolean;
var
  LValue: string;
begin
  Result := False;
  if not Assigned(AValues) then
    Exit;
  for LValue in AValues do
    if SameText(LValue, AExpected) then
      Exit(True);
end;

function TLegacyProjectTests.WarningsContain(const AProjectInfo: TProjectInfo;
  const AFragment: string): Boolean;
var
  LWarning: string;
begin
  Result := False;
  if not Assigned(AProjectInfo.Warnings) then
    Exit;
  for LWarning in AProjectInfo.Warnings do
    if Pos(AFragment, LWarning) > 0 then
      Exit(True);
end;

procedure TLegacyProjectTests.WriteProjectFile(const ADir, AName, AContents: string);
begin
  TFile.WriteAllText(TPath.Combine(ADir, AName), AContents, TEncoding.ASCII);
end;

procedure TLegacyProjectTests.ParseDof_SampleFixture_ReadsDirectoriesAndVersion;
var
  LOptions: TLegacyOptionSet;
  LPath: string;
begin
  LPath := FindRepoFile('tests' + PathDelim + 'fixtures' + PathDelim +
    'delphi7' + PathDelim + 'SampleApp.dof');
  Assert.AreNotEqual('', LPath, 'SampleApp.dof fixture must be on disk');

  LOptions := ParseDofOptions(LPath);
  Assert.IsTrue(LOptions.HasOutputDir);
  Assert.AreEqual('.\bin', LOptions.OutputDir);
  Assert.AreEqual('.\dcu', LOptions.UnitOutputDir);
  Assert.IsTrue(LOptions.HasPackageDllOutputDir,
    'An empty PackageDLLOutputDir key is still defined');
  Assert.AreEqual('', LOptions.PackageDllOutputDir);
  Assert.AreEqual('..\shared;$(DELPHI)\Lib', LOptions.SearchPath);
  Assert.AreEqual('vcl;rtl', LOptions.Packages);
  Assert.AreEqual('DELPHI7;APP_TRIAL', LOptions.Conditionals);
  Assert.IsTrue(LOptions.HasUsePackages and LOptions.UsePackages);
  Assert.IsTrue(LOptions.HasMapFile and LOptions.HasDetailedMap);
  Assert.AreEqual(3, LOptions.MapFile);
  Assert.AreEqual('1.2.3.4', LOptions.FileVersion);
  Assert.AreEqual('Acme Tools', LOptions.CompanyName);
  Assert.AreEqual('Sample Application', LOptions.ProductName);
  Assert.AreEqual('1.2.3.4', LegacyVersionText(LOptions),
    'FileVersion wins over MajorVer/MinorVer/Release/Build');
end;

procedure TLegacyProjectTests.ParseCfg_SampleFixture_ReadsSwitches;
var
  LOptions: TLegacyOptionSet;
  LPath: string;
begin
  LPath := FindRepoFile('tests' + PathDelim + 'fixtures' + PathDelim +
    'delphi7' + PathDelim + 'SampleApp.cfg');
  Assert.AreNotEqual('', LPath, 'SampleApp.cfg fixture must be on disk');

  LOptions := ParseCfgOptions(LPath);
  Assert.IsTrue(LOptions.HasOutputDir);
  Assert.AreEqual('.\cfgout', LOptions.OutputDir);
  Assert.AreEqual('.\cfgdcu', LOptions.UnitOutputDir);
  Assert.AreEqual('..\fromcfg', LOptions.SearchPath);
  Assert.AreEqual('CFGONLY;DELPHI7', LOptions.Conditionals);
  Assert.AreEqual('vclx;ibxpress', LOptions.Packages);
  Assert.IsTrue(LOptions.HasDetailedMap, '-GD must mark a detailed map');
  Assert.IsFalse(LOptions.HasUsePackages, 'A .cfg has no UsePackages key');
end;

procedure TLegacyProjectTests.ParseCfg_SplitSwitch_ReadsFollowingToken;
var
  LOptions: TLegacyOptionSet;
  LPath: string;
begin
  LPath := TPath.Combine(FTempDir, 'Split.cfg');
  TFile.WriteAllText(LPath,
    '-E' + sLineBreak + '".\splitout"' + sLineBreak +
    '-U' + sLineBreak + '".\splitunits"' + sLineBreak +
    '-D' + sLineBreak + 'SPLIT' + sLineBreak, TEncoding.ASCII);

  LOptions := ParseCfgOptions(LPath);
  Assert.AreEqual('.\splitout', LOptions.OutputDir);
  Assert.AreEqual('.\splitunits', LOptions.SearchPath);
  Assert.AreEqual('SPLIT', LOptions.Conditionals);
end;

procedure TLegacyProjectTests.ParseCfg_Directive_IsNotAnOutputDir;
var
  LOptions: TLegacyOptionSet;
  LPath: string;
begin
  LPath := TPath.Combine(FTempDir, 'Directive.cfg');
  TFile.WriteAllText(LPath, '-$E-' + sLineBreak + '-$M16384,1048576' + sLineBreak,
    TEncoding.ASCII);
  LOptions := ParseCfgOptions(LPath);
  Assert.IsFalse(LOptions.HasOutputDir, '-$E- must not set the exe output directory');
end;

procedure TLegacyProjectTests.Merge_DofWins_IncludingEmptyOutputDir;
var
  LCfg: TLegacyOptionSet;
  LDof: TLegacyOptionSet;
  LMerged: TLegacyOptionSet;
begin
  LDof := Default(TLegacyOptionSet);
  LDof.HasOutputDir := True;
  LDof.OutputDir := '';
  LDof.HasConditionals := True;
  LDof.Conditionals := 'FROMDOF';
  LDof.HasMapFile := True;
  LDof.MapFile := 0;

  LCfg := Default(TLegacyOptionSet);
  LCfg.HasOutputDir := True;
  LCfg.OutputDir := '.\cfgout';
  LCfg.HasConditionals := True;
  LCfg.Conditionals := 'FROMCFG';
  LCfg.HasDetailedMap := True;
  LCfg.HasSearchPath := True;
  LCfg.SearchPath := '.\fromcfg';

  LMerged := MergeLegacyOptions(LDof, LCfg);
  Assert.IsTrue(LMerged.HasOutputDir);
  Assert.AreEqual('', LMerged.OutputDir, 'An empty .dof OutputDir must beat -E');
  Assert.AreEqual('FROMDOF', LMerged.Conditionals);
  Assert.AreEqual('.\fromcfg', LMerged.SearchPath,
    'A value only the .cfg defines is kept');
  Assert.IsFalse(LMerged.HasDetailedMap,
    'MapFile=0 in the .dof must beat -GD in the .cfg');
end;

procedure TLegacyProjectTests.RuntimePackages_UsePackagesOff_IgnoresCfg;
var
  LCfg: TLegacyOptionSet;
  LDof: TLegacyOptionSet;
  LPackages: string;
begin
  LDof := Default(TLegacyOptionSet);
  LDof.HasUsePackages := True;
  LDof.UsePackages := False;
  LDof.HasPackages := True;
  LDof.Packages := 'vcl';
  LCfg := Default(TLegacyOptionSet);
  LCfg.HasPackages := True;
  LCfg.Packages := 'rtl';

  Assert.IsFalse(ResolveRuntimePackages(LDof, LCfg, LPackages));
  Assert.AreEqual('', LPackages);
end;

procedure TLegacyProjectTests.RuntimePackages_CfgOnly_UsesLu;
var
  LCfg: TLegacyOptionSet;
  LDof: TLegacyOptionSet;
  LPackages: string;
begin
  LDof := Default(TLegacyOptionSet);
  LCfg := Default(TLegacyOptionSet);
  LCfg.HasPackages := True;
  LCfg.Packages := 'rtl;vcl';
  Assert.IsTrue(ResolveRuntimePackages(LDof, LCfg, LPackages));
  Assert.AreEqual('rtl;vcl', LPackages);
end;

procedure TLegacyProjectTests.Scan_SampleDpr_FillsProjectModel;
var
  LDpr: string;
  LProject: TProjectInfo;
  LShared: string;
begin
  LDpr := FindRepoFile('tests' + PathDelim + 'fixtures' + PathDelim +
    'delphi7' + PathDelim + 'SampleApp.dpr');
  Assert.AreNotEqual('', LDpr, 'SampleApp.dpr fixture must be on disk');

  LProject := FScanner.Scan(LDpr, 'Win32', 'Release');
  try
    Assert.IsTrue(LProject.IsLegacyProject);
    Assert.AreEqual('SampleApp', LProject.ProjectName);
    Assert.AreEqual('Win32', LProject.Platform);
    Assert.AreEqual('Default', LProject.Configuration);
    Assert.AreEqual('1.2.3.4', LProject.Version);
    Assert.AreEqual('Acme Tools', LProject.CompanyName);
    Assert.AreEqual('DELPHI7;APP_TRIAL', LProject.ConditionalDefines);
    Assert.IsTrue(ListHas(LProject.RuntimePackages, 'vcl'));
    Assert.IsTrue(ListHas(LProject.RuntimePackages, 'rtl'));
    Assert.IsFalse(ListHas(LProject.RuntimePackages, 'vclx'),
      'Packages from the .cfg must not replace the .dof list');
    Assert.IsTrue(SameText(LProject.OutputFilePath,
      TPath.Combine(TPath.Combine(LProject.ProjectDir, 'bin'), 'SampleApp.exe')),
      'The program output must be OutputDir\SampleApp.exe');
    Assert.IsTrue(SameText(LProject.MapFilePath,
      TPath.ChangeExtension(LProject.OutputFilePath, '.map')),
      'The MAP file must sit next to the output binary');
    Assert.IsTrue(SameText(LProject.DcuOutputDir,
      TPath.Combine(LProject.ProjectDir, 'dcu')));
    LShared := TPath.GetFullPath(TPath.Combine(LProject.ProjectDir, '..\shared'));
    Assert.IsTrue(ListHas(LProject.ProjectSearchPaths, LShared),
      'The .dof search path must be kept');
    Assert.IsFalse(ListHas(LProject.ProjectSearchPaths,
      TPath.GetFullPath(TPath.Combine(LProject.ProjectDir, '..\fromcfg'))),
      'The .cfg search path must not be added when the .dof defines one');
    Assert.IsFalse(WarningsContain(LProject, 'Ignoring requested configuration'),
      'The built-in Release default must not warn');
    Assert.AreEqual(NativeInt(1), NativeInt(LProject.ExplicitUnitReferences.Count));
    Assert.AreEqual('Unit1', LProject.ExplicitUnitReferences[0].UnitName);
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_CommentBeforeKeyword_DetectsLibrary;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'Commented.dpr',
    '{ program NotThis }' + sLineBreak + 'library Commented;' + sLineBreak);
  WriteProjectFile(FTempDir, 'Commented.dof',
    '[Directories]' + sLineBreak + 'OutputDir=.\out' + sLineBreak);

  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'Commented.dpr'), '', '');
  try
    Assert.IsTrue(SameText(LProject.OutputFilePath,
      TPath.Combine(TPath.Combine(FTempDir, 'out'), 'Commented.dll')),
      'The library keyword must select a dll');
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_PackageHeader_UsesBplDirectoryAndLibSuffix;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'SamplePkg.dpk',
    'package SamplePkg;' + sLineBreak +
    '{$LIBSUFFIX ''70''}' + sLineBreak +
    'end.' + sLineBreak);
  WriteProjectFile(FTempDir, 'SamplePkg.dof',
    '[Directories]' + sLineBreak +
    'OutputDir=.\bin' + sLineBreak +
    'PackageDLLOutputDir=.\bpl' + sLineBreak +
    'PackageDCPOutputDir=.\dcp' + sLineBreak +
    'UsePackages=0' + sLineBreak);

  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'SamplePkg.dpk'), 'Win32', 'Release');
  try
    Assert.IsTrue(SameText(LProject.OutputFilePath,
      TPath.Combine(TPath.Combine(FTempDir, 'bpl'), 'SamplePkg70.bpl')),
      'A package must be named in PackageDLLOutputDir with LIBSUFFIX');
    Assert.AreEqual('70', LProject.DllSuffix);
    Assert.IsTrue(SameText(LProject.ArtefactOutputDir,
      TPath.Combine(FTempDir, 'bpl')));
    Assert.IsTrue(SameText(LProject.DcpOutputDir, TPath.Combine(FTempDir, 'dcp')));
    Assert.AreEqual(NativeInt(0), NativeInt(LProject.RuntimePackages.Count));
    Assert.IsTrue(SameText(LProject.MapFilePath,
      TPath.Combine(TPath.Combine(FTempDir, 'bpl'), 'SamplePkg70.map')));
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_ProgramHeader_UsesExeOutputDir;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'Prog.dpr', 'program Prog;' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak);
  WriteProjectFile(FTempDir, 'Prog.dof', '[Directories]' + sLineBreak + 'OutputDir=.\bin' + sLineBreak);

  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'Prog.dpr'), 'Win32', 'Default');
  try
    Assert.IsTrue(SameText(LProject.OutputFilePath,
      TPath.Combine(TPath.Combine(FTempDir, 'bin'), 'Prog.exe')));
    Assert.IsFalse(WarningsContain(LProject, 'Ignoring requested configuration'),
      'Default is the legacy configuration name and needs no ignore note');
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_CfgOnly_UsesCfgValues;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'CfgOnly.dpr', 'program CfgOnly;' + sLineBreak);
  WriteProjectFile(FTempDir, 'CfgOnly.cfg',
    '-E".\cfgbin"' + sLineBreak +
    '-DONLYCFG' + sLineBreak +
    '-LUrtl' + sLineBreak);

  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'CfgOnly.dpr'), 'Win32', 'Release');
  try
    Assert.IsTrue(SameText(LProject.OutputFilePath,
      TPath.Combine(TPath.Combine(FTempDir, 'cfgbin'), 'CfgOnly.exe')));
    Assert.AreEqual('ONLYCFG', LProject.ConditionalDefines);
    Assert.IsTrue(ListHas(LProject.RuntimePackages, 'rtl'));
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_EmptyDofOutputDir_BeatsCfg;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'EmptyOut.dpr', 'program EmptyOut;' + sLineBreak);
  WriteProjectFile(FTempDir, 'EmptyOut.dof',
    '[Directories]' + sLineBreak + 'OutputDir=' + sLineBreak);
  WriteProjectFile(FTempDir, 'EmptyOut.cfg', '-E".\cfgout"' + sLineBreak);

  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'EmptyOut.dpr'), 'Win32', 'Release');
  try
    Assert.IsTrue(SameText(LProject.OutputFilePath,
      TPath.Combine(FTempDir, 'EmptyOut.exe')),
      'An empty .dof OutputDir means the project directory, not the .cfg -E path');
    Assert.IsFalse(WarningsContain(LProject, 'No output directory'),
      'An explicit empty OutputDir is a defined value');
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_Bdsproj_UsesMainSourceAndDof;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'Widget.dpr', 'library Widget;' + sLineBreak);
  WriteProjectFile(FTempDir, 'Widget.dof',
    '[Directories]' + sLineBreak + 'OutputDir=.\out' + sLineBreak +
    '[Version Info Keys]' + sLineBreak + 'CompanyName=Widget Co' + sLineBreak +
    'FileVersion=2.0.0.1' + sLineBreak);
  WriteProjectFile(FTempDir, 'Widget.bdsproj',
    '<BorlandProject><Delphi.Personality><Source>' +
    '<Source Name="MainSource">Widget.dpr</Source>' +
    '</Source></Delphi.Personality></BorlandProject>');

  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'Widget.bdsproj'), 'Win32', 'Release');
  try
    Assert.IsTrue(LProject.IsLegacyProject);
    Assert.AreEqual('Widget', LProject.ProjectName);
    Assert.IsTrue(SameText(LProject.MainSourcePath, TPath.Combine(FTempDir, 'Widget.dpr')));
    Assert.IsTrue(SameText(LProject.OutputFilePath,
      TPath.Combine(TPath.Combine(FTempDir, 'out'), 'Widget.dll')));
    Assert.AreEqual('Widget Co', LProject.CompanyName);
    Assert.AreEqual('2.0.0.1', LProject.Version);
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_RequestedPlatformAndConfig_AreIgnored;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'OneSet.dpr', 'program OneSet;' + sLineBreak);
  FScanner.SetExplicitTargetRequest(True, True);
  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'OneSet.dpr'), 'Win64', 'Debug');
  try
    Assert.AreEqual('Win32', LProject.Platform);
    Assert.AreEqual('Default', LProject.Configuration);
    Assert.IsTrue(WarningsContain(LProject, 'Ignoring requested platform "Win64"'));
    Assert.IsTrue(WarningsContain(LProject, 'Ignoring requested configuration "Debug"'));
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_Delphi7Root_ExpandsLibraryPath;
var
  LLib: string;
  LProject: TProjectInfo;
  LRoot: string;
begin
  LRoot := TPath.Combine(FTempDir, 'Delphi7');
  LLib := TPath.Combine(LRoot, 'Lib');
  TDirectory.CreateDirectory(LLib);
  WriteProjectFile(FTempDir, 'Roots.dpr', 'program Roots;' + sLineBreak);
  WriteProjectFile(FTempDir, 'Roots.dof',
    '[Directories]' + sLineBreak + 'SearchPath=$(DELPHI)\Lib' + sLineBreak);
  FScanner.SetDelphi7Root(LRoot);

  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'Roots.dpr'), 'Win32', 'Release');
  try
    Assert.AreEqual(LRoot, LProject.Toolchain.RootDir);
    Assert.AreEqual('Borland Delphi', LProject.Toolchain.ProductName);
    Assert.AreEqual('7.0', LProject.Toolchain.Version);
    Assert.IsTrue(ListHas(LProject.ProjectSearchPaths, LLib),
      '$(DELPHI)\Lib must expand to the override root');
    Assert.IsTrue(ListHas(LProject.GlobalSearchPaths, LLib));
    Assert.IsFalse(WarningsContain(LProject, 'not installed'),
      'An explicit root must satisfy the Delphi 7 lookup');
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_MissingDelphi7Root_WarnsAndContinues;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'NoRoot.dpr', 'program NoRoot;' + sLineBreak);
  FScanner.SetDelphi7Root(TPath.Combine(FTempDir, 'missing-delphi'));
  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'NoRoot.dpr'), 'Win32', 'Release');
  try
    Assert.AreEqual('NoRoot', LProject.ProjectName);
    Assert.IsTrue(WarningsContain(LProject, 'was not found'),
      'A missing override must be reported');
    Assert.IsTrue(SameText(LProject.OutputFilePath, TPath.Combine(FTempDir, 'NoRoot.exe')));
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_Dproj_IsNotLegacy;
var
  LDproj: string;
  LProject: TProjectInfo;
begin
  LDproj := FindRepoFile('src' + PathDelim + 'DX.Comply.Engine.dproj');
  Assert.AreNotEqual('', LDproj, 'Engine .dproj must be reachable from the test binary');
  LProject := FScanner.Scan(LDproj, 'Win32', 'Debug');
  try
    Assert.IsFalse(LProject.IsLegacyProject);
    Assert.AreEqual('', LProject.CompanyName);
    Assert.AreEqual('', LProject.ConditionalDefines);
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Validate_Dpr_RequiresExistingFile;
var
  LDpr: string;
begin
  LDpr := FindRepoFile('tests' + PathDelim + 'fixtures' + PathDelim +
    'delphi7' + PathDelim + 'SampleApp.dpr');
  Assert.IsTrue(FScanner.Validate(LDpr), 'An existing .dpr must be accepted');
  Assert.IsFalse(FScanner.Validate(TPath.Combine(FTempDir, 'Missing.dpr')),
    'A missing .dpr must be rejected');
  WriteProjectFile(FTempDir, 'Empty.bdsproj', '<BorlandProject/>');
  Assert.IsTrue(FScanner.Validate(TPath.Combine(FTempDir, 'Empty.bdsproj')),
    'An existing .bdsproj must be accepted');
end;

procedure TLegacyProjectTests.Generate_MissingMap_ReturnsDelphi7Error;
var
  LGenerator: TDxComplyGenerator;
  LSuccess: Boolean;
  LText: string;
begin
  WriteProjectFile(FTempDir, 'NeedsMap.dpr', 'program NeedsMap;' + sLineBreak);
  WriteProjectFile(FTempDir, 'NeedsMap.dof',
    '[Directories]' + sLineBreak + 'OutputDir=.\bin' + sLineBreak);

  LGenerator := TDxComplyGenerator.Create;
  try
    LGenerator.OnProgress := OnProgress;
    LSuccess := LGenerator.Generate(TPath.Combine(FTempDir, 'NeedsMap.dpr'));
  finally
    LGenerator.Free;
  end;

  Assert.IsFalse(LSuccess, 'A legacy project without a MAP file must fail');
  LText := FMessages.Text;
  Assert.IsTrue(Pos('No detailed MAP file found next to the output binary', LText) > 0,
    LText);
  Assert.IsTrue(Pos('Map file to Detailed', LText) > 0, LText);
  Assert.IsTrue(Pos('-GD', LText) > 0, LText);
  Assert.IsTrue(Pos('-1', LText) > 0, 'The failure must be reported as an error');
  Assert.IsFalse(Pos('Ignoring requested configuration', LText) > 0,
    'The built-in Release default must not warn: ' + LText);
  Assert.IsFalse(TFile.Exists(TPath.Combine(FTempDir, 'bom.json')),
    'SBOM generation must stop before writing output');
end;

procedure TLegacyProjectTests.Scan_DefaultRelease_DoesNotWarn;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'Quiet.dpr', 'program Quiet;' + sLineBreak);
  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'Quiet.dpr'), 'Win32', 'Release');
  try
    Assert.AreEqual('Win32', LProject.Platform);
    Assert.AreEqual('Default', LProject.Configuration);
    Assert.IsFalse(WarningsContain(LProject, 'Ignoring requested configuration'),
      'Release passed as the built-in default must not warn');
    Assert.IsFalse(WarningsContain(LProject, 'Ignoring requested platform'),
      'Win32 passed as the built-in default must not warn');
    Assert.IsFalse(WarningsContain(LProject, 'Legacy Delphi project'),
      'A default scan must not warn about the single option set');
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.Scan_ExplicitRelease_Warns;
var
  LProject: TProjectInfo;
begin
  WriteProjectFile(FTempDir, 'Chosen.dpr', 'program Chosen;' + sLineBreak);
  FScanner.SetExplicitTargetRequest(False, True);
  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'Chosen.dpr'), 'Win32', 'Release');
  try
    Assert.AreEqual('Default', LProject.Configuration);
    Assert.IsTrue(WarningsContain(LProject, 'Ignoring requested configuration "Release"'),
      'An explicit Release configuration must be reported');
    Assert.IsFalse(WarningsContain(LProject, 'Ignoring requested platform'),
      'Win32 must not be reported when the platform was not set');
  finally
    LProject.Free;
  end;
end;

procedure TLegacyProjectTests.ResolveBlankPackageOutputDir_UsesRegistryOnlyWhenRootFound;
begin
  Assert.AreEqual('C:\Bpl',
    ResolveBlankPackageOutputDir('C:\Proj', 'C:\Bpl', True),
    'A found registry root must use Package DPL Output');
  Assert.AreEqual('C:\Proj',
    ResolveBlankPackageOutputDir('C:\Proj', 'C:\Bpl', False),
    'Without a registry root the project directory is the fallback');
  Assert.AreEqual('C:\Proj',
    ResolveBlankPackageOutputDir('C:\Proj', '  ', True),
    'An empty Package DPL Output value falls back to the project directory');
end;

procedure TLegacyProjectTests.Generate_ExplicitRelease_Warns;
var
  LConfig: TSbomConfig;
  LGenerator: TDxComplyGenerator;
  LText: string;
begin
  WriteProjectFile(FTempDir, 'Explicit.dpr', 'program Explicit;' + sLineBreak);
  LGenerator := TDxComplyGenerator.Create;
  try
    LConfig := LGenerator.Config;
    LConfig.Configuration := 'Release';
    LConfig.ConfigurationExplicit := True;
    LGenerator.Config := LConfig;
    LGenerator.OnProgress := OnProgress;
    Assert.IsFalse(LGenerator.Generate(TPath.Combine(FTempDir, 'Explicit.dpr')));
  finally
    LGenerator.Free;
  end;

  LText := FMessages.Text;
  Assert.IsTrue(Pos('Ignoring requested configuration "Release"', LText) > 0, LText);
end;

procedure TLegacyProjectTests.Generate_ConfigFileConfiguration_Warns;
var
  LGenerator: TDxComplyGenerator;
  LJsonPath: string;
  LText: string;
begin
  WriteProjectFile(FTempDir, 'FromJson.dpr', 'program FromJson;' + sLineBreak);
  WriteProjectFile(FTempDir, '.dxcomply.json', '{"configuration":"Debug"}' + sLineBreak);
  LJsonPath := TPath.Combine(FTempDir, '.dxcomply.json');

  LGenerator := TDxComplyGenerator.Create;
  try
    LGenerator.OnProgress := OnProgress;
    Assert.IsFalse(LGenerator.GenerateFromConfig(
      TPath.Combine(FTempDir, 'FromJson.dpr'), LJsonPath));
  finally
    LGenerator.Free;
  end;

  LText := FMessages.Text;
  Assert.IsTrue(Pos('Ignoring requested configuration "Debug"', LText) > 0, LText);
end;

procedure TLegacyProjectTests.ReadEvidence_MapWithoutUnits_WarnsAboutDetailed;
var
  LEvidence: TBuildEvidence;
  LProject: TProjectInfo;
  LReader: IBuildEvidenceReader;
  LWarning: string;
  LFound: Boolean;
begin
  WriteProjectFile(FTempDir, 'Shallow.dpr', 'program Shallow;' + sLineBreak);
  LProject := FScanner.Scan(TPath.Combine(FTempDir, 'Shallow.dpr'), 'Win32', 'Release');
  try
    TFile.WriteAllText(LProject.MapFilePath,
      ' Start         Length     Name                   Class' + sLineBreak +
      ' 0001:00000000 00001000H  CODE                   CODE' + sLineBreak,
      TEncoding.ASCII);

    LReader := TBuildEvidenceReader.Create;
    LEvidence := LReader.Read(LProject);
    try
      LFound := False;
      for LWarning in LEvidence.Warnings do
        if (Pos('no unit information', LWarning) > 0) and (Pos('-GD', LWarning) > 0) then
          LFound := True;
      Assert.IsTrue(LFound, 'A MAP file without units must explain the Delphi 7 setting');
    finally
      LEvidence.Free;
    end;
  finally
    LProject.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLegacyProjectTests);

end.
