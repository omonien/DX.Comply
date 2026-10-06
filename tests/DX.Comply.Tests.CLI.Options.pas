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
  DX.Comply.CLI.Options;

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

    /// <summary>The built-in Win32 and Release defaults are not explicit.</summary>
    [Test]
    procedure Parse_DefaultTarget_IsNotExplicit;

    /// <summary>--platform and --config-name mark the target as explicitly set.</summary>
    [Test]
    procedure Parse_ConfigName_MarksTargetExplicit;
  end;

implementation

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

initialization
  TDUnitX.RegisterTestFixture(TCliOptionsTests);

end.
