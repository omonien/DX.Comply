/// <summary>
/// DX.Comply.Tests.VersionInfo
/// DUnitX tests for the shared module version helper.
/// </summary>
///
/// <remarks>
/// Confirms the helper reads the running module (HInstance) and that a zero
/// module handle does not switch to the host executable.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.VersionInfo;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.VersionInfo,
  Winapi.Windows;

type
  /// <summary>
  /// DUnitX fixture for DX.Comply.VersionInfo.
  /// </summary>
  [TestFixture]
  TVersionInfoTests = class
  public
    /// <summary>
    /// The tool version must be a dotted numeric version from this module.
    /// </summary>
    [Test]
    procedure ToolVersion_MatchesRunningModule;

    /// <summary>
    /// A zero module handle must resolve to this module, not the host process.
    /// </summary>
    [Test]
    procedure ZeroModule_UsesThisModule;

    /// <summary>
    /// An explicit metadata version must win over the module version.
    /// </summary>
    [Test]
    procedure Resolve_MetadataValueWins;

    /// <summary>
    /// A blank metadata version must fall back to the module version.
    /// </summary>
    [Test]
    procedure Resolve_BlankMetadataUsesModule;
  end;

implementation

uses
  System.RegularExpressions,
  System.SysUtils;

procedure TVersionInfoTests.ToolVersion_MatchesRunningModule;
var
  LModuleVersion: string;
begin
  LModuleVersion := GetModuleProductVersion(HInstance);
  if LModuleVersion = '' then
    LModuleVersion := '1.0.0';
  Assert.AreEqual(LModuleVersion, GetDxComplyToolVersion,
    'GetDxComplyToolVersion must read the module that contains the helper');
  Assert.IsTrue(TRegEx.IsMatch(GetDxComplyToolVersion, '^\d+\.\d+(\.\d+){0,2}$'),
    'The tool version must look like a numeric version');
end;

procedure TVersionInfoTests.ZeroModule_UsesThisModule;
begin
  Assert.AreEqual(GetModuleProductVersion(HInstance), GetModuleProductVersion(0),
    'Module handle 0 must mean HInstance, not the host executable');
end;

procedure TVersionInfoTests.Resolve_MetadataValueWins;
begin
  Assert.AreEqual('9.9.9-meta', ResolveDxComplyToolVersion('  9.9.9-meta  '),
    'A supplied metadata tool version must be used as written, trimmed');
end;

procedure TVersionInfoTests.Resolve_BlankMetadataUsesModule;
begin
  Assert.AreEqual(GetDxComplyToolVersion, ResolveDxComplyToolVersion(''),
    'A blank metadata tool version must fall back to the running module');
  Assert.AreEqual(GetDxComplyToolVersion, ResolveDxComplyToolVersion('   '),
    'Whitespace must not count as an explicit tool version');
end;

initialization
  TDUnitX.RegisterTestFixture(TVersionInfoTests);

end.
