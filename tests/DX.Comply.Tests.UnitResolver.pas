/// <summary>
/// DX.Comply.Tests.UnitResolver
/// DUnitX tests for TUnitResolver.
/// </summary>
///
/// <remarks>
/// Verifies the first-pass resolver envelope before real unit-closure logic is
/// added in later slices.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.UnitResolver;

interface

uses
  System.IOUtils,
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.HashService,
  DX.Comply.UnitResolver;

type
  /// <summary>
  /// DUnitX fixture for the first-pass unit resolver.
  /// </summary>
  [TestFixture]
  TUnitResolverTests = class
  private
    FResolver: IUnitResolver;
  public
    [Setup]
    procedure Setup;

    /// <summary>
    /// Project metadata must be mapped into the composition evidence envelope.
    /// </summary>
    [Test]
    procedure Resolve_MapsProjectMetadata;

    /// <summary>
    /// Project and build evidence warnings must be merged uniquely.
    /// </summary>
    [Test]
    procedure Resolve_MergesWarningsUniquely;

    /// <summary>
    /// Without MAP-derived evidence there must not be any resolved units.
    /// </summary>
    [Test]
    procedure Resolve_WithoutMapEvidence_ReturnsNoUnits;

    /// <summary>
    /// Map-file evidence items must become first resolved units.
    /// </summary>
    [Test]
    procedure Resolve_WithMapEvidence_CreatesResolvedUnits;

    /// <summary>
    /// Explicit project references must resolve local units authoritatively.
    /// </summary>
    [Test]
    procedure Resolve_WithExplicitProjectUnitReference_ResolvesLocalUnit;

    /// <summary>
    /// Effective compiler search paths from option files must beat source fallbacks.
    /// </summary>
    [Test]
    procedure Resolve_WithCompilerOptionSearchPath_PrefersDcuEvidence;

    /// <summary>
    /// Global toolchain DCU paths must win over Delphi source fallbacks.
    /// </summary>
    [Test]
    procedure Resolve_WithGlobalToolchainDcuPath_PrefersDcuEvidence;

    /// <summary>
    /// Global toolchain roots must classify standard Delphi units as Embarcadero RTL.
    /// </summary>
    [Test]
    procedure Resolve_WithGlobalToolchainSourcePath_ClassifiesEmbarcaderoRtl;

    /// <summary>
    /// Resolved units with existing files must receive SHA-256 and SHA-512 hashes.
    /// </summary>
    [Test]
    procedure Resolve_WithHashService_ComputesHashesForResolvedFiles;

    /// <summary>
    /// Unresolved units (no file on disk) must not receive hashes.
    /// </summary>
    [Test]
    procedure Resolve_UnresolvedUnit_HasEmptyHashes;
  end;

implementation

procedure TUnitResolverTests.Setup;
begin
  FResolver := TUnitResolver.Create;
end;

procedure TUnitResolverTests.Resolve_MapsProjectMetadata;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  LBuildEvidence := TBuildEvidence.Create;
  try
    LProjectInfo.ProjectName := 'DX.Comply';
    LProjectInfo.Version := '1.2.3.4';
    LProjectInfo.Platform := 'Win64';
    LProjectInfo.Configuration := 'Release';
    LProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
    LProjectInfo.Toolchain.Version := '37.0';
    LProjectInfo.Toolchain.BuildVersion := '37.0.57242.3601';

    LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
    try
      Assert.AreEqual('DX.Comply', LCompositionEvidence.ProjectName,
        'ProjectName must be copied into the composition evidence envelope');
      Assert.AreEqual('1.2.3.4', LCompositionEvidence.ProjectVersion,
        'ProjectVersion must be copied into the composition evidence envelope');
      Assert.AreEqual('Win64', LCompositionEvidence.Platform,
        'Platform must be copied into the composition evidence envelope');
      Assert.AreEqual('Release', LCompositionEvidence.Configuration,
        'Configuration must be copied into the composition evidence envelope');
      Assert.AreEqual('37.0', LCompositionEvidence.ToolchainVersion,
        'ToolchainVersion must be copied into the composition evidence envelope');
      Assert.AreEqual('37.0.57242.3601', LCompositionEvidence.ToolchainBuildVersion,
        'ToolchainBuildVersion must be copied into the composition evidence envelope');
      Assert.IsTrue(LCompositionEvidence.GeneratedAt <> '',
        'GeneratedAt must be populated by the resolver');
    finally
      LCompositionEvidence.Free;
    end;
  finally
    LBuildEvidence.Free;
    LProjectInfo.Free;
  end;
