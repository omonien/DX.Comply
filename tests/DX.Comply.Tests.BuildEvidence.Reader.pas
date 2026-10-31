/// <summary>
/// DX.Comply.Tests.BuildEvidence.Reader
/// DUnitX tests for TBuildEvidenceReader.
/// </summary>
///
/// <remarks>
/// Verifies the first-pass reader that maps already scanned TProjectInfo data
/// into a normalized TBuildEvidence structure.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.BuildEvidence.Reader;

interface

uses
  DUnitX.TestFramework,
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.BuildEvidence.Reader;

type
  /// <summary>
  /// DUnitX fixture for the build evidence reader.
  /// </summary>
  [TestFixture]
  TBuildEvidenceReaderTests = class
  private
    FReader: IBuildEvidenceReader;
  public
    [Setup]
    procedure Setup;

    /// <summary>
    /// Scalar metadata and normalized path fields must be copied to TBuildEvidence.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_MapsScalarFields;

    /// <summary>
    /// Lists and warnings must be copied without duplication.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_CopiesListsAndWarnings;

    /// <summary>
    /// The reader must emit project metadata evidence items.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_CreatesEvidenceItems;

    /// <summary>
    /// A present detailed map file must become map-file evidence and unit evidence.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_WithMapFile_CreatesMapEvidenceItems;

    /// <summary>
    /// Missing MAP files must produce targeted warnings, including RSM guidance.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_MissingMapFile_AddsHelpfulWarnings;

    /// <summary>
    /// Compiler option files must enrich effective search paths and unit scopes.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_WithCompilerOptionFiles_ParsesEffectivePathsAndScopes;

    /// <summary>
    /// A MAP file that exists but contains no unit entries (non-detailed format)
    /// must emit an actionable warning guiding the user to enable detailed output.
    /// Regression for issue #15.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_NonDetailedMapFile_AddsGuidanceWarning;

    /// <summary>
    /// An Android map with no classic unit sections must not tell the user to
    /// set Map file to Detailed. The ARM format is not guessed. Issue #100.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_AndroidMap_UsesArmHintAndDoesNotGuess;

    /// <summary>
    /// Classic unit sections in an Android map are still read.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_AndroidMap_ClassicUnitsAreRead;

    /// <summary>
    /// An ARM/LLVM linker map yields its unit objects as map units and its
    /// archive members as native components, with no unknown-format warning.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_AndroidLldMap_ReadsUnitsAndNativeComponents;

    /// <summary>
    /// A Linux map with no classic unit sections names the unknown format
    /// and does not invent a Project Options path.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_LinuxMap_UnknownFormatDoesNotGuess;

    /// <summary>
    /// A missing Android map names Map file ARM, not the Windows Detailed path.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_MissingAndroidMap_UsesArmHint;

    /// <summary>
    /// The progress log line names the evidence item, not only a count.
    /// </summary>
    [Test]
    procedure BuildEvidenceItemLogLine_NamesWhatWasFound;
  end;

implementation

procedure TBuildEvidenceReaderTests.Setup;
begin
  FReader := TBuildEvidenceReader.Create;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_MapsScalarFields;
