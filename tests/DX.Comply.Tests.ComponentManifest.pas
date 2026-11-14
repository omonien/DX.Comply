/// <summary>
/// DX.Comply.Tests.ComponentManifest
/// DUnitX tests for the components.json manifest.
/// </summary>
///
/// <remarks>
/// Covers matching (exact beats prefix, first row wins, shared prefixes,
/// scope stripping, case, own-code folders, component folders), licence
/// classification, PURL generation, writer output, optional copyright text
/// in CycloneDX, SPDX 2.3 and SPDX 3.0.1, optional CPE text in those same
/// formats, library mode, and the CLI / config precedence for --manifest.
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
    procedure PrepareCopyrightLibraries(const AManifest: string);
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
    /// <summary>
    /// The same units_prefix assigns units to the first row and warns.
    /// A prefix matches without a trailing dot. Issue #172.
    /// </summary>
    [Test]
    procedure Match_SharedPrefix_FirstRowWins_AndWarns;
    /// <summary>The longest prefix wins whatever the row order. Issue #129.</summary>
    [Test]
    procedure Match_LongestPrefixWins_RegardlessOfOrder;
    /// <summary>units_exclude takes units out of a row's prefixes. Issue #140.</summary>
    [Test]
    procedure Match_UnitsExclude_SkipsRowPrefix;
    /// <summary>
    /// An excluded unit written with its Delphi scope (Vcl.Skia) stays out of
    /// the row when the prefix matches the name without the scope. Issue #140.
    /// </summary>
    [Test]
    procedure Match_UnitsExclude_FullScopedName_SkipsRowPrefix;
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
    /// <summary>own_code_folders marks units under that folder, including subfolders.</summary>
    [Test]
    procedure Match_OwnCodeFolder_IncludesSubfolders;
    /// <summary>units_folder assigns the units in a package folder to that row.</summary>
    [Test]
    procedure Match_ComponentFolder_AssignsRow;
    /// <summary>A folder includes its own files and subfolders, and not a sibling directory.</summary>
    [Test]
    procedure Match_Folder_SkipsSiblingDirectory;
    /// <summary>The longest folder path wins, for a package inside own code and a patch inside a package.</summary>
    [Test]
    procedure Match_Folder_LongestPathWins;
    /// <summary>units_exact still beats a folder.</summary>
    [Test]
    procedure Match_ExactBeatsFolder;
    /// <summary>own_code_units still beats a component folder.</summary>
    [Test]
    procedure Match_OwnCodeUnitBeatsFolder;
    /// <summary>A folder beats units_prefix and own_code_prefixes.</summary>
    [Test]
    procedure Match_FolderBeatsPrefix;
    /// <summary>
    /// A prefix with no dot does not assign. A prefix that contains a dot does.
    /// A prefix never assigns a unit in an Embarcadero product path.
    /// match.prefixes legacy still assigns a prefix with no dot off that path.
    /// </summary>
    [Test]
    procedure Match_CorroboratedPrefix_RequiresADot_AndSkipsProductPath;
    /// <summary>An unknown match.prefixes value warns and stays corroborated.</summary>
    [Test]
    procedure Parse_MatchPrefixes_Unknown_StaysCorroborated;
    /// <summary>units_exclude takes a unit out of that row's folder.</summary>
    [Test]
    procedure Match_UnitsExclude_SkipsFolder;
    /// <summary>A unit known only by name is not matched by a folder.</summary>
    [Test]
    procedure Match_Folder_NameOnly_DoesNotMatch;
    /// <summary>Folder comparison ignores case and accepts either slash.</summary>
    [Test]
    procedure Match_Folder_IsCaseInsensitive;
    /// <summary>The first component row wins when two folders have the same length.</summary>
    [Test]
    procedure Match_FirstFolderRowWinsOnTie;
    /// <summary>A missing folder is a warning and the rule is still applied. A file is not a folder.</summary>
    [Test]
    procedure Parse_MissingFolder_WarnsAndStillApplies;
    /// <summary>Relative folders are resolved from the components file, then kept absolute for writers.</summary>
    [Test]
    procedure Load_RelativeFolder_ResolvesAgainstManifestFile;
    /// <summary>A row that only has units_folder is a match rule.</summary>
    [Test]
    procedure Parse_FolderOnlyRow_IsAMatchRule;
    /// <summary>Grouping uses the source path, not a DCU in the output folder.</summary>
    [Test]
    procedure Plan_UsesSourcePathNotOutputDcu;
    /// <summary>
    /// The MAP unit name matches when the file name is only the last segment,
    /// and a name with no file is added when a library row matches. Issue #172.
    /// </summary>
    [Test]
    procedure Plan_UnitName_AndNameOnly_AssignedToFirstSharedPrefix;

    [Test]
    procedure Licence_SpdxId_IsCanonical;
    [Test]
    procedure Licence_OrLaterForm_StaysAnId;
    [Test]
    procedure Licence_Expression_IsExpression;
    [Test]
    procedure Licence_Commercial_IsName;
    /// <summary>
    /// A value that already starts with LicenseRef- is accepted. The SPDX
    /// token keeps that prefix. A plain name still gets one prefix.
    /// </summary>
    [Test]
    procedure Licence_LicenseRef_IsAcceptedWithoutWarning;
    /// <summary>
    /// CycloneDX writes LicenseRef-* as license.name. license.id is the
    /// SPDX license list and would reject the value.
    /// </summary>
    [Test]
    procedure Licence_LicenseRef_CycloneDxUsesName;
    /// <summary>
    /// Embarcadero RTL, VCL and FMX units use that origin label as their
    /// licence. Another file keeps none. Issue #165.
    /// </summary>
    [Test]
    procedure ComponentLicence_EmbarcaderoOrigin_UsesOriginLabel;
    /// <summary>
    /// own_code_units, own_code_prefixes and own_code_folders inherit the
    /// product licence. With no product licence they stay empty, except an
    /// Embarcadero unit, which keeps its origin label. A library row leaves
    /// the unit empty. Issue #166.
    /// </summary>
    [Test]
    procedure ComponentLicence_OwnCode_UsesProductLicence;

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
    /// <summary>
    /// An unquoted value names the file, the line and the position. Issue #172.
    /// </summary>
    [Test]
    procedure Parse_UnquotedValue_NamesFileAndPosition;
    [Test]
    procedure Parse_RootMustBeObjectOrArray;
    [Test]
    procedure Parse_BareArray_IsComponents;
    [Test]
    procedure Parse_LicenseAlias_IsAccepted;
    /// <summary>copyright is an optional string and does not affect matching. Issue #151.</summary>
    [Test]
    procedure Parse_Copyright_OptionalString;
    /// <summary>A non-string copyright is ignored. Issue #151.</summary>
    [Test]
    procedure Parse_Copyright_WrongType_IsIgnored;
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

    /// <summary>
    /// A manifest copyright is written only on that library component.
    /// CycloneDX JSON uses copyright. XML uses the same element after
    /// licenses and before purl.
    /// </summary>
    [Test]
    procedure CycloneDx_Copyright_WhenManifestSetsIt;
    /// <summary>
    /// A row that omits copyright, and a blank copyright, leave CycloneDX
    /// JSON and XML without a copyright field.
    /// </summary>
    [Test]
    procedure CycloneDx_Copyright_WhenManifestOmitsIt;
    /// <summary>
    /// SPDX 2.3 writes the manifest copyright as package copyrightText.
    /// Other packages stay NOASSERTION.
    /// </summary>
    [Test]
    procedure Spdx_CopyrightText_WhenManifestSetsIt;
    /// <summary>
    /// SPDX 2.3 keeps copyrightText NOASSERTION when no copyright is known.
    /// </summary>
    [Test]
    procedure Spdx_CopyrightText_WhenManifestOmitsIt;
    /// <summary>
    /// SPDX 3.0.1 writes software_copyrightText on the software package
    /// the manifest row describes.
    /// </summary>
    [Test]
    procedure Spdx3_CopyrightText_WhenManifestSetsIt;
    /// <summary>
    /// SPDX 3.0.1 omits software_copyrightText when the row has no copyright.
    /// </summary>
    [Test]
    procedure Spdx3_CopyrightText_WhenManifestOmitsIt;

    /// <summary>
    /// A CPE 2.3 formatted string and a CPE 2.2 URI are stored. Matching
    /// ignores them. Issue #181.
    /// </summary>
    [Test]
    procedure Parse_Cpe_Valid_IsStored;
    /// <summary>
    /// A value that is neither CPE form, and a non-string, are warnings.
    /// The row stays loaded and the CPE is left empty. Issue #181.
    /// </summary>
    [Test]
    procedure Parse_Cpe_Invalid_WarnsAndOmits;
    /// <summary>
    /// A missing cpe, a blank cpe, and null are empty and do not warn.
    /// Issue #181.
    /// </summary>
    [Test]
    procedure Parse_Cpe_AbsentOrBlank_IsEmpty;
    /// <summary>
    /// CycloneDX JSON and XML write cpe on the library component only,
    /// after copyright and before purl. Issue #181.
    /// </summary>
    [Test]
    procedure CycloneDx_Cpe_WhenManifestSetsIt;
    /// <summary>
    /// Omitting cpe, a blank cpe, and an invalid cpe leave CycloneDX
    /// without a cpe field. The row is still written. Issue #181.
    /// </summary>
    [Test]
    procedure CycloneDx_Cpe_WhenManifestOmitsIt;
    /// <summary>
    /// SPDX 2.3 writes SECURITY externalRefs, cpe23Type or cpe22Type.
    /// Issue #181.
    /// </summary>
    [Test]
    procedure Spdx_Cpe_WhenManifestSetsIt;
    /// <summary>
    /// SPDX 2.3 adds no SECURITY externalRef when no CPE is known. Issue #181.
    /// </summary>
    [Test]
    procedure Spdx_Cpe_WhenManifestOmitsIt;
    /// <summary>
    /// SPDX 3.0.1 writes externalIdentifier cpe23 or cpe22. Issue #181.
    /// </summary>
    [Test]
    procedure Spdx3_Cpe_WhenManifestSetsIt;
    /// <summary>
    /// SPDX 3.0.1 omits externalIdentifier when the row has no CPE. Issue #181.
    /// </summary>
    [Test]
    procedure Spdx3_Cpe_WhenManifestOmitsIt;
    /// <summary>
    /// dxcomply.exe --library applies a manifest row to a shipped .pas and
    /// writes that row's cpe. An invalid cpe is a warning and is omitted.
    /// Issue #181.
    /// </summary>
    [Test]
    procedure LibraryMode_Cpe_WhenManifestMatchesSource;
    /// <summary>
    /// Library mode with a project passes the install root into the manifest,
    /// so a short prefix does not assign a shipped .pas under source\rtl.
    /// units_exact still assigns on that path and keeps the row's cpe.
    /// A prefix outside the product tree still assigns in legacy mode.
    /// </summary>
    [Test]
    procedure LibraryMode_Prefix_ProductPath_KeepsInstallOrigin;
  end;

implementation

uses
  DX.Comply.Spdx3.Writer,
  DX.Comply.Tests.Paths;

procedure AssertValidation(const AResult: TValidationResult);
var
  LErrors: string;
  I: Integer;
begin
  LErrors := '';
  for I := 0 to High(AResult.Errors) do
    LErrors := LErrors + AResult.Errors[I] + sLineBreak;
  Assert.IsTrue(AResult.IsValid, LErrors);
end;

procedure AssertXmlSequence(const AContent: string);
var
  LSequence: TArray<string>;
  LErrors: string;
  I: Integer;
begin
  LSequence := CycloneDxXmlSequenceErrors(AContent);
  LErrors := '';
  for I := 0 to High(LSequence) do
    LErrors := LErrors + LSequence[I] + sLineBreak;
  Assert.AreEqual(NativeInt(0), NativeInt(Length(LSequence)), LErrors);
end;

const
  cCopyrightNotice = 'Copyright (c) 2020 Smith & Sons';
  cCpe23 = 'cpe:2.3:a:openssl:openssl:3.0.2:*:*:*:*:*:*:*';
  cCpe22 = 'cpe:/a:sqlite:sqlite:3.45.0';

function ManifestCpeSet: string;
begin
  Result :=
    '{"components":[' +
    '{"name":"OpenSSL","version":"3.0.2","vendor":"OpenSSL",' +
    '"licence":"Apache-2.0","type":"library","copyright":"2020",' +
    '"cpe":"' + cCpe23 + '","units_exact":["OpenSsl"]},' +
    '{"name":"SQLite","version":"3.45.0","vendor":"SQLite",' +
    '"licence":"MIT","type":"library",' +
    '"cpe":"' + cCpe22 + '","units_exact":["Sqlite"]}]}';
end;

function ManifestCpeOmitted: string;
begin
  // The second row is only spaces. Parsing trims that to empty.
  // The third row is not a CPE. Parsing warns and clears it.
  Result :=
    '{"components":[' +
    '{"name":"OpenSSL","version":"3.0.2","vendor":"OpenSSL",' +
    '"licence":"Apache-2.0","type":"library","units_exact":["OpenSsl"]},' +
    '{"name":"SQLite","version":"3.45.0","vendor":"SQLite",' +
    '"licence":"MIT","type":"library","cpe":"   ","units_exact":["Sqlite"]},' +
    '{"name":"Broken","version":"1","vendor":"Broken",' +
    '"licence":"MIT","type":"library","cpe":"not-a-cpe","units_exact":["Broken"]}]}';
