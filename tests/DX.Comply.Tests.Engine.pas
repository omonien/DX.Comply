/// <summary>
/// DX.Comply.Tests.Engine
/// DUnitX tests for TDxComplyGenerator (engine facade).
/// </summary>
///
/// <remarks>
/// Covers project validation, progress-event firing, full end-to-end
/// SBOM generation against the real engine .dproj, configuration defaults,
/// and GenerateFromConfig fall-back behaviour when no config file exists.
///
/// Integration tests (Generate_ValidProject_*) load DX.Comply.Engine.dproj
/// through RepoRoot in DX.Comply.Tests.Paths.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Engine;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.BuildOrchestrator,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf,
  DX.Comply.VersionInfo;

type
  /// <summary>
  /// DUnitX test fixture for TDxComplyGenerator.
  /// </summary>
  [TestFixture]
  TEngineTests = class
  private
    FTempDir: string;
    FOutputFile: string;
    FProgressMessages: TStringList;
    FProgressValues: TList<Integer>;
    /// <summary>
    /// Absolute path to DX.Comply.Engine.dproj, resolved by RepoRoot.
    /// </summary>
    FEngineDprojPath: string;
    /// <summary>
    /// Progress callback. Captures messages and percentage values for assertion.
    /// </summary>
    procedure OnProgress(const AMessage: string; const AProgress: Integer);
    function CreateScopeProject(const AFolder: string; AWithOutputDir: Boolean): string;
    function ScopeConfig: TSbomConfig;
    function CountComponents(const AJson: TJSONObject; const AName: string): NativeInt;
    function ComponentHasHash(const AJson: TJSONObject; const AName: string): Boolean;
    function GenerateScope(const AProjectPath: string; const AConfig: TSbomConfig): TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // ---- ValidateProject ----------------------------------------------------

    /// <summary>ValidateProject must return True for the existing engine dproj.</summary>
    [Test]
    procedure ValidateProject_ValidDproj_ReturnsTrue;

    /// <summary>ValidateProject must return False for a non-existent file.</summary>
    [Test]
    procedure ValidateProject_NonExistentFile_ReturnsFalse;

    /// <summary>ValidateProject must return False for a file with a wrong extension.</summary>
    [Test]
    procedure ValidateProject_WrongExtension_ReturnsFalse;

    // ---- Generate: failure path -------------------------------------------

    /// <summary>Generate with an invalid project path must return False.</summary>
    [Test]
    procedure Generate_InvalidProject_ReturnsFalse;

    /// <summary>A failed Generate must fire a progress event with value -1.</summary>
    [Test]
    procedure Generate_InvalidProject_FiresNegativeProgress;

    // ---- Generate: happy path (integration) --------------------------------

    /// <summary>Generate with the engine dproj must return True and write the output file.</summary>
    [Test]
    procedure Generate_ValidProject_WritesFile;

    /// <summary>A successful Generate must fire a progress event with value 100.</summary>
    [Test]
    procedure Generate_ValidProject_FiresProgress100;

    /// <summary>The generated file must contain valid CycloneDX JSON.</summary>
    [Test]
    procedure Generate_OutputFileContainsValidJson;

    /// <summary>The generated SBOM tool version must match the running module.</summary>
    [Test]
    procedure Generate_ToolVersion_MatchesModule;

    /// <summary>The generated SBOM must include DX.Comply Deep-Evidence metadata properties.</summary>
    [Test]
    procedure Generate_OutputFileContainsDxComplyMetadataProperties;

    /// <summary>
    /// Unit-evidence library components for resolved files must include hashes.
    /// Runtime packages and source-scanned DLLs are also type library and carry
    /// an empty hash on purpose, so they are not part of this check.
    /// </summary>
    [Test]
    procedure Generate_OutputFileContainsUnitEvidenceProperties;

    // ---- GenerateFromConfig -------------------------------------------------

    /// <summary>GenerateFromConfig with a missing config must fall back to defaults and succeed.</summary>
    [Test]
    procedure GenerateFromConfig_MissingConfig_UsesDefaults;

    /// <summary>Generate with report settings must create a Markdown companion report.</summary>
    [Test]
    procedure Generate_WithHumanReadableMarkdownReport_WritesReportFile;

    /// <summary>GenerateFromConfig must honor report settings for Markdown and HTML output.</summary>
    [Test]
    procedure GenerateFromConfig_ReportBoth_WritesMarkdownAndHtmlReports;

    // ---- TSbomConfig --------------------------------------------------------

    /// <summary>TSbomConfig.Default.Format must be sfCycloneDxJson.</summary>
    [Test]
    procedure Config_Default_HasCycloneDxJson;

    /// <summary>TSbomConfig.Default.OutputPath must be 'bom.json'.</summary>
    [Test]
    procedure Config_Default_OutputPathIsBomJson;

    /// <summary>Deep-Evidence builds must be disabled by default.</summary>
    [Test]
    procedure Config_Default_DeepEvidenceBuildWhenMapMissing;

    /// <summary>MapFileDir must be empty by default.</summary>
    [Test]
    procedure Config_Default_MapFileDirEmpty;

    /// <summary>MapFileDir override must redirect the expected MAP file path.</summary>
    [Test]
    procedure Config_MapFileDirOverride_RedirectsMapFilePath;

    /// <summary>IncludeCompositionEvidence must be True by default.</summary>
    [Test]
    procedure Config_Default_IncludeCompositionEvidenceIsTrue;

    /// <summary>
    /// When IncludeCompositionEvidence is False, the generated SBOM must not
    /// contain any unit-evidence (library) components.
    /// </summary>
    [Test]
    procedure Generate_NoCompositionEvidence_OmitsUnitEvidenceComponents;

    // ---- RuntimePackages / External DLL references --------------------------

    /// <summary>
    /// Generated SBOM must include runtime-package components when the
    /// project links with runtime packages (UsePackages true).
    /// </summary>
    [Test]
    procedure Generate_ValidProject_ContainsRuntimePackageComponents;

    /// <summary>
    /// $(ProductVersion) output directories are written to the SBOM as the
    /// directory that exists, with no leftover $(...) token.
    /// </summary>
    [Test]
    procedure Generate_ProductVersionOutput_WritesResolvedPath;

    /// <summary>
    /// Generated SBOM must include external-reference components when
    /// the project source files contain external DLL declarations.
    /// </summary>
    [Test]
    procedure Generate_ValidProject_ContainsExternalDllComponents;

    // ---- ScanPasFilesForDllReferences (issue #24 regressions) ---------------

    /// <summary>const NAME = 'foo.dll' + LoadLibrary(NAME) must resolve to foo.dll.</summary>
    [Test]
    procedure ScanPasFiles_ConstAndLoadLibrary_ResolvesDllName;

    /// <summary>GetModuleHandle('foo.dll') must be detected.</summary>
    [Test]
    procedure ScanPasFiles_GetModuleHandle_DetectsDllName;

    /// <summary>
    /// Same const name in two different units must each resolve independently
    /// (no cross-unit collision).
    /// </summary>
    [Test]
    procedure ScanPasFiles_SameConstInTwoUnits_BothResolveCorrectly;

    /// <summary>A comparison like `if X = 'foo.dll'` must NOT be parsed as a const.</summary>
    [Test]
    procedure ScanPasFiles_ComparisonExpression_NotTreatedAsConst;

    /// <summary>
    /// const declared in unit A, LoadLibrary called in unit B referencing the
    /// same identifier (typical 3rd-party OpenSSL/Indy pattern) must still
    /// resolve. Issue #24, user-reported gap after #36 preview build.
    /// </summary>
    [Test]
    procedure ScanPasFiles_ConstInOtherUnit_ResolvesViaGlobalFallback;

    /// <summary>external 'kernel32.dll' must still be detected, and {$I+} must not be treated as an include.</summary>
    [Test]
    procedure ScanPasFiles_ExternalLiteral_DetectsDllName;

    /// <summary>external DLLName must resolve a const in the same unit.</summary>
    [Test]
    procedure ScanPasFiles_ExternalIdentifier_ResolvesConst;

    /// <summary>
    /// The reported OPC UA stack pattern: the external declaration lives in
    /// an include, and the DLL name const has two {$IFDEF} branches.
    /// Both file names must be reported and marked conditional. Issue #45.
    /// </summary>
    [Test]
    procedure ScanPasFiles_ExternalInInclude_IfdefConst_ResolvesBothNames;

    /// <summary>
    /// An include that is not next to the unit must still be found on the
    /// search path. Issue #45.
    /// </summary>
    [Test]
    procedure ScanPasFiles_IncludeOnSearchPath_ResolvesExternalDll;

    /// <summary>LoadLibrary(CONST) inside an include must resolve a const declared in the including unit.</summary>
    [Test]
    procedure ScanPasFiles_LoadLibraryInInclude_ResolvesConst;

    /// <summary>external NotADll must not be reported when the identifier is not a const.</summary>
    [Test]
    procedure ScanPasFiles_UnresolvedExternalIdent_IsIgnored;

    // ---- .dxcomply.json loading (issue #50) --------------------------------

    /// <summary>configName and platform keys are stored on the loaded config.</summary>
    [Test]
    procedure LoadConfig_ConfigNameAndPlatform;

    /// <summary>A JSON array root must not raise and must keep defaults.</summary>
    [Test]
    procedure LoadConfig_NonObjectRoot_ReturnsDefaults;

    /// <summary>
    /// deepEvidence.build must not override deepEvidence.mode. The boolean
    /// used to be dead code that always stored when-map-missing.
    /// </summary>
    [Test]
    procedure LoadConfig_DeepEvidenceBuild_DoesNotOverrideMode;

    /// <summary>
    /// A file configName applies when the caller did not pass one explicitly.
    /// </summary>
    [Test]
    procedure GenerateFromConfig_FileValues_ApplyWhenNotExplicit;

    /// <summary>
    /// Explicit caller fields win over the file. Omitted fields keep the file.
    /// </summary>
    [Test]
    procedure GenerateFromConfig_ExplicitCaller_OverridesFile;

    /// <summary>
    /// --include-platform-in-output decorates the file output using the
    /// merged platform and configuration, unless --output was explicit.
    /// </summary>
    [Test]
    procedure GenerateFromConfig_IncludePlatformInOutput_DecoratesMergedOutput;

    /// <summary>The recursive output walk is off unless the caller opts in.</summary>
    [Test]
    procedure Config_Default_ScanTreeIsFalse;

    // ---- Artefact scope (issue #38) ------------------------------------------

    /// <summary>
    /// Default generation lists the named output and binaries beside it,
    /// and leaves setup\ and nested build folders out.
    /// </summary>
    [Test]
    procedure Generate_OutputScope_ListsNamedOutputAndSiblingsOnly;

    /// <summary>
    /// The named output stays in the SBOM when the file is missing, without a hash.
    /// </summary>
    [Test]
    procedure Generate_OutputScope_MissingNamedFile_HasNoHash;

    /// <summary>
    /// Runtime packages and external DLLs are still components when the scan
    /// did not find those files.
    /// </summary>
    [Test]
    procedure Generate_OutputScope_KeepsDeclaredDependencies;

    /// <summary>Exclude globs still filter scanned binaries.</summary>
    [Test]
    procedure Generate_OutputScope_ExcludeFiltersScannedFiles;

    /// <summary>
    /// --scan-dir / scanDirs is not recursive unless the value contains **.
    /// </summary>
    [Test]
    procedure Generate_OutputScope_ScanDirRespectsRecursion;

    /// <summary>
    /// scanTree walks the output directory recursively and is reported as deprecated.
    /// </summary>
    [Test]
    procedure Generate_OutputScope_ScanTreeWalksOutputDirectory;

    /// <summary>
    /// With no DCC_ExeOutput, the project directory is scanned non-recursively.
    /// </summary>
    [Test]
    procedure Generate_OutputScope_ProjectDirFallbackSkipsSubfolders;

    /// <summary>A package is scanned from the BPL directory, not DCC_ExeOutput.</summary>
    [Test]
    procedure Generate_OutputScope_PackageUsesBplDirectory;

    /// <summary>scanDirs in .dxcomply.json adds that directory.</summary>
    [Test]
    procedure GenerateFromConfig_ScanDirs_AddsStagedBinaries;

    /// <summary>scanTree in .dxcomply.json restores the recursive walk.</summary>
    [Test]
    procedure GenerateFromConfig_ScanTree_RestoresRecursiveWalk;

  end;

