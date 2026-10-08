/// <summary>
/// DX.Comply.Tests.ComponentManifest
/// DUnitX tests for the components.json manifest.
/// </summary>
///
/// <remarks>
/// Covers matching (exact beats prefix, first row wins, scope stripping,
/// case), licence classification, PURL generation, writer output, and the
/// CLI / config precedence for --manifest.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.ComponentManifest;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.ComponentManifest,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.CycloneDx.XmlWriter,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.Schema.Validator,
  DX.Comply.Spdx.Writer,
  DX.Comply.CLI.Options;

type
  /// <summary>
  /// DUnitX tests for component manifest matching and SBOM enrichment.
  /// </summary>
  [TestFixture]
  TComponentManifestTests = class
  private
    FOutputFile: string;
    FArtefacts: TArtefactList;
    FMetadata: TSbomMetadata;
    FProjectInfo: TProjectInfo;
    function ParseManifest(const AJson: string): TComponentManifest;
    function SampleManifestJson: string;
    function FindComponent(AComponents: TJSONArray; const AName: string): TJSONObject;
    function FindDependency(ADependencies: TJSONArray; const ARef: string): TJSONObject;
    function DependsOnContains(ADependency: TJSONObject; const ARef: string): Boolean;
    procedure AddUnit(const AFileName: string);
    procedure AddFile(const AFileName, AKind: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Match_ExactBeatsEarlierPrefix;
    [Test]
    procedure Match_FirstExactRowWins;
    [Test]
    procedure Match_FirstPrefixRowWins;
    [Test]
    procedure Match_StripsKnownScopePrefix;
    [Test]
    procedure Match_DoesNotStripUnknownScope;
    [Test]
    procedure Match_IsCaseInsensitive;
    [Test]
    procedure Match_OwnCodeUnitBeatsPrefix;
    [Test]
    procedure Match_ExactBeatsOwnCodeUnit;
    [Test]
    procedure Match_OwnCodePrefixAfterLibraryPrefix;

    [Test]
    procedure Licence_SpdxId_IsCanonical;
    [Test]
    procedure Licence_OrLaterForm_StaysAnId;
    [Test]
    procedure Licence_Expression_IsExpression;
    [Test]
    procedure Licence_Commercial_IsName;

    [Test]
    procedure Purl_EncodesSpaceAsPercent20;
    [Test]
    procedure Purl_IncludesVersion;
    [Test]
    procedure Purl_OmitsEmptyVersion;
    [Test]
    procedure Purl_OverrideWins;

    [Test]
    procedure Parse_InvalidJson_SetsError;
    [Test]
    procedure Parse_RootMustBeObjectOrArray;
    [Test]
    procedure Parse_BareArray_IsComponents;
    [Test]
    procedure Parse_LicenseAlias_IsAccepted;
    [Test]
    procedure Parse_ShortPrefix_Warns;
    [Test]
    procedure Load_MissingFile_NamesTheReason;
    [Test]
    procedure Publisher_FillsEmptySupplierOnly;

    [Test]
    procedure Resolve_RelativePath_UsesProjectDir;
    [Test]
    procedure Cli_ManifestFlag_WinsInToSbomConfig;
    [Test]
    procedure Cli_EmptyManifest_IsAnError;
    [Test]
    procedure Config_ExplicitFlag_WinsOverFile;
    [Test]
    procedure Config_File_UsedWhenFlagAbsent;
    [Test]
    procedure Generate_InvalidManifest_ReportsPathAndReason;

    [Test]
    procedure JsonWriter_GroupsLibrariesAndLinksUnits;
    [Test]
    procedure XmlWriter_LibraryElementOrder;
    [Test]
    procedure SpdxWriter_LicenceSupplierAndPurl;
  end;

implementation

uses
  DX.Comply.Tests.Paths;

function TComponentManifestTests.ParseManifest(const AJson: string): TComponentManifest;
var
  LError: string;
begin
  Assert.IsTrue(TryParseComponentManifest(AJson, 'test', Result, LError),
    'The test manifest must parse. ' + LError);
end;

function TComponentManifestTests.SampleManifestJson: string;
begin
  Result :=
    '{' +
    '"schema_version":"1.0",' +
    '"last_updated":"2026-03-26",' +
    '"supplier":{"name":"Acme GmbH","url":"https://acme.example"},' +
    '"components":[' +
    '{"name":"OmniThreadLibrary","version":"3.7.8","vendor":"Primo Gabrijelcic",' +
    '"vendor_url":"https://github.com/gabr42/OmniThreadLibrary",' +
    '"licence":"MIT","licence_url":"https://opensource.org/licenses/MIT",' +
    '"type":"library","units_prefix":["Otl"],"units_exact":["GpLists"]},' +
    '{"name":"SynEdit","version":"3.0","vendor":"SynEdit Contributors",' +
    '"licence":"MPL-1.1 OR LGPL-2.1-or-later","type":"library",' +
    '"units_exact":["SynEdit"]},' +
    '{"name":"TMS VCL UI Pack","version":"13.0","vendor":"tmssoftware.com",' +
    '"vendor_url":"https://www.tmssoftware.com","licence":"Commercial",' +
    '"type":"library","units_prefix":["AdvGrid"],' +
    '"purl":"pkg:generic/tms-vcl@13"}' +
    '],' +
    '"own_code_units":["MainForm"],' +
    '"own_code_prefixes":["app"]' +
    '}';
end;

function TComponentManifestTests.FindComponent(AComponents: TJSONArray;
  const AName: string): TJSONObject;
var
  I: Integer;
  LValue: TJSONValue;
begin
  Result := nil;
  if not Assigned(AComponents) then
    Exit;
  for I := 0 to AComponents.Count - 1 do
  begin
    if not (AComponents.Items[I] is TJSONObject) then
      Continue;
    LValue := TJSONObject(AComponents.Items[I]).GetValue('name');
    if (LValue <> nil) and SameText(LValue.Value, AName) then
      Exit(TJSONObject(AComponents.Items[I]));
  end;
end;

function TComponentManifestTests.FindDependency(ADependencies: TJSONArray;
  const ARef: string): TJSONObject;
var
  I: Integer;
  LValue: TJSONValue;
begin
  Result := nil;
  if not Assigned(ADependencies) then
    Exit;
  for I := 0 to ADependencies.Count - 1 do
  begin
    if not (ADependencies.Items[I] is TJSONObject) then
      Continue;
    LValue := TJSONObject(ADependencies.Items[I]).GetValue('ref');
    if (LValue <> nil) and SameText(LValue.Value, ARef) then
      Exit(TJSONObject(ADependencies.Items[I]));
  end;
end;

function TComponentManifestTests.DependsOnContains(ADependency: TJSONObject;
  const ARef: string): Boolean;
var
  LDepends: TJSONArray;
  I: Integer;
begin
  Result := False;
  if not Assigned(ADependency) then
    Exit;
  if not (ADependency.GetValue('dependsOn') is TJSONArray) then
    Exit;
  LDepends := TJSONArray(ADependency.GetValue('dependsOn'));
  for I := 0 to LDepends.Count - 1 do
    if SameText(LDepends.Items[I].Value, ARef) then
      Exit(True);
end;

procedure TComponentManifestTests.AddUnit(const AFileName: string);
var
  LArtefact: TArtefactInfo;
begin
  LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := AFileName;
  LArtefact.ArtefactType := 'unit-evidence';
  LArtefact.Hash := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  LArtefact.FileSize := 10;
  LArtefact.Origin := 'Third party';
  LArtefact.Evidence := 'PAS';
  LArtefact.Confidence := 'Strong';
  FArtefacts.Add(LArtefact);
end;

procedure TComponentManifestTests.AddFile(const AFileName, AKind: string);
var
  LArtefact: TArtefactInfo;
begin
  LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := AFileName;
  LArtefact.ArtefactType := AKind;
  LArtefact.FileSize := 20;
  FArtefacts.Add(LArtefact);
end;

procedure TComponentManifestTests.Setup;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FOutputFile := TPath.Combine(TPath.GetTempPath,
    'dxm-' + Copy(GUIDToString(LGuid), 2, 8) + '.out');
  FArtefacts := TArtefactList.Create;
  FMetadata := Default(TSbomMetadata);
  FMetadata.ProductName := 'TestApp';
  FMetadata.ProductVersion := '1.0.0';
  FMetadata.Timestamp := '2026-01-01T00:00:00Z';
  FMetadata.ToolName := 'DX.Comply';
  FMetadata.ToolVersion := '1.3.0.0';
  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'TestApp';
  FProjectInfo.Version := '1.0.0';
  FProjectInfo.ProjectDir := TPath.GetTempPath;
end;

procedure TComponentManifestTests.TearDown;
begin
  if TFile.Exists(FOutputFile) then
    TFile.Delete(FOutputFile);
  FArtefacts.Free;
  FProjectInfo.Free;
end;

procedure TComponentManifestTests.Match_ExactBeatsEarlierPrefix;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"ByPrefix","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Otl"]},' +
    '{"name":"ByExact","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_exact":["OtlTask"]}' +
    ']}');
  LMatch := MatchManifestUnit(LManifest, 'OtlTask');
  Assert.AreEqual(Ord(mmLibrary), Ord(LMatch.Kind));
  Assert.AreEqual(1, LMatch.ComponentIndex, 'An exact row must beat an earlier prefix');
  LMatch := MatchManifestUnit(LManifest, 'OtlCommon');
  Assert.AreEqual(0, LMatch.ComponentIndex, 'A prefix-only name stays on the prefix row');
