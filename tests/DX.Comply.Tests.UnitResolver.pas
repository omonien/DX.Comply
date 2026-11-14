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

    /// <summary>
    /// LLVM platforms without MAP evidence must discover units via uses-clause analysis.
    /// </summary>
    [Test]
    procedure Resolve_LlvmPlatform_UsesClauseFallback;

    /// <summary>
    /// Classic platforms without MAP evidence must also fall back to uses-clause analysis.
    /// </summary>
    [Test]
    procedure Resolve_ClassicPlatformNoMap_UsesClauseFallback;

    /// <summary>
    /// Classic platforms with MAP evidence must not invoke uses-clause fallback.
    /// </summary>
    [Test]
    procedure Resolve_ClassicPlatformWithMap_NoUsesClauseFallback;

    /// <summary>
    /// IsClassicCompilerPlatform must return True only for Win32 and Win64.
    /// </summary>
    [Test]
    procedure IsClassicCompilerPlatform_ClassifiesCorrectly;

    /// <summary>
    /// A unit whose resolved path lies in a sibling directory that is
    /// explicitly listed in the project search paths must be classified as
    /// Local project, not Third party (regression #22).
    /// </summary>
    [Test]
    procedure Resolve_SiblingDirectoryInSearchPaths_ClassifiesAsLocalProject;

    /// <summary>
    /// A unit resolved from a path that is NOT in the project search paths
    /// and NOT under the project directory must remain Third party.
    /// </summary>
    [Test]
    procedure Resolve_UnitOutsideSearchPaths_ClassifiesAsThirdParty;

    /// <summary>
    /// A library installed into a folder below the Delphi root that
    /// Embarcadero does not ship (Extras\madExcept) is Third party, not
    /// Embarcadero RTL (issue #134).
    /// </summary>
    [Test]
    procedure Resolve_LibraryInDelphiExtrasFolder_ClassifiesAsThirdParty;
    /// <summary>A project search path inside the Delphi folder is not project code. Issue #133.</summary>
    [Test]
    procedure Resolve_ProjectSearchPathBelowDelphiRoot_ClassifiesAsThirdParty;
    /// <summary>A DCU in the DCU output folder takes the origin of its source. Issue #133.</summary>
    [Test]
    procedure Resolve_DcuInOutputDir_UsesOriginOfSource;

    /// <summary>
    /// A unit under the install Extras folder that a manifest row names
    /// (units_exact, units_folder, or units_prefix) is that component.
    /// </summary>
    [Test]
    procedure Resolve_ExtrasDecWithManifest_MatchesComponent;
    /// <summary>
    /// The same Extras unit with no manifest row is third party.
    /// </summary>
    [Test]
    procedure Resolve_ExtrasDecWithoutManifest_ClassifiesAsThirdParty;
    /// <summary>
    /// Product source trees stay Embarcadero: source\rtl, source\vcl,
    /// source\fmx, and source\data.
    /// </summary>
    [Test]
    procedure Resolve_ProductSourceFolders_StayEmbarcadero;
    /// <summary>A GetIt catalog repository under the install is third party.</summary>
    [Test]
    procedure Resolve_CatalogRepositoryUnderInstall_ClassifiesAsThirdParty;
    /// <summary>
    /// The default GetIt catalog repository, under Documents, is third party.
    /// </summary>
    [Test]
    procedure Resolve_CatalogRepositoryUnderDocuments_ClassifiesAsThirdParty;
    /// <summary>
    /// A DCU in a product lib folder stays Embarcadero when the only match
    /// is a units_prefix. units_exact still wins over that location.
    /// </summary>
    [Test]
    procedure Resolve_ProductLibDcuWithManifest_MatchesComponent;
    /// <summary>
    /// Winapi.GDIP* and Vcl.HtmlHelpViewer stay Embarcadero when a short
    /// prefix would otherwise claim them. Issue #176.
    /// </summary>
    [Test]
    procedure Resolve_ShortPrefix_KeepsProductUnitsEmbarcadero;
    /// <summary>A folder added under source or lib is third party.</summary>
    [Test]
    procedure Resolve_UserFoldersUnderInstall_ClassifyAsThirdParty;
    /// <summary>
    /// A unit under the Delphi install with no manifest row is third party
    /// and is named on the Unknown supplier row. A manifest library keeps
    /// its supplier. Own-code units stay off that row. A unit under
    /// source\rtl stays Embarcadero.
    /// </summary>
    [Test]
    procedure Resolve_UnmatchedInstallUnit_IsNamedUnknownSupplier;
  end;

implementation

uses
  DX.Comply.ComponentManifest,
  DX.Comply.CraChecks,
  DX.Comply.Engine,
  DX.Comply.Report.Intf,
  DX.Comply.Report.Overview,
  DX.Comply.Report.Support;

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

