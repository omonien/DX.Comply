/// <summary>
/// DX.Comply.Report.Intf
/// Contracts for human-readable SBOM reports.
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
  DX.Comply.Schema.Validator;

type
  /// <summary>
  /// Supported human-readable SBOM report formats.
  /// </summary>
  THumanReadableReportFormat = (hrfMarkdown, hrfHtml, hrfBoth);

  /// <summary>
  /// Selects the sections of a human-readable report (issue #126).
  /// hrcAll writes the overview sections and the unit list, hrcOverview
  /// only the overview sections (origin summary, licences, third-party
  /// units without manifest), hrcUnits only the unit list with hashes.
  /// The SBOM itself is not affected.
  /// </summary>
  THumanReadableReportContent = (hrcAll, hrcOverview, hrcUnits);

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
    Content: THumanReadableReportContent;
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
    ValidationResult: TValidationResult;
    /// <summary>
    /// False when the SBOM was generated with composition evidence excluded
    /// (binary-only mode via --no-composition-evidence or config key).
    /// </summary>
    CompositionEvidenceIncluded: Boolean;
  end;

  /// <summary>
  /// Writes a human-readable SBOM report.
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

/// <summary>
/// Converts a report content value to its option text: all, overview or units.
/// </summary>
function ReportContentToString(AValue: THumanReadableReportContent): string;

/// <summary>
/// Parses all, overview or units (case-insensitive). Returns False for
/// anything else and leaves AValue unchanged.
/// </summary>
function TryParseReportContent(const AText: string;
  var AValue: THumanReadableReportContent): Boolean;

implementation

uses
  System.SysUtils;

function ReportContentToString(AValue: THumanReadableReportContent): string;
begin
  case AValue of
    hrcOverview: Result := 'overview';
    hrcUnits: Result := 'units';
  else
    Result := 'all';
  end;
end;

function TryParseReportContent(const AText: string;
  var AValue: THumanReadableReportContent): Boolean;
var
  LText: string;
begin
  LText := LowerCase(Trim(AText));
  Result := True;
  if LText = 'all' then
    AValue := hrcAll
  else if LText = 'overview' then
    AValue := hrcOverview
  else if LText = 'units' then
    AValue := hrcUnits
  else
    Result := False;
end;

{ THumanReadableReportConfig }

class function THumanReadableReportConfig.Default: THumanReadableReportConfig;
begin
  Result.Enabled := False;
  Result.Format := hrfMarkdown;
  Result.OutputBasePath := '';
  Result.IncludeWarnings := True;
  Result.IncludeCompositionEvidence := True;
  Result.IncludeBuildEvidence := True;
  Result.Content := hrcAll;
end;

end.