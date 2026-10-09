/// <summary>
/// DX.Comply.Tests.ProjectScanner
/// DUnitX tests for TProjectScanner.
/// </summary>
///
/// <remarks>
/// Uses DX.Comply.Engine.dproj as a real-file fixture to verify
/// project-metadata extraction (name, platform, output directory,
/// runtime packages) and path validation logic.
/// The engine .dproj is located through RepoRoot in DX.Comply.Tests.Paths,
/// so the executable does not have to sit in build\$(Platform)\$(Config).
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.ProjectScanner;

interface

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  DX.Comply.ProjectScanner,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// DUnitX test fixture for TProjectScanner.
  /// </summary>
  [TestFixture]
  TProjectScannerTests = class
  private
    FScanner: IProjectScanner;
    /// <summary>
    /// Absolute path to DX.Comply.Engine.dproj, resolved by RepoRoot.
    /// </summary>
    FEngineDprojPath: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // ---- Validate -----------------------------------------------------------

    /// <summary>Validate must return True for the existing engine .dproj.</summary>
    [Test]
    procedure Validate_ValidDprojPath_ReturnsTrue;

    /// <summary>Validate must return False for a .txt extension.</summary>
    [Test]
    procedure Validate_NonDprojExtension_ReturnsFalse;

    /// <summary>Validate must return False for a path that does not exist.</summary>
    [Test]
    procedure Validate_NonExistentFile_ReturnsFalse;

    /// <summary>Validate must return False for an empty path.</summary>
    [Test]
    procedure Validate_EmptyPath_ReturnsFalse;

    // ---- Scan — basic metadata extraction -----------------------------------

    /// <summary>ProjectName must be 'DX.Comply.Engine' (filename without extension).</summary>
    [Test]
    procedure Scan_EngineDproj_ExtractsProjectName;

    /// <summary>Default platform must be 'Win32' when explicitly requested.</summary>
    [Test]
    procedure Scan_EngineDproj_ExtractsPlatform;

    /// <summary>OutputDir must contain the platform token 'Win32'.</summary>
    [Test]
    procedure Scan_EngineDproj_ExtractsOutputDir;

    /// <summary>OutputDir must be an absolute path.</summary>
    [Test]
    procedure Scan_EngineDproj_OutputDirIsAbsolute;

    /// <summary>RuntimePackages list must be assigned (not nil).</summary>
    [Test]
    procedure Scan_EngineDproj_RuntimePackagesNotNil;

    /// <summary>SearchPaths list must be assigned and include the src folder.</summary>
    [Test]
    procedure Scan_EngineDproj_ExtractsSearchPaths;

    /// <summary>UnitScopeNames must include the standard System namespace.</summary>
    [Test]
    procedure Scan_EngineDproj_ExtractsUnitScopeNames;

    /// <summary>Additional output directories must be resolved as absolute paths.</summary>
    [Test]
    procedure Scan_EngineDproj_ExtractsAdditionalOutputDirs;

    /// <summary>Warnings list must be assigned even when no warnings are emitted.</summary>
    [Test]
    procedure Scan_EngineDproj_WarningsListAssigned;

    /// <summary>MapFilePath must be inferred from the output directory and project name.</summary>
    [Test]
    procedure Scan_EngineDproj_InfersMapFilePath;

    /// <summary>ProjectDir must be the src directory containing the dproj.</summary>
    [Test]
    procedure Scan_EngineDproj_ProjectDirIsValid;

    /// <summary>
    /// A project path without a directory part (only a filename, relative to the
    /// current working directory) must still yield a non-empty, absolute
    /// ProjectDir. An empty ProjectDir cascades into an empty OutputDir which
    /// crashes the file scanner. Regression test for issue #47.
    /// </summary>
    [Test]
    procedure Scan_RelativeProjectPath_ProjectDirIsAbsolute;

    /// <summary>MainSourcePath must resolve to the package source file.</summary>
    [Test]
    procedure Scan_EngineDproj_ExtractsMainSourcePath;

    /// <summary>ExplicitUnitReferences must include engine package units.</summary>
    [Test]
    procedure Scan_EngineDproj_ExtractsExplicitUnitReferences;

    /// <summary>Toolchain metadata and global search paths must be detected.</summary>
    [Test]
    procedure Scan_EngineDproj_DetectsToolchainMetadata;

    /// <summary>Debug builds should prefer Delphi debug DCUs when no explicit override exists.</summary>
    [Test]
    procedure Scan_EngineDproj_DebugConfig_UsesDebugDCUs;

    /// <summary>Release builds should prefer Delphi release DCUs when no explicit override exists.</summary>
    [Test]
    procedure Scan_EngineDproj_ReleaseConfig_DisablesDebugDCUs;

    /// <summary>When scanning with Win64, OutputDir must contain 'Win64'.</summary>
    [Test]
    procedure Scan_Win64Platform_OutputDirContainsWin64;

    // ---- Legacy Delphi 2007 format ------------------------------------------

    /// <summary>Must extract properties from $(Configuration)|$(Platform) conditions.</summary>
    [Test]
    procedure Scan_LegacyConfigPlatformCondition_ExtractsOutputDir;

    /// <summary>Must extract properties from AnyCPU fallback conditions.</summary>
    [Test]
    procedure Scan_LegacyAnyCPUCondition_ExtractsOutputDir;

    // ---- Named <Platform> entries (regression #16) --------------------------

    /// <summary>
    /// A dproj that declares iOSDevice64 only via named Platform entries
    /// (not in the numeric bitmask) must not emit a TargetedPlatforms warning
    /// when scanned with platform 'iOSDevice64'.
    /// </summary>
    [Test]
    procedure Scan_NamedPlatformEntry_iOSDevice64_NoTargetedPlatformsWarning;

    /// <summary>
    /// $(VarName) tokens in DPROJ paths must be expanded from the
    /// process environment (issue #27).
    /// </summary>
    [Test]
    procedure Scan_DprojWithEnvVarInOutputDir_ExpandsEnvVar;

    /// <summary>
    /// The engine package output is the BPL name plus DllSuffix, in the
    /// active config/platform output directory.
    /// </summary>
    [Test]
    procedure Scan_EngineDproj_ResolvesPackageOutputFile;

    /// <summary>A library output name includes DllSuffix before .dll.</summary>
    [Test]
    procedure Scan_LibraryDproj_AppendsDllSuffix;

    /// <summary>An application output name does not include DllSuffix.</summary>
    [Test]
    procedure Scan_ApplicationDproj_IgnoresDllSuffix;

    /// <summary>
    /// A package whose BPL folder differs from DCC_ExeOutput is named in the
    /// BPL folder.
    /// </summary>
    [Test]
    procedure Scan_PackageDproj_UsesBplOutputDir;

    /// <summary>
    /// When AppType is absent, a source file that starts with library is a dll.
    /// </summary>
    [Test]
    procedure Scan_LibrarySource_DetectedWithoutAppType;

    /// <summary>
    /// An unresolved $(Auto) suffix must not invent an output file name.
    /// </summary>
    [Test]
    procedure Scan_UnresolvedDllSuffix_LeavesOutputFileEmpty;

    /// <summary>
    /// When only the command-line directory exists (ProductVersion empty),
    /// that directory is the output path and it contains no $(...).
    /// </summary>
    [Test]
    procedure Scan_ProductVersion_UsesEmptyDirWhenThatIsTheOnlyOne;

    /// <summary>
    /// When the directory with the BDS version exists, that directory wins.
    /// </summary>
    [Test]
    procedure Scan_ProductVersion_UsesExpandedDirWhenItExists;

    /// <summary>
    /// DCC_UsePackage without UsePackages is the IDE default list and is not linked.
    /// </summary>
    [Test]
    procedure Scan_UsePackagesMissing_ReturnsNoRuntimePackages;

    /// <summary>UsePackages true in Base returns the declared packages.</summary>
    [Test]
    procedure Scan_UsePackagesTrueInBase_ReturnsPackages;

    /// <summary>
    /// UsePackages true only in another configuration does not apply here.
    /// </summary>
    [Test]
    procedure Scan_UsePackagesTrueInOtherConfig_ReturnsNone;

    /// <summary>
    /// A readable PE keeps only packages whose BPL name is imported.
    /// </summary>
    [Test]
    procedure Scan_UsePackages_PeImports_KeepsOnlyImportedPackages;

    /// <summary>
    /// A file that is not a valid PE keeps the UsePackages list.
    /// </summary>
    [Test]
    procedure Scan_UsePackages_UnreadablePe_KeepsDeclaredPackages;

    /// <summary>A minimal PE32 import directory yields the DLL name.</summary>
    [Test]
    procedure TryReadPeImportNames_SyntheticPe32_ReadsDllName;

    /// <summary>A minimal PE32+ import directory yields the DLL name.</summary>
    [Test]
    procedure TryReadPeImportNames_SyntheticPe32Plus_ReadsDllName;

    /// <summary>A truncated MZ file is a failure, not an empty import list.</summary>
    [Test]
    procedure TryReadPeImportNames_Malformed_ReturnsFalse;

    /// <summary>The running test executable imports no BPL.</summary>
    [Test]
    procedure TryReadPeImportNames_TestExecutable_HasNoBplImports;
  end;

