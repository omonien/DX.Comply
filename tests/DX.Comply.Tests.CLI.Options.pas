/// <summary>
/// DX.Comply.Tests.CLI.Options
/// DUnitX tests for TCliOptions CLI argument parsing.
/// </summary>
///
/// <remarks>
/// Covers default-value contracts and the ToSbomConfig mapping.
/// Full flag-parsing tests (--verbose, --no-composition-evidence) require
/// ParamStr which cannot be overridden in-process; those code paths are
/// covered by the integration smoke-tests in the engine fixture.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.CLI.Options;

interface

uses
  System.SysUtils,
  System.IOUtils,
  DUnitX.TestFramework,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf,
  DX.Comply.CLI.Options,
  DX.Comply.VersionInfo;

type
  /// <summary>
  /// DUnitX test fixture for TCliOptions.
  /// </summary>
  [TestFixture]
  TCliOptionsTests = class
  public
    // ---- Default values -------------------------------------------------------

    /// <summary>A freshly created TCliOptions must have Verbose = False.</summary>
    [Test]
    procedure Create_Default_VerboseIsFalse;

    /// <summary>A freshly created TCliOptions must have NoCompositionEvidence = False.</summary>
    [Test]
    procedure Create_Default_NoCompositionEvidenceIsFalse;

    // ---- ToSbomConfig mapping ------------------------------------------------

    /// <summary>
    /// ToSbomConfig on a default TCliOptions must set
    /// IncludeCompositionEvidence = True (inverse of NoCompositionEvidence).
    /// </summary>
    [Test]
    procedure ToSbomConfig_Default_IncludeCompositionEvidenceIsTrue;

    /// <summary>ToSbomConfig must propagate the default output path.</summary>
    [Test]
    procedure ToSbomConfig_Default_OutputPathIsBomJson;

    /// <summary>ToSbomConfig must propagate the default platform.</summary>
    [Test]
    procedure ToSbomConfig_Default_PlatformIsWin32;

    /// <summary>ToSbomConfig must propagate the default configuration.</summary>
    [Test]
    procedure ToSbomConfig_Default_ConfigurationIsRelease;

    // ---- Executable name in help and hints (issue #102) ---------------------

    /// <summary>A renamed copy shows its own file name.</summary>
    [Test]
    procedure ExecutableName_FullPath_ReturnsFileName;

    /// <summary>The standard install path yields dxcomply.exe.</summary>
    [Test]
    procedure ExecutableName_InstallerCopy_ReturnsDxcomplyExe;

    /// <summary>A path ending in a separator falls back to cDefaultExeName.</summary>
    [Test]
    procedure ExecutableName_NoFileName_FallsBackToDefault;

    /// <summary>Without a path, the running test executable's name is used.</summary>
    [Test]
    procedure ExecutableName_Empty_UsesParamStr0;

    /// <summary>UsageHint names the executable instead of a fixed dxcomply.</summary>
    [Test]
    procedure UsageHint_ContainsExecutableName;

    /// <summary>VersionLine uses the module version resource, not a literal (issue #41).</summary>
    [Test]
    procedure VersionLine_UsesModuleVersion;

    // ---- Filename sanitisation (issue #25 security follow-up) ---------------

    /// <summary>Backslashes must be stripped from filename segments.</summary>
    [Test]
    procedure SanitizeForFilename_StripsBackslash;

    /// <summary>Forward slashes must be stripped from filename segments.</summary>
    [Test]
    procedure SanitizeForFilename_StripsForwardSlash;

    /// <summary>Parent-directory '..' sequences must be reduced to safe chars.</summary>
    [Test]
    procedure SanitizeForFilename_StripsDoubleDot;

    /// <summary>Alphanumeric, hyphen and underscore must be preserved.</summary>
    [Test]
    procedure SanitizeForFilename_PreservesAllowedChars;

    /// <summary>
    /// --config-name, --platform, --product, --supplier and --report mark
    /// those fields explicit so a config file cannot replace them (issue #50).
    /// </summary>
    [Test]
    procedure Parse_ExplicitFlags_AreRecorded;
    /// <summary>--strict and --strict=false set StrictMode. Issue #111.</summary>
    [Test]
    procedure Parse_Strict_SetsStrictMode;
    /// <summary>The strict key loads from .dxcomply.json, and --strict=false wins. Issue #111.</summary>
    [Test]
    procedure Config_Strict_LoadsAndMerges;
    /// <summary>--spdx-version=3.0.1 selects SPDX 3.0.1 for spdx-json. Issue #108.</summary>
    [Test]
    procedure Parse_SpdxVersion_SelectsSpdx3;
    /// <summary>The spdxVersion key loads from .dxcomply.json, and the CLI wins. Issue #108.</summary>
    [Test]
    procedure Config_SpdxVersion_LoadsAndMerges;
    /// <summary>--report-content selects the report sections, default all. Issue #126.</summary>
    [Test]
    procedure Parse_ReportContent_SetsContent;
    /// <summary>The report.content key loads from .dxcomply.json, and the CLI wins. Issue #126.</summary>
    [Test]
    procedure Config_ReportContent_LoadsAndMerges;
    /// <summary>--report-group-by-folder and report.groupByFolder. Issue #132.</summary>
    [Test]
    procedure ReportGroupByFolder_ParseAndConfig;

    /// <summary>Defaults are not treated as explicit overrides.</summary>
    [Test]
    procedure Parse_OmittedFlags_AreNotExplicit;

    /// <summary>
    /// Explicit CLI values win over .dxcomply.json. Omitted ones keep the file.
    /// </summary>
    [Test]
    procedure Parse_ExplicitFlags_WinOverConfigFile;

    /// <summary>--scan-dir can be passed more than once.</summary>
    [Test]
    procedure Parse_ScanDir_IsRepeatable;

    /// <summary>--scan-tree sets the deprecated recursive walk.</summary>
    [Test]
    procedure Parse_ScanTree_SetsFlag;

    /// <summary>--scan-tree=false clears the flag.</summary>
    [Test]
    procedure Parse_ScanTreeFalse_ClearsFlag;

    /// <summary>An unrecognised --scan-tree value is a parse error.</summary>
    [Test]
    procedure Parse_ScanTreeInvalid_ReturnsFalse;

    /// <summary>ToSbomConfig copies scan directories and the scanTree flag.</summary>
    [Test]
    procedure ToSbomConfig_CopiesScanOptions;

    /// <summary>--delphi7-root is copied into the engine configuration.</summary>
    [Test]
    procedure Parse_Delphi7Root_CopiesToConfig;

    /// <summary>--bds-version is copied into the engine configuration.</summary>
    [Test]
    procedure Parse_BdsVersion_CopiesToConfig;

    /// <summary>The built-in Win32 and Release defaults are not explicit.</summary>
    [Test]
    procedure Parse_DefaultTarget_IsNotExplicit;

    /// <summary>--platform and --config-name mark the target as explicitly set.</summary>
    [Test]
    procedure Parse_ConfigName_MarksTargetExplicit;

    /// <summary>
    /// --supplier-url and --licence are copied into the engine configuration
    /// and marked explicit. Surrounding spaces are trimmed.
    /// </summary>
    [Test]
    procedure Parse_SupplierUrlAndLicence_AreRecorded;

    /// <summary>
    /// --supplier-url and --licence without '=' fail like --supplier.
    /// An empty value after '=' is accepted and stays explicit.
    /// </summary>
    [Test]
    procedure Parse_SupplierUrlAndLicence_WithoutValue_MatchSupplier;

    /// <summary>
    /// product.supplierUrl and product.licence stay when the flags are omitted.
    /// An explicit flag, including an empty one, replaces the file.
    /// </summary>
    [Test]
    procedure Parse_SupplierUrlAndLicence_WinOverConfigFile;

    /// <summary>
    /// A relative config file in the working directory is used, even when
    /// the project folder has another file of the same name.
    /// </summary>
    [Test]
    procedure ResolveConfigPath_FoundInWorkingDirectory;

    /// <summary>
    /// When the working directory has no config file, the file next to
    /// --project is used.
    /// </summary>
    [Test]
    procedure ResolveConfigPath_FoundNextToProject;

    /// <summary>
    /// When neither directory has the file, both paths are reported and
    /// the folder of dxcomply.exe is not one of them.
    /// </summary>
    [Test]
    procedure ResolveConfigPath_NeitherPresent;

    /// <summary>
    /// An absolute --config path is used as given. A missing absolute path
    /// is not replaced with a file in the project folder.
    /// </summary>
    [Test]
    procedure ResolveConfigPath_AbsolutePath;

    /// <summary>
    /// A relative path with a subdirectory is applied to the working
    /// directory and then to the project folder.
    /// </summary>
    [Test]
    procedure ResolveConfigPath_RelativeSubfolder;

    /// <summary>
    /// Without --config the default name is .dxcomply.json, and that file
    /// is found next to the project when the working directory has none.
    /// </summary>
    [Test]
    procedure ResolveConfigPath_DefaultWithoutConfigFlag;

    /// <summary>
    /// The config file exists only next to the project, the process
    /// directory is somewhere else, and LoadConfig reads the header values.
    /// </summary>
    [Test]
    procedure ResolveConfigPath_ProjectFolder_LoadsValuesWhenCwdDiffers;

    /// <summary>
    /// With --ci, a missing config file produces a warning that lists the
    /// paths that were checked. Without --ci, or when a file was found,
    /// there is no warning.
    /// </summary>
    [Test]
    procedure ConfigFileWarning_ListsTriedPathsWhenMissing;

    /// <summary>
    /// Help text says that square brackets mark an optional value, and it
    /// describes the --config lookup order.
    /// </summary>
    [Test]
    procedure HelpText_DescribesOptionalBrackets;
  end;