end;

procedure TUnitResolverTests.Resolve_MergesWarningsUniquely;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  LBuildEvidence := TBuildEvidence.Create;
  try
    LProjectInfo.Warnings.Add('Shared warning');
    LProjectInfo.Warnings.Add('Project warning');
    LBuildEvidence.Warnings.Add('Shared warning');
    LBuildEvidence.Warnings.Add('Build warning');

    LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
    try
      Assert.AreEqual(NativeInt(3), NativeInt(LCompositionEvidence.Warnings.Count),
        'Warnings from project and build evidence must be merged without duplicates');
      Assert.IsTrue(LCompositionEvidence.Warnings.Contains('Project warning'),
        'Project warnings must be preserved');
      Assert.IsTrue(LCompositionEvidence.Warnings.Contains('Build warning'),
        'Build evidence warnings must be preserved');
    finally
      LCompositionEvidence.Free;
    end;
  finally
    LBuildEvidence.Free;
    LProjectInfo.Free;
  end;
end;

procedure TUnitResolverTests.Resolve_WithoutMapEvidence_ReturnsNoUnits;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  LBuildEvidence := TBuildEvidence.Create;
  try
    LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
    try
      Assert.AreEqual(NativeInt(0), NativeInt(LCompositionEvidence.Units.Count),
        'Resolver must not invent units when no MAP-derived evidence is present');
    finally
      LCompositionEvidence.Free;
    end;
  finally
    LBuildEvidence.Free;
    LProjectInfo.Free;
  end;
end;

procedure TUnitResolverTests.Resolve_WithMapEvidence_CreatesResolvedUnits;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  LBuildEvidence := TBuildEvidence.Create;
  try
    LBuildEvidence.Paths.MapFilePath := 'C:\Repo\build\Win32\Debug\DX.Comply.Engine.map';

    LEvidenceItem := Default(TBuildEvidenceItem);
    LEvidenceItem.SourceKind := besMapFile;
    LEvidenceItem.FilePath := LBuildEvidence.Paths.MapFilePath;
    LEvidenceItem.UnitName := 'DX.Comply.Engine';
    LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

    LEvidenceItem.UnitName := 'System.SysUtils';
    LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

    LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
    try
      Assert.AreEqual(NativeInt(2), NativeInt(LCompositionEvidence.Units.Count),
        'Map-file evidence items must be transformed into resolved units');
      Assert.AreEqual('DX.Comply.Engine', LCompositionEvidence.Units[0].UnitName,
        'The first resolved unit must come from the first map evidence item');
      Assert.AreEqual(rcHeuristic, LCompositionEvidence.Units[0].Confidence,
        'Unresolved MAP-only units should produce heuristic confidence');
      Assert.AreEqual(uekMap, LCompositionEvidence.Units[0].EvidenceKind,
        'Unresolved MAP-only units must have MAP evidence kind');
      Assert.AreEqual(besMapFile, LCompositionEvidence.Units[0].EvidenceSources[0],
        'Resolved units created from map evidence must retain besMapFile as their source');
    finally
      LCompositionEvidence.Free;
    end;
  finally
    LBuildEvidence.Free;
    LProjectInfo.Free;
  end;
end;

