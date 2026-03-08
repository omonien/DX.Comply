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
             (LEvidenceItem.DisplayName = 'Detailed map file') then
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

initialization
  TDUnitX.RegisterTestFixture(TBuildEvidenceReaderTests);

end.