implementation

uses
  Winapi.Windows;

{ TCliOptionsTests }

procedure TCliOptionsTests.Create_Default_VerboseIsFalse;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Verbose,
      'Verbose must default to False');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Create_Default_NoCompositionEvidenceIsFalse;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.NoCompositionEvidence,
      'NoCompositionEvidence must default to False');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.ToSbomConfig_Default_IncludeCompositionEvidenceIsTrue;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    // Do not call Parse — test mapping contract with default field values.
    LConfig := LOptions.ToSbomConfig;
    Assert.IsTrue(LConfig.IncludeCompositionEvidence,
      'ToSbomConfig must set IncludeCompositionEvidence = True when ' +
      'NoCompositionEvidence is False');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.ToSbomConfig_Default_OutputPathIsBomJson;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('bom.json', LConfig.OutputPath,
      'Default output path must be bom.json');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.ToSbomConfig_Default_PlatformIsWin32;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('Win32', LConfig.Platform,
      'Default platform must be Win32');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.ToSbomConfig_Default_ConfigurationIsRelease;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('Release', LConfig.Configuration,
      'Default configuration must be Release');
  finally
    LOptions.Free;
  end;
end;

// ---- Filename sanitisation --------------------------------------------------

procedure TCliOptionsTests.ExecutableName_FullPath_ReturnsFileName;
begin
  Assert.AreEqual('dxcomply-2.1.exe',
    TCliOptions.ExecutableName('C:\Tools\DX.Comply\dxcomply-2.1.exe'));
end;

procedure TCliOptionsTests.ExecutableName_InstallerCopy_ReturnsDxcomplyExe;
begin
  Assert.AreEqual('dxcomply.exe',
    TCliOptions.ExecutableName('C:\Program Files\DX.Comply\bin\dxcomply.exe'));
end;