procedure TUnitResolverTests.Resolve_WithExplicitProjectUnitReference_ResolvesLocalUnit;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
  LReference: TProjectUnitReference;
  LTempDir: string;
  LUnitPath: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  TDirectory.CreateDirectory(LTempDir);
  try
    LUnitPath := TPath.Combine(LTempDir, 'Demo.Main.pas');
    TFile.WriteAllText(LUnitPath, 'unit Demo.Main;' + sLineBreak + 'interface' + sLineBreak + 'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectDir := LTempDir;
      LReference.UnitName := 'Demo.Main';
      LReference.FilePath := LUnitPath;
      LReference.Source := 'MainSource';
      LProjectInfo.ExplicitUnitReferences.Add(LReference);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LTempDir, 'Demo.map');
      LEvidenceItem.UnitName := 'Demo.Main';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.AreEqual(LUnitPath, LCompositionEvidence.Units[0].ResolvedPath,
          'Explicit project references must win over search path heuristics');
        Assert.AreEqual(uokLocalProject, LCompositionEvidence.Units[0].OriginKind,
          'Explicitly referenced local units must be classified as local project code');
        Assert.AreEqual(uekPas, LCompositionEvidence.Units[0].EvidenceKind,
          'A PAS file reference must resolve to PAS evidence');
        Assert.AreEqual(rcAuthoritative, LCompositionEvidence.Units[0].Confidence,
          'Explicit project references must be treated as authoritative evidence');
      finally
        LCompositionEvidence.Free;
      end;
    finally
      LBuildEvidence.Free;
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TUnitResolverTests.Resolve_WithCompilerOptionSearchPath_PrefersDcuEvidence;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LLibDebugRoot: string;
  LProjectInfo: TProjectInfo;
  LSourceRoot: string;
  LTempDir: string;
  LUnitDcuPath: string;
  LUnitSourcePath: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LLibDebugRoot := TPath.Combine(LTempDir, 'lib\Win32\debug');
  LSourceRoot := TPath.Combine(LTempDir, 'source');
  TDirectory.CreateDirectory(LLibDebugRoot);
  TDirectory.CreateDirectory(TPath.Combine(LSourceRoot, 'rtl\sys'));
  try
    LUnitDcuPath := TPath.Combine(LLibDebugRoot, 'System.SysUtils.dcu');
    TFile.WriteAllBytes(LUnitDcuPath, TBytes.Create($01, $02, $03, $04));

    LUnitSourcePath := TPath.Combine(LSourceRoot, 'rtl\sys\System.SysUtils.pas');
    TFile.WriteAllText(LUnitSourcePath,
      'unit System.SysUtils;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
      LProjectInfo.Toolchain.RootDir := LTempDir;
      LProjectInfo.Toolchain.Version := '37.0';
      LProjectInfo.GlobalSearchPaths.Add(LSourceRoot);
      LBuildEvidence.SearchPaths.Add(LLibDebugRoot);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LTempDir, 'Demo.map');
      LEvidenceItem.UnitName := 'System.SysUtils';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.AreEqual(LUnitDcuPath, LCompositionEvidence.Units[0].ResolvedPath,
          'Effective compiler search paths must be preferred over recursive source fallbacks');
        Assert.AreEqual(uekDcu, LCompositionEvidence.Units[0].EvidenceKind,
          'Compiler-derived search path hits for RTL units must resolve as DCU evidence');
      finally
        LCompositionEvidence.Free;
      end;
    finally
      LBuildEvidence.Free;
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TUnitResolverTests.Resolve_WithGlobalToolchainDcuPath_PrefersDcuEvidence;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LEvidenceItem: TBuildEvidenceItem;
  LLibDebugRoot: string;
  LProjectInfo: TProjectInfo;
  LSourceRoot: string;
  LTempDir: string;
  LUnitDcuPath: string;
  LUnitSourcePath: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LLibDebugRoot := TPath.Combine(LTempDir, 'lib\Win32\debug');
  LSourceRoot := TPath.Combine(LTempDir, 'source');
  TDirectory.CreateDirectory(LLibDebugRoot);
  TDirectory.CreateDirectory(TPath.Combine(LSourceRoot, 'rtl\sys'));
  try
    LUnitDcuPath := TPath.Combine(LLibDebugRoot, 'System.SysUtils.dcu');
    TFile.WriteAllBytes(LUnitDcuPath, TBytes.Create($01, $02, $03, $04));

    LUnitSourcePath := TPath.Combine(LSourceRoot, 'rtl\sys\System.SysUtils.pas');
    TFile.WriteAllText(LUnitSourcePath,
      'unit System.SysUtils;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
      LProjectInfo.Toolchain.RootDir := LTempDir;
      LProjectInfo.Toolchain.Version := '37.0';
      LProjectInfo.UsesDebugDCUs := True;
      LProjectInfo.GlobalSearchPaths.Add(LLibDebugRoot);
      LProjectInfo.GlobalSearchPaths.Add(LSourceRoot);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LTempDir, 'Demo.map');
      LEvidenceItem.UnitName := 'System.SysUtils';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.AreEqual(LUnitDcuPath, LCompositionEvidence.Units[0].ResolvedPath,
          'Toolchain DCU folders must be preferred over Delphi source fallbacks');
        Assert.AreEqual(uekDcu, LCompositionEvidence.Units[0].EvidenceKind,
          'A resolved RTL DCU must be classified as DCU evidence');
        Assert.AreEqual(uokEmbarcaderoRtl, LCompositionEvidence.Units[0].OriginKind,
          'Toolchain DCU hits below the Delphi root must remain classified as Embarcadero RTL');
      finally
        LCompositionEvidence.Free;
      end;
    finally
      LBuildEvidence.Free;
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TUnitResolverTests.Resolve_WithGlobalToolchainSourcePath_ClassifiesEmbarcaderoRtl;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
  LSourceRoot: string;
  LTempDir: string;
  LUnitPath: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LSourceRoot := TPath.Combine(LTempDir, 'source');
  TDirectory.CreateDirectory(TPath.Combine(LSourceRoot, 'rtl\sys'));
  try
    LUnitPath := TPath.Combine(LSourceRoot, 'rtl\sys\System.SysUtils.pas');
    TFile.WriteAllText(LUnitPath, 'unit System.SysUtils;' + sLineBreak + 'interface' + sLineBreak + 'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
      LProjectInfo.Toolchain.RootDir := LTempDir;
      LProjectInfo.Toolchain.Version := '37.0';
      LProjectInfo.GlobalSearchPaths.Add(LSourceRoot);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LTempDir, 'Demo.map');
      LEvidenceItem.UnitName := 'System.SysUtils';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.AreEqual(LUnitPath, LCompositionEvidence.Units[0].ResolvedPath,
          'Standard Delphi units must resolve from the global toolchain search roots');
        Assert.AreEqual(uokEmbarcaderoRtl, LCompositionEvidence.Units[0].OriginKind,
          'Resolved System.* units below the Delphi root must be classified as Embarcadero RTL');
        Assert.AreEqual(uekPas, LCompositionEvidence.Units[0].EvidenceKind,
          'Toolchain source hits must resolve as PAS evidence');
      finally
        LCompositionEvidence.Free;
      end;
    finally
      LBuildEvidence.Free;
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TUnitResolverTests.Resolve_WithHashService_ComputesHashesForResolvedFiles;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LHashService: IHashService;
  LProjectInfo: TProjectInfo;
  LResolver: IUnitResolver;
  LTempDir: string;
  LUnitPath: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  TDirectory.CreateDirectory(LTempDir);
  try
    LUnitPath := TPath.Combine(LTempDir, 'Demo.Main.pas');
    TFile.WriteAllText(LUnitPath, 'unit Demo.Main; interface implementation end.');

    LHashService := THashService.Create;
    LResolver := TUnitResolver.Create(LHashService);

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
    var LReference: TProjectUnitReference;
      LProjectInfo.ProjectDir := LTempDir;
      LReference.UnitName := 'Demo.Main';
      LReference.FilePath := LUnitPath;
      LReference.Source := 'MainSource';
      LProjectInfo.ExplicitUnitReferences.Add(LReference);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LTempDir, 'Demo.map');
      LEvidenceItem.UnitName := 'Demo.Main';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := LResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.IsTrue(LCompositionEvidence.Units[0].SecondaryHashSha256 <> '',
          'Resolved units with existing files must have a SHA-256 hash');
        Assert.IsTrue(LCompositionEvidence.Units[0].PrimaryHashSha512 <> '',
          'Resolved units with existing files must have a SHA-512 hash');
        Assert.AreEqual(NativeInt(64),
          NativeInt(Length(LCompositionEvidence.Units[0].SecondaryHashSha256)),
          'SHA-256 hash must be 64 hex characters');
        Assert.AreEqual(NativeInt(128),
          NativeInt(Length(LCompositionEvidence.Units[0].PrimaryHashSha512)),
          'SHA-512 hash must be 128 hex characters');
      finally
        LCompositionEvidence.Free;
      end;
    finally
      LBuildEvidence.Free;
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TUnitResolverTests.Resolve_UnresolvedUnit_HasEmptyHashes;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LHashService: IHashService;
  LProjectInfo: TProjectInfo;
  LResolver: IUnitResolver;
begin
  LHashService := THashService.Create;
  LResolver := TUnitResolver.Create(LHashService);

  LProjectInfo := TProjectInfo.Create;
  LBuildEvidence := TBuildEvidence.Create;
  try
    LEvidenceItem := Default(TBuildEvidenceItem);
    LEvidenceItem.SourceKind := besMapFile;
    LEvidenceItem.FilePath := 'C:\nonexistent\Demo.map';
    LEvidenceItem.UnitName := 'Nonexistent.Unit';
    LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

    LCompositionEvidence := LResolver.Resolve(LProjectInfo, LBuildEvidence);
    try
      Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
      Assert.AreEqual('', LCompositionEvidence.Units[0].SecondaryHashSha256,
        'Unresolved units must not have a SHA-256 hash');
      Assert.AreEqual('', LCompositionEvidence.Units[0].PrimaryHashSha512,
        'Unresolved units must not have a SHA-512 hash');
    finally
      LCompositionEvidence.Free;
    end;
  finally
    LBuildEvidence.Free;
    LProjectInfo.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitResolverTests);

end.