end;

function SpdxExternalRef(APackage: TJSONObject; const AType: string): TJSONObject;
var
  LRefs: TJSONArray;
  I: Integer;
  LRef: TJSONObject;
begin
  Result := nil;
  if not Assigned(APackage) or not (APackage.GetValue('externalRefs') is TJSONArray) then
    Exit;
  LRefs := TJSONArray(APackage.GetValue('externalRefs'));
  for I := 0 to LRefs.Count - 1 do
  begin
    if not (LRefs.Items[I] is TJSONObject) then
      Continue;
    LRef := TJSONObject(LRefs.Items[I]);
    if (LRef.GetValue('referenceType') <> nil) and
      SameText(LRef.GetValue<string>('referenceType'), AType) then
      Exit(LRef);
  end;
end;

function Spdx3ExternalId(APackage: TJSONObject; const AType: string): TJSONObject;
var
  LIds: TJSONArray;
  I: Integer;
  LId: TJSONObject;
begin
  Result := nil;
  if not Assigned(APackage) or
    not (APackage.GetValue('externalIdentifier') is TJSONArray) then
    Exit;
  LIds := TJSONArray(APackage.GetValue('externalIdentifier'));
  for I := 0 to LIds.Count - 1 do
  begin
    if not (LIds.Items[I] is TJSONObject) then
      Continue;
    LId := TJSONObject(LIds.Items[I]);
    if (LId.GetValue('externalIdentifierType') <> nil) and
      SameText(LId.GetValue<string>('externalIdentifierType'), AType) then
      Exit(LId);
  end;
end;

function WarningContains(const AManifest: TComponentManifest;
  const AText: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(AManifest.Warnings) do
    if Pos(AText, AManifest.Warnings[I]) > 0 then
      Exit(True);
end;

function ManifestCopyrightSet: string;
begin
  Result :=
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"OmniThreadLibrary","version":"3.7.8","vendor":"Primo Gabrijelcic",' +
    '"licence":"MIT","type":"library",' +
    '"copyright":"' + cCopyrightNotice + '","units_exact":["OtlTask"]},' +
    '{"name":"SynEdit","version":"3.0","vendor":"SynEdit Contributors",' +
    '"licence":"MPL-1.1","type":"library","units_exact":["SynEdit"]}]}';
end;

function ManifestCopyrightOmitted: string;
begin
  // The second row sets copyright to spaces. Parsing trims that to empty,
  // which is the same as leaving the field out.
  Result :=
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"OmniThreadLibrary","version":"3.7.8","vendor":"Primo Gabrijelcic",' +
    '"licence":"MIT","type":"library","units_exact":["OtlTask"]},' +
    '{"name":"SynEdit","version":"3.0","vendor":"SynEdit Contributors",' +
    '"licence":"MPL-1.1","type":"library","copyright":"   ",' +
    '"units_exact":["SynEdit"]}]}';
end;

function XmlComponentSlice(const AContent, ABomRef: string): string;
var
  LStart, LEnd: Integer;
begin
  LStart := Pos('bom-ref="' + ABomRef + '"', AContent);
  Assert.IsTrue(LStart > 0, 'Missing component ' + ABomRef);
  LEnd := Pos('</component>', AContent, LStart);
  Assert.IsTrue(LEnd > LStart, ABomRef);
  Result := Copy(AContent, LStart, LEnd - LStart);
end;

function Spdx3Package(ADoc: TJSONObject; const AName: string): TJSONObject;
var
  LGraph: TJSONArray;
  I: Integer;
  LItem: TJSONObject;
begin
  Result := nil;
  LGraph := ADoc.GetValue('@graph') as TJSONArray;
  Assert.IsNotNull(LGraph, '@graph must be present');
  for I := 0 to LGraph.Count - 1 do
  begin
    if not (LGraph.Items[I] is TJSONObject) then
      Continue;
    LItem := TJSONObject(LGraph.Items[I]);
    if (LItem.GetValue('type') <> nil) and
      (LItem.GetValue<string>('type') = 'software_Package') and
      (LItem.GetValue('name') <> nil) and
      SameText(LItem.GetValue<string>('name'), AName) then
      Exit(LItem);
  end;
  Assert.Fail(AName + ' must appear as a software_Package');
end;

function JsonPath(const APath: string): string;
begin
  // Delphi strings do not treat "\" as an escape. JSON does.
  Result := StringReplace(APath, '\', '\\', [rfReplaceAll]);
end;

procedure AssertFolderMatch(const AManifest: TComponentManifest;
  const AUnitName, APath: string; AKind: TManifestMatchKind; AIndex: Integer;
  const AMessage: string);
var
  LMatch: TManifestMatch;
begin
  LMatch := MatchManifestUnit(AManifest, AUnitName, APath);
  Assert.AreEqual(Ord(AKind), Ord(LMatch.Kind), AMessage);
  Assert.AreEqual(AIndex, LMatch.ComponentIndex, AMessage);
end;

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
    '"match":{"prefixes":"legacy"},' +
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

procedure TComponentManifestTests.PrepareCopyrightLibraries(const AManifest: string);
begin
  AddUnit('OtlTask.pas');
  AddUnit('SynEdit.pas');
  FMetadata.ComponentManifestJson := AManifest;
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
  FMetadata.ToolVersion := '2.0.0.0';
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
    '{"match":{"prefixes":"legacy"},"components":[' +
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
    '{"match":{"prefixes":"legacy"},"components":[' +
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
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"First","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Spring"]},' +
    '{"name":"Second","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Spring"]}' +
    ']}');
  LMatch := MatchManifestUnit(LManifest, 'Spring.Collections');
  Assert.AreEqual(0, LMatch.ComponentIndex, 'The first prefix row must win');
end;

procedure TComponentManifestTests.Match_SharedPrefix_FirstRowWins_AndWarns;
const
  cCoreFirst = 'units_prefix "FMX.TMSFNC" is shared by "TMS FNC Core" and ' +
    '"TMS FNC UI Pack". Units that start with it are assigned to ' +
    '"TMS FNC Core", the first row in the file. Use units_exact or a more ' +
    'specific units_prefix for the other rows.';
  cPackFirst = 'units_prefix "FMX.TMSFNC" is shared by "TMS FNC UI Pack" and ' +
    '"TMS FNC Core". Units that start with it are assigned to ' +
    '"TMS FNC UI Pack", the first row in the file. Use units_exact or a more ' +
    'specific units_prefix for the other rows.';
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;

  function SharedWarning(const AManifest: TComponentManifest): string;
  var
    I: Integer;
  begin
    Result := '';
    for I := 0 to High(AManifest.Warnings) do
      if Pos('units_prefix "', AManifest.Warnings[I]) > 0 then
        Exit(AManifest.Warnings[I]);
  end;

begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"TMS FNC Core","version":"4.2.3.7","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNC"]},' +
    '{"name":"TMS FNC UI Pack","version":"7.1.2.2","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNC"]},' +
    '{"name":"TMS FNC Charts","version":"1.0.0","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNCCharts"]}' +
    ']}');
  Assert.AreEqual(cCoreFirst, SharedWarning(LManifest));

  LMatch := MatchManifestUnit(LManifest, 'FMX.TMSFNCButton');
  Assert.AreEqual(NativeInt(Ord(mmLibrary)), NativeInt(Ord(LMatch.Kind)));
  Assert.AreEqual(0, LMatch.ComponentIndex,
    'A prefix without a trailing dot must match the unit name');
  LMatch := MatchManifestUnit(LManifest, 'FMX.TMSFNC.Types');
  Assert.AreEqual(0, LMatch.ComponentIndex);
  LMatch := MatchManifestUnit(LManifest, 'fmx.tmsfncbutton');
  Assert.AreEqual(0, LMatch.ComponentIndex, 'Prefix matching ignores case');
  LMatch := MatchManifestUnit(LManifest, 'FMX.TMSFNCCharts.Core');
  Assert.AreEqual(2, LMatch.ComponentIndex, 'The longer prefix still wins');
  LMatch := MatchManifestUnit(LManifest, 'TMSFNCButton');
  Assert.AreEqual(NativeInt(Ord(mmNone)), NativeInt(Ord(LMatch.Kind)),
    'The shortened file name does not start with FMX.TMSFNC');

  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"TMS FNC UI Pack","version":"7.1.2.2","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNC"]},' +
    '{"name":"TMS FNC Core","version":"4.2.3.7","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNC"]}' +
    ']}');
  Assert.AreEqual(cPackFirst, SharedWarning(LManifest));
  LMatch := MatchManifestUnit(LManifest, 'FMX.TMSFNCButton');
  Assert.AreEqual(0, LMatch.ComponentIndex);
  Assert.AreEqual('TMS FNC UI Pack', LManifest.Components[LMatch.ComponentIndex].Name);
end;

procedure TComponentManifestTests.Match_LongestPrefixWins_RegardlessOfOrder;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"Base","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Neslib"]},' +
    '{"name":"Xml","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Neslib.Xml"]}' +
    '],"own_code_units":["Neslib.Xml.Mine"]}');
  Assert.AreEqual(1, MatchManifestUnit(LManifest, 'Neslib.Xml.Reader').ComponentIndex,
    'The longer prefix must win over an earlier shorter one');
  Assert.AreEqual(0, MatchManifestUnit(LManifest, 'Neslib.Utils').ComponentIndex);
  Assert.AreEqual(NativeInt(Ord(mmOwnCode)),
    NativeInt(Ord(MatchManifestUnit(LManifest, 'Neslib.Xml.Mine').Kind)),
    'own_code_units keeps priority over any prefix');

  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"Xml","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Neslib.Xml"]},' +
    '{"name":"Base","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Neslib"],"units_exact":["Neslib.Xml.Special"]}' +
    ']}');
  Assert.AreEqual(0, MatchManifestUnit(LManifest, 'Neslib.Xml.Reader').ComponentIndex);
  Assert.AreEqual(1, MatchManifestUnit(LManifest, 'Neslib.Xml.Special').ComponentIndex,
    'units_exact keeps priority over a longer prefix');
end;

procedure TComponentManifestTests.Match_UnitsExclude_SkipsRowPrefix;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"Abbrevia","version":"5","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_prefix":["Ab"],"units_exclude":["AboutBox","abcd"]},' +
    '{"name":"Other","version":"1","vendor":"B","licence":"MIT","type":"library",' +
    '"units_exact":["AboutBox"]}' +
    ']}');
  Assert.AreEqual(NativeInt(2), NativeInt(Length(LManifest.Components[0].ExcludeUnits)));
  Assert.AreEqual(0, MatchManifestUnit(LManifest, 'AbZipper').ComponentIndex);
  Assert.AreEqual(NativeInt(Ord(mmNone)),
    NativeInt(Ord(MatchManifestUnit(LManifest, 'ABCD').Kind)),
    'An excluded unit must not match the row (case-insensitive)');
  Assert.AreEqual(1, MatchManifestUnit(LManifest, 'AboutBox').ComponentIndex,
    'An excluded unit can still match another row');
end;

procedure TComponentManifestTests.Match_UnitsExclude_FullScopedName_SkipsRowPrefix;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"Skia4Delphi","version":"6","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Skia"],"units_exclude":["Vcl.Skia","FMX.Skia.Canvas"]}' +
    ']}');
  Assert.AreEqual(0, MatchManifestUnit(LManifest, 'Skia.API').ComponentIndex,
    'A unit that is not excluded still matches');
  Assert.AreEqual(0, MatchManifestUnit(LManifest, 'Vcl.Skia.Designtime').ComponentIndex,
    'Another unit of the same scope still matches by its stripped name');
  Assert.AreEqual(NativeInt(Ord(mmNone)),
    NativeInt(Ord(MatchManifestUnit(LManifest, 'Vcl.Skia').Kind)),
    'The full scoped name in units_exclude must keep the unit out of the row');
  Assert.AreEqual(NativeInt(Ord(mmNone)),
    NativeInt(Ord(MatchManifestUnit(LManifest, 'fmx.skia.canvas').Kind)),
    'The exclusion is case-insensitive');
end;

