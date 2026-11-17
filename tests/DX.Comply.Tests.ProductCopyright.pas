/// <summary>
/// DX.Comply.Tests.ProductCopyright
/// DUnitX tests for the product copyright notice.
/// </summary>
///
/// <remarks>
/// The notice comes from LegalCopyright on the built binary. A non-empty
/// copyright value in .dxcomply.json wins, including in library mode.
/// When both are empty, CycloneDX omits copyright, SPDX 2.3 keeps
/// copyrightText as NOASSERTION, and SPDX 3.0.1 omits software_copyrightText.
/// A manifest row keeps its own copyright. A neighbour binary stays empty.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.ProductCopyright;

interface

uses
  DUnitX.TestFramework,
  System.Classes,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// DUnitX fixture for product, own-binary, and own-code copyright.
  /// </summary>
  [TestFixture]
  TProductCopyrightTests = class
  private
    FTempDir: string;
    FProgress: TStringList;
    procedure OnProgress(const AMessage: string; const AProgress: Integer);
    function GenerateProject(const AProject: string; const AConfig: TSbomConfig;
      const AOutput: string; AFormat: TSbomFormat): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    /// <summary>
    /// LegalCopyright on the built binary is written on the product, on
    /// every copy of that binary, and on own-code units. A manifest row
    /// and a neighbour binary are left alone.
    /// </summary>
    [Test]
    procedure Automatic_LegalCopyright_OnProductOwnBinaryAndOwnCode;

    /// <summary>
    /// A non-empty copyright value wins over LegalCopyright.
    /// </summary>
    [Test]
    procedure Override_ConfigKey_WinsOverLegalCopyright;

    /// <summary>
    /// Library mode applies the same key to the product and to own-code
    /// source files.
    /// </summary>
    [Test]
    procedure Override_LibraryMode_ConfigKeyWins;

    /// <summary>
    /// Spaces are not a notice, so LegalCopyright is still read.
    /// </summary>
    [Test]
    procedure BlankCopyright_FallsThroughToLegalCopyright;

    /// <summary>
    /// No key and no LegalCopyright keeps the previous output.
    /// </summary>
    [Test]
    procedure Empty_OmitsCopyrightAndKeepsNoAssertion;

    /// <summary>
    /// The file key is trimmed. A blank value and a non-string are ignored.
    /// </summary>
    [Test]
    procedure LoadConfig_TrimsString_AndIgnoresBadValues;
  end;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  DX.Comply.Report.Intf,
  DX.Comply.Tests.Paths,
  DX.Comply.VersionInfo;

const
  cOverrideNotice = 'Copyright (c) 1999 Example Ltd';
  cRowCopyright = '2020';
  cBuildDproj =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>MyApp.dpr</MainSource>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\out</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak;
  cBuildDpr = 'program MyApp;' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak;
  cBuildMap =
    '  Line numbers for MainForm(MainForm.pas) segment .text' + sLineBreak +
    '  Line numbers for OtherUnit(OtherUnit.pas) segment .text' + sLineBreak;
  cBuildManifest =
    '{' + sLineBreak +
    '  "schema_version": "1.0",' + sLineBreak +
    '  "components": [' + sLineBreak +
    '    {"name": "VendorLib", "version": "1.2.3", "copyright": "2020",' + sLineBreak +
    '     "units_exact": ["OtherUnit"]}' + sLineBreak +
    '  ],' + sLineBreak +
    '  "own_code_units": ["MainForm"]' + sLineBreak +
    '}' + sLineBreak;

type
  TBuildFixture = record
    Project: string;
    ExePath: string;
    Manifest: string;
    ReportBase: string;
  end;

function VersionFixture(const AFileName: string): string;
begin
  Result := TPath.Combine(RepoRoot, 'tests' + PathDelim + 'fixtures' +
    PathDelim + 'binaries' + PathDelim + AFileName);
end;

function UnitSource(const AUnitName: string): string;
begin
  Result := 'unit ' + AUnitName + ';' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'end.' + sLineBreak;
end;

procedure CopyFileChecked(const ASource, ADest: string);
begin
  Assert.IsTrue(TFile.Exists(ASource), ASource);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(ADest));
  TFile.Copy(ASource, ADest, True);
end;

function TextPos(const AText, APart: string; AStart: Integer): Integer;
var
  LRest: string;
begin
  if AStart < 1 then
    AStart := 1;
  if (APart = '') or (AStart > Length(AText)) then
    Exit(0);
  LRest := Copy(AText, AStart, MaxInt);
  Result := Pos(APart, LRest);
  if Result > 0 then
    Result := Result + AStart - 1;
end;

function CountText(const AText, APart: string): Integer;
var
  LPos: Integer;
begin
  Result := 0;
  if APart = '' then
    Exit;
  LPos := Pos(APart, AText);
  while LPos > 0 do
  begin
    Inc(Result);
    LPos := TextPos(AText, APart, LPos + Length(APart));
  end;
end;

function Between(const AText, AStart, AEnd: string): string;
var
  LFrom: Integer;
  LTo: Integer;