end;

procedure TComponentManifestTests.Match_FirstExactRowWins;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"First","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_exact":["GpLists"]},' +
    '{"name":"Second","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_exact":["GpLists"]}' +
    ']}');
  LMatch := MatchManifestUnit(LManifest, 'GpLists');
  Assert.AreEqual(0, LMatch.ComponentIndex, 'The first exact row must win');
end;

procedure TComponentManifestTests.Match_FirstPrefixRowWins;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"First","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Spring"]},' +
    '{"name":"Second","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Spring"]}' +
    ']}');
  LMatch := MatchManifestUnit(LManifest, 'Spring.Collections');
  Assert.AreEqual(0, LMatch.ComponentIndex, 'The first prefix row must win');
end;

procedure TComponentManifestTests.Match_StripsKnownScopePrefix;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"Spring4D","version":"2","vendor":"A","licence":"Apache-2.0","type":"framework",' +
    '"units_prefix":["Spring"]}' +
    ']}');
  LMatch := MatchManifestUnit(LManifest, 'System.Spring.Collections');
  Assert.AreEqual(Ord(mmLibrary), Ord(LMatch.Kind));
  Assert.AreEqual(0, LMatch.ComponentIndex,
    'System. must be stripped before the prefix is tested');
  Assert.AreEqual('Spring.Collections', StripDelphiScopePrefix('System.Spring.Collections'));