implementation

uses
  System.Generics.Collections,
  DX.Comply.Tests.Paths;

{ TProjectScannerTests }

procedure TProjectScannerTests.Setup;
begin
  FScanner := TProjectScanner.Create;

  // Engine dproj is at <repo>\src\DX.Comply.Engine.dproj. RepoRoot finds the
  // checkout when the executable is outside build\(platform)\(config)\.
  FEngineDprojPath := TPath.Combine(RepoRoot,
    'src' + PathDelim + 'DX.Comply.Engine.dproj');
end;

procedure TProjectScannerTests.TearDown;
begin
  FScanner := nil;
end;

// ---- Validate ---------------------------------------------------------------

procedure TProjectScannerTests.Validate_ValidDprojPath_ReturnsTrue;
begin
  Assert.IsTrue(FScanner.Validate(FEngineDprojPath),
    'Validate must return True for the existing engine .dproj file');
end;

procedure TProjectScannerTests.Validate_NonDprojExtension_ReturnsFalse;
begin
  Assert.IsFalse(FScanner.Validate('C:\Temp\readme.txt'),
    'Validate must return False for a .txt extension');
end;

procedure TProjectScannerTests.Validate_NonExistentFile_ReturnsFalse;
begin
  Assert.IsFalse(FScanner.Validate('C:\DoesNotExist\Missing.dproj'),
    'Validate must return False for a path that does not exist');
end;

procedure TProjectScannerTests.Validate_EmptyPath_ReturnsFalse;
begin
  Assert.IsFalse(FScanner.Validate(''),
    'Validate must return False for an empty path');
end;

// ---- Scan -------------------------------------------------------------------

procedure TProjectScannerTests.Scan_EngineDproj_ExtractsProjectName;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.AreEqual('DX.Comply.Engine', LProjectInfo.ProjectName,
      'ProjectName must equal the dproj filename without extension');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ExtractsPlatform;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.AreEqual('Win32', LProjectInfo.Platform,
      'Platform must be Win32 when Win32 is requested');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ExtractsOutputDir;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsTrue(Pos('Win32', LProjectInfo.OutputDir) > 0,
      'OutputDir must contain the platform token Win32');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_OutputDirIsAbsolute;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsFalse(TPath.IsRelativePath(LProjectInfo.OutputDir),
      'OutputDir must be an absolute path after scanning');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_RuntimePackagesNotNil;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsNotNull(LProjectInfo.RuntimePackages,
      'RuntimePackages must be assigned (not nil) after scanning');
    Assert.AreEqual(NativeInt(0), NativeInt(LProjectInfo.RuntimePackages.Count),
      'The engine .dproj lists DCC_UsePackage but does not set UsePackages');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ExtractsSearchPaths;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsNotNull(LProjectInfo.SearchPaths,
      'SearchPaths must be assigned after scanning');
    Assert.IsTrue(LProjectInfo.SearchPaths.Contains(LProjectInfo.ProjectDir),
      'SearchPaths must include the project src directory resolved from the dproj');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ExtractsUnitScopeNames;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsNotNull(LProjectInfo.UnitScopeNames,
      'UnitScopeNames must be assigned after scanning');
    Assert.IsTrue(LProjectInfo.UnitScopeNames.Contains('System'),
      'UnitScopeNames must include the System namespace from DCC_Namespace');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ExtractsAdditionalOutputDirs;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsFalse(TPath.IsRelativePath(LProjectInfo.BplOutputDir),
      'BplOutputDir must be an absolute path after scanning');
    Assert.IsFalse(TPath.IsRelativePath(LProjectInfo.DcpOutputDir),
      'DcpOutputDir must be an absolute path after scanning');
    Assert.IsFalse(TPath.IsRelativePath(LProjectInfo.DcuOutputDir),
      'DcuOutputDir must be an absolute path after scanning');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_WarningsListAssigned;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsNotNull(LProjectInfo.Warnings,
      'Warnings must be assigned after scanning');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_InfersMapFilePath;