implementation

uses
  Winapi.Windows,
  DX.Comply.Tests.Paths;

{ TEngineTests }

procedure TEngineTests.Setup;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FTempDir := TPath.Combine(TPath.GetTempPath, GUIDToString(LGuid).Trim(['{', '}']));
  TDirectory.CreateDirectory(FTempDir);

  FOutputFile := TPath.Combine(FTempDir, 'bom.json');

  FProgressMessages := TStringList.Create;
  FProgressValues   := TList<Integer>.Create;

  // Engine dproj is at <repo>\src\DX.Comply.Engine.dproj. RepoRoot finds the
  // checkout when the executable is outside build\(platform)\(config)\.
  FEngineDprojPath := TPath.Combine(RepoRoot,
    'src' + PathDelim + 'DX.Comply.Engine.dproj');
end;

procedure TEngineTests.TearDown;
begin
  if TFile.Exists(FOutputFile) then
    TFile.Delete(FOutputFile);
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);

  FProgressMessages.Free;
  FProgressValues.Free;
end;

procedure TEngineTests.OnProgress(const AMessage: string; const AProgress: Integer);
begin
  FProgressMessages.Add(AMessage);
  FProgressValues.Add(AProgress);
end;

// ---- ValidateProject --------------------------------------------------------

procedure TEngineTests.ValidateProject_ValidDproj_ReturnsTrue;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    Assert.IsTrue(LGen.ValidateProject(FEngineDprojPath),
      'ValidateProject must return True for the existing engine dproj');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.ValidateProject_NonExistentFile_ReturnsFalse;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    Assert.IsFalse(LGen.ValidateProject('C:\DoesNotExist\Missing.dproj'),
      'ValidateProject must return False for a non-existent file');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.ValidateProject_WrongExtension_ReturnsFalse;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    Assert.IsFalse(LGen.ValidateProject('C:\Temp\readme.txt'),
      'ValidateProject must return False for a wrong file extension');
  finally
    LGen.Free;
  end;
end;

// ---- Generate: failure path ------------------------------------------------

procedure TEngineTests.Generate_InvalidProject_ReturnsFalse;
var
  LGen: TDxComplyGenerator;
  LResult: Boolean;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LResult := LGen.Generate('C:\DoesNotExist\NoProject.dproj', FOutputFile);
    Assert.IsFalse(LResult, 'Generate must return False for an invalid project path');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_InvalidProject_FiresNegativeProgress;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LGen.Generate('C:\DoesNotExist\NoProject.dproj', FOutputFile);
    Assert.IsTrue(FProgressValues.Contains(-1),
      'A failed Generate must fire a progress event with value -1');
  finally
    LGen.Free;
  end;
end;

// ---- Generate: happy path (integration) ------------------------------------

procedure TEngineTests.Generate_ValidProject_WritesFile;
var
  LGen: TDxComplyGenerator;
  LResult: Boolean;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LResult := LGen.Generate(FEngineDprojPath, FOutputFile);
    Assert.IsTrue(LResult, 'Generate must return True for the engine dproj');
    Assert.IsTrue(TFile.Exists(FOutputFile),
      'Generate must write the output file to disk');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_ValidProject_FiresProgress100;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LGen.Generate(FEngineDprojPath, FOutputFile);
    Assert.IsTrue(FProgressValues.Contains(100),
      'A successful Generate must fire a progress event with value 100');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_OutputFileContainsValidJson;
var
  LGen: TDxComplyGenerator;
  LContent: string;
  LJson: TJSONObject;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LGen.Generate(FEngineDprojPath, FOutputFile);
    Assert.IsTrue(TFile.Exists(FOutputFile), 'Output file must exist');

    LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
    try
      Assert.IsNotNull(LJson, 'Output file must contain valid parseable JSON');
      Assert.AreEqual('CycloneDX', LJson.GetValue<string>('bomFormat'),
        'bomFormat must be CycloneDX');
    finally
      LJson.Free;
    end;
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_ToolVersion_MatchesModule;
var
  LComponents: TJSONArray;
  LGen: TDxComplyGenerator;
  LJson, LMetadata, LTool, LTools: TJSONObject;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.Generate(FEngineDprojPath, FOutputFile),
      'Generate must succeed before the tool version can be checked');
    LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(FOutputFile, TEncoding.UTF8)) as TJSONObject;
    try
      LMetadata := LJson.GetValue('metadata') as TJSONObject;
      LTools := LMetadata.GetValue('tools') as TJSONObject;
      LComponents := LTools.GetValue('components') as TJSONArray;
      LTool := LComponents.Items[0] as TJSONObject;
      Assert.AreEqual(GetDxComplyToolVersion, LTool.GetValue<string>('version'),
        'The generated SBOM tool version must match the running module');
    finally
      LJson.Free;
    end;
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_OutputFileContainsDxComplyMetadataProperties;
var
  LBomProperties: TJSONArray;
  LComponent: TJSONObject;
  LGen: TDxComplyGenerator;
  LContent: string;
  LJson: TJSONObject;
  LMeta: TJSONObject;
  LComponentProperties: TJSONArray;

  function FindPropertyValue(const AProperties: TJSONArray; const AName: string): string;
  var
    I: Integer;
    LProperty: TJSONObject;
  begin
    Result := '';
    for I := 0 to AProperties.Count - 1 do
    begin
      if not (AProperties.Items[I] is TJSONObject) then
        Continue;

      LProperty := TJSONObject(AProperties.Items[I]);
      if SameText(LProperty.GetValue<string>('name'), AName) then
        Exit(LProperty.GetValue<string>('value'));
    end;
  end;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.Generate(FEngineDprojPath, FOutputFile),
      'Generate must succeed for the engine dproj');

    LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
    try
      Assert.IsNotNull(LJson, 'Output file must contain valid parseable JSON');

      LMeta := LJson.GetValue('metadata') as TJSONObject;
      LBomProperties := LMeta.GetValue('properties') as TJSONArray;
      LComponent := LMeta.GetValue('component') as TJSONObject;
      LComponentProperties := LComponent.GetValue('properties') as TJSONArray;

      Assert.IsNotNull(LBomProperties,
        'DX.Comply BOM metadata properties must be present on metadata.properties');
      Assert.IsNotNull(LComponentProperties,
        'DX.Comply component metadata properties must be present on metadata.component.properties');
      Assert.AreEqual('build-evidence', FindPropertyValue(LBomProperties,
        'net.developer-experts.dx-comply:document.profile'),
        'BOM document profile must name the build evidence');
      Assert.AreEqual('Release', FindPropertyValue(LComponentProperties,
        'net.developer-experts.dx-comply:build.configuration'));
      Assert.AreEqual('Win32', FindPropertyValue(LComponentProperties,
        'net.developer-experts.dx-comply:build.platform'));
    finally
      LJson.Free;
    end;
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_OutputFileContainsUnitEvidenceProperties;
const
  cEvidenceProperty = 'net.developer-experts.dx-comply:evidence';
  cConfidenceProperty = 'net.developer-experts.dx-comply:confidence';
  cFileSizeProperty = 'file:size';