procedure TUnitResolverTests.Resolve_LlvmPlatform_UsesClauseFallback;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
  LTempDir: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyResolverLlvm_' + TPath.GetRandomFileName);
  TDirectory.CreateDirectory(LTempDir);
  try
    TFile.WriteAllText(TPath.Combine(LTempDir, 'MyApp.dpr'),
      'program MyApp;' + sLineBreak +
      'uses' + sLineBreak +
      '  HelperUnit;' + sLineBreak +
      'begin' + sLineBreak +
      'end.');
    TFile.WriteAllText(TPath.Combine(LTempDir, 'HelperUnit.pas'),
      'unit HelperUnit;' + sLineBreak +
      'interface' + sLineBreak +
      'implementation' + sLineBreak +
      'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectPath := TPath.Combine(LTempDir, 'MyApp.dproj');
      LProjectInfo.ProjectDir := LTempDir;
      LProjectInfo.Platform := 'iOSDevice64';
      LProjectInfo.Configuration := 'Release';
      LBuildEvidence.SearchPaths.Add(LTempDir);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.IsTrue(LCompositionEvidence.Units.Count > 0,
          'LLVM platform without MAP evidence must discover units via uses-clause analysis');
        Assert.AreEqual(besUsesClause, LCompositionEvidence.Units[0].EvidenceSources[0],
          'Uses-clause-derived units must be tagged with besUsesClause');
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

procedure TUnitResolverTests.Resolve_ClassicPlatformNoMap_UsesClauseFallback;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
  LTempDir: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyResolverNoMap_' + TPath.GetRandomFileName);
  TDirectory.CreateDirectory(LTempDir);
  try
    TFile.WriteAllText(TPath.Combine(LTempDir, 'MyApp.dpr'),
      'program MyApp;' + sLineBreak +
      'uses' + sLineBreak +
      '  LocalUnit;' + sLineBreak +
      'begin' + sLineBreak +
      'end.');
    TFile.WriteAllText(TPath.Combine(LTempDir, 'LocalUnit.pas'),
      'unit LocalUnit;' + sLineBreak +
      'interface' + sLineBreak +
      'implementation' + sLineBreak +
      'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectPath := TPath.Combine(LTempDir, 'MyApp.dproj');
      LProjectInfo.ProjectDir := LTempDir;
      LProjectInfo.Platform := 'Win32';
      LProjectInfo.Configuration := 'Debug';
      LBuildEvidence.SearchPaths.Add(LTempDir);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.IsTrue(LCompositionEvidence.Units.Count > 0,
          'Classic platform without MAP evidence must also fall back to uses-clause analysis');
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

procedure TUnitResolverTests.Resolve_ClassicPlatformWithMap_NoUsesClauseFallback;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
  LTempDir: string;
  LUnit: TResolvedUnitInfo;
  LHasUsesClause: Boolean;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyResolverMap_' + TPath.GetRandomFileName);
  TDirectory.CreateDirectory(LTempDir);
  try
    // Create a .dpr that references ExtraUnit — should NOT be picked up
    TFile.WriteAllText(TPath.Combine(LTempDir, 'MyApp.dpr'),
      'program MyApp;' + sLineBreak +
      'uses' + sLineBreak +
      '  ExtraUnit;' + sLineBreak +
      'begin' + sLineBreak +
      'end.');
    TFile.WriteAllText(TPath.Combine(LTempDir, 'ExtraUnit.pas'),
      'unit ExtraUnit;' + sLineBreak +
      'interface implementation end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectPath := TPath.Combine(LTempDir, 'MyApp.dproj');
      LProjectInfo.ProjectDir := LTempDir;
      LProjectInfo.Platform := 'Win64';
      LProjectInfo.Configuration := 'Release';
      LBuildEvidence.SearchPaths.Add(LTempDir);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LTempDir, 'MyApp.map');
      LEvidenceItem.UnitName := 'MapUnit';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        LHasUsesClause := False;
        for LUnit in LCompositionEvidence.Units do
          if (Length(LUnit.EvidenceSources) > 0) and (LUnit.EvidenceSources[0] = besUsesClause) then
            LHasUsesClause := True;

        Assert.IsFalse(LHasUsesClause,
          'Classic platform with MAP evidence must not invoke uses-clause fallback');
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

procedure TUnitResolverTests.IsClassicCompilerPlatform_ClassifiesCorrectly;
begin
  Assert.IsTrue(TUnitResolver.IsClassicCompilerPlatform('Win32'),
    'Win32 must be classified as classic compiler platform');
  Assert.IsTrue(TUnitResolver.IsClassicCompilerPlatform('Win64'),
    'Win64 must be classified as classic compiler platform');
  Assert.IsFalse(TUnitResolver.IsClassicCompilerPlatform('iOSDevice64'),
    'iOSDevice64 must be classified as LLVM platform');
  Assert.IsFalse(TUnitResolver.IsClassicCompilerPlatform('Android'),
    'Android must be classified as LLVM platform');
  Assert.IsFalse(TUnitResolver.IsClassicCompilerPlatform('Android64'),
    'Android64 must be classified as LLVM platform');
  Assert.IsFalse(TUnitResolver.IsClassicCompilerPlatform('OSX64'),
    'OSX64 must be classified as LLVM platform');
  Assert.IsFalse(TUnitResolver.IsClassicCompilerPlatform('OSXARM64'),
    'OSXARM64 must be classified as LLVM platform');
  Assert.IsFalse(TUnitResolver.IsClassicCompilerPlatform('Linux64'),
    'Linux64 must be classified as LLVM platform');
  Assert.IsFalse(TUnitResolver.IsClassicCompilerPlatform('Win64x'),
    'Win64x (ARM64) must be classified as LLVM platform');
end;

procedure TUnitResolverTests.Resolve_SiblingDirectoryInSearchPaths_ClassifiesAsLocalProject;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
  LProjectDir: string;
  LSharedDir: string;
  LTempRoot: string;
  LUnitPath: string;
begin
  // Layout:  <TempRoot>\ProjectDir\   (project lives here)
  //          <TempRoot>\SharedUnits\  (sibling directory in project search paths)
  LTempRoot := TPath.Combine(TPath.GetTempPath,
    'DXComplyResolverSibling_' + TPath.GetRandomFileName);
  LProjectDir := TPath.Combine(LTempRoot, 'ProjectDir');
  LSharedDir := TPath.Combine(LTempRoot, 'SharedUnits');
  TDirectory.CreateDirectory(LProjectDir);
  TDirectory.CreateDirectory(LSharedDir);
  try
    LUnitPath := TPath.Combine(LSharedDir, 'Shared.Helpers.pas');
    TFile.WriteAllText(LUnitPath,
      'unit Shared.Helpers;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectPath := TPath.Combine(LProjectDir, 'MyApp.dproj');
      LProjectInfo.ProjectDir := LProjectDir;
      LProjectInfo.Platform := 'Win32';
      LProjectInfo.Configuration := 'Release';
      // Register SharedUnits as a project search path (mirrors what the .dproj
      // parser produces for a ..\SharedUnits\ entry in the DCC_UnitSearchPath).
      LProjectInfo.ProjectSearchPaths.Add(LSharedDir);
      LBuildEvidence.SearchPaths.Add(LSharedDir);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LProjectDir, 'MyApp.map');
      LEvidenceItem.UnitName := 'Shared.Helpers';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.AreEqual(uokLocalProject, LCompositionEvidence.Units[0].OriginKind,
          'A unit in a sibling directory declared in project search paths must be ' +
          'classified as Local project, not Third party (issue #22)');
      finally
        LCompositionEvidence.Free;
      end;
    finally
      LBuildEvidence.Free;
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempRoot) then
      TDirectory.Delete(LTempRoot, True);
  end;
end;

procedure TUnitResolverTests.Resolve_UnitOutsideSearchPaths_ClassifiesAsThirdParty;
var
  LEvidenceItem: TBuildEvidenceItem;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LProjectInfo: TProjectInfo;
  LProjectDir: string;
  LThirdPartyDir: string;
  LTempRoot: string;
  LUnitPath: string;
begin
  LTempRoot := TPath.Combine(TPath.GetTempPath,
    'DXComplyResolverThirdParty_' + TPath.GetRandomFileName);
  LProjectDir := TPath.Combine(LTempRoot, 'ProjectDir');
  LThirdPartyDir := TPath.Combine(LTempRoot, 'SomeThirdPartyLib');
  TDirectory.CreateDirectory(LProjectDir);
  TDirectory.CreateDirectory(LThirdPartyDir);
  try
    LUnitPath := TPath.Combine(LThirdPartyDir, 'ThirdParty.Core.pas');
    TFile.WriteAllText(LUnitPath,
      'unit ThirdParty.Core;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectPath := TPath.Combine(LProjectDir, 'MyApp.dproj');
      LProjectInfo.ProjectDir := LProjectDir;
      LProjectInfo.Platform := 'Win32';
      LProjectInfo.Configuration := 'Release';
      // ThirdPartyDir is in the build evidence search paths but NOT in the
      // project-declared search paths — so the unit should remain Third party.
      LBuildEvidence.SearchPaths.Add(LThirdPartyDir);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LProjectDir, 'MyApp.map');
      LEvidenceItem.UnitName := 'ThirdParty.Core';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.AreEqual(uokThirdParty, LCompositionEvidence.Units[0].OriginKind,
          'A unit outside the project directory and project search paths must remain Third party');
      finally
        LCompositionEvidence.Free;
      end;
    finally
      LBuildEvidence.Free;
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTempRoot) then
      TDirectory.Delete(LTempRoot, True);
  end;