var
  LBuildEvidence: TBuildEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\Repo\src\DX.Comply.Engine.dproj';
    LProjectInfo.Platform := 'Win64';
    LProjectInfo.Configuration := 'Release';
    LProjectInfo.OutputDir := 'C:\Repo\build\Win64\Release';
    LProjectInfo.DcuOutputDir := 'C:\Repo\build\Win64\Release\dcu';
    LProjectInfo.DcpOutputDir := 'C:\Repo\build\Win64\Release\dcu';
    LProjectInfo.BplOutputDir := 'C:\Repo\build\Win64\Release';

    LBuildEvidence := FReader.Read(LProjectInfo);
    try
      Assert.AreEqual(LProjectInfo.ProjectPath, LBuildEvidence.ProjectPath,
        'ProjectPath must be copied into TBuildEvidence');
      Assert.AreEqual(LProjectInfo.Platform, LBuildEvidence.Platform,
        'Platform must be copied into TBuildEvidence');
      Assert.AreEqual(LProjectInfo.Configuration, LBuildEvidence.Configuration,
        'Configuration must be copied into TBuildEvidence');
      Assert.AreEqual(LProjectInfo.OutputDir, LBuildEvidence.Paths.OutputDir,
        'OutputDir must be copied into the build path set');
      Assert.AreEqual(LProjectInfo.DcuOutputDir, LBuildEvidence.Paths.DcuOutputDir,
        'DcuOutputDir must be copied into the build path set');
      Assert.AreEqual(LProjectInfo.DcpOutputDir, LBuildEvidence.Paths.DcpOutputDir,
        'DcpOutputDir must be copied into the build path set');
      Assert.AreEqual(LProjectInfo.BplOutputDir, LBuildEvidence.Paths.BplOutputDir,
        'BplOutputDir must be copied into the build path set');
    finally
      LBuildEvidence.Free;
    end;
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_CopiesListsAndWarnings;
var
  LBuildEvidence: TBuildEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.SearchPaths.Add('C:\Repo\src');
    LProjectInfo.SearchPaths.Add('C:\Repo\libs');
    LProjectInfo.UnitScopeNames.Add('System');
    LProjectInfo.UnitScopeNames.Add('Vcl');
    LProjectInfo.RuntimePackages.Add('rtl');
    LProjectInfo.RuntimePackages.Add('vcl');
    LProjectInfo.Warnings.Add('Synthetic warning');

    LBuildEvidence := FReader.Read(LProjectInfo);
    try
      Assert.AreEqual(NativeInt(2), NativeInt(LBuildEvidence.SearchPaths.Count),
        'SearchPaths must be copied to build evidence');
      Assert.AreEqual(NativeInt(2), NativeInt(LBuildEvidence.UnitScopeNames.Count),
        'UnitScopeNames must be copied to build evidence');
      Assert.AreEqual(NativeInt(2), NativeInt(LBuildEvidence.RuntimePackages.Count),
        'RuntimePackages must be copied to build evidence');
      Assert.AreEqual(NativeInt(1), NativeInt(LBuildEvidence.Warnings.Count),
        'Warnings must be copied to build evidence');
      Assert.AreEqual('Synthetic warning', LBuildEvidence.Warnings[0],
        'Warnings must preserve the original text');
    finally
      LBuildEvidence.Free;
    end;
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_CreatesEvidenceItems;
var
  LBuildEvidence: TBuildEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\Repo\src\DX.Comply.Engine.dproj';
    LProjectInfo.Platform := 'Win32';
    LProjectInfo.Configuration := 'Debug';
    LProjectInfo.OutputDir := 'C:\Repo\build\Win32\Debug';
    LProjectInfo.MapFilePath := 'C:\Repo\build\Win32\Debug\DX.Comply.Engine.map';
    LProjectInfo.RuntimePackages.Add('rtl');

    LBuildEvidence := FReader.Read(LProjectInfo);
    try
      Assert.IsTrue(LBuildEvidence.EvidenceItems.Count >= 3,
        'The reader must emit at least project metadata, output dir, and runtime package evidence items');
      Assert.AreEqual(besProjectMetadata, LBuildEvidence.EvidenceItems[0].SourceKind,
        'The first evidence item must be tagged as project metadata');
      Assert.AreEqual('Project metadata', LBuildEvidence.EvidenceItems[0].DisplayName,
        'The first evidence item must describe the project metadata source');
      Assert.AreEqual(LProjectInfo.MapFilePath, LBuildEvidence.Paths.MapFilePath,
        'MapFilePath must be copied into the build path set');
    finally
      LBuildEvidence.Free;
    end;
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_WithMapFile_CreatesMapEvidenceItems;
var
  LBuildEvidence: TBuildEvidence;
  LHasDetailedMapItem: Boolean;
  LHasEngineUnitItem: Boolean;
  LHasSysUtilsUnitItem: Boolean;
  LEvidenceItem: TBuildEvidenceItem;
  LMapFilePath: string;
  LProjectInfo: TProjectInfo;