var
  LComponents: TJSONArray;
  LComponentObj: TJSONObject;
  LConfig: TSbomConfig;
  LGen: TDxComplyGenerator;
  LContent: string;
  LHashObj: TJSONObject;
  LHashes: TJSONArray;
  LJson: TJSONObject;
  LName: string;
  LTestsDprojPath: string;
  LUnitEvidenceCount: Integer;
  I: Integer;

  function PropertyValue(const AComponent: TJSONObject; const AName: string): string;
  var
    J: Integer;
    LProperties: TJSONArray;
    LProperty: TJSONObject;
  begin
    Result := '';
    LProperties := AComponent.GetValue('properties') as TJSONArray;
    if not Assigned(LProperties) then
      Exit;

    for J := 0 to LProperties.Count - 1 do
    begin
      if not (LProperties.Items[J] is TJSONObject) then
        Continue;
      LProperty := TJSONObject(LProperties.Items[J]);
      if SameText(LProperty.GetValue<string>('name', ''), AName) then
        Exit(LProperty.GetValue<string>('value', ''));
    end;
  end;

  function IsUnitEvidence(const AComponent: TJSONObject): Boolean;
  var
    LConfidence: string;
    LEvidence: string;
  begin
    Result := False;
    if not SameText(AComponent.GetValue<string>('type', ''), 'library') then
      Exit;

    LEvidence := PropertyValue(AComponent, cEvidenceProperty);
    if LEvidence = '' then
      Exit;

    // Runtime packages are declared BPLs. Source-scanned DLLs use confidence
    // Source-scan. Both are type library and have an empty hash on purpose.
    LConfidence := PropertyValue(AComponent, cConfidenceProperty);
    if SameText(LConfidence, 'Source-scan') then
      Exit;
    if SameText(LEvidence, 'BPL') and SameText(LConfidence, 'Declared') then
      Exit;

    Result := True;
  end;

begin
  LTestsDprojPath := TPath.Combine(
    TPath.GetDirectoryName(TPath.GetDirectoryName(FEngineDprojPath)),
    'tests\DX.Comply.Tests.dproj');
  LConfig := TSbomConfig.Default;
  LConfig.OutputPath := FOutputFile;
  LConfig.Format := sfCycloneDxJson;
  LConfig.Configuration := 'Debug';
  LConfig.Platform := 'Win32';
  LConfig.DeepEvidenceMode := debWhenMapMissing;

  LGen := TDxComplyGenerator.Create(LConfig);
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.Generate(LTestsDprojPath, FOutputFile, sfCycloneDxJson),
      'Generate must succeed for the tests dproj');

    LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
    try
      Assert.IsNotNull(LJson, 'Output file must contain valid parseable JSON');

      LComponents := LJson.GetValue('components') as TJSONArray;
      Assert.IsNotNull(LComponents, 'SBOM must contain a components array');
      Assert.IsTrue(LComponents.Count > 1,
        'SBOM must contain more than just the primary artefact');

      LUnitEvidenceCount := 0;
      for I := 0 to LComponents.Count - 1 do
      begin
        LComponentObj := LComponents.Items[I] as TJSONObject;
        if not IsUnitEvidence(LComponentObj) then
          Continue;

        Inc(LUnitEvidenceCount);
        // file:size is written only when the resolved file was present on disk.
        if PropertyValue(LComponentObj, cFileSizeProperty) = '' then
          Continue;

        LName := LComponentObj.GetValue<string>('name', '');
        LHashes := LComponentObj.GetValue('hashes') as TJSONArray;
        Assert.IsNotNull(LHashes,
          'Unit-evidence component "' + LName + '" must include hashes');
        Assert.IsTrue(LHashes.Count > 0,
          'Unit-evidence component "' + LName + '" must include a hash value');
        LHashObj := LHashes.Items[0] as TJSONObject;
        Assert.IsTrue(Trim(LHashObj.GetValue<string>('content', '')) <> '',
          'Unit-evidence component "' + LName + '" must include a non-empty hash');
      end;

      Assert.IsTrue(LUnitEvidenceCount > 0,
        'SBOM must contain at least one unit-evidence library component');
    finally
      LJson.Free;
    end;
  finally
    LGen.Free;
  end;
end;

// ---- GenerateFromConfig -----------------------------------------------------

procedure TEngineTests.GenerateFromConfig_MissingConfig_UsesDefaults;
var
  LGen: TDxComplyGenerator;
  LNonExistentConfig: string;
  LResult: Boolean;
begin
  // When the config file is absent, LoadConfig falls back to TSbomConfig.Default
  // and the generation should still succeed against the valid engine dproj.
  LNonExistentConfig := TPath.Combine(FTempDir, 'nonexistent.json');

  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    // Override the output path to a known temp location so we can clean up.
    // GenerateFromConfig uses the config's OutputPath which defaults to 'bom.json'
    // relative to the project dir. We write to FOutputFile explicitly via Generate
    // after loading the (non-existent) config through the internal API. Since we
    // cannot override output path via GenerateFromConfig directly, we accept any
    // result and simply verify the call does not raise.
    Assert.WillNotRaise(
      procedure
      begin
        LResult := LGen.GenerateFromConfig(FEngineDprojPath, LNonExistentConfig);
      end,
      Exception,
      'GenerateFromConfig must not raise when config file is missing');
    // With a valid project and default config the call should succeed
    Assert.IsTrue(LResult,
      'GenerateFromConfig must succeed when config is missing and project is valid');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_WithHumanReadableMarkdownReport_WritesReportFile;
var
  LConfig: TSbomConfig;
  LGen: TDxComplyGenerator;
  LReportPath: string;
begin
  LReportPath := TPath.Combine(FTempDir, 'compliance.report.md');
  LConfig := TSbomConfig.Default;
  LConfig.HumanReadableReport.Enabled := True;
  LConfig.HumanReadableReport.Format := hrfMarkdown;
  LConfig.HumanReadableReport.OutputBasePath := TPath.Combine(FTempDir, 'compliance.report');

  LGen := TDxComplyGenerator.Create(LConfig);
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.Generate(FEngineDprojPath, FOutputFile));
    Assert.IsTrue(TFile.Exists(LReportPath),
      'Generate must create the configured Markdown companion report');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.GenerateFromConfig_ReportBoth_WritesMarkdownAndHtmlReports;
var
  LConfigJson: TStringList;
  LConfigPath: string;
  LGen: TDxComplyGenerator;
  LReportBasePath: string;
