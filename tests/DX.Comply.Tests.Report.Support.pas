/// <summary>
/// DX.Comply.Tests.Report.Support
/// DUnitX tests for human-readable UTC timestamps.
/// </summary>
///
/// <remarks>
/// FormatReportUtcTimestamp is shared by the HTML and Markdown reports.
/// These tests cover that helper, and they check that CycloneDX JSON,
/// CycloneDX XML, SPDX 2.3 and SPDX 3.0.1 still write YYYY-MM-DDThh:mm:ssZ.
/// Issue #208.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Report.Support;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  /// DUnitX fixture for report timestamps and unchanged SBOM timestamps.
  /// </summary>
  [TestFixture]
  TReportTimestampTests = class
  public
    /// <summary>
    /// A Zulu timestamp, a lowercase z, a value with no zone, and fractional
    /// seconds become YYYY-MM-DD hh:mm:ss UTC.
    /// </summary>
    [Test]
    procedure FormatReportUtcTimestamp_ShowsUtcLabel;
    /// <summary>
    /// An offset is converted to the UTC clock before the label is added.
    /// </summary>
    [Test]
    procedure FormatReportUtcTimestamp_ConvertsOffset;
    /// <summary>
    /// Empty text, a version, and any other non-timestamp stay unchanged.
    /// </summary>
    [Test]
    procedure FormatReportUtcTimestamp_LeavesOtherText;
    /// <summary>
    /// CycloneDX JSON, CycloneDX XML, SPDX 2.3 and SPDX 3.0.1 keep
    /// YYYY-MM-DDThh:mm:ssZ for the generation time and for a file-date version.
    /// </summary>
    [Test]
    procedure SbomWriters_KeepRfc3339Timestamp;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Engine.Intf,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.CycloneDx.XmlWriter,
  DX.Comply.Report.Support,
  DX.Comply.Spdx.Writer,
  DX.Comply.Spdx3.Writer;

procedure TReportTimestampTests.FormatReportUtcTimestamp_ShowsUtcLabel;
begin
  Assert.AreEqual('2026-11-20 21:11:57 UTC',
    FormatReportUtcTimestamp('2026-11-20T21:11:57Z'));
  Assert.AreEqual('2026-11-20 21:11:57 UTC',
    FormatReportUtcTimestamp('2026-11-20t21:11:57z'));
  Assert.AreEqual('2026-11-20 21:11:57 UTC',
    FormatReportUtcTimestamp('  2026-11-20T21:11:57Z  '));
  Assert.AreEqual('2026-01-01 00:00:00 UTC',
    FormatReportUtcTimestamp('2026-01-01T00:00:00'));
  Assert.AreEqual('2026-02-24 10:00:00 UTC',
    FormatReportUtcTimestamp('2026-02-24T10:00:00.895Z'));
end;

procedure TReportTimestampTests.FormatReportUtcTimestamp_ConvertsOffset;
begin
  Assert.AreEqual('2026-05-18 04:27:39 UTC',
    FormatReportUtcTimestamp('2026-05-18T14:27:39.895+10:00'));
  Assert.AreEqual('2025-12-31 15:30:00 UTC',
    FormatReportUtcTimestamp('2026-01-01T01:30:00+10:00'));
  Assert.AreEqual('2026-02-24 15:00:00 UTC',
    FormatReportUtcTimestamp('2026-02-24T10:00:00-05:00'));
end;

procedure TReportTimestampTests.FormatReportUtcTimestamp_LeavesOtherText;
begin
  Assert.AreEqual('', FormatReportUtcTimestamp(''));
  Assert.AreEqual('n/a', FormatReportUtcTimestamp('n/a'));
  Assert.AreEqual('2.0.0.1', FormatReportUtcTimestamp('2.0.0.1'));
  Assert.AreEqual('10.0.19041.1', FormatReportUtcTimestamp('10.0.19041.1'));
  Assert.AreEqual('not a timestamp', FormatReportUtcTimestamp('not a timestamp'));
  Assert.AreEqual('2026-11-20', FormatReportUtcTimestamp('2026-11-20'));
  Assert.AreEqual('2026-11-20 21:11:57 UTC',
    FormatReportUtcTimestamp('2026-11-20 21:11:57 UTC'));
  Assert.AreEqual('2026-02-31T00:00:00Z',
    FormatReportUtcTimestamp('2026-02-31T00:00:00Z'));