begin
  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath,
      'Line numbers for DX.Comply.Engine(DX.Comply.Engine.pas) segment CODE' + sLineBreak +
      'Line numbers for System.SysUtils(System.SysUtils.pas) segment CODE',
      TEncoding.UTF8);

    LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.ProjectPath := 'C:\Repo\src\DX.Comply.Engine.dproj';
      LProjectInfo.Platform := 'Win32';
      LProjectInfo.Configuration := 'Debug';
      LProjectInfo.MapFilePath := LMapFilePath;

      LBuildEvidence := FReader.Read(LProjectInfo);
      try
        LHasDetailedMapItem := False;
        LHasEngineUnitItem := False;
        LHasSysUtilsUnitItem := False;

        for LEvidenceItem in LBuildEvidence.EvidenceItems do
        begin
          if (LEvidenceItem.SourceKind = besMapFile) and
             (LEvidenceItem.DisplayName = 'Map file') then
            LHasDetailedMapItem := True;

          if (LEvidenceItem.SourceKind = besMapFile) and
             (LEvidenceItem.UnitName = 'DX.Comply.Engine') then
            LHasEngineUnitItem := True;

          if (LEvidenceItem.SourceKind = besMapFile) and
             (LEvidenceItem.UnitName = 'System.SysUtils') then
            LHasSysUtilsUnitItem := True;
        end;

        Assert.IsTrue(LBuildEvidence.EvidenceItems.Count >= 4,
          'The reader must emit metadata, detailed map, and per-unit map evidence items');
        Assert.IsTrue(LHasDetailedMapItem,
          'A present map file must become besMapFile evidence');
        Assert.IsTrue(LHasEngineUnitItem,
          'The first unit extracted from the map file must become evidence');
        Assert.IsTrue(LHasSysUtilsUnitItem,
          'The second unit extracted from the map file must become evidence');
      finally
        LBuildEvidence.Free;
      end;
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_MissingMapFile_AddsHelpfulWarnings;
var
  LBuildEvidence: TBuildEvidence;
  LMapFilePath: string;
  LProjectInfo: TProjectInfo;
  LRsmFilePath: string;
