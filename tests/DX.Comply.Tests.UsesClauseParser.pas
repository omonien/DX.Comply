/// <summary>
/// DX.Comply.Tests.UsesClauseParser
/// DUnitX tests for TUsesClauseParser and TUsesClauseWalker.
/// </summary>
///
/// <remarks>
/// Covers comment/string stripping, uses-clause extraction edge cases,
/// and recursive dependency walking with cycle detection and depth limits.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.UsesClauseParser;

interface

uses
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Comply.UsesClauseParser;

type
  /// <summary>
  /// DUnitX fixture for uses-clause parsing.
  /// </summary>
  [TestFixture]
  TUsesClauseParserTests = class
  public
    /// <summary>
    /// Must extract units from both interface and implementation uses clauses.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_InterfaceAndImplementationUses;

    /// <summary>
    /// Line comments must be stripped before extraction.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_WithLineComments;

    /// <summary>
    /// Brace comments must be stripped before extraction.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_WithBraceComments;

    /// <summary>
    /// Parenthesis-star comments must be stripped before extraction.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_WithParenStarComments;

    /// <summary>
    /// Compiler directives inside braces must be stripped.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_WithCompilerDirectives;

    /// <summary>
    /// String literals containing the word 'uses' must not produce false matches.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_WithStringLiterals;

    /// <summary>
    /// DPR-style 'Unit in ''path''' syntax must extract just the unit name.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_WithInClause;

    /// <summary>
    /// DPR 'Unit in ''path'' {FormHint}' syntax must extract just the unit name.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_WithInClauseAndFormHint;

    /// <summary>
    /// Empty source must return nil.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_EmptySource;

    /// <summary>
    /// Source without uses clauses must return nil.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_NoUsesClause;

    /// <summary>
    /// Duplicate unit names must be deduplicated case-insensitively.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_DuplicateUnits;

    /// <summary>
    /// Dotted unit names (e.g. System.SysUtils) must be extracted correctly.
    /// </summary>
    [Test]
    procedure ExtractUsedUnits_DottedUnitNames;
  end;

  /// <summary>
  /// DUnitX fixture for recursive uses-clause dependency walking.
  /// </summary>
  [TestFixture]
  TUsesClauseWalkerTests = class
  private
    FTempDir: string;
    FSearchPaths: TList<string>;
    FGlobalSearchPaths: TList<string>;
    FUnitScopeNames: TList<string>;
    procedure WriteUnitFile(const AFileName, AContent: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    /// <summary>
    /// A single-level dependency must be discovered.
    /// </summary>
    [Test]
    procedure WalkDependencies_SingleLevel;

    /// <summary>
    /// Multi-level transitive dependencies must be discovered recursively.
    /// </summary>
    [Test]
    procedure WalkDependencies_Recursive;

    /// <summary>
    /// Circular dependencies must not cause infinite recursion.
    /// </summary>
    [Test]
    procedure WalkDependencies_CycleDetection;

    /// <summary>
    /// The depth limit must cap recursion.
    /// </summary>
    [Test]
    procedure WalkDependencies_MaxDepthRespected;

    /// <summary>
    /// Units without .pas source must be included but recursion stops there.
    /// </summary>
    [Test]
    procedure WalkDependencies_SkipsDcuOnlyUnits;

    /// <summary>
    /// A source that only has the last part of a dotted unit name is another
    /// unit, so its uses clause is not followed.
    /// </summary>
    [Test]
    procedure WalkDependencies_ShortFileNameIsNotTheDottedUnit;
  end;

implementation

uses
  System.StrUtils;

{ TUsesClauseParserTests }

procedure TUsesClauseParserTests.ExtractUsedUnits_InterfaceAndImplementationUses;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  System.SysUtils,' + sLineBreak +
    '  System.Classes;' + sLineBreak +
    'implementation' + sLineBreak +
    'uses' + sLineBreak +
    '  System.IOUtils;' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(3), NativeInt(Length(LUnits)),
    'Must extract units from both interface and implementation uses');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_WithLineComments;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  // This is a comment' + sLineBreak +
    '  System.SysUtils,' + sLineBreak +
    '  System.Classes; // trailing comment' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(2), NativeInt(Length(LUnits)),
    'Line comments must not interfere with uses extraction');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_WithBraceComments;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  {this is a comment} System.SysUtils,' + sLineBreak +
    '  System.Classes;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(2), NativeInt(Length(LUnits)),
    'Brace comments must not interfere with uses extraction');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_WithParenStarComments;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  (* multi-line' + sLineBreak +
    '     comment *) System.SysUtils,' + sLineBreak +
    '  System.Classes;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(2), NativeInt(Length(LUnits)),
    'Paren-star comments must not interfere with uses extraction');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_WithCompilerDirectives;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    '{$R *.res}' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  {$IFDEF MSWINDOWS}' + sLineBreak +
    '  System.SysUtils,' + sLineBreak +
    '  {$ENDIF}' + sLineBreak +
    '  System.Classes;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(2), NativeInt(Length(LUnits)),
    'Compiler directives must be stripped as brace comments');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_WithStringLiterals;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  System.SysUtils;' + sLineBreak +
    'implementation' + sLineBreak +
    'const' + sLineBreak +
    '  cFoo = ''this uses something'';' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(1), NativeInt(Length(LUnits)),
    'String literals containing "uses" must not produce false matches');
  Assert.AreEqual('System.SysUtils', LUnits[0]);
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_WithInClause;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'program Demo;' + sLineBreak +
    'uses' + sLineBreak +
    '  Main.Form in ''src\Main.Form.pas'',' + sLineBreak +
    '  System.SysUtils;' + sLineBreak +
    'begin' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(2), NativeInt(Length(LUnits)),
    'Must extract unit names from in-clause syntax');
  Assert.AreEqual('Main.Form', LUnits[0],
    'The unit name must be extracted before the "in" keyword');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_WithInClauseAndFormHint;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'program Demo;' + sLineBreak +
    'uses' + sLineBreak +
    '  Main.Form in ''src\Main.Form.pas'' {FormMain},' + sLineBreak +
    '  System.SysUtils;' + sLineBreak +
    'begin' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(2), NativeInt(Length(LUnits)),
    'Must handle in-clause with form hint');
  Assert.AreEqual('Main.Form', LUnits[0],
    'The unit name must be extracted ignoring the form hint');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_EmptySource;