procedure TCliOptionsTests.ExecutableName_NoFileName_FallsBackToDefault;
begin
  Assert.AreEqual(cDefaultExeName, TCliOptions.ExecutableName('C:\Tools\'));
end;

procedure TCliOptionsTests.ExecutableName_Empty_UsesParamStr0;
begin
  Assert.AreEqual(ExtractFileName(ParamStr(0)), TCliOptions.ExecutableName);
end;

procedure TCliOptionsTests.VersionLine_UsesModuleVersion;
begin
  Assert.AreEqual('DX.Comply v' + GetDxComplyToolVersion, TCliOptions.VersionLine);
  Assert.IsTrue(GetDxComplyToolVersion <> '', 'The version part must not be empty');
end;

procedure TCliOptionsTests.UsageHint_ContainsExecutableName;
begin
  Assert.AreEqual('Run dxcomply.exe --help for usage.',
    TCliOptions.UsageHint('C:\Tools\dxcomply.exe'));
end;

procedure TCliOptionsTests.SanitizeForFilename_StripsBackslash;
begin
  // SanitizeForFilename is a strip-only whitelist: every non-safe char
  // is removed but the remaining safe chars from later segments are
  // preserved (same semantics as SanitizeForFilename_StripsForwardSlash).
  Assert.AreEqual('Win32evil', TCliOptions.SanitizeForFilename('Win32\..\evil'),
    'Backslashes and dots must be stripped — only safe chars survive');
end;

procedure TCliOptionsTests.SanitizeForFilename_StripsForwardSlash;
begin
  Assert.AreEqual('Win32etc', TCliOptions.SanitizeForFilename('Win32/etc'),
    'Forward slashes must be stripped');
end;

procedure TCliOptionsTests.SanitizeForFilename_StripsDoubleDot;
begin
  Assert.AreEqual('abc', TCliOptions.SanitizeForFilename('..abc..'),
    'Period characters must be stripped');
end;

procedure TCliOptionsTests.SanitizeForFilename_PreservesAllowedChars;
begin
  Assert.AreEqual('Release-1_0', TCliOptions.SanitizeForFilename('Release-1_0'),
    'Alphanumeric, hyphen and underscore must be preserved');
end;

procedure TCliOptionsTests.Parse_ExplicitFlags_AreRecorded;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse([
      '--project=App.dproj',
      '--config-name=Debug',
      '--platform=Win64',
      '--product=CliApp',
      '--supplier=CliCo',
      '--report=html']));
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('Debug', LConfig.Configuration);
    Assert.AreEqual('Win64', LConfig.Platform);
    Assert.AreEqual('CliApp', LConfig.ProductName);
    Assert.AreEqual('CliCo', LConfig.Supplier);
    Assert.IsTrue(LConfig.HumanReadableReport.Enabled);
    Assert.AreEqual(Ord(hrfHtml), Ord(LConfig.HumanReadableReport.Format));
    Assert.IsTrue(scoConfiguration in LConfig.ExplicitOverrides);
    Assert.IsTrue(scoPlatform in LConfig.ExplicitOverrides);
    Assert.IsTrue(scoProductName in LConfig.ExplicitOverrides);
    Assert.IsTrue(scoSupplier in LConfig.ExplicitOverrides);
    Assert.IsTrue(scoReport in LConfig.ExplicitOverrides);
    Assert.IsFalse(scoFormat in LConfig.ExplicitOverrides,
      '--format was not passed, so the file may still set the format');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_OmittedFlags_AreNotExplicit;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj']));
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('Release', LConfig.Configuration);
    Assert.AreEqual('Win32', LConfig.Platform);
    Assert.IsFalse(scoConfiguration in LConfig.ExplicitOverrides);
    Assert.IsFalse(scoPlatform in LConfig.ExplicitOverrides);
    Assert.IsFalse(scoProductName in LConfig.ExplicitOverrides);
    Assert.IsFalse(scoSupplier in LConfig.ExplicitOverrides);
    Assert.IsFalse(scoReport in LConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_ExplicitFlags_WinOverConfigFile;
var
  LOptions: TCliOptions;
  LGen: TDxComplyGenerator;
  LPath: string;
begin
  LPath := TPath.Combine(TPath.GetTempPath, 'dxcomply-cli-precedence.json');
  TFile.WriteAllText(LPath,
    '{"configName":"Release","platform":"Win32","format":"spdx-json",' +
    '"product":{"name":"FileApp","supplier":"FileCo"},' +
    '"report":{"enabled":true,"format":"html","output":"auditor-report"}}',
    TEncoding.UTF8);
  LOptions := TCliOptions.Create;
  LGen := nil;
  try
    Assert.IsTrue(LOptions.Parse([
      '--project=App.dproj',
      '--config-name=Debug',
      '--supplier=CliCo',
      '--report=markdown']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual('Debug', LGen.Config.Configuration);
    Assert.AreEqual('Win32', LGen.Config.Platform,
      'platform was not passed, so the file value stays');
    Assert.AreEqual(Ord(sfSpdxJson), Ord(LGen.Config.Format),
      'format was not passed, so the file value stays');
    Assert.AreEqual('FileApp', LGen.Config.ProductName);
    Assert.AreEqual('CliCo', LGen.Config.Supplier);
    Assert.IsTrue(LGen.Config.HumanReadableReport.Enabled);
    Assert.AreEqual(Ord(hrfMarkdown), Ord(LGen.Config.HumanReadableReport.Format));
    Assert.AreEqual('auditor-report', LGen.Config.HumanReadableReport.OutputBasePath);
  finally
    LGen.Free;
    LOptions.Free;
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
  end;
end;

procedure TCliOptionsTests.Parse_ScanDir_IsRepeatable;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj',
      '--scan-dir=redist',
      '--scan-dir=plugins\**')),
      'Repeatable --scan-dir values must parse');
    Assert.AreEqual(NativeInt(2), NativeInt(Length(LOptions.ScanDirs)),
      'Both --scan-dir values must be kept');
    Assert.AreEqual('redist', LOptions.ScanDirs[0]);
    Assert.AreEqual('plugins\**', LOptions.ScanDirs[1]);
    Assert.IsFalse(LOptions.ScanTree,
      '--scan-dir must not turn on the deprecated tree walk');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_ScanTree_SetsFlag;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--scan-tree')),
      '--scan-tree must parse');
    Assert.IsTrue(LOptions.ScanTree, '--scan-tree must enable the recursive walk');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_ScanTreeFalse_ClearsFlag;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--scan-tree=false')),
      '--scan-tree=false must parse');
    Assert.IsFalse(LOptions.ScanTree, '--scan-tree=false must leave the walk off');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_ScanTreeInvalid_ReturnsFalse;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--scan-tree=maybe')),
      'An invalid --scan-tree value must fail parsing');
    Assert.IsTrue(Pos('scan-tree', LOptions.ParseError) > 0,
      'The parse error must name --scan-tree');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.ToSbomConfig_CopiesScanOptions;
