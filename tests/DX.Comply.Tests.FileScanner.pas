/// <summary>
/// DX.Comply.Tests.FileScanner
/// DUnitX tests for TFileScanner.
/// </summary>
///
/// <remarks>
/// Verifies directory scanning, include/exclude pattern filtering,
/// file-size reporting, hash delegation, optional subdirectory recursion,
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

    /// <summary>
    /// A directory path containing a character that is illegal in Windows paths
    /// (e.g. the pipe '|') makes TPath.GetFullPath raise EInOutArgumentException.
    /// The scanner must catch this and treat the path like a missing directory,
    /// returning an empty list instead of crashing. Exercises the try/except
    /// branch in TFileScanner.Scan. Regression test for issue #47.
    /// </summary>
    [Test]
    procedure Scan_InvalidPathCharacters_ReturnsEmpty;

    /// <summary>
    /// A path containing an unresolved MSBuild token such as $(Platform) must be
    /// tolerated: '$', '(' and ')' are valid Windows path characters, so
    /// TPath.GetFullPath does NOT raise. The scanner simply finds no such
    /// directory and returns an empty list. Documents token tolerance (issue #47).
    /// </summary>
    [Test]
    procedure Scan_UnresolvedMSBuildToken_ReturnsEmpty;

    /// <summary>An empty directory path must return an empty list without raising.</summary>
    [Test]
    procedure Scan_EmptyPath_ReturnsEmpty;

    // ---- Default-extension filtering -----------------------------------------

    /// <summary>Default scan includes .exe and .dll but excludes .dcu.</summary>
    [Test]
    procedure Scan_DefaultExtensions_IncludesExeAndDll;

    /// <summary>Default scan includes a .bpl that sits in the scanned directory.</summary>
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

    /// <summary>
    /// Files in subdirectories are not part of the default scan (issue #38).
    /// </summary>
    [Test]
    procedure Scan_SubdirectoriesAreSkippedByDefault;

    /// <summary>
    /// The recursive walk is opt-in. test.bpl under subdir is found only then.
    /// </summary>
    [Test]
    procedure Scan_SubdirectoriesAreScanned;

    /// <summary>
    /// A plain --scan-dir path stays in that directory. ** walks further.
    /// </summary>
    [Test]
    procedure ScanLocation_PlainPath_SkipsNestedFiles;

    /// <summary>A scan location that contains ** includes nested binaries.</summary>
    [Test]
    procedure ScanLocation_DoubleStar_IncludesNestedFiles;

    /// <summary>
    /// A non-recursive glob on a scan location limits the files, and
    /// include/exclude still apply on top of that.
    /// </summary>
    [Test]
    procedure ScanLocation_GlobAndExclude_FilterFiles;

    /// <summary>
    /// The named output is listed even when the file is missing, and hashed
    /// when it exists.
    /// </summary>
    [Test]
    procedure CollectFile_ExistingFile_IsHashed;

    /// <summary>A missing file is still collected, without a hash.</summary>
    [Test]
    procedure CollectFile_MissingFile_HasNoHash;

    /// <summary>Include and exclude globs apply to the named file as well.</summary>
    [Test]
    procedure CollectFile_ExcludePattern_RejectsFile;

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

    /// <summary>
    /// README include/exclude globs must match paths relative to the scan root,
    /// including when the absolute path contains an extra "build" directory.
    /// </summary>
    [Test]
    procedure Scan_ReadmeGlobs_MatchRelativeToScanRoot;

    /// <summary>
    /// A pattern that cannot be compiled must be reported, not ignored.
    /// </summary>
    [Test]
    procedure Scan_InvalidPattern_RecordsWarning;
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

  // .bpl in the scanned directory itself. The default scan must see this.
  TFile.WriteAllBytes(TPath.Combine(FTempDir, 'shipped.bpl'),
    TBytes.Create($4D, $5A, $00, $00, $00, $00, $00, $00, $00, $00));

  // .bpl in a subdirectory. Only the opt-in recursive scan should see this.
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