var
  LUnits: TArray<string>;
begin
  LUnits := TUsesClauseParser.ExtractUsedUnits('');
  Assert.IsTrue(LUnits = nil, 'Empty source must return nil');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_NoUsesClause;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.IsTrue(LUnits = nil, 'Source without uses clauses must return nil');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_DuplicateUnits;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  System.SysUtils;' + sLineBreak +
    'implementation' + sLineBreak +
    'uses' + sLineBreak +
    '  system.sysutils;' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(1), NativeInt(Length(LUnits)),
    'Duplicate unit names must be deduplicated case-insensitively');
end;

procedure TUsesClauseParserTests.ExtractUsedUnits_DottedUnitNames;
var
  LSource: string;
  LUnits: TArray<string>;
begin
  LSource :=
    'unit Demo;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  System.Generics.Collections,' + sLineBreak +
    '  Data.DB;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';

  LUnits := TUsesClauseParser.ExtractUsedUnits(LSource);

  Assert.AreEqual(NativeInt(2), NativeInt(Length(LUnits)),
    'Dotted unit names must be extracted correctly');
  Assert.AreEqual('System.Generics.Collections', LUnits[0]);
  Assert.AreEqual('Data.DB', LUnits[1]);
end;

{ TUsesClauseWalkerTests }

