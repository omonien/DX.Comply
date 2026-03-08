/// <summary>
/// DX.Comply.Tests.FileScanner
/// DUnitX tests for TFileScanner.
/// </summary>
///
/// <remarks>
/// Verifies directory scanning, include/exclude pattern filtering,
/// file-size reporting, hash delegation, subdirectory recursion,
/// and artefact-type classification.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.FileScanner;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Winapi.Windows,
  DUnitX.TestFramework,
  DX.Comply.FileScanner,
  DX.Comply.HashService,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// DUnitX test fixture for TFileScanner.
  /// </summary>
  [TestFixture]
  TFileScannerTests = class
  private
    FTempDir: string;
    FHashService: IHashService;
    /// <summary>Returns True when AArtefacts contains an entry whose RelativePath ends with AFileName.</summary>
    function ContainsFile(const AArtefacts: TArtefactList; const AFileName: string): Boolean;
    /// <summary>Returns the TArtefactInfo for AFileName, or Default(TArtefactInfo) when not found.</summary>
    function FindArtefact(const AArtefacts: TArtefactList; const AFileName: string): TArtefactInfo;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // ---- Boundary / empty-input tests ----------------------------------------

    /// <summary>Scanning a directory that does not exist must return an empty list.</summary>
    [Test]
    procedure Scan_NonExistentDirectory_ReturnsEmpty;

    /// <summary>Scanning an empty subdirectory must return an empty list.</summary>
    [Test]
    procedure Scan_EmptyDirectory_ReturnsEmpty;

    // ---- Default-extension filtering -----------------------------------------

    /// <summary>Default scan includes .exe and .dll but excludes .dcu.</summary>
    [Test]
    procedure Scan_DefaultExtensions_IncludesExeAndDll;

    /// <summary>Default scan includes .bpl files.</summary>
    [Test]
    procedure Scan_DefaultExtensions_IncludesBpl;

    /// <summary>Default scan must exclude non-shipped Delphi build evidence files.</summary>
    [Test]
    procedure Scan_DefaultExtensions_ExcludesBuildEvidenceFiles;

    // ---- Pattern-driven filtering --------------------------------------------

    /// <summary>Passing ['*.dll'] as exclude must remove dll files from results.</summary>
    [Test]
    procedure Scan_ExcludePattern_ExcludesMatchingFiles;

    /// <summary>Passing ['*.exe'] as include must return only exe files.</summary>
    [Test]
    procedure Scan_IncludePattern_OnlyReturnsMatching;

    /// <summary>Explicit include patterns may still opt into .res files.</summary>
    [Test]
    procedure Scan_IncludePattern_CanOptIntoResourceFiles;

    // ---- Metadata correctness ------------------------------------------------

    /// <summary>FileSize of the 5-byte exe fixture must be 5.</summary>
    [Test]
    procedure Scan_FileSizeIsCorrect;

    /// <summary>Hash field is non-empty when a hash service is injected.</summary>
    [Test]
    procedure Scan_HashIsComputed_WhenHashServiceProvided;

    /// <summary>Hash field is empty when no hash service is provided.</summary>
    [Test]
    procedure Scan_HashIsEmpty_WhenNoHashService;

    // ---- Recursion -----------------------------------------------------------

    /// <summary>Files in subdirectories must be discovered.</summary>
    [Test]
    procedure Scan_SubdirectoriesAreScanned;

    // ---- GetArtefactType -----------------------------------------------------

    [Test]
    procedure GetArtefactType_Exe_ReturnsApplication;

    [Test]
    procedure GetArtefactType_Dll_ReturnsLibrary;

    [Test]
    procedure GetArtefactType_Bpl_ReturnsPackage;

    [Test]
    procedure GetArtefactType_Dcp_ReturnsDcuPackage;

    [Test]
    procedure GetArtefactType_Res_ReturnsResource;

    [Test]
    procedure GetArtefactType_Unknown_ReturnsUnknown;
  end;

implementation

{ TFileScannerTests }

procedure TFileScannerTests.Setup;
var
  LSubDir: string;
