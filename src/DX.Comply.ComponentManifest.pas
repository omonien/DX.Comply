/// <summary>
/// DX.Comply.ComponentManifest
/// Loads a components.json manifest and matches units to libraries.
/// </summary>
///
/// <remarks>
/// The file format is the one published by DelphiSBOM (schema 1.0): one row
/// per library, matched by units_exact and units_prefix. Root supplier is the
/// application publisher. The per-component author is vendor.
///
/// Licence values are classified as an SPDX identifier, an SPDX expression,
/// or a plain name. Package URLs for manifest libraries use pkg:delphi, which
/// is not a registered PURL type. Scanned files keep the file: locator the
/// writers already emit. An optional purl field on a row replaces the
/// generated value.
///
/// Own-code units stay in the evidence. They are not dropped and they are
/// not attached to a third-party library.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.ComponentManifest;

interface

uses
  System.Classes,
  System.JSON,
  DX.Comply.DependencyGraph,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// How a licence value is written into CycloneDX and SPDX.
  /// </summary>
  TLicenceKind = (
    /// <summary>No licence text.</summary>
    lkNone,
    /// <summary>A recognised SPDX identifier. Emitted as license.id.</summary>
    lkSpdxId,
    /// <summary>An SPDX expression (OR, AND, or WITH). Emitted as expression.</summary>
    lkExpression,
    /// <summary>Any other text, such as Commercial. Emitted as license.name.</summary>
    lkName
  );

  /// <summary>
  /// Result of matching one unit name against the manifest.
  /// </summary>
  TManifestMatchKind = (
    /// <summary>No rule matched.</summary>
    mmNone,
    /// <summary>A library row matched.</summary>
    mmLibrary,
    /// <summary>The unit is the project's own code.</summary>
    mmOwnCode
  );

  /// <summary>
  /// One library row from components.json.
  /// </summary>
  TComponentEntry = record
    /// <summary>Library display name.</summary>
    Name: string;
    /// <summary>Version string.</summary>
    Version: string;
    /// <summary>Author or vendor. Written as supplier and author.</summary>
    Vendor: string;
    /// <summary>Optional home page or repository URL.</summary>
    VendorUrl: string;
    /// <summary>SPDX id, SPDX expression, or a plain name.</summary>
    Licence: string;
    /// <summary>Optional URL of the licence text. Omitted for expressions.</summary>
    LicenceUrl: string;
    /// <summary>Optional purl. When empty, pkg:delphi/name@version is generated.</summary>
    Purl: string;
    /// <summary>CycloneDX component type: library, framework, or application.</summary>
    ComponentType: string;
    /// <summary>Case-insensitive unit name prefixes.</summary>
    Prefixes: TArray<string>;
    /// <summary>Case-insensitive exact unit names.</summary>
    ExactUnits: TArray<string>;
    /// <summary>Freeform notes. Not written into the SBOM.</summary>
    Notes: string;
  end;

  /// <summary>
  /// A parsed components.json file.
  /// </summary>
  TComponentManifest = record
    /// <summary>True when parsing succeeded.</summary>
    Loaded: Boolean;
    /// <summary>schema_version, when present.</summary>
    SchemaVersion: string;
    /// <summary>last_updated, when present.</summary>
    LastUpdated: string;
    /// <summary>Application publisher name (root supplier).</summary>
    SupplierName: string;
    /// <summary>Application publisher URL.</summary>
    SupplierUrl: string;
    /// <summary>Library rows, in file order.</summary>
    Components: TArray<TComponentEntry>;
    /// <summary>Exact unit names that are the project's own code.</summary>
    OwnCodeUnits: TArray<string>;
    /// <summary>Unit name prefixes that are the project's own code.</summary>
    OwnCodePrefixes: TArray<string>;
    /// <summary>Non-fatal schema notes. Fatal problems are returned separately.</summary>
    Warnings: TArray<string>;
    /// <summary>Path or label the text was loaded from.</summary>
    SourcePath: string;
  end;

  /// <summary>
  /// Match of one unit name.
  /// </summary>
  TManifestMatch = record
    /// <summary>Which kind of rule matched.</summary>
    Kind: TManifestMatchKind;
    /// <summary>Index into TComponentManifest.Components, or -1.</summary>
    ComponentIndex: Integer;
  end;

  /// <summary>
  /// One library that has at least one matched unit.
  /// </summary>
  TManifestLibraryPlan = record
    /// <summary>Index into the manifest component array.</summary>
    ComponentIndex: Integer;
    /// <summary>CycloneDX bom-ref for the library.</summary>
    BomRef: string;
    /// <summary>SPDXID for the library package.</summary>
    SpdxId: string;
    /// <summary>bom-ref values of the matched unit components.</summary>
    UnitBomRefs: TArray<string>;
    /// <summary>SPDX package ids of the matched unit components.</summary>
    UnitSpdxIds: TArray<string>;
  end;

  /// <summary>
  /// How unit-evidence artefacts map onto library rows.
  /// </summary>
  TManifestPlan = record
    /// <summary>True when at least one library has a matched unit.</summary>
    Active: Boolean;
    /// <summary>Libraries that matched, in manifest order.</summary>
    Libraries: TArray<TManifestLibraryPlan>;
    /// <summary>Artefact indexes that belong to a library.</summary>
    GroupedArtefactIndexes: TArray<Integer>;
  end;

/// <summary>
/// Strips one known Delphi scope prefix (System., Vcl., and the rest).
/// The original name is returned when nothing matches.
/// </summary>
function StripDelphiScopePrefix(const AUnitName: string): string;

/// <summary>
/// Classifies a licence value. Recognised SPDX ids are returned in canonical case.
/// </summary>
function ClassifyLicence(const AValue: string; out ANormalised: string): TLicenceKind;

/// <summary>
/// Percent-encodes one purl segment. Unreserved characters are kept.
/// A space becomes %20.
/// </summary>
function PurlEncode(const AValue: string): string;

/// <summary>
/// Builds pkg:delphi/name@version. A non-empty override is returned unchanged.
/// pkg:delphi is not a registered PURL type.
/// </summary>
function BuildDelphiPurl(const AName, AVersion, AOverride: string): string;

/// <summary>
/// Parses manifest JSON. AError is set when the text is not usable.
/// Schema gaps are warnings on a successfully loaded manifest.
/// </summary>
function TryParseComponentManifest(const AJson, ASourceName: string;
  out AManifest: TComponentManifest; out AError: string): Boolean;

/// <summary>
/// Loads a manifest file. AJson receives the file text on success.
/// </summary>
function TryLoadComponentManifest(const AFilePath: string;
  out AManifest: TComponentManifest; out AJson, AError: string): Boolean;

/// <summary>
/// Reads the manifest key from a .dxcomply.json file.
/// A missing file or a missing key yields an empty path and True.
/// Invalid JSON or a non-string key yields False and AError.
/// </summary>
function TryReadConfigManifest(const AConfigPath: string;
  out AManifestPath, AError: string): Boolean;

/// <summary>
/// Resolves a relative manifest path against the project directory.
/// </summary>
function ResolveManifestPath(const AProjectDir, AManifestFile: string): string;

/// <summary>
/// Matches one unit name. Exact rules beat prefix rules. The first row wins.
/// The name is tried as written and with its scope prefix removed.
/// own_code_units beats prefix rules. A units_exact hit beats own_code_units.
/// </summary>
function MatchManifestUnit(const AManifest: TComponentManifest;
  const AUnitName: string): TManifestMatch;

/// <summary>
/// Groups unit-evidence artefacts that match a library row.
/// </summary>
function BuildManifestPlan(const AManifest: TComponentManifest;
  const AArtefacts: TArtefactList): TManifestPlan;

/// <summary>
/// Names of library rows that had match rules but no unit.
/// </summary>
function DormantComponentWarnings(const AManifest: TComponentManifest;
  const APlan: TManifestPlan): TArray<string>;

/// <summary>
/// Copies the manifest publisher onto metadata when supplier is still empty.
/// An explicit supplier (CLI or product.supplier) is left as it is.
/// </summary>
procedure ApplyManifestPublisher(const AManifest: TComponentManifest;
  var AMetadata: TSbomMetadata);

/// <summary>
/// Appends library components and rewrites the dependency graph.
/// The program that was built depends on each library. Each library
/// depends on the units it matched. Does nothing when the JSON is empty.
/// </summary>
procedure ApplyManifestCycloneDxJson(const AManifestJson: string;
  const AArtefacts: TArtefactList; AComponents, ADependencies: TJSONArray;
  const AProjectBomRef: string);

