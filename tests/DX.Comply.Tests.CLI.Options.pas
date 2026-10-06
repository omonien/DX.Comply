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
  DUnitX.TestFramework,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.CLI.Options,
  System.SysUtils;

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

initialization
  TDUnitX.RegisterTestFixture(TCliOptionsTests);

end.