begin
  FHashService := THashService.Create;

  // Create a unique temp directory for each test run
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'dx_comply_scan_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FTempDir);

  // 5-byte fake .exe (MZ header prefix)
  TFile.WriteAllBytes(TPath.Combine(FTempDir, 'test.exe'),
    TBytes.Create($4D, $5A, $00, $00, $00));

  // 3-byte fake .dll
  TFile.WriteAllBytes(TPath.Combine(FTempDir, 'test.dll'),
    TBytes.Create($4D, $5A, $90));

  // 2-byte .dcu — must NOT appear in default-extension results
  TFile.WriteAllBytes(TPath.Combine(FTempDir, 'test.dcu'),
    TBytes.Create($FF, $FE));

  // Build evidence and intermediate files must not be treated as shipped artefacts by default
  TFile.WriteAllBytes(TPath.Combine(FTempDir, 'test.res'),
    TBytes.Create($01, $02, $03));
  TFile.WriteAllBytes(TPath.Combine(FTempDir, 'test.map'),
    TBytes.Create($10, $11, $12));
  TFile.WriteAllBytes(TPath.Combine(FTempDir, 'test.rsm'),
    TBytes.Create($20, $21, $22));
  TFile.WriteAllBytes(TPath.Combine(FTempDir, 'test.tvsconfig'),
    TBytes.Create($30, $31, $32));

  // 10-byte .bpl in a subdirectory — tests recursion
  LSubDir := TPath.Combine(FTempDir, 'subdir');
  TDirectory.CreateDirectory(LSubDir);
  TFile.WriteAllBytes(TPath.Combine(LSubDir, 'test.bpl'),
    TBytes.Create($4D, $5A, $00, $00, $00, $00, $00, $00, $00, $00));
end;

procedure TFileScannerTests.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
  FHashService := nil;
end;

function TFileScannerTests.ContainsFile(const AArtefacts: TArtefactList;
  const AFileName: string): Boolean;
var
  LArtefact: TArtefactInfo;
begin
  Result := False;
  for LArtefact in AArtefacts do
    if SameText(TPath.GetFileName(LArtefact.FilePath), AFileName) then
    begin
      Result := True;
      Break;
    end;
end;

function TFileScannerTests.FindArtefact(const AArtefacts: TArtefactList;
  const AFileName: string): TArtefactInfo;
var
  LArtefact: TArtefactInfo;
begin
  Result := Default(TArtefactInfo);
  for LArtefact in AArtefacts do
    if SameText(TPath.GetFileName(LArtefact.FilePath), AFileName) then
    begin
      Result := LArtefact;
      Break;
    end;
end;

// ---- Boundary / empty-input tests -------------------------------------------

procedure TFileScannerTests.Scan_NonExistentDirectory_ReturnsEmpty;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan('C:\this\path\does\not\exist', [], []);
  try
    Assert.AreEqual(NativeInt(0), NativeInt(LResult.Count), 'Scanning a non-existent directory must return an empty list');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_EmptyDirectory_ReturnsEmpty;
var
  LScanner: IFileScanner;
  LEmptyDir: string;
  LResult: TArtefactList;
begin
  LEmptyDir := TPath.Combine(FTempDir, 'empty');
  TDirectory.CreateDirectory(LEmptyDir);

  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(LEmptyDir, [], []);
  try
    Assert.AreEqual(NativeInt(0), NativeInt(LResult.Count), 'Scanning an empty directory must return an empty list');
  finally
    LResult.Free;
  end;
end;

// ---- Default-extension filtering --------------------------------------------

procedure TFileScannerTests.Scan_DefaultExtensions_IncludesExeAndDll;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, [], []);
  try
    Assert.IsTrue(ContainsFile(LResult, 'test.exe'), '.exe file must be included in default scan');
    Assert.IsTrue(ContainsFile(LResult, 'test.dll'), '.dll file must be included in default scan');
    Assert.IsFalse(ContainsFile(LResult, 'test.dcu'), '.dcu file must NOT be included in default scan');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_DefaultExtensions_IncludesBpl;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, [], []);
  try
    Assert.IsTrue(ContainsFile(LResult, 'test.bpl'), '.bpl file must be included in default scan');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_DefaultExtensions_ExcludesBuildEvidenceFiles;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, [], []);
  try
    Assert.IsFalse(ContainsFile(LResult, 'test.res'),
      '.res files must not be included by default because they are build evidence, not shipped artefacts');
    Assert.IsFalse(ContainsFile(LResult, 'test.map'),
      '.map files must not be included by default because they are build evidence, not shipped artefacts');
    Assert.IsFalse(ContainsFile(LResult, 'test.rsm'),
      '.rsm files must not be included by default because they are build evidence, not shipped artefacts');
    Assert.IsFalse(ContainsFile(LResult, 'test.tvsconfig'),
      '.tvsconfig files must not be included by default because they are configuration/evidence files, not shipped artefacts');
  finally
    LResult.Free;
  end;
end;

// ---- Pattern-driven filtering -----------------------------------------------