procedure TFileScannerTests.Scan_InvalidPathCharacters_ReturnsEmpty;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  // The pipe '|' is illegal in Windows paths, so TPath.GetFullPath raises
  // EInOutArgumentException ("Ungültige Zeichen im Pfad"). The scanner must
  // swallow this via its try/except guard and behave like a missing directory.
  LResult := LScanner.Scan('E:\agents\_work\2\s\bad|dir', [], []);
  try
    Assert.AreEqual(NativeInt(0), NativeInt(LResult.Count),
      'Scanning a path with illegal characters must return an empty list, not crash');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_UnresolvedMSBuildToken_ReturnsEmpty;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  // '$', '(' and ')' are valid Windows path characters, so an unresolved
  // MSBuild token does NOT make TPath.GetFullPath raise. The directory just
  // does not exist, so the scan returns an empty list.
  LResult := LScanner.Scan('E:\agents\_work\2\s\$(Platform)\$(Config)', [], []);
  try
    Assert.AreEqual(NativeInt(0), NativeInt(LResult.Count),
      'Scanning a path with an unresolved MSBuild token must return an empty list');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_EmptyPath_ReturnsEmpty;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan('', [], []);
  try
    Assert.AreEqual(NativeInt(0), NativeInt(LResult.Count),
      'Scanning an empty path must return an empty list, not crash');
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
    Assert.IsTrue(ContainsFile(LResult, 'shipped.bpl'), '.bpl file must be included in default scan');
    Assert.IsFalse(ContainsFile(LResult, 'test.bpl'),
      'A .bpl in a subdirectory must not be included in the default scan');
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
    Assert.IsFalse(ContainsFile(LResult, 'shipped.bpl'), '*.exe include must exclude the bpl file');
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

procedure TFileScannerTests.Scan_SubdirectoriesAreSkippedByDefault;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, [], []);
  try
    Assert.IsFalse(ContainsFile(LResult, 'test.bpl'),
      'test.bpl in subdir must not be found unless recursion is requested');
    Assert.IsTrue(ContainsFile(LResult, 'shipped.bpl'),
      'A .bpl in the scanned directory itself must still be found');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.Scan_SubdirectoriesAreScanned;
var
  LScanner: IFileScanner;
  LResult: TArtefactList;
begin
  LScanner := TFileScanner.Create;
  LResult := LScanner.Scan(FTempDir, [], [], True);
  try
    Assert.IsTrue(ContainsFile(LResult, 'test.bpl'),
      'test.bpl in subdir must be found when the recursive scan is requested');
  finally
    LResult.Free;
  end;
end;

procedure TFileScannerTests.ScanLocation_PlainPath_SkipsNestedFiles;
var
  LNested: string;
  LResult: TArtefactList;
  LScanner: TFileScanner;
begin
  LNested := TPath.Combine(FTempDir, 'subdir', 'nested');
  TDirectory.CreateDirectory(LNested);
  TFile.WriteAllBytes(TPath.Combine(LNested, 'deep.dll'), TBytes.Create($4D, $5A));

  LScanner := TFileScanner.Create;
  try
    LResult := LScanner.ScanLocation('subdir', FTempDir, [], []);
    try
      Assert.IsTrue(ContainsFile(LResult, 'test.bpl'),
        'A plain scan-dir must include binaries directly in that directory');
      Assert.IsFalse(ContainsFile(LResult, 'deep.dll'),
        'A plain scan-dir must not walk subdirectories');
      Assert.IsFalse(ContainsFile(LResult, 'test.exe'),
        'A plain scan-dir must not include files outside that directory');
    finally
      LResult.Free;
    end;
  finally
    LScanner.Free;
  end;
end;

procedure TFileScannerTests.ScanLocation_DoubleStar_IncludesNestedFiles;
var
  LNested: string;
  LResult: TArtefactList;
  LScanner: TFileScanner;