begin
  Result := '';
  LFrom := Pos(AStart, AText);
  if LFrom = 0 then
    Exit;
  LFrom := LFrom + Length(AStart);
  LTo := TextPos(AText, AEnd, LFrom);
  if LTo = 0 then
    Result := Copy(AText, LFrom, MaxInt)
  else
    Result := Copy(AText, LFrom, LTo - LFrom);
end;

function FileTitle(const AName: string): string;
var
  LPos: Integer;
  LSlash: Integer;
begin
  LSlash := 0;
  for LPos := 1 to Length(AName) do
    if (AName[LPos] = '\') or (AName[LPos] = '/') then
      LSlash := LPos;
  if LSlash = 0 then
    Result := AName
  else
    Result := Copy(AName, LSlash + 1, MaxInt);
end;

function NameMatches(const AName, AWanted: string): Boolean;
begin
  Result := SameText(AName, AWanted) or SameText(FileTitle(AName), AWanted);
end;

function JsonNames(const AItems: TJSONArray): string;
var
  I: Integer;
  LValue: TJSONValue;
begin
  Result := '';
  if AItems = nil then
    Exit;
  for I := 0 to AItems.Count - 1 do
  begin
    if not (AItems.Items[I] is TJSONObject) then
      Continue;
    LValue := TJSONObject(AItems.Items[I]).GetValue('name');
    if LValue is TJSONString then
      Result := Result + LValue.Value + ', ';
  end;
end;

function JsonArray(const AObject: TJSONObject; const AName: string): TJSONArray;
var
  LValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  LValue := AObject.GetValue(AName);
  if LValue is TJSONArray then
    Result := TJSONArray(LValue);
end;

function MetadataComponent(const ARoot: TJSONObject): TJSONObject;
var
  LMeta: TJSONValue;
  LComponent: TJSONValue;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  LMeta := ARoot.GetValue('metadata');
  if not (LMeta is TJSONObject) then
    Exit;
  LComponent := TJSONObject(LMeta).GetValue('component');
  if LComponent is TJSONObject then
    Result := TJSONObject(LComponent);
end;

function JsonField(const AObject: TJSONObject; const AName: string): TJSONValue;
begin
  Result := nil;
  if AObject <> nil then
    Result := AObject.GetValue(AName);
end;

function RequiredJsonText(const AObject: TJSONObject; const AName: string): string;
var
  LField: TJSONValue;
begin
  LField := JsonField(AObject, AName);
  Assert.IsTrue(LField is TJSONString, 'missing ' + AName);
  Result := LField.Value;
end;

function ParseRoot(const APath: string): TJSONObject;
var
  LContent: string;
  LValue: TJSONValue;
begin
  LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
  LValue := TJSONObject.ParseJSONValue(LContent);
  Assert.IsTrue(LValue is TJSONObject, Copy(LContent, 1, 400));
  Result := TJSONObject(LValue);
end;

procedure AssertNamedField(const AItems: TJSONArray; const AField, AName,
  AExpected: string; AMinCount, AMaxCount: Integer; AOmitWhenEmpty: Boolean);
var
  I: Integer;
  LFound: Integer;
  LObject: TJSONObject;
  LName: TJSONValue;
  LField: TJSONValue;
  LNames: string;
begin
  LFound := 0;
  LNames := JsonNames(AItems);
  if AItems <> nil then
    for I := 0 to AItems.Count - 1 do
    begin
      if not (AItems.Items[I] is TJSONObject) then
        Continue;
      LObject := TJSONObject(AItems.Items[I]);
      LName := LObject.GetValue('name');
      if not (LName is TJSONString) then
        Continue;
      if not NameMatches(LName.Value, AName) then
        Continue;
      Inc(LFound);
      LField := LObject.GetValue(AField);
      if AExpected = '' then
      begin
        if AOmitWhenEmpty then
          Assert.IsNull(LField, AName + ' must omit ' + AField + '. Names: ' + LNames)
        else
          Assert.AreEqual('', LField.Value, AName);
      end
      else
      begin
        Assert.IsTrue(LField is TJSONString, AName + ' is missing ' + AField +
          '. Names: ' + LNames);
        Assert.AreEqual(AExpected, LField.Value, AName + ' ' + AField);
      end;
    end;
  Assert.IsTrue(LFound >= AMinCount, AName + ' count ' + IntToStr(LFound) +
    ' is below ' + IntToStr(AMinCount) + '. Names: ' + LNames);
  if AMaxCount >= 0 then
    Assert.AreEqual(AMaxCount, LFound, AName + ' count. Names: ' + LNames);
end;

procedure AssertJsonCopyright(const AItems: TJSONArray; const AName, AExpected: string;
  AMinCount, AMaxCount: Integer);
begin
  AssertNamedField(AItems, 'copyright', AName, AExpected, AMinCount, AMaxCount, True);
end;

procedure AssertSpdxCopyright(const AItems: TJSONArray; const AName, AExpected: string;
  AMinCount, AMaxCount: Integer);
begin
  AssertNamedField(AItems, 'copyrightText', AName, AExpected, AMinCount, AMaxCount, False);
end;

procedure AssertSpdx3Copyright(const AItems: TJSONArray; const AName, AExpected: string;
  AMinCount, AMaxCount: Integer);
var
  I: Integer;
  LFound: Integer;
  LObject: TJSONObject;
  LName: TJSONValue;
  LType: TJSONValue;
  LField: TJSONValue;
  LNames: string;
begin
  LFound := 0;
  LNames := JsonNames(AItems);
  if AItems <> nil then
    for I := 0 to AItems.Count - 1 do
    begin
      if not (AItems.Items[I] is TJSONObject) then
        Continue;
      LObject := TJSONObject(AItems.Items[I]);
      LType := LObject.GetValue('type');
      if (LType is TJSONString) and not SameText(LType.Value, 'software_Package') then
        Continue;
      LName := LObject.GetValue('name');
      if not (LName is TJSONString) then
        Continue;
      if not NameMatches(LName.Value, AName) then
        Continue;
      Inc(LFound);
      LField := LObject.GetValue('software_copyrightText');
      if AExpected = '' then
        Assert.IsNull(LField, AName + ' must omit software_copyrightText. Names: ' + LNames)
      else
      begin
        Assert.IsTrue(LField is TJSONString, AName + ' is missing software_copyrightText');
        Assert.AreEqual(AExpected, LField.Value, AName);
      end;
    end;
  Assert.IsTrue(LFound >= AMinCount, AName + ' SPDX 3 count ' + IntToStr(LFound) +
    '. Names: ' + LNames);
  if AMaxCount >= 0 then
    Assert.AreEqual(AMaxCount, LFound, AName + ' SPDX 3 count. Names: ' + LNames);
end;

function XmlEscape(const AValue: string): string;
begin
  Result := AValue;
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

function HtmlEscape(const AValue: string): string;
begin
  Result := StringReplace(AValue, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function XmlComponent(const AXml, AName: string): string;
var
  LNamePos: Integer;
  LStart: Integer;
  LFound: Integer;
  LPos: Integer;
  LEnd: Integer;
begin
  Result := '';
  LNamePos := Pos('<name>' + AName + '</name>', AXml);
  if LNamePos = 0 then
    Exit;
  LFound := 0;
  LPos := Pos('<component', AXml);
  while (LPos > 0) and (LPos < LNamePos) do
  begin
    LFound := LPos;
    LPos := TextPos(AXml, '<component', LPos + 1);
  end;
  LStart := LFound;
  if LStart = 0 then
    LStart := 1;
  LEnd := TextPos(AXml, '</component>', LNamePos);
  if LEnd = 0 then
    Exit;
  Result := Copy(AXml, LStart, LEnd + Length('</component>') - LStart);
end;

function CopyrightElement(const ANotice: string): string;
begin
  Result := '<copyright>' + XmlEscape(ANotice) + '</copyright>';
end;

function CellMatches(const ACell, AExpected: string): Boolean;
begin
  if AExpected = '' then
    Result := Trim(ACell) = ''
  else
    Result := (ACell = AExpected) or (ACell = HtmlEscape(AExpected)) or
      (ACell = StringReplace(AExpected, '|', '\|', [rfReplaceAll]));
end;

function NextTd(const AHtml: string; var APos: Integer): string;
var
  LOpen: Integer;
  LCloseTag: Integer;
  LClose: Integer;
begin
  Result := '';
  LOpen := TextPos(AHtml, '<td', APos);
  if LOpen = 0 then
    Exit;
  LCloseTag := TextPos(AHtml, '>', LOpen);
  if LCloseTag = 0 then
    Exit;
  LClose := TextPos(AHtml, '</td>', LCloseTag);
  if LClose = 0 then
    Exit;
  Result := Copy(AHtml, LCloseTag + 1, LClose - LCloseTag - 1);
  APos := LClose + Length('</td>');
end;

procedure AssertHtmlCopyright(const AHtml, AName, AExpected: string; AMinCount: Integer);
var
  LSection: string;
  LNeedle: string;
  LPos: Integer;
  LFound: Integer;
  LCellPos: Integer;
  LCopyright: string;
begin
  LSection := Between(AHtml, '<h2>Licences</h2>', '</section>');
  LNeedle := '<td>' + HtmlEscape(AName) + '</td>';
  LFound := 0;
  LPos := Pos(LNeedle, LSection);
  while LPos > 0 do
  begin
    Inc(LFound);
    LCellPos := LPos + Length(LNeedle);
    NextTd(LSection, LCellPos);
    LCopyright := NextTd(LSection, LCellPos);
    Assert.IsTrue(CellMatches(LCopyright, AExpected),
      AName + ' HTML copyright is [' + LCopyright + ']');
    LPos := TextPos(LSection, LNeedle, LPos + Length(LNeedle));
  end;
  Assert.IsTrue(LFound >= AMinCount, AName + ' is missing from the HTML licence table. ' +
    Copy(LSection, 1, 500));
end;

procedure AssertMarkdownCopyright(const AMarkdown, AName, AExpected: string;
  AMinCount: Integer);
var
  LSection: string;
  LLines: TStringList;
  I: Integer;
  LCells: TStringList;
  LFound: Integer;
  LName: string;
  LCopyright: string;
begin
  LSection := Between(AMarkdown, '## Licences', sLineBreak + '## ');
  LLines := TStringList.Create;
  LCells := TStringList.Create;
  try
    LLines.Text := LSection;
    LCells.StrictDelimiter := True;
    LCells.Delimiter := '|';
    LFound := 0;
    for I := 0 to LLines.Count - 1 do
    begin
      LCells.DelimitedText := StringReplace(LLines[I], '\|', #1, [rfReplaceAll]);
      if LCells.Count < 6 then
        Continue;
      LName := Trim(StringReplace(LCells[3], #1, '|', [rfReplaceAll]));
      if not SameText(LName, AName) then
        Continue;
      Inc(LFound);
      LCopyright := Trim(StringReplace(LCells[5], #1, '|', [rfReplaceAll]));
      Assert.IsTrue(CellMatches(LCopyright, AExpected),
        AName + ' Markdown copyright is [' + LCopyright + ']');
    end;
    Assert.IsTrue(LFound >= AMinCount, AName + ' is missing from the Markdown licence table. ' +
      Copy(LSection, 1, 500));
  finally
    LCells.Free;
    LLines.Free;
  end;
end;

function PrepareBuild(const ARoot, AExeSource: string; ASecondCopy: Boolean): TBuildFixture;
var
  LOut: string;
  LExtra: string;
begin
  Result := Default(TBuildFixture);
  TDirectory.CreateDirectory(ARoot);
  LOut := TPath.Combine(ARoot, 'out');
  TDirectory.CreateDirectory(LOut);
  TFile.WriteAllText(TPath.Combine(ARoot, 'MyApp.dpr'), cBuildDpr, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(ARoot, 'MyApp.dproj'), cBuildDproj, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(ARoot, 'MainForm.pas'), UnitSource('MainForm'), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(ARoot, 'OtherUnit.pas'), UnitSource('OtherUnit'), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(ARoot, 'components.json'), cBuildManifest, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(LOut, 'MyApp.map'), cBuildMap, TEncoding.UTF8);
  Result.ExePath := TPath.Combine(LOut, 'MyApp.exe');
  CopyFileChecked(AExeSource, Result.ExePath);
  CopyFileChecked(VersionFixture('FakeNoVersion.exe'), TPath.Combine(LOut, 'plugin.dll'));
  if ASecondCopy then
  begin
    LExtra := TPath.Combine(ARoot, 'extra');
    TDirectory.CreateDirectory(LExtra);
    CopyFileChecked(AExeSource, TPath.Combine(LExtra, 'MyApp.exe'));
  end;
  Result.Project := TPath.Combine(ARoot, 'MyApp.dproj');
  Result.Manifest := TPath.Combine(ARoot, 'components.json');
  Result.ReportBase := TPath.Combine(ARoot, 'report');
end;

function BuildConfig(const AFixture: TBuildFixture; const ACopyright: string;
  AReports, ASecondCopy: Boolean): TSbomConfig;
begin
  Result := TSbomConfig.Default;
  Result.Platform := 'Win32';
  Result.Configuration := 'Release';
  Result.IncludeCompositionEvidence := True;
  Result.ManifestFile := AFixture.Manifest;
  Result.Copyright := ACopyright;
  Result.HumanReadableReport.Enabled := AReports;
  Result.HumanReadableReport.Format := hrfBoth;
  Result.HumanReadableReport.OutputBasePath := AFixture.ReportBase;
  if ASecondCopy then
    Result.ScanDirs := TArray<string>.Create(TPath.Combine(
      TPath.GetDirectoryName(AFixture.Project), 'extra'));
end;

procedure TProductCopyrightTests.Setup;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FTempDir := TPath.Combine(TPath.GetTempPath, 'dxcomply-copyright-' +
    GUIDToString(LGuid).Trim(['{', '}']));
  TDirectory.CreateDirectory(FTempDir);
  FProgress := TStringList.Create;
end;

procedure TProductCopyrightTests.TearDown;
begin
  if (FTempDir <> '') and TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
  FProgress.Free;
  FProgress := nil;
end;

procedure TProductCopyrightTests.OnProgress(const AMessage: string; const AProgress: Integer);
begin
  FProgress.Add(AMessage + ' [' + IntToStr(AProgress) + ']');
end;

function TProductCopyrightTests.GenerateProject(const AProject: string;
  const AConfig: TSbomConfig; const AOutput: string; AFormat: TSbomFormat): Boolean;
var
  LGen: TDxComplyGenerator;
begin
  FProgress.Clear;
  LGen := TDxComplyGenerator.Create(AConfig);
  try
    LGen.OnProgress := OnProgress;
    Result := LGen.Generate(AProject, AOutput, AFormat);
  finally
    LGen.Free;
  end;
end;

procedure TProductCopyrightTests.Automatic_LegalCopyright_OnProductOwnBinaryAndOwnCode;
var
  LFixture: TBuildFixture;
  LNotice: string;
  LConfig: TSbomConfig;
  LJsonPath: string;
  LXmlPath: string;
  LSpdxPath: string;
  LSpdx3Path: string;
  LRoot: TJSONObject;
  LComponents: TJSONArray;
  LXml: string;
  LPlugin: string;
  LHtml: string;
  LMarkdown: string;
begin
  LFixture := PrepareBuild(TPath.Combine(FTempDir, 'auto'), ParamStr(0), True);
  LNotice := GetFileLegalCopyright(LFixture.ExePath);
  Assert.AreNotEqual('', LNotice,
    'the test executable must carry LegalCopyright in its version resource');
  Assert.AreNotEqual(cRowCopyright, LNotice,
    'the product notice must stay distinct from the manifest row');

  LJsonPath := TPath.Combine(FTempDir, 'auto.json');
  LConfig := BuildConfig(LFixture, '', True, True);
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LJsonPath, sfCycloneDxJson),
    FProgress.Text);
  Assert.IsTrue(Pos('Structural check error', FProgress.Text) = 0, FProgress.Text);

  LRoot := ParseRoot(LJsonPath);
  try
    Assert.AreEqual(LNotice, RequiredJsonText(MetadataComponent(LRoot), 'copyright'),
      'metadata.component.copyright');
    LComponents := JsonArray(LRoot, 'components');
    AssertJsonCopyright(LComponents, 'MyApp.exe', LNotice, 2, 2);
    AssertJsonCopyright(LComponents, 'MainForm.pas', LNotice, 1, 1);
    AssertJsonCopyright(LComponents, 'OtherUnit.pas', '', 1, 1);
    AssertJsonCopyright(LComponents, 'plugin.dll', '', 1, 1);
    AssertJsonCopyright(LComponents, 'VendorLib', cRowCopyright, 1, 1);
  finally
    LRoot.Free;
  end;

  LHtml := TFile.ReadAllText(LFixture.ReportBase + '.html', TEncoding.UTF8);
  LMarkdown := TFile.ReadAllText(LFixture.ReportBase + '.md', TEncoding.UTF8);
  AssertHtmlCopyright(LHtml, 'MyApp (product)', LNotice, 1);
  AssertHtmlCopyright(LHtml, 'MyApp.exe', LNotice, 1);
  AssertHtmlCopyright(LHtml, 'MainForm', LNotice, 1);
  AssertHtmlCopyright(LHtml, 'plugin.dll', '', 1);
  AssertHtmlCopyright(LHtml, 'VendorLib', cRowCopyright, 1);
  AssertMarkdownCopyright(LMarkdown, 'MyApp (product)', LNotice, 1);
  AssertMarkdownCopyright(LMarkdown, 'MyApp.exe', LNotice, 1);
  AssertMarkdownCopyright(LMarkdown, 'MainForm', LNotice, 1);
  AssertMarkdownCopyright(LMarkdown, 'plugin.dll', '', 1);
  AssertMarkdownCopyright(LMarkdown, 'VendorLib', cRowCopyright, 1);

  LXmlPath := TPath.Combine(FTempDir, 'auto.xml');
  LConfig := BuildConfig(LFixture, '', False, True);
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LXmlPath, sfCycloneDxXml),
    FProgress.Text);
  Assert.IsTrue(Pos('Structural check error', FProgress.Text) = 0, FProgress.Text);
  LXml := TFile.ReadAllText(LXmlPath, TEncoding.UTF8);
  Assert.IsTrue(CountText(LXml, CopyrightElement(LNotice)) >= 4, LXml);
  Assert.AreEqual(1, CountText(LXml, CopyrightElement(cRowCopyright)), LXml);
  LPlugin := XmlComponent(LXml, 'plugin.dll');
  Assert.AreNotEqual('', LPlugin, 'plugin.dll must be a component');
  Assert.IsTrue(Pos('<copyright', LPlugin) = 0, LPlugin);

  LSpdxPath := TPath.Combine(FTempDir, 'auto.spdx.json');
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LSpdxPath, sfSpdxJson),
    FProgress.Text);
  LRoot := ParseRoot(LSpdxPath);
  try
    LComponents := JsonArray(LRoot, 'packages');
    AssertSpdxCopyright(LComponents, 'MyApp.exe', LNotice, 2, 2);
    AssertSpdxCopyright(LComponents, 'MainForm.pas', LNotice, 1, 1);
    AssertSpdxCopyright(LComponents, 'OtherUnit.pas', 'NOASSERTION', 1, 1);
    AssertSpdxCopyright(LComponents, 'plugin.dll', 'NOASSERTION', 1, 1);
    AssertSpdxCopyright(LComponents, 'VendorLib', cRowCopyright, 1, 1);
  finally
    LRoot.Free;
  end;

  LSpdx3Path := TPath.Combine(FTempDir, 'auto.spdx3.json');
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LSpdx3Path, sfSpdx3Json),
    FProgress.Text);
  LRoot := ParseRoot(LSpdx3Path);
  try
    LComponents := JsonArray(LRoot, '@graph');
    AssertSpdx3Copyright(LComponents, 'MyApp.exe', LNotice, 2, 2);
    AssertSpdx3Copyright(LComponents, 'MainForm.pas', LNotice, 1, 1);
    AssertSpdx3Copyright(LComponents, 'OtherUnit.pas', '', 1, 1);
    AssertSpdx3Copyright(LComponents, 'plugin.dll', '', 1, 1);
    AssertSpdx3Copyright(LComponents, 'VendorLib', cRowCopyright, 1, 1);
  finally
    LRoot.Free;
  end;