procedure TFileScannerTests.Scan_ExcludePattern_ExcludesMatchingFiles;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, [], ['*.dll']);
  try
    Assert.IsFalse(ContainsFile(LResult, 'test.dll'), '.dll must be excluded when *.dll is in exclude list');
    Assert.IsTrue(ContainsFile(LResult, 'test.exe'), '.exe must still be present after *.dll exclusion');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_IncludePattern_OnlyReturnsMatching;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, ['*.exe'], []);
  try
    Assert.IsTrue(ContainsFile(LResult, 'test.exe'), '*.exe include must include the exe file');
    Assert.IsFalse(ContainsFile(LResult, 'test.dll'), '*.exe include must exclude the dll file');
    Assert.IsFalse(ContainsFile(LResult, 'test.bpl'), '*.exe include must exclude the bpl file');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_IncludePattern_CanOptIntoResourceFiles;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, ['*.res'], []);
  try
    Assert.IsTrue(ContainsFile(LResult, 'test.res'),
      'Explicit include patterns must still allow resource files when the caller requests them intentionally');
    Assert.IsFalse(ContainsFile(LResult, 'test.exe'),
      'An explicit *.res include must limit the result set to the requested resource files');
  finally
    LResult.Free;
  end;
end;

// ---- Metadata correctness ---------------------------------------------------

procedure TFileScannerTests.Scan_FileSizeIsCorrect;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
  LArtefact: TArtefactInfo;
begin
  LScanner := TFileScanner.Create(FHashService);
  LResult := LScanner.Scan(FTempDir, ['*.exe'], []);
  try
    Assert.AreEqual(NativeInt(1), NativeInt(LResult.Count), 'Exactly one .exe must be found');
    LArtefact := FindArtefact(LResult, 'test.exe');
    Assert.AreEqual(Int64(5), LArtefact.FileSize, 'FileSize of the 5-byte exe fixture must be 5');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_HashIsComputed_WhenHashServiceProvided;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
  LArtefact: TArtefactInfo;
begin
  LScanner := TFileScanner.Create(FHashService);
  LResult := LScanner.Scan(FTempDir, ['*.exe'], []);
  try
    LArtefact := FindArtefact(LResult, 'test.exe');
    Assert.IsTrue(LArtefact.Hash <> '', 'Hash must be computed when a hash service is provided');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_HashIsEmpty_WhenNoHashService;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
  LArtefact: TArtefactInfo;
begin
  // Construct without hash service
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, ['*.exe'], []);
  try
    LArtefact := FindArtefact(LResult, 'test.exe');
    Assert.AreEqual('', LArtefact.Hash, 'Hash must be empty when no hash service is provided');
  finally
    LResult.Free;
  end;
end;

// ---- Recursion --------------------------------------------------------------

procedure TFileScannerTests.Scan_SubdirectoriesAreScanned;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, [], []);
  try
    Assert.IsTrue(ContainsFile(LResult, 'test.bpl'),
      'test.bpl in subdir must be found by recursive scan');
  finally
    LResult.Free;
  end;
end;

// ---- GetArtefactType --------------------------------------------------------

procedure TFileScannerTests.GetArtefactType_Exe_ReturnsApplication;
var
  LScanner: IFileScanner;
begin
  LScanner := TFileScanner.Create;
  Assert.AreEqual('application', LScanner.GetArtefactType('MyApp.exe'));
end;

procedure TFileScannerTests.GetArtefactType_Dll_ReturnsLibrary;
var
  LScanner: IFileScanner;
begin
  LScanner := TFileScanner.Create;
  Assert.AreEqual('library', LScanner.GetArtefactType('MyLib.dll'));
end;

procedure TFileScannerTests.GetArtefactType_Bpl_ReturnsPackage;
var
  LScanner: IFileScanner;
begin
  LScanner := TFileScanner.Create;
  Assert.AreEqual('package', LScanner.GetArtefactType('MyPkg.bpl'));
end;

procedure TFileScannerTests.GetArtefactType_Dcp_ReturnsDcuPackage;
var
  LScanner: IFileScanner;
begin
  LScanner := TFileScanner.Create;
  Assert.AreEqual('dcu-package', LScanner.GetArtefactType('MyPkg.dcp'));
end;

procedure TFileScannerTests.GetArtefactType_Res_ReturnsResource;
var
  LScanner: IFileScanner;
begin
  LScanner := TFileScanner.Create;
  Assert.AreEqual('resource', LScanner.GetArtefactType('MyApp.res'));
end;

procedure TFileScannerTests.GetArtefactType_Unknown_ReturnsUnknown;
var
  LScanner: IFileScanner;
begin
  LScanner := TFileScanner.Create;
  Assert.AreEqual('unknown', LScanner.GetArtefactType('SomeFile.xyz'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFileScannerTests);

end.
