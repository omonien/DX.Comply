/// <summary>
/// DX.Comply.Tests.MapFile.Reader
/// DUnitX tests for TMapFileReader.
/// </summary>
///
/// <remarks>
/// Uses synthetic detailed map-file snippets to verify unit extraction from
/// "Line numbers for ..." sections.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.MapFile.Reader;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.MapFile.Reader;

type
  /// <summary>
  /// DUnitX fixture for the map file reader.
  /// </summary>
  [TestFixture]
  TMapFileReaderTests = class
  public
    /// <summary>
    /// The reader must extract unique unit names from line-number sections.
    /// </summary>
    [Test]
    procedure ReadUnitNames_DetailedMap_ExtractsUniqueUnitNames;

    /// <summary>
    /// The reader must extract unit names from segment entries (M=UnitName).
    /// </summary>
    [Test]
    procedure ReadUnitNames_SegmentMap_ExtractsUnitNamesFromSegments;

    /// <summary>
    /// The reader must merge units from both line-number and segment sections.
    /// </summary>
    [Test]
    procedure ReadUnitNames_MixedMap_MergesLineNumbersAndSegments;

    /// <summary>
    /// The reader must produce unique unit names across both extraction methods.
    /// </summary>
    [Test]
    procedure ReadUnitNames_SegmentMap_DeduplicatesAcrossSections;

    /// <summary>
    /// Units come back in the order of their first appearance.
    /// </summary>
    [Test]
    procedure ReadUnitNames_ManyUnits_KeepsFirstAppearanceOrder;

    /// <summary>
    /// Names that differ only in case count once, with the first spelling.
    /// </summary>
    [Test]
    procedure ReadUnitNames_DifferentCase_KeepsFirstSpelling;

    /// <summary>
    /// 40,000 distinct units must not take quadratic time. The old list scan
    /// needed about 15 seconds for the dedupe alone. The bound is generous,
    /// because the per-line regex still costs a few seconds on slow machines.
    /// </summary>
    [Test]
    [Category('Performance')]
    procedure ReadUnitNames_FortyThousandUnits_DedupesInLinearTime;
  end;

implementation

uses
  System.Diagnostics,
  System.IOUtils,
  System.SysUtils;

procedure TMapFileReaderTests.ReadUnitNames_DetailedMap_ExtractsUniqueUnitNames;
var
  LMapContent: string;
  LMapFilePath: string;
  LUnitNames: TArray<string>;
begin
  LMapContent :=
    '  Detailed map of segments' + sLineBreak +
    sLineBreak +
    '  Line numbers for DX.Comply.Engine(DX.Comply.Engine.pas) segment CODE' + sLineBreak +
    '  Line numbers for System.SysUtils(System.SysUtils.pas) segment CODE' + sLineBreak +
    '  Line numbers for DX.Comply.Engine(DX.Comply.Engine.pas) segment DATA';

  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath, LMapContent, TEncoding.UTF8);
    LUnitNames := TMapFileReader.ReadUnitNames(LMapFilePath);

    Assert.AreEqual(NativeInt(2), NativeInt(Length(LUnitNames)),
      'The map file reader must return unique unit names only once');
    Assert.AreEqual('DX.Comply.Engine', LUnitNames[0],
      'The first extracted unit name must match the first line-number section');
    Assert.AreEqual('System.SysUtils', LUnitNames[1],
      'The second extracted unit name must match the next unique line-number section');
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TMapFileReaderTests.ReadUnitNames_SegmentMap_ExtractsUnitNamesFromSegments;
var
  LMapContent: string;
  LMapFilePath: string;
  LUnitNames: TArray<string>;
begin
  LMapContent :=
    'Start         Length     Name                   Class' + sLineBreak +
    ' 0001:00401000 00683DB8H .text                   CODE' + sLineBreak +
    sLineBreak +
    'Detailed map of segments' + sLineBreak +
    sLineBreak +
    ' 0001:00000000 00010F9C C=CODE     S=.text    G=(none)   M=System   ACBP=A9' + sLineBreak +
    ' 0001:00010F9C 00000C98 C=CODE     S=.text    G=(none)   M=SysInit  ACBP=A9' + sLineBreak +
    ' 0001:00011C34 0000547C C=CODE     S=.text    G=(none)   M=System.Types ACBP=A9' + sLineBreak +
    ' 0001:000170B0 00000C68 C=CODE     S=.text    G=(none)   M=System.UITypes ACBP=A9';

  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath, LMapContent, TEncoding.UTF8);
    LUnitNames := TMapFileReader.ReadUnitNames(LMapFilePath);

    Assert.AreEqual(NativeInt(4), NativeInt(Length(LUnitNames)),
      'The reader must extract unit names from M= segment entries');
    Assert.AreEqual('System', LUnitNames[0]);
    Assert.AreEqual('SysInit', LUnitNames[1]);
    Assert.AreEqual('System.Types', LUnitNames[2]);
    Assert.AreEqual('System.UITypes', LUnitNames[3]);
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TMapFileReaderTests.ReadUnitNames_MixedMap_MergesLineNumbersAndSegments;
var
  LMapContent: string;
  LMapFilePath: string;
  LUnitNames: TArray<string>;