procedure TComponentManifestTests.Match_StripsKnownScopePrefix;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
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
    '{"match":{"prefixes":"legacy"},"components":[' +
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
    '{"match":{"prefixes":"legacy"},"components":[' +
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
    '{"match":{"prefixes":"legacy"},"components":[' +
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
    '{"match":{"prefixes":"legacy"},"components":[' +
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
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"AppLib","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["app"]}' +
    '],"own_code_prefixes":["app"]}');
  LMatch := MatchManifestUnit(LManifest, 'appSettings');
  Assert.AreEqual(Ord(mmLibrary), Ord(LMatch.Kind),
    'A library prefix is tested before own_code_prefixes');

  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[],"own_code_prefixes":["app"]}');
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
  LKind := ClassifyLicence('LicenseRef-Mine OR MIT', LValue);
  Assert.AreEqual(Ord(lkExpression), Ord(LKind));
  Assert.AreEqual('LicenseRef-Mine OR MIT', LValue);
  LKind := ClassifyLicence('(MIT OR Apache-2.0) AND GPL-2.0-only', LValue);
  Assert.AreEqual(Ord(lkExpression), Ord(LKind));
  LKind := ClassifyLicence('LicenseRef-Freeware with source', LValue);
  Assert.AreEqual(Ord(lkName), Ord(LKind), 'English "with" is not an operator');
  LKind := ClassifyLicence('Freeware with source', LValue);
  Assert.AreEqual(Ord(lkName), Ord(LKind));
  LKind := ClassifyLicence('Free and open', LValue);
  Assert.AreEqual(Ord(lkName), Ord(LKind));
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

procedure TComponentManifestTests.Licence_LicenseRef_IsAcceptedWithoutWarning;
var
  LManifest: TComponentManifest;
  LKind: TLicenceKind;

  function WarnsFor(const ALicence: string): Boolean;
  var
    LIdx: Integer;
  begin
    Result := False;
    for LIdx := 0 to High(LManifest.Warnings) do
      if Pos('licence "' + ALicence + '" is not a recognised SPDX identifier',
        LManifest.Warnings[LIdx]) > 0 then
        Exit(True);
  end;

begin
  Assert.AreEqual('LicenseRef-Proprietary', SpdxLicenceTokenFor('LicenseRef-Proprietary', LKind));
  Assert.AreEqual(Ord(lkName), Ord(LKind));
  Assert.AreEqual('licenseref-Proprietary', SpdxLicenceTokenFor('  licenseref-Proprietary  ', LKind));
  Assert.AreEqual('LicenseRef-Freeware-with-source',
    SpdxLicenceTokenFor('LicenseRef-Freeware with source', LKind));
  Assert.AreEqual(Ord(lkName), Ord(LKind));
  Assert.AreEqual('LicenseRef-Freeware-with-source',
    SpdxLicenceTokenFor('Freeware with source', LKind));
  Assert.AreEqual(Ord(lkName), Ord(LKind));
  Assert.AreEqual('LicenseRef-Free-and-open',
    SpdxLicenceTokenFor('Free and open', LKind));
  Assert.AreEqual(Ord(lkName), Ord(LKind));
  Assert.AreEqual('LicenseRef-Proprietary', SpdxLicenceTokenFor('Proprietary', LKind));
  Assert.AreEqual('LicenseRef-Custom', SpdxLicenceTokenFor('LicenseRef-', LKind));
  Assert.AreEqual('LicenseRef-Custom', SpdxLicenceTokenFor('!!!', LKind));
  Assert.AreEqual('LicenseRef-Custom', SpdxLicenceTokenFor('LicenseRef-!!!', LKind));
  Assert.AreEqual('LicenseRef-Custom', SpdxLicenceTokenFor('...', LKind));
  Assert.AreEqual('LicenseRef-Custom', SpdxLicenceTokenFor('LicenseRef-...', LKind));
  Assert.AreEqual('MIT', SpdxLicenceTokenFor('mit', LKind));
  Assert.AreEqual(Ord(lkSpdxId), Ord(LKind));

  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"A","version":"1","vendor":"V","licence":"LicenseRef-Proprietary","units_exact":["A"]},' +
    '{"name":"B","version":"1","vendor":"V","licence":" licenseref-Freeware-with-source ","units_exact":["B"]},' +
    '{"name":"C","version":"1","vendor":"V","licence":"Commercial","units_exact":["C"]},' +
    '{"name":"D","version":"1","vendor":"V","licence":"Proprietary","units_exact":["D"]},' +
    '{"name":"E","version":"1","vendor":"V","licence":"MIT","units_exact":["E"]},' +
    '{"name":"F","version":"1","vendor":"V","licence":"LicenseRef","units_exact":["F"]}' +
    ']}');
  Assert.IsFalse(WarnsFor('LicenseRef-Proprietary'), 'LicenseRef-Proprietary is accepted');
  Assert.IsFalse(WarnsFor('licenseref-Freeware-with-source'), 'letter case does not matter');
  Assert.IsFalse(WarnsFor('Commercial'));
  Assert.IsFalse(WarnsFor('MIT'));
  Assert.IsTrue(WarnsFor('Proprietary'), 'a plain name is still reported');
  Assert.IsTrue(WarnsFor('LicenseRef'), 'the dash is required');
end;

procedure TComponentManifestTests.Licence_LicenseRef_CycloneDxUsesName;
var
  LComponent, LWrap, LLicence: TJSONObject;
  LLicences: TJSONArray;
  LLines: TStringList;
begin
  LComponent := TJSONObject.Create;
  try
    AddCycloneDxLicences(LComponent, 'LicenseRef-Proprietary', '');
    LLicences := LComponent.GetValue('licenses') as TJSONArray;
    Assert.IsNotNull(LLicences);
    Assert.AreEqual(NativeInt(2), NativeInt(LLicences.Count));
    LWrap := LLicences.Items[0] as TJSONObject;
    LLicence := LWrap.GetValue('license') as TJSONObject;
    Assert.AreEqual('LicenseRef-Proprietary', LLicence.GetValue<string>('name'));
    Assert.IsNull(LLicence.GetValue('id'), 'LicenseRef is not an SPDX list id');
    Assert.AreEqual('concluded', LLicence.GetValue<string>('acknowledgement'));
    LWrap := LLicences.Items[1] as TJSONObject;
    LLicence := LWrap.GetValue('license') as TJSONObject;
    Assert.AreEqual('declared', LLicence.GetValue<string>('acknowledgement'));
    Assert.AreEqual('LicenseRef-Proprietary', LLicence.GetValue<string>('name'));
    Assert.AreEqual(0, Pos('LicenseRef-LicenseRef', LComponent.ToJSON));
  finally
    LComponent.Free;
  end;

  LLines := TStringList.Create;
  try
    AppendCycloneDxLicencesXml(LLines, 'licenseref-Freeware-with-source', '', 1);
    Assert.IsTrue(Pos('<name>licenseref-Freeware-with-source</name>', LLines.Text) > 0,
      LLines.Text);
    Assert.AreEqual(0, Pos('<id>', LLines.Text));
    Assert.AreEqual(0, Pos('LicenseRef-LicenseRef', LLines.Text));
  finally
    LLines.Free;
  end;
end;

procedure TComponentManifestTests.ComponentLicence_EmbarcaderoOrigin_UsesOriginLabel;
var
  LUnit, LFile: TArtefactInfo;
  LManifest: TComponentManifest;
begin
  LManifest := Default(TComponentManifest);
  LUnit := Default(TArtefactInfo);
  LUnit.RelativePath := 'System.SysUtils.pas';
  LUnit.ArtefactType := 'unit-evidence';
  LUnit.Origin := 'Embarcadero RTL';
  Assert.AreEqual('Embarcadero RTL', ComponentLicenceFor(LUnit, False, 'MIT', LManifest));
  LUnit.RelativePath := 'Winapi.Windows.pas';
  Assert.AreEqual('Embarcadero RTL', ComponentLicenceFor(LUnit, False, '', LManifest),
    'Other Embarcadero units use the same origin label');
  LUnit.RelativePath := 'Vcl.Forms.pas';
  LUnit.Origin := 'Embarcadero VCL';
  Assert.AreEqual('Embarcadero VCL', ComponentLicenceFor(LUnit, False, '', LManifest));
  LUnit.RelativePath := 'FMX.Forms.pas';
  LUnit.Origin := 'Embarcadero FMX';
  Assert.AreEqual('Embarcadero FMX', ComponentLicenceFor(LUnit, False, 'MIT', LManifest));
  LUnit.Origin := 'Third party';
  Assert.AreEqual('', ComponentLicenceFor(LUnit, False, 'MIT', LManifest));
  LFile := Default(TArtefactInfo);
  LFile.RelativePath := 'vendor.dll';
  LFile.ArtefactType := 'library';
  LFile.Origin := 'Embarcadero RTL';
  Assert.AreEqual('', ComponentLicenceFor(LFile, False, 'MIT', LManifest),
    'A file that is not unit evidence does not take the origin label');
end;

procedure TComponentManifestTests.ComponentLicence_OwnCode_UsesProductLicence;
var
  LManifest: TComponentManifest;
  LUnit, LExe: TArtefactInfo;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[{"name":"Wrapped","version":"1","vendor":"A","licence":"MIT",' +
    '"type":"library","units_exact":["Data.DB"]}],' +
    '"own_code_units":["MainForm","System.SysUtils"],' +
    '"own_code_prefixes":["App"],' +
    '"own_code_folders":["' + JsonPath('C:\DXComplyFolderTest\src') + '"]}');

  LUnit := Default(TArtefactInfo);
  LUnit.ArtefactType := 'unit-evidence';
  LUnit.Origin := 'Local project';
  LUnit.RelativePath := 'MainForm.pas';
  Assert.AreEqual('Apache-2.0', ComponentLicenceFor(LUnit, False, 'Apache-2.0', LManifest));
  LUnit.RelativePath := 'AppSettings.pas';
  Assert.AreEqual('Apache-2.0', ComponentLicenceFor(LUnit, False, ' Apache-2.0 ', LManifest),
    'An own_code_prefixes unit inherits the trimmed product licence');
  LUnit.RelativePath := 'Helper.pas';
  LUnit.SourcePath := 'C:\DXComplyFolderTest\src\Helper.pas';
  Assert.AreEqual('Apache-2.0', ComponentLicenceFor(LUnit, False, 'Apache-2.0', LManifest),
    'An own_code_folders unit inherits the product licence');
  LUnit.SourcePath := '';
  LUnit.RelativePath := 'LocalOnly.pas';
  Assert.AreEqual('', ComponentLicenceFor(LUnit, False, 'Apache-2.0', LManifest),
    'A local unit that is not own code stays without a licence');

  LUnit.RelativePath := 'System.SysUtils.pas';
  LUnit.Origin := 'Embarcadero RTL';
  Assert.AreEqual('Apache-2.0', ComponentLicenceFor(LUnit, False, 'Apache-2.0', LManifest),
    'Own code wins over the Embarcadero origin when a product licence is set');
  Assert.AreEqual('Embarcadero RTL', ComponentLicenceFor(LUnit, False, '', LManifest),
    'Without a product licence an Embarcadero own-code unit keeps its origin label');
  LUnit.RelativePath := 'MainForm.pas';
  LUnit.Origin := 'Local project';
  Assert.AreEqual('', ComponentLicenceFor(LUnit, False, '', LManifest),
    'Without a product licence other own-code units stay empty');

  LUnit.RelativePath := 'Data.DB.pas';
  LUnit.Origin := 'Embarcadero RTL';
  Assert.AreEqual('', ComponentLicenceFor(LUnit, False, 'Apache-2.0', LManifest),
    'A manifest library keeps the unit licence empty');

  LExe := Default(TArtefactInfo);
  LExe.RelativePath := 'Demo.exe';
  LExe.ArtefactType := 'application';
  Assert.AreEqual('MIT', ComponentLicenceFor(LExe, True, ' MIT ', LManifest));
  Assert.AreEqual('', ComponentLicenceFor(LExe, True, '', LManifest));
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

procedure TComponentManifestTests.Parse_UnquotedValue_NamesFileAndPosition;
var
  LManifest: TComponentManifest;
  LError: string;
  LJson: string;
begin
  LJson := '{' + #10 +
    '  "name": "TMS FNC Core",' + #10 +
    '  "vendor_url": https://www.tmssoftware.com' + #10 +
    '}';
  Assert.IsFalse(TryParseComponentManifest(LJson, 'components.json', LManifest, LError));
  Assert.IsFalse(LManifest.Loaded);
  Assert.AreEqual('Invalid JSON in "components.json" at line 3, position 17', LError);
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
    '{"match":{"prefixes":"legacy"},"components":[{"name":"Lib","version":"1","vendor":"A","license":"Apache-2.0",' +
    '"license_url":"https://www.apache.org/licenses/LICENSE-2.0","type":"library",' +
    '"units_exact":["LibUnit"]}]}');
  Assert.AreEqual('Apache-2.0', LManifest.Components[0].Licence);
  Assert.AreEqual('https://www.apache.org/licenses/LICENSE-2.0',
    LManifest.Components[0].LicenceUrl);
end;

procedure TComponentManifestTests.Parse_Copyright_OptionalString;
var
  LWith, LWithout: TComponentManifest;
  I: Integer;