/// <summary>
/// Appends CycloneDX 1.6 library elements. Child order follows bom-1.6.xsd.
/// </summary>
procedure AppendManifestLibrariesXml(ALines: TStrings; const AManifestJson: string;
  const AArtefacts: TArtefactList; AIndentLevel: Integer);

/// <summary>
/// Writes the dependencies element. The project depends on the program
/// that was built. That program depends on each library and on components
/// the manifest did not group. Each library depends on its matched units.
/// </summary>
procedure AppendManifestDependenciesXml(ALines: TStrings; const AManifestJson: string;
  const AArtefacts: TArtefactList; const AProjectBomRef: string;
  AIndentLevel: Integer; const AUsesGraph: TUsesDependencyGraph);

/// <summary>
/// bom-ref values of manifest libraries that matched at least one unit.
/// Those libraries are a complete declaration: dependsOn is exactly the
/// matched units. Empty when the manifest is inactive.
/// </summary>
function ManifestLibraryBomRefs(const AManifestJson: string;
  const AArtefacts: TArtefactList): TArray<string>;

/// <summary>
/// Appends SPDX 2.3 packages, relationships, and extracted licence names.
/// Unit edges use APackageIds so they match the packages in the document.
/// </summary>
procedure ApplyManifestSpdx(const AManifestJson: string;
  const AArtefacts: TArtefactList; APackages, ARelationships: TJSONArray;
  const APackageIds: TArray<string>; const ADocumentSpdxId: string;
  ARoot: TJSONObject);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  System.Hash;

const
  cScopePrefixes: array[0..14] of string = (
    'System.',
    'Vcl.',
    'Winapi.',
    'Data.',
    'Xml.',
    'Datasnap.',
    'FMX.',
    'REST.',
    'Net.',
    'Web.',
    'Soap.',
    'Bde.',
    'IBX.',
    'FireDAC.',
    'Posix.'
  );

  /// <summary>
  /// Practical SPDX identifier subset used by DelphiSBOM, so the same licence
  /// strings classify the same way. Anything else becomes a name.
  /// </summary>
  cKnownSpdxIds: array[0..71] of string = (
    '0BSD', 'AFL-3.0', 'AGPL-3.0', 'AGPL-3.0-only', 'AGPL-3.0-or-later',
    'Apache-1.1', 'Apache-2.0', 'Artistic-2.0', 'BSD-1-Clause', 'BSD-2-Clause',
    'BSD-3-Clause', 'BSD-3-Clause-Clear', 'BSD-4-Clause', 'BSL-1.0', 'CC-BY-3.0',
    'CC-BY-4.0', 'CC-BY-SA-4.0', 'CC0-1.0', 'CDDL-1.0', 'CDDL-1.1', 'CPL-1.0',
    'curl', 'ECL-2.0', 'EPL-1.0', 'EPL-2.0', 'EUPL-1.1', 'EUPL-1.2', 'GPL-1.0',
    'GPL-2.0', 'GPL-2.0+', 'GPL-2.0-only', 'GPL-2.0-or-later', 'GPL-3.0',
    'GPL-3.0+', 'GPL-3.0-only', 'GPL-3.0-or-later', 'ICU', 'IJG', 'ISC', 'JSON',
    'LGPL-2.0', 'LGPL-2.0+', 'LGPL-2.0-only', 'LGPL-2.0-or-later', 'LGPL-2.1',
    'LGPL-2.1+', 'LGPL-2.1-only', 'LGPL-2.1-or-later', 'LGPL-3.0', 'LGPL-3.0+',
    'LGPL-3.0-only', 'LGPL-3.0-or-later', 'Libpng', 'MIT', 'MIT-0', 'MPL-1.0',
    'MPL-1.1', 'MPL-2.0', 'MPL-2.0-no-copyleft-exception', 'MS-PL', 'MS-RL',
    'NCSA', 'OpenSSL', 'PostgreSQL', 'Python-2.0', 'Unicode-DFS-2016',
    'Unlicense', 'UPL-1.0', 'W3C', 'WTFPL', 'X11', 'Zlib'
  );

  cMinPrefixLength = 3;

function StripDelphiScopePrefix(const AUnitName: string): string;
var
  I: Integer;
begin
  for I := Low(cScopePrefixes) to High(cScopePrefixes) do
    if AUnitName.StartsWith(cScopePrefixes[I], True) then
    begin
      Result := AUnitName.Substring(cScopePrefixes[I].Length);
      if Result = '' then
        Result := AUnitName;
      Exit;
    end;
  Result := AUnitName;
end;

function ClassifyLicence(const AValue: string; out ANormalised: string): TLicenceKind;
var
  I: Integer;
  LPadded: string;
begin
  ANormalised := Trim(AValue);
  if ANormalised = '' then
    Exit(lkNone);

  for I := Low(cKnownSpdxIds) to High(cKnownSpdxIds) do
    if SameText(ANormalised, cKnownSpdxIds[I]) then
    begin
      ANormalised := cKnownSpdxIds[I];
      Exit(lkSpdxId);
    end;

  LPadded := ' ' + UpperCase(ANormalised) + ' ';
  if LPadded.Contains(' OR ') or LPadded.Contains(' AND ') or LPadded.Contains(' WITH ') then
    Exit(lkExpression);

  Result := lkName;
end;

function PurlEncode(const AValue: string): string;
var
  LBytes: TBytes;
  I: Integer;
  LBuilder: TStringBuilder;