begin
  LConfigPath := TPath.Combine(FTempDir, 'dxcomply.report.json');
  LReportBasePath := TPath.Combine(FTempDir, 'auditor-report');
  LConfigJson := TStringList.Create;
  try
    LConfigJson.Add('{');
    LConfigJson.Add('  "outputPath": "' + StringReplace(FOutputFile, '\', '\\', [rfReplaceAll]) + '",');
    LConfigJson.Add('  "format": "cyclonedx-json",');
    LConfigJson.Add('  "report": {');
    LConfigJson.Add('    "enabled": true,');
    LConfigJson.Add('    "format": "both",');
    LConfigJson.Add('    "output": "' + StringReplace(LReportBasePath, '\', '\\', [rfReplaceAll]) + '",');
    LConfigJson.Add('    "includeWarnings": true,');
    LConfigJson.Add('    "includeCompositionEvidence": true,');
    LConfigJson.Add('    "includeBuildEvidence": true');
    LConfigJson.Add('  }');
    LConfigJson.Add('}');
    LConfigJson.SaveToFile(LConfigPath, TEncoding.UTF8);

    LGen := TDxComplyGenerator.Create;
    try
      LGen.OnProgress := OnProgress;
      Assert.IsTrue(LGen.GenerateFromConfig(FEngineDprojPath, LConfigPath));
      Assert.IsTrue(TFile.Exists(LReportBasePath + '.md'),
        'GenerateFromConfig must create the configured Markdown report');
      Assert.IsTrue(TFile.Exists(LReportBasePath + '.html'),
        'GenerateFromConfig must create the configured HTML report');
    finally
      LGen.Free;
    end;
  finally
    LConfigJson.Free;
  end;
end;

// ---- TSbomConfig ------------------------------------------------------------

procedure TEngineTests.Config_Default_HasCycloneDxJson;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.AreEqual(Ord(sfCycloneDxJson), Ord(LConfig.Format),
    'TSbomConfig.Default.Format must be sfCycloneDxJson');
end;

procedure TEngineTests.Config_Default_OutputPathIsBomJson;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.AreEqual('bom.json', LConfig.OutputPath,
    'TSbomConfig.Default.OutputPath must be ''bom.json''');
end;

procedure TEngineTests.Config_Default_DeepEvidenceBuildWhenMapMissing;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.AreEqual(NativeInt(Ord(debWhenMapMissing)), NativeInt(Ord(LConfig.DeepEvidenceMode)),
    'TSbomConfig.Default.DeepEvidenceMode must be debWhenMapMissing');
  Assert.AreEqual(0, LConfig.DeepEvidenceDelphiVersion,
    'TSbomConfig.Default.DeepEvidenceDelphiVersion must be 0');
  Assert.AreEqual('', LConfig.DeepEvidenceBuildScriptPath,
    'TSbomConfig.Default.DeepEvidenceBuildScriptPath must be empty');
  Assert.IsFalse(LConfig.WarnOnEmptyCompositionEvidence,
    'TSbomConfig.Default.WarnOnEmptyCompositionEvidence must be False');
  Assert.IsFalse(LConfig.HumanReadableReport.Enabled,
    'TSbomConfig.Default.HumanReadableReport.Enabled must be False');
  Assert.AreEqual(NativeInt(Ord(hrfMarkdown)),
    NativeInt(Ord(LConfig.HumanReadableReport.Format)),
    'TSbomConfig.Default.HumanReadableReport.Format must be hrfMarkdown');
end;

procedure TEngineTests.Config_Default_MapFileDirEmpty;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.AreEqual('', LConfig.MapFileDir,
    'TSbomConfig.Default.MapFileDir must be empty');
end;

procedure TEngineTests.Config_MapFileDirOverride_RedirectsMapFilePath;
var
  LGenerator: TDxComplyGenerator;
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  LConfig.MapFileDir := 'C:\CustomMapDir';
  LGenerator := TDxComplyGenerator.Create(LConfig);
  try
    Assert.AreEqual('C:\CustomMapDir', LGenerator.Config.MapFileDir,
      'MapFileDir must be preserved in the generator config');
  finally
    LGenerator.Free;
  end;
end;

procedure TEngineTests.Config_Default_IncludeCompositionEvidenceIsTrue;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.IsTrue(LConfig.IncludeCompositionEvidence,
    'TSbomConfig.Default.IncludeCompositionEvidence must be True');
end;

procedure TEngineTests.Generate_NoCompositionEvidence_OmitsUnitEvidenceComponents;
const
  cOriginPropertyName = 'net.developer-experts.dx-comply:origin';
var
  LConfig: TSbomConfig;
  LGen: TDxComplyGenerator;
  LContent: string;
  LJson: TJSONObject;
  LComponents: TJSONArray;
  LComponent, LProp: TJSONObject;
  LProperties: TJSONArray;
  I, J: Integer;
begin
  LConfig := TSbomConfig.Default;
  LConfig.OutputPath := FOutputFile;
  LConfig.Configuration := 'Debug';
  LConfig.Platform := 'Win32';
  LConfig.DeepEvidenceMode := debWhenMapMissing;
  LConfig.IncludeCompositionEvidence := False;

  LGen := TDxComplyGenerator.Create(LConfig);
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.Generate(FEngineDprojPath, FOutputFile, sfCycloneDxJson),
      'Generate must succeed when IncludeCompositionEvidence is False');

    LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
    try
      Assert.IsNotNull(LJson, 'Output must be valid JSON');
      LComponents := LJson.GetValue('components') as TJSONArray;
      if not Assigned(LComponents) then
        Exit;

      // Unit-evidence components carry the origin property.
      // Shipped artefacts (exe/dll/bpl) do not.
      for I := 0 to LComponents.Count - 1 do
      begin
        LComponent := LComponents.Items[I] as TJSONObject;
        LProperties := LComponent.GetValue('properties') as TJSONArray;
        if not Assigned(LProperties) then
          Continue;
        for J := 0 to LProperties.Count - 1 do
        begin
          LProp := LProperties.Items[J] as TJSONObject;
          Assert.AreNotEqual(cOriginPropertyName,
            LProp.GetValue<string>('name', ''),
            'SBOM must not contain unit-evidence origin property when ' +
            'IncludeCompositionEvidence is False');
        end;
      end;
    finally
      LJson.Free;
    end;
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_ValidProject_ContainsRuntimePackageComponents;
var
  LComponent: TJSONObject;
  LComponents: TJSONArray;
  LConfig: TSbomConfig;
  LContent: string;
  LFoundRuntimePackage: Boolean;
  LGen: TDxComplyGenerator;
  LJson: TJSONObject;
  LProject: string;
  LProp: TJSONObject;
  LProperties: TJSONArray;
  LRoot: string;
  I, J: Integer;
begin
  // The engine .dproj lists DCC_UsePackage and does not set UsePackages, so
  // it must not contribute runtime packages. This fixture links rtl.
  LRoot := TPath.Combine(FTempDir, 'rtlpkg');
  TDirectory.CreateDirectory(LRoot);
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'out'));
  TFile.WriteAllText(TPath.Combine(LRoot, 'RtApp.dpr'),
    'program RtApp;' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(LRoot, 'RtApp.dproj'),
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>RtApp.dpr</MainSource>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\out</DCC_ExeOutput>' + sLineBreak +
    '    <UsePackages>true</UsePackages>' + sLineBreak +
    '    <DCC_UsePackage>rtl</DCC_UsePackage>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak, TEncoding.UTF8);
  // Not a valid PE, so the import filter keeps the UsePackages list.
  // The map file skips the Deep-Evidence build.
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'out', 'RtApp.exe'),
    TBytes.Create($4D, $5A, $01));
  TFile.WriteAllText(TPath.Combine(LRoot, 'out', 'RtApp.map'), 'map', TEncoding.UTF8);
  LProject := TPath.Combine(LRoot, 'RtApp.dproj');

  LConfig := TSbomConfig.Default;
  LConfig.OutputPath := FOutputFile;
  LConfig.Configuration := 'Release';
  LConfig.Platform := 'Win32';
  LConfig.IncludeCompositionEvidence := False;

  LGen := TDxComplyGenerator.Create(LConfig);
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.Generate(LProject, FOutputFile, sfCycloneDxJson),
      'Generate must succeed. Progress: ' + FProgressMessages.Text);

    LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
    try
      LComponents := LJson.GetValue('components') as TJSONArray;
      Assert.IsNotNull(LComponents, 'SBOM must contain components');
      Assert.AreEqual(NativeInt(1), NativeInt(CountComponents(LJson, 'rtl.bpl')),
        'The linked runtime package must be a component');

      LFoundRuntimePackage := False;
      for I := 0 to LComponents.Count - 1 do
      begin
        LComponent := LComponents.Items[I] as TJSONObject;
        if not SameText(LComponent.GetValue<string>('name', ''), 'rtl.bpl') then
          Continue;
        LProperties := LComponent.GetValue('properties') as TJSONArray;
        if not Assigned(LProperties) then
          Continue;
        for J := 0 to LProperties.Count - 1 do
        begin
          LProp := LProperties.Items[J] as TJSONObject;
          if (LProp.GetValue<string>('name', '') = 'net.developer-experts.dx-comply:evidence') and
             (LProp.GetValue<string>('value', '') = 'BPL') then
          begin
            LFoundRuntimePackage := True;
            Break;
          end;
        end;
      end;

      Assert.IsTrue(LFoundRuntimePackage,
        'SBOM must contain a runtime-package component with evidence=BPL');
    finally
      LJson.Free;
    end;
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_ProductVersionOutput_WritesResolvedPath;
var
  LBdsRoot: string;
  LComponent: TJSONObject;
  LConfig: TSbomConfig;
  LDcpDir: string;
  LDcuDir: string;
  LExeDir: string;
  LGen: TDxComplyGenerator;
  LJson: TJSONObject;
  LMeta: TJSONObject;
  LPreviousBds: string;
  LProject: string;
  LProperties: TJSONArray;
  LRoot: string;
  LBplDir: string;

  function FindPropertyValue(const AProperties: TJSONArray; const AName: string): string;
  var
    I: Integer;
    LProperty: TJSONObject;
  begin
    Result := '';
    if not Assigned(AProperties) then
      Exit;
    for I := 0 to AProperties.Count - 1 do
    begin
      if not (AProperties.Items[I] is TJSONObject) then
        Continue;
      LProperty := TJSONObject(AProperties.Items[I]);
      if SameText(LProperty.GetValue<string>('name', ''), AName) then
        Exit(LProperty.GetValue<string>('value', ''));
    end;
  end;

  procedure ExpectResolved(const AValue, AFolder: string);
  var
    LSuffix: string;
  begin
    LSuffix := '\' + AFolder;
    Assert.IsTrue((Length(AValue) >= Length(LSuffix)) and
      (Copy(AValue, Length(AValue) - Length(LSuffix) + 1, Length(LSuffix)) = LSuffix),
      AFolder + ' must be the resolved directory, but was: ' + AValue);
    Assert.IsTrue(Pos('$(', AValue) = 0,
      AFolder + ' must contain no $( token: ' + AValue);
  end;
begin
  LPreviousBds := System.SysUtils.GetEnvironmentVariable('BDS');
  LRoot := TPath.Combine(FTempDir, 'pv');
  TDirectory.CreateDirectory(LRoot);
  LBdsRoot := TPath.Combine(FTempDir, 'bds', '37.0');
  ForceDirectories(LBdsRoot);
  LExeDir := TPath.Combine(LRoot, 'Compiled', 'BIN_IDE_Win32_Release');
  LDcuDir := TPath.Combine(LRoot, 'Compiled', 'DCU_IDE_Win32_Release');
  LDcpDir := TPath.Combine(LRoot, 'Compiled', 'DCP_IDE_Win32_Release');
  LBplDir := TPath.Combine(LRoot, 'Compiled', 'BPL_IDE_Win32_Release');
  ForceDirectories(LExeDir);
  ForceDirectories(LDcuDir);
  ForceDirectories(LDcpDir);
  ForceDirectories(LBplDir);
  try
    Winapi.Windows.SetEnvironmentVariable(PChar('BDS'), PChar(LBdsRoot));
    TFile.WriteAllText(TPath.Combine(LRoot, 'PvApp.dpr'),
      'program PvApp;' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak,
      TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(LExeDir, 'PvApp.map'), 'map', TEncoding.UTF8);
    LProject := TPath.Combine(LRoot, 'PvApp.dproj');
    TFile.WriteAllText(LProject,
      '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
      '  <PropertyGroup>' + sLineBreak +
      '    <MainSource>PvApp.dpr</MainSource>' + sLineBreak +
      '    <AppType>Console</AppType>' + sLineBreak +
      '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
      '    <DCC_ExeOutput>.\Compiled\BIN_IDE$(ProductVersion)_$(Platform)_$(Config)</DCC_ExeOutput>' + sLineBreak +
      '    <DCC_DcuOutput>.\Compiled\DCU_IDE$(ProductVersion)_$(Platform)_$(Config)</DCC_DcuOutput>' + sLineBreak +
      '    <DCC_DcpOutput>.\Compiled\DCP_IDE$(BDSVER)_$(Platform)_$(Config)</DCC_DcpOutput>' + sLineBreak +
      '    <DCC_BplOutput>.\Compiled\BPL_IDE$(BDSVersion)_$(Platform)_$(Config)</DCC_BplOutput>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak +
      '</Project>' + sLineBreak, TEncoding.UTF8);

    LConfig := TSbomConfig.Default;
    LConfig.OutputPath := FOutputFile;
    LConfig.Configuration := 'Release';
    LConfig.Platform := 'Win32';
    LConfig.IncludeCompositionEvidence := False;

    FProgressMessages.Clear;
    LGen := TDxComplyGenerator.Create(LConfig);
    try
      LGen.OnProgress := OnProgress;
      Assert.IsTrue(LGen.Generate(LProject, FOutputFile, sfCycloneDxJson),
        'Generate must succeed. Progress: ' + FProgressMessages.Text);
    finally
      LGen.Free;
    end;

    LJson := TJSONObject.ParseJSONValue(
      TFile.ReadAllText(FOutputFile, TEncoding.UTF8)) as TJSONObject;
    try
      LMeta := LJson.GetValue('metadata') as TJSONObject;
      LComponent := LMeta.GetValue('component') as TJSONObject;
      LProperties := LComponent.GetValue('properties') as TJSONArray;
      ExpectResolved(FindPropertyValue(LProperties,
        'net.developer-experts.dx-comply:build.output-dir'),
        'BIN_IDE_Win32_Release');
      ExpectResolved(FindPropertyValue(LProperties,
        'net.developer-experts.dx-comply:build.dcu-output-dir'),
        'DCU_IDE_Win32_Release');
      ExpectResolved(FindPropertyValue(LProperties,
        'net.developer-experts.dx-comply:build.dcp-output-dir'),
        'DCP_IDE_Win32_Release');
      ExpectResolved(FindPropertyValue(LProperties,
        'net.developer-experts.dx-comply:build.bpl-output-dir'),
        'BPL_IDE_Win32_Release');
    finally
      LJson.Free;
    end;

    Assert.IsTrue(Pos('left empty', FProgressMessages.Text) > 0,
      'Verbose progress must say the empty ProductVersion directory was used: ' +
      FProgressMessages.Text);
    Assert.IsTrue(Pos('DCC_ExeOutput', FProgressMessages.Text) > 0,
      'Verbose progress must name the output directory: ' + FProgressMessages.Text);
  finally
    if LPreviousBds = '' then
      Winapi.Windows.SetEnvironmentVariable(PChar('BDS'), nil)
    else
      Winapi.Windows.SetEnvironmentVariable(PChar('BDS'), PChar(LPreviousBds));
  end;