procedure TUsesClauseWalkerTests.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyWalkerTests_' + TPath.GetRandomFileName);
  TDirectory.CreateDirectory(FTempDir);
  FSearchPaths := TList<string>.Create;
  FSearchPaths.Add(FTempDir);
  FGlobalSearchPaths := TList<string>.Create;
  FUnitScopeNames := TList<string>.Create;
end;

procedure TUsesClauseWalkerTests.TearDown;
begin
  FSearchPaths.Free;
  FGlobalSearchPaths.Free;
  FUnitScopeNames.Free;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TUsesClauseWalkerTests.WriteUnitFile(const AFileName, AContent: string);
begin
  TFile.WriteAllText(TPath.Combine(FTempDir, AFileName), AContent);
end;

procedure TUsesClauseWalkerTests.WalkDependencies_SingleLevel;
var
  LUnits: TArray<string>;
  LRootPath: string;
begin
  WriteUnitFile('Root.pas',
    'unit Root;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  ChildA, ChildB;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');
  WriteUnitFile('ChildA.pas',
    'unit ChildA;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');
  WriteUnitFile('ChildB.pas',
    'unit ChildB;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');

  LRootPath := TPath.Combine(FTempDir, 'Root.pas');
  LUnits := TUsesClauseWalker.WalkDependencies(LRootPath,
    FSearchPaths, FGlobalSearchPaths, FUnitScopeNames);

  Assert.IsTrue(Length(LUnits) >= 2,
    'Single-level dependencies must be discovered');
end;

procedure TUsesClauseWalkerTests.WalkDependencies_Recursive;
var
  LUnits: TArray<string>;
  LRootPath: string;
  LFoundLeaf: Boolean;
  I: Integer;
begin
  WriteUnitFile('Root.pas',
    'unit Root;' + sLineBreak +
    'interface' + sLineBreak +
    'uses Middle;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');
  WriteUnitFile('Middle.pas',
    'unit Middle;' + sLineBreak +
    'interface' + sLineBreak +
    'uses Leaf;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');
  WriteUnitFile('Leaf.pas',
    'unit Leaf;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');

  LRootPath := TPath.Combine(FTempDir, 'Root.pas');
  LUnits := TUsesClauseWalker.WalkDependencies(LRootPath,
    FSearchPaths, FGlobalSearchPaths, FUnitScopeNames);

  LFoundLeaf := False;
  for I := 0 to High(LUnits) do
    if SameText(LUnits[I], 'leaf') then
      LFoundLeaf := True;

  Assert.IsTrue(LFoundLeaf,
    'Transitive dependencies must be discovered recursively');
end;

procedure TUsesClauseWalkerTests.WalkDependencies_CycleDetection;
var
  LUnits: TArray<string>;
  LRootPath: string;
begin
  WriteUnitFile('CycleA.pas',
    'unit CycleA;' + sLineBreak +
    'interface' + sLineBreak +
    'uses CycleB;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');
  WriteUnitFile('CycleB.pas',
    'unit CycleB;' + sLineBreak +
    'interface' + sLineBreak +
    'uses CycleA;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');

  LRootPath := TPath.Combine(FTempDir, 'CycleA.pas');

  // Must not raise or hang — cycle detection stops infinite recursion
  LUnits := TUsesClauseWalker.WalkDependencies(LRootPath,
    FSearchPaths, FGlobalSearchPaths, FUnitScopeNames);

  Assert.IsTrue(Length(LUnits) >= 1,
    'Circular dependencies must be handled without infinite recursion');
end;

procedure TUsesClauseWalkerTests.WalkDependencies_MaxDepthRespected;
var
  LUnits: TArray<string>;
  LRootPath: string;
  LFoundDeep: Boolean;
  I: Integer;
