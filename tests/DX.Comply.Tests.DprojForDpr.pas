/// <summary>
/// DX.Comply.Tests.DprojForDpr
/// DUnitX tests for a .dpr that has a .dproj of the same name next to it.
/// </summary>
///
/// <remarks>
/// Issue #75. A .dpr with a sibling .dproj resolves to the .dproj and
/// reports an info message. A .dpr without a .dproj (a Delphi 7 project)
/// keeps its path.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.DprojForDpr;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  DUnitX.TestFramework,
  DX.Comply.Engine,
  DX.Comply.ProjectScanner;

type
  /// <summary>
  /// Covers TryFindDprojForDpr and TDxComplyGenerator.ResolveProjectPath.
  /// </summary>
  [TestFixture]
  TDprojForDprTests = class
  private
    FTempDir: string;
    FMessages: TStringList;
    procedure OnProgress(const AMessage: string; const AProgress: Integer);
    function WriteFile(const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    /// <summary>A .dpr with a sibling .dproj finds the .dproj.</summary>
    [Test]
    procedure TryFind_DprWithDproj_ReturnsDproj;

    /// <summary>A Delphi 7 .dpr without a .dproj finds nothing.</summary>
    [Test]
    procedure TryFind_DprWithoutDproj_ReturnsFalse;

    /// <summary>A .dproj passed directly is not changed.</summary>
    [Test]
    procedure TryFind_Dproj_ReturnsFalse;

    /// <summary>A .dproj with another base name does not count.</summary>
    [Test]
    procedure TryFind_OtherDprojName_ReturnsFalse;

    /// <summary>The info text names both files.</summary>
    [Test]
    procedure Message_NamesBothFiles;

    /// <summary>The engine uses the .dproj and reports it.</summary>
    [Test]
    procedure Resolve_DprWithDproj_UsesDprojAndReportsInfo;

    /// <summary>The engine keeps a Delphi 7 .dpr and reports nothing.</summary>
    [Test]
    procedure Resolve_DprWithoutDproj_KeepsDprSilently;
  end;

implementation

procedure TDprojForDprTests.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'dxc-dprojfordpr-' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(FTempDir);
  FMessages := TStringList.Create;
end;

procedure TDprojForDprTests.TearDown;
begin
  FMessages.Free;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TDprojForDprTests.OnProgress(const AMessage: string;
  const AProgress: Integer);
begin
  FMessages.Add(AMessage);
end;

function TDprojForDprTests.WriteFile(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
  TFile.WriteAllText(Result, '');
end;

procedure TDprojForDprTests.TryFind_DprWithDproj_ReturnsDproj;
var
  LDpr: string;
  LDproj: string;
  LFound: string;
begin
  LDpr := WriteFile('Foo.dpr');
  LDproj := WriteFile('Foo.dproj');
  Assert.IsTrue(TryFindDprojForDpr(LDpr, LFound));
  Assert.IsTrue(SameText(LDproj, LFound), LFound);
end;

procedure TDprojForDprTests.TryFind_DprWithoutDproj_ReturnsFalse;
var
  LDpr: string;
  LFound: string;
begin
  LDpr := WriteFile('Legacy.dpr');
  WriteFile('Legacy.dof');
  WriteFile('Legacy.cfg');
  Assert.IsFalse(TryFindDprojForDpr(LDpr, LFound));
  Assert.AreEqual('', LFound);
end;

procedure TDprojForDprTests.TryFind_Dproj_ReturnsFalse;
var
  LDproj: string;
  LFound: string;
begin
  WriteFile('Foo.dpr');
  LDproj := WriteFile('Foo.dproj');
  Assert.IsFalse(TryFindDprojForDpr(LDproj, LFound));
  Assert.AreEqual('', LFound);
end;

procedure TDprojForDprTests.TryFind_OtherDprojName_ReturnsFalse;
var
  LDpr: string;
  LFound: string;
begin
  LDpr := WriteFile('Foo.dpr');
  WriteFile('Bar.dproj');
  Assert.IsFalse(TryFindDprojForDpr(LDpr, LFound));
end;

procedure TDprojForDprTests.Message_NamesBothFiles;
begin
  Assert.AreEqual('Using Foo.dproj found next to Foo.dpr.',
    DprojForDprMessage('C:\Src\Foo.dpr', 'C:\Src\Foo.dproj'));
end;

procedure TDprojForDprTests.Resolve_DprWithDproj_UsesDprojAndReportsInfo;
var
  LGen: TDxComplyGenerator;
  LDpr: string;
  LDproj: string;
  LResolved: string;
begin
  LDpr := WriteFile('Foo.dpr');
  LDproj := WriteFile('Foo.dproj');
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LResolved := LGen.ResolveProjectPath(LDpr);
  finally
    LGen.Free;
  end;
  Assert.IsTrue(SameText(LDproj, LResolved), LResolved);
  Assert.AreEqual(1, FMessages.Count);
  Assert.AreEqual('Info: Using Foo.dproj found next to Foo.dpr.', FMessages[0]);
end;

procedure TDprojForDprTests.Resolve_DprWithoutDproj_KeepsDprSilently;
var
  LGen: TDxComplyGenerator;
  LDpr: string;
  LResolved: string;
begin
  LDpr := WriteFile('Legacy.dpr');
  WriteFile('Legacy.dof');
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LResolved := LGen.ResolveProjectPath(LDpr);
  finally
    LGen.Free;
  end;
  Assert.AreEqual(LDpr, LResolved);
  Assert.AreEqual(0, FMessages.Count);
end;

initialization
  TDUnitX.RegisterTestFixture(TDprojForDprTests);

end.