var
  LConfig: TSbomConfig;
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--scan-dir=redist', '--scan-tree')),
      'Scan options must parse before they can be copied');
    LConfig := LOptions.ToSbomConfig;
    Assert.IsTrue(LConfig.ScanTree, 'ToSbomConfig must copy scanTree');
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LConfig.ScanDirs)),
      'ToSbomConfig must copy scan directories');
    Assert.AreEqual('redist', LConfig.ScanDirs[0]);
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_Delphi7Root_CopiesToConfig;
var
  LConfig: TSbomConfig;
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dpr', '--delphi7-root=C:\Delphi7')),
      '--delphi7-root must parse');
    Assert.AreEqual('C:\Delphi7', LOptions.Delphi7Root);
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('C:\Delphi7', LConfig.Delphi7Root,
      'ToSbomConfig must copy the Delphi 7 root');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_BdsVersion_CopiesToConfig;
var
  LConfig: TSbomConfig;
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create('--project=App.dproj', '--bds-version=23.0')),
      '--bds-version must parse');
    Assert.AreEqual('23.0', LOptions.BdsVersion);
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('23.0', LConfig.BdsVersion, 'ToSbomConfig must copy the BDS version');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_DefaultTarget_IsNotExplicit;
var
  LConfig: TSbomConfig;
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create('--project=App.dpr')),
      'A project-only command line must parse');
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('Win32', LConfig.Platform);
    Assert.AreEqual('Release', LConfig.Configuration);
    Assert.IsFalse(LConfig.PlatformExplicit,
      'The built-in Win32 default must not count as --platform');
    Assert.IsFalse(LConfig.ConfigurationExplicit,
      'The built-in Release default must not count as --config-name');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_ConfigName_MarksTargetExplicit;