var
  LExpectedMapPath: string;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    LExpectedMapPath := TPath.Combine(LProjectInfo.OutputDir,
      LProjectInfo.ProjectName + LProjectInfo.DllSuffix + '.map');

    Assert.AreEqual(LExpectedMapPath, LProjectInfo.MapFilePath,
      'MapFilePath must be inferred from OutputDir, ProjectName and DllSuffix');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ProjectDirIsValid;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsTrue(TDirectory.Exists(LProjectInfo.ProjectDir),
      'ProjectDir must be an existing directory');
    Assert.IsTrue(
      SameText(TPath.GetFileName(LProjectInfo.ProjectDir), 'src'),
      'ProjectDir must be the src folder');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_RelativeProjectPath_ProjectDirIsAbsolute;
var
  LProjectInfo: TProjectInfo;
  LSavedCwd: string;
begin
  // Reproduce a CI scenario: the project is passed as a bare filename, relative
  // to the current working directory (src\). TPath.GetDirectoryName on such a
  // path returns '' — the scanner must resolve it to an absolute directory.
  LSavedCwd := TDirectory.GetCurrentDirectory;
  try
    TDirectory.SetCurrentDirectory(TPath.GetDirectoryName(FEngineDprojPath));
    LProjectInfo := FScanner.Scan('DX.Comply.Engine.dproj', 'Win32', 'Debug');
    try
      Assert.IsTrue(LProjectInfo.ProjectDir <> '',
        'ProjectDir must not be empty for a relative project path');
      Assert.IsFalse(TPath.IsRelativePath(LProjectInfo.ProjectDir),
        'ProjectDir must be absolute even for a relative project path');
      Assert.IsTrue(LProjectInfo.OutputDir <> '',
        'OutputDir must not be empty for a relative project path');
    finally
      LProjectInfo.Free;
    end;
  finally
    TDirectory.SetCurrentDirectory(LSavedCwd);
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ExtractsMainSourcePath;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsTrue(TFile.Exists(LProjectInfo.MainSourcePath),
      'MainSourcePath must resolve to an existing .dpk or .dpr file');
    Assert.IsTrue(SameText(TPath.GetFileName(LProjectInfo.MainSourcePath), 'DX.Comply.Engine.dpk'),
      'The engine project must resolve its main package source file');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ExtractsExplicitUnitReferences;
var
  LProjectInfo: TProjectInfo;
  LReference: TProjectUnitReference;
  LFound: Boolean;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsNotNull(LProjectInfo.ExplicitUnitReferences,
      'ExplicitUnitReferences must be assigned after scanning');
    LFound := False;
    for LReference in LProjectInfo.ExplicitUnitReferences do
    begin
      if not SameText(LReference.UnitName, 'DX.Comply.Engine.Intf') then
        Continue;
      LFound := True;
      Assert.IsTrue(TFile.Exists(LReference.FilePath),
        'Explicit engine package references must resolve to existing source files');
      Break;
    end;
    Assert.IsTrue(LFound,
      'The engine package must expose DX.Comply.Engine.Intf as an explicit unit reference');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_DetectsToolchainMetadata;
var
  LDebugDir: string;
  LProjectInfo: TProjectInfo;
  LSourceDir: string;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsTrue(LProjectInfo.Toolchain.Version <> '',
      'A Delphi version must be detected for the active toolchain');
    Assert.IsTrue(LProjectInfo.Toolchain.BuildVersion <> '',
      'A Delphi build version must be detected for the active toolchain');
    Assert.IsTrue(TDirectory.Exists(LProjectInfo.Toolchain.RootDir),
      'The detected Delphi toolchain root directory must exist');
    Assert.IsNotNull(LProjectInfo.GlobalSearchPaths,
      'GlobalSearchPaths must be assigned after scanning');
    Assert.IsTrue(LProjectInfo.GlobalSearchPaths.Count > 0,
      'The detected Delphi toolchain must contribute at least one global search root');

    LDebugDir := TPath.Combine(LProjectInfo.Toolchain.RootDir, 'lib\Win32\debug');
    LSourceDir := TPath.Combine(LProjectInfo.Toolchain.RootDir, 'source');
    if TDirectory.Exists(LDebugDir) and TDirectory.Exists(LSourceDir) and
      LProjectInfo.GlobalSearchPaths.Contains(LDebugDir) and
      LProjectInfo.GlobalSearchPaths.Contains(LSourceDir) then
      Assert.IsTrue(LProjectInfo.GlobalSearchPaths.IndexOf(LDebugDir) <
        LProjectInfo.GlobalSearchPaths.IndexOf(LSourceDir),
        'Toolchain debug DCU paths must be searched before Delphi source fallbacks');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_DebugConfig_UsesDebugDCUs;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsTrue(LProjectInfo.UsesDebugDCUs,
      'Debug builds must prefer Delphi debug DCUs unless the project explicitly disables them');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ReleaseConfig_DisablesDebugDCUs;
var
  LProjectInfo: TProjectInfo;
  LReleaseDir: string;
  LSourceDir: string;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Release');
  try
    Assert.IsFalse(LProjectInfo.UsesDebugDCUs,
      'Release builds must prefer Delphi release DCUs unless the project explicitly enables debug DCUs');

    LReleaseDir := TPath.Combine(LProjectInfo.Toolchain.RootDir, 'lib\Win32\release');
    LSourceDir := TPath.Combine(LProjectInfo.Toolchain.RootDir, 'source');
    if TDirectory.Exists(LReleaseDir) and TDirectory.Exists(LSourceDir) and
      LProjectInfo.GlobalSearchPaths.Contains(LReleaseDir) and
      LProjectInfo.GlobalSearchPaths.Contains(LSourceDir) then
      Assert.IsTrue(LProjectInfo.GlobalSearchPaths.IndexOf(LReleaseDir) <
        LProjectInfo.GlobalSearchPaths.IndexOf(LSourceDir),
        'Toolchain release DCU paths must be searched before Delphi source fallbacks');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_Win64Platform_OutputDirContainsWin64;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win64', 'Debug');
  try
    Assert.IsTrue(Pos('Win64', LProjectInfo.OutputDir) > 0,
      'OutputDir must contain Win64 when the Win64 platform is requested');
  finally
    LProjectInfo.Free;
  end;
end;

// ---- Legacy Delphi 2007 format -----------------------------------------------