end;

procedure TProductCopyrightTests.Override_ConfigKey_WinsOverLegalCopyright;
var
  LFixture: TBuildFixture;
  LNotice: string;
  LConfig: TSbomConfig;
  LJsonPath: string;
  LSpdxPath: string;
  LRoot: TJSONObject;
  LComponents: TJSONArray;
begin
  LFixture := PrepareBuild(TPath.Combine(FTempDir, 'override'), ParamStr(0), False);
  LNotice := GetFileLegalCopyright(LFixture.ExePath);
  Assert.AreNotEqual('', LNotice,
    'the test executable must carry LegalCopyright so the override is visible');
  Assert.AreNotEqual(LNotice, cOverrideNotice);

  LJsonPath := TPath.Combine(FTempDir, 'override.json');
  LConfig := BuildConfig(LFixture, cOverrideNotice, False, False);
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LJsonPath, sfCycloneDxJson),
    FProgress.Text);
  LRoot := ParseRoot(LJsonPath);
  try
    Assert.AreEqual(cOverrideNotice, RequiredJsonText(MetadataComponent(LRoot), 'copyright'));
    LComponents := JsonArray(LRoot, 'components');
    AssertJsonCopyright(LComponents, 'MyApp.exe', cOverrideNotice, 1, 1);
    AssertJsonCopyright(LComponents, 'MainForm.pas', cOverrideNotice, 1, 1);
    AssertJsonCopyright(LComponents, 'OtherUnit.pas', '', 1, 1);
    AssertJsonCopyright(LComponents, 'VendorLib', cRowCopyright, 1, 1);
  finally
    LRoot.Free;
  end;

  LSpdxPath := TPath.Combine(FTempDir, 'override.spdx.json');
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LSpdxPath, sfSpdxJson),
    FProgress.Text);
  LRoot := ParseRoot(LSpdxPath);
  try
    LComponents := JsonArray(LRoot, 'packages');
    AssertSpdxCopyright(LComponents, 'MyApp.exe', cOverrideNotice, 1, 1);
    AssertSpdxCopyright(LComponents, 'MainForm.pas', cOverrideNotice, 1, 1);
    AssertSpdxCopyright(LComponents, 'OtherUnit.pas', 'NOASSERTION', 1, 1);
    AssertSpdxCopyright(LComponents, 'VendorLib', cRowCopyright, 1, 1);
  finally
    LRoot.Free;
  end;
