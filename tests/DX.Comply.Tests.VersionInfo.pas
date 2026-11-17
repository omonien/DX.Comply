/// <summary>
/// DX.Comply.Tests.VersionInfo
/// DUnitX tests for the shared module version helper.
/// </summary>
///
/// <remarks>
/// Confirms the helper reads the running module (HInstance) and that a zero
/// module handle does not switch to the host executable. The file version
/// selection tests pass fixed file info and version strings, so they do not
/// need a binary.
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

    /// <summary>
    /// The About caption uses the module version and does not invent 1.0.0.0.
    /// </summary>
    [Test]
    procedure VersionCaption_UsesModuleVersionOrUnavailable;

    /// <summary>
    /// A numeric file version wins when the version strings differ.
    /// </summary>
    [Test]
    procedure Select_NumericVersion_WinsOverDifferentText;

    /// <summary>
    /// A numeric file version is used when both version strings are empty.
    /// </summary>
    [Test]
    procedure Select_NumericVersion_UsedWhenStringsEmpty;

    /// <summary>
    /// Fixed file info of 0.0.0.0 is a version and is not replaced by text.
    /// </summary>
    [Test]
    procedure Select_ZeroNumericVersion_WinsOverText;

    /// <summary>
    /// Without fixed file info, the FileVersion string is used.
    /// </summary>
    [Test]
    procedure Select_NoFixedInfo_UsesFileVersion;

    /// <summary>
    /// Without fixed file info, a blank FileVersion falls through to
    /// ProductVersion.
    /// </summary>
    [Test]
    procedure Select_NoFixedInfo_BlankFileVersion_UsesProductVersion;

    /// <summary>
    /// Without fixed file info and without version strings, the result is empty.
    /// </summary>
    [Test]
    procedure Select_NoFixedInfo_BothBlank_ReturnsEmpty;

    /// <summary>
    /// A missing file, a PE with no version resource, and a PE that has
    /// FileVersion but no LegalCopyright all return an empty notice.
    /// </summary>
    [Test]
    procedure LegalCopyright_MissingOrNoNotice_IsEmpty;

    /// <summary>
    /// The running executable's file and its module resource agree.
    /// </summary>
    [Test]
    procedure LegalCopyright_FileMatchesRunningModule;
  end;

implementation

uses
  System.IOUtils,
  System.RegularExpressions,
  System.SysUtils,
  DX.Comply.Tests.Paths;

function MakeFixedFileInfo(AMajor, AMinor, ARelease, ABuild: Word): TVSFixedFileInfo;
begin
  Result := Default(TVSFixedFileInfo);
  Result.dwSignature := VS_FFI_SIGNATURE;
  Result.dwFileVersionMS := (DWORD(AMajor) shl 16) or DWORD(AMinor);
  Result.dwFileVersionLS := (DWORD(ARelease) shl 16) or DWORD(ABuild);
end;

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

procedure TVersionInfoTests.VersionCaption_UsesModuleVersionOrUnavailable;
var
  LCaption: string;
  LModuleVersion: string;
begin
  Assert.AreEqual('Version unavailable', FormatDXComplyVersionCaption('', 'Olaf Monien'),
    'A missing product version must not be replaced with 1.0.0.0');
  Assert.AreEqual('Version unavailable', FormatDXComplyVersionCaption('   ', ''),
    'Whitespace is not a product version');

  LModuleVersion := GetModuleProductVersion(HInstance);
  LCaption := FormatDXComplyVersionCaption(LModuleVersion, 'Olaf Monien');
  if LModuleVersion = '' then
    Assert.AreEqual('Version unavailable', LCaption,
      'The caption must stay unavailable when this module has no product version')
  else
  begin
    Assert.AreEqual('Version ' + LModuleVersion + ' · Olaf Monien', LCaption,
      'The caption must show the module product version');
    Assert.Contains(LCaption, LModuleVersion);
  end;
end;

procedure TVersionInfoTests.Select_NumericVersion_WinsOverDifferentText;
var
  LInfo: TVSFixedFileInfo;
begin
  // Issue #188: a vendor string such as "6, 10, 5, 0" must not replace 6.10.5.0.
  LInfo := MakeFixedFileInfo(6, 10, 5, 0);
  LInfo.dwProductVersionMS := (DWORD(1) shl 16) or DWORD(2);
  LInfo.dwProductVersionLS := (DWORD(3) shl 16) or DWORD(4);
  Assert.AreEqual('6.10.5.0',
    SelectFileVersionText(True, LInfo, '6, 10, 5, 0', '1.2.3.4'),
    'the numeric file version wins when the version strings differ');