procedure TProjectScannerTests.Scan_LegacyConfigPlatformCondition_ExtractsOutputDir;
var
  LTempDir: string;
  LTempDproj: string;
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
const
  cLegacyDproj =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>LegacyApp.dpr</MainSource>' + sLineBreak +
    '    <ProjectGuid>{00000000-0000-0000-0000-000000000001}</ProjectGuid>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Configuration)|$(Platform)''==''Release|Win32''">' + sLineBreak +
    '    <DCC_ExeOutput>.\output\release</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Configuration)|$(Platform)''==''Debug|Win32''">' + sLineBreak +
    '    <DCC_ExeOutput>.\output\debug</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>';
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_Legacy');
  ForceDirectories(LTempDir);
  LTempDproj := TPath.Combine(LTempDir, 'LegacyApp.dproj');
  try
    TFile.WriteAllText(LTempDproj, cLegacyDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LTempDproj, 'Win32', 'Release');
    try
      Assert.IsTrue(Pos('release', LowerCase(LProjectInfo.OutputDir)) > 0,
        'Legacy $(Configuration)|$(Platform) condition must resolve the Release output directory');
    finally
      LProjectInfo.Free;
    end;
  finally
    TFile.Delete(LTempDproj);
    TDirectory.Delete(LTempDir);
  end;
end;

procedure TProjectScannerTests.Scan_LegacyAnyCPUCondition_ExtractsOutputDir;
var
  LTempDir: string;
  LTempDproj: string;
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
const
  cAnyCpuDproj =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>OldApp.dpr</MainSource>' + sLineBreak +
    '    <ProjectGuid>{00000000-0000-0000-0000-000000000002}</ProjectGuid>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Configuration)|$(Platform)''==''Release|AnyCPU''">' + sLineBreak +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>';
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_AnyCPU');
  ForceDirectories(LTempDir);
  LTempDproj := TPath.Combine(LTempDir, 'OldApp.dproj');
  try
    TFile.WriteAllText(LTempDproj, cAnyCpuDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LTempDproj, 'Win32', 'Release');
    try
      Assert.IsTrue(Pos('bin', LowerCase(LProjectInfo.OutputDir)) > 0,
        'AnyCPU fallback condition must resolve the output directory when no platform-specific block exists');
    finally
      LProjectInfo.Free;
    end;
  finally
    TFile.Delete(LTempDproj);
    TDirectory.Delete(LTempDir);
  end;
end;

// ---- Named <Platform> entries (regression #16) ------------------------------

procedure TProjectScannerTests.Scan_NamedPlatformEntry_iOSDevice64_NoTargetedPlatformsWarning;
// Regression test for issue #16: projects that target LLVM/mobile platforms
// (iOSDevice64, Android64, …) declare them via named <Platform value="X">True</Platform>
// entries inside the BorlandProject ItemGroup — NOT in the legacy numeric
// TargetedPlatforms bitmask.  Scanning such a project with platform
// 'iOSDevice64' must not emit a "not listed in TargetedPlatforms" warning.
var
  LTempDir: string;
  LTempDproj: string;
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LWarning: string;
  LHasTargetedPlatformsWarning: Boolean;
const
  // Bitmask 1 = Win32 only — iOSDevice64 (128) is intentionally absent so
  // the scanner must fall back to the named-entry parsing path.
  cIosDproj =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>MyApp.dpr</MainSource>' + sLineBreak +
    '    <ProjectGuid>{00000000-0000-0000-0000-000000000016}</ProjectGuid>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Configuration)|$(Platform)''==''Release|iOSDevice64''">' + sLineBreak +
    '    <DCC_ExeOutput>.\bin\iOSDevice64\Release</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <BuildConfiguration Include="Release">' + sLineBreak +
    '      <Key>Cfg_2</Key>' + sLineBreak +
    '    </BuildConfiguration>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '  <ProjectExtensions>' + sLineBreak +
    '    <BorlandProject>' + sLineBreak +
    '      <Platforms>' + sLineBreak +
    '        <Platform value="Win32">True</Platform>' + sLineBreak +
    '        <Platform value="iOSDevice64">True</Platform>' + sLineBreak +
    '        <Platform value="Android64">False</Platform>' + sLineBreak +
    '      </Platforms>' + sLineBreak +
    '    </BorlandProject>' + sLineBreak +
    '  </ProjectExtensions>' + sLineBreak +
    '</Project>';
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_iOS16');
  ForceDirectories(LTempDir);
  LTempDproj := TPath.Combine(LTempDir, 'MyApp.dproj');
  try
    TFile.WriteAllText(LTempDproj, cIosDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LTempDproj, 'iOSDevice64', 'Release');
    try
      LHasTargetedPlatformsWarning := False;
      for LWarning in LProjectInfo.Warnings do
        if Pos('TargetedPlatforms', LWarning) > 0 then
        begin
          LHasTargetedPlatformsWarning := True;
          Break;
        end;
      Assert.IsFalse(LHasTargetedPlatformsWarning,
        'No TargetedPlatforms warning must be emitted for iOSDevice64 ' +
        'when it is declared via a named <Platform value="iOSDevice64">True</Platform> entry');
    finally
      LProjectInfo.Free;
    end;
  finally
    TFile.Delete(LTempDproj);
    TDirectory.Delete(LTempDir);
  end;
end;

// ---- Environment variable expansion (regression #27) -----------------------

procedure TProjectScannerTests.Scan_DprojWithEnvVarInOutputDir_ExpandsEnvVar;
const
  cEnvVarName  = 'DXCOMPLY_TEST_OUTPUT';
  cEnvVarValue = 'env_expanded_segment';
var
  LTempDir, LTempDproj: string;
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LDproj: string;
begin
  // Set a process-level env var so NormalizePath has something to resolve.
  Winapi.Windows.SetEnvironmentVariable(PChar(cEnvVarName), PChar(cEnvVarValue));
  try
    // Use the Delphi 2007 legacy condition format the scanner recognizes:
    // '$(Configuration)|$(Platform)'=='Release|Win32'. Modern .dproj files
    // use $(Cfg_N) keys instead, but the legacy form is sufficient to
    // exercise the env-var expansion path.
    LDproj :=
      '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
      '  <PropertyGroup>' + sLineBreak +
      '    <MainSource>EnvVarApp.dpr</MainSource>' + sLineBreak +
      '    <ProjectGuid>{00000000-0000-0000-0000-000000000099}</ProjectGuid>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '  <PropertyGroup Condition="''$(Configuration)|$(Platform)''==''Release|Win32''">' + sLineBreak +
      '    <DCC_ExeOutput>.\bin\$(' + cEnvVarName + ')</DCC_ExeOutput>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '</Project>';

    LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_EnvVar');
    ForceDirectories(LTempDir);
    LTempDproj := TPath.Combine(LTempDir, 'EnvVarApp.dproj');
    try
      TFile.WriteAllText(LTempDproj, LDproj, TEncoding.UTF8);
      LScanner := TProjectScanner.Create;
      LProjectInfo := LScanner.Scan(LTempDproj, 'Win32', 'Release');
      try
        Assert.IsTrue(Pos(cEnvVarValue, LProjectInfo.OutputDir) > 0,
          'OutputDir must contain the expanded env var value but was: ' +
          LProjectInfo.OutputDir);
        Assert.IsTrue(Pos('$(' + cEnvVarName + ')', LProjectInfo.OutputDir) = 0,
          'OutputDir must not contain the unresolved $(VarName) token');
      finally
        LProjectInfo.Free;
      end;
    finally
      if TFile.Exists(LTempDproj) then
        TFile.Delete(LTempDproj);
      if TDirectory.Exists(LTempDir) then
        TDirectory.Delete(LTempDir);
    end;
  finally
    Winapi.Windows.SetEnvironmentVariable(PChar(cEnvVarName), nil);
  end;