end;

procedure TProductCopyrightTests.Override_LibraryMode_ConfigKeyWins;
const
  cLibDpr =
    'program LibApp;' + sLineBreak +
    'uses' + sLineBreak +
    '  UnitMine in ''UnitMine.pas'',' + sLineBreak +
    '  Other in ''Other.pas'';' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak;
  cLibDproj =
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>src\LibApp.dpr</MainSource>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\out</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak;
  cLibManifest =
    '{' + sLineBreak +
    '  "schema_version": "1.0",' + sLineBreak +
    '  "components": [],' + sLineBreak +
    '  "own_code_units": ["UnitMine"]' + sLineBreak +
    '}' + sLineBreak;
var
  LRootDir: string;
  LSrc: string;
  LExe: string;
  LProject: string;
  LManifest: string;
  LConfigPath: string;
  LOutput: string;
  LNotice: string;
  LDirs: TJSONArray;
  LConfig: TJSONObject;
  LGen: TDxComplyGenerator;
  LDoc: TJSONObject;
  LComponents: TJSONArray;
begin
  LRootDir := TPath.Combine(FTempDir, 'library');
  LSrc := TPath.Combine(LRootDir, 'src');
  TDirectory.CreateDirectory(LSrc);
  TDirectory.CreateDirectory(TPath.Combine(LRootDir, 'out'));
  TFile.WriteAllText(TPath.Combine(LSrc, 'LibApp.dpr'), cLibDpr, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(LSrc, 'UnitMine.pas'), UnitSource('UnitMine'), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(LSrc, 'Other.pas'), UnitSource('Other'), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(LRootDir, 'LibApp.dproj'), cLibDproj, TEncoding.UTF8);
  LManifest := TPath.Combine(LRootDir, 'components.json');
  TFile.WriteAllText(LManifest, cLibManifest, TEncoding.UTF8);
  LExe := TPath.Combine(LRootDir, 'out' + PathDelim + 'LibApp.exe');
  CopyFileChecked(ParamStr(0), LExe);
  LNotice := GetFileLegalCopyright(LExe);
  Assert.AreNotEqual('', LNotice,
    'the test executable must carry LegalCopyright so the library override is visible');
  Assert.AreNotEqual(LNotice, cOverrideNotice);

  LProject := TPath.Combine(LRootDir, 'LibApp.dproj');
  LOutput := TPath.Combine(FTempDir, 'library-bom.json');
  LConfigPath := TPath.Combine(LRootDir, '.dxcomply.json');
  LConfig := TJSONObject.Create;
  try
    LDirs := TJSONArray.Create;
    LDirs.Add('src');
    LConfig.AddPair('library', TJSONBool.Create(True));
    LConfig.AddPair('copyright', cOverrideNotice);
    LConfig.AddPair('sourceDirs', LDirs);
    LConfig.AddPair('manifest', LManifest);
    LConfig.AddPair('output', LOutput);
    LConfig.AddPair('platform', 'Win32');
    LConfig.AddPair('configName', 'Release');
    TFile.WriteAllText(LConfigPath, LConfig.ToJSON, TEncoding.UTF8);
  finally
    LConfig.Free;
  end;

  FProgress.Clear;
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    Assert.IsTrue(LGen.GenerateFromConfig(LProject, LConfigPath), FProgress.Text);
  finally
    LGen.Free;
  end;

  LDoc := ParseRoot(LOutput);
  try
    Assert.AreEqual(cOverrideNotice, RequiredJsonText(MetadataComponent(LDoc), 'copyright'),
      'library mode must use the copyright key');
    LComponents := JsonArray(LDoc, 'components');
    AssertJsonCopyright(LComponents, 'UnitMine.pas', cOverrideNotice, 1, -1);
    AssertJsonCopyright(LComponents, 'Other.pas', '', 1, -1);
    AssertJsonCopyright(LComponents, 'LibApp.dpr', '', 1, -1);
  finally
    LDoc.Free;
  end;