end;

procedure TComponentManifestTests.Match_DoesNotStripUnknownScope;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"BarLib","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Bar"]}' +
    ']}');
  LMatch := MatchManifestUnit(LManifest, 'Foo.Bar');
  Assert.AreEqual(Ord(mmNone), Ord(LMatch.Kind),
    'An unknown scope prefix must be left in place');
  LMatch := MatchManifestUnit(LManifest, 'System.Bar');
  Assert.AreEqual(Ord(mmLibrary), Ord(LMatch.Kind));
end;

procedure TComponentManifestTests.Match_IsCaseInsensitive;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"OTL","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Otl"],"units_exact":["GpLists"]}' +
    ']}');
  LMatch := MatchManifestUnit(LManifest, 'otltask');
  Assert.AreEqual(0, LMatch.ComponentIndex);
  LMatch := MatchManifestUnit(LManifest, 'GPLISTS');
  Assert.AreEqual(0, LMatch.ComponentIndex);
  LMatch := MatchManifestUnit(LManifest, 'vcl.otlcommon');
  Assert.AreEqual(0, LMatch.ComponentIndex, 'Scope stripping is case-insensitive');
end;

procedure TComponentManifestTests.Match_OwnCodeUnitBeatsPrefix;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"AppLib","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["App"]}' +
    '],"own_code_units":["AppSettings"]}');
  LMatch := MatchManifestUnit(LManifest, 'AppSettings');
  Assert.AreEqual(Ord(mmOwnCode), Ord(LMatch.Kind),
    'own_code_units must beat a prefix rule');
  Assert.AreEqual(-1, LMatch.ComponentIndex);
end;

procedure TComponentManifestTests.Match_ExactBeatsOwnCodeUnit;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"Vendored","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_exact":["MainForm"]}' +
    '],"own_code_units":["MainForm"]}');
  LMatch := MatchManifestUnit(LManifest, 'MainForm');
  Assert.AreEqual(Ord(mmLibrary), Ord(LMatch.Kind));
  Assert.AreEqual(0, LMatch.ComponentIndex,
    'units_exact must beat own_code_units');
end;

procedure TComponentManifestTests.Match_OwnCodePrefixAfterLibraryPrefix;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"components":[' +
    '{"name":"AppLib","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["app"]}' +
    '],"own_code_prefixes":["app"]}');
  LMatch := MatchManifestUnit(LManifest, 'appSettings');
  Assert.AreEqual(Ord(mmLibrary), Ord(LMatch.Kind),
    'A library prefix is tested before own_code_prefixes');

  LManifest := ParseManifest(
    '{"components":[],"own_code_prefixes":["app"]}');
  LMatch := MatchManifestUnit(LManifest, 'System.AppSettings');
  Assert.AreEqual(Ord(mmOwnCode), Ord(LMatch.Kind));
end;

procedure TComponentManifestTests.Licence_SpdxId_IsCanonical;
var
  LKind: TLicenceKind;
  LValue: string;