begin
  LWith := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"Neslib XML","version":"1.0","copyright":"2020",' +
    '"vendor":"Neslib","licence":"MIT","type":"library","units_exact":["Neslib.Xml"]},' +
    '{"name":"Other","version":"2","copyright":"Copyright (c) 2019 Example",' +
    '"vendor":"Example","licence":"Apache-2.0","type":"library","units_prefix":["Example"]}' +
    ']}');
  Assert.AreEqual(NativeInt(2), NativeInt(Length(LWith.Components)));
  Assert.AreEqual('2020', LWith.Components[0].Copyright);
  Assert.AreEqual('Copyright (c) 2019 Example', LWith.Components[1].Copyright);
  Assert.IsTrue(LWith.Loaded);
  for I := 0 to High(LWith.Warnings) do
    Assert.IsTrue(Pos('copyright', LWith.Warnings[I]) = 0, LWith.Warnings[I]);
  Assert.AreEqual(Ord(mmLibrary), Ord(MatchManifestUnit(LWith, 'Neslib.Xml').Kind));
  Assert.AreEqual(0, MatchManifestUnit(LWith, 'Neslib.Xml').ComponentIndex);
  Assert.AreEqual(1, MatchManifestUnit(LWith, 'Example.Collections').ComponentIndex);

  LWithout := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[{"name":"Neslib XML","version":"1.0",' +
    '"vendor":"Neslib","licence":"MIT","type":"library","units_exact":["Neslib.Xml"]}]}');
  Assert.AreEqual('', LWithout.Components[0].Copyright);
  Assert.IsTrue(LWithout.Loaded, 'A row without copyright must stay valid');
  Assert.AreEqual(MatchManifestUnit(LWithout, 'Neslib.Xml').ComponentIndex,
    MatchManifestUnit(LWith, 'Neslib.Xml').ComponentIndex);
  Assert.AreEqual(Ord(mmLibrary), Ord(MatchManifestUnit(LWithout, 'Neslib.Xml').Kind));
end;

procedure TComponentManifestTests.Parse_Copyright_WrongType_IsIgnored;
var
  LManifest: TComponentManifest;
  I: Integer;
  LFound: Boolean;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[{"name":"Lib","version":"1","copyright":{"year":2020},' +
    '"vendor":"A","licence":"MIT","type":"library","units_exact":["LibUnit"]}]}');
  Assert.AreEqual('', LManifest.Components[0].Copyright);
  Assert.IsTrue(LManifest.Loaded);
  LFound := False;
  for I := 0 to High(LManifest.Warnings) do
    if (Pos('"copyright"', LManifest.Warnings[I]) > 0) and
      (Pos('should be a string', LManifest.Warnings[I]) > 0) then
      LFound := True;
  Assert.IsTrue(LFound, 'A non-string copyright must be reported and ignored');
  Assert.AreEqual(Ord(mmLibrary), Ord(MatchManifestUnit(LManifest, 'LibUnit').Kind));
  Assert.AreEqual(0, MatchManifestUnit(LManifest, 'LibUnit').ComponentIndex);
end;

procedure TComponentManifestTests.Parse_ShortPrefix_Warns;
var
  LManifest: TComponentManifest;
  I: Integer;
  LFound: Boolean;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"schema_version":"1.0","last_updated":"2026-03-26",' +
    '"supplier":{"name":"Acme"},' +
    '"components":[{"name":"Indy","version":"10","vendor":"Indy","licence":"BSD-3-Clause",' +
    '"type":"library","units_prefix":["Id"]}]}');
  LFound := False;
  for I := 0 to High(LManifest.Warnings) do
    if (Pos('shorter than 3', LManifest.Warnings[I]) > 0) and
      (Pos('still applied', LManifest.Warnings[I]) > 0) then
      LFound := True;
  Assert.IsTrue(LFound, 'A 2-character prefix must produce a warning that says it is still applied');
  Assert.AreEqual(0, MatchManifestUnit(LManifest, 'IdHTTP').ComponentIndex,
    'A short prefix is still applied');
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

  LMetadata := Default(TSbomMetadata);
  LMetadata.SupplierUrl := 'https://cli.example';
  ApplyManifestPublisher(LManifest, LMetadata);
  Assert.AreEqual('Acme GmbH', LMetadata.Supplier);
  Assert.AreEqual('https://cli.example', LMetadata.SupplierUrl,
    'An explicit supplier URL stays when the manifest fills an empty name');
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
    Assert.AreEqual(NativeInt(2), NativeInt(LLicences.Count));
    LLicenceWrap := LLicences.Items[0] as TJSONObject;
    Assert.AreEqual('MIT', TJSONObject(LLicenceWrap.GetValue('license')).GetValue<string>('id'));
    Assert.AreEqual('concluded',
      TJSONObject(LLicenceWrap.GetValue('license')).GetValue<string>('acknowledgement'));
    Assert.AreEqual('declared',
      TJSONObject(TJSONObject(LLicences.Items[1] as TJSONObject).GetValue('license')).GetValue<string>('acknowledgement'));

    LLibrary := FindComponent(LComponents, 'SynEdit');
    LLicences := LLibrary.GetValue('licenses') as TJSONArray;
    Assert.AreEqual(NativeInt(1), NativeInt(LLicences.Count));
    Assert.AreEqual('MPL-1.1 OR LGPL-2.1-or-later',
      TJSONObject(LLicences.Items[0]).GetValue<string>('expression'));
    Assert.AreEqual('concluded',
      TJSONObject(LLicences.Items[0]).GetValue<string>('acknowledgement'));

    LLibrary := FindComponent(LComponents, 'TMS VCL UI Pack');
    Assert.AreEqual('pkg:generic/tms-vcl@13', LLibrary.GetValue<string>('purl'));
    LLicences := LLibrary.GetValue('licenses') as TJSONArray;
    Assert.AreEqual(NativeInt(2), NativeInt(LLicences.Count));
    Assert.AreEqual('Commercial',
      TJSONObject(TJSONObject(LLicences.Items[0]).GetValue('license')).GetValue<string>('name'));
    Assert.AreEqual('concluded',
      TJSONObject(TJSONObject(LLicences.Items[0]).GetValue('license')).GetValue<string>('acknowledgement'));
    Assert.AreEqual('declared',
      TJSONObject(TJSONObject(LLicences.Items[1]).GetValue('license')).GetValue<string>('acknowledgement'));

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

  Assert.IsTrue(Pos('<expression acknowledgement="concluded">MPL-1.1 OR LGPL-2.1-or-later</expression>', LContent) > 0);
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

procedure TComponentManifestTests.CycloneDx_Copyright_WhenManifestSetsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LLibrary: TJSONObject;
  LComponents: TJSONArray;
  LLibraryXml, LUnitXml: string;
  LAt: Integer;
  LValidator: TSbomValidator;
begin
  PrepareCopyrightLibraries(ManifestCopyrightSet);

  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateCycloneDxJson(LText));
  finally
    LValidator.Free;
  end;
  LAt := Pos('"copyright"', LText);
  Assert.IsTrue(LAt > 0, 'The library component must carry copyright');
  Assert.AreEqual(0, Pos('"copyright"', LText, LAt + 1),
    'Only the manifest row that sets copyright is written');

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    LLibrary := FindComponent(LComponents, 'OmniThreadLibrary');
    Assert.IsNotNull(LLibrary);
    Assert.AreEqual(cCopyrightNotice, LLibrary.GetValue<string>('copyright'));
    LLibrary := FindComponent(LComponents, 'SynEdit');
    Assert.IsNotNull(LLibrary);
    Assert.IsNull(LLibrary.GetValue('copyright'),
      'A row without copyright must not gain the field');
    LLibrary := FindComponent(LComponents, 'OtlTask.pas');
    Assert.IsNotNull(LLibrary, 'The matched unit stays in the evidence');
    Assert.IsNull(LLibrary.GetValue('copyright'),
      'Copyright belongs to the library component, not the unit');
  finally
    LJson.Free;
  end;

  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  AssertXmlSequence(LText);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateCycloneDxXml(LText));
  finally
    LValidator.Free;
  end;
  LAt := Pos('<copyright>', LText);
  Assert.IsTrue(LAt > 0, LText);
  Assert.AreEqual(0, Pos('<copyright>', LText, LAt + 1),
    'XML writes one copyright element');
  LLibraryXml := XmlComponentSlice(LText, 'manifest-0');
  Assert.IsTrue(Pos('<licenses>', LLibraryXml) < Pos('<copyright>', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<copyright>', LLibraryXml) < Pos('<purl>', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<copyright>Copyright (c) 2020 Smith &amp; Sons</copyright>',
    LLibraryXml) > 0, LLibraryXml);
  Assert.AreEqual(0, Pos('<copyright>', XmlComponentSlice(LText, 'manifest-1')));
  LUnitXml := XmlComponentSlice(LText, 'comp-0');
  Assert.AreEqual(0, Pos('<copyright>', LUnitXml), LUnitXml);
end;

procedure TComponentManifestTests.CycloneDx_Copyright_WhenManifestOmitsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LLibrary: TJSONObject;
  LComponents: TJSONArray;
  I: Integer;
  LValidator: TSbomValidator;
begin
  PrepareCopyrightLibraries(ManifestCopyrightOmitted);

  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateCycloneDxJson(LText));
  finally
    LValidator.Free;
  end;
  Assert.AreEqual(0, Pos('"copyright"', LText),
    'Omitting copyright, or setting only spaces, must not add the field');

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    for I := 0 to LComponents.Count - 1 do
    begin
      LLibrary := LComponents.Items[I] as TJSONObject;
      Assert.IsNull(LLibrary.GetValue('copyright'), LLibrary.GetValue<string>('name'));
    end;
    Assert.IsNotNull(FindComponent(LComponents, 'OmniThreadLibrary'));
    Assert.IsNotNull(FindComponent(LComponents, 'SynEdit'));
  finally
    LJson.Free;
  end;

  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  AssertXmlSequence(LText);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateCycloneDxXml(LText));
  finally
    LValidator.Free;
  end;
  Assert.AreEqual(0, Pos('<copyright', LText), LText);
  Assert.IsTrue(Pos('bom-ref="manifest-0"', LText) > 0, 'The library component is still written');
  Assert.IsTrue(Pos('bom-ref="manifest-1"', LText) > 0, 'A blank copyright still matches the row');
end;

procedure TComponentManifestTests.Spdx_CopyrightText_WhenManifestSetsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LPackage: TJSONObject;
  LPackages: TJSONArray;
  LValidator: TSbomValidator;
begin
  PrepareCopyrightLibraries(ManifestCopyrightSet);

  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateSpdxJson(LText));
  finally
    LValidator.Free;
  end;

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LPackages := LJson.GetValue('packages') as TJSONArray;
    LPackage := FindComponent(LPackages, 'OmniThreadLibrary');
    Assert.IsNotNull(LPackage);
    Assert.AreEqual(cCopyrightNotice, LPackage.GetValue<string>('copyrightText'));
    LPackage := FindComponent(LPackages, 'SynEdit');
    Assert.IsNotNull(LPackage);
    Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('copyrightText'));
    LPackage := FindComponent(LPackages, 'OtlTask.pas');
    Assert.IsNotNull(LPackage, 'The matched unit stays a package');
    Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('copyrightText'));
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.Spdx_CopyrightText_WhenManifestOmitsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LPackage: TJSONObject;
  LPackages: TJSONArray;
  I: Integer;
  LValidator: TSbomValidator;
begin
  PrepareCopyrightLibraries(ManifestCopyrightOmitted);

  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateSpdxJson(LText));
  finally
    LValidator.Free;
  end;
  Assert.AreEqual(0, Pos(cCopyrightNotice, LText), LText);

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LPackages := LJson.GetValue('packages') as TJSONArray;
    Assert.IsNotNull(FindComponent(LPackages, 'OmniThreadLibrary'));
    Assert.IsNotNull(FindComponent(LPackages, 'SynEdit'));
    for I := 0 to LPackages.Count - 1 do
    begin
      LPackage := LPackages.Items[I] as TJSONObject;
      Assert.AreEqual('NOASSERTION', LPackage.GetValue<string>('copyrightText'),
        LPackage.GetValue<string>('name'));
    end;
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.Spdx3_CopyrightText_WhenManifestSetsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LPackage: TJSONObject;
  LGraph: TJSONArray;
  I, LCount: Integer;
  LValidator: TSbomValidator;
begin
  PrepareCopyrightLibraries(ManifestCopyrightSet);

  LWriter := TSpdx3JsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateSpdx3Json(LText));
  finally
    LValidator.Free;
  end;

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LPackage := Spdx3Package(LJson, 'OmniThreadLibrary');
    Assert.AreEqual(cCopyrightNotice, LPackage.GetValue<string>('software_copyrightText'));
    LPackage := Spdx3Package(LJson, 'SynEdit');
    Assert.IsNull(LPackage.GetValue('software_copyrightText'));
    LPackage := Spdx3Package(LJson, 'OtlTask.pas');
    Assert.IsNull(LPackage.GetValue('software_copyrightText'),
      'The unit package does not take the library copyright');

    LCount := 0;
    LGraph := LJson.GetValue('@graph') as TJSONArray;
    for I := 0 to LGraph.Count - 1 do
      if (LGraph.Items[I] is TJSONObject) and
        (TJSONObject(LGraph.Items[I]).GetValue('software_copyrightText') <> nil) then
        Inc(LCount);
    Assert.AreEqual(NativeInt(1), NativeInt(LCount),
      'Only the library with a copyright notice is marked');
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.Spdx3_CopyrightText_WhenManifestOmitsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LItem: TJSONObject;
  LGraph: TJSONArray;
  I: Integer;
  LValidator: TSbomValidator;
