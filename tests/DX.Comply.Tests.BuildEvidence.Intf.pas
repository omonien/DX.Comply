/// <summary>
/// DX.Comply.Tests.BuildEvidence.Intf
/// DUnitX tests for build evidence contracts.
/// </summary>
///
/// <remarks>
/// Verifies that the record-based evidence models correctly initialize and free
/// their owned lists. This keeps the first implementation slice safe before
/// reader and resolver implementations are added.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.BuildEvidence.Intf;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.BuildEvidence.Intf;

type
  /// <summary>
  /// DUnitX fixture for build evidence contracts.
  /// </summary>
  [TestFixture]
  TBuildEvidenceIntfTests = class
  public
    /// <summary>
    /// TBuildEvidence.Create must initialize all owned lists.
    /// </summary>
    [Test]
    procedure BuildEvidence_Create_InitializesOwnedLists;

    /// <summary>
    /// TCompositionEvidence.Create must initialize all owned lists.
    /// </summary>
    [Test]
    procedure CompositionEvidence_Create_InitializesOwnedLists;
  end;

implementation

procedure TBuildEvidenceIntfTests.BuildEvidence_Create_InitializesOwnedLists;
var
  LBuildEvidence: TBuildEvidence;
begin
  LBuildEvidence := TBuildEvidence.Create;
  try
    Assert.IsNotNull(LBuildEvidence.SearchPaths,
      'SearchPaths must be assigned after TBuildEvidence.Create');
    Assert.IsNotNull(LBuildEvidence.UnitScopeNames,
      'UnitScopeNames must be assigned after TBuildEvidence.Create');
    Assert.IsNotNull(LBuildEvidence.RuntimePackages,
      'RuntimePackages must be assigned after TBuildEvidence.Create');
    Assert.IsNotNull(LBuildEvidence.EvidenceItems,
      'EvidenceItems must be assigned after TBuildEvidence.Create');
    Assert.IsNotNull(LBuildEvidence.Warnings,
      'Warnings must be assigned after TBuildEvidence.Create');
  finally
    LBuildEvidence.Free;
  end;
end;

procedure TBuildEvidenceIntfTests.CompositionEvidence_Create_InitializesOwnedLists;
var
  LCompositionEvidence: TCompositionEvidence;
begin
  LCompositionEvidence := TCompositionEvidence.Create;
  try
    Assert.IsNotNull(LCompositionEvidence.Units,
      'Units must be assigned after TCompositionEvidence.Create');
    Assert.IsNotNull(LCompositionEvidence.Warnings,
      'Warnings must be assigned after TCompositionEvidence.Create');
  finally
    LCompositionEvidence.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildEvidenceIntfTests);

end.