begin
  LKind := ClassifyLicence('mit', LValue);
  Assert.AreEqual(Ord(lkSpdxId), Ord(LKind));
  Assert.AreEqual('MIT', LValue);
end;

procedure TComponentManifestTests.Licence_OrLaterForm_StaysAnId;
var
  LKind: TLicenceKind;
  LValue: string;
begin
  LKind := ClassifyLicence('GPL-2.0-or-later', LValue);
  Assert.AreEqual(Ord(lkSpdxId), Ord(LKind),
    'GPL-2.0-or-later is an SPDX id, not an expression');
  Assert.AreEqual('GPL-2.0-or-later', LValue);
end;

procedure TComponentManifestTests.Licence_Expression_IsExpression;
var
  LKind: TLicenceKind;
  LValue: string;
begin
  LKind := ClassifyLicence('MPL-1.1 OR LGPL-2.1-or-later', LValue);
  Assert.AreEqual(Ord(lkExpression), Ord(LKind));
  Assert.AreEqual('MPL-1.1 OR LGPL-2.1-or-later', LValue);
  LKind := ClassifyLicence('mit and apache-2.0', LValue);
  Assert.AreEqual(Ord(lkExpression), Ord(LKind));
end;

procedure TComponentManifestTests.Licence_Commercial_IsName;
var
  LKind: TLicenceKind;
  LValue: string;
begin
  LKind := ClassifyLicence('Commercial', LValue);
  Assert.AreEqual(Ord(lkName), Ord(LKind));
  Assert.AreEqual('Commercial', LValue);
  LKind := ClassifyLicence('Proprietary', LValue);
  Assert.AreEqual(Ord(lkName), Ord(LKind));
  Assert.AreEqual('Proprietary', LValue);
  LKind := ClassifyLicence('', LValue);
  Assert.AreEqual(Ord(lkNone), Ord(LKind));
end;

procedure TComponentManifestTests.Purl_EncodesSpaceAsPercent20;
begin
  Assert.AreEqual('TMS%20VCL%20UI%20Pack', PurlEncode('TMS VCL UI Pack'));
  Assert.AreEqual('pkg:delphi/TMS%20VCL%20UI%20Pack@13.0',
    BuildDelphiPurl('TMS VCL UI Pack', '13.0', ''));
end;

procedure TComponentManifestTests.Purl_IncludesVersion;
begin
  Assert.AreEqual('pkg:delphi/OmniThreadLibrary@3.7.8',
    BuildDelphiPurl('OmniThreadLibrary', '3.7.8', ''));
end;

procedure TComponentManifestTests.Purl_OmitsEmptyVersion;
begin
  Assert.AreEqual('pkg:delphi/OmniThreadLibrary',
    BuildDelphiPurl('OmniThreadLibrary', '', ''));
  Assert.AreEqual('', BuildDelphiPurl('', '1.0', ''));
end;

procedure TComponentManifestTests.Purl_OverrideWins;
begin
  Assert.AreEqual('pkg:generic/tms-vcl@13',
    BuildDelphiPurl('TMS VCL UI Pack', '13.0', 'pkg:generic/tms-vcl@13'));
end;

procedure TComponentManifestTests.Parse_InvalidJson_SetsError;
var
  LManifest: TComponentManifest;
  LError: string;
begin
  Assert.IsFalse(TryParseComponentManifest('{', 'components.json', LManifest, LError));
  Assert.IsTrue(Pos('Invalid JSON', LError) > 0, LError);
  Assert.IsFalse(LManifest.Loaded);
end;

procedure TComponentManifestTests.Parse_RootMustBeObjectOrArray;
var
  LManifest: TComponentManifest;
  LError: string;
begin
  Assert.IsFalse(TryParseComponentManifest('"hello"', 'components.json', LManifest, LError));
  Assert.IsTrue(Pos('JSON object', LError) > 0, LError);
end;

procedure TComponentManifestTests.Parse_BareArray_IsComponents;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '[{"name":"Indy","version":"10","vendor":"Indy Project","licence":"BSD-3-Clause",' +
    '"type":"library","units_exact":["IdHTTP"]}]');
  Assert.AreEqual(NativeInt(1), NativeInt(Length(LManifest.Components)));
  Assert.AreEqual('Indy', LManifest.Components[0].Name);
  Assert.IsTrue(Length(LManifest.Warnings) > 0, 'A bare array should be noted');
end;