end;

procedure TProjectScannerTests.Scan_EngineDproj_ResolvesPackageOutputFile;
var
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := FScanner.Scan(FEngineDprojPath, 'Win32', 'Debug');
  try
    Assert.IsTrue(LProjectInfo.OutputFilePath.EndsWith('DX.Comply.Engine370.bpl'),
      'Package output must be ProjectName + DllSuffix + .bpl, but was: ' +
      LProjectInfo.OutputFilePath);
    Assert.IsTrue(Pos('Win32', LProjectInfo.ArtefactOutputDir) > 0,
      'ArtefactOutputDir must contain the active platform');
    Assert.IsTrue(Pos('Debug', LProjectInfo.ArtefactOutputDir) > 0,
      'ArtefactOutputDir must contain the active configuration');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TProjectScannerTests.Scan_LibraryDproj_AppendsDllSuffix;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
  LTempDproj: string;
const
  cDproj =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>Demo.dpr</MainSource>' + sLineBreak +
    '    <AppType>Library</AppType>' + sLineBreak +
    '    <DllSuffix>_sfx</DllSuffix>' + sLineBreak +
    '    <DCC_ExeOutput>.\out\$(Platform)\$(Config)</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>';
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_DllSuffix');
  ForceDirectories(LTempDir);
  LTempDproj := TPath.Combine(LTempDir, 'Demo.dproj');
  try
    TFile.WriteAllText(LTempDproj, cDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LTempDproj, 'Win64', 'Debug');
    try
      Assert.IsTrue(LProjectInfo.OutputFilePath.EndsWith('Demo_sfx.dll'),
        'Library output must append DllSuffix, but was: ' + LProjectInfo.OutputFilePath);
      Assert.IsTrue(Pos('Win64', LProjectInfo.OutputFilePath) > 0,
        'Library output path must contain the active platform');
      Assert.IsTrue(Pos('Debug', LProjectInfo.OutputFilePath) > 0,
        'Library output path must contain the active configuration');
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LTempDproj) then
      TFile.Delete(LTempDproj);
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir);
  end;
end;

procedure TProjectScannerTests.Scan_ApplicationDproj_IgnoresDllSuffix;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
  LTempDproj: string;
  LWarning: string;
const
  cDproj =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>Demo.dpr</MainSource>' + sLineBreak +
    '    <AppType>Application</AppType>' + sLineBreak +
    '    <DllSuffix>$(Auto)</DllSuffix>' + sLineBreak +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>';
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_ExeName');
  ForceDirectories(LTempDir);
  LTempDproj := TPath.Combine(LTempDir, 'Demo.dproj');
  try
    TFile.WriteAllText(LTempDproj, cDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LTempDproj, 'Win32', 'Release');
    try
      Assert.IsTrue(LProjectInfo.OutputFilePath.EndsWith('Demo.exe'),
        'Application output must not append DllSuffix, but was: ' +
        LProjectInfo.OutputFilePath);
      Assert.IsTrue(Pos('$(Auto)', LProjectInfo.OutputFilePath) = 0,
        'An unresolved suffix must not be written into an exe name');
      for LWarning in LProjectInfo.Warnings do
        Assert.IsTrue(Pos('DllSuffix', LWarning) = 0,
          'An application must not warn about DllSuffix: ' + LWarning);
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LTempDproj) then
      TFile.Delete(LTempDproj);
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir);
  end;
end;

procedure TProjectScannerTests.Scan_PackageDproj_UsesBplOutputDir;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
  LTempDproj: string;
const
  cDproj =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>Demo.dpk</MainSource>' + sLineBreak +
    '    <AppType>Package</AppType>' + sLineBreak +
    '    <DllSuffix>290</DllSuffix>' + sLineBreak +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
    '    <DCC_BplOutput>.\bpl\$(Platform)\$(Config)</DCC_BplOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>';
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_BplDir');
  ForceDirectories(LTempDir);
  LTempDproj := TPath.Combine(LTempDir, 'Demo.dproj');
  try
    TFile.WriteAllText(LTempDproj, cDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LTempDproj, 'Win32', 'Release');
    try
      Assert.IsTrue(Pos('\bpl\', LowerCase(LProjectInfo.OutputFilePath)) > 0,
        'Package output must live under the BPL directory, but was: ' +
        LProjectInfo.OutputFilePath);
      Assert.IsTrue(LProjectInfo.OutputFilePath.EndsWith('Demo290.bpl'),
        'Package output must include DllSuffix');
      Assert.IsTrue(LowerCase(LProjectInfo.OutputDir).EndsWith('\bin'),
        'OutputDir still prefers DCC_ExeOutput, but was: ' + LProjectInfo.OutputDir);
      Assert.IsTrue(Pos('\bpl\', LowerCase(LProjectInfo.ArtefactOutputDir)) > 0,
        'ArtefactOutputDir must be the BPL directory');
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LTempDproj) then
      TFile.Delete(LTempDproj);
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir);
  end;
end;