end;

procedure TProductCopyrightTests.BlankCopyright_FallsThroughToLegalCopyright;
var
  LFixture: TBuildFixture;
  LNotice: string;
  LConfig: TSbomConfig;
  LJsonPath: string;
  LRoot: TJSONObject;
  LComponents: TJSONArray;
begin
  LFixture := PrepareBuild(TPath.Combine(FTempDir, 'blank'), ParamStr(0), False);
  LNotice := GetFileLegalCopyright(LFixture.ExePath);
  Assert.AreNotEqual('', LNotice);

  LJsonPath := TPath.Combine(FTempDir, 'blank.json');
  LConfig := BuildConfig(LFixture, '   ', False, False);
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LJsonPath, sfCycloneDxJson),
    FProgress.Text);
  LRoot := ParseRoot(LJsonPath);
  try
    Assert.AreEqual(LNotice, RequiredJsonText(MetadataComponent(LRoot), 'copyright'),
      'spaces must not hide LegalCopyright');
    LComponents := JsonArray(LRoot, 'components');
    AssertJsonCopyright(LComponents, 'MyApp.exe', LNotice, 1, 1);
    AssertJsonCopyright(LComponents, 'MainForm.pas', LNotice, 1, 1);
  finally
    LRoot.Free;
  end;
end;