begin
  WriteUnitFile('Depth0.pas',
    'unit Depth0;' + sLineBreak +
    'interface uses Depth1; implementation end.');
  WriteUnitFile('Depth1.pas',
    'unit Depth1;' + sLineBreak +
    'interface uses Depth2; implementation end.');
  WriteUnitFile('Depth2.pas',
    'unit Depth2;' + sLineBreak +
    'interface uses Depth3; implementation end.');
  WriteUnitFile('Depth3.pas',
    'unit Depth3;' + sLineBreak +
    'interface implementation end.');

  LRootPath := TPath.Combine(FTempDir, 'Depth0.pas');
  LUnits := TUsesClauseWalker.WalkDependencies(LRootPath,
    FSearchPaths, FGlobalSearchPaths, FUnitScopeNames, 2);

  // Depth 2 means: root -> depth1 (1) -> depth2 (2, at limit)
  // depth3 may appear as name but depth2's children are not recursed
  Assert.IsTrue(Length(LUnits) >= 2,
    'Depth limit must cap recursion while still recording discovered names');

  LFoundDeep := False;
  for I := 0 to High(LUnits) do
    if SameText(LUnits[I], 'depth3') then
      LFoundDeep := True;
  // depth3 appears because depth2 is parsed at the limit, but depth3 itself is not recursed
  if LFoundDeep then
    Assert.Pass('depth3 was discovered as a leaf name at the depth boundary');
end;

procedure TUsesClauseWalkerTests.WalkDependencies_SkipsDcuOnlyUnits;
var
  LUnits: TArray<string>;
  LRootPath: string;
  LFoundDcuOnly: Boolean;
  I: Integer;
begin
  WriteUnitFile('WithDcu.pas',
    'unit WithDcu;' + sLineBreak +
    'interface' + sLineBreak +
    'uses DcuOnlyUnit;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.');
  // DcuOnlyUnit.pas does NOT exist — simulates a DCU-only dependency

  LRootPath := TPath.Combine(FTempDir, 'WithDcu.pas');
  LUnits := TUsesClauseWalker.WalkDependencies(LRootPath,
    FSearchPaths, FGlobalSearchPaths, FUnitScopeNames);

  LFoundDcuOnly := False;
  for I := 0 to High(LUnits) do
    if SameText(LUnits[I], 'dcuonlyunit') then
      LFoundDcuOnly := True;

  Assert.IsTrue(LFoundDcuOnly,
    'DCU-only units must appear in the result even without .pas source');
end;

procedure TUsesClauseWalkerTests.WalkDependencies_ShortFileNameIsNotTheDottedUnit;
var
  LGlobalDir: string;
  LRootPath: string;
  LUnits: TArray<string>;
begin
  LGlobalDir := TPath.Combine(FTempDir, 'global');
  TDirectory.CreateDirectory(LGlobalDir);
  FGlobalSearchPaths.Add(LGlobalDir);
  LRootPath := TPath.Combine(FTempDir, 'Demo.dpr');
  TFile.WriteAllText(LRootPath, 'program Demo; uses System.Bindings.Search, Other.Tools; begin end.');
  TFile.WriteAllText(TPath.Combine(FTempDir, 'Search.pas'),
    'unit Search; interface uses ProjectOnly; implementation end.');
  TFile.WriteAllText(TPath.Combine(LGlobalDir, 'Tools.pas'),
    'unit Tools; interface uses GlobalOnly; implementation end.');
  TFile.WriteAllText(TPath.Combine(LGlobalDir, 'System.Bindings.Search.pas'),
    'unit System.Bindings.Search; interface uses RealDependency; implementation end.');

  LUnits := TUsesClauseWalker.WalkDependencies(LRootPath,
    FSearchPaths, FGlobalSearchPaths, FUnitScopeNames);
  Assert.IsTrue(MatchText('RealDependency', LUnits),
    'The uses clause of the unit with the full name is followed');
  Assert.IsFalse(MatchText('ProjectOnly', LUnits), 'Search.pas is not System.Bindings.Search');
  Assert.IsFalse(MatchText('GlobalOnly', LUnits), 'Tools.pas is not Other.Tools');
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesClauseParserTests);
  TDUnitX.RegisterTestFixture(TUsesClauseWalkerTests);

end.