procedure TProjectScannerTests.Scan_LibrarySource_DetectedWithoutAppType;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
  LTempDproj: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_LibSource');
  ForceDirectories(LTempDir);
  LTempDproj := TPath.Combine(LTempDir, 'Demo.dproj');
  try
    TFile.WriteAllText(TPath.Combine(LTempDir, 'Demo.dpr'),
      'library Demo;' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak,
      TEncoding.UTF8);
    TFile.WriteAllText(LTempDproj,
      '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
      '  <PropertyGroup>' + sLineBreak +
      '    <MainSource>Demo.dpr</MainSource>' + sLineBreak +
      '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '</Project>', TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LTempDproj, 'Win32', 'Release');
    try
      Assert.IsTrue(LProjectInfo.OutputFilePath.EndsWith('Demo.dll'),
        'A library source file must produce a .dll when AppType is absent, but was: ' +
        LProjectInfo.OutputFilePath);
    finally
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.Scan_UnresolvedDllSuffix_LeavesOutputFileEmpty;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
  LTempDproj: string;
  LWarning: string;
  LSawSuffixWarning: Boolean;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_AutoSuffix');
  ForceDirectories(LTempDir);
  LTempDproj := TPath.Combine(LTempDir, 'Demo.dproj');
  try
    TFile.WriteAllText(LTempDproj,
      '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
      '  <PropertyGroup>' + sLineBreak +
      '    <MainSource>Demo.dpk</MainSource>' + sLineBreak +
      '    <AppType>Package</AppType>' + sLineBreak +
      '    <DllSuffix>$(Auto)</DllSuffix>' + sLineBreak +
      '    <DCC_BplOutput>.\bpl</DCC_BplOutput>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '</Project>', TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LTempDproj, 'Win32', 'Release');
    try
      Assert.AreEqual('', LProjectInfo.OutputFilePath,
        'An unresolved $(Auto) suffix must not invent an output file name');
      Assert.IsTrue(Pos('bpl', LowerCase(LProjectInfo.ArtefactOutputDir)) > 0,
        'The BPL directory must still be the directory that is scanned');
      LSawSuffixWarning := False;
      for LWarning in LProjectInfo.Warnings do
        if Pos('DllSuffix', LWarning) > 0 then
          LSawSuffixWarning := True;
      Assert.IsTrue(LSawSuffixWarning,
        'An unresolved DllSuffix must be reported');
    finally
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

function MakeTempDir: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := TPath.Combine(TPath.GetTempPath,
    'dxc-' + GUIDToString(LGuid).Trim(['{', '}']));
  ForceDirectories(Result);
end;

procedure PushBds(const AVersionDir: string; out APrevious: string);
begin
  APrevious := System.SysUtils.GetEnvironmentVariable('BDS');
  ForceDirectories(AVersionDir);
  Winapi.Windows.SetEnvironmentVariable(PChar('BDS'), PChar(AVersionDir));
end;

procedure PopBds(const APrevious: string);
begin
  if APrevious = '' then
    Winapi.Windows.SetEnvironmentVariable(PChar('BDS'), nil)
  else
    Winapi.Windows.SetEnvironmentVariable(PChar('BDS'), PChar(APrevious));
end;

function ProgressText(const AInfo: TProjectInfo): string;
var
  LNote: string;
begin
  Result := '';
  if not Assigned(AInfo.ProgressNotes) then
    Exit;
  for LNote in AInfo.ProgressNotes do
    Result := Result + LNote + sLineBreak;
end;

procedure WriteU16(var ABytes: TBytes; AOffset: Integer; AValue: Word);
begin
  ABytes[AOffset] := Byte(AValue and $00FF);
  ABytes[AOffset + 1] := Byte(AValue shr 8);
end;

procedure WriteU32(var ABytes: TBytes; AOffset: Integer; AValue: Cardinal);
begin
  ABytes[AOffset] := Byte(AValue and $FF);
  ABytes[AOffset + 1] := Byte((AValue shr 8) and $FF);
  ABytes[AOffset + 2] := Byte((AValue shr 16) and $FF);
  ABytes[AOffset + 3] := Byte((AValue shr 24) and $FF);
end;

procedure WriteAsciiZ(var ABytes: TBytes; AOffset: Integer; const AText: string);
var
  I: Integer;
begin
  for I := 1 to Length(AText) do
    ABytes[AOffset + I - 1] := Byte(Ord(AText[I]));
  ABytes[AOffset + Length(AText)] := 0;
end;

// Minimal PE image: DOS stub, one section at RVA $1000 / file $200, and an
// import directory whose DLL names sit just after the descriptor table.
function BuildImportPe(APe32Plus: Boolean; const ADllNames: array of string): TBytes;
const
  cFileSize = $400;
  cSectionVa = $1000;
  cSectionRaw = $200;
var
  LDataOffset: Integer;
  LDescAt: Integer;
  LFilePos: Integer;
  LImportSize: Integer;
  LMachine: Word;
  LMagic: Word;
  LNameRva: Integer;
  LNumberOffset: Integer;
  LOptSize: Integer;
  LSectionAt: Integer;
  I: Integer;
begin
  SetLength(Result, cFileSize);
  if APe32Plus then
  begin
    LMachine := $8664;
    LOptSize := 240;
    LMagic := $020B;
    LNumberOffset := 108;
    LDataOffset := 112;
  end
  else
  begin
    LMachine := $014C;
    LOptSize := 224;
    LMagic := $010B;
    LNumberOffset := 92;
    LDataOffset := 96;
  end;

  WriteU16(Result, 0, $5A4D);
  WriteU32(Result, $3C, $80);
  WriteU32(Result, $80, $4550);
  WriteU16(Result, $84, LMachine);
  WriteU16(Result, $86, 1);
  WriteU16(Result, $94, Word(LOptSize));
  WriteU16(Result, $98, LMagic);
  WriteU32(Result, $98 + LNumberOffset, 16);
  LImportSize := 20 * (Length(ADllNames) + 1);
  WriteU32(Result, $98 + LDataOffset + 8, cSectionVa);
  WriteU32(Result, $98 + LDataOffset + 12, Cardinal(LImportSize));

  LSectionAt := $98 + LOptSize;
  WriteU32(Result, LSectionAt + 8, $200);
  WriteU32(Result, LSectionAt + 12, cSectionVa);
  WriteU32(Result, LSectionAt + 16, $200);
  WriteU32(Result, LSectionAt + 20, cSectionRaw);

  LNameRva := cSectionVa + LImportSize;
  LFilePos := cSectionRaw + LImportSize;
  for I := 0 to High(ADllNames) do
  begin
    LDescAt := cSectionRaw + (I * 20);
    WriteU32(Result, LDescAt, $2000);
    WriteU32(Result, LDescAt + 12, Cardinal(LNameRva));
    WriteU32(Result, LDescAt + 16, $2100);
    if LFilePos + Length(ADllNames[I]) >= cFileSize then
      raise Exception.Create('Synthetic PE import name does not fit');
    WriteAsciiZ(Result, LFilePos, ADllNames[I]);
    Inc(LNameRva, Length(ADllNames[I]) + 1);
    Inc(LFilePos, Length(ADllNames[I]) + 1);
  end;
end;

function ProductVersionDproj: string;
begin
  Result :=
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>DecApp.dpr</MainSource>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\Compiled\BIN_IDE$(ProductVersion)_$(Platform)_$(Config)</DCC_ExeOutput>' + sLineBreak +
    '    <DCC_DcuOutput>.\Compiled\DCU_IDE$(BDSVersion)_$(Platform)_$(Config)</DCC_DcuOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak;
end;

procedure TProjectScannerTests.Scan_ProductVersion_UsesEmptyDirWhenThatIsTheOnlyOne;
var
  LNotes: string;
  LPreviousBds: string;
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
begin
  LTempDir := MakeTempDir;
  LPreviousBds := '';
  try
    PushBds(TPath.Combine(LTempDir, 'Studio', '37.0'), LPreviousBds);
    ForceDirectories(TPath.Combine(LTempDir, 'Compiled', 'BIN_IDE_Win32_Release'));
    ForceDirectories(TPath.Combine(LTempDir, 'Compiled', 'DCU_IDE_Win32_Release'));
    TFile.WriteAllText(TPath.Combine(LTempDir, 'DecApp.dproj'),
      ProductVersionDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(TPath.Combine(LTempDir, 'DecApp.dproj'),
      'Win32', 'Release');
    try
      Assert.IsTrue(LProjectInfo.OutputDir.EndsWith('\Compiled\BIN_IDE_Win32_Release'),
        'The directory with an empty ProductVersion must be used, but was: ' +
        LProjectInfo.OutputDir);
      Assert.IsTrue(Pos('$(', LProjectInfo.OutputDir) = 0,
        'The resolved output path must contain no $( token: ' + LProjectInfo.OutputDir);
      Assert.IsTrue(Pos('37.0', LProjectInfo.OutputDir) = 0,
        'The empty ProductVersion directory was expected: ' + LProjectInfo.OutputDir);
      Assert.IsTrue(LProjectInfo.DcuOutputDir.EndsWith('\Compiled\DCU_IDE_Win32_Release'),
        '$(BDSVersion) must follow the empty-token directory, but was: ' +
        LProjectInfo.DcuOutputDir);
      Assert.IsTrue(Pos('$(', LProjectInfo.DcuOutputDir) = 0,
        'The resolved DCU path must contain no $( token: ' + LProjectInfo.DcuOutputDir);
      LNotes := ProgressText(LProjectInfo);
      Assert.IsTrue(Pos('DCC_ExeOutput', LNotes) > 0,
        'Verbose progress must name the output directory: ' + LNotes);
      Assert.IsTrue(Pos('left empty', LNotes) > 0,
        'Verbose progress must say the empty ProductVersion directory was used: ' +
        LNotes);
    finally
      LProjectInfo.Free;
    end;
  finally
    PopBds(LPreviousBds);
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.Scan_ProductVersion_UsesExpandedDirWhenItExists;
var
  LNotes: string;
  LPreviousBds: string;
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
begin
  LTempDir := MakeTempDir;
  LPreviousBds := '';
  try
    PushBds(TPath.Combine(LTempDir, 'Studio', '37.0'), LPreviousBds);
    ForceDirectories(TPath.Combine(LTempDir, 'Compiled', 'BIN_IDE37.0_Win32_Release'));
    ForceDirectories(TPath.Combine(LTempDir, 'Compiled', 'BIN_IDE_Win32_Release'));
    ForceDirectories(TPath.Combine(LTempDir, 'Compiled', 'DCU_IDE37.0_Win32_Release'));
    TFile.WriteAllText(TPath.Combine(LTempDir, 'DecApp.dproj'),
      ProductVersionDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(TPath.Combine(LTempDir, 'DecApp.dproj'),
      'Win32', 'Release');
    try
      Assert.IsTrue(
        LProjectInfo.OutputDir.EndsWith('\Compiled\BIN_IDE37.0_Win32_Release'),
        'The directory with the BDS version must win, but was: ' +
        LProjectInfo.OutputDir);
      Assert.IsTrue(Pos('$(', LProjectInfo.OutputDir) = 0,
        'The resolved output path must contain no $( token: ' + LProjectInfo.OutputDir);
      Assert.IsTrue(
        LProjectInfo.DcuOutputDir.EndsWith('\Compiled\DCU_IDE37.0_Win32_Release'),
        '$(BDSVersion) must expand to the detected BDS version, but was: ' +
        LProjectInfo.DcuOutputDir);
      Assert.IsTrue(Pos('$(', LProjectInfo.DcuOutputDir) = 0,
        'The resolved DCU path must contain no $( token: ' + LProjectInfo.DcuOutputDir);
      LNotes := ProgressText(LProjectInfo);
      Assert.IsTrue(Pos('expanded properties; the directory exists', LNotes) > 0,
        'Verbose progress must say the expanded directory was used: ' + LNotes);
      Assert.IsTrue(Pos('left empty', LNotes) = 0,
        'The empty ProductVersion directory must not be chosen when the expanded one exists: ' +
        LNotes);
    finally
      LProjectInfo.Free;
    end;
  finally
    PopBds(LPreviousBds);
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.Scan_UsePackagesMissing_ReturnsNoRuntimePackages;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
begin
  LTempDir := MakeTempDir;
  try
    TFile.WriteAllText(TPath.Combine(LTempDir, 'PkgApp.dproj'),
      '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
      '  <PropertyGroup>' + sLineBreak +
      '    <MainSource>PkgApp.dpr</MainSource>' + sLineBreak +
      '    <AppType>Console</AppType>' + sLineBreak +
      '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
      '    <DCC_UsePackage>rtl;vcl;fmx</DCC_UsePackage>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '</Project>' + sLineBreak, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(TPath.Combine(LTempDir, 'PkgApp.dproj'),
      'Win32', 'Release');
    try
      Assert.IsNotNull(LProjectInfo.RuntimePackages);
      Assert.AreEqual(NativeInt(0), NativeInt(LProjectInfo.RuntimePackages.Count),
        'DCC_UsePackage without UsePackages must not be linked');
    finally
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.Scan_UsePackagesTrueInBase_ReturnsPackages;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
begin
  LTempDir := MakeTempDir;
  try
    TFile.WriteAllText(TPath.Combine(LTempDir, 'PkgApp.dproj'),
      '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
      '  <PropertyGroup>' + sLineBreak +
      '    <MainSource>PkgApp.dpr</MainSource>' + sLineBreak +
      '    <AppType>Console</AppType>' + sLineBreak +
      '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
      '    <UsePackages>true</UsePackages>' + sLineBreak +
      '    <DCC_UsePackage>rtl;vcl</DCC_UsePackage>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '</Project>' + sLineBreak, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(TPath.Combine(LTempDir, 'PkgApp.dproj'),
      'Win32', 'Release');
    try
      Assert.AreEqual(NativeInt(2), NativeInt(LProjectInfo.RuntimePackages.Count),
        'UsePackages true in Base must return the declared packages');
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('rtl'));
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('vcl'));
    finally
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.Scan_UsePackagesTrueInOtherConfig_ReturnsNone;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
  LDproj: string;
const
  cXml =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>PkgApp.dpr</MainSource>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_UsePackage>rtl;vcl</DCC_UsePackage>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Cfg_1)''!=''''">' + sLineBreak +
    '    <UsePackages>true</UsePackages>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <BuildConfiguration Include="Debug">' + sLineBreak +
    '      <Key>Cfg_1</Key>' + sLineBreak +
    '    </BuildConfiguration>' + sLineBreak +
    '    <BuildConfiguration Include="Release">' + sLineBreak +
    '      <Key>Cfg_2</Key>' + sLineBreak +
    '    </BuildConfiguration>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>' + sLineBreak;
begin
  LTempDir := MakeTempDir;
  try
    LDproj := TPath.Combine(LTempDir, 'PkgApp.dproj');
    TFile.WriteAllText(LDproj, cXml, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(LDproj, 'Win32', 'Release');
    try
      Assert.AreEqual(NativeInt(0), NativeInt(LProjectInfo.RuntimePackages.Count),
        'UsePackages true only in Debug must not apply to Release');
    finally
      LProjectInfo.Free;
    end;

    LProjectInfo := LScanner.Scan(LDproj, 'Win32', 'Debug');
    try
      Assert.AreEqual(NativeInt(2), NativeInt(LProjectInfo.RuntimePackages.Count),
        'UsePackages true in the Debug config must return the declared packages');
    finally
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

function UsePackagesDproj: string;
begin
  Result :=
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>PeApp.dpr</MainSource>' + sLineBreak +
    '    <AppType>Application</AppType>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\out</DCC_ExeOutput>' + sLineBreak +
    '    <UsePackages>true</UsePackages>' + sLineBreak +
    '    <DCC_UsePackage>rtl;vcl;vclimg;LockBox</DCC_UsePackage>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak;
end;

procedure TProjectScannerTests.Scan_UsePackages_PeImports_KeepsOnlyImportedPackages;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
begin
  LTempDir := MakeTempDir;
  try
    ForceDirectories(TPath.Combine(LTempDir, 'out'));
    TFile.WriteAllBytes(TPath.Combine(LTempDir, 'out', 'PeApp.exe'),
      BuildImportPe(False, ['rtl370.bpl', 'vclimg370.bpl', 'LockBox.bpl',
        'kernel32.dll']));
    TFile.WriteAllText(TPath.Combine(LTempDir, 'PeApp.dproj'),
      UsePackagesDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(TPath.Combine(LTempDir, 'PeApp.dproj'),
      'Win32', 'Release');
    try
      Assert.IsTrue(TFile.Exists(LProjectInfo.OutputFilePath),
        'The synthetic exe must be the resolved output file: ' +
        LProjectInfo.OutputFilePath);
      Assert.AreEqual(NativeInt(3), NativeInt(LProjectInfo.RuntimePackages.Count),
        'Only BPLs named in the import directory are kept');
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('rtl'),
        'rtl370.bpl must keep the rtl package');
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('vclimg'),
        'vclimg370.bpl must keep the vclimg package');
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('LockBox'),
        'LockBox.bpl must keep the package with no version suffix');
      Assert.IsFalse(LProjectInfo.RuntimePackages.Contains('vcl'),
        'vcl must not match vclimg370.bpl');
    finally
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.Scan_UsePackages_UnreadablePe_KeepsDeclaredPackages;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
  LTempDir: string;
begin
  LTempDir := MakeTempDir;
  try
    ForceDirectories(TPath.Combine(LTempDir, 'out'));
    TFile.WriteAllBytes(TPath.Combine(LTempDir, 'out', 'PeApp.exe'),
      TBytes.Create($4D, $5A, $00));
    TFile.WriteAllText(TPath.Combine(LTempDir, 'PeApp.dproj'),
      UsePackagesDproj, TEncoding.UTF8);
    LScanner := TProjectScanner.Create;
    LProjectInfo := LScanner.Scan(TPath.Combine(LTempDir, 'PeApp.dproj'),
      'Win32', 'Release');
    try
      Assert.AreEqual(NativeInt(4), NativeInt(LProjectInfo.RuntimePackages.Count),
        'A file that is not a valid PE must keep the UsePackages list');
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('rtl'));
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('vcl'));
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('vclimg'));
      Assert.IsTrue(LProjectInfo.RuntimePackages.Contains('LockBox'));
    finally
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.TryReadPeImportNames_SyntheticPe32_ReadsDllName;
var
  LNames: TArray<string>;
  LTempDir: string;
  LFile: string;
begin
  LTempDir := MakeTempDir;
  try
    LFile := TPath.Combine(LTempDir, 'sample.exe');
    TFile.WriteAllBytes(LFile, BuildImportPe(False, ['rtl370.bpl', 'kernel32.dll']));
    Assert.IsTrue(TryReadPeImportNames(LFile, LNames),
      'A minimal PE32 image must be readable');
    Assert.AreEqual(NativeInt(2), NativeInt(Length(LNames)));
    Assert.AreEqual('rtl370.bpl', LNames[0]);
    Assert.AreEqual('kernel32.dll', LNames[1]);
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.TryReadPeImportNames_SyntheticPe32Plus_ReadsDllName;
var
  LNames: TArray<string>;
  LTempDir: string;
  LFile: string;
begin
  LTempDir := MakeTempDir;
  try
    LFile := TPath.Combine(LTempDir, 'sample.exe');
    TFile.WriteAllBytes(LFile, BuildImportPe(True, ['vcl290.bpl']));
    Assert.IsTrue(TryReadPeImportNames(LFile, LNames),
      'A minimal PE32+ image must be readable');
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LNames)));
    Assert.AreEqual('vcl290.bpl', LNames[0]);
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.TryReadPeImportNames_Malformed_ReturnsFalse;
var
  LNames: TArray<string>;
  LTempDir: string;
  LFile: string;
begin
  LTempDir := MakeTempDir;
  try
    LFile := TPath.Combine(LTempDir, 'short.exe');
    TFile.WriteAllBytes(LFile, TBytes.Create($4D, $5A));
    Assert.IsFalse(TryReadPeImportNames(LFile, LNames),
      'A truncated MZ file must be a failed read');
    Assert.AreEqual(NativeInt(0), NativeInt(Length(LNames)));
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TProjectScannerTests.TryReadPeImportNames_TestExecutable_HasNoBplImports;
var
  LName: string;
  LNames: TArray<string>;
begin
  Assert.IsTrue(TryReadPeImportNames(ParamStr(0), LNames),
    'The running test executable must be a readable PE');
  for LName in LNames do
    Assert.IsFalse(SameText(TPath.GetExtension(LName), '.bpl'),
      'The test executable imports a BPL: ' + LName);
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectScannerTests);

end.
