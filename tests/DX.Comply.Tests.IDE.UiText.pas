/// <summary>
/// DX.Comply.Tests.IDE.UiText
/// DUnitX tests for shared IDE UI caption strings.
/// </summary>
///
/// <remarks>
/// Locks the progress-dialog failure wording (issue #86) without loading VCL.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.IDE.UiText;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  /// DUnitX fixture for DX.Comply.IDE.UiText constants.
  /// </summary>
  [TestFixture]
  TIDEUiTextTests = class
  public
    [Test]
    procedure GenerationFailedHint_PointsAtLogBelow;
  end;

implementation

uses
  System.SysUtils,
  DX.Comply.IDE.UiText;

procedure TIDEUiTextTests.GenerationFailedHint_PointsAtLogBelow;
begin
  Assert.AreEqual(
    'Generation failed - check the log output in this dialog below.',
    scProgressDialogGenerationFailedCheckLog);
  Assert.IsTrue(scProgressDialogGenerationFailedCheckLog.Contains('below'));
  Assert.IsFalse(scProgressDialogGenerationFailedCheckLog.Contains('above'));
end;

initialization
  TDUnitX.RegisterTestFixture(TIDEUiTextTests);

end.
