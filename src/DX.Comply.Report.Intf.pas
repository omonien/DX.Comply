/// <summary>
/// DX.Comply.Report.Intf
/// Contracts for human-readable compliance reports.
/// </summary>
///
/// <remarks>
/// This unit defines the report configuration, normalized report payload and writer
/// abstraction used to generate Markdown and HTML companion reports next to the
/// formal SBOM artefact.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Report.Intf;

interface

uses
  System.Generics.Collections,
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.BuildOrchestrator,
  DX.Comply.Schema.Validator;

type
  /// <summary>
  /// Supported human-readable compliance report formats.
  /// </summary>
  THumanReadableReportFormat = (hrfMarkdown, hrfHtml, hrfBoth);

  /// <summary>
  /// Controls optional human-readable report generation.
  /// </summary>
  THumanReadableReportConfig = record
    Enabled: Boolean;
    Format: THumanReadableReportFormat;
    OutputBasePath: string;
    IncludeWarnings: Boolean;
    IncludeCompositionEvidence: Boolean;
    IncludeBuildEvidence: Boolean;
    class function Default: THumanReadableReportConfig; static;
  end;

  /// <summary>
  /// Normalized payload passed to report writers.
  /// </summary>
  TComplianceReportData = record
    SbomOutputPath: string;
    SbomFormat: TSbomFormat;
    Metadata: TSbomMetadata;
    ProjectInfo: TProjectInfo;
    BuildEvidence: TBuildEvidence;
    CompositionEvidence: TCompositionEvidence;
    Artefacts: TArtefactList;
    Warnings: TList<string>;
    DeepEvidenceRequested: Boolean;
    DeepEvidenceResult: TDeepEvidenceBuildResult;
    ValidationResult: TValidationResult;
    /// <summary>
    /// False when the SBOM was generated with composition evidence excluded
    /// (binary-only mode via --no-composition-evidence or config key).
    /// </summary>
    CompositionEvidenceIncluded: Boolean;
  end;

  /// <summary>
  /// Writes a human-readable compliance report.
  /// </summary>
  IHumanReadableReportWriter = interface
    ['{4FD4E8C2-E69C-40E2-AF0E-8E0D92E2148A}']
    /// <summary>
    /// Writes the report to the requested output file.
    /// </summary>
    function Write(const AOutputPath: string; const AData: TComplianceReportData;
      const AConfig: THumanReadableReportConfig): Boolean;
    /// <summary>
    /// Returns the report format handled by the writer.
    /// </summary>
    function GetFormat: THumanReadableReportFormat;
  end;

implementation

{ THumanReadableReportConfig }

class function THumanReadableReportConfig.Default: THumanReadableReportConfig;
begin
  Result.Enabled := False;
  Result.Format := hrfMarkdown;
  Result.OutputBasePath := '';
  Result.IncludeWarnings := True;
  Result.IncludeCompositionEvidence := True;
  Result.IncludeBuildEvidence := True;
end;

end.