begin
  LMapContent :=
    'Detailed map of segments' + sLineBreak +
    ' 0001:00000000 00010F9C C=CODE     S=.text    G=(none)   M=System   ACBP=A9' + sLineBreak +
    ' 0001:00010F9C 00000C98 C=CODE     S=.text    G=(none)   M=SysInit  ACBP=A9' + sLineBreak +
    sLineBreak +
    '  Line numbers for DX.Comply.Engine(DX.Comply.Engine.pas) segment CODE' + sLineBreak +
    '  Line numbers for DX.Comply.Utils(DX.Comply.Utils.pas) segment CODE';

  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath, LMapContent, TEncoding.UTF8);
    LUnitNames := TMapFileReader.ReadUnitNames(LMapFilePath);

    Assert.AreEqual(NativeInt(4), NativeInt(Length(LUnitNames)),
      'The reader must collect units from both segment entries and line-number sections');
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TMapFileReaderTests.ReadUnitNames_SegmentMap_DeduplicatesAcrossSections;
var
  LMapContent: string;
  LMapFilePath: string;
  LUnitNames: TArray<string>;
begin
  LMapContent :=
    'Detailed map of segments' + sLineBreak +
    ' 0001:00000000 00010F9C C=CODE     S=.text    G=(none)   M=System.SysUtils ACBP=A9' + sLineBreak +
    ' 0001:00010F9C 00000C98 C=CODE     S=.text    G=(none)   M=System.SysUtils ACBP=A9' + sLineBreak +
    sLineBreak +
    '  Line numbers for System.SysUtils(System.SysUtils.pas) segment CODE';

  LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath, LMapContent, TEncoding.UTF8);
    LUnitNames := TMapFileReader.ReadUnitNames(LMapFilePath);

    Assert.AreEqual(NativeInt(1), NativeInt(Length(LUnitNames)),
      'Duplicate unit names from segments and line-number sections must be deduplicated');
    Assert.AreEqual('System.SysUtils', LUnitNames[0]);
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TMapFileReaderTests.ReadUnitNames_ManyUnits_KeepsFirstAppearanceOrder;
begin
  var LMapContent :=
    '  Line numbers for Zeta.Unit(Zeta.Unit.pas) segment CODE' + sLineBreak +
    ' 0001:00000000 00000010 C=CODE     S=.text    G=(none)   M=Alpha.Unit ACBP=A9' + sLineBreak +
    '  Line numbers for Zeta.Unit(Zeta.Unit.pas) segment ICODE' + sLineBreak +
    ' 0001:00000010 00000010 C=CODE     S=.text    G=(none)   M=Mid.Unit ACBP=A9' + sLineBreak +
    '  Line numbers for Alpha.Unit(Alpha.Unit.pas) segment CODE';

  var LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath, LMapContent, TEncoding.UTF8);
    var LUnitNames := TMapFileReader.ReadUnitNames(LMapFilePath);

    Assert.AreEqual(NativeInt(3), NativeInt(Length(LUnitNames)));
    Assert.AreEqual('Zeta.Unit', LUnitNames[0]);
    Assert.AreEqual('Alpha.Unit', LUnitNames[1]);
    Assert.AreEqual('Mid.Unit', LUnitNames[2]);
  finally
    if TFile.Exists(LMapFilePath) then
    begin
      TFile.Delete(LMapFilePath);
    end;
  end;
end;

procedure TMapFileReaderTests.ReadUnitNames_DifferentCase_KeepsFirstSpelling;
begin
  var LMapContent :=
    ' 0001:00000000 00000010 C=CODE     S=.text    G=(none)   M=Vcl.Forms ACBP=A9' + sLineBreak +
    ' 0001:00000010 00000010 C=CODE     S=.text    G=(none)   M=VCL.FORMS ACBP=A9' + sLineBreak +
    '  Line numbers for vcl.forms(Vcl.Forms.pas) segment CODE';

  var LMapFilePath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LMapFilePath, LMapContent, TEncoding.UTF8);
    var LUnitNames := TMapFileReader.ReadUnitNames(LMapFilePath);

    Assert.AreEqual(NativeInt(1), NativeInt(Length(LUnitNames)),
      'Unit names that differ only in case must be deduplicated');
    Assert.AreEqual('Vcl.Forms', LUnitNames[0]);
  finally
    if TFile.Exists(LMapFilePath) then
    begin
      TFile.Delete(LMapFilePath);
    end;
  end;
end;

procedure TMapFileReaderTests.ReadUnitNames_FortyThousandUnits_DedupesInLinearTime;
const
  cUnitCount = 40000;
  cMaxMilliseconds = 20000;
begin
  var LMapFilePath := TPath.GetTempFileName;
  try
    var LBuilder := TStringBuilder.Create;
    try
      for var i := 0 to cUnitCount - 1 do
      begin
        // One segment entry per unit keeps the line count, and with it the
        // regex cost, low, so the time is mostly the dedupe.
        LBuilder.AppendFormat(' 0001:00000000 00000010 C=CODE     S=.text    G=(none)   M=Unit%d ACBP=A9', [i]);
        LBuilder.AppendLine;
      end;
      TFile.WriteAllText(LMapFilePath, LBuilder.ToString, TEncoding.UTF8);
    finally
      LBuilder.Free;
    end;

    var LStopwatch := TStopwatch.StartNew;
    var LUnitNames := TMapFileReader.ReadUnitNames(LMapFilePath);
    LStopwatch.Stop;

    Assert.AreEqual(NativeInt(cUnitCount), NativeInt(Length(LUnitNames)),
      'Every synthetic unit must be extracted once');
    Assert.AreEqual('Unit0', LUnitNames[0]);
    Assert.AreEqual('Unit' + IntToStr(cUnitCount - 1), LUnitNames[cUnitCount - 1]);
    Assert.IsTrue(LStopwatch.ElapsedMilliseconds < cMaxMilliseconds,
      Format('Reading %d units took %d ms, limit is %d ms',
        [cUnitCount, LStopwatch.ElapsedMilliseconds, cMaxMilliseconds]));
  finally
    if TFile.Exists(LMapFilePath) then
    begin
      TFile.Delete(LMapFilePath);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMapFileReaderTests);

end.