begin
  LMapFilePath := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName + '.map');
  LRsmFilePath := ChangeFileExt(LMapFilePath, '.rsm');
  TFile.WriteAllText(LRsmFilePath, 'dummy-rsm', TEncoding.UTF8);
  try
    LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.ProjectDir := TPath.GetTempPath;
      LProjectInfo.MapFilePath := LMapFilePath;

      LBuildEvidence := FReader.Read(LProjectInfo);
      try
        Assert.AreEqual(NativeInt(2), NativeInt(LBuildEvidence.Warnings.Count),
          'Missing MAP files with a sibling RSM file must emit two targeted warnings');
        Assert.IsTrue(Pos('.map', LowerCase(LBuildEvidence.Warnings[0])) > 0,
          'The first warning must mention the missing MAP file');
        Assert.IsTrue(Pos('.rsm', LowerCase(LBuildEvidence.Warnings[1])) > 0,
          'The second warning must mention the sibling RSM file');
      finally
        LBuildEvidence.Free;
      end;
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LRsmFilePath) then
      TFile.Delete(LRsmFilePath);
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_WithCompilerOptionFiles_ParsesEffectivePathsAndScopes;
var
  LBuildEvidence: TBuildEvidence;
  LCfgFilePath: string;
  LEvidenceItem: TBuildEvidenceItem;
  LGlobalSourceRoot: string;
  LHasCfgEvidence: Boolean;
  LHasRspEvidence: Boolean;
  LProjectDir: string;
  LProjectInfo: TProjectInfo;
  LProjectPath: string;
  LProjectSearchPath: string;
  LRspFilePath: string;
  LRspSearchPath: string;
  LTempDir: string;
  LToolchainDebugPath: string;
  LToolchainRoot: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LProjectDir := TPath.Combine(LTempDir, 'project');
  LToolchainRoot := TPath.Combine(LTempDir, 'delphi');
  LProjectSearchPath := TPath.Combine(LProjectDir, 'cfg-units');
  LRspSearchPath := TPath.Combine(LProjectDir, 'rsp-units');
  LToolchainDebugPath := TPath.Combine(LToolchainRoot, 'lib\Win32\debug');
  LGlobalSourceRoot := TPath.Combine(LToolchainRoot, 'source');
  TDirectory.CreateDirectory(LProjectSearchPath);
  TDirectory.CreateDirectory(LRspSearchPath);
  TDirectory.CreateDirectory(LToolchainDebugPath);
  TDirectory.CreateDirectory(LGlobalSourceRoot);
  try
    LProjectPath := TPath.Combine(LProjectDir, 'Demo.dproj');
    LCfgFilePath := ChangeFileExt(LProjectPath, '.cfg');
    LRspFilePath := TPath.Combine(LProjectDir, 'Demo.rsp');

    TFile.WriteAllText(LCfgFilePath,
      '-U".\cfg-units" @".\Demo.rsp"', TEncoding.UTF8);
    TFile.WriteAllText(LRspFilePath,
      '-U".\rsp-units"' + sLineBreak +
      '-U"$(BDSLIB)\Win32\debug"' + sLineBreak +
      '-NS"System;Vcl"', TEncoding.UTF8);

    LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.ProjectName := 'Demo';
      LProjectInfo.ProjectPath := LProjectPath;
      LProjectInfo.ProjectDir := LProjectDir;
      LProjectInfo.Platform := 'Win32';
      LProjectInfo.Configuration := 'Debug';
      LProjectInfo.Toolchain.RootDir := LToolchainRoot;
      LProjectInfo.ProjectSearchPaths.Add(TPath.Combine(LProjectDir, 'src'));
      LProjectInfo.GlobalSearchPaths.Add(LGlobalSourceRoot);

      LBuildEvidence := FReader.Read(LProjectInfo);
      try
        Assert.IsTrue(LBuildEvidence.SearchPaths.Contains(LProjectSearchPath),
          'Project CFG files must contribute effective compiler search paths');
        Assert.IsTrue(LBuildEvidence.SearchPaths.Contains(LRspSearchPath),
          'Nested response files must contribute effective compiler search paths');
        Assert.IsTrue(LBuildEvidence.SearchPaths.Contains(LToolchainDebugPath),
          'Compiler option macros such as $(BDSLIB) must resolve into effective search paths');
        Assert.IsTrue(LBuildEvidence.UnitScopeNames.Contains('System'),
          'Compiler option files must contribute resolved unit scope names');
        Assert.IsTrue(LBuildEvidence.UnitScopeNames.Contains('Vcl'),
          'Multiple unit scopes from compiler option files must be preserved');
        Assert.IsTrue(LBuildEvidence.SearchPaths.IndexOf(LToolchainDebugPath) <
          LBuildEvidence.SearchPaths.IndexOf(LGlobalSourceRoot),
          'Compiler-derived DCU paths must be searched before global source fallbacks');

        LHasCfgEvidence := False;
        LHasRspEvidence := False;
        for LEvidenceItem in LBuildEvidence.EvidenceItems do
        begin
          if (LEvidenceItem.SourceKind = besCompilerResponseFile) and
             SameText(LEvidenceItem.FilePath, LCfgFilePath) then
            LHasCfgEvidence := True;
          if (LEvidenceItem.SourceKind = besCompilerResponseFile) and
             SameText(LEvidenceItem.FilePath, LRspFilePath) then
            LHasRspEvidence := True;
        end;

        Assert.IsTrue(LHasCfgEvidence,
          'The project CFG file must be surfaced as compiler option evidence');
        Assert.IsTrue(LHasRspEvidence,
          'Nested response files must be surfaced as compiler option evidence');
      finally
        LBuildEvidence.Free;
      end;
    finally
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_NonDetailedMapFile_AddsGuidanceWarning;
var
  LBuildEvidence: TBuildEvidence;
  LMapFilePath: string;
  LProjectInfo: TProjectInfo;
  LWarning: string;
  LHasGuidanceWarning: Boolean;
begin
  // Write a segment-only MAP (no "Line numbers for" section) — this is what
  // Delphi generates when DCC_MapFile is NOT set to 3 (Detailed).
  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath,
      ' Start         Length     Name                   Class' + sLineBreak +
      '  0001:00000000 000067FCH .text                  CODE' + sLineBreak +
      '  0002:00000000 00000000H .itext                 ICODE',
      TEncoding.UTF8);

    LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.ProjectPath := 'C:\Repo\src\MyApp.dproj';
      LProjectInfo.Platform := 'Win32';
      LProjectInfo.Configuration := 'Release';
      LProjectInfo.MapFilePath := LMapFilePath;

      LBuildEvidence := FReader.Read(LProjectInfo);
      try
        LHasGuidanceWarning := False;
        for LWarning in LBuildEvidence.Warnings do
        begin
          if (Pos('no unit information', LowerCase(LWarning)) > 0) or
             (Pos('DCC_MapFile=3', LWarning) > 0) then
          begin
            LHasGuidanceWarning := True;
            Break;
          end;
        end;

        Assert.IsTrue(LHasGuidanceWarning,
          'A non-detailed MAP file must produce an actionable warning with DCC_MapFile=3 guidance (regression #15)');
        Assert.IsTrue(Pos('Map file > Detailed', LBuildEvidence.Warnings[0]) > 0,
          'Win32 guidance must keep the Detailed map path');
      finally
        LBuildEvidence.Free;
      end;
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_AndroidMap_UsesArmHintAndDoesNotGuess;
var
  LBuildEvidence: TBuildEvidence;
  LMapFilePath: string;
  LProjectInfo: TProjectInfo;
  LWarning: string;