end;

procedure TUnitResolverTests.Resolve_ProjectSearchPathBelowDelphiRoot_ClassifiesAsThirdParty;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LEvidenceItem: TBuildEvidenceItem;
  LLibDir: string;
  LProjectInfo: TProjectInfo;
  LTempDir: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LLibDir := TPath.Combine(LTempDir, 'Delphi\Extras\CpDrv');
  TDirectory.CreateDirectory(LLibDir);
  TDirectory.CreateDirectory(TPath.Combine(LTempDir, 'Project'));
  try
    TFile.WriteAllText(TPath.Combine(LLibDir, 'CPDrv.pas'),
      'unit CPDrv;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectDir := TPath.Combine(LTempDir, 'Project');
      LProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
      LProjectInfo.Toolchain.RootDir := TPath.Combine(LTempDir, 'Delphi');
      LProjectInfo.Toolchain.Version := '37.0';
      LProjectInfo.ProjectSearchPaths.Add(LLibDir);
      LBuildEvidence.SearchPaths.Add(LLibDir);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LTempDir, 'Demo.map');
      LEvidenceItem.UnitName := 'CPDrv';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.AreEqual(uokThirdParty, LCompositionEvidence.Units[0].OriginKind,
          'A project search path inside the Delphi folder must not make a unit Local project');
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