begin
  LNested := TPath.Combine(FTempDir, 'subdir', 'nested');
  TDirectory.CreateDirectory(LNested);
  TFile.WriteAllBytes(TPath.Combine(LNested, 'deep.dll'), TBytes.Create($4D, $5A));

  LScanner := TFileScanner.Create;
  try
    LResult := LScanner.ScanLocation('subdir\**', FTempDir, [], []);
    try
      Assert.IsTrue(ContainsFile(LResult, 'test.bpl'),
        '** must still include binaries in the scan-dir root');
      Assert.IsTrue(ContainsFile(LResult, 'deep.dll'),
        '** must include binaries in subdirectories of the scan-dir');
    finally
      LResult.Free;
    end;
  finally
    LScanner.Free;
  end;
end;

procedure TFileScannerTests.ScanLocation_GlobAndExclude_FilterFiles;
var
  LResult: TArtefactList;
  LScanner: TFileScanner;
begin
  LScanner := TFileScanner.Create;
  try
    LResult := LScanner.ScanLocation('subdir\*.bpl', FTempDir, [], ['*.bpl']);
    try
      Assert.IsFalse(ContainsFile(LResult, 'test.bpl'),
        'An exclude glob must still reject a file matched by the scan-dir glob');
    finally
      LResult.Free;
    end;

    LResult := LScanner.ScanLocation('subdir\*.dll', FTempDir, [], []);
    try
      Assert.IsFalse(ContainsFile(LResult, 'test.bpl'),
        'A *.dll scan-dir glob must not return a .bpl in that directory');
    finally
      LResult.Free;
    end;
  finally
    LScanner.Free;
  end;
end;

procedure TFileScannerTests.CollectFile_ExistingFile_IsHashed;
var
  LArtefact: TArtefactInfo;
  LScanner: TFileScanner;
begin
  LScanner := TFileScanner.Create(FHashService);
  try
    Assert.IsTrue(LScanner.CollectFile(TPath.Combine(FTempDir, 'test.exe'),
      'test.exe', [], [], LArtefact),
      'An existing output file that passes the filters must be collected');
    Assert.AreEqual(Int64(5), LArtefact.FileSize,
      'The collected file must report its size');
    Assert.IsTrue(LArtefact.Hash <> '',
      'The collected file must be hashed when a hash service is available');
  finally
    LScanner.Free;
  end;
end;

procedure TFileScannerTests.CollectFile_MissingFile_HasNoHash;
var
  LArtefact: TArtefactInfo;
  LScanner: TFileScanner;
begin
  LScanner := TFileScanner.Create(FHashService);
  try
    Assert.IsTrue(LScanner.CollectFile(TPath.Combine(FTempDir, 'missing.exe'),
      'missing.exe', [], [], LArtefact),
      'The named output must be collected even when the file does not exist yet');
    Assert.AreEqual(Int64(-1), LArtefact.FileSize,
      'A missing file has no size');
    Assert.AreEqual('', LArtefact.Hash,
      'A missing file must not receive a hash');
  finally
    LScanner.Free;
  end;
end;

procedure TFileScannerTests.CollectFile_ExcludePattern_RejectsFile;
var
  LArtefact: TArtefactInfo;
  LScanner: TFileScanner;
begin
  LScanner := TFileScanner.Create;
  try
    Assert.IsFalse(LScanner.CollectFile(TPath.Combine(FTempDir, 'test.exe'),
      'test.exe', [], ['*.exe'], LArtefact),
      'An exclude glob must reject the named output file');
  finally
    LScanner.Free;
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

procedure TFileScannerTests.Scan_ReadmeGlobs_MatchRelativeToScanRoot;
var
  LArtefacts: TArtefactList;
  LBackslashArtefacts: TArtefactList;
  LReleasePath: string;
  LRoot: string;
  LScanner: TFileScanner;

  procedure WriteFile(const ARelativePath: string);
  var
    LFullPath: string;
  begin
    LFullPath := TPath.Combine(LRoot, ARelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(LFullPath));
    TFile.WriteAllBytes(LFullPath, TBytes.Create($4D, $5A));
  end;