procedure TComponentManifestTests.Parse_LicenseAlias_IsAccepted;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"components":[{"name":"Lib","version":"1","vendor":"A","license":"Apache-2.0",' +
    '"license_url":"https://www.apache.org/licenses/LICENSE-2.0","type":"library",' +
    '"units_exact":["LibUnit"]}]}');
  Assert.AreEqual('Apache-2.0', LManifest.Components[0].Licence);
  Assert.AreEqual('https://www.apache.org/licenses/LICENSE-2.0',
    LManifest.Components[0].LicenceUrl);
end;

procedure TComponentManifestTests.Parse_ShortPrefix_Warns;
var
  LManifest: TComponentManifest;
  I: Integer;
  LFound: Boolean;
begin
  LManifest := ParseManifest(
    '{"schema_version":"1.0","last_updated":"2026-03-26",' +
    '"supplier":{"name":"Acme"},' +
    '"components":[{"name":"Indy","version":"10","vendor":"Indy","licence":"BSD-3-Clause",' +
    '"type":"library","units_prefix":["Id"]}]}');
  LFound := False;
  for I := 0 to High(LManifest.Warnings) do
    if Pos('shorter than 3', LManifest.Warnings[I]) > 0 then
      LFound := True;
  Assert.IsTrue(LFound, 'A 2-character prefix must produce a warning');
  Assert.IsTrue(LManifest.Loaded, 'The warning must not reject the file');
end;

procedure TComponentManifestTests.Load_MissingFile_NamesTheReason;
var
  LManifest: TComponentManifest;
  LJson, LError: string;
begin
  Assert.IsFalse(TryLoadComponentManifest(
    TPath.Combine(TPath.GetTempPath, 'dxm-missing-components.json'),
    LManifest, LJson, LError));
  Assert.AreEqual('File not found', LError);
end;

procedure TComponentManifestTests.Publisher_FillsEmptySupplierOnly;
var
  LManifest: TComponentManifest;
  LMetadata: TSbomMetadata;
begin
  LManifest := ParseManifest(SampleManifestJson);
  LMetadata := Default(TSbomMetadata);
  ApplyManifestPublisher(LManifest, LMetadata);
  Assert.AreEqual('Acme GmbH', LMetadata.Supplier);
  Assert.AreEqual('https://acme.example', LMetadata.SupplierUrl);

  LMetadata := Default(TSbomMetadata);
  LMetadata.Supplier := 'From CLI';
  ApplyManifestPublisher(LManifest, LMetadata);
  Assert.AreEqual('From CLI', LMetadata.Supplier);
  Assert.AreEqual('', LMetadata.SupplierUrl,
    'A manifest URL must not be attached to a different supplier name');
end;

procedure TComponentManifestTests.Resolve_RelativePath_UsesProjectDir;
begin
  Assert.AreEqual(TPath.Combine('C:\work\app', 'components.json'),
    ResolveManifestPath('C:\work\app', 'components.json'));
  Assert.AreEqual('D:\shared\components.json',
    ResolveManifestPath('C:\work\app', 'D:\shared\components.json'));
end;

procedure TComponentManifestTests.Cli_ManifestFlag_WinsInToSbomConfig;
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--manifest=components.json')));
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual('components.json', LConfig.ManifestFile);
    Assert.IsTrue(LConfig.ManifestFileExplicit);
  finally
    LOptions.Free;
  end;
end;

procedure TComponentManifestTests.Cli_EmptyManifest_IsAnError;
var
  LOptions: TCliOptions;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(TArray<string>.Create(
      '--project=App.dproj', '--manifest=')));
    Assert.IsTrue(Pos('manifest', LOptions.ParseError) > 0, LOptions.ParseError);
  finally
    LOptions.Free;
  end;
end;