procedure TUnitResolverTests.Resolve_DcuInOutputDir_UsesOriginOfSource;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LDcuDir: string;
  LEvidenceItem: TBuildEvidenceItem;
  LLibDir: string;
  LProjectDir: string;
  LProjectInfo: TProjectInfo;
  LTempDir: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LProjectDir := TPath.Combine(LTempDir, 'Project');
  LDcuDir := TPath.Combine(LProjectDir, 'Win32\Release');
  LLibDir := TPath.Combine(LTempDir, 'Libs\DEC\Source');
  TDirectory.CreateDirectory(LDcuDir);
  TDirectory.CreateDirectory(LLibDir);
  try
    TFile.WriteAllBytes(TPath.Combine(LDcuDir, 'DECCipherBase.dcu'), TBytes.Create($01, $02));
    TFile.WriteAllBytes(TPath.Combine(LDcuDir, 'Main.dcu'), TBytes.Create($01, $02));
    TFile.WriteAllText(TPath.Combine(LLibDir, 'DECCipherBase.pas'),
      'unit DECCipherBase;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectDir := LProjectDir;
      LBuildEvidence.Paths.DcuOutputDir := LDcuDir;
      LBuildEvidence.SearchPaths.Add(LLibDir);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LProjectDir, 'Demo.map');
      LEvidenceItem.UnitName := 'DECCipherBase';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);
      LEvidenceItem.UnitName := 'Main';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(2), NativeInt(LCompositionEvidence.Units.Count));
        for var LUnit in LCompositionEvidence.Units do
        begin
          if SameText(LUnit.UnitName, 'DECCipherBase') then
          begin
            Assert.AreEqual(uokThirdParty, LUnit.OriginKind,
              'A DCU compiled from a third-party source stays Third party');
            Assert.IsTrue(SameText(LUnit.SourcePath,
              TPath.Combine(LLibDir, 'DECCipherBase.pas')),
              'The .pas on the search path is kept so a manifest folder can match it');
          end
          else
          begin
            Assert.AreEqual(uokLocalProject, LUnit.OriginKind,
              'A DCU without a source outside the output folder stays Local project');
            Assert.AreEqual('', LUnit.SourcePath,
              'A DCU with no source outside the output folder has no source path');
          end;
        end;
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

procedure TUnitResolverTests.Resolve_LibraryInDelphiExtrasFolder_ClassifiesAsThirdParty;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LEvidenceItem: TBuildEvidenceItem;
  LExtrasDir: string;
  LProjectInfo: TProjectInfo;
  LTempDir: string;
  LUnitDcuPath: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LExtrasDir := TPath.Combine(LTempDir, 'Extras\madExcept\madExcept\BDS37\win32');
  TDirectory.CreateDirectory(LExtrasDir);
  try
    LUnitDcuPath := TPath.Combine(LExtrasDir, 'madExcept.dcu');
    TFile.WriteAllBytes(LUnitDcuPath, TBytes.Create($01, $02, $03, $04));

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectDir := TPath.Combine(LTempDir, 'Project');
      LProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
      LProjectInfo.Toolchain.RootDir := LTempDir;
      LProjectInfo.Toolchain.Version := '37.0';
      LBuildEvidence.SearchPaths.Add(LExtrasDir);

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LTempDir, 'Demo.map');
      LEvidenceItem.UnitName := 'madExcept';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count));
        Assert.AreEqual(LUnitDcuPath, LCompositionEvidence.Units[0].ResolvedPath);
        Assert.AreEqual(uokThirdParty, LCompositionEvidence.Units[0].OriginKind,
          'A library below Delphi\Extras must be classified as Third party');
        Assert.IsTrue(SameText(LCompositionEvidence.Units[0].SourcePath, LUnitDcuPath),
          'A DCU outside the output folder keeps its path for manifest folder matching');
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

function ResolveInstallFile(const AResolver: IUnitResolver;
  const AInstallRoot, AUnitDir, AUnitName, AFileName, AText: string;
  AAsDcu: Boolean): TResolvedUnitInfo;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LEvidenceItem: TBuildEvidenceItem;
  LFilePath: string;
  LProjectDir: string;
  LProjectInfo: TProjectInfo;
begin
  Result := Default(TResolvedUnitInfo);
  LProjectDir := TPath.Combine(TPath.GetDirectoryName(
    ExcludeTrailingPathDelimiter(AInstallRoot)), 'Project');
  TDirectory.CreateDirectory(LProjectDir);
  TDirectory.CreateDirectory(AUnitDir);
  LFilePath := TPath.Combine(AUnitDir, AFileName);
  if AAsDcu then
    TFile.WriteAllBytes(LFilePath, TBytes.Create($01, $02, $03, $04))
  else
    TFile.WriteAllText(LFilePath, AText);

  LProjectInfo := TProjectInfo.Create;
  LBuildEvidence := TBuildEvidence.Create;
  try
    LProjectInfo.ProjectDir := LProjectDir;
    LProjectInfo.Platform := 'Win32';
    LProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
    LProjectInfo.Toolchain.RootDir := AInstallRoot;
    LProjectInfo.Toolchain.Version := '37.0';
    LBuildEvidence.SearchPaths.Add(AUnitDir);

    LEvidenceItem := Default(TBuildEvidenceItem);
    LEvidenceItem.SourceKind := besMapFile;
    LEvidenceItem.FilePath := TPath.Combine(LProjectDir, 'Demo.map');
    LEvidenceItem.UnitName := AUnitName;
    LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

    LCompositionEvidence := AResolver.Resolve(LProjectInfo, LBuildEvidence);
    try
      Assert.AreEqual(NativeInt(1), NativeInt(LCompositionEvidence.Units.Count),
        AUnitName);
      Result := LCompositionEvidence.Units[0];
    finally
      LCompositionEvidence.Free;
    end;
  finally
    LBuildEvidence.Free;
    LProjectInfo.Free;
  end;
end;