end;

procedure TReportTimestampTests.SbomWriters_KeepRfc3339Timestamp;
const
  cGenerated = '2026-11-20T21:11:57Z';
  cFileDate = '2020-01-02T03:04:05Z';
  cGeneratedLabel = '2026-11-20 21:11:57 UTC';
  cFileDateLabel = '2020-01-02 03:04:05 UTC';
var
  LArtefact: TArtefactInfo;
  LArtefacts: TArtefactList;
  LContent: string;
  LDir: string;
  LGuid: TGUID;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LWriter: ISbomWriter;

  procedure CheckFile(const APath, ALabel: string);
  begin
    Assert.IsTrue(TFile.Exists(APath), ALabel + ' file must be written');
    LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
    Assert.IsTrue(Pos(cGenerated, LContent) > 0,
      ALabel + ' keeps the RFC 3339 generation time');
    Assert.AreEqual<Integer>(0, Pos(cGeneratedLabel, LContent),
      ALabel + ' does not use the report label for the generation time');
    Assert.IsTrue(Pos(cFileDate, LContent) > 0,
      ALabel + ' keeps a file-date version as RFC 3339');
    Assert.AreEqual<Integer>(0, Pos(cFileDateLabel, LContent),
      ALabel + ' does not label a file-date version');
  end;

begin
  CreateGUID(LGuid);
  LDir := TPath.Combine(TPath.GetTempPath, 'dx-comply-utc-' +
    GUIDToString(LGuid).Trim(['{', '}']));
  TDirectory.CreateDirectory(LDir);
  LArtefacts := TArtefactList.Create;
  LProject := TProjectInfo.Create;
  try
    LMetadata := Default(TSbomMetadata);
    LMetadata.ProductName := 'TestApp';
    LMetadata.Supplier := 'Test Supplier';
    LMetadata.Timestamp := cGenerated;
    LMetadata.ToolName := 'DX.Comply';

    // No product version, so a file-date stand-in is not replaced on the
    // built program. The SBOM must keep the RFC 3339 text.
    LProject.ProjectName := 'OtherApp';
    LProject.ProjectDir := LDir;
    LProject.OutputDir := LDir;

    LArtefact := Default(TArtefactInfo);
    LArtefact.RelativePath := 'old.dll';
    LArtefact.FilePath := TPath.Combine(LDir, 'old.dll');
    LArtefact.ArtefactType := 'library';
    LArtefact.Version := cFileDate;
    LArtefact.VersionFromFileDate := True;
    LArtefacts.Add(LArtefact);

    LWriter := TCycloneDxJsonWriter.Create;
    Assert.IsTrue(LWriter.Write(TPath.Combine(LDir, 'bom.json'), LMetadata,
      LArtefacts, LProject));
    CheckFile(TPath.Combine(LDir, 'bom.json'), 'CycloneDX JSON');

    LWriter := TCycloneDxXmlWriter.Create;
    Assert.IsTrue(LWriter.Write(TPath.Combine(LDir, 'bom.xml'), LMetadata,
      LArtefacts, LProject));
    CheckFile(TPath.Combine(LDir, 'bom.xml'), 'CycloneDX XML');

    LWriter := TSpdxJsonWriter.Create;
    Assert.IsTrue(LWriter.Write(TPath.Combine(LDir, 'bom.spdx.json'), LMetadata,
      LArtefacts, LProject));
    CheckFile(TPath.Combine(LDir, 'bom.spdx.json'), 'SPDX 2.3');

    LWriter := TSpdx3JsonWriter.Create;
    Assert.IsTrue(LWriter.Write(TPath.Combine(LDir, 'bom.spdx3.json'), LMetadata,
      LArtefacts, LProject));
    CheckFile(TPath.Combine(LDir, 'bom.spdx3.json'), 'SPDX 3.0.1');
  finally
    LWriter := nil;
    LArtefacts.Free;
    LProject.Free;
    if TDirectory.Exists(LDir) then
      TDirectory.Delete(LDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TReportTimestampTests);

end.