begin
  // The scan root sits under a parent directory named "build". Patterns match
  // the path relative to that root, so build/** keeps output\helper.exe out.
  LRoot := TPath.Combine(TPath.GetTempPath, 'dx_glob_' + IntToStr(GetTickCount));
  LRoot := TPath.Combine(LRoot, 'build', 'client');
  TDirectory.CreateDirectory(LRoot);
  try
    WriteFile('output\helper.exe');
    WriteFile('build\Win32\Release\app.exe');
    WriteFile('build\Win32\Debug\debug.exe');
    WriteFile('build\Win32\Release\unit.dcu');
    WriteFile('notes.dcu');

    LScanner := TFileScanner.Create;
    try
      LArtefacts := LScanner.Scan(LRoot, ['build/**'], ['build/**/Debug/**', '**/*.dcu'], True);
      try
        Assert.IsTrue(ContainsFile(LArtefacts, 'app.exe'),
          'build/** must include build\Win32\Release\app.exe relative to the scan root');
        LReleasePath := FindArtefact(LArtefacts, 'app.exe').FilePath;
        Assert.IsTrue(LReleasePath.StartsWith(LRoot),
          'The matched file must be the absolute path under the scan root');
        Assert.IsFalse(ContainsFile(LArtefacts, 'debug.exe'),
          'build/**/Debug/** must exclude the Debug tree');
        Assert.IsFalse(ContainsFile(LArtefacts, 'unit.dcu'),
          '**/*.dcu must exclude a dcu under build');
        Assert.IsFalse(ContainsFile(LArtefacts, 'notes.dcu'),
          '**/*.dcu must exclude a dcu at the scan root');
        Assert.IsFalse(ContainsFile(LArtefacts, 'helper.exe'),
          'A file outside the relative build directory must not match build/**');
        Assert.AreEqual(NativeInt(0), NativeInt(Length(LScanner.PatternWarnings)),
          'The README patterns must compile');
      finally
        LArtefacts.Free;
      end;

      LBackslashArtefacts := LScanner.Scan(LRoot,
        ['build\**'], ['build\**\Debug\**', '**\*.dcu'], True);
      try
        Assert.IsTrue(ContainsFile(LBackslashArtefacts, 'app.exe'),
          'Backslash globs must match the same relative path as slash globs');
        Assert.IsFalse(ContainsFile(LBackslashArtefacts, 'debug.exe'),
          'Backslash exclude globs must exclude the Debug tree');
      finally
        LBackslashArtefacts.Free;
      end;
    finally
      LScanner.Free;
    end;
  finally
    if TDirectory.Exists(TPath.GetDirectoryName(TPath.GetDirectoryName(LRoot))) then
      TDirectory.Delete(TPath.GetDirectoryName(TPath.GetDirectoryName(LRoot)), True);
  end;
end;

procedure TFileScannerTests.Scan_InvalidPattern_RecordsWarning;
var
  LArtefacts: TArtefactList;
  LScanner: TFileScanner;
begin
  LScanner := TFileScanner.Create;
  try
    LArtefacts := LScanner.Scan(FTempDir, [], ['*' + #10 + '.exe']);
    try
      Assert.IsTrue(Length(LScanner.PatternWarnings) > 0,
        'An invalid exclude pattern must be reported');
      Assert.IsTrue(Pos('control character', LScanner.PatternWarnings[0]) > 0,
        'The warning must describe why the pattern was rejected');
      Assert.IsTrue(ContainsFile(LArtefacts, 'test.exe'),
        'An invalid exclude pattern must not hide files');
    finally
      LArtefacts.Free;
    end;
  finally
    LScanner.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFileScannerTests);

end.