var
  LConfig: TSbomConfig;
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dpr', '--platform=Win64', '--config-name=Release')),
      '--platform and --config-name must parse');
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('Win64', LConfig.Platform);
    Assert.AreEqual('Release', LConfig.Configuration);
    Assert.IsTrue(LConfig.PlatformExplicit);
    Assert.IsTrue(LConfig.ConfigurationExplicit,
      'An explicit Release must still count as set by the user');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_SupplierUrlAndLicence_AreRecorded;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse([
      '--project=App.dproj',
      '--supplier-url= https://acme.example ',
      '--licence= Apache-2.0 OR MIT ']));
    Assert.AreEqual('https://acme.example', LOptions.SupplierUrl);
    Assert.AreEqual('Apache-2.0 OR MIT', LOptions.Licence);
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('https://acme.example', LConfig.SupplierUrl);
    Assert.AreEqual('Apache-2.0 OR MIT', LConfig.Licence);
    Assert.IsTrue(scoSupplierUrl in LConfig.ExplicitOverrides);
    Assert.IsTrue(scoLicence in LConfig.ExplicitOverrides);
    Assert.IsFalse(scoSupplier in LConfig.ExplicitOverrides,
      '--supplier was not passed, so the file may still set the supplier name');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_SupplierUrlAndLicence_WithoutValue_MatchSupplier;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
  LSupplierError: string;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--project=App.dproj', '--supplier']),
      '--supplier without a value must fail');
    LSupplierError := LOptions.ParseError;
    Assert.AreEqual('Unknown option: --supplier', LSupplierError);
  finally
    LOptions.Free;
  end;

  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--project=App.dproj', '--supplier-url']));
    Assert.AreEqual(StringReplace(LSupplierError, '--supplier', '--supplier-url', []),
      LOptions.ParseError);
  finally
    LOptions.Free;
  end;

  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--project=App.dproj', '--licence']));
    Assert.AreEqual(StringReplace(LSupplierError, '--supplier', '--licence', []),
      LOptions.ParseError);
  finally
    LOptions.Free;
  end;

  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse([
      '--project=App.dproj',
      '--supplier=',
      '--supplier-url=',
      '--licence=']),
      'An empty value after = must parse, the same as --supplier=');
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('', LConfig.Supplier);
    Assert.AreEqual('', LConfig.SupplierUrl);
    Assert.AreEqual('', LConfig.Licence);
    Assert.IsTrue(scoSupplier in LConfig.ExplicitOverrides);
    Assert.IsTrue(scoSupplierUrl in LConfig.ExplicitOverrides);
    Assert.IsTrue(scoLicence in LConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_SupplierUrlAndLicence_WinOverConfigFile;
var
  LOptions: TCliOptions;
  LGen: TDxComplyGenerator;
  LPath: string;
begin
  LPath := TPath.Combine(TPath.GetTempPath, 'dxcomply-cli-supplier-licence.json');
  TFile.WriteAllText(LPath,
    '{"product":{"supplierUrl":"https://file.example","licence":"Apache-2.0"}}',
    TEncoding.UTF8);
  LOptions := nil;
  LGen := nil;
  try
    LOptions := TCliOptions.Create;
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual('https://file.example', LGen.Config.SupplierUrl,
      'An omitted --supplier-url keeps product.supplierUrl');
    Assert.AreEqual('Apache-2.0', LGen.Config.Licence,
      'An omitted --licence keeps product.licence');
    Assert.IsFalse(scoSupplierUrl in LGen.Config.ExplicitOverrides);
    Assert.IsFalse(scoLicence in LGen.Config.ExplicitOverrides);
    LGen.Free;
    LGen := nil;
    LOptions.Free;
    LOptions := nil;

    LOptions := TCliOptions.Create;
    Assert.IsTrue(LOptions.Parse([
      '--project=App.dproj',
      '--supplier-url=https://cli.example',
      '--licence=MIT']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual('https://cli.example', LGen.Config.SupplierUrl);
    Assert.AreEqual('MIT', LGen.Config.Licence);
    LGen.Free;
    LGen := nil;
    LOptions.Free;
    LOptions := nil;

    LOptions := TCliOptions.Create;
    Assert.IsTrue(LOptions.Parse([
      '--project=App.dproj',
      '--supplier-url=',
      '--licence=']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual('', LGen.Config.SupplierUrl,
      'An empty --supplier-url replaces the file');
    Assert.AreEqual('', LGen.Config.Licence,
      'An empty --licence replaces the file');
    Assert.IsTrue(scoSupplierUrl in LGen.Config.ExplicitOverrides);
    Assert.IsTrue(scoLicence in LGen.Config.ExplicitOverrides);
  finally
    LGen.Free;
    LOptions.Free;
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
  end;
end;

procedure TCliOptionsTests.Parse_Strict_SetsStrictMode;
begin
  var LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj']));
    Assert.IsFalse(LOptions.ToSbomConfig.StrictMode);
    Assert.IsFalse(scoStrictMode in LOptions.ToSbomConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--strict']));
    Assert.IsTrue(LOptions.ToSbomConfig.StrictMode);
    Assert.IsTrue(scoStrictMode in LOptions.ToSbomConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--strict=false']));
    Assert.IsFalse(LOptions.ToSbomConfig.StrictMode);
    Assert.IsTrue(scoStrictMode in LOptions.ToSbomConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--project=App.dproj', '--strict=maybe']));
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Parse_ReportContent_SetsContent;
begin
  var LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj']));
    Assert.AreEqual(NativeInt(Ord(hrcAll)), NativeInt(Ord(LOptions.ToSbomConfig.HumanReadableReport.Content)));
    Assert.IsFalse(scoReportContent in LOptions.ToSbomConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--report', '--report-content=Units']));
    Assert.AreEqual(NativeInt(Ord(hrcUnits)), NativeInt(Ord(LOptions.ToSbomConfig.HumanReadableReport.Content)));
    Assert.IsTrue(scoReportContent in LOptions.ToSbomConfig.ExplicitOverrides);
    Assert.IsTrue(LOptions.ToSbomConfig.HumanReadableReport.Enabled);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--report-content=overview']));
    Assert.AreEqual(NativeInt(Ord(hrcOverview)), NativeInt(Ord(LOptions.ToSbomConfig.HumanReadableReport.Content)));
    Assert.IsFalse(LOptions.ToSbomConfig.HumanReadableReport.Enabled,
      '--report-content alone does not turn reports on');
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--project=App.dproj', '--report-content=hashes']));
    Assert.IsTrue(Pos('--report-content', LOptions.ParseError) > 0);
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.ReportGroupByFolder_ParseAndConfig;
begin
  var LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj']));
    Assert.IsFalse(LOptions.ToSbomConfig.HumanReadableReport.GroupByFolder);
    Assert.IsFalse(scoReportGroupByFolder in LOptions.ToSbomConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--report-group-by-folder']));
    Assert.IsTrue(LOptions.ToSbomConfig.HumanReadableReport.GroupByFolder);
    Assert.IsTrue(scoReportGroupByFolder in LOptions.ToSbomConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--project=App.dproj', '--report-group-by-folder=maybe']));
    Assert.IsTrue(Pos('--report-group-by-folder', LOptions.ParseError) > 0);
  finally
    LOptions.Free;
  end;

  var LPath := TPath.Combine(TPath.GetTempPath, 'dxcomply-group-by-folder-test.json');
  TFile.WriteAllText(LPath, '{"report":{"enabled":true,"groupByFolder":true}}', TEncoding.UTF8);
  var LGen: TDxComplyGenerator := nil;
  LOptions := TCliOptions.Create;
  try
    LGen := TDxComplyGenerator.Create;
    Assert.IsTrue(LGen.LoadConfig(LPath).HumanReadableReport.GroupByFolder);
    FreeAndNil(LGen);

    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--report-group-by-folder=false']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.IsFalse(LGen.Config.HumanReadableReport.GroupByFolder,
      '--report-group-by-folder overrides the file');
  finally
    LGen.Free;
    LOptions.Free;
    if TFile.Exists(LPath) then
    begin
      TFile.Delete(LPath);
    end;
  end;
end;

procedure TCliOptionsTests.Config_ReportContent_LoadsAndMerges;
begin
  var LPath := TPath.Combine(TPath.GetTempPath, 'dxcomply-report-content-test.json');
  TFile.WriteAllText(LPath, '{"report":{"enabled":true,"format":"html","content":"overview"}}', TEncoding.UTF8);
  var LGen: TDxComplyGenerator := nil;
  var LOptions := TCliOptions.Create;
  try
    LGen := TDxComplyGenerator.Create;
    Assert.AreEqual(NativeInt(Ord(hrcOverview)), NativeInt(Ord(LGen.LoadConfig(LPath).HumanReadableReport.Content)));
    FreeAndNil(LGen);

    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--report-content=all']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.AreEqual(NativeInt(Ord(hrcAll)), NativeInt(Ord(LGen.Config.HumanReadableReport.Content)),
      '--report-content overrides the file');
    Assert.IsTrue(LGen.Config.HumanReadableReport.Enabled, 'the file keeps reports on');
    Assert.AreEqual(NativeInt(Ord(hrfHtml)), NativeInt(Ord(LGen.Config.HumanReadableReport.Format)));
  finally
    LGen.Free;
    LOptions.Free;
    if TFile.Exists(LPath) then
    begin
      TFile.Delete(LPath);
    end;
  end;
end;

procedure TCliOptionsTests.Config_Strict_LoadsAndMerges;
begin
  var LPath := TPath.Combine(TPath.GetTempPath, 'dxcomply-strict-test.json');
  TFile.WriteAllText(LPath, '{"strict":true}', TEncoding.UTF8);
  var LGen: TDxComplyGenerator := nil;
  var LOptions := TCliOptions.Create;
  try
    LGen := TDxComplyGenerator.Create;
    Assert.IsTrue(LGen.LoadConfig(LPath).StrictMode);
    FreeAndNil(LGen);

    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--strict=false']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.IsFalse(LGen.Config.StrictMode, '--strict=false overrides the file');
  finally
    LGen.Free;
    LOptions.Free;
    if TFile.Exists(LPath) then
    begin
      TFile.Delete(LPath);
    end;
  end;
end;

procedure TCliOptionsTests.Parse_SpdxVersion_SelectsSpdx3;
begin
  var LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--format=spdx-json']));
    Assert.IsTrue(LOptions.ToSbomConfig.Format = sfSpdxJson, 'SPDX 2.3 stays the default');
    Assert.IsFalse(scoSpdxVersion in LOptions.ToSbomConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--format=spdx-json', '--spdx-version=3.0.1']));
    Assert.IsTrue(LOptions.ToSbomConfig.Format = sfSpdx3Json);
    Assert.AreEqual('3.0.1', LOptions.ToSbomConfig.SpdxVersion);
    Assert.IsTrue(scoSpdxVersion in LOptions.ToSbomConfig.ExplicitOverrides);
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--spdx-version=3.0.1']));
    Assert.IsTrue(LOptions.ToSbomConfig.Format = sfCycloneDxJson,
      '--spdx-version does not change a CycloneDX format');
  finally
    LOptions.Free;
  end;
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--project=App.dproj', '--spdx-version=4.0']));
    Assert.Contains(LOptions.ParseError, '--spdx-version');
  finally
    LOptions.Free;
  end;
end;

procedure TCliOptionsTests.Config_SpdxVersion_LoadsAndMerges;
begin
  var LPath := TPath.Combine(TPath.GetTempPath, 'dxcomply-spdx3-test.json');
  TFile.WriteAllText(LPath, '{"format":"spdx-json","spdxVersion":"3.0.1"}', TEncoding.UTF8);
  var LGen: TDxComplyGenerator := nil;
  var LOptions := TCliOptions.Create;
  try
    LGen := TDxComplyGenerator.Create;
    var LConfig := LGen.LoadConfig(LPath);
    Assert.IsTrue(LConfig.Format = sfSpdx3Json, 'spdxVersion 3.0.1 selects the SPDX 3 writer');
    Assert.AreEqual('3.0.1', LConfig.SpdxVersion);
    FreeAndNil(LGen);

    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--spdx-version=2.3']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    LGen.GenerateFromConfig('missing.dproj', LPath);
    Assert.IsTrue(LGen.Config.Format = sfSpdxJson, '--spdx-version=2.3 overrides the file');
  finally
    LGen.Free;
    LOptions.Free;
    if TFile.Exists(LPath) then
    begin
      TFile.Delete(LPath);
    end;
  end;
end;

function CliOptions_TempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'dxcomply-cfg-' + TPath.GetRandomFileName);
  TDirectory.CreateDirectory(Result);
end;

procedure CliOptions_DeleteTree(const APath: string);
begin
  if (APath <> '') and TDirectory.Exists(APath) then
    TDirectory.Delete(APath, True);
end;

procedure CliOptions_WriteText(const APath, AText: string);
var
  LDir: string;
begin
  LDir := TPath.GetDirectoryName(APath);
  if (LDir <> '') and not TDirectory.Exists(LDir) then
    TDirectory.CreateDirectory(LDir);
  TFile.WriteAllText(APath, AText, TEncoding.UTF8);
end;

procedure TCliOptionsTests.ResolveConfigPath_FoundInWorkingDirectory;
var
  LRoot, LWork, LProjectDir, LProject, LCwdConfig: string;
  LResolution: TConfigPathResolution;
begin
  LRoot := CliOptions_TempDir;
  try
    LWork := TPath.Combine(LRoot, 'work');
    LProjectDir := TPath.Combine(LRoot, 'proj');
    TDirectory.CreateDirectory(LWork);
    TDirectory.CreateDirectory(LProjectDir);
    LProject := TPath.Combine(LProjectDir, 'App.dproj');
    CliOptions_WriteText(LProject, '<Project/>');
    LCwdConfig := TPath.Combine(LWork, '.dxcomply.json');
    CliOptions_WriteText(LCwdConfig, '{"product":{"supplier":"FromCwd"}}');
    CliOptions_WriteText(TPath.Combine(LProjectDir, '.dxcomply.json'),
      '{"product":{"supplier":"FromProject"}}');

    LResolution := TCliOptions.ResolveConfigPath('.dxcomply.json', LProject, LWork);
    Assert.IsTrue(LResolution.Found, 'the working-directory file must be used');
    Assert.IsTrue(SameText(LResolution.Path, LCwdConfig), LResolution.Path);
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LResolution.Tried)),
      'a file in the working directory stops the lookup');
    Assert.IsTrue(SameText(LResolution.Tried[0], LCwdConfig), LResolution.Tried[0]);
  finally
    CliOptions_DeleteTree(LRoot);
  end;
end;

procedure TCliOptionsTests.ResolveConfigPath_FoundNextToProject;
var
  LRoot, LWork, LProjectDir, LProject, LProjectConfig: string;
  LResolution: TConfigPathResolution;
begin
  LRoot := CliOptions_TempDir;
  try
    LWork := TPath.Combine(LRoot, 'work');
    LProjectDir := TPath.Combine(LRoot, 'proj');
    TDirectory.CreateDirectory(LWork);
    TDirectory.CreateDirectory(LProjectDir);
    LProject := TPath.Combine(LProjectDir, 'App.dproj');
    CliOptions_WriteText(LProject, '<Project/>');
    LProjectConfig := TPath.Combine(LProjectDir, '.dxcomply.json');
    CliOptions_WriteText(LProjectConfig, '{"product":{"supplier":"FromProject"}}');

    LResolution := TCliOptions.ResolveConfigPath('.dxcomply.json', LProject, LWork);
    Assert.IsTrue(LResolution.Found, 'the file next to the project must be used');
    Assert.IsTrue(SameText(LResolution.Path, LProjectConfig), LResolution.Path);
    Assert.AreEqual(NativeInt(2), NativeInt(Length(LResolution.Tried)));
    Assert.IsTrue(SameText(LResolution.Tried[0],
      TPath.GetFullPath(TPath.Combine(LWork, '.dxcomply.json'))), LResolution.Tried[0]);
    Assert.IsTrue(SameText(LResolution.Tried[1], LProjectConfig), LResolution.Tried[1]);
  finally
    CliOptions_DeleteTree(LRoot);
  end;
end;

procedure TCliOptionsTests.ResolveConfigPath_NeitherPresent;
var
  LRoot, LWork, LProjectDir, LProject, LExeDir: string;
  LResolution: TConfigPathResolution;
  I: Integer;
begin
  LRoot := CliOptions_TempDir;
  try
    LWork := TPath.Combine(LRoot, 'work');
    LProjectDir := TPath.Combine(LRoot, 'proj');
    TDirectory.CreateDirectory(LWork);
    TDirectory.CreateDirectory(LProjectDir);
    LProject := TPath.Combine(LProjectDir, 'App.dproj');
    CliOptions_WriteText(LProject, '<Project/>');

    LResolution := TCliOptions.ResolveConfigPath('.dxcomply.json', LProject, LWork);
    Assert.IsFalse(LResolution.Found);
    Assert.AreEqual('', LResolution.Path);
    Assert.AreEqual(NativeInt(2), NativeInt(Length(LResolution.Tried)),
      'the working directory and the project folder are both checked');
    Assert.IsTrue(SameText(LResolution.Tried[0],
      TPath.GetFullPath(TPath.Combine(LWork, '.dxcomply.json'))));
    Assert.IsTrue(SameText(LResolution.Tried[1],
      TPath.GetFullPath(TPath.Combine(LProjectDir, '.dxcomply.json'))));

    LExeDir := ExcludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)));
    for I := 0 to High(LResolution.Tried) do
      Assert.IsFalse(
        SameText(ExcludeTrailingPathDelimiter(TPath.GetDirectoryName(LResolution.Tried[I])), LExeDir),
        'lookup must not use the folder of dxcomply.exe');
  finally
    CliOptions_DeleteTree(LRoot);
  end;
end;

procedure TCliOptionsTests.ResolveConfigPath_AbsolutePath;
var
  LRoot, LWork, LProjectDir, LProject, LAbsolute, LMissing: string;
  LResolution: TConfigPathResolution;
begin
  LRoot := CliOptions_TempDir;
  try
    LWork := TPath.Combine(LRoot, 'work');
    LProjectDir := TPath.Combine(LRoot, 'proj');
    TDirectory.CreateDirectory(LWork);
    TDirectory.CreateDirectory(LProjectDir);
    LProject := TPath.Combine(LProjectDir, 'App.dproj');
    CliOptions_WriteText(LProject, '<Project/>');
    CliOptions_WriteText(TPath.Combine(LProjectDir, '.dxcomply.json'),
      '{"product":{"supplier":"FromProject"}}');
    LAbsolute := TPath.Combine(LWork, 'explicit.json');
    CliOptions_WriteText(LAbsolute, '{"product":{"supplier":"Absolute"}}');

    LResolution := TCliOptions.ResolveConfigPath(LAbsolute, LProject, LWork);
    Assert.IsTrue(LResolution.Found);
    Assert.AreEqual(LAbsolute, LResolution.Path, 'an absolute path is used as given');
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LResolution.Tried)));
    Assert.AreEqual(LAbsolute, LResolution.Tried[0]);

    LMissing := TPath.Combine(LRoot, 'missing.json');
    LResolution := TCliOptions.ResolveConfigPath(LMissing, LProject, LWork);
    Assert.IsFalse(LResolution.Found, 'a missing absolute path is not found elsewhere');
    Assert.AreEqual('', LResolution.Path);
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LResolution.Tried)),
      'a missing absolute path is not looked up in the project folder');
    Assert.AreEqual(LMissing, LResolution.Tried[0]);
  finally
    CliOptions_DeleteTree(LRoot);
  end;