begin
  LBuilder := TStringBuilder.Create;
  try
    LBytes := TEncoding.UTF8.GetBytes(AValue);
    for I := 0 to High(LBytes) do
      if (LBytes[I] < 128) and CharInSet(Chr(LBytes[I]),
        ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_', '~']) then
        LBuilder.Append(Chr(LBytes[I]))
      else
        LBuilder.Append('%').Append(IntToHex(Integer(LBytes[I]), 2));
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function BuildDelphiPurl(const AName, AVersion, AOverride: string): string;
var
  LName, LVersion: string;
begin
  if Trim(AOverride) <> '' then
    Exit(Trim(AOverride));

  LName := Trim(AName);
  if LName = '' then
    Exit('');

  LVersion := Trim(AVersion);
  Result := 'pkg:delphi/' + PurlEncode(LName);
  if LVersion <> '' then
    Result := Result + '@' + PurlEncode(LVersion);
end;

function SanitizeSpdxId(const AValue: string): string;
var
  I: Integer;
  LChar: Char;
begin
  // Same character set as TSpdxJsonWriter.SanitizeSpdxId. Package ids for
  // manifest libraries have to line up with the ids that writer emits.
  Result := '';
  for I := 1 to Length(AValue) do
  begin
    LChar := AValue[I];
    if CharInSet(LChar, ['a'..'z', 'A'..'Z', '0'..'9', '.', '-']) then
      Result := Result + LChar
    else
      Result := Result + '-';
  end;
end;

function SpdxPackageIdForRelativePath(const ARelativePath: string): string;
var
  LPath: string;
  LSanitized: string;
  LHash: string;
  LBytes: TBytes;
  LSha: THashSHA1;
begin
  // Same path hash as TSpdxJsonWriter.BuildPackageSpdxId. The writer still
  // passes its package ids, which add a suffix when two paths collide.
  LPath := StringReplace(Trim(ARelativePath), '\', '/', [rfReplaceAll]);
  if LPath = '' then
    LPath := 'unknown';
  LSanitized := SanitizeSpdxId(LPath);
  if LSanitized = '' then
    LSanitized := 'unknown';
  LBytes := TEncoding.UTF8.GetBytes(LPath);
  LSha := THashSHA1.Create;
  if Length(LBytes) > 0 then
    LSha.Update(LBytes, Length(LBytes));
  LHash := Copy(LowerCase(LSha.HashAsString), 1, 8);
  Result := 'SPDXRef-Package-' + LSanitized + '-' + LHash;
end;

function ManifestSpdxId(const AName: string; AIndex: Integer): string;
var
  LSafe: string;
begin
  LSafe := SanitizeSpdxId(AName);
  if LSafe = '' then
    Result := 'SPDXRef-Package-Manifest-' + IntToStr(AIndex)
  else
    Result := 'SPDXRef-Package-Manifest-' + IntToStr(AIndex) + '-' + LSafe;
end;

function ComponentDisplayName(const AEntry: TComponentEntry; AIndex: Integer): string;
begin
  Result := Trim(AEntry.Name);
  if Result = '' then
    Result := 'component-' + IntToStr(AIndex);
end;

function ArtefactUnitName(const AArtefact: TArtefactInfo): string;
begin
  Result := '';
  if not SameText(AArtefact.ArtefactType, 'unit-evidence') then
    Exit;
  Result := TPath.GetFileNameWithoutExtension(AArtefact.RelativePath);
  if Result = '' then
    Result := TPath.GetFileNameWithoutExtension(AArtefact.FilePath);
end;

function EscapeXml(const AValue: string): string;
begin
  Result := AValue;
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

type
  TJsonTextStatus = (jtsMissing, jtsValue, jtsWrongType);

function ReadJsonText(AObject: TJSONObject; const AName: string;
  out AText: string): TJsonTextStatus;
var
  LValue: TJSONValue;
begin
  AText := '';
  LValue := AObject.GetValue(AName);
  if (LValue = nil) or (LValue is TJSONNull) then
    Exit(jtsMissing);
  if (LValue is TJSONString) or (LValue is TJSONNumber) or (LValue is TJSONBool) then
  begin
    AText := Trim(LValue.Value);
    Exit(jtsValue);
  end;
  Result := jtsWrongType;
end;

procedure AddWarning(AWarnings: TList<string>; const AMessage: string);
begin
  if Assigned(AWarnings) then
    AWarnings.Add(AMessage);
end;

function ReadStringArray(AObject: TJSONObject; const AName, AContext: string;
  AWarnings: TList<string>): TArray<string>;
var
  LValue: TJSONValue;
  LArray: TJSONArray;
  LList: TList<string>;
  I: Integer;
  LItem: string;
begin
  Result := nil;
  LValue := AObject.GetValue(AName);
  if (LValue = nil) or (LValue is TJSONNull) then
    Exit;
  if not (LValue is TJSONArray) then
  begin
    AddWarning(AWarnings, AContext + ': "' + AName + '" should be an array and was ignored');
    Exit;
  end;

  LArray := TJSONArray(LValue);
  LList := TList<string>.Create;
  try
    for I := 0 to LArray.Count - 1 do
    begin
      if (LArray.Items[I] is TJSONString) or (LArray.Items[I] is TJSONNumber) then
      begin
        LItem := Trim(LArray.Items[I].Value);
        if LItem = '' then
          AddWarning(AWarnings, AContext + ': skipping an empty entry in "' + AName + '"')
        else
          LList.Add(LItem);
      end
      else
        AddWarning(AWarnings, AContext + ': skipping a non-string entry in "' + AName + '"');
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function NormaliseComponentType(const AType: string): string;
begin
  Result := LowerCase(Trim(AType));
  if (Result <> 'library') and (Result <> 'framework') and (Result <> 'application') then
    Result := 'library';
end;

function ReadComponent(AObject: TJSONObject; AIndex: Integer;
  AWarnings: TList<string>): TComponentEntry;
var
  LContext: string;
  LStatus: TJsonTextStatus;
  LText: string;
  LKind: TLicenceKind;
  LNormalised: string;
  I: Integer;
begin
  Result := Default(TComponentEntry);
  Result.ComponentType := 'library';
  LContext := Format('Component[%d]', [AIndex]);

  LStatus := ReadJsonText(AObject, 'name', Result.Name);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "name" should be a string and was ignored');
  if Result.Name <> '' then
    LContext := Format('Component[%d] "%s"', [AIndex, Result.Name]);

  if Result.Name = '' then
    AddWarning(AWarnings, LContext + ': missing name');

  LStatus := ReadJsonText(AObject, 'version', Result.Version);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "version" should be a string and was ignored');
  if Result.Version = '' then
    AddWarning(AWarnings, LContext + ': missing version');

  LStatus := ReadJsonText(AObject, 'vendor', Result.Vendor);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "vendor" should be a string and was ignored');
  if Result.Vendor = '' then
    AddWarning(AWarnings, LContext + ': missing vendor');

  LStatus := ReadJsonText(AObject, 'vendor_url', Result.VendorUrl);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "vendor_url" should be a string and was ignored');

  LStatus := ReadJsonText(AObject, 'licence', Result.Licence);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "licence" should be a string and was ignored')
  else if Result.Licence = '' then
  begin
    // British spelling is the format. "license" is accepted as an alias.
    LStatus := ReadJsonText(AObject, 'license', LText);
    if LStatus = jtsValue then
      Result.Licence := LText
    else if LStatus = jtsWrongType then
      AddWarning(AWarnings, LContext + ': "license" should be a string and was ignored');
  end;

  LStatus := ReadJsonText(AObject, 'licence_url', Result.LicenceUrl);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "licence_url" should be a string and was ignored');
  if (LStatus = jtsMissing) or (Result.LicenceUrl = '') then
  begin
    LStatus := ReadJsonText(AObject, 'license_url', LText);
    if LStatus = jtsValue then
      Result.LicenceUrl := LText
    else if LStatus = jtsWrongType then
      AddWarning(AWarnings, LContext + ': "license_url" should be a string and was ignored');
  end;

  if Result.Licence = '' then
    AddWarning(AWarnings, LContext + ': missing licence')
  else
  begin
    LKind := ClassifyLicence(Result.Licence, LNormalised);
    if (LKind = lkName) and not SameText(Result.Licence, 'Commercial') then
      AddWarning(AWarnings, LContext + ': licence "' + Result.Licence +
        '" is not a recognised SPDX identifier and will be written as a licence name');
  end;

  LStatus := ReadJsonText(AObject, 'purl', Result.Purl);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "purl" should be a string and was ignored');

  LStatus := ReadJsonText(AObject, 'type', LText);
  if LStatus = jtsMissing then
    AddWarning(AWarnings, LContext + ': missing type; library will be used')
  else if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "type" should be a string; library will be used')
  else if (LowerCase(LText) <> 'library') and (LowerCase(LText) <> 'framework') and
    (LowerCase(LText) <> 'application') then
    AddWarning(AWarnings, LContext + ': type "' + LText +
      '" is not library, framework, or application; library will be used');
  if LStatus = jtsValue then
    Result.ComponentType := NormaliseComponentType(LText);

  LStatus := ReadJsonText(AObject, 'notes', Result.Notes);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "notes" should be a string and was ignored');

  Result.Prefixes := ReadStringArray(AObject, 'units_prefix', LContext, AWarnings);
  Result.ExactUnits := ReadStringArray(AObject, 'units_exact', LContext, AWarnings);

  if (Length(Result.Prefixes) = 0) and (Length(Result.ExactUnits) = 0) then
    AddWarning(AWarnings, LContext +
      ': no units_prefix or units_exact; this row will not match any unit');

  for I := 0 to High(Result.Prefixes) do
    if Length(Result.Prefixes[I]) < cMinPrefixLength then
      AddWarning(AWarnings, LContext + ': prefix "' + Result.Prefixes[I] +
        '" is shorter than 3 characters');
end;

procedure ReadComponents(AArray: TJSONArray; AWarnings: TList<string>;
  var AManifest: TComponentManifest);
var
  LList: TList<TComponentEntry>;
  I: Integer;
begin
  LList := TList<TComponentEntry>.Create;
  try
    if Assigned(AArray) then
      for I := 0 to AArray.Count - 1 do
      begin
        if not (AArray.Items[I] is TJSONObject) then
        begin
          AddWarning(AWarnings, Format('Component[%d] is not an object and was skipped', [I]));
          Continue;
        end;
        LList.Add(ReadComponent(TJSONObject(AArray.Items[I]), I, AWarnings));
      end;
    AManifest.Components := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function IsIsoDate(const AValue: string): Boolean;
begin
  Result := TRegEx.IsMatch(AValue, '^\d{4}-\d{2}-\d{2}$');
end;

function ReadRootObject(ARoot: TJSONObject; AWarnings: TList<string>;
  var AManifest: TComponentManifest): Boolean;
var
  LStatus: TJsonTextStatus;
  LSupplier: TJSONValue;
  LComponents: TJSONValue;
  I: Integer;
begin
  Result := True;
  LStatus := ReadJsonText(ARoot, 'schema_version', AManifest.SchemaVersion);
  if LStatus = jtsMissing then
    AddWarning(AWarnings, 'Missing schema_version (expected "1.0")')
  else if LStatus = jtsWrongType then
    AddWarning(AWarnings, 'schema_version should be a string; reading the file as 1.0')
  else if AManifest.SchemaVersion <> '1.0' then
    AddWarning(AWarnings, 'schema_version "' + AManifest.SchemaVersion +
      '" is not supported (expected "1.0"); reading the file as 1.0');

  LStatus := ReadJsonText(ARoot, 'last_updated', AManifest.LastUpdated);
  if LStatus = jtsMissing then
    AddWarning(AWarnings, 'Missing last_updated')
  else if (LStatus = jtsValue) and not IsIsoDate(AManifest.LastUpdated) then
    AddWarning(AWarnings, 'last_updated "' + AManifest.LastUpdated +
      '" is not YYYY-MM-DD');

  LSupplier := ARoot.GetValue('supplier');
  if LSupplier = nil then
    AddWarning(AWarnings, 'Missing supplier object')
  else if not (LSupplier is TJSONObject) then
    AddWarning(AWarnings, 'supplier should be an object and was ignored')
  else
  begin
    ReadJsonText(TJSONObject(LSupplier), 'name', AManifest.SupplierName);
    ReadJsonText(TJSONObject(LSupplier), 'url', AManifest.SupplierUrl);
    if AManifest.SupplierName = '' then
      AddWarning(AWarnings, 'Supplier name is empty');
  end;

  LComponents := ARoot.GetValue('components');
  if LComponents = nil then
    AddWarning(AWarnings, 'No components array in the manifest')
  else if not (LComponents is TJSONArray) then
    AddWarning(AWarnings, 'components should be an array and was ignored')
  else
    ReadComponents(TJSONArray(LComponents), AWarnings, AManifest);

  AManifest.OwnCodeUnits := ReadStringArray(ARoot, 'own_code_units', 'Manifest', AWarnings);
  AManifest.OwnCodePrefixes := ReadStringArray(ARoot, 'own_code_prefixes', 'Manifest', AWarnings);
  for I := 0 to High(AManifest.OwnCodePrefixes) do
    if Length(AManifest.OwnCodePrefixes[I]) < cMinPrefixLength then
      AddWarning(AWarnings, 'own_code_prefixes: prefix "' + AManifest.OwnCodePrefixes[I] +
        '" is shorter than 3 characters');
end;

function ParseComponentManifest(const AJson, ASourceName: string;
  out AManifest: TComponentManifest; out AError: string): Boolean;
var
  LValue: TJSONValue;
  LWarnings: TList<string>;
begin
  AManifest := Default(TComponentManifest);
  AError := '';
  Result := False;
  if Trim(AJson) = '' then
  begin
    AError := 'Invalid JSON';
    Exit;
  end;

  LValue := TJSONObject.ParseJSONValue(AJson);
  if LValue = nil then
  begin
    AError := 'Invalid JSON';
    Exit;
  end;

  LWarnings := TList<string>.Create;
  try
    try
      if LValue is TJSONArray then
      begin
        AddWarning(LWarnings, 'Manifest root is a JSON array; reading it as the components list');
        ReadComponents(TJSONArray(LValue), LWarnings, AManifest);
        Result := True;
      end
      else if LValue is TJSONObject then
        Result := ReadRootObject(TJSONObject(LValue), LWarnings, AManifest)
      else
        AError := 'Manifest root must be a JSON object or an array of components';
    finally
      LValue.Free;
    end;

    if Result then
    begin
      AManifest.Loaded := True;
      AManifest.Warnings := LWarnings.ToArray;
      AManifest.SourcePath := ASourceName;
    end
    else if AError = '' then
      AError := 'The manifest could not be read';
  finally
    LWarnings.Free;
  end;
end;

function TryParseComponentManifest(const AJson, ASourceName: string;
  out AManifest: TComponentManifest; out AError: string): Boolean;
begin
  AManifest := Default(TComponentManifest);
  AError := '';
  Result := False;
  try
    Result := ParseComponentManifest(AJson, ASourceName, AManifest, AError);
  except
    on E: Exception do
    begin
      AManifest := Default(TComponentManifest);
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function TryLoadComponentManifest(const AFilePath: string;
  out AManifest: TComponentManifest; out AJson, AError: string): Boolean;
var
  LContent: TStringList;
begin
  AManifest := Default(TComponentManifest);
  AJson := '';
  AError := '';
  Result := False;

  if Trim(AFilePath) = '' then
  begin
    AError := 'Path is empty';
    Exit;
  end;
  if not TFile.Exists(AFilePath) then
  begin
    AError := 'File not found';
    Exit;
  end;

  LContent := TStringList.Create;
  try
    try
      LContent.LoadFromFile(AFilePath, TEncoding.UTF8);
      AJson := LContent.Text;
    except
      on E: Exception do
      begin
        AError := E.Message;
        Exit;
      end;
    end;
  finally
    LContent.Free;
  end;

  Result := TryParseComponentManifest(AJson, AFilePath, AManifest, AError);
end;

function TryReadConfigManifest(const AConfigPath: string;
  out AManifestPath, AError: string): Boolean;
var
  LContent: TStringList;
  LValue: TJSONValue;
  LKey: TJSONValue;
begin
  AManifestPath := '';
  AError := '';
  Result := True;
  if not TFile.Exists(AConfigPath) then
    Exit;

  LContent := TStringList.Create;
  try
    try
      LContent.LoadFromFile(AConfigPath, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        AError := E.Message;
        Exit(False);
      end;
    end;

    LValue := TJSONObject.ParseJSONValue(LContent.Text);
  finally
    LContent.Free;
  end;

  if LValue = nil then
  begin
    AError := 'Invalid JSON';
    Exit(False);
  end;

  try
    if not (LValue is TJSONObject) then
    begin
      AError := 'Config root must be a JSON object';
      Exit(False);
    end;

    LKey := TJSONObject(LValue).GetValue('manifest');
    if (LKey = nil) or (LKey is TJSONNull) then
      Exit(True);
    if not ((LKey is TJSONString) or (LKey is TJSONNumber)) then
    begin
      AError := 'manifest must be a string';
      Exit(False);
    end;
    AManifestPath := Trim(LKey.Value);
    Result := True;
  finally
    LValue.Free;
  end;
end;

function ResolveManifestPath(const AProjectDir, AManifestFile: string): string;
begin
  Result := Trim(AManifestFile);
  if Result = '' then
    Exit;
  if TPath.IsRelativePath(Result) then
    Result := TPath.Combine(AProjectDir, Result);
end;

function FindExact(const AManifest: TComponentManifest; const AUnitName: string): Integer;
var
  I, J: Integer;
begin
  Result := -1;
  for I := 0 to High(AManifest.Components) do
    for J := 0 to High(AManifest.Components[I].ExactUnits) do
      if SameText(AUnitName, AManifest.Components[I].ExactUnits[J]) then
        Exit(I);
end;

function FindPrefix(const AManifest: TComponentManifest; const AUnitName: string): Integer;
var
  I, J: Integer;
  LLower: string;
begin
  Result := -1;
  LLower := LowerCase(AUnitName);
  for I := 0 to High(AManifest.Components) do
    for J := 0 to High(AManifest.Components[I].Prefixes) do
      if (AManifest.Components[I].Prefixes[J] <> '') and
        LLower.StartsWith(LowerCase(AManifest.Components[I].Prefixes[J])) then
        Exit(I);
end;

function IsListedOwnCode(const AManifest: TComponentManifest; const AUnitName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(AManifest.OwnCodeUnits) do
    if SameText(AUnitName, AManifest.OwnCodeUnits[I]) then
      Exit(True);
end;

function IsOwnCodePrefix(const AManifest: TComponentManifest; const AUnitName: string): Boolean;
var
  I: Integer;
  LLower: string;
begin
  Result := False;
  LLower := LowerCase(AUnitName);
  for I := 0 to High(AManifest.OwnCodePrefixes) do
    if (AManifest.OwnCodePrefixes[I] <> '') and
      LLower.StartsWith(LowerCase(AManifest.OwnCodePrefixes[I])) then
      Exit(True);
end;

function MatchManifestUnit(const AManifest: TComponentManifest;
  const AUnitName: string): TManifestMatch;
var
  LStripped: string;
  LIndex: Integer;
begin
  Result.Kind := mmNone;
  Result.ComponentIndex := -1;
  if not AManifest.Loaded then
    Exit;
  if Trim(AUnitName) = '' then
    Exit;

  LStripped := StripDelphiScopePrefix(AUnitName);

  LIndex := FindExact(AManifest, AUnitName);
  if (LIndex < 0) and not SameText(LStripped, AUnitName) then
    LIndex := FindExact(AManifest, LStripped);
  if LIndex >= 0 then
  begin
    Result.Kind := mmLibrary;
    Result.ComponentIndex := LIndex;
    Exit;
  end;

  if IsListedOwnCode(AManifest, AUnitName) or
    ((not SameText(LStripped, AUnitName)) and IsListedOwnCode(AManifest, LStripped)) then
  begin
    Result.Kind := mmOwnCode;
    Exit;
  end;

  LIndex := FindPrefix(AManifest, AUnitName);
  if (LIndex < 0) and not SameText(LStripped, AUnitName) then
    LIndex := FindPrefix(AManifest, LStripped);
  if LIndex >= 0 then
  begin
    Result.Kind := mmLibrary;
    Result.ComponentIndex := LIndex;
    Exit;
  end;

  if IsOwnCodePrefix(AManifest, AUnitName) or
    ((not SameText(LStripped, AUnitName)) and IsOwnCodePrefix(AManifest, LStripped)) then
    Result.Kind := mmOwnCode;
end;

function BuildManifestPlan(const AManifest: TComponentManifest;
  const AArtefacts: TArtefactList): TManifestPlan;
var
  LGroups: TList<TManifestLibraryPlan>;
  LGrouped: TList<Integer>;
  LPlan: TManifestLibraryPlan;
  LMatch: TManifestMatch;
  LUnitName: string;
  I, J, LLib: Integer;
  LFound: Boolean;
begin
  Result := Default(TManifestPlan);
  if not AManifest.Loaded or not Assigned(AArtefacts) then
    Exit;

  LGroups := TList<TManifestLibraryPlan>.Create;
  LGrouped := TList<Integer>.Create;
  try
    for I := 0 to AArtefacts.Count - 1 do
    begin
      LUnitName := ArtefactUnitName(AArtefacts[I]);
      if LUnitName = '' then
        Continue;

      LMatch := MatchManifestUnit(AManifest, LUnitName);
      if LMatch.Kind <> mmLibrary then
        Continue;

      LFound := False;
      LLib := -1;
      for J := 0 to LGroups.Count - 1 do
        if LGroups[J].ComponentIndex = LMatch.ComponentIndex then
        begin
          LFound := True;
          LLib := J;
          Break;
        end;

      if not LFound then
      begin
        LPlan := Default(TManifestLibraryPlan);
        LPlan.ComponentIndex := LMatch.ComponentIndex;
        LPlan.BomRef := 'manifest-' + IntToStr(LMatch.ComponentIndex);
        LPlan.SpdxId := ManifestSpdxId(
          AManifest.Components[LMatch.ComponentIndex].Name, LMatch.ComponentIndex);
        LGroups.Add(LPlan);
        LLib := LGroups.Count - 1;
      end;

      LPlan := LGroups[LLib];
      SetLength(LPlan.UnitBomRefs, Length(LPlan.UnitBomRefs) + 1);
      LPlan.UnitBomRefs[High(LPlan.UnitBomRefs)] := 'comp-' + IntToStr(I);
      SetLength(LPlan.UnitSpdxIds, Length(LPlan.UnitSpdxIds) + 1);
      LPlan.UnitSpdxIds[High(LPlan.UnitSpdxIds)] :=
        SpdxPackageIdForRelativePath(AArtefacts[I].RelativePath);
      LGroups[LLib] := LPlan;
      LGrouped.Add(I);
    end;

    Result.Libraries := LGroups.ToArray;
    Result.GroupedArtefactIndexes := LGrouped.ToArray;
    Result.Active := Length(Result.Libraries) > 0;
  finally
    LGrouped.Free;
    LGroups.Free;
  end;
end;

function DormantComponentWarnings(const AManifest: TComponentManifest;
  const APlan: TManifestPlan): TArray<string>;
var
  LSeen: TArray<Boolean>;
  LList: TList<string>;
  I, LIndex: Integer;
  LEntry: TComponentEntry;
begin
  Result := nil;
  if not AManifest.Loaded then
    Exit;

  SetLength(LSeen, Length(AManifest.Components));
  for I := 0 to High(APlan.Libraries) do
  begin
    LIndex := APlan.Libraries[I].ComponentIndex;
    if (LIndex >= 0) and (LIndex <= High(LSeen)) then
      LSeen[LIndex] := True;
  end;

  LList := TList<string>.Create;
  try
    for I := 0 to High(AManifest.Components) do
    begin
      if LSeen[I] then
        Continue;
      LEntry := AManifest.Components[I];
      if (Length(LEntry.Prefixes) = 0) and (Length(LEntry.ExactUnits) = 0) then
        Continue;
      if LEntry.Name <> '' then
        LList.Add('component "' + LEntry.Name + '" matched no units')
      else
        LList.Add(Format('component[%d] matched no units', [I]));
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

procedure ApplyManifestPublisher(const AManifest: TComponentManifest;
  var AMetadata: TSbomMetadata);
begin
  if not AManifest.Loaded then
    Exit;
  if (Trim(AMetadata.Supplier) = '') and (AManifest.SupplierName <> '') then
  begin
    AMetadata.Supplier := AManifest.SupplierName;
    AMetadata.SupplierUrl := AManifest.SupplierUrl;
  end;
end;

function TryPrepareManifest(const AManifestJson: string; const AArtefacts: TArtefactList;
  out AManifest: TComponentManifest; out APlan: TManifestPlan): Boolean;
var
  LError: string;
begin
  AManifest := Default(TComponentManifest);
  APlan := Default(TManifestPlan);
  Result := False;
  if Trim(AManifestJson) = '' then
    Exit;
  if not TryParseComponentManifest(AManifestJson, '', AManifest, LError) then
    Exit;
  APlan := BuildManifestPlan(AManifest, AArtefacts);
  Result := True;
end;

procedure AddLicenceJson(AComponent: TJSONObject; const AEntry: TComponentEntry);
var
  LKind: TLicenceKind;
  LValue: string;
  LLicences: TJSONArray;
  LWrapper, LLicence: TJSONObject;

  procedure AddNamed(const AAcknowledgement: string);
  begin
    LWrapper := TJSONObject.Create;
    LLicences.Add(LWrapper);
    LLicence := TJSONObject.Create;
    LWrapper.AddPair('license', LLicence);
    if LKind = lkSpdxId then
      LLicence.AddPair('id', LValue)
    else
      LLicence.AddPair('name', LValue);
    // acknowledgement sits on the license object in bom-1.6.schema.json.
    LLicence.AddPair('acknowledgement', AAcknowledgement);
    if AEntry.LicenceUrl <> '' then
      LLicence.AddPair('url', AEntry.LicenceUrl);
  end;

begin
  LKind := ClassifyLicence(AEntry.Licence, LValue);
  if LKind = lkNone then
    Exit;

  LLicences := TJSONArray.Create;
  AComponent.AddPair('licenses', LLicences);

  if LKind = lkExpression then
  begin
    // licenseChoice allows one expression. That slot is the distribution
    // licence we assert, so the acknowledgement is concluded. A second
    // declared copy would not match the schema.
    LWrapper := TJSONObject.Create;
    LLicences.Add(LWrapper);
    LWrapper.AddPair('expression', LValue);
    LWrapper.AddPair('acknowledgement', 'concluded');
  end
  else
  begin
    // The manifest row declares the licence, and it is also the distribution
    // licence we assert. Same id or name, once concluded and once declared.
    AddNamed('concluded');
    AddNamed('declared');
  end;
end;

function BuildLibraryJson(const AEntry: TComponentEntry; AIndex: Integer;
  const ABomRef: string): TJSONObject;
var
  LSupplier, LContact: TJSONObject;
  LUrls, LRefs, LContacts: TJSONArray;
  LRef: TJSONObject;
  LPurl: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', AEntry.ComponentType);
  Result.AddPair('bom-ref', ABomRef);

  if AEntry.Vendor <> '' then
  begin
    LSupplier := TJSONObject.Create;
    Result.AddPair('supplier', LSupplier);
    LSupplier.AddPair('name', AEntry.Vendor);
    if AEntry.VendorUrl <> '' then
    begin
      LUrls := TJSONArray.Create;
      LSupplier.AddPair('url', LUrls);
      LUrls.Add(AEntry.VendorUrl);
    end;
    if IsBsiEmailAddress(Trim(AEntry.Vendor)) then
    begin
      LContacts := TJSONArray.Create;
      LContact := TJSONObject.Create;
      LContact.AddPair('email', Trim(AEntry.Vendor));
      LContacts.Add(LContact);
      LSupplier.AddPair('contact', LContacts);
    end;
    Result.AddPair('author', AEntry.Vendor);
  end;

  Result.AddPair('name', ComponentDisplayName(AEntry, AIndex));
  if AEntry.Version <> '' then
    Result.AddPair('version', AEntry.Version);

  AddLicenceJson(Result, AEntry);

  LPurl := BuildDelphiPurl(AEntry.Name, AEntry.Version, AEntry.Purl);
  if LPurl <> '' then
    Result.AddPair('purl', LPurl);

  if AEntry.VendorUrl <> '' then
  begin
    LRefs := TJSONArray.Create;
    Result.AddPair('externalReferences', LRefs);
    LRef := TJSONObject.Create;
    LRefs.Add(LRef);
    LRef.AddPair('type', 'website');
    LRef.AddPair('url', AEntry.VendorUrl);
  end;
end;

function IsGroupedComponentRef(const ARef: string; const AGrouped: TArray<Boolean>): Boolean;
var
  LIndex, LCode: Integer;
begin
  Result := False;
  if not ARef.StartsWith('comp-') then
    Exit;
  Val(Copy(ARef, 6, MaxInt), LIndex, LCode);
  if LCode <> 0 then
    Exit;
  Result := (LIndex >= 0) and (LIndex <= High(AGrouped)) and AGrouped[LIndex];
end;

procedure ApplyManifestCycloneDxJson(const AManifestJson: string;
  const AArtefacts: TArtefactList; AComponents, ADependencies: TJSONArray;
  const AProjectBomRef: string);
var
  LManifest: TComponentManifest;
  LPlan: TManifestPlan;
  LGrouped: TArray<Boolean>;
  LDep, LLibraryDep: TJSONObject;
  LDepends, LNewDepends, LChildDepends: TJSONArray;
  LPair: TJSONPair;
  LValue: TJSONValue;
  I, J: Integer;
  LRef: string;
  LArtefactCount: Integer;
  LHasGrouped: Boolean;
  LRewritten: Boolean;
begin
  if not Assigned(AComponents) or not Assigned(ADependencies) then
    Exit;
  if not TryPrepareManifest(AManifestJson, AArtefacts, LManifest, LPlan) then
    Exit;
  if not LPlan.Active then
    Exit;

  for I := 0 to High(LPlan.Libraries) do
    AComponents.Add(BuildLibraryJson(
      LManifest.Components[LPlan.Libraries[I].ComponentIndex],
      LPlan.Libraries[I].ComponentIndex,
      LPlan.Libraries[I].BomRef));

  LArtefactCount := 0;
  if Assigned(AArtefacts) then
    LArtefactCount := AArtefacts.Count;
  SetLength(LGrouped, LArtefactCount);
  for I := 0 to High(LPlan.GroupedArtefactIndexes) do
    if (LPlan.GroupedArtefactIndexes[I] >= 0) and
      (LPlan.GroupedArtefactIndexes[I] < LArtefactCount) then
      LGrouped[LPlan.GroupedArtefactIndexes[I]] := True;

  // The grouped graph lists matched units on the deliverable, not on
  // the project. Rewrite whichever dependency still lists those units.
  // When none does, hang the libraries off the project.
  LRewritten := False;
  for I := 0 to ADependencies.Count - 1 do
  begin
    if not (ADependencies.Items[I] is TJSONObject) then
      Continue;
    LDep := TJSONObject(ADependencies.Items[I]);
    if not (LDep.GetValue('dependsOn') is TJSONArray) then
      Continue;

    LDepends := TJSONArray(LDep.GetValue('dependsOn'));
    LHasGrouped := False;
    for J := 0 to LDepends.Count - 1 do
      if IsGroupedComponentRef(LDepends.Items[J].Value, LGrouped) then
      begin
        LHasGrouped := True;
        Break;
      end;
    if not LHasGrouped then
      Continue;

    LNewDepends := TJSONArray.Create;
    for J := 0 to LDepends.Count - 1 do
    begin
      LRef := LDepends.Items[J].Value;
      if not IsGroupedComponentRef(LRef, LGrouped) then
        LNewDepends.Add(LRef);
    end;
    for J := 0 to High(LPlan.Libraries) do
      LNewDepends.Add(LPlan.Libraries[J].BomRef);

    LPair := LDep.RemovePair('dependsOn');
    if Assigned(LPair) then
      LPair.Free;
    LDep.AddPair('dependsOn', LNewDepends);
    LRewritten := True;
  end;

  if not LRewritten then
    for I := 0 to ADependencies.Count - 1 do
    begin
      if not (ADependencies.Items[I] is TJSONObject) then
        Continue;
      LDep := TJSONObject(ADependencies.Items[I]);
      LValue := LDep.GetValue('ref');
      if (LValue = nil) or not SameText(LValue.Value, AProjectBomRef) then
        Continue;

      LNewDepends := TJSONArray.Create;
      if LDep.GetValue('dependsOn') is TJSONArray then
      begin
        LDepends := TJSONArray(LDep.GetValue('dependsOn'));
        for J := 0 to LDepends.Count - 1 do
        begin
          LRef := LDepends.Items[J].Value;
          if not IsGroupedComponentRef(LRef, LGrouped) then
            LNewDepends.Add(LRef);
        end;
      end;
      for J := 0 to High(LPlan.Libraries) do
        LNewDepends.Add(LPlan.Libraries[J].BomRef);

      LPair := LDep.RemovePair('dependsOn');
      if Assigned(LPair) then
        LPair.Free;
      LDep.AddPair('dependsOn', LNewDepends);
      Break;
    end;

  for I := 0 to High(LPlan.Libraries) do
  begin
    LLibraryDep := TJSONObject.Create;
    ADependencies.Add(LLibraryDep);
    LLibraryDep.AddPair('ref', LPlan.Libraries[I].BomRef);
    LChildDepends := TJSONArray.Create;
    LLibraryDep.AddPair('dependsOn', LChildDepends);
    for J := 0 to High(LPlan.Libraries[I].UnitBomRefs) do
      LChildDepends.Add(LPlan.Libraries[I].UnitBomRefs[J]);
  end;
end;

procedure AppendManifestLibrariesXml(ALines: TStrings; const AManifestJson: string;
  const AArtefacts: TArtefactList; AIndentLevel: Integer);
var
  LManifest: TComponentManifest;
  LPlan: TManifestPlan;
  I: Integer;

  procedure AddLine(ALevel: Integer; const AText: string);
  begin
    ALines.Add(StringOfChar(' ', ALevel * 2) + AText);
  end;

  procedure EmitLicence(const AEntry: TComponentEntry; ALevel: Integer);
  var
    LKind: TLicenceKind;
    LValue: string;
  begin
    LKind := ClassifyLicence(AEntry.Licence, LValue);
    if LKind = lkNone then
      Exit;
    AddLine(ALevel, '<licenses>');
    if LKind = lkExpression then
      AddLine(ALevel + 1, '<expression acknowledgement="concluded">' +
        EscapeXml(LValue) + '</expression>')
    else
    begin
      AddLine(ALevel + 1, '<license acknowledgement="concluded">');
      if LKind = lkSpdxId then
        AddLine(ALevel + 2, '<id>' + EscapeXml(LValue) + '</id>')
      else
        AddLine(ALevel + 2, '<name>' + EscapeXml(LValue) + '</name>');
      if AEntry.LicenceUrl <> '' then
        AddLine(ALevel + 2, '<url>' + EscapeXml(AEntry.LicenceUrl) + '</url>');
      AddLine(ALevel + 1, '</license>');
      AddLine(ALevel + 1, '<license acknowledgement="declared">');
      if LKind = lkSpdxId then
        AddLine(ALevel + 2, '<id>' + EscapeXml(LValue) + '</id>')
      else
        AddLine(ALevel + 2, '<name>' + EscapeXml(LValue) + '</name>');
      if AEntry.LicenceUrl <> '' then
        AddLine(ALevel + 2, '<url>' + EscapeXml(AEntry.LicenceUrl) + '</url>');
      AddLine(ALevel + 1, '</license>');
    end;
    AddLine(ALevel, '</licenses>');
  end;

  procedure EmitLibrary(const AEntry: TComponentEntry; AIndex: Integer; const ABomRef: string);
  var
    LPurl: string;
  begin
    // bom-1.6.xsd component order: supplier, author, name, version,
    // hashes, licenses, purl, externalReferences.
    AddLine(AIndentLevel, '<component type="' + EscapeXml(AEntry.ComponentType) +
      '" bom-ref="' + EscapeXml(ABomRef) + '">');
    if AEntry.Vendor <> '' then
    begin
      AddLine(AIndentLevel + 1, '<supplier>');
      AddLine(AIndentLevel + 2, '<name>' + EscapeXml(AEntry.Vendor) + '</name>');
      if AEntry.VendorUrl <> '' then
        AddLine(AIndentLevel + 2, '<url>' + EscapeXml(AEntry.VendorUrl) + '</url>');
      if IsBsiEmailAddress(Trim(AEntry.Vendor)) then
      begin
        AddLine(AIndentLevel + 2, '<contact>');
        AddLine(AIndentLevel + 3, '<email>' + EscapeXml(Trim(AEntry.Vendor)) + '</email>');
        AddLine(AIndentLevel + 2, '</contact>');
      end;
      AddLine(AIndentLevel + 1, '</supplier>');
      AddLine(AIndentLevel + 1, '<author>' + EscapeXml(AEntry.Vendor) + '</author>');
    end;
    AddLine(AIndentLevel + 1, '<name>' +
      EscapeXml(ComponentDisplayName(AEntry, AIndex)) + '</name>');
    if AEntry.Version <> '' then
      AddLine(AIndentLevel + 1, '<version>' + EscapeXml(AEntry.Version) + '</version>');
    EmitLicence(AEntry, AIndentLevel + 1);
    LPurl := BuildDelphiPurl(AEntry.Name, AEntry.Version, AEntry.Purl);
    if LPurl <> '' then
      AddLine(AIndentLevel + 1, '<purl>' + EscapeXml(LPurl) + '</purl>');
    if AEntry.VendorUrl <> '' then
    begin
      AddLine(AIndentLevel + 1, '<externalReferences>');
      AddLine(AIndentLevel + 2, '<reference type="website">');
      AddLine(AIndentLevel + 3, '<url>' + EscapeXml(AEntry.VendorUrl) + '</url>');
      AddLine(AIndentLevel + 2, '</reference>');
      AddLine(AIndentLevel + 1, '</externalReferences>');
    end;
    AddLine(AIndentLevel, '</component>');
  end;

begin
  if not Assigned(ALines) then
    Exit;
  if not TryPrepareManifest(AManifestJson, AArtefacts, LManifest, LPlan) then
    Exit;
  if not LPlan.Active then
    Exit;

  for I := 0 to High(LPlan.Libraries) do
    EmitLibrary(
      LManifest.Components[LPlan.Libraries[I].ComponentIndex],
      LPlan.Libraries[I].ComponentIndex,
      LPlan.Libraries[I].BomRef);
end;

procedure AppendManifestDependenciesXml(ALines: TStrings; const AManifestJson: string;
  const AArtefacts: TArtefactList; const AProjectBomRef: string; AIndentLevel: Integer;
  const AUsesGraph: TUsesDependencyGraph);
var
  LManifest: TComponentManifest;
  LPlan: TManifestPlan;
  LGrouped: TArray<Boolean>;
  LChildren: TStringList;
  LTargetIndex: Integer;
  LGroup: Integer;
  I, J: Integer;

  procedure AddLine(ALevel: Integer; const AText: string);
  begin
    ALines.Add(StringOfChar(' ', ALevel * 2) + AText);
  end;

begin
  if not Assigned(ALines) then
    Exit;

  LPlan := Default(TManifestPlan);
  if Assigned(AArtefacts) then
    SetLength(LGrouped, AArtefacts.Count);
  if TryPrepareManifest(AManifestJson, AArtefacts, LManifest, LPlan) and LPlan.Active then
    for I := 0 to High(LPlan.GroupedArtefactIndexes) do
      if (LPlan.GroupedArtefactIndexes[I] >= 0) and
        (LPlan.GroupedArtefactIndexes[I] <= High(LGrouped)) then
        LGrouped[LPlan.GroupedArtefactIndexes[I]] := True;

  LTargetIndex := -1;
  if Assigned(AArtefacts) then
    LTargetIndex := FindDeliverableTargetIndex(AArtefacts, AProjectBomRef);

  AddLine(AIndentLevel, '<dependencies>');
  AddLine(AIndentLevel + 1, '<dependency ref="' + EscapeXml(AProjectBomRef) + '">');
  if LTargetIndex >= 0 then
    AddLine(AIndentLevel + 2, '<dependency ref="comp-' + IntToStr(LTargetIndex) + '"/>')
  else if Assigned(AArtefacts) then
  begin
    for I := 0 to AArtefacts.Count - 1 do
      if (I > High(LGrouped)) or not LGrouped[I] then
        AddLine(AIndentLevel + 2, '<dependency ref="comp-' + IntToStr(I) + '"/>');
    if LPlan.Active then
      for I := 0 to High(LPlan.Libraries) do
        AddLine(AIndentLevel + 2, '<dependency ref="' +
          EscapeXml(LPlan.Libraries[I].BomRef) + '"/>');
  end;
  AddLine(AIndentLevel + 1, '</dependency>');

  if (LTargetIndex >= 0) and Assigned(AArtefacts) then
  begin
    LChildren := TStringList.Create;
    try
      for LGroup := 0 to 3 do
        for I := 0 to AArtefacts.Count - 1 do
          if (I <> LTargetIndex) and
             (ArtefactDependencyGroup(AArtefacts[I]) = LGroup) and
             ((I > High(LGrouped)) or not LGrouped[I]) then
            LChildren.Add('<dependency ref="comp-' + IntToStr(I) + '"/>');
      if LPlan.Active then
        for I := 0 to High(LPlan.Libraries) do
          LChildren.Add('<dependency ref="' +
            EscapeXml(LPlan.Libraries[I].BomRef) + '"/>');
      if LChildren.Count > 0 then
      begin
        AddLine(AIndentLevel + 1, '<dependency ref="comp-' + IntToStr(LTargetIndex) + '">');
        for I := 0 to LChildren.Count - 1 do
          AddLine(AIndentLevel + 2, LChildren[I]);
        AddLine(AIndentLevel + 1, '</dependency>');
      end;
    finally
      LChildren.Free;
    end;
  end;

  if LPlan.Active then
    for I := 0 to High(LPlan.Libraries) do
    begin
      AddLine(AIndentLevel + 1, '<dependency ref="' +
        EscapeXml(LPlan.Libraries[I].BomRef) + '">');
      for J := 0 to High(LPlan.Libraries[I].UnitBomRefs) do
        AddLine(AIndentLevel + 2, '<dependency ref="' +
          EscapeXml(LPlan.Libraries[I].UnitBomRefs[J]) + '"/>');
      AddLine(AIndentLevel + 1, '</dependency>');
    end;
  WriteUsesDependenciesXml(ALines, AIndentLevel, AUsesGraph);
  AddLine(AIndentLevel, '</dependencies>');
end;

function ManifestLibraryBomRefs(const AManifestJson: string;
  const AArtefacts: TArtefactList): TArray<string>;
var
  LManifest: TComponentManifest;
  LPlan: TManifestPlan;
  I: Integer;
begin
  Result := nil;
  if not TryPrepareManifest(AManifestJson, AArtefacts, LManifest, LPlan) then
    Exit;
  if not LPlan.Active then
    Exit;
  SetLength(Result, Length(LPlan.Libraries));
  for I := 0 to High(LPlan.Libraries) do
    Result[I] := LPlan.Libraries[I].BomRef;
end;

function SpdxLicenceToken(const AEntry: TComponentEntry; out AKind: TLicenceKind): string;
var
  LValue: string;
begin
  AKind := ClassifyLicence(AEntry.Licence, LValue);
  case AKind of
    lkNone:
      Result := 'NOASSERTION';
    lkSpdxId, lkExpression:
      Result := LValue;
  else
    Result := 'LicenseRef-' + SanitizeSpdxId(LValue);
    if Result = 'LicenseRef-' then
      Result := 'LicenseRef-Custom';
  end;
end;

function BuildSpdxLibraryPackage(const AEntry: TComponentEntry; AIndex: Integer;
  const ASpdxId: string): TJSONObject;
var
  LKind: TLicenceKind;
  LToken, LPurl: string;
  LRefs: TJSONArray;
  LRef: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('SPDXID', ASpdxId);
  Result.AddPair('name', ComponentDisplayName(AEntry, AIndex));
  if AEntry.Version <> '' then
    Result.AddPair('versionInfo', AEntry.Version);
  Result.AddPair('downloadLocation', 'NOASSERTION');
  Result.AddPair('filesAnalyzed', TJSONBool.Create(False));
  if AEntry.Vendor <> '' then
    Result.AddPair('supplier', 'Organization: ' + AEntry.Vendor)
  else
    Result.AddPair('supplier', 'NOASSERTION');
  if IsBsiEmailAddress(Trim(AEntry.Vendor)) then
    Result.AddPair('originator', 'Person: ' + Trim(AEntry.Vendor) + ' (' +
      Trim(AEntry.Vendor) + ')')
  else if Trim(AEntry.Vendor) <> '' then
    Result.AddPair('originator', 'Organization: ' + Trim(AEntry.Vendor));

  LToken := SpdxLicenceToken(AEntry, LKind);
  Result.AddPair('licenseConcluded', LToken);
  Result.AddPair('licenseDeclared', LToken);
  Result.AddPair('copyrightText', 'NOASSERTION');

  LPurl := BuildDelphiPurl(AEntry.Name, AEntry.Version, AEntry.Purl);
  if (LPurl <> '') or (AEntry.VendorUrl <> '') then
  begin
    LRefs := TJSONArray.Create;
    Result.AddPair('externalRefs', LRefs);
    if LPurl <> '' then
    begin
      LRef := TJSONObject.Create;
      LRefs.Add(LRef);
      LRef.AddPair('referenceCategory', 'PACKAGE-MANAGER');
      LRef.AddPair('referenceType', 'purl');
      LRef.AddPair('referenceLocator', LPurl);
    end;
    if AEntry.VendorUrl <> '' then
    begin
      LRef := TJSONObject.Create;
      LRefs.Add(LRef);
      LRef.AddPair('referenceCategory', 'OTHER');
      LRef.AddPair('referenceType', 'website');
      LRef.AddPair('referenceLocator', AEntry.VendorUrl);
    end;
  end;
end;

procedure AddSpdxRelationship(ARelationships: TJSONArray;
  const AFromId, AKind, AToId: string);
var
  LRel: TJSONObject;
begin
  LRel := TJSONObject.Create;
  ARelationships.Add(LRel);
  LRel.AddPair('spdxElementId', AFromId);
  LRel.AddPair('relationshipType', AKind);
  LRel.AddPair('relatedSpdxElement', AToId);
end;

procedure ApplyManifestSpdx(const AManifestJson: string;
  const AArtefacts: TArtefactList; APackages, ARelationships: TJSONArray;
  const APackageIds: TArray<string>; const ADocumentSpdxId: string;
  ARoot: TJSONObject);
var
  LManifest: TComponentManifest;
  LPlan: TManifestPlan;
  LExtracted: TJSONArray;
  LSeen: TStringList;
  LAddedEdges: TStringList;
  LUnitToLibrary: TDictionary<string, string>;
  LEntry: TComponentEntry;
  LKind: TLicenceKind;
  LToken, LNormalised, LUnitId, LParent, LLibraryId, LEdge: string;
  LInfo, LRel: TJSONObject;
  LRemoved: TJSONValue;
  I, J, LIndex, LCode, LBar: Integer;

  function JsonText(AObject: TJSONObject; const AName: string): string;
  var
    LItem: TJSONValue;
  begin
    Result := '';
    if not Assigned(AObject) then
      Exit;
    LItem := AObject.GetValue(AName);
    if LItem <> nil then
      Result := LItem.Value;
  end;

  function PackageIdForBomRef(const ARef: string): string;
  begin
    Result := '';
    if not ARef.StartsWith('comp-') then
      Exit;
    Val(Copy(ARef, 6, MaxInt), LIndex, LCode);
    if (LCode <> 0) or (LIndex < 0) or (LIndex > High(APackageIds)) then
      Exit;
    Result := APackageIds[LIndex];
  end;

begin
  if not Assigned(APackages) or not Assigned(ARelationships) or not Assigned(ARoot) then
    Exit;
  if not TryPrepareManifest(AManifestJson, AArtefacts, LManifest, LPlan) then
    Exit;
  if not LPlan.Active then
    Exit;

  LExtracted := TJSONArray.Create;
  LSeen := TStringList.Create;
  LAddedEdges := TStringList.Create;
  LUnitToLibrary := TDictionary<string, string>.Create;
  try
    LSeen.CaseSensitive := False;
    LAddedEdges.CaseSensitive := False;
    for I := 0 to High(LPlan.Libraries) do
    begin
      LEntry := LManifest.Components[LPlan.Libraries[I].ComponentIndex];
      APackages.Add(BuildSpdxLibraryPackage(LEntry, LPlan.Libraries[I].ComponentIndex,
        LPlan.Libraries[I].SpdxId));
      AddSpdxRelationship(ARelationships, ADocumentSpdxId, 'DESCRIBES',
        LPlan.Libraries[I].SpdxId);
      for J := 0 to High(LPlan.Libraries[I].UnitBomRefs) do
      begin
        LUnitId := PackageIdForBomRef(LPlan.Libraries[I].UnitBomRefs[J]);
        if (LUnitId = '') and (J <= High(LPlan.Libraries[I].UnitSpdxIds)) then
          LUnitId := LPlan.Libraries[I].UnitSpdxIds[J];
        if LUnitId = '' then
          Continue;
        LUnitToLibrary.AddOrSetValue(LUnitId, LPlan.Libraries[I].SpdxId);
        AddSpdxRelationship(ARelationships, LPlan.Libraries[I].SpdxId, 'DEPENDS_ON',
          LUnitId);
      end;

      LToken := SpdxLicenceToken(LEntry, LKind);
      if (LKind = lkName) and (LSeen.IndexOf(LToken) < 0) then
      begin
        LSeen.Add(LToken);
        ClassifyLicence(LEntry.Licence, LNormalised);
        LInfo := TJSONObject.Create;
        LExtracted.Add(LInfo);
        LInfo.AddPair('licenseId', LToken);
        LInfo.AddPair('name', LNormalised);
        LInfo.AddPair('extractedText', LNormalised);
      end;
    end;

    // The deliverable contains every linked unit. Move the grouped ones
    // onto the library and record one DEPENDS_ON edge to that library.
    for I := ARelationships.Count - 1 downto 0 do
    begin
      if not (ARelationships.Items[I] is TJSONObject) then
        Continue;
      LRel := TJSONObject(ARelationships.Items[I]);
      LToken := JsonText(LRel, 'relationshipType');
      if (LToken <> 'CONTAINS') and (LToken <> 'DEPENDS_ON') then
        Continue;
      LUnitId := JsonText(LRel, 'relatedSpdxElement');
      if not LUnitToLibrary.TryGetValue(LUnitId, LLibraryId) then
        Continue;
      LParent := JsonText(LRel, 'spdxElementId');
      if SameText(LParent, ADocumentSpdxId) then
        Continue;
      if LParent.StartsWith('SPDXRef-Package-Manifest-') then
        Continue;
      LRemoved := ARelationships.Remove(I);
      if Assigned(LRemoved) then
        LRemoved.Free;
      LEdge := LParent + '|' + LLibraryId;
      if LAddedEdges.IndexOf(LEdge) < 0 then
        LAddedEdges.Add(LEdge);
    end;

    for I := 0 to LAddedEdges.Count - 1 do
    begin
      LBar := Pos('|', LAddedEdges[I]);
      AddSpdxRelationship(ARelationships, Copy(LAddedEdges[I], 1, LBar - 1),
        'DEPENDS_ON', Copy(LAddedEdges[I], LBar + 1, MaxInt));
    end;

    if LExtracted.Count > 0 then
      ARoot.AddPair('hasExtractedLicensingInfos', LExtracted)
    else
      LExtracted.Free;
  finally
    LUnitToLibrary.Free;
    LAddedEdges.Free;
    LSeen.Free;
  end;
end;

end.
