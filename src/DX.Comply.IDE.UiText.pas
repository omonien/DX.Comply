/// <summary>
/// DX.Comply.IDE.UiText
/// Shared UI strings for the DX.Comply IDE package that stay free of VCL.
/// </summary>
///
/// <remarks>
/// Keeping a few caption strings here lets the console test suite lock the
/// wording without pulling Vcl.Forms into DX.Comply.Tests.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.UiText;

interface

const
  /// <summary>
  /// Failure hint on the SBOM progress dialog. The log memo sits below the
  /// step label (issue #86).
  /// </summary>
  scProgressDialogGenerationFailedCheckLog =
    'Generation failed - check the log output in this dialog below.';

implementation

end.