procedure TComponentManifestTests.Config_ExplicitFlag_WinsOverFile;
var
  LDir, LConfigPath: string;
  LFile: TStringList;
  LConfig: TSbomConfig;
  LGen: TDxComplyGenerator;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-precedence');
  TDirectory.CreateDirectory(LDir);
  LConfigPath := TPath.Combine(LDir, '.dxcomply.json');
  LFile := TStringList.Create;
  try
    LFile.Text := '{"manifest":"from-file.json"}';
    LFile.SaveToFile(LConfigPath, TEncoding.UTF8);
  finally
    LFile.Free;
  end;

  LConfig := TSbomConfig.Default;
  LConfig.ManifestFile := 'from-cli.json';
  LConfig.ManifestFileExplicit := True;
  LGen := TDxComplyGenerator.Create(LConfig);
  try
    Assert.IsFalse(LGen.GenerateFromConfig(TPath.Combine(LDir, 'missing.dproj'), LConfigPath));
    Assert.AreEqual('from-cli.json', LGen.Config.ManifestFile,
      '--manifest must win over the config file');
    Assert.IsTrue(LGen.Config.ManifestFileExplicit);
  finally
    LGen.Free;
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TComponentManifestTests.Config_File_UsedWhenFlagAbsent;
var
  LDir, LConfigPath: string;
  LFile: TStringList;
  LGen: TDxComplyGenerator;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-from-file');
  TDirectory.CreateDirectory(LDir);
  LConfigPath := TPath.Combine(LDir, '.dxcomply.json');
  LFile := TStringList.Create;
  try
    LFile.Text := '{"manifest":"components.json"}';
    LFile.SaveToFile(LConfigPath, TEncoding.UTF8);
  finally
    LFile.Free;
  end;

  LGen := TDxComplyGenerator.Create;
  try
    Assert.IsFalse(LGen.GenerateFromConfig(TPath.Combine(LDir, 'missing.dproj'), LConfigPath));
    Assert.AreEqual('components.json', LGen.Config.ManifestFile);
    Assert.IsFalse(LGen.Config.ManifestFileExplicit);
  finally
    LGen.Free;
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TComponentManifestTests.Generate_InvalidManifest_ReportsPathAndReason;
var
  LDir, LManifestPath, LProject, LMessage: string;
  LFile: TStringList;
  LConfig: TSbomConfig;
  LGen: TDxComplyGenerator;
  LMessages: TStringList;
begin
  LProject := TPath.Combine(RepoRoot, 'src' + PathDelim + 'DX.Comply.Engine.dproj');
  Assert.IsTrue(TFile.Exists(LProject),
    'The engine project must be available for this test: ' + LProject);

  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-bad-manifest');
  TDirectory.CreateDirectory(LDir);
  LManifestPath := TPath.Combine(LDir, 'components.json');
  LFile := TStringList.Create;
  try
    LFile.Text := '{ this is not json';
    LFile.SaveToFile(LManifestPath, TEncoding.UTF8);
  finally
    LFile.Free;
  end;

  LMessages := TStringList.Create;
  LConfig := TSbomConfig.Default;
  LConfig.ManifestFile := LManifestPath;
  LConfig.OutputPath := TPath.Combine(LDir, 'bom.json');
  LGen := TDxComplyGenerator.Create(LConfig);
  try
    LGen.OnProgress :=
      procedure(const AMessage: string; const AProgress: Integer)
      begin
        LMessages.Add(AMessage);
      end;
    Assert.IsFalse(LGen.Generate(LProject, LConfig.OutputPath),
      'An invalid manifest must fail generation');
    LMessage := LMessages.Text;
    Assert.IsTrue(Pos('Invalid component manifest', LMessage) > 0, LMessage);
    Assert.IsTrue(Pos(LManifestPath, LMessage) > 0, LMessage);
    Assert.IsTrue(Pos('Invalid JSON', LMessage) > 0, LMessage);
  finally
    LGen.Free;
    LMessages.Free;
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TComponentManifestTests.JsonWriter_GroupsLibrariesAndLinksUnits;
var
  LWriter: ISbomWriter;
  LJson: TJSONObject;
  LComponents, LDependencies, LLicences: TJSONArray;
  LLibrary, LRoot, LLicenceWrap, LSupplier: TJSONObject;
  LText: string;