end;

procedure TVersionInfoTests.Select_NumericVersion_UsedWhenStringsEmpty;
var
  LInfo: TVSFixedFileInfo;
begin
  LInfo := MakeFixedFileInfo(9, 8, 7, 6);
  Assert.AreEqual('9.8.7.6', SelectFileVersionText(True, LInfo, '', ''),
    'fixed file info is enough when both version strings are empty');
end;

procedure TVersionInfoTests.Select_ZeroNumericVersion_WinsOverText;
var
  LInfo: TVSFixedFileInfo;
begin
  LInfo := MakeFixedFileInfo(0, 0, 0, 0);
  Assert.AreEqual('0.0.0.0', SelectFileVersionText(True, LInfo, '1.2.3', '4.5.6'),
    'fixed file info of 0.0.0.0 is a version and is not replaced by text');
end;

procedure TVersionInfoTests.Select_NoFixedInfo_UsesFileVersion;
var
  LInfo: TVSFixedFileInfo;
begin
  LInfo := Default(TVSFixedFileInfo);
  Assert.AreEqual('1.2.3-beta',
    SelectFileVersionText(False, LInfo, '  1.2.3-beta  ', '9.9.9'),
    'without fixed file info the FileVersion string is used, trimmed');
end;

procedure TVersionInfoTests.Select_NoFixedInfo_BlankFileVersion_UsesProductVersion;
var
  LInfo: TVSFixedFileInfo;
begin
  LInfo := Default(TVSFixedFileInfo);
  Assert.AreEqual('4.5.6',
    SelectFileVersionText(False, LInfo, '   ', '  4.5.6  '),
    'a blank FileVersion string falls through to ProductVersion');
  Assert.AreEqual('4.5.6', SelectFileVersionText(False, LInfo, '', '4.5.6'),
    'an empty FileVersion string falls through to ProductVersion');
end;

procedure TVersionInfoTests.Select_NoFixedInfo_BothBlank_ReturnsEmpty;
var
  LInfo: TVSFixedFileInfo;
begin
  LInfo := Default(TVSFixedFileInfo);
  Assert.AreEqual('', SelectFileVersionText(False, LInfo, '', ''),
    'no fixed file info and no version strings means no version');
  Assert.AreEqual('', SelectFileVersionText(False, LInfo, '  ', '   '),
    'whitespace is not a version string');
end;

procedure TVersionInfoTests.LegalCopyright_MissingOrNoNotice_IsEmpty;
var
  LNoVersion: string;
  LWithVersion: string;
begin
  Assert.AreEqual('', GetFileLegalCopyright(''),
    'an empty path has no LegalCopyright');
  Assert.AreEqual('', GetFileLegalCopyright('C:\DoesNotExist\DX.Comply.NoSuch.exe'),
    'a missing file has no LegalCopyright');

  LNoVersion := TPath.Combine(RepoRoot, 'tests' + PathDelim + 'fixtures' +
    PathDelim + 'binaries' + PathDelim + 'FakeNoVersion.exe');
  LWithVersion := TPath.Combine(RepoRoot, 'tests' + PathDelim + 'fixtures' +
    PathDelim + 'binaries' + PathDelim + 'FakeWithVersion.exe');
  Assert.IsTrue(TFile.Exists(LNoVersion), LNoVersion);
  Assert.IsTrue(TFile.Exists(LWithVersion), LWithVersion);
  Assert.AreEqual('', GetFileLegalCopyright(LNoVersion),
    'FakeNoVersion.exe has no version resource');
  Assert.AreEqual('9.8.7.6', GetFileVersionText(LWithVersion),
    'FakeWithVersion.exe still has a FileVersion');
  Assert.AreEqual('', GetFileLegalCopyright(LWithVersion),
    'FileVersion is not a copyright notice');
end;

procedure TVersionInfoTests.LegalCopyright_FileMatchesRunningModule;
begin
  Assert.AreEqual(GetModuleVersionString(HInstance, 'LegalCopyright'),
    GetFileLegalCopyright(ParamStr(0)),
    'the test executable file and its module must report the same LegalCopyright');
end;

initialization
  TDUnitX.RegisterTestFixture(TVersionInfoTests);

end.