function JsonPath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
end;

function DecManifest(const AMatchField, AMatchValue: string): string;
begin
  Result := '{"match":{"prefixes":"legacy"},"components":[{"name":"DEC","vendor":"Example","licence":"MIT",' +
    '"type":"library","' + AMatchField + '":["' + AMatchValue + '"]}]}';
end;

function ArtefactFromResolved(const AUnit: TResolvedUnitInfo): TArtefactInfo;
begin
  Result := Default(TArtefactInfo);
  Result.FilePath := AUnit.ResolvedPath;
  Result.SourcePath := AUnit.SourcePath;
  Result.UnitName := AUnit.UnitName;
  Result.RelativePath := TPath.GetFileName(AUnit.ResolvedPath);
  Result.ArtefactType := 'unit-evidence';
  Result.Origin := UnitOriginKindToString(AUnit.OriginKind);
end;

procedure AssertDecComponent(const AJson, AUnitName, ASourcePath, ABecause: string);
var
  LError: string;
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  Assert.IsTrue(TryParseComponentManifest(AJson, '', LManifest, LError), LError);
  LMatch := MatchManifestUnit(LManifest, AUnitName, ASourcePath);
  Assert.AreEqual(NativeInt(Ord(mmLibrary)), NativeInt(Ord(LMatch.Kind)), ABecause);
  Assert.IsTrue(LMatch.ComponentIndex >= 0, ABecause);
  Assert.AreEqual('DEC', LManifest.Components[LMatch.ComponentIndex].Name, ABecause);
end;

procedure TUnitResolverTests.Resolve_ExtrasDecWithManifest_MatchesComponent;
var
  LDecDir: string;
  LInstall: string;
  LManifest: TComponentManifest;
  LError: string;
  LTemp: string;
  LUnit: TResolvedUnitInfo;
  LUnits: TResolvedUnitList;
begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'Delphi');
  LDecDir := TPath.Combine(LInstall, 'Extras\DEC');
  try
    LUnit := ResolveInstallFile(FResolver, LInstall, LDecDir, 'DECCipher',
      'DECCipher.pas',
      'unit DECCipher;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.', False);
    Assert.AreEqual(uokThirdParty, LUnit.OriginKind,
      'A unit under Extras is third party before the manifest is applied');
    Assert.IsTrue(SameText(LUnit.SourcePath, TPath.Combine(LDecDir, 'DECCipher.pas')),
      'The Extras source path is kept for a folder rule');

    AssertDecComponent(DecManifest('units_exact', 'DECCipher'),
      'DECCipher', LUnit.SourcePath, 'units_exact');
    AssertDecComponent(DecManifest('units_prefix', 'DEC'),
      'DECCipher', LUnit.SourcePath, 'units_prefix');
    AssertDecComponent(DecManifest('units_folder', JsonPath(LDecDir)),
      'DECCipher', LUnit.SourcePath, 'units_folder');

    Assert.IsTrue(TryParseComponentManifest(DecManifest('units_folder', JsonPath(LDecDir)),
      '', LManifest, LError), LError);
    LUnits := TResolvedUnitList.Create;
    try
      LUnits.Add(LUnit);
      ApplyManifestOverInstallOrigin(LManifest, LInstall, LUnits);
      Assert.AreEqual(uokThirdParty, LUnits[0].OriginKind,
        'A manifest match keeps an Extras unit as third party');
    finally
      LUnits.Free;
    end;
  finally
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

procedure TUnitResolverTests.Resolve_ExtrasDecWithoutManifest_ClassifiesAsThirdParty;
var
  LInstall: string;
  LTemp: string;
  LUnit: TResolvedUnitInfo;
begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'Delphi');
  try
    LUnit := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'Extras\DEC'), 'DECCipher', 'DECCipher.pas',
      'unit DECCipher;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.', False);
    Assert.AreEqual(uokThirdParty, LUnit.OriginKind,
      'Extras\DEC with no manifest row is third party, not Embarcadero RTL');
  finally
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

procedure TUnitResolverTests.Resolve_ProductSourceFolders_StayEmbarcadero;
var
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LEvidenceItem: TBuildEvidenceItem;
  LInstall: string;
  LProjectDir: string;
  LProjectInfo: TProjectInfo;
  LTemp: string;
  LUnit: TResolvedUnitInfo;
  i: Integer;
begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'Delphi');
  LProjectDir := TPath.Combine(LTemp, 'Project');
  TDirectory.CreateDirectory(TPath.Combine(LInstall, 'source\rtl\sys'));
  TDirectory.CreateDirectory(TPath.Combine(LInstall, 'source\vcl'));
  TDirectory.CreateDirectory(TPath.Combine(LInstall, 'source\fmx'));
  TDirectory.CreateDirectory(TPath.Combine(LInstall, 'source\data'));
  TDirectory.CreateDirectory(LProjectDir);
  try
    TFile.WriteAllText(TPath.Combine(LInstall, 'source\rtl\sys\System.SysUtils.pas'),
      'unit System.SysUtils;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');
    TFile.WriteAllText(TPath.Combine(LInstall, 'source\vcl\Vcl.Forms.pas'),
      'unit Vcl.Forms;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');
    TFile.WriteAllText(TPath.Combine(LInstall, 'source\fmx\FMX.Forms.pas'),
      'unit FMX.Forms;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');
    TFile.WriteAllText(TPath.Combine(LInstall, 'source\data\Data.DB.pas'),
      'unit Data.DB;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.');

    LProjectInfo := TProjectInfo.Create;
    LBuildEvidence := TBuildEvidence.Create;
    try
      LProjectInfo.ProjectDir := LProjectDir;
      LProjectInfo.Platform := 'Win32';
      LProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
      LProjectInfo.Toolchain.RootDir := LInstall;
      LProjectInfo.Toolchain.Version := '37.0';
      LBuildEvidence.SearchPaths.Add(TPath.Combine(LInstall, 'source\rtl\sys'));
      LBuildEvidence.SearchPaths.Add(TPath.Combine(LInstall, 'source\vcl'));
      LBuildEvidence.SearchPaths.Add(TPath.Combine(LInstall, 'source\fmx'));
      LBuildEvidence.SearchPaths.Add(TPath.Combine(LInstall, 'source\data'));

      LEvidenceItem := Default(TBuildEvidenceItem);
      LEvidenceItem.SourceKind := besMapFile;
      LEvidenceItem.FilePath := TPath.Combine(LProjectDir, 'Demo.map');
      LEvidenceItem.UnitName := 'System.SysUtils';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);
      LEvidenceItem.UnitName := 'Vcl.Forms';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);
      LEvidenceItem.UnitName := 'FMX.Forms';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);
      LEvidenceItem.UnitName := 'Data.DB';
      LBuildEvidence.EvidenceItems.Add(LEvidenceItem);

      LCompositionEvidence := FResolver.Resolve(LProjectInfo, LBuildEvidence);
      try
        Assert.AreEqual(NativeInt(4), NativeInt(LCompositionEvidence.Units.Count));
        for i := 0 to LCompositionEvidence.Units.Count - 1 do
        begin
          LUnit := LCompositionEvidence.Units[i];
          if SameText(LUnit.UnitName, 'System.SysUtils') then
            Assert.AreEqual(uokEmbarcaderoRtl, LUnit.OriginKind,
              'A unit under source\rtl stays Embarcadero RTL')
          else if SameText(LUnit.UnitName, 'Vcl.Forms') then
            Assert.AreEqual(uokEmbarcaderoVcl, LUnit.OriginKind,
              'A unit under source\vcl stays Embarcadero VCL')
          else if SameText(LUnit.UnitName, 'FMX.Forms') then
            Assert.AreEqual(uokEmbarcaderoFmx, LUnit.OriginKind,
              'A unit under source\fmx stays Embarcadero FMX')
          else
            Assert.AreEqual(uokEmbarcaderoRtl, LUnit.OriginKind,
              'A unit under source\data stays Embarcadero RTL');
        end;
      finally
        LCompositionEvidence.Free;
      end;
    finally
      LBuildEvidence.Free;
      LProjectInfo.Free;
    end;
  finally
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

procedure TUnitResolverTests.Resolve_CatalogRepositoryUnderInstall_ClassifiesAsThirdParty;
var
  LInstall: string;
  LTemp: string;
  LUnit: TResolvedUnitInfo;
begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'Delphi');
  try
    LUnit := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'CatalogRepository\ICS\Source'),
      'OverbyteIcsWSocket', 'OverbyteIcsWSocket.pas',
      'unit OverbyteIcsWSocket;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.', False);
    Assert.AreEqual(uokThirdParty, LUnit.OriginKind,
      'A GetIt package under the install CatalogRepository is third party');
  finally
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

procedure TUnitResolverTests.Resolve_CatalogRepositoryUnderDocuments_ClassifiesAsThirdParty;
var
  LInstall: string;
  LTemp: string;
  LUnit: TResolvedUnitInfo;
begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'ProgramFiles\Embarcadero\Studio\37.0');
  try
    // Default GetIt location: Documents\Embarcadero\Studio\<version>\CatalogRepository
    LUnit := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LTemp, 'Documents\Embarcadero\Studio\37.0\CatalogRepository\ICS\Source'),
      'OverbyteIcsWSocket', 'OverbyteIcsWSocket.pas',
      'unit OverbyteIcsWSocket;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.', False);
    Assert.AreEqual(uokThirdParty, LUnit.OriginKind,
      'A GetIt package under Documents is third party');
  finally
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

procedure TUnitResolverTests.Resolve_ProductLibDcuWithManifest_MatchesComponent;
var
  LError: string;
  LInstall: string;
  LManifest: TComponentManifest;
  LPath: string;
  LTemp: string;
  LUnit: TResolvedUnitInfo;
  LUnits: TResolvedUnitList;
begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'Delphi');
  try
    LUnit := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'lib\Win32\release'), 'DECCipher', 'DECCipher.dcu',
      '', True);
    Assert.AreEqual(uokEmbarcaderoRtl, LUnit.OriginKind,
      'A DCU in the product lib folder is Embarcadero when no row matches');

    Assert.IsTrue(TryParseComponentManifest(DecManifest('units_prefix', 'DEC'),
      '', LManifest, LError), LError);
    LManifest.InstallRoot := LInstall;
    LUnits := TResolvedUnitList.Create;
    try
      LUnits.Add(LUnit);
      ApplyManifestOverInstallOrigin(LManifest, LInstall, LUnits);
      Assert.AreEqual(uokEmbarcaderoRtl, LUnits[0].OriginKind,
        'A prefix does not reassign a unit in the product lib folder');
      LPath := LUnit.SourcePath;
      if LPath = '' then
        LPath := LUnit.ResolvedPath;
      Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(
        LManifest, 'DECCipher', LPath).Kind),
        'The same prefix does not assign once the install root is known');
    finally
      LUnits.Free;
    end;

    AssertDecComponent(DecManifest('units_exact', 'DECCipher'),
      'DECCipher', LUnit.SourcePath, 'units_exact');
    Assert.IsTrue(TryParseComponentManifest(DecManifest('units_exact', 'DECCipher'),
      '', LManifest, LError), LError);
    LUnits := TResolvedUnitList.Create;
    try
      LUnits.Add(LUnit);
      ApplyManifestOverInstallOrigin(LManifest, LInstall, LUnits);
      Assert.AreEqual(uokThirdParty, LUnits[0].OriginKind,
        'units_exact still wins over the product lib location');
    finally
      LUnits.Free;
    end;
  finally
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