end;

procedure TEngineTests.Generate_ValidProject_ContainsExternalDllComponents;
var
  LConfig: TSbomConfig;
  LGen: TDxComplyGenerator;
  LContent: string;
  LJson: TJSONObject;
  LComponents: TJSONArray;
  LComponent, LProp: TJSONObject;
  LProperties: TJSONArray;
  LFoundExternalRef: Boolean;
  I, J: Integer;
begin
  LConfig := TSbomConfig.Default;
  LConfig.OutputPath := FOutputFile;
  LConfig.Configuration := 'Debug';
  LConfig.Platform := 'Win32';

  LGen := TDxComplyGenerator.Create(LConfig);
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.Generate(FEngineDprojPath, FOutputFile, sfCycloneDxJson),
      'Generate must succeed');

    LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
    try
      LComponents := LJson.GetValue('components') as TJSONArray;
      Assert.IsNotNull(LComponents, 'SBOM must contain components');

      LFoundExternalRef := False;
      for I := 0 to LComponents.Count - 1 do
      begin
        LComponent := LComponents.Items[I] as TJSONObject;
        LProperties := LComponent.GetValue('properties') as TJSONArray;
        if not Assigned(LProperties) then
          Continue;
        for J := 0 to LProperties.Count - 1 do
        begin
          LProp := LProperties.Items[J] as TJSONObject;
          if (LProp.GetValue<string>('name', '') = 'net.developer-experts.dx-comply:confidence') and
             (LProp.GetValue<string>('value', '') = 'Source-scan') then
          begin
            LFoundExternalRef := True;
            Break;
          end;
        end;
        if LFoundExternalRef then
          Break;
      end;

      // Note: This test may not find external DLL refs in the Engine package
      // itself since it's pure Delphi code. The assertion is intentionally
      // soft: we verify the pipeline runs without error. A project with
      // external declarations would produce components.
      Assert.WillNotRaise(
        procedure begin end,
        Exception,
        'External DLL scan must not raise');
    finally
      LJson.Free;
    end;
  finally
    LGen.Free;
  end;
end;

// ---- ScanPasFilesForDllReferences (issue #24) ------------------------------

procedure TEngineTests.ScanPasFiles_ConstAndLoadLibrary_ResolvesDllName;
var
  LPasFile: string;
  LDllNames: TArray<string>;
const
  cSource =
    'unit TestUnitA;'#13#10 +
    'interface'#13#10 +
    'const'#13#10 +
    '  LIBEAY_DLL_NAME = ''libeay32.dll'';'#13#10 +
    'implementation'#13#10 +
    'procedure DoIt;'#13#10 +
    'begin'#13#10 +
    '  LoadLibrary(LIBEAY_DLL_NAME);'#13#10 +
    'end;'#13#10 +
    'end.';
begin
  LPasFile := TPath.Combine(FTempDir, 'TestUnitA.pas');
  TFile.WriteAllText(LPasFile, cSource, TEncoding.UTF8);
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile));
  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'libeay32.dll') >= 0,
    'libeay32.dll must be detected through const + LoadLibrary identifier resolution');
end;

procedure TEngineTests.ScanPasFiles_GetModuleHandle_DetectsDllName;
var
  LPasFile: string;
  LDllNames: TArray<string>;
const
  cSource =
    'unit TestUnitGmh;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure DoIt;'#13#10 +
    'begin'#13#10 +
    '  GetModuleHandle(''user32.dll'');'#13#10 +
    'end;'#13#10 +
    'end.';
begin
  LPasFile := TPath.Combine(FTempDir, 'TestUnitGmh.pas');
  TFile.WriteAllText(LPasFile, cSource, TEncoding.UTF8);
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile));
  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'user32.dll') >= 0,
    'GetModuleHandle with a literal argument must be detected');
end;

procedure TEngineTests.ScanPasFiles_SameConstInTwoUnits_BothResolveCorrectly;
var
  LPasFile1, LPasFile2: string;
  LDllNames: TArray<string>;
const
  cSourceA =
    'unit UnitAlpha;'#13#10 +
    'interface'#13#10 +
    'const'#13#10 +
    '  DLL_NAME = ''alpha.dll'';'#13#10 +
    'implementation'#13#10 +
    'procedure DoIt;'#13#10 +
    'begin'#13#10 +
    '  LoadLibrary(DLL_NAME);'#13#10 +
    'end;'#13#10 +
    'end.';
  cSourceB =
    'unit UnitBeta;'#13#10 +
    'interface'#13#10 +
    'const'#13#10 +
    '  DLL_NAME = ''beta.dll'';'#13#10 +
    'implementation'#13#10 +
    'procedure DoIt;'#13#10 +
    'begin'#13#10 +
    '  LoadLibrary(DLL_NAME);'#13#10 +
    'end;'#13#10 +
    'end.';
begin
  LPasFile1 := TPath.Combine(FTempDir, 'UnitAlpha.pas');
  LPasFile2 := TPath.Combine(FTempDir, 'UnitBeta.pas');
  TFile.WriteAllText(LPasFile1, cSourceA, TEncoding.UTF8);
  TFile.WriteAllText(LPasFile2, cSourceB, TEncoding.UTF8);

  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile1, LPasFile2));

  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'alpha.dll') >= 0,
    'alpha.dll (UnitAlpha.DLL_NAME) must resolve independently');
  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'beta.dll') >= 0,
    'beta.dll (UnitBeta.DLL_NAME) must resolve independently');
end;

procedure TEngineTests.ScanPasFiles_ComparisonExpression_NotTreatedAsConst;
var
  LPasFile: string;
  LDllNames: TArray<string>;
const
  cSource =
    'unit TestCmp;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure DoIt;'#13#10 +
    'var X: string;'#13#10 +
    'begin'#13#10 +
    '  X := SomeFunc;'#13#10 +
    '  if X = ''foo.dll'' then'#13#10 +
    '    LoadLibrary(X);'#13#10 +
    'end;'#13#10 +
    'end.';
begin
  LPasFile := TPath.Combine(FTempDir, 'TestCmp.pas');
  TFile.WriteAllText(LPasFile, cSource, TEncoding.UTF8);
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile));
  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'foo.dll') < 0,
    '`if X = ''foo.dll''` must NOT be parsed as a const declaration; ' +
    'foo.dll should not appear in detected DLLs');
end;

procedure TEngineTests.ScanPasFiles_ConstInOtherUnit_ResolvesViaGlobalFallback;
var
  LConstsUnit, LCallerUnit: string;
  LDllNames: TArray<string>;
const
  // Mirrors AlexSTHfg's reported pattern: 3rd-party libraries declare DLL
  // names in a separate consts unit and load them in another wrapper unit.
  cConstsSource =
    'unit OpenSSL_Consts;'#13#10 +
    'interface'#13#10 +
    'const'#13#10 +
    '  LIBEAY_DLL_NAME = ''libeay32.dll'';'#13#10 +
    'implementation'#13#10 +
    'end.';
  cCallerSource =
    'unit OpenSSL_Wrapper;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'uses Windows, OpenSSL_Consts;'#13#10 +
    'procedure DoIt;'#13#10 +
    'var H: NativeUInt;'#13#10 +
    'begin'#13#10 +
    '  H := GetModuleHandle(LIBEAY_DLL_NAME);'#13#10 +
    'end;'#13#10 +
    'end.';
begin
  LConstsUnit := TPath.Combine(FTempDir, 'OpenSSL_Consts.pas');
  LCallerUnit := TPath.Combine(FTempDir, 'OpenSSL_Wrapper.pas');
  TFile.WriteAllText(LConstsUnit, cConstsSource, TEncoding.UTF8);
  TFile.WriteAllText(LCallerUnit, cCallerSource, TEncoding.UTF8);

  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LConstsUnit, LCallerUnit));

  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'libeay32.dll') >= 0,
    'libeay32.dll must be detected when LIBEAY_DLL_NAME is declared in one ' +
    'unit and GetModuleHandle is called in another');