end;

procedure TCliOptionsTests.ResolveConfigPath_RelativeSubfolder;
var
  LRoot, LWork, LProjectDir, LProject, LRelative, LProjectConfig: string;
  LResolution: TConfigPathResolution;
begin
  LRoot := CliOptions_TempDir;
  try
    LWork := TPath.Combine(LRoot, 'work');
    LProjectDir := TPath.Combine(LRoot, 'proj');
    TDirectory.CreateDirectory(LWork);
    TDirectory.CreateDirectory(LProjectDir);
    LProject := TPath.Combine(LProjectDir, 'App.dproj');
    CliOptions_WriteText(LProject, '<Project/>');
    LRelative := TPath.Combine('ci', '.dxcomply.json');
    LProjectConfig := TPath.Combine(LProjectDir, LRelative);
    CliOptions_WriteText(LProjectConfig, '{"product":{"supplier":"FromSub"}}');

    LResolution := TCliOptions.ResolveConfigPath(LRelative, LProject, LWork);
    Assert.IsTrue(LResolution.Found);
    Assert.IsTrue(SameText(LResolution.Path, TPath.GetFullPath(LProjectConfig)), LResolution.Path);
    Assert.AreEqual(NativeInt(2), NativeInt(Length(LResolution.Tried)));
    Assert.IsTrue(SameText(LResolution.Tried[0],
      TPath.GetFullPath(TPath.Combine(LWork, LRelative))), LResolution.Tried[0]);
    Assert.IsTrue(SameText(LResolution.Tried[1], TPath.GetFullPath(LProjectConfig)),
      LResolution.Tried[1]);
  finally
    CliOptions_DeleteTree(LRoot);
  end;