procedure TUnitResolverTests.Resolve_ShortPrefix_KeepsProductUnitsEmbarcadero;
const
  cJson = '{"components":[{"name":"TMS VCL UI Pack","vendor":"tmssoftware.com",' +
    '"licence":"Commercial","type":"library",' +
    '"units_prefix":["Adv","GDIP","HTML","TMS"]}]}';
var
  LArtefact: TArtefactInfo;
  LArtefacts: TArtefactList;
  LEntry: TComponentEntry;
  LError: string;
  LGdip: TResolvedUnitInfo;
  LHelp: TResolvedUnitInfo;
  LInstall: string;
  LLine: string;
  LManifest: TComponentManifest;
  LTemp: string;
  LUnits: TResolvedUnitList;
begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'Delphi');
  try
    LGdip := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'source\rtl\win'), 'Winapi.GDIPAPI',
      'Winapi.GDIPAPI.pas',
      'unit Winapi.GDIPAPI;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.', False);
    LHelp := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'source\vcl'), 'Vcl.HtmlHelpViewer',
      'Vcl.HtmlHelpViewer.pas',
      'unit Vcl.HtmlHelpViewer;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.', False);
    Assert.AreEqual(uokEmbarcaderoRtl, LGdip.OriginKind);
    Assert.AreEqual(uokEmbarcaderoVcl, LHelp.OriginKind);

    Assert.IsTrue(TryParseComponentManifest(cJson, '', LManifest, LError), LError);
    LManifest.InstallRoot := LInstall;
    Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LManifest, 'Winapi.GDIPAPI',
      LGdip.SourcePath).Kind), 'GDIP must not take Winapi.GDIPAPI');
    Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LManifest, 'Vcl.HtmlHelpViewer',
      LHelp.SourcePath).Kind), 'HTML must not take Vcl.HtmlHelpViewer');
    // A dotted prefix is still refused on a product path.
    LEntry := LManifest.Components[0];
    LEntry.Prefixes := TArray<string>.Create('Winapi.GDIP');
    LManifest.Components[0] := LEntry;
    Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LManifest, 'Winapi.GDIPAPI',
      LGdip.SourcePath).Kind), 'A dotted prefix does not reassign a product path');

    LEntry.Prefixes := TArray<string>.Create('Adv', 'GDIP', 'HTML', 'TMS');
    LManifest.Components[0] := LEntry;
    LUnits := TResolvedUnitList.Create;
    try
      LUnits.Add(LGdip);
      LUnits.Add(LHelp);
      ApplyManifestOverInstallOrigin(LManifest, LInstall, LUnits);
      Assert.AreEqual(uokEmbarcaderoRtl, LUnits[0].OriginKind);
      Assert.AreEqual(uokEmbarcaderoVcl, LUnits[1].OriginKind);
    finally
      LUnits.Free;
    end;

    LArtefact := ArtefactFromResolved(LGdip);
    LArtefacts := TArtefactList.Create;
    try
      LArtefacts.Add(LArtefact);
      LLine := RejectedPrefixLogLines(LManifest, LArtefacts)[0];
    finally
      LArtefacts.Free;
    end;
    Assert.IsTrue(Pos('unit Winapi.GDIPAPI', LLine) > 0, LLine);
    Assert.IsTrue(Pos('prefix GDIP', LLine) > 0, LLine);
    Assert.IsTrue(Pos('row TMS VCL UI Pack', LLine) > 0, LLine);
    Assert.IsTrue(Pos('kept origin Embarcadero RTL', LLine) > 0, LLine);
  finally
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

procedure TUnitResolverTests.Resolve_UserFoldersUnderInstall_ClassifyAsThirdParty;
var
  LInstall: string;
  LTemp: string;
  LSource: TResolvedUnitInfo;
  LLib: TResolvedUnitInfo;
begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'Delphi');
  try
    LSource := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'source\DEC'), 'DECCipher', 'DECCipher.pas',
      'unit DECCipher;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.', False);
    LLib := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'lib\DEC'), 'DECUtil', 'DECUtil.dcu', '', True);
    Assert.AreEqual(uokThirdParty, LSource.OriginKind,
      'A folder added under source is third party');
    Assert.AreEqual(uokThirdParty, LLib.OriginKind,
      'A folder added under lib is third party');
  finally
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

procedure TUnitResolverTests.Resolve_UnmatchedInstallUnit_IsNamedUnknownSupplier;
const
  cManifestJson =
    '{"match":{"prefixes":"legacy"},"components":[{"name":"DEC","vendor":"Example","licence":"MIT",' +
    '"units_prefix":["DEC"]}],"own_code_units":["MyHelper"]}';