procedure TProductCopyrightTests.Empty_OmitsCopyrightAndKeepsNoAssertion;
var
  LFixture: TBuildFixture;
  LConfig: TSbomConfig;
  LJsonPath: string;
  LXmlPath: string;
  LSpdxPath: string;
  LSpdx3Path: string;
  LRoot: TJSONObject;
  LComponents: TJSONArray;
  LXml: string;
  LHtml: string;
  LMarkdown: string;
begin
  LFixture := PrepareBuild(TPath.Combine(FTempDir, 'empty'),
    VersionFixture('FakeWithVersion.exe'), False);
  Assert.AreEqual('9.8.7.6', GetFileVersionText(LFixture.ExePath),
    'FakeWithVersion.exe FileVersion is 9.8.7.6');
  Assert.AreEqual('', GetFileLegalCopyright(LFixture.ExePath),
    'FakeWithVersion.exe has no LegalCopyright');

  LJsonPath := TPath.Combine(FTempDir, 'empty.json');
  LConfig := BuildConfig(LFixture, '', True, False);
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LJsonPath, sfCycloneDxJson),
    FProgress.Text);
  LRoot := ParseRoot(LJsonPath);
  try
    Assert.IsNull(JsonField(MetadataComponent(LRoot), 'copyright'),
      'an empty notice must omit metadata.component.copyright');
    LComponents := JsonArray(LRoot, 'components');
    AssertJsonCopyright(LComponents, 'MyApp.exe', '', 1, 1);
    AssertJsonCopyright(LComponents, 'MainForm.pas', '', 1, 1);
    AssertJsonCopyright(LComponents, 'OtherUnit.pas', '', 1, 1);
    AssertJsonCopyright(LComponents, 'plugin.dll', '', 1, 1);
    AssertJsonCopyright(LComponents, 'VendorLib', cRowCopyright, 1, 1);
  finally
    LRoot.Free;
  end;

  LHtml := TFile.ReadAllText(LFixture.ReportBase + '.html', TEncoding.UTF8);
  LMarkdown := TFile.ReadAllText(LFixture.ReportBase + '.md', TEncoding.UTF8);
  AssertHtmlCopyright(LHtml, 'MyApp (product)', '', 1);
  Assert.IsTrue(Pos('<td>MyApp (product)</td><td>9.8.7.6</td>', LHtml) > 0,
    'the product row carries the binary version');
  Assert.AreEqual<Integer>(0, Pos('<td>MyApp.exe</td>',
    Between(LHtml, '<h2>Licences</h2>', '</section>')),
    'the only project binary is the product row');
  AssertHtmlCopyright(LHtml, 'MainForm', '', 1);
  AssertHtmlCopyright(LHtml, 'VendorLib', cRowCopyright, 1);
  AssertMarkdownCopyright(LMarkdown, 'MyApp (product)', '', 1);
  Assert.IsTrue(Pos('| MyApp (product) | 9.8.7.6 |', LMarkdown) > 0,
    'the product row carries the binary version');
  Assert.AreEqual<Integer>(0, Pos('| MyApp.exe |',
    Between(LMarkdown, '## Licences', sLineBreak + '## ')),
    'the only project binary is the product row');
  AssertMarkdownCopyright(LMarkdown, 'MainForm', '', 1);
  AssertMarkdownCopyright(LMarkdown, 'VendorLib', cRowCopyright, 1);

  LXmlPath := TPath.Combine(FTempDir, 'empty.xml');
  LConfig := BuildConfig(LFixture, '', False, False);
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LXmlPath, sfCycloneDxXml),
    FProgress.Text);
  Assert.IsTrue(Pos('Structural check error', FProgress.Text) = 0, FProgress.Text);
  LXml := TFile.ReadAllText(LXmlPath, TEncoding.UTF8);
  Assert.AreEqual(1, CountText(LXml, '<copyright>'),
    'only the manifest row may carry a copyright element. ' + LXml);
  Assert.AreEqual(1, CountText(LXml, CopyrightElement(cRowCopyright)), LXml);

  LSpdxPath := TPath.Combine(FTempDir, 'empty.spdx.json');
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LSpdxPath, sfSpdxJson),
    FProgress.Text);
  LRoot := ParseRoot(LSpdxPath);
  try
    LComponents := JsonArray(LRoot, 'packages');
    AssertSpdxCopyright(LComponents, 'MyApp.exe', 'NOASSERTION', 1, 1);
    AssertSpdxCopyright(LComponents, 'MainForm.pas', 'NOASSERTION', 1, 1);
    AssertSpdxCopyright(LComponents, 'VendorLib', cRowCopyright, 1, 1);
  finally
    LRoot.Free;
  end;

  LSpdx3Path := TPath.Combine(FTempDir, 'empty.spdx3.json');
  Assert.IsTrue(GenerateProject(LFixture.Project, LConfig, LSpdx3Path, sfSpdx3Json),
    FProgress.Text);
  LRoot := ParseRoot(LSpdx3Path);
  try
    LComponents := JsonArray(LRoot, '@graph');
    AssertSpdx3Copyright(LComponents, 'MyApp.exe', '', 1, 1);
    AssertSpdx3Copyright(LComponents, 'MainForm.pas', '', 1, 1);
    AssertSpdx3Copyright(LComponents, 'VendorLib', cRowCopyright, 1, 1);
  finally
    LRoot.Free;
  end;
