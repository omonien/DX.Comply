/// <summary>
/// DX.Comply.Tests.CLI.GitTag
/// DUnitX tests for the --version-from-git-tag CLI option.
/// </summary>
///
/// <remarks>
/// The repository test creates a throwaway git repository in the temp folder.
/// It passes without checks when git is not installed on the test machine.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.CLI.GitTag;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCliGitTagTests = class
  public
    [Test]
    procedure StripVersionTagPrefix_RemovesLowerV;
    [Test]
    procedure StripVersionTagPrefix_RemovesUpperV;
    [Test]
    procedure StripVersionTagPrefix_KeepsPlainVersion;
    [Test]
    procedure StripVersionTagPrefix_KeepsSingleV;
    [Test]
    procedure Parse_VersionFromGitTag_SetsFlag;
    [Test]
    procedure Parse_Default_VersionFromGitTagIsFalse;
    [Test]
    procedure GitTagDirectory_UsesProjectFolder;
    [Test]
    procedure Apply_ExplicitVersion_IsKept;
    [Test]
    procedure Apply_DirectoryWithoutRepository_WarnsAndKeepsVersion;
    [Test]
    procedure Apply_TaggedRepository_UsesTagWithoutPrefix;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  DX.Comply.Engine,
  DX.Comply.CLI.Options,
  DX.Comply.CLI.GitTag;

function NewTempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'dxc-gittag-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(Result);
end;

procedure TCliGitTagTests.StripVersionTagPrefix_RemovesLowerV;
begin
  Assert.AreEqual('2.1.0', StripVersionTagPrefix('v2.1.0'));
end;

procedure TCliGitTagTests.StripVersionTagPrefix_RemovesUpperV;
begin
  Assert.AreEqual('2.1.0', StripVersionTagPrefix(' V2.1.0 '));
end;

procedure TCliGitTagTests.StripVersionTagPrefix_KeepsPlainVersion;
begin
  Assert.AreEqual('1.0.3', StripVersionTagPrefix('1.0.3'));
end;

procedure TCliGitTagTests.StripVersionTagPrefix_KeepsSingleV;
begin
  Assert.AreEqual('v', StripVersionTagPrefix('v'));
end;

procedure TCliGitTagTests.Parse_VersionFromGitTag_SetsFlag;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj', '--version-from-git-tag']));
    Assert.IsTrue(LOptions.VersionFromGitTag);
  finally
    LOptions.Free;
  end;
end;

procedure TCliGitTagTests.Parse_Default_VersionFromGitTagIsFalse;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=App.dproj']));
    Assert.IsFalse(LOptions.VersionFromGitTag);
  finally
    LOptions.Free;
  end;
end;

procedure TCliGitTagTests.GitTagDirectory_UsesProjectFolder;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=sub\App.dproj', '--version-from-git-tag']));
    Assert.AreEqual(ExtractFileDir(ExpandFileName('sub\App.dproj')),
      LOptions.GitTagDirectory);
  finally
    LOptions.Free;
  end;
end;

procedure TCliGitTagTests.Apply_ExplicitVersion_IsKept;
var
  LConfig: TSbomConfig;
  LWarning: string;
begin
  LConfig := TSbomConfig.Default;
  LConfig.ProductVersion := '9.9.9';
  Include(LConfig.ExplicitOverrides, scoProductVersion);
  Assert.IsFalse(ApplyVersionFromGitTag(LConfig, TPath.GetTempPath, LWarning));
  Assert.AreEqual('9.9.9', LConfig.ProductVersion);
  Assert.AreEqual('', LWarning);
end;

procedure TCliGitTagTests.Apply_DirectoryWithoutRepository_WarnsAndKeepsVersion;
var
  LConfig: TSbomConfig;
  LWarning: string;
  LDir: string;
begin
  LDir := NewTempDir;
  try
    LConfig := TSbomConfig.Default;
    LConfig.ProductVersion := '';
    Assert.IsFalse(ApplyVersionFromGitTag(LConfig, LDir, LWarning));
    Assert.AreEqual('', LConfig.ProductVersion);
    Assert.IsFalse(scoProductVersion in LConfig.ExplicitOverrides);
    Assert.IsTrue(LWarning.StartsWith('Warning:'), LWarning);
  finally
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TCliGitTagTests.Apply_TaggedRepository_UsesTagWithoutPrefix;
const
  cIdentity = '-c user.name=dxcomply -c user.email=dxcomply@example.com ' +
    '-c commit.gpgsign=false -c tag.gpgsign=false ';
var
  LConfig: TSbomConfig;
  LWarning: string;
  LDir: string;
  LOutput: string;
  LExitCode: Cardinal;
begin
  LDir := NewTempDir;
  try
    if not RunGitCommand(LDir, 'init -q', LOutput, LExitCode) then
    begin
      Assert.Pass('git is not installed on this machine');
      Exit;
    end;
    Assert.AreEqual(Cardinal(0), LExitCode, LOutput);
    RunGitCommand(LDir, cIdentity + 'commit -q --allow-empty -m first', LOutput, LExitCode);
    Assert.AreEqual(Cardinal(0), LExitCode, LOutput);
    RunGitCommand(LDir, cIdentity + 'tag v1.2.3', LOutput, LExitCode);
    Assert.AreEqual(Cardinal(0), LExitCode, LOutput);
    RunGitCommand(LDir, cIdentity + 'commit -q --allow-empty -m second', LOutput, LExitCode);
    RunGitCommand(LDir, cIdentity + 'tag V1.3.0', LOutput, LExitCode);
    Assert.AreEqual(Cardinal(0), LExitCode, LOutput);

    LConfig := TSbomConfig.Default;
    Assert.IsTrue(ApplyVersionFromGitTag(LConfig, LDir, LWarning), LWarning);
    Assert.AreEqual('1.3.0', LConfig.ProductVersion);
    Assert.IsTrue(scoProductVersion in LConfig.ExplicitOverrides);
  finally
    // git marks object files read-only; clear that so the folder can go.
    for var LFile in TDirectory.GetFiles(LDir, '*', TSearchOption.soAllDirectories) do
      TFile.SetAttributes(LFile, [TFileAttribute.faNormal]);
    TDirectory.Delete(LDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCliGitTagTests);

end.