begin
  AddFile('TestApp.exe', 'application');
  AddUnit('OtlTask.pas');
  AddUnit('GpLists.pas');
  AddUnit('SynEdit.pas');
  AddUnit('AdvGrid.pas');
  AddUnit('MainForm.pas');
  AddUnit('Loose.pas');
  FMetadata.ComponentManifestJson := SampleManifestJson;
  FMetadata.Supplier := 'Already set';

  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    LLibrary := FindComponent(LComponents, 'OmniThreadLibrary');
    Assert.IsNotNull(LLibrary, 'Matched units must produce one library component');
    Assert.AreEqual('library', LLibrary.GetValue<string>('type'));
    Assert.AreEqual('3.7.8', LLibrary.GetValue<string>('version'));
    Assert.AreEqual('pkg:delphi/OmniThreadLibrary@3.7.8', LLibrary.GetValue<string>('purl'));
    Assert.AreEqual('Primo Gabrijelcic', LLibrary.GetValue<string>('author'));
    LSupplier := LLibrary.GetValue('supplier') as TJSONObject;
    Assert.AreEqual('Primo Gabrijelcic', LSupplier.GetValue<string>('name'));
    LLicences := LLibrary.GetValue('licenses') as TJSONArray;
    LLicenceWrap := LLicences.Items[0] as TJSONObject;
    Assert.AreEqual('MIT', TJSONObject(LLicenceWrap.GetValue('license')).GetValue<string>('id'));

    LLibrary := FindComponent(LComponents, 'SynEdit');
    LLicences := LLibrary.GetValue('licenses') as TJSONArray;
    Assert.AreEqual('MPL-1.1 OR LGPL-2.1-or-later',
      TJSONObject(LLicences.Items[0]).GetValue<string>('expression'));

    LLibrary := FindComponent(LComponents, 'TMS VCL UI Pack');
    Assert.AreEqual('pkg:generic/tms-vcl@13', LLibrary.GetValue<string>('purl'));
    LLicences := LLibrary.GetValue('licenses') as TJSONArray;
    Assert.AreEqual('Commercial',
      TJSONObject(TJSONObject(LLicences.Items[0]).GetValue('license')).GetValue<string>('name'));

    Assert.IsNotNull(FindComponent(LComponents, 'MainForm.pas'),
      'Own-code units stay in the evidence');
    Assert.IsNotNull(FindComponent(LComponents, 'Loose.pas'),
      'Unmatched units stay as they are');
    Assert.IsNotNull(FindComponent(LComponents, 'OtlTask.pas'),
      'Matched units stay in the evidence');

    LDependencies := LJson.GetValue('dependencies') as TJSONArray;
    LRoot := FindDependency(LDependencies, 'TestApp');
    Assert.IsTrue(DependsOnContains(LRoot, 'comp-0'),
      'The project depends on the program that was built');
    Assert.IsFalse(DependsOnContains(LRoot, 'manifest-0'),
      'Libraries hang off the program, not the project');
    Assert.IsFalse(DependsOnContains(LRoot, 'comp-1'),
      'A matched unit is not linked from the project');

    LRoot := FindDependency(LDependencies, 'comp-0');
    Assert.IsTrue(DependsOnContains(LRoot, 'manifest-0'));
    Assert.IsTrue(DependsOnContains(LRoot, 'manifest-1'));
    Assert.IsTrue(DependsOnContains(LRoot, 'manifest-2'));
    Assert.IsFalse(DependsOnContains(LRoot, 'comp-1'),
      'A matched unit is linked from its library, not from the program');
    Assert.IsTrue(DependsOnContains(LRoot, 'comp-5'), 'Own code stays on the program');
    Assert.IsTrue(DependsOnContains(LRoot, 'comp-6'), 'An unmatched unit stays on the program');

    LLibrary := FindDependency(LDependencies, 'manifest-0');
    Assert.IsTrue(DependsOnContains(LLibrary, 'comp-1'));
    Assert.IsTrue(DependsOnContains(LLibrary, 'comp-2'));
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.XmlWriter_LibraryElementOrder;
var
  LWriter: ISbomWriter;
  LContent, LLibrary, LErrors: string;
  LStart, LEnd, I: Integer;
  LSequence: TArray<string>;
begin
  AddFile('TestApp.exe', 'application');
  AddUnit('OtlTask.pas');
  AddUnit('SynEdit.pas');
  AddUnit('AdvGrid.pas');
  FMetadata.ComponentManifestJson := SampleManifestJson;
  FMetadata.Supplier := 'Acme GmbH';
  FMetadata.SupplierUrl := 'https://acme.example';

  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LSequence := CycloneDxXmlSequenceErrors(LContent);
  LErrors := '';
  for I := 0 to High(LSequence) do
    LErrors := LErrors + LSequence[I] + sLineBreak;
  Assert.AreEqual(NativeInt(0), NativeInt(Length(LSequence)), LErrors);

  LStart := Pos('bom-ref="manifest-0"', LContent);
  LEnd := Pos('</component>', LContent, LStart);
  LLibrary := Copy(LContent, LStart, LEnd - LStart);
  Assert.IsTrue(Pos('<supplier>', LLibrary) < Pos('<author>', LLibrary), LLibrary);
  Assert.IsTrue(Pos('<author>', LLibrary) < Pos('<name>', LLibrary, Pos('</supplier>', LLibrary)), LLibrary);
  Assert.IsTrue(Pos('<name>', LLibrary, Pos('</supplier>', LLibrary)) < Pos('<version>', LLibrary), LLibrary);
  Assert.IsTrue(Pos('<version>', LLibrary) < Pos('<licenses>', LLibrary), LLibrary);
  Assert.IsTrue(Pos('<licenses>', LLibrary) < Pos('<purl>', LLibrary), LLibrary);
  Assert.IsTrue(Pos('<purl>', LLibrary) < Pos('<externalReferences>', LLibrary), LLibrary);
  Assert.IsTrue(Pos('<id>MIT</id>', LLibrary) > 0, LLibrary);
  Assert.IsTrue(Pos('pkg:delphi/OmniThreadLibrary@3.7.8', LLibrary) > 0, LLibrary);

  Assert.IsTrue(Pos('<expression>MPL-1.1 OR LGPL-2.1-or-later</expression>', LContent) > 0);
  Assert.IsTrue(Pos('<name>Commercial</name>', LContent) > 0);
  Assert.IsTrue(Pos('pkg:generic/tms-vcl@13', LContent) > 0);
  Assert.IsTrue(Pos('<dependency ref="manifest-0">', LContent) > 0);
  Assert.IsTrue(Pos('<dependency ref="comp-1"/>', LContent) > 0);
  Assert.IsTrue(Pos('<url>https://acme.example</url>', LContent) > 0,
    'The manifest publisher URL must be written on the metadata supplier');