begin
  // Neither a classic segment map nor an LLVM linker map has the unit
  // sections the reader understands. The warning must not invent units.
  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath,
      'Linker script and memory map' + sLineBreak +
      '.text           0x0000000000010000' + sLineBreak +
      ' .text.Unit1    0x0000000000010000       Unit1.o' + sLineBreak +
      '                0x0000000000010000       Unit1.Initialize' + sLineBreak,
      TEncoding.UTF8);

    LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.ProjectPath := 'C:\Softwareprojekte\AndroidApp\Source\AndroidApp.dproj';
      LProjectInfo.Platform := 'Android64';
      LProjectInfo.Configuration := 'Release';
      LProjectInfo.MapFilePath := LMapFilePath;

      LBuildEvidence := FReader.Read(LProjectInfo);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LBuildEvidence.Warnings.Count),
          'An unreadable Android map must produce one warning');
        LWarning := LBuildEvidence.Warnings[0];
        Assert.IsTrue(Pos('Map file ARM', LWarning) > 0, LWarning);
        Assert.IsTrue(Pos('> On', LWarning) > 0, LWarning);
        Assert.IsTrue(Pos('no "Detailed" map setting', LWarning) > 0, LWarning);
        Assert.IsTrue(Pos('did not guess', LWarning) > 0, LWarning);
        Assert.IsTrue(Pos('DCC_MapFile=3', LWarning) = 0, LWarning);
        Assert.IsTrue(Pos('Map file > Detailed', LWarning) = 0, LWarning);
        Assert.IsTrue(Pos('Unit1', LWarning) = 0,
          'The warning must not treat an LLVM symbol as a unit');
      finally
        LBuildEvidence.Free;
      end;
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_AndroidMap_ClassicUnitsAreRead;
var
  LBuildEvidence: TBuildEvidence;
  LEvidenceItem: TBuildEvidenceItem;
  LHasUnit: Boolean;
  LMapFilePath: string;
  LProjectInfo: TProjectInfo;
  LWarning: string;
begin
  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath,
      'Line numbers for Androidapi.Jni(Androidapi.Jni.pas) segment .text' + sLineBreak +
      '  10 0001:00000000' + sLineBreak,
      TEncoding.UTF8);

    LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.Platform := 'Android32';
      LProjectInfo.MapFilePath := LMapFilePath;
      LBuildEvidence := FReader.Read(LProjectInfo);
      try
        LHasUnit := False;
        for LEvidenceItem in LBuildEvidence.EvidenceItems do
          if SameText(LEvidenceItem.UnitName, 'Androidapi.Jni') then
            LHasUnit := True;
        Assert.IsTrue(LHasUnit,
          'Classic unit sections in an Android map must still be read');
        for LWarning in LBuildEvidence.Warnings do
          Assert.IsTrue(Pos('did not guess', LWarning) = 0,
            'A map that yielded units must not warn that the format is unknown: ' + LWarning);
      finally
        LBuildEvidence.Free;
      end;
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_AndroidLldMap_ReadsUnitsAndNativeComponents;
begin
  var LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath,
      '             VMA              LMA     Size Align Out     In      Symbol' + sLineBreak +
      '             2d0              2d0       24     4         <internal>:(.note.gnu.build-id)' + sLineBreak +
      '          dbeef8           dbeef8       38     4         c:\\lib\\Android64\\Release\\SysInit.o:' +
      '(.gcc_except_table)' + sLineBreak +
      '         184e348          184e348        4     4         .\\Compiled\\Cipher_FMX.o:(.text._NativeMain)' +
      sLineBreak +
      '         184e348          184e348        4     1                 Cipher_fmx::Finalization()' + sLineBreak +
      '         184e42c          184e42c       c8     4         c:\\lib\\Android64\\Release/libunwind.a' +
      '(UnwindLevel1.o):(.text._Unwind_RaiseException)' + sLineBreak +
      '          dbef30           dbef30     16f8     4         c:\\lib\\Android64\\Release\\SysInit.o:' +
      '(.text)' + sLineBreak,
      TEncoding.UTF8);

    var LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.Platform := 'Android64';
      LProjectInfo.MapFilePath := LMapFilePath;
      var LBuildEvidence := FReader.Read(LProjectInfo);
      try
        var LUnits := '';
        var LNative := '';
        for var LEvidenceItem in LBuildEvidence.EvidenceItems do
        begin
          if LEvidenceItem.UnitName <> '' then
            LUnits := LUnits + LEvidenceItem.UnitName + ',';
          if LEvidenceItem.DisplayName = 'Native component from map file' then
            LNative := LNative + LEvidenceItem.PackageName + ',';
        end;
        Assert.AreEqual('SysInit,Cipher_FMX,', LUnits);
        Assert.AreEqual('libunwind.a,', LNative);
        Assert.AreEqual(NativeInt(0), NativeInt(LBuildEvidence.Warnings.Count),
          'A readable LLVM map must not warn about an unknown format');
      finally
        LBuildEvidence.Free;
      end;
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_LinuxMap_UnknownFormatDoesNotGuess;
var
  LBuildEvidence: TBuildEvidence;
  LMapFilePath: string;
  LProjectInfo: TProjectInfo;
  LWarning: string;