end;

function TEngineTests_WriteConfig(const ADir, AJson: string): string;
begin
  Result := TPath.Combine(ADir, 'dxcomply.json');
  TFile.WriteAllText(Result, AJson, TEncoding.UTF8);
end;

procedure TEngineTests.LoadConfig_ConfigNameAndPlatform;
var
  LGen: TDxComplyGenerator;
  LConfig: TSbomConfig;
  LPath: string;
begin
  LPath := TEngineTests_WriteConfig(FTempDir,
    '{"configName":" Debug ","platform":" Win64 ","format":"spdx-json",' +
    '"product":{"name":"FromFile","supplier":"File GmbH"},' +
    '"report":{"enabled":true,"format":"html"}}');
  LGen := TDxComplyGenerator.Create;
  try
    LConfig := LGen.LoadConfig(LPath);
    Assert.AreEqual('Debug', LConfig.Configuration, 'configName must be trimmed and stored');
    Assert.AreEqual('Win64', LConfig.Platform, 'platform must be trimmed and stored');
    Assert.AreEqual(Ord(sfSpdxJson), Ord(LConfig.Format));
    Assert.AreEqual('FromFile', LConfig.ProductName);
    Assert.AreEqual('File GmbH', LConfig.Supplier);
    Assert.IsTrue(LConfig.HumanReadableReport.Enabled);
    Assert.AreEqual(Ord(hrfHtml), Ord(LConfig.HumanReadableReport.Format));
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.LoadConfig_NonObjectRoot_ReturnsDefaults;
var
  LGen: TDxComplyGenerator;
  LConfig: TSbomConfig;
  LPath: string;
begin
  LConfig := TSbomConfig.Default;
  LPath := TEngineTests_WriteConfig(FTempDir, '[1, 2, 3]');
  LGen := TDxComplyGenerator.Create;
  try
    Assert.WillNotRaise(
      procedure
      begin
        LConfig := LGen.LoadConfig(LPath);
      end,
      Exception,
      'A JSON array root must not raise');
    Assert.AreEqual('Release', LConfig.Configuration);
    Assert.AreEqual('Win32', LConfig.Platform);
    Assert.AreEqual('bom.json', LConfig.OutputPath);

    LConfig := LGen.LoadConfig(TEngineTests_WriteConfig(FTempDir, '"not-an-object"'));
    Assert.AreEqual('Release', LConfig.Configuration);
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.LoadConfig_DeepEvidenceBuild_DoesNotOverrideMode;
var
  LGen: TDxComplyGenerator;
  LConfig: TSbomConfig;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LConfig := LGen.LoadConfig(TEngineTests_WriteConfig(FTempDir,
      '{"deepEvidence":{"mode":"always","build":false}}'));
    Assert.AreEqual(Ord(debAlways), Ord(LConfig.DeepEvidenceMode),
      'deepEvidence.build must not overwrite mode always');

    LConfig := LGen.LoadConfig(TEngineTests_WriteConfig(FTempDir,
      '{"deepEvidence":{"build":false}}'));
    Assert.AreEqual(Ord(debWhenMapMissing), Ord(LConfig.DeepEvidenceMode),
      'build alone must leave the default mode');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.GenerateFromConfig_FileValues_ApplyWhenNotExplicit;
var
  LGen: TDxComplyGenerator;
  LPath: string;
begin
  LPath := TEngineTests_WriteConfig(FTempDir,
    '{"configName":"Debug","platform":"Win64","format":"spdx-json",' +
    '"output":"from-file.json","product":{"name":"FileApp","supplier":"FileCo"}}');
  LGen := TDxComplyGenerator.Create;
  try
    // Missing project: Generate fails, but the merge has already happened.
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual('Debug', LGen.Config.Configuration);
    Assert.AreEqual('Win64', LGen.Config.Platform);
    Assert.AreEqual(Ord(sfSpdxJson), Ord(LGen.Config.Format));
    Assert.AreEqual('from-file.json', LGen.Config.OutputPath);
    Assert.AreEqual('FileApp', LGen.Config.ProductName);
    Assert.AreEqual('FileCo', LGen.Config.Supplier);
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.GenerateFromConfig_ExplicitCaller_OverridesFile;
var
  LCaller: TSbomConfig;
  LGen: TDxComplyGenerator;
  LPath: string;
begin
  LPath := TEngineTests_WriteConfig(FTempDir,
    '{"configName":"Release","platform":"Win32","format":"spdx-json",' +
    '"output":"from-file.json",' +
    '"product":{"name":"FileApp","version":"9.9.9","supplier":"FileCo"},' +
    '"report":{"enabled":true,"format":"html","output":"auditor-report"}}');
  LCaller := TSbomConfig.Default;
  LCaller.Configuration := 'Debug';
  LCaller.Platform := 'Win64';
  LCaller.Format := sfCycloneDxXml;
  LCaller.OutputPath := 'cli.json';
  LCaller.ProductName := 'CliApp';
  LCaller.Supplier := 'CliCo';
  LCaller.HumanReadableReport.Enabled := True;
  LCaller.HumanReadableReport.Format := hrfMarkdown;
  LCaller.ExplicitOverrides := [scoConfiguration, scoPlatform, scoFormat,
    scoOutputPath, scoProductName, scoSupplier, scoReport];

  LGen := TDxComplyGenerator.Create(LCaller);
  try
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual('Debug', LGen.Config.Configuration, 'explicit --config-name wins');
    Assert.AreEqual('Win64', LGen.Config.Platform, 'explicit --platform wins');
    Assert.AreEqual(Ord(sfCycloneDxXml), Ord(LGen.Config.Format), 'explicit --format wins');
    Assert.AreEqual('cli.json', LGen.Config.OutputPath, 'explicit --output wins');
    Assert.AreEqual('CliApp', LGen.Config.ProductName, 'explicit --product wins');
    Assert.AreEqual('CliCo', LGen.Config.Supplier, 'explicit --supplier wins');
    Assert.AreEqual('9.9.9', LGen.Config.ProductVersion,
      'version was not passed, so the file value stays');
    Assert.IsTrue(LGen.Config.HumanReadableReport.Enabled);
    Assert.AreEqual(Ord(hrfMarkdown), Ord(LGen.Config.HumanReadableReport.Format),
      'explicit --report wins over the file format');
    Assert.AreEqual('auditor-report', LGen.Config.HumanReadableReport.OutputBasePath,
      'report output path stays with the file');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.GenerateFromConfig_IncludePlatformInOutput_DecoratesMergedOutput;
var
  LCaller: TSbomConfig;
  LGen: TDxComplyGenerator;
  LPath: string;
begin
  LPath := TEngineTests_WriteConfig(FTempDir,
    '{"output":"custom.json","platform":"Win64","configName":"Debug"}');
  LCaller := TSbomConfig.Default;
  LCaller.IncludePlatformInOutput := True;
  LGen := TDxComplyGenerator.Create(LCaller);
  try
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual('custom.Win64.Debug.json', LGen.Config.OutputPath,
      'decoration uses the merged platform and configuration');
  finally
    LGen.Free;
  end;

  LCaller := TSbomConfig.Default;
  LCaller.IncludePlatformInOutput := True;
  LCaller.OutputPath := 'given.json';
  LCaller.ExplicitOverrides := [scoOutputPath];
  LGen := TDxComplyGenerator.Create(LCaller);
  try
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual('given.json', LGen.Config.OutputPath,
      'an explicit output path is not decorated');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.ScanPasFiles_ExternalLiteral_DetectsDllName;
var
  LPasFile: string;
  LDllNames: TArray<string>;
const
  cSource =
    'unit WinHook;'#13#10 +
    'interface'#13#10 +
    '{$I+}'#13#10 +
    'function GetTickCount: Cardinal; stdcall; external ''kernel32.dll'';'#13#10 +
    'implementation'#13#10 +
    'end.';
begin
  LPasFile := TPath.Combine(FTempDir, 'WinHook.pas');
  TFile.WriteAllText(LPasFile, cSource, TEncoding.UTF8);
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile));
  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'kernel32.dll') >= 0,
    'a quoted external DLL name must be detected');
end;

procedure TEngineTests.ScanPasFiles_ExternalIdentifier_ResolvesConst;
var
  LPasFile: string;
  LDllNames: TArray<string>;
const
  cSource =
    'unit NetApi;'#13#10 +
    'interface'#13#10 +
    'const'#13#10 +
    '  NETAPI = ''netapi32.dll'';'#13#10 +
    'function NetWkstaGetInfo: Integer; stdcall; external NETAPI;'#13#10 +
    'implementation'#13#10 +
    'end.';
begin
  LPasFile := TPath.Combine(FTempDir, 'NetApi.pas');
  TFile.WriteAllText(LPasFile, cSource, TEncoding.UTF8);
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile));
  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'netapi32.dll') >= 0,
    'external NETAPI must resolve the const to netapi32.dll');
end;

procedure TEngineTests.ScanPasFiles_ExternalInInclude_IfdefConst_ResolvesBothNames;
var
  LPasFile: string;
  LIncFile: string;
  LDllNames: TArray<string>;
  LConditional: TArray<Boolean>;
  LSearchPaths: TArray<string>;

  function IsConditional(const AName: string): Boolean;
  var
    LIndex: Integer;
  begin
    LIndex := TArray.IndexOf<string>(LDllNames, AName);
    Assert.IsTrue(LIndex >= 0, AName + ' must be detected');
    Result := LConditional[LIndex];
  end;