begin
  PrepareCopyrightLibraries(ManifestCopyrightOmitted);

  LWriter := TSpdx3JsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateSpdx3Json(LText));
  finally
    LValidator.Free;
  end;
  Assert.AreEqual(0, Pos('software_copyrightText', LText),
    'No copyright notice means the SPDX 3 property stays absent');
  Assert.AreEqual(0, Pos(cCopyrightNotice, LText), LText);

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    Assert.IsNotNull(Spdx3Package(LJson, 'OmniThreadLibrary'));
    Assert.IsNotNull(Spdx3Package(LJson, 'SynEdit'));
    LGraph := LJson.GetValue('@graph') as TJSONArray;
    for I := 0 to LGraph.Count - 1 do
    begin
      if not (LGraph.Items[I] is TJSONObject) then
        Continue;
      LItem := TJSONObject(LGraph.Items[I]);
      Assert.IsNull(LItem.GetValue('software_copyrightText'));
    end;
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.Parse_Cpe_Valid_IsStored;
var
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
  I: Integer;
begin
  LManifest := ParseManifest(ManifestCpeSet);
  Assert.AreEqual(cCpe23, LManifest.Components[0].Cpe);
  Assert.AreEqual(cCpe22, LManifest.Components[1].Cpe);
  Assert.AreEqual(Ord(ckCpe23), Ord(ClassifyCpe(LManifest.Components[0].Cpe)));
  Assert.AreEqual(Ord(ckCpe22), Ord(ClassifyCpe(LManifest.Components[1].Cpe)));
  for I := 0 to High(LManifest.Warnings) do
    Assert.IsTrue(Pos('cpe', LManifest.Warnings[I]) = 0, LManifest.Warnings[I]);
  LMatch := MatchManifestUnit(LManifest, 'OpenSsl');
  Assert.AreEqual(Ord(mmLibrary), Ord(LMatch.Kind));
  Assert.AreEqual(0, LMatch.ComponentIndex);
  Assert.AreEqual(Ord(ckNone), Ord(ClassifyCpe('')));
end;

procedure TComponentManifestTests.Parse_Cpe_Invalid_WarnsAndOmits;
var
  LManifest: TComponentManifest;
  LError: string;
begin
  Assert.IsTrue(TryParseComponentManifest(
    '{"components":[{"name":"OpenSSL","version":"3.0.2","vendor":"OpenSSL",' +
    '"licence":"Apache-2.0","type":"library",' +
    '"cpe":"cpe:2.3:a:openssl:openssl","units_exact":["OpenSsl"]}]}',
    'components.json', LManifest, LError), LError);
  Assert.IsTrue(LManifest.Loaded, 'An invalid cpe must not fail the parse');
  Assert.AreEqual('', LManifest.Components[0].Cpe);
  Assert.IsTrue(WarningContains(LManifest, 'was omitted'),
    string.Join(sLineBreak, LManifest.Warnings));
  Assert.IsTrue(WarningContains(LManifest, 'cpe:2.3:a:openssl:openssl'),
    string.Join(sLineBreak, LManifest.Warnings));

  Assert.IsTrue(TryParseComponentManifest(
    '{"components":[{"name":"OpenSSL","version":"3.0.2","vendor":"OpenSSL",' +
    '"licence":"Apache-2.0","type":"library","cpe":{"id":"openssl"},' +
    '"units_exact":["OpenSsl"]}]}',
    'components.json', LManifest, LError), LError);
  Assert.IsTrue(LManifest.Loaded);
  Assert.AreEqual('', LManifest.Components[0].Cpe);
  Assert.IsTrue(WarningContains(LManifest, '"cpe" should be a string and was ignored'),
    string.Join(sLineBreak, LManifest.Warnings));

  Assert.AreEqual(Ord(ckNone), Ord(ClassifyCpe(
    'CPE:2.3:a:openssl:openssl:3.0.2:*:*:*:*:*:*:*')));
  Assert.AreEqual(Ord(ckNone), Ord(ClassifyCpe('not-a-cpe')));
end;

procedure TComponentManifestTests.Parse_Cpe_AbsentOrBlank_IsEmpty;
var
  LWith, LWithout: TComponentManifest;
  LError: string;
  I: Integer;
begin
  Assert.IsTrue(TryParseComponentManifest(
    '{"components":[{"name":"OpenSSL","version":"3.0.2","licence":"MIT",' +
    '"type":"library","cpe":"   ","units_exact":["OpenSsl"]},' +
    '{"name":"Other","version":"1","licence":"MIT","type":"library",' +
    '"cpe":null,"units_exact":["Other"]}]}',
    'test', LWith, LError), LError);
  Assert.AreEqual('', LWith.Components[0].Cpe);
  Assert.AreEqual('', LWith.Components[1].Cpe);
  for I := 0 to High(LWith.Warnings) do
    Assert.IsTrue(Pos('cpe', LWith.Warnings[I]) = 0, LWith.Warnings[I]);

  LWithout := ParseManifest(
    '{"components":[{"name":"OpenSSL","version":"3.0.2","licence":"MIT",' +
    '"type":"library","units_exact":["OpenSsl"]}]}');
  Assert.AreEqual('', LWithout.Components[0].Cpe);
  Assert.IsTrue(LWithout.Loaded, 'A row without cpe must stay valid');
end;

procedure TComponentManifestTests.CycloneDx_Cpe_WhenManifestSetsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LLibrary: TJSONObject;
  LComponents: TJSONArray;
  LLibraryXml: string;
  LValidator: TSbomValidator;
begin
  AddUnit('OpenSsl.pas');
  AddUnit('Sqlite.pas');
  FMetadata.ComponentManifestJson := ManifestCpeSet;

  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateCycloneDxJson(LText));
  finally
    LValidator.Free;
  end;

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    LLibrary := FindComponent(LComponents, 'OpenSSL');
    Assert.IsNotNull(LLibrary);
    Assert.AreEqual(cCpe23, LLibrary.GetValue<string>('cpe'));
    Assert.IsTrue(Pos('"copyright"', LLibrary.ToString) < Pos('"cpe"', LLibrary.ToString),
      LLibrary.ToString);
    Assert.IsTrue(Pos('"cpe"', LLibrary.ToString) < Pos('"purl"', LLibrary.ToString),
      LLibrary.ToString);
    LLibrary := FindComponent(LComponents, 'SQLite');
    Assert.IsNotNull(LLibrary);
    Assert.AreEqual(cCpe22, LLibrary.GetValue<string>('cpe'));
    LLibrary := FindComponent(LComponents, 'OpenSsl.pas');
    Assert.IsNotNull(LLibrary, 'The matched unit stays in the evidence');
    Assert.IsNull(LLibrary.GetValue('cpe'),
      'CPE belongs to the library component, not the unit');
  finally
    LJson.Free;
  end;

  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  AssertXmlSequence(LText);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateCycloneDxXml(LText));
  finally
    LValidator.Free;
  end;
  LLibraryXml := XmlComponentSlice(LText, 'manifest-0');
  Assert.IsTrue(Pos('<copyright>', LLibraryXml) < Pos('<cpe>', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<cpe>', LLibraryXml) < Pos('<purl>', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<cpe>' + cCpe23 + '</cpe>', LLibraryXml) > 0, LLibraryXml);
  LLibraryXml := XmlComponentSlice(LText, 'manifest-1');
  Assert.AreEqual(0, Pos('<copyright>', LLibraryXml));
  Assert.IsTrue(Pos('<licenses>', LLibraryXml) < Pos('<cpe>', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<cpe>', LLibraryXml) < Pos('<purl>', LLibraryXml), LLibraryXml);
  Assert.IsTrue(Pos('<cpe>' + cCpe22 + '</cpe>', LLibraryXml) > 0, LLibraryXml);
  Assert.AreEqual(0, Pos('<cpe>', XmlComponentSlice(LText, 'comp-0')));
end;

procedure TComponentManifestTests.CycloneDx_Cpe_WhenManifestOmitsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LLibrary: TJSONObject;
  LComponents: TJSONArray;
  I: Integer;
  LValidator: TSbomValidator;
begin
  AddUnit('OpenSsl.pas');
  AddUnit('Sqlite.pas');
  AddUnit('Broken.pas');
  FMetadata.ComponentManifestJson := ManifestCpeOmitted;

  LWriter := TCycloneDxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateCycloneDxJson(LText));
  finally
    LValidator.Free;
  end;
  Assert.AreEqual(0, Pos('"cpe"', LText),
    'Omitting cpe, a blank cpe, or an invalid cpe must not add the field');

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LComponents := LJson.GetValue('components') as TJSONArray;
    Assert.IsNotNull(FindComponent(LComponents, 'OpenSSL'));
    Assert.IsNotNull(FindComponent(LComponents, 'SQLite'));
    Assert.IsNotNull(FindComponent(LComponents, 'Broken'),
      'An invalid cpe still writes the library component');
    for I := 0 to LComponents.Count - 1 do
    begin
      LLibrary := LComponents.Items[I] as TJSONObject;
      Assert.IsNull(LLibrary.GetValue('cpe'), LLibrary.GetValue<string>('name'));
    end;
  finally
    LJson.Free;
  end;

  LWriter := TCycloneDxXmlWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  AssertXmlSequence(LText);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateCycloneDxXml(LText));
  finally
    LValidator.Free;
  end;
  Assert.AreEqual(0, Pos('<cpe', LText), LText);
  Assert.IsTrue(Pos('bom-ref="manifest-2"', LText) > 0,
    'A rejected cpe still matches the row');
end;

procedure TComponentManifestTests.Spdx_Cpe_WhenManifestSetsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LPackage, LRef: TJSONObject;
  LPackages: TJSONArray;
  LValidator: TSbomValidator;
begin
  AddUnit('OpenSsl.pas');
  AddUnit('Sqlite.pas');
  FMetadata.ComponentManifestJson := ManifestCpeSet;

  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateSpdxJson(LText));
  finally
    LValidator.Free;
  end;

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LPackages := LJson.GetValue('packages') as TJSONArray;
    LPackage := FindComponent(LPackages, 'OpenSSL');
    Assert.IsNotNull(LPackage);
    LRef := SpdxExternalRef(LPackage, 'cpe23Type');
    Assert.IsNotNull(LRef, 'The library package must carry cpe23Type');
    Assert.AreEqual('SECURITY', LRef.GetValue<string>('referenceCategory'));
    Assert.AreEqual(cCpe23, LRef.GetValue<string>('referenceLocator'));
    Assert.IsNull(SpdxExternalRef(LPackage, 'cpe22Type'));
    Assert.IsNotNull(SpdxExternalRef(LPackage, 'purl'),
      'The package URL stays on the package');

    LPackage := FindComponent(LPackages, 'SQLite');
    Assert.IsNotNull(LPackage);
    LRef := SpdxExternalRef(LPackage, 'cpe22Type');
    Assert.IsNotNull(LRef, 'A CPE 2.2 URI is referenceType cpe22Type');
    Assert.AreEqual('SECURITY', LRef.GetValue<string>('referenceCategory'));
    Assert.AreEqual(cCpe22, LRef.GetValue<string>('referenceLocator'));

    LPackage := FindComponent(LPackages, 'OpenSsl.pas');
    Assert.IsNotNull(LPackage, 'The matched unit stays a package');
    Assert.IsNull(SpdxExternalRef(LPackage, 'cpe23Type'));
    Assert.IsNull(SpdxExternalRef(LPackage, 'cpe22Type'));
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.Spdx_Cpe_WhenManifestOmitsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LPackage: TJSONObject;
  LPackages: TJSONArray;
  I: Integer;
  LValidator: TSbomValidator;
begin
  AddUnit('OpenSsl.pas');
  AddUnit('Sqlite.pas');
  AddUnit('Broken.pas');
  FMetadata.ComponentManifestJson := ManifestCpeOmitted;

  LWriter := TSpdxJsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateSpdxJson(LText));
  finally
    LValidator.Free;
  end;
  Assert.AreEqual(0, Pos('cpe23Type', LText), LText);
  Assert.AreEqual(0, Pos('cpe22Type', LText), LText);
  Assert.AreEqual(0, Pos('not-a-cpe', LText), LText);
  Assert.AreEqual(0, Pos('"SECURITY"', LText), LText);

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LPackages := LJson.GetValue('packages') as TJSONArray;
    Assert.IsNotNull(FindComponent(LPackages, 'OpenSSL'));
    Assert.IsNotNull(FindComponent(LPackages, 'SQLite'));
    Assert.IsNotNull(FindComponent(LPackages, 'Broken'));
    for I := 0 to LPackages.Count - 1 do
    begin
      LPackage := LPackages.Items[I] as TJSONObject;
      Assert.IsNull(SpdxExternalRef(LPackage, 'cpe23Type'),
        LPackage.GetValue<string>('name'));
      Assert.IsNull(SpdxExternalRef(LPackage, 'cpe22Type'),
        LPackage.GetValue<string>('name'));
    end;
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.Spdx3_Cpe_WhenManifestSetsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LPackage, LId: TJSONObject;
  LValidator: TSbomValidator;