end;

procedure TComponentManifestTests.SpdxWriter_LicenceSupplierAndPurl;
var
  LWriter: ISbomWriter;
  LJson, LPackage, LRef: TJSONObject;
  LPackages, LRelationships, LRefs, LExtracted: TJSONArray;
  I: Integer;
  LUnitId: string;
  LDescribesLibrary, LDependsOnUnit: Boolean;
begin
  AddUnit('OtlTask.pas');
  AddUnit('SynEdit.pas');
  AddUnit('AdvGrid.pas');
  AddUnit('MainForm.pas');
  FMetadata.ComponentManifestJson := SampleManifestJson;

  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(FOutputFile, TEncoding.UTF8)) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LPackages := LJson.GetValue('packages') as TJSONArray;
    LPackage := FindComponent(LPackages, 'OmniThreadLibrary');
    Assert.IsNotNull(LPackage);
    Assert.AreEqual('MIT', LPackage.GetValue<string>('licenseDeclared'));
    Assert.AreEqual('MIT', LPackage.GetValue<string>('licenseConcluded'));
    Assert.AreEqual('Organization: Primo Gabrijelcic', LPackage.GetValue<string>('supplier'));
    LRefs := LPackage.GetValue('externalRefs') as TJSONArray;
    LRef := LRefs.Items[0] as TJSONObject;
    Assert.AreEqual('purl', LRef.GetValue<string>('referenceType'));
    Assert.AreEqual('pkg:delphi/OmniThreadLibrary@3.7.8',
      LRef.GetValue<string>('referenceLocator'));

    LPackage := FindComponent(LPackages, 'SynEdit');
    Assert.AreEqual('MPL-1.1 OR LGPL-2.1-or-later',
      LPackage.GetValue<string>('licenseDeclared'));

    LPackage := FindComponent(LPackages, 'TMS VCL UI Pack');
    Assert.AreEqual('LicenseRef-Commercial', LPackage.GetValue<string>('licenseDeclared'));
    Assert.AreEqual('LicenseRef-Commercial', LPackage.GetValue<string>('licenseConcluded'));
    LRefs := LPackage.GetValue('externalRefs') as TJSONArray;
    Assert.AreEqual('pkg:generic/tms-vcl@13',
      TJSONObject(LRefs.Items[0]).GetValue<string>('referenceLocator'));

    LExtracted := LJson.GetValue('hasExtractedLicensingInfos') as TJSONArray;
    Assert.IsNotNull(LExtracted);
    Assert.AreEqual('LicenseRef-Commercial',
      TJSONObject(LExtracted.Items[0]).GetValue<string>('licenseId'));

    Assert.IsNotNull(FindComponent(LPackages, 'MainForm.pas'),
      'Own-code units stay in the package list');

    LPackage := FindComponent(LPackages, 'OtlTask.pas');
    Assert.IsNotNull(LPackage, 'The matched unit stays in the package list');
    LUnitId := LPackage.GetValue<string>('SPDXID');

    LRelationships := LJson.GetValue('relationships') as TJSONArray;
    LDescribesLibrary := False;
    LDependsOnUnit := False;
    for I := 0 to LRelationships.Count - 1 do
    begin
      LRef := LRelationships.Items[I] as TJSONObject;
      if (LRef.GetValue<string>('relationshipType') = 'DESCRIBES') and
        (Pos('SPDXRef-Package-Manifest-0-', LRef.GetValue<string>('relatedSpdxElement')) = 1) then
        LDescribesLibrary := True;
      if (LRef.GetValue<string>('relationshipType') = 'DEPENDS_ON') and
        (Pos('SPDXRef-Package-Manifest-0-', LRef.GetValue<string>('spdxElementId')) = 1) and
        (LRef.GetValue<string>('relatedSpdxElement') = LUnitId) then
        LDependsOnUnit := True;
    end;
    Assert.IsTrue(LDescribesLibrary, 'The document must describe the library package');
    Assert.IsTrue(LDependsOnUnit, 'The library must depend on the matched unit package');
  finally
    LJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TComponentManifestTests);

end.