begin
  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath,
      ' Start         Length     Name                   Class' + sLineBreak +
      '  0001:00000000 000067FCH .text                  CODE' + sLineBreak,
      TEncoding.UTF8);

    LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.Platform := 'Linux64';
      LProjectInfo.MapFilePath := LMapFilePath;
      LBuildEvidence := FReader.Read(LProjectInfo);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LBuildEvidence.Warnings.Count));
        LWarning := LBuildEvidence.Warnings[0];
        Assert.IsTrue(Pos('Linux map format', LWarning) > 0, LWarning);
        Assert.IsTrue(Pos('did not guess', LWarning) > 0, LWarning);
        Assert.IsTrue(Pos('Map file > Detailed', LWarning) = 0, LWarning);
        Assert.IsTrue(Pos('Map file ARM', LWarning) = 0, LWarning);
        Assert.IsTrue(Pos('DCC_MapFile=3', LWarning) = 0, LWarning);
      finally
        LBuildEvidence.Free;
      end;
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_MissingAndroidMap_UsesArmHint;
var
  LBuildEvidence: TBuildEvidence;
  LMapFilePath: string;
  LProjectInfo: TProjectInfo;
  LWarning: string;
begin
  LMapFilePath := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName + '.map');
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.Platform := 'Android64';
    LProjectInfo.MapFilePath := LMapFilePath;
    LBuildEvidence := FReader.Read(LProjectInfo);
    try
      Assert.IsTrue(LBuildEvidence.Warnings.Count >= 1);
      LWarning := LBuildEvidence.Warnings[0];
      Assert.IsTrue(Pos('Map file ARM', LWarning) > 0, LWarning);
      Assert.IsTrue(Pos('Map file > Detailed', LWarning) = 0, LWarning);
    finally
      LBuildEvidence.Free;
    end;
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildEvidenceReaderTests.BuildEvidenceItemLogLine_NamesWhatWasFound;
var
  LItem: TBuildEvidenceItem;
begin
  LItem := Default(TBuildEvidenceItem);
  LItem.DisplayName := 'Expected map file';
  LItem.FilePath := 'C:\Softwareprojekte\AndroidApp\Source\Android64\Release\libAndroidApp.so.map';
  LItem.Detail := 'MapFilePath';
  Assert.AreEqual(
    'Expected map file - C:\Softwareprojekte\AndroidApp\Source\Android64\Release\libAndroidApp.so.map [MapFilePath]',
    BuildEvidenceItemLogLine(LItem));

  LItem := Default(TBuildEvidenceItem);
  LItem.DisplayName := 'Unit from map file';
  LItem.UnitName := 'System.SysUtils';
  LItem.FilePath := 'C:\Build\App.map';
  LItem.Detail := 'LineNumbersSection';
  Assert.IsTrue(Pos('System.SysUtils', BuildEvidenceItemLogLine(LItem)) > 0);
  Assert.IsTrue(Pos('App.map', BuildEvidenceItemLogLine(LItem)) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildEvidenceReaderTests);

end.