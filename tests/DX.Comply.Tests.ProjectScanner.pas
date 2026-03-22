/// <summary>
/// DX.Comply.Tests.ProjectScanner
/// DUnitX tests for TProjectScanner.
/// </summary>
///
/// <remarks>
/// Uses DX.Comply.Engine.dproj as a real-file fixture to verify
/// project-metadata extraction (name, platform, output directory,
/// runtime packages) and path validation logic.
/// The engine .dproj is located relative to the test executable which
/// is placed in build\$(Platform)\$(Config) by the build system.
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
    /// Absolute path to DX.Comply.Engine.dproj, resolved from the test
    /// executable location (build\Win32\Debug\ -> ..\..\..\src\).
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
  end;

implementation

{ TProjectScannerTests }

procedure TProjectScannerTests.Setup;
begin
  FScanner := TProjectScanner.Create;

  // Compute path to DX.Comply.Engine.dproj from the test binary location.
  // Test binary lands in:  <repo>\build\<Platform>\<Config>\DX.Comply.Tests.exe
  // Engine dproj is at:    <repo>\src\DX.Comply.Engine.dproj
  // So we go up three levels then into src\.
  FEngineDprojPath := TPath.GetFullPath(
    TPath.Combine(TPath.GetDirectoryName(ParamStr(0)),
      '..' + PathDelim + '..' + PathDelim + '..' + PathDelim +
      'src' + PathDelim + 'DX.Comply.Engine.dproj'));
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

initialization
  TDUnitX.RegisterTestFixture(TProjectScannerTests);

end.