var
  LArtefacts: TArtefactList;
  LData: TComplianceReportData;
  LDec: TResolvedUnitInfo;
  LError: string;
  LExample: TReportGroup;
  LHelper: TResolvedUnitInfo;
  LIcs: TResolvedUnitInfo;
  LInstall: string;
  LManifest: TComponentManifest;
  LOverview: TReportOverview;
  LRtl: TResolvedUnitInfo;
  LTemp: string;
  LUnits: TResolvedUnitList;
  LUnknown: TReportGroup;
  LWarnings: TArray<string>;

  function PasText(const AUnitName: string): string;
  begin
    Result := 'unit ' + AUnitName + ';' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.';
  end;

  function FindSupplier(const AOverview: TReportOverview;
    const ATitle: string): TReportGroup;
  var
    i: Integer;
  begin
    Result := Default(TReportGroup);
    for i := 0 to High(AOverview.Suppliers) do
      if SameText(AOverview.Suppliers[i].Title, ATitle) then
        Exit(AOverview.Suppliers[i]);
  end;

begin
  LTemp := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  LInstall := TPath.Combine(LTemp, 'ProgramFiles\Embarcadero\Studio\37.0');
  LArtefacts := TArtefactList.Create;
  LUnits := TResolvedUnitList.Create;
  try
    LDec := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'Extras\DEC'), 'DECCipher', 'DECCipher.pas',
      PasText('DECCipher'), False);
    LIcs := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'CatalogRepository\ICS\Source'),
      'OverbyteIcsWSocket', 'OverbyteIcsWSocket.pas',
      PasText('OverbyteIcsWSocket'), False);
    LHelper := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'Extras\Mine'), 'MyHelper', 'MyHelper.pas',
      PasText('MyHelper'), False);
    LRtl := ResolveInstallFile(FResolver, LInstall,
      TPath.Combine(LInstall, 'source\rtl\sys'), 'System.SysUtils',
      'System.SysUtils.pas', PasText('System.SysUtils'), False);

    LUnits.Add(LDec);
    LUnits.Add(LIcs);
    LUnits.Add(LHelper);
    LUnits.Add(LRtl);
    Assert.IsTrue(TryParseComponentManifest(cManifestJson, '', LManifest, LError),
      LError);
    ApplyManifestOverInstallOrigin(LManifest, LInstall, LUnits);

    Assert.AreEqual(uokThirdParty, LUnits[0].OriginKind,
      'A manifest library under Extras stays third party');
    Assert.AreEqual(uokThirdParty, LUnits[1].OriginKind,
      'A GetIt unit under the install with no row is third party');
    Assert.AreEqual(uokThirdParty, LUnits[2].OriginKind,
      'An own-code unit under Extras is still third party by location');
    Assert.AreEqual(uokEmbarcaderoRtl, LUnits[3].OriginKind,
      'A unit under source\rtl stays Embarcadero RTL');

    LArtefacts.Add(ArtefactFromResolved(LUnits[0]));
    LArtefacts.Add(ArtefactFromResolved(LUnits[1]));
    LArtefacts.Add(ArtefactFromResolved(LUnits[2]));
    LArtefacts.Add(ArtefactFromResolved(LUnits[3]));
    Assert.AreEqual('Third party', LArtefacts[1].Origin);
    Assert.AreEqual('Embarcadero RTL', LArtefacts[3].Origin);

    LData := Default(TComplianceReportData);
    LData.Metadata.ProductName := 'Demo';
    LData.Metadata.ComponentManifestJson := cManifestJson;
    LData.Artefacts := LArtefacts;
    LOverview := BuildReportOverview(LData);

    Assert.AreEqual(2, LOverview.ThirdPartyUnitCount,
      'The library unit and the unmatched unit count as third party');
    Assert.AreEqual(1, LOverview.WithoutManifestCount,
      'Only the unmatched unit is missing a manifest row');
    LUnknown := FindSupplier(LOverview, cUnknownSupplierTitle);
    Assert.AreEqual(1, LUnknown.Count);
    Assert.AreEqual('OverbyteIcsWSocket', LUnknown.NamesText);
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LUnknown.Detail)));
    Assert.AreEqual('Overbyte: 1 unit (OverbyteIcsWSocket)', LUnknown.Detail[0]);
    Assert.AreEqual(0, Pos('DECCipher', LUnknown.NamesText));
    Assert.AreEqual(0, Pos('MyHelper', LUnknown.NamesText));
    Assert.AreEqual(0, Pos('System.SysUtils', LUnknown.NamesText));
    LExample := FindSupplier(LOverview, 'Example');
    Assert.AreEqual(1, LExample.Count);
    Assert.AreEqual('DECCipher', LExample.NamesText);

    LWarnings := BuildThirdPartyComponentWarnings(TSbomConfig.Default,
      LManifest, LArtefacts);
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LWarnings)));
    Assert.IsTrue(Pos('OverbyteIcsWSocket', LWarnings[0]) > 0, LWarnings[0]);
    Assert.AreEqual(0, Pos('DECCipher', LWarnings[0]));
    Assert.AreEqual(0, Pos('MyHelper', LWarnings[0]));
    Assert.AreEqual(0, Pos('System.SysUtils', LWarnings[0]));
  finally
    LUnits.Free;
    LArtefacts.Free;
    if TDirectory.Exists(LTemp) then
      TDirectory.Delete(LTemp, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitResolverTests);

end.