begin
  AddUnit('OpenSsl.pas');
  AddUnit('Sqlite.pas');
  FMetadata.ComponentManifestJson := ManifestCpeSet;

  LWriter := TSpdx3JsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateSpdx3Json(LText));
  finally
    LValidator.Free;
  end;

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    LPackage := Spdx3Package(LJson, 'OpenSSL');
    LId := Spdx3ExternalId(LPackage, 'cpe23');
    Assert.IsNotNull(LId, 'The software package must carry cpe23');
    Assert.AreEqual('ExternalIdentifier', LId.GetValue<string>('type'));
    Assert.AreEqual(cCpe23, LId.GetValue<string>('identifier'));
    Assert.IsNull(Spdx3ExternalId(LPackage, 'cpe22'));

    LPackage := Spdx3Package(LJson, 'SQLite');
    LId := Spdx3ExternalId(LPackage, 'cpe22');
    Assert.IsNotNull(LId, 'A CPE 2.2 URI is externalIdentifierType cpe22');
    Assert.AreEqual(cCpe22, LId.GetValue<string>('identifier'));

    LPackage := Spdx3Package(LJson, 'OpenSsl.pas');
    Assert.IsNull(LPackage.GetValue('externalIdentifier'),
      'The unit package does not take the library CPE');
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.Spdx3_Cpe_WhenManifestOmitsIt;
var
  LWriter: ISbomWriter;
  LText: string;
  LJson, LItem: TJSONObject;
  LGraph: TJSONArray;
  I: Integer;
  LValidator: TSbomValidator;
begin
  AddUnit('OpenSsl.pas');
  AddUnit('Sqlite.pas');
  AddUnit('Broken.pas');
  FMetadata.ComponentManifestJson := ManifestCpeOmitted;

  LWriter := TSpdx3JsonWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputFile, FMetadata, FArtefacts, FProjectInfo));
  LText := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
  LValidator := TSbomValidator.Create;
  try
    AssertValidation(LValidator.ValidateSpdx3Json(LText));
  finally
    LValidator.Free;
  end;
  Assert.AreEqual(0, Pos('externalIdentifier', LText),
    'No CPE means the SPDX 3 property stays absent');
  Assert.AreEqual(0, Pos('not-a-cpe', LText), LText);
  Assert.AreEqual(0, Pos(cCpe23, LText), LText);

  LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
  Assert.IsNotNull(LJson);
  try
    Assert.IsNotNull(Spdx3Package(LJson, 'OpenSSL'));
    Assert.IsNotNull(Spdx3Package(LJson, 'SQLite'));
    Assert.IsNotNull(Spdx3Package(LJson, 'Broken'));
    LGraph := LJson.GetValue('@graph') as TJSONArray;
    for I := 0 to LGraph.Count - 1 do
    begin
      if not (LGraph.Items[I] is TJSONObject) then
        Continue;
      LItem := TJSONObject(LGraph.Items[I]);
      Assert.IsNull(LItem.GetValue('externalIdentifier'));
    end;
  finally
    LJson.Free;
  end;
end;

procedure TComponentManifestTests.LibraryMode_Cpe_WhenManifestMatchesSource;
var
  LDir, LManifestPath, LOutput, LText, LMessage: string;
  LConfig: TSbomConfig;
  LGenerator: TDxComplyGenerator;
  LMessages: TList<string>;
  LJson, LComponent, LPackage, LRef, LId: TJSONObject;
  LComponents: TJSONArray;
  LValidator: TSbomValidator;
  LWarned: Boolean;
  LCapture: TProgressEvent;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxc-cpe-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LDir);
  LMessages := TList<string>.Create;
  try
    // OnProgress is a method reference. A nested procedure that uses
    // LMessages cannot be captured (E2555). An anonymous method can.
    LCapture :=
      procedure(const AMessage: string; const AProgress: Integer)
      begin
        LMessages.Add(AMessage);
      end;
    TFile.WriteAllText(TPath.Combine(LDir, 'OpenSsl.pas'),
      'unit OpenSsl;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(LDir, 'Sqlite.pas'),
      'unit Sqlite;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(LDir, 'Plain.pas'),
      'unit Plain;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
    LManifestPath := TPath.Combine(LDir, 'components.json');
    TFile.WriteAllText(LManifestPath,
      '{"supplier":{"name":"Acme"},"components":[' +
      '{"name":"OpenSSL","version":"3.0.2","vendor":"OpenSSL","licence":"Apache-2.0",' +
      '"type":"library","cpe":"' + cCpe23 + '","units_exact":["OpenSsl"]},' +
      '{"name":"SQLite","version":"3.45.0","vendor":"SQLite","licence":"MIT",' +
      '"type":"library","cpe":"not-a-cpe","units_exact":["Sqlite"]}]}',
      TEncoding.UTF8);

    LConfig := TSbomConfig.Default;
    LConfig.LibraryMode := True;
    LConfig.SourceDirs := [LDir];
    LConfig.ManifestFile := LManifestPath;
    LConfig.Supplier := 'Acme';
    LConfig.Licence := 'MIT';
    LConfig.SbomCreator := 'sbom@acme.example';

    LOutput := TPath.Combine(LDir, 'lib.cdx.json');
    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress := LCapture;
      Assert.IsTrue(LGenerator.Generate('', LOutput, sfCycloneDxJson),
        string.Join(sLineBreak, LMessages.ToArray));
    finally
      LGenerator.Free;
    end;

    LWarned := False;
    for LMessage in LMessages do
      if Pos('was omitted', LMessage) > 0 then
        LWarned := True;
    Assert.IsTrue(LWarned, 'Library mode must warn and continue: ' +
      string.Join(sLineBreak, LMessages.ToArray));

    LText := TFile.ReadAllText(LOutput, TEncoding.UTF8);
    LValidator := TSbomValidator.Create;
    try
      AssertValidation(LValidator.ValidateCycloneDxJson(LText));
    finally
      LValidator.Free;
    end;
    LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
    try
      LComponents := LJson.GetValue('components') as TJSONArray;
      LComponent := FindComponent(LComponents, 'OpenSSL');
      Assert.IsNotNull(LComponent, 'The matched row is a library component');
      Assert.AreEqual(cCpe23, LComponent.GetValue<string>('cpe'));
      LComponent := FindComponent(LComponents, 'SQLite');
      Assert.IsNotNull(LComponent, 'An invalid cpe still matches the shipped unit');
      Assert.IsNull(LComponent.GetValue('cpe'));
      LComponent := FindComponent(LComponents, 'OpenSsl.pas');
      Assert.IsNotNull(LComponent);
      Assert.IsNull(LComponent.GetValue('cpe'));
      LComponent := FindComponent(LComponents, 'Plain.pas');
      Assert.IsNotNull(LComponent, 'An unmatched file stays in the SBOM');
      Assert.IsNull(LComponent.GetValue('cpe'));
    finally
      LJson.Free;
    end;

    LMessages.Clear;
    LOutput := TPath.Combine(LDir, 'lib.spdx.json');
    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress := LCapture;
      Assert.IsTrue(LGenerator.Generate('', LOutput, sfSpdxJson),
        string.Join(sLineBreak, LMessages.ToArray));
    finally
      LGenerator.Free;
    end;
    LText := TFile.ReadAllText(LOutput, TEncoding.UTF8);
    LValidator := TSbomValidator.Create;
    try
      AssertValidation(LValidator.ValidateSpdxJson(LText));
    finally
      LValidator.Free;
    end;
    LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
    try
      LPackage := FindComponent(LJson.GetValue('packages') as TJSONArray, 'OpenSSL');
      Assert.IsNotNull(LPackage);
      LRef := SpdxExternalRef(LPackage, 'cpe23Type');
      Assert.IsNotNull(LRef);
      Assert.AreEqual('SECURITY', LRef.GetValue<string>('referenceCategory'));
      Assert.AreEqual(cCpe23, LRef.GetValue<string>('referenceLocator'));
      LPackage := FindComponent(LJson.GetValue('packages') as TJSONArray, 'SQLite');
      Assert.IsNotNull(LPackage);
      Assert.IsNull(SpdxExternalRef(LPackage, 'cpe23Type'));
      Assert.IsNull(SpdxExternalRef(LPackage, 'cpe22Type'));
    finally
      LJson.Free;
    end;

    LMessages.Clear;
    LOutput := TPath.Combine(LDir, 'lib.spdx3.json');
    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress := LCapture;
      Assert.IsTrue(LGenerator.Generate('', LOutput, sfSpdx3Json),
        string.Join(sLineBreak, LMessages.ToArray));
    finally
      LGenerator.Free;
    end;
    LText := TFile.ReadAllText(LOutput, TEncoding.UTF8);
    LValidator := TSbomValidator.Create;
    try
      AssertValidation(LValidator.ValidateSpdx3Json(LText));
    finally
      LValidator.Free;
    end;
    LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
    try
      LPackage := Spdx3Package(LJson, 'OpenSSL');
      LId := Spdx3ExternalId(LPackage, 'cpe23');
      Assert.IsNotNull(LId);
      Assert.AreEqual(cCpe23, LId.GetValue<string>('identifier'));
      LPackage := Spdx3Package(LJson, 'SQLite');
      Assert.IsNull(LPackage.GetValue('externalIdentifier'));
    finally
      LJson.Free;
    end;
  finally
    LMessages.Free;
    if TDirectory.Exists(LDir) then
      TDirectory.Delete(LDir, True);
  end;
end;

procedure TComponentManifestTests.LibraryMode_Prefix_ProductPath_KeepsInstallOrigin;
var
  LRoot, LInstall, LProject, LRtl, LVendor, LManifestPath, LOutput, LText: string;
  LMessage, LProductRef, LVendorRef, LExactRef: string;
  LConfig: TSbomConfig;
  LGenerator: TDxComplyGenerator;
  LMessages: TList<string>;
  LJson, LComponent, LDependency: TJSONObject;
  LComponents, LDependencies: TJSONArray;
  LCapture: TProgressEvent;
  LRefused: Boolean;

  function BomRefForFile(AComponents: TJSONArray; const AFileName: string): string;
  var
    I: Integer;
    LItem: TJSONObject;
    LName: string;
  begin
    Result := '';
    if not Assigned(AComponents) then
      Exit;
    for I := 0 to AComponents.Count - 1 do
    begin
      if not (AComponents.Items[I] is TJSONObject) then
        Continue;
      LItem := TJSONObject(AComponents.Items[I]);
      if LItem.GetValue('name') = nil then
        Continue;
      LName := LItem.GetValue('name').Value;
      LName := StringReplace(LName, '/', '\', [rfReplaceAll]);
      if SameText(LName, AFileName) or
        SameText(LName, AFileName + '.pas') or
        ((Length(LName) >= Length(AFileName) + 5) and
        SameText(Copy(LName, Length(LName) - Length(AFileName) - 4, MaxInt),
          '\' + AFileName + '.pas')) then
      begin
        if LItem.GetValue('bom-ref') <> nil then
          Exit(LItem.GetValue('bom-ref').Value);
      end;
    end;
  end;

begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'dxc-libprefix-' + TGUID.NewGuid.ToString);
  LInstall := TPath.Combine(LRoot, 'install');
  LProject := TPath.Combine(LRoot, 'proj');
  LRtl := TPath.Combine(LInstall, 'source\rtl');
  LVendor := TPath.Combine(LProject, 'vendor');
  TDirectory.CreateDirectory(TPath.Combine(LRtl, 'win'));
  TDirectory.CreateDirectory(LVendor);
  LMessages := TList<string>.Create;
  try
    LCapture :=
      procedure(const AMessage: string; const AProgress: Integer)
      begin
        LMessages.Add(AMessage);
      end;
    TFile.WriteAllText(TPath.Combine(LRtl, 'win\Winapi.GDIPAPI.pas'),
      'unit Winapi.GDIPAPI;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(LRtl, 'System.Classes.pas'),
      'unit System.Classes;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(LVendor, 'GDIPFill.pas'),
      'unit GDIPFill;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(LProject, 'Demo.dpr'),
      'program Demo;' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak,
      TEncoding.UTF8);
    LManifestPath := TPath.Combine(LProject, 'components.json');
    TFile.WriteAllText(LManifestPath,
      '{"match":{"prefixes":"legacy"},"components":[' +
      '{"name":"Pack","version":"1.0","vendor":"Example","licence":"MIT",' +
      '"type":"library","cpe":"' + cCpe23 + '","units_prefix":["GDIP"]},' +
      '{"name":"RtlExact","version":"1.0","vendor":"Example","licence":"MIT",' +
      '"type":"library","cpe":"' + cCpe23 + '","units_exact":["System.Classes"]}]}',
      TEncoding.UTF8);

    LConfig := TSbomConfig.Default;
    LConfig.LibraryMode := True;
    LConfig.Delphi7Root := LInstall;
    LConfig.SourceDirs := [LRtl, LVendor];
    LConfig.ManifestFile := LManifestPath;
    LConfig.Supplier := 'Example';
    LConfig.Licence := 'MIT';
    LConfig.SbomCreator := 'sbom@example.test';

    LOutput := TPath.Combine(LProject, 'lib.cdx.json');
    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress := LCapture;
      Assert.IsTrue(LGenerator.Generate(TPath.Combine(LProject, 'Demo.dpr'),
        LOutput, sfCycloneDxJson),
        string.Join(sLineBreak, LMessages.ToArray));
    finally
      LGenerator.Free;
    end;

    LRefused := False;
    for LMessage in LMessages do
      if (Pos('Prefix match not applied', LMessage) > 0) and
        (Pos('Winapi.GDIPAPI', LMessage) > 0) and
        (Pos('prefix GDIP', LMessage) > 0) and
        (Pos('row Pack', LMessage) > 0) then
        LRefused := True;
    Assert.IsTrue(LRefused, 'The product-path prefix must be logged: ' +
      string.Join(sLineBreak, LMessages.ToArray));

    LText := TFile.ReadAllText(LOutput, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LText) as TJSONObject;
    try
      LComponents := LJson.GetValue('components') as TJSONArray;
      LComponent := FindComponent(LComponents, 'Pack');
      Assert.IsNotNull(LComponent, 'The prefix still matches a file outside the product tree');
      Assert.AreEqual(cCpe23, LComponent.GetValue<string>('cpe'));
      LComponent := FindComponent(LComponents, 'RtlExact');
      Assert.IsNotNull(LComponent, 'units_exact still matches a product-path source file');
      Assert.AreEqual(cCpe23, LComponent.GetValue<string>('cpe'));

      LProductRef := BomRefForFile(LComponents, 'Winapi.GDIPAPI');
      LVendorRef := BomRefForFile(LComponents, 'GDIPFill');
      LExactRef := BomRefForFile(LComponents, 'System.Classes');
      Assert.AreNotEqual('', LProductRef, 'The product-path unit stays in the SBOM');
      Assert.AreNotEqual('', LVendorRef, 'The file outside the product tree stays in the SBOM');
      Assert.AreNotEqual('', LExactRef, 'The exact-matched unit stays in the SBOM');

      LDependencies := LJson.GetValue('dependencies') as TJSONArray;
      LDependency := FindDependency(LDependencies, 'manifest-0');
      Assert.IsNotNull(LDependency, 'Pack is the first manifest library');
      Assert.IsTrue(DependsOnContains(LDependency, LVendorRef),
        'Legacy mode assigns GDIPFill, which is not on a product path');
      Assert.IsFalse(DependsOnContains(LDependency, LProductRef),
        'A product path blocks the GDIP prefix');
      LDependency := FindDependency(LDependencies, 'manifest-1');
      Assert.IsNotNull(LDependency, 'RtlExact is the second manifest library');
      Assert.IsTrue(DependsOnContains(LDependency, LExactRef),
        'units_exact assigns System.Classes on the product path');
    finally
      LJson.Free;
    end;
  finally
    LMessages.Free;
    if TDirectory.Exists(LRoot) then
      TDirectory.Delete(LRoot, True);
  end;
end;

procedure TComponentManifestTests.Match_OwnCodeFolder_IncludesSubfolders;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[],"own_code_folders":["' +
    JsonPath('C:\DXComplyFolderTest\src') + '"]}');
  AssertFolderMatch(LManifest, 'Main',
    'C:\DXComplyFolderTest\src\App\Main.pas', mmOwnCode, -1,
    'A unit in a subfolder of own_code_folders is own code');
  AssertFolderMatch(LManifest, 'VendorUnit',
    'C:\DXComplyFolderTest\libs\VendorUnit.pas', mmNone, -1,
    'A unit outside the own-code folder stays unmatched');
end;

procedure TComponentManifestTests.Match_ComponentFolder_AssignsRow;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]}]}');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\run\JvCore.pas', mmLibrary, 0,
    'A unit under units_folder belongs to that row');