end;

procedure TCliOptionsTests.ResolveConfigPath_DefaultWithoutConfigFlag;
var
  LRoot, LWork, LProjectDir, LProject, LProjectConfig: string;
  LOptions: TCliOptions;
  LResolution: TConfigPathResolution;
begin
  LRoot := CliOptions_TempDir;
  try
    LWork := TPath.Combine(LRoot, 'work');
    LProjectDir := TPath.Combine(LRoot, 'proj');
    TDirectory.CreateDirectory(LWork);
    TDirectory.CreateDirectory(LProjectDir);
    LProject := TPath.Combine(LProjectDir, 'App.dproj');
    CliOptions_WriteText(LProject, '<Project/>');
    LProjectConfig := TPath.Combine(LProjectDir, '.dxcomply.json');
    CliOptions_WriteText(LProjectConfig, '{"product":{"name":"Default"}}');

    LOptions := TCliOptions.Create;
    try
      Assert.IsTrue(LOptions.Parse(['--project=' + LProject, '--ci']), LOptions.ParseError);
      Assert.AreEqual('.dxcomply.json', LOptions.ConfigFile);
      LResolution := TCliOptions.ResolveConfigPath(
        LOptions.ConfigFile, LOptions.Project, LWork);
      Assert.IsTrue(LResolution.Found);
      Assert.IsTrue(SameText(LResolution.Path, LProjectConfig), LResolution.Path);
    finally
      LOptions.Free;
    end;
  finally
    CliOptions_DeleteTree(LRoot);
  end;