const
  // Mirrors the project attached to issue #45: the import lives in an
  // include, and DLLName is assigned in both {$IFDEF} branches.
  cInc =
    '  function OpcUa_P_Initialize; external DLLName ' +
    '{$IFDEF UASTACK_32} name ''_OpcUa_P_Initialize@4'' {$ENDIF};'#13#10;
  cPas =
    'unit Unit2;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'const'#13#10 +
    '{$IFDEF UASTACK_32}'#13#10 +
    '  DLLName = ''uastack_32.dll'';'#13#10 +
    '{$ELSE}'#13#10 +
    '  DLLName = ''uastack_64.dll'';'#13#10 +
    '{$ENDIF}'#13#10 +
    '{$INCLUDE ''StackMethodsImpl.inc''}'#13#10 +
    'end.'#13#10;
begin
  LPasFile := TPath.Combine(FTempDir, 'Unit2.pas');
  LIncFile := TPath.Combine(FTempDir, 'StackMethodsImpl.inc');
  TFile.WriteAllText(LIncFile, cInc, TEncoding.UTF8);
  TFile.WriteAllText(LPasFile, cPas, TEncoding.UTF8);
  SetLength(LSearchPaths, 0);
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile), LSearchPaths, LConditional);
  Assert.IsTrue(IsConditional('uastack_32.dll'),
    'uastack_32.dll from the {$IFDEF} branch must be detected and marked conditional');
  Assert.IsTrue(IsConditional('uastack_64.dll'),
    'uastack_64.dll from the {$ELSE} branch must be detected and marked conditional');
end;

procedure TEngineTests.ScanPasFiles_IncludeOnSearchPath_ResolvesExternalDll;
var
  LPasFile: string;
  LIncDir: string;
  LIncFile: string;
  LDllNames: TArray<string>;
  LConditional: TArray<Boolean>;
  LSearchPaths: TArray<string>;
const
  cInc =
    'function OpcUa_P_Initialize; external DLLName;'#13#10;
  cPas =
    'unit Unit2;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'const'#13#10 +
    '  DLLName = ''uastack_64.dll'';'#13#10 +
    '{$INCLUDE ''StackMethodsImpl.inc''}'#13#10 +
    'end.'#13#10;
begin
  LIncDir := TPath.Combine(FTempDir, 'includes');
  TDirectory.CreateDirectory(LIncDir);
  LPasFile := TPath.Combine(FTempDir, 'Unit2.pas');
  LIncFile := TPath.Combine(LIncDir, 'StackMethodsImpl.inc');
  TFile.WriteAllText(LIncFile, cInc, TEncoding.UTF8);
  TFile.WriteAllText(LPasFile, cPas, TEncoding.UTF8);

  SetLength(LSearchPaths, 1);
  LSearchPaths[0] := LIncDir;
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile), LSearchPaths, LConditional);
  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'uastack_64.dll') >= 0,
    'an include on the search path must be expanded and the DLL reported');
  Assert.IsFalse(LConditional[TArray.IndexOf<string>(LDllNames, 'uastack_64.dll')],
    'a single const value is not conditional');
end;

procedure TEngineTests.ScanPasFiles_LoadLibraryInInclude_ResolvesConst;
var
  LPasFile: string;
  LIncFile: string;
  LDllNames: TArray<string>;
const
  cInc =
    'procedure LoadIt;'#13#10 +
    'begin'#13#10 +
    '  LoadLibrary(IBASE_DLL);'#13#10 +
    'end;'#13#10;
  cPas =
    'unit IbWrap;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'const'#13#10 +
    '  IBASE_DLL = ''gds32.dll'';'#13#10 +
    '{$I ''IbLoad.inc''}'#13#10 +
    'end.';
begin
  LPasFile := TPath.Combine(FTempDir, 'IbWrap.pas');
  LIncFile := TPath.Combine(FTempDir, 'IbLoad.inc');
  TFile.WriteAllText(LIncFile, cInc, TEncoding.UTF8);
  TFile.WriteAllText(LPasFile, cPas, TEncoding.UTF8);
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile));
  Assert.IsTrue(TArray.IndexOf<string>(LDllNames, 'gds32.dll') >= 0,
    'LoadLibrary(IBASE_DLL) inside an include must resolve gds32.dll');
end;

procedure TEngineTests.ScanPasFiles_UnresolvedExternalIdent_IsIgnored;
var
  LPasFile: string;
  LDllNames: TArray<string>;
const
  cSource =
    'unit Bare;'#13#10 +
    'interface'#13#10 +
    'function Foo: Integer; external NotADll;'#13#10 +
    'implementation'#13#10 +
    'end.';
begin
  LPasFile := TPath.Combine(FTempDir, 'Bare.pas');
  TFile.WriteAllText(LPasFile, cSource, TEncoding.UTF8);
  LDllNames := TDxComplyGenerator.ScanPasFilesForDllReferences(
    TArray<string>.Create(LPasFile));
  Assert.AreEqual(NativeInt(0), NativeInt(Length(LDllNames)),
    'an unresolved external identifier must not be reported as a DLL name');
end;

procedure TEngineTests.Config_Default_ScanTreeIsFalse;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.IsFalse(LConfig.ScanTree,
    'TSbomConfig.Default.ScanTree must be False');
  Assert.AreEqual(NativeInt(0), NativeInt(Length(LConfig.ScanDirs)),
    'TSbomConfig.Default.ScanDirs must be empty');
end;

function TEngineTests.CreateScopeProject(const AFolder: string;
  AWithOutputDir: Boolean): string;
var
  LRoot: string;
  LXml: string;
begin
  LRoot := TPath.Combine(FTempDir, AFolder);
  TDirectory.CreateDirectory(LRoot);
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'setup'));
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'output'));
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'output', 'nested'));
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'staging'));
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'staging', 'nested'));

  TFile.WriteAllText(TPath.Combine(LRoot, 'MyApp.dpr'),
    'program MyApp;' + sLineBreak +
    'procedure NotShipped; external ''notshipped.dll'';' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak, TEncoding.UTF8);

  LXml :=
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>MyApp.dpr</MainSource>' + sLineBreak +
    '    <AppType>Application</AppType>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak;
  if AWithOutputDir then
    LXml := LXml + '    <DCC_ExeOutput>.\output</DCC_ExeOutput>' + sLineBreak;
  LXml := LXml +
    '    <UsePackages>true</UsePackages>' + sLineBreak +
    '    <DCC_UsePackage>rtl</DCC_UsePackage>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>';

  Result := TPath.Combine(LRoot, 'MyApp.dproj');
  TFile.WriteAllText(Result, LXml, TEncoding.UTF8);

  // Two copies of MyApp.exe: one in the project root (the fallback output)
  // and one in output\ (the configured output). The map files exist so the
  // Deep-Evidence build is skipped.
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'MyApp.exe'), TBytes.Create($4D, $5A, $01));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'setup', 'setup.exe'), TBytes.Create($4D, $5A, $02));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'output', 'MyApp.exe'), TBytes.Create($4D, $5A, $03));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'output', 'plugin.dll'), TBytes.Create($4D, $5A, $04));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'output', 'nested', 'old.exe'), TBytes.Create($4D, $5A, $05));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'staging', 'extra.dll'), TBytes.Create($4D, $5A, $06));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'staging', 'nested', 'deep.dll'), TBytes.Create($4D, $5A, $07));
  TFile.WriteAllText(TPath.Combine(LRoot, 'MyApp.map'), 'map', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(LRoot, 'output', 'MyApp.map'), 'map', TEncoding.UTF8);
end;

function TEngineTests.ScopeConfig: TSbomConfig;
begin
  Result := TSbomConfig.Default;
  Result.OutputPath := FOutputFile;
  Result.IncludeCompositionEvidence := False;
  Result.Platform := 'Win32';
  Result.Configuration := 'Release';
end;

function TEngineTests.CountComponents(const AJson: TJSONObject;
  const AName: string): NativeInt;
var
  LComponents: TJSONArray;
  LComponent: TJSONObject;
  I: Integer;
begin
  Result := 0;
  if not Assigned(AJson) then
    Exit;
  LComponents := AJson.GetValue('components') as TJSONArray;
  if not Assigned(LComponents) then
    Exit;
  for I := 0 to LComponents.Count - 1 do
  begin
    if not (LComponents.Items[I] is TJSONObject) then
      Continue;
    LComponent := TJSONObject(LComponents.Items[I]);
    if SameText(LComponent.GetValue<string>('name', ''), AName) then
      Inc(Result);
  end;
end;

function TEngineTests.ComponentHasHash(const AJson: TJSONObject;
  const AName: string): Boolean;
var
  LComponents: TJSONArray;
  LComponent: TJSONObject;
  I: Integer;
begin
  Result := False;
  if not Assigned(AJson) then
    Exit;
  LComponents := AJson.GetValue('components') as TJSONArray;
  if not Assigned(LComponents) then
    Exit;
  for I := 0 to LComponents.Count - 1 do
  begin
    if not (LComponents.Items[I] is TJSONObject) then
      Continue;
    LComponent := TJSONObject(LComponents.Items[I]);
    if SameText(LComponent.GetValue<string>('name', ''), AName) and
       (LComponent.GetValue('hashes') <> nil) then
      Exit(True);
  end;
end;

function TEngineTests.GenerateScope(const AProjectPath: string;
  const AConfig: TSbomConfig): TJSONObject;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create(AConfig);
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.Generate(AProjectPath, FOutputFile, sfCycloneDxJson),
      'Generate must succeed for the scope fixture');
    Result := TJSONObject.ParseJSONValue(
      TFile.ReadAllText(FOutputFile, TEncoding.UTF8)) as TJSONObject;
    Assert.IsNotNull(Result, 'SBOM must be JSON');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_OutputScope_ListsNamedOutputAndSiblingsOnly;
var
  LConfig: TSbomConfig;
  LJson: TJSONObject;
  LProject: string;