end;

procedure TComponentManifestTests.Match_Folder_SkipsSiblingDirectory;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]}]}');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\JvCore.pas', mmLibrary, 0,
    'A unit directly in the folder matches');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\run\core\JvCore.pas', mmLibrary, 0,
    'Subfolders are included');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL2\JvCore.pas', mmNone, -1,
    'A sibling directory whose name starts with the folder name does not match');
end;

procedure TComponentManifestTests.Match_Folder_LongestPathWins;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\src\ThirdParty\JVCL') + '"]}' +
    '],"own_code_folders":["' + JsonPath('C:\DXComplyFolderTest\src') + '"]}');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\src\ThirdParty\JVCL\run\JvCore.pas', mmLibrary, 0,
    'A package folder inside the own-code tree wins because it is longer');
  AssertFolderMatch(LManifest, 'Main',
    'C:\DXComplyFolderTest\src\App\Main.pas', mmOwnCode, -1,
    'The rest of the own-code tree stays own code');

  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]}' +
    '],"own_code_folders":["' + JsonPath('C:\DXComplyFolderTest\JVCL\Patches') + '"]}');
  AssertFolderMatch(LManifest, 'MyFix',
    'C:\DXComplyFolderTest\JVCL\Patches\MyFix.pas', mmOwnCode, -1,
    'A longer own-code folder inside a package stays own code');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\run\JvCore.pas', mmLibrary, 0,
    'The rest of the package stays with the component');
end;

procedure TComponentManifestTests.Match_ExactBeatsFolder;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]},' +
    '{"name":"Special","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_exact":["JvSpecial"]}' +
    ']}');
  AssertFolderMatch(LManifest, 'JvSpecial',
    'C:\DXComplyFolderTest\JVCL\JvSpecial.pas', mmLibrary, 1,
    'units_exact beats a folder on another row');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\JvCore.pas', mmLibrary, 0,
    'Other units in the folder stay with the folder row');
end;

procedure TComponentManifestTests.Match_OwnCodeUnitBeatsFolder;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]}' +
    '],"own_code_units":["JvPatch"]}');
  AssertFolderMatch(LManifest, 'JvPatch',
    'C:\DXComplyFolderTest\JVCL\JvPatch.pas', mmOwnCode, -1,
    'own_code_units beats a component folder');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\JvCore.pas', mmLibrary, 0,
    'The rest of the folder stays with the component');
end;

procedure TComponentManifestTests.Match_FolderBeatsPrefix;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"ByPrefix","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Jv"]},' +
    '{"name":"ByFolder","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\Other') + '"]}' +
    ']}');
  AssertFolderMatch(LManifest, 'JvFoo',
    'C:\DXComplyFolderTest\Other\JvFoo.pas', mmLibrary, 1,
    'A component folder beats a prefix, whatever the row order');

  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"ByPrefix","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["App"]}' +
    '],"own_code_folders":["' + JsonPath('C:\DXComplyFolderTest\src') + '"]}');
  AssertFolderMatch(LManifest, 'AppSettings',
    'C:\DXComplyFolderTest\src\AppSettings.pas', mmOwnCode, -1,
    'An own-code folder beats a library prefix');
end;

procedure TComponentManifestTests.Match_UnitsExclude_SkipsFolder;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"],' +
    '"units_prefix":["Jv"],"units_exclude":["JvSkip","Vcl.Skia"]},' +
    '{"name":"Skia","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Skia"]}' +
    ']}');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\JvCore.pas', mmLibrary, 0,
    'A unit that is not excluded stays in the folder');
  AssertFolderMatch(LManifest, 'JvSkip',
    'C:\DXComplyFolderTest\JVCL\JvSkip.pas', mmNone, -1,
    'units_exclude takes the unit out of that row''s folder and its prefix');
  AssertFolderMatch(LManifest, 'Vcl.Skia',
    'C:\DXComplyFolderTest\JVCL\Skia.pas', mmLibrary, 1,
    'An excluded scoped name leaves the unit for another row');
end;

procedure TComponentManifestTests.Match_Folder_NameOnly_DoesNotMatch;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"],' +
    '"units_prefix":["Jv"]}' +
    '],"own_code_folders":["' + JsonPath('C:\DXComplyFolderTest\src') + '"]}');
  AssertFolderMatch(LManifest, 'JvCore', '', mmLibrary, 0,
    'With no source path the prefix still matches and the folder does not');
  AssertFolderMatch(LManifest, 'Main', '', mmNone, -1,
    'An own-code folder does not match a unit known only by name');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\run\JvCore.pas', mmLibrary, 0,
    'The same unit matches the folder once a source path is known');
end;

procedure TComponentManifestTests.Match_Folder_IsCaseInsensitive;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["C:/DXComplyFolderTest/JVCL"]}]}');
  AssertFolderMatch(LManifest, 'JvCore',
    'c:\dxcomplyfoldertest\jvcl\run\JvCore.pas', mmLibrary, 0,
    'Folder matching ignores case and accepts either slash');
end;

procedure TComponentManifestTests.Match_FirstFolderRowWinsOnTie;
var
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"First","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]},' +
    '{"name":"Second","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]}' +
    '],"own_code_folders":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]}');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\JVCL\JvCore.pas', mmLibrary, 0,
    'On equal length the first component row wins, ahead of own code');
end;

procedure TComponentManifestTests.Parse_MissingFolder_WarnsAndStillApplies;
var
  LManifest: TComponentManifest;
  LError: string;
  I: Integer;
  LFound: Boolean;
  LDir, LFile: string;
begin
  Assert.IsTrue(TryParseComponentManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
    '"units_folder":["' + JsonPath('C:\DXComplyFolderTest\Missing') + '"]}]}',
    'test', LManifest, LError), LError);
  LFound := False;
  for I := 0 to High(LManifest.Warnings) do
    if (Pos('was not found', LManifest.Warnings[I]) > 0) and
      (Pos('still applied', LManifest.Warnings[I]) > 0) and
      (Pos('Missing', LManifest.Warnings[I]) > 0) then
      LFound := True;
  Assert.IsTrue(LFound, 'A missing folder must be a warning that says the rule is still applied');
  AssertFolderMatch(LManifest, 'JvCore',
    'C:\DXComplyFolderTest\Missing\JvCore.pas', mmLibrary, 0,
    'The missing folder is still applied');

  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-not-a-folder');
  TDirectory.CreateDirectory(LDir);
  LFile := TPath.Combine(LDir, 'note.txt');
  try
    TFile.WriteAllText(LFile, 'not a folder');
    Assert.IsTrue(TryParseComponentManifest(
      '{"match":{"prefixes":"legacy"},"components":[' +
      '{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1","type":"library",' +
      '"units_folder":["' + JsonPath(LFile) + '"]}]}',
      'test', LManifest, LError), LError);
    LFound := False;
    for I := 0 to High(LManifest.Warnings) do
      if Pos('is a file, not a folder', LManifest.Warnings[I]) > 0 then
        LFound := True;
    Assert.IsTrue(LFound, 'A file path must be reported as not a folder');
    AssertFolderMatch(LManifest, 'Note', LFile, mmNone, -1,
      'A file path is not applied as a folder');
  finally
    if TDirectory.Exists(LDir) then
      TDirectory.Delete(LDir, True);
  end;
end;

procedure TComponentManifestTests.Load_RelativeFolder_ResolvesAgainstManifestFile;
var
  LRoot, LManifestDir, LVendor, LSrc, LManifestPath: string;
  LUnitPath, LOwnPath, LJson, LError: string;
  LManifest, LAgain: TComponentManifest;
  I: Integer;
  LMissingNamed, LVendorMissing: Boolean;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'dxm-folders-' + TPath.GetRandomFileName);
  LManifestDir := TPath.Combine(LRoot, 'sbom');
  LVendor := TPath.Combine(LRoot, 'vendor', 'JVCL', 'run');
  LSrc := TPath.Combine(LRoot, 'src', 'App');
  TDirectory.CreateDirectory(LManifestDir);
  TDirectory.CreateDirectory(LVendor);
  TDirectory.CreateDirectory(LSrc);
  try
    LUnitPath := TPath.Combine(LVendor, 'JvCore.pas');
    LOwnPath := TPath.Combine(LSrc, 'Main.pas');
    TFile.WriteAllText(LUnitPath, 'unit JvCore;');
    TFile.WriteAllText(LOwnPath, 'unit Main;');
    LManifestPath := TPath.Combine(LManifestDir, 'components.json');
    TFile.WriteAllText(LManifestPath,
      '{"match":{"prefixes":"legacy"},"components":[{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1",' +
      '"type":"library","units_folder":["../vendor/JVCL"]}],' +
      '"own_code_folders":["../src","../missing-src"]}');

    Assert.IsTrue(TryLoadComponentManifest(LManifestPath, LManifest, LJson, LError), LError);
    LMissingNamed := False;
    LVendorMissing := False;
    for I := 0 to High(LManifest.Warnings) do
    begin
      if (Pos('missing-src', LManifest.Warnings[I]) > 0) and
        (Pos('was not found', LManifest.Warnings[I]) > 0) and
        (Pos('still applied', LManifest.Warnings[I]) > 0) then
        LMissingNamed := True;
      if (Pos('JVCL', LManifest.Warnings[I]) > 0) and
        (Pos('was not found', LManifest.Warnings[I]) > 0) then
        LVendorMissing := True;
    end;
    Assert.IsTrue(LMissingNamed, 'A relative folder that is missing must be named');
    Assert.IsFalse(LVendorMissing, 'A folder that exists must not be reported missing');
    AssertFolderMatch(LManifest, 'JvCore', LUnitPath, mmLibrary, 0,
      'A relative units_folder is resolved from the manifest file');
    AssertFolderMatch(LManifest, 'Main', LOwnPath, mmOwnCode, -1,
      'A relative own_code_folders entry is resolved from the manifest file');
    AssertFolderMatch(LManifest, 'JvOther',
      TPath.Combine(LRoot, 'vendor', 'JVCL2', 'JvOther.pas'), mmNone, -1,
      'The resolved folder does not include a sibling directory');

    // Writers parse the loaded text again, with no file path.
    Assert.IsTrue(TryParseComponentManifest(LJson, '', LAgain, LError), LError);
    AssertFolderMatch(LAgain, 'JvCore', LUnitPath, mmLibrary, 0,
      'The loaded text keeps the folder absolute for a later parse');
    AssertFolderMatch(LAgain, 'Main', LOwnPath, mmOwnCode, -1,
      'The loaded text keeps own-code folders absolute for a later parse');

    Assert.IsTrue(TryParseComponentManifest(
      '{"match":{"prefixes":"legacy"},"components":[{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1",' +
      '"type":"library","units_folder":["libs/JVCL"]}]}',
      'test', LManifest, LError), LError);
    LMissingNamed := False;
    for I := 0 to High(LManifest.Warnings) do
      if Pos('was not applied', LManifest.Warnings[I]) > 0 then
        LMissingNamed := True;
    Assert.IsTrue(LMissingNamed,
      'A relative folder is not applied when the manifest file location is unknown');
    AssertFolderMatch(LManifest, 'JvCore',
      TPath.Combine(TPath.GetTempPath, 'libs', 'JVCL', 'JvCore.pas'), mmNone, -1,
      'An unresolved relative folder does not match');
  finally
    if TDirectory.Exists(LRoot) then
      TDirectory.Delete(LRoot, True);
  end;