end;

procedure TCliOptionsTests.ResolveConfigPath_ProjectFolder_LoadsValuesWhenCwdDiffers;
var
  LRoot, LWork, LProjectDir, LProject, LSaved: string;
  LResolution: TConfigPathResolution;
  LGen: TDxComplyGenerator;
  LConfig: TSbomConfig;
begin
  LRoot := CliOptions_TempDir;
  LSaved := TDirectory.GetCurrentDirectory;
  try
    LWork := TPath.Combine(LRoot, 'work');
    LProjectDir := TPath.Combine(LRoot, 'proj');
    TDirectory.CreateDirectory(LWork);
    TDirectory.CreateDirectory(LProjectDir);
    LProject := TPath.Combine(LProjectDir, 'App.dproj');
    CliOptions_WriteText(LProject, '<Project/>');
    CliOptions_WriteText(TPath.Combine(LProjectDir, '.dxcomply.json'),
      '{"sbomCreator":"sbom@example.com",' +
      '"product":{"supplier":"From Project GmbH",' +
      '"supplierUrl":"https://example.com/supplier",' +
      '"licence":"MIT"}}');

    TDirectory.SetCurrentDirectory(LWork);
    LResolution := TCliOptions.ResolveConfigPath('.dxcomply.json', LProject);
    Assert.IsTrue(LResolution.Found, 'the file next to the project must be found');
    Assert.IsTrue(SameText(LResolution.Path,
      TPath.Combine(LProjectDir, '.dxcomply.json')), LResolution.Path);

    LGen := TDxComplyGenerator.Create;
    try
      LConfig := LGen.LoadConfig(LResolution.Path);
      Assert.AreEqual('From Project GmbH', LConfig.Supplier);
      Assert.AreEqual('https://example.com/supplier', LConfig.SupplierUrl);
      Assert.AreEqual('MIT', LConfig.Licence);
      Assert.AreEqual('sbom@example.com', LConfig.SbomCreator);
    finally
      LGen.Free;
    end;
  finally
    TDirectory.SetCurrentDirectory(LSaved);
    CliOptions_DeleteTree(LRoot);
  end;
end;

procedure TCliOptionsTests.ConfigFileWarning_ListsTriedPathsWhenMissing;
var
  LRoot, LWork, LProjectDir, LProject, LWarning: string;
  LResolution: TConfigPathResolution;
begin
  LRoot := CliOptions_TempDir;
  try
    LWork := TPath.Combine(LRoot, 'work');
    LProjectDir := TPath.Combine(LRoot, 'proj');
    TDirectory.CreateDirectory(LWork);
    TDirectory.CreateDirectory(LProjectDir);
    LProject := TPath.Combine(LProjectDir, 'App.dproj');
    CliOptions_WriteText(LProject, '<Project/>');

    LResolution := TCliOptions.ResolveConfigPath('.dxcomply.json', LProject, LWork);
    Assert.IsFalse(LResolution.Found);
    Assert.AreEqual(NativeInt(2), NativeInt(Length(LResolution.Tried)));
    LWarning := TCliOptions.ConfigFileWarning(True, LResolution);
    Assert.Contains(LWarning, 'No config file was found for --ci');
    Assert.Contains(LWarning, 'continues without it');
    Assert.Contains(LWarning, LResolution.Tried[0]);
    Assert.Contains(LWarning, LResolution.Tried[1]);
    Assert.IsTrue(Pos(LResolution.Tried[0], LWarning) < Pos(LResolution.Tried[1], LWarning),
      'the working directory is listed before the project folder');
    Assert.AreEqual('', TCliOptions.ConfigFileWarning(False, LResolution),
      'without --ci the missing file is not reported');

    CliOptions_WriteText(TPath.Combine(LProjectDir, '.dxcomply.json'), '{}');
    LResolution := TCliOptions.ResolveConfigPath('.dxcomply.json', LProject, LWork);
    Assert.IsTrue(LResolution.Found);
    Assert.AreEqual('', TCliOptions.ConfigFileWarning(True, LResolution),
      'a file that was found does not produce the warning');
  finally
    CliOptions_DeleteTree(LRoot);
  end;
end;

procedure TCliOptionsTests.HelpText_DescribesOptionalBrackets;
var
  LHelp: string;
begin
  LHelp := TCliOptions.HelpText;
  Assert.Contains(LHelp, 'Square brackets mark an optional value');
  Assert.Contains(LHelp, '--report equals --report=both');
  Assert.Contains(LHelp, '--library equals --library=true');
  Assert.Contains(LHelp, '--report[=<format>]',
    'the optional-value notation stays in the option list');
  Assert.Contains(LHelp, '--library[=true|false]',
    'the optional-value notation stays in the option list');
  Assert.Contains(LHelp, 'checked in the current');
  Assert.Contains(LHelp, 'project folder');
  Assert.Contains(LHelp, 'Android 32-bit is the platform Android');
  Assert.Contains(LHelp, 'Android32');
  Assert.Contains(LHelp, 'Android64 stays Android64');
end;

initialization
  TDUnitX.RegisterTestFixture(TCliOptionsTests);

end.