end;

procedure TProductCopyrightTests.LoadConfig_TrimsString_AndIgnoresBadValues;
var
  LPath: string;
  LGen: TDxComplyGenerator;
  LLoaded: TSbomConfig;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;

    LPath := TPath.Combine(FTempDir, 'trim.json');
    TFile.WriteAllText(LPath, '{"copyright":"  Notice  "}', TEncoding.UTF8);
    LLoaded := LGen.LoadConfig(LPath);
    Assert.AreEqual('Notice', LLoaded.Copyright, 'a copyright string is trimmed');

    LPath := TPath.Combine(FTempDir, 'blank.json');
    TFile.WriteAllText(LPath, '{"copyright":"   "}', TEncoding.UTF8);
    LLoaded := LGen.LoadConfig(LPath);
    Assert.AreEqual('', LLoaded.Copyright, 'spaces alone stay empty');

    LPath := TPath.Combine(FTempDir, 'number.json');
    TFile.WriteAllText(LPath, '{"copyright":1999}', TEncoding.UTF8);
    LLoaded := LGen.LoadConfig(LPath);
    Assert.IsTrue((LLoaded.Copyright = '1999') or (LLoaded.Copyright = '1999.0'),
      'a numeric copyright is kept as text, got [' + LLoaded.Copyright + ']');

    FProgress.Clear;
    LPath := TPath.Combine(FTempDir, 'object.json');
    TFile.WriteAllText(LPath, '{"copyright":{"text":"hidden"}}', TEncoding.UTF8);
    LLoaded := LGen.LoadConfig(LPath);
    Assert.AreEqual('', LLoaded.Copyright, 'an object is ignored');
    Assert.IsTrue(Pos('must be a string', FProgress.Text) > 0, FProgress.Text);

    LPath := TPath.Combine(FTempDir, 'null.json');
    TFile.WriteAllText(LPath, '{"copyright":null}', TEncoding.UTF8);
    LLoaded := LGen.LoadConfig(LPath);
    Assert.AreEqual('', LLoaded.Copyright, 'null leaves the notice empty');
  finally
    LGen.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TProductCopyrightTests);

end.