end;

procedure TComponentManifestTests.Parse_FolderOnlyRow_IsAMatchRule;
var
  LManifest: TComponentManifest;
  LError: string;
  I: Integer;
  LPlan: TManifestPlan;
  LWarnings: TArray<string>;
  LArtefacts: TArtefactList;
  LArtefact: TArtefactInfo;
begin
  Assert.IsTrue(TryParseComponentManifest(
    '{"match":{"prefixes":"legacy"},"components":[{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1",' +
    '"type":"library","units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]}]}',
    'test', LManifest, LError), LError);
  for I := 0 to High(LManifest.Warnings) do
    Assert.IsFalse(Pos('no units_prefix', LManifest.Warnings[I]) > 0,
      LManifest.Warnings[I]);

  LPlan := BuildManifestPlan(LManifest, FArtefacts);
  LWarnings := DormantComponentWarnings(LManifest, LPlan);
  Assert.AreEqual(NativeInt(1), NativeInt(Length(LWarnings)),
    'A folder row that matches nothing is reported');
  Assert.IsTrue(Pos('JVCL', LWarnings[0]) > 0, LWarnings[0]);

  LArtefacts := TArtefactList.Create;
  try
    LArtefact := Default(TArtefactInfo);
    LArtefact.ArtefactType := 'unit-evidence';
    LArtefact.RelativePath := 'JvCore.pas';
    LArtefact.FilePath := 'C:\DXComplyFolderTest\JVCL\run\JvCore.pas';
    LArtefacts.Add(LArtefact);
    LPlan := BuildManifestPlan(LManifest, LArtefacts);
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LPlan.Libraries)));
    Assert.AreEqual(0, LPlan.Libraries[0].ComponentIndex);
    LWarnings := DormantComponentWarnings(LManifest, LPlan);
    Assert.AreEqual(NativeInt(0), NativeInt(Length(LWarnings)),
      'A matched folder row is not dormant');
  finally
    LArtefacts.Free;
  end;
end;

procedure TComponentManifestTests.Plan_UsesSourcePathNotOutputDcu;
var
  LManifest: TComponentManifest;
  LPlan: TManifestPlan;
  LArtefact: TArtefactInfo;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[{"name":"JVCL","version":"1","vendor":"A","licence":"MPL-1.1",' +
    '"type":"library","units_folder":["' + JsonPath('C:\DXComplyFolderTest\JVCL') + '"]}]}');

  LArtefact := Default(TArtefactInfo);
  LArtefact.ArtefactType := 'unit-evidence';
  LArtefact.RelativePath := 'JvCore.dcu';
  LArtefact.FilePath := 'C:\DXComplyFolderTest\Project\Win32\Release\JvCore.dcu';
  LArtefact.SourcePath := 'C:\DXComplyFolderTest\JVCL\run\JvCore.pas';
  FArtefacts.Add(LArtefact);

  LArtefact := Default(TArtefactInfo);
  LArtefact.ArtefactType := 'unit-evidence';
  LArtefact.RelativePath := 'Other.dcu';
  LArtefact.FilePath := 'C:\DXComplyFolderTest\Project\Win32\Release\Other.dcu';
  FArtefacts.Add(LArtefact);

  LArtefact := Default(TArtefactInfo);
  LArtefact.ArtefactType := 'unit-evidence';
  LArtefact.RelativePath := 'OnlyPas.pas';
  LArtefact.FilePath := 'C:\DXComplyFolderTest\JVCL\OnlyPas.pas';
  FArtefacts.Add(LArtefact);

  LPlan := BuildManifestPlan(LManifest, FArtefacts);
  Assert.AreEqual(NativeInt(1), NativeInt(Length(LPlan.Libraries)));
  Assert.AreEqual(NativeInt(2), NativeInt(Length(LPlan.GroupedArtefactIndexes)),
    'The source path and a .pas file match. The output DCU with no source path does not');
  Assert.AreEqual(0, LPlan.GroupedArtefactIndexes[0]);
  Assert.AreEqual(2, LPlan.GroupedArtefactIndexes[1]);
end;

procedure TComponentManifestTests.Plan_UnitName_AndNameOnly_AssignedToFirstSharedPrefix;
var
  LManifest: TComponentManifest;
  LPlan: TManifestPlan;
  LArtefact: TArtefactInfo;
  LDormant: TArray<string>;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"TMS FNC Core","version":"4.2.3.7","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNC"]},' +
    '{"name":"TMS FNC UI Pack","version":"7.1.2.2","vendor":"TMS Software",' +
    '"licence":"LicenseRef-Proprietary","type":"library","units_prefix":["FMX.TMSFNC"]}' +
    ']}');

  LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := 'TMSFNCButton.dcu';
  LArtefact.UnitName := 'FMX.TMSFNCButton';
  LArtefact.ArtefactType := 'unit-evidence';
  LArtefact.Origin := 'Local project';
  FArtefacts.Add(LArtefact);

  Assert.IsTrue(TryAddNameOnlyLibraryUnit(LManifest, 'FMX.TMSFNCTypes',
    'Local project', 'MAP', 'Heuristic', FArtefacts));
  Assert.IsFalse(TryAddNameOnlyLibraryUnit(LManifest, 'FMX.TMSFNCTypes',
    'Local project', 'MAP', 'Heuristic', FArtefacts),
    'A unit that is already present is not added again');
  Assert.IsFalse(TryAddNameOnlyLibraryUnit(LManifest, 'System.SysUtils',
    'Embarcadero FMX', 'MAP', 'Heuristic', FArtefacts),
    'A name that matches no library row stays out of the SBOM');

  LPlan := BuildManifestPlan(LManifest, FArtefacts);
  Assert.AreEqual(NativeInt(1), NativeInt(Length(LPlan.Libraries)));
  Assert.AreEqual(0, LPlan.Libraries[0].ComponentIndex);
  Assert.AreEqual(NativeInt(2), NativeInt(Length(LPlan.GroupedArtefactIndexes)));

  LDormant := DormantComponentWarnings(LManifest, LPlan);
  Assert.AreEqual(NativeInt(1), NativeInt(Length(LDormant)));
  Assert.IsTrue(Pos('component "TMS FNC UI Pack" matched no units', LDormant[0]) > 0,
    LDormant[0]);
  Assert.AreEqual(0, Pos('TMS FNC Core', LDormant[0]));
end;

procedure TComponentManifestTests.Match_CorroboratedPrefix_RequiresADot_AndSkipsProductPath;
var
  LLegacy: TComponentManifest;
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
  LPrefix: string;
  LRow: string;
const
  cJson =
    '{"components":[' +
    '{"name":"Neslib","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Neslib"]},' +
    '{"name":"Neslib XML","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Neslib.Xml"]},' +
    '{"name":"Pack","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Adv","GDIP","FMX.TMSFNC"]}]}';
  cProduct = 'C:\DXProduct\source\rtl\win\Winapi.GDIPAPI.pas';
begin
  LManifest := ParseManifest(cJson);
  Assert.AreEqual(Ord(pmmCorroborated), Ord(LManifest.PrefixMode));
  Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LManifest, 'Neslib.Utils').Kind),
    'A prefix with no dot does not assign');
  LMatch := MatchManifestUnit(LManifest, 'Neslib.Xml.Reader');
  Assert.AreEqual(Ord(mmLibrary), Ord(LMatch.Kind));
  Assert.AreEqual(1, LMatch.ComponentIndex, 'The dotted prefix still wins');
  LMatch := MatchManifestUnit(LManifest, 'FMX.TMSFNCButton');
  Assert.AreEqual(2, LMatch.ComponentIndex, 'A dotted prefix assigns when there is no product path');
  Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LManifest, 'AdvGrid').Kind));

  LManifest.InstallRoot := 'C:\DXProduct';
  Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LManifest, 'Winapi.GDIPAPI', cProduct).Kind),
    'GDIP does not take a product RTL unit');
  Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LManifest, 'FMX.TMSFNCButton',
    'C:\DXProduct\source\fmx\FMX.TMSFNCButton.pas').Kind),
    'A dotted prefix does not reassign a product path');
  Assert.IsTrue(TryRejectedLibraryPrefix(LManifest, 'Winapi.GDIPAPI', cProduct, LPrefix, LRow));
  Assert.AreEqual('GDIP', LPrefix);
  Assert.AreEqual('Pack', LRow);
  Assert.IsTrue(Pos('kept origin Embarcadero RTL',
    RejectedPrefixLogLine('Winapi.GDIPAPI', LPrefix, LRow, 'Embarcadero RTL')) > 0);

  // units_exact and units_folder still assign on a product path.
  LManifest := ParseManifest(
    '{"components":[{"name":"Pack","version":"1","vendor":"A","licence":"MIT",' +
    '"type":"library","units_exact":["Winapi.GDIPAPI"],' +
    '"units_folder":["C:\\DXProduct\\source\\rtl"]}]}');
  LManifest.InstallRoot := 'C:\DXProduct';
  Assert.AreEqual(Ord(mmLibrary), Ord(MatchManifestUnit(LManifest, 'Winapi.GDIPAPI', cProduct).Kind),
    'units_exact still assigns on a product path');

  LLegacy := ParseManifest('{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"Pack","version":"1","vendor":"A","licence":"MIT","type":"library",' +
    '"units_prefix":["Adv"]}]}');
  Assert.AreEqual(Ord(pmmLegacy), Ord(LLegacy.PrefixMode));
  Assert.AreEqual(Ord(mmLibrary), Ord(MatchManifestUnit(LLegacy, 'AdvGrid').Kind),
    'legacy still assigns a prefix with no dot when there is no product path');
  LLegacy.InstallRoot := 'C:\DXProduct';
  Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LLegacy, 'AdvGrid',
    'C:\DXProduct\source\vcl\AdvGrid.pas').Kind),
    'legacy never reassigns a product path');
end;

procedure TComponentManifestTests.Parse_MatchPrefixes_Unknown_StaysCorroborated;
var
  I: Integer;
  LFound: Boolean;
  LManifest: TComponentManifest;
begin
  LManifest := ParseManifest(
    '{"match":{"prefixes":"strict"},"components":[{"name":"Pack","version":"1",' +
    '"vendor":"A","licence":"MIT","type":"library","units_prefix":["Adv"]}]}');
  Assert.AreEqual(Ord(pmmCorroborated), Ord(LManifest.PrefixMode));
  LFound := False;
  for I := 0 to High(LManifest.Warnings) do
    if Pos('match.prefixes "strict"', LManifest.Warnings[I]) > 0 then
      LFound := True;
  Assert.IsTrue(LFound, 'An unknown match.prefixes value must be reported');
  Assert.AreEqual(Ord(mmNone), Ord(MatchManifestUnit(LManifest, 'AdvGrid').Kind));
  LFound := False;
  for I := 0 to High(LManifest.Warnings) do
    if (Pos('prefix "Adv"', LManifest.Warnings[I]) > 0) and
      (Pos('has no dot', LManifest.Warnings[I]) > 0) and
      (Pos('not applied', LManifest.Warnings[I]) > 0) then
      LFound := True;
  Assert.IsTrue(LFound, 'A prefix with no dot must say it is not applied');
end;

initialization
  TDUnitX.RegisterTestFixture(TComponentManifestTests);

end.