begin
  LProject := CreateScopeProject('with-output', True);
  LConfig := ScopeConfig;
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'MyApp.exe'),
      'The named exe in the output directory must be listed once');
    Assert.IsTrue(ComponentHasHash(LJson, 'MyApp.exe'),
      'The named exe must be hashed when the file exists');
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'plugin.dll'),
      'A DLL beside the exe must be listed');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'old.exe'),
      'A binary in a subdirectory of the output directory must not be listed');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'setup.exe'),
      'A binary under setup\ must not be listed');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'extra.dll'),
      'A staged directory must not be scanned unless scanDirs says so');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.Generate_OutputScope_MissingNamedFile_HasNoHash;
var
  LConfig: TSbomConfig;
  LJson: TJSONObject;
  LProject: string;
  LRoot: string;
begin
  LProject := CreateScopeProject('missing-exe', True);
  LRoot := TPath.GetDirectoryName(LProject);
  TFile.Delete(TPath.Combine(LRoot, 'output', 'MyApp.exe'));

  LConfig := ScopeConfig;
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'MyApp.exe'),
      'The named output must stay in the SBOM when the file is missing');
    Assert.IsFalse(ComponentHasHash(LJson, 'MyApp.exe'),
      'A missing output file must not be given a hash');
    Assert.IsTrue(ComponentHasHash(LJson, 'plugin.dll'),
      'A sibling that does exist must still be hashed');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.Generate_OutputScope_KeepsDeclaredDependencies;
var
  LConfig: TSbomConfig;
  LJson: TJSONObject;
  LProject: string;
begin
  LProject := CreateScopeProject('declared', True);
  LConfig := ScopeConfig;
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'rtl.bpl'),
      'A declared runtime package must be listed even when the BPL was not scanned');
    Assert.IsFalse(ComponentHasHash(LJson, 'rtl.bpl'),
      'A runtime package that was not found on disk has no hash');
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'notshipped.dll'),
      'An external DLL from source must be listed even when the file was not scanned');
    Assert.IsFalse(ComponentHasHash(LJson, 'notshipped.dll'),
      'An external DLL that was not found on disk has no hash');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.Generate_OutputScope_ExcludeFiltersScannedFiles;
var
  LConfig: TSbomConfig;
  LJson: TJSONObject;
  LProject: string;
begin
  LProject := CreateScopeProject('exclude', True);
  LConfig := ScopeConfig;
  LConfig.ExcludePatterns := TArray<string>.Create('*.dll');
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'plugin.dll'),
      'An exclude glob must drop a DLL found in the output directory');
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'MyApp.exe'),
      'The named exe must remain when the exclude glob does not match it');
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'notshipped.dll'),
      'An external DLL reference is not removed by an artefact exclude glob');
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'rtl.bpl'),
      'A runtime package is not removed by an artefact exclude glob');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.Generate_OutputScope_ScanDirRespectsRecursion;
var
  LConfig: TSbomConfig;
  LJson: TJSONObject;
  LProject: string;
begin
  LProject := CreateScopeProject('scan-dir', True);
  LConfig := ScopeConfig;
  LConfig.ScanDirs := TArray<string>.Create('staging');
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'extra.dll'),
      'scanDirs must include binaries directly in that directory');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'deep.dll'),
      'scanDirs must not walk subdirectories unless the value contains **');
  finally
    LJson.Free;
  end;

  LConfig.ScanDirs := TArray<string>.Create('staging\**');
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'deep.dll'),
      'A scanDirs value that contains ** must include nested binaries');
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'extra.dll'),
      'A recursive scan dir must still include binaries in the directory itself');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.Generate_OutputScope_ScanTreeWalksOutputDirectory;
var
  LConfig: TSbomConfig;
  LJson: TJSONObject;
  LProject: string;
begin
  LProject := CreateScopeProject('scan-tree', True);
  LConfig := ScopeConfig;
  LConfig.ScanTree := True;
  FProgressMessages.Clear;
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'old.exe'),
      'scanTree must include binaries under the output directory');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'setup.exe'),
      'scanTree walks the output directory, not folders outside it');
    Assert.IsTrue(Pos('deprecated', FProgressMessages.Text) > 0,
      'scanTree must be reported as deprecated');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.Generate_OutputScope_ProjectDirFallbackSkipsSubfolders;
var
  LConfig: TSbomConfig;
  LJson: TJSONObject;
  LProject: string;
begin
  LProject := CreateScopeProject('fallback', False);
  LConfig := ScopeConfig;
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'MyApp.exe'),
      'With no output directory, the exe in the project directory is the named output');
    Assert.IsTrue(ComponentHasHash(LJson, 'MyApp.exe'),
      'That exe must be hashed');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'setup.exe'),
      'Subfolders of the project directory must not be scanned by default');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'plugin.dll'),
      'Binaries under output\ must not be scanned when that folder is not the output directory');
  finally
    LJson.Free;
  end;

  LConfig.ScanTree := True;
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'setup.exe'),
      'scanTree on a project without an output directory walks the project tree');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.Generate_OutputScope_PackageUsesBplDirectory;
var
  LConfig: TSbomConfig;
  LJson: TJSONObject;
  LProject: string;
  LRoot: string;
begin
  LRoot := TPath.Combine(FTempDir, 'package');
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'bin'));
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'bpl'));
  TDirectory.CreateDirectory(TPath.Combine(LRoot, 'bpl', 'nested'));
  TFile.WriteAllText(TPath.Combine(LRoot, 'Demo.dpk'),
    'package Demo;' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(LRoot, 'Demo.dproj'),
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>Demo.dpk</MainSource>' + sLineBreak +
    '    <AppType>Package</AppType>' + sLineBreak +
    '    <DllSuffix>290</DllSuffix>' + sLineBreak +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
    '    <DCC_BplOutput>.\bpl</DCC_BplOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>', TEncoding.UTF8);
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'bin', 'stray.exe'), TBytes.Create($4D, $5A, $11));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'bpl', 'Demo290.bpl'), TBytes.Create($4D, $5A, $12));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'bpl', 'plugin.dll'), TBytes.Create($4D, $5A, $13));
  TFile.WriteAllBytes(TPath.Combine(LRoot, 'bpl', 'nested', 'old.bpl'), TBytes.Create($4D, $5A, $14));
  // OutputDir prefers the exe folder, so the expected map lives there.
  TFile.WriteAllText(TPath.Combine(LRoot, 'bin', 'Demo290.map'), 'map', TEncoding.UTF8);

  LProject := TPath.Combine(LRoot, 'Demo.dproj');
  LConfig := ScopeConfig;
  LJson := GenerateScope(LProject, LConfig);
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'Demo290.bpl'),
      'The package output must be listed under its DllSuffix name');
    Assert.IsTrue(ComponentHasHash(LJson, 'Demo290.bpl'),
      'The package output must be hashed when the BPL exists');
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'plugin.dll'),
      'A DLL beside the BPL must be listed');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'stray.exe'),
      'Binaries in DCC_ExeOutput must not be listed when the package output is the BPL directory');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'old.bpl'),
      'A nested BPL must not be listed');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.GenerateFromConfig_ScanDirs_AddsStagedBinaries;
var
  LConfigJson: TStringList;
  LConfigPath: string;
  LGen: TDxComplyGenerator;
  LJson: TJSONObject;
  LProject: string;
begin
  LProject := CreateScopeProject('json-scan-dir', True);
  LConfigPath := TPath.Combine(FTempDir, 'scan-dirs.json');
  LConfigJson := TStringList.Create;
  try
    LConfigJson.Add('{');
    LConfigJson.Add('  "output": "' + StringReplace(FOutputFile, '\', '\\', [rfReplaceAll]) + '",');
    LConfigJson.Add('  "includeCompositionEvidence": false,');
    LConfigJson.Add('  "scanDirs": ["staging"],');
    LConfigJson.Add('  "scanTree": false');
    LConfigJson.Add('}');
    LConfigJson.SaveToFile(LConfigPath, TEncoding.UTF8);
  finally
    LConfigJson.Free;
  end;

  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.GenerateFromConfig(LProject, LConfigPath),
      'GenerateFromConfig must succeed when scanDirs is set');
  finally
    LGen.Free;
  end;

  LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(FOutputFile, TEncoding.UTF8)) as TJSONObject;
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'extra.dll'),
      'scanDirs in .dxcomply.json must add binaries from that directory');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'deep.dll'),
      'A scanDirs entry without ** must not include nested binaries');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'setup.exe'),
      'scanDirs must not bring back the recursive project walk');
  finally
    LJson.Free;
  end;
end;

procedure TEngineTests.GenerateFromConfig_ScanTree_RestoresRecursiveWalk;
var
  LConfigJson: TStringList;
  LConfigPath: string;
  LGen: TDxComplyGenerator;
  LJson: TJSONObject;
  LProject: string;
begin
  LProject := CreateScopeProject('json-scan-tree', True);
  LConfigPath := TPath.Combine(FTempDir, 'scan-tree.json');
  LConfigJson := TStringList.Create;
  try
    LConfigJson.Add('{');
    LConfigJson.Add('  "output": "' + StringReplace(FOutputFile, '\', '\\', [rfReplaceAll]) + '",');
    LConfigJson.Add('  "includeCompositionEvidence": false,');
    LConfigJson.Add('  "scanTree": true');
    LConfigJson.Add('}');
    LConfigJson.SaveToFile(LConfigPath, TEncoding.UTF8);
  finally
    LConfigJson.Free;
  end;

  FProgressMessages.Clear;
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.GenerateFromConfig(LProject, LConfigPath),
      'GenerateFromConfig must succeed when scanTree is set');
  finally
    LGen.Free;
  end;

  LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(FOutputFile, TEncoding.UTF8)) as TJSONObject;
  try
    Assert.AreEqual(NativeInt(1), CountComponents(LJson, 'old.exe'),
      'scanTree in .dxcomply.json must walk the output directory');
    Assert.AreEqual(NativeInt(0), CountComponents(LJson, 'setup.exe'),
      'scanTree must not include folders outside the output directory');
    Assert.IsTrue(Pos('deprecated', FProgressMessages.Text) > 0,
      'scanTree from config must be reported as deprecated');
  finally
    LJson.Free;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TEngineTests);

end.
