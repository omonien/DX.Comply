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

    /// <summary>ProjectDir must be the src directory containing the dproj.</summary>
    [Test]
    procedure Scan_EngineDproj_ProjectDirIsValid;

    /// <summary>When scanning with Win64, OutputDir must contain 'Win64'.</summary>
    [Test]
    procedure Scan_Win64Platform_OutputDirContainsWin64;
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

initialization
  TDUnitX.RegisterTestFixture(TProjectScannerTests);

end.
