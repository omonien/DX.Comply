/// <summary>
/// DX.Comply.ComponentManifest
/// Loads a components.json manifest and matches units to libraries.
/// </summary>
///
/// <remarks>
/// This is DX.Comply's components.json shape (schema_version 1.0): one row
/// per library, matched by units_exact, units_prefix, and units_folder.
/// schema_version "1.0" is the version of this manifest, not an industry
/// standard. Root supplier is the application publisher. The per-component
/// author is vendor. own_code_folders names folders of the project's own
/// units, the same way own_code_units names those units one by one.
///
/// Licence values are classified as an SPDX identifier, an SPDX expression,
/// or a plain name. An expression is recognised only when every operand is
/// a known SPDX id or a LicenseRef id, so English words such as "with",
/// "and", and "or" do not turn a name into an expression. A value that
/// already starts with LicenseRef- and is not such an expression stays a
/// name, so CycloneDX writes license.name. The SPDX writers keep that
/// prefix and only sanitize the id characters. Package URLs for manifest
/// libraries use pkg:delphi, which
/// is not a registered PURL type. Scanned files keep the file: locator the
/// writers already emit. An optional purl field on a row replaces the
/// generated value.
///
/// Own-code units stay in the evidence. They are not dropped and they are
/// not attached to a third-party library. When a product licence is set,
/// those units carry it. Embarcadero RTL, VCL, and FMX units carry the
/// origin label the resolver already writes.
///
/// An optional copyright string on a row is stored as text (a year or other
/// copyright notice). It is not used for matching. When the text is set,
/// the CycloneDX and SPDX writers put it on the library component for that
/// row. The human-readable licence summary shows the same text.
///
/// An optional cpe string is stored only when it is a CPE 2.3 formatted
/// string or a CPE 2.2 URI, the two forms the CycloneDX 1.6 schema accepts.
/// It is not used for matching and it is not derived from the name or the
/// version. When it is set, the writers put it on the library component for
/// that row. A value that is neither form is a warning and is left out.
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
  /// Which CPE binding a manifest value uses.
  /// </summary>
  TCpeKind = (
    /// <summary>
    /// No CPE, or a value that is not a CPE 2.3 formatted string and not a
    /// CPE 2.2 URI. The writers leave the field out.
    /// </summary>
    ckNone,
    /// <summary>
    /// CPE 2.3 formatted string: cpe:2.3:part:vendor:product:version:...
    /// </summary>
    ckCpe23,
    /// <summary>
    /// CPE 2.2 URI: cpe:/part:vendor:product:version:...
    /// </summary>
    ckCpe22
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
  /// How units_prefix assigns a library. corroborated is the default.
  /// legacy is the one-release switch match.prefixes=legacy.
  /// </summary>
  TPrefixMatchMode = (
    /// <summary>
    /// A prefix assigns a library only when it contains a dot and the
    /// unit file is not in an Embarcadero product path. A prefix with no
    /// dot does not assign. units_exact and units_folder are unchanged.
    /// </summary>
    pmmCorroborated,
    /// <summary>
    /// A prefix assigns a library the way it did before this rule, except
    /// it never assigns a unit whose file is in an Embarcadero product path.
    /// </summary>
    pmmLegacy
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
    /// <summary>
    /// Case-insensitive unit names that the prefixes and folders of this
    /// row do not match (units_exclude, issue #140).
    /// </summary>
    ExcludeUnits: TArray<string>;
    /// <summary>
    /// Folders whose units belong to this row (units_folder). A unit matches
    /// when its source file is in the folder or in a folder under it. After
    /// a successful load each entry is an absolute path.
    /// </summary>
    Folders: TArray<string>;
    /// <summary>Freeform notes. Not written into the SBOM.</summary>
    Notes: string;
    /// <summary>
    /// Optional copyright text, such as a year ("2020") or a free-form
    /// notice. Not a timestamp. Not used for matching. Written on the
    /// library component when set (CycloneDX copyright, SPDX 2.3
    /// copyrightText, SPDX 3.0.1 software_copyrightText). Shown in the
    /// human-readable licence summary. Empty when the row omits it.
    /// </summary>
    Copyright: string;
    /// <summary>
    /// Optional CPE. A CPE 2.3 formatted string or a CPE 2.2 URI, the forms
    /// CycloneDX 1.6 accepts. Not used for matching. Not derived. Written on
    /// the library component when set (CycloneDX cpe, SPDX 2.3 externalRefs
    /// referenceType cpe23Type or cpe22Type, SPDX 3.0.1 externalIdentifier
    /// cpe23 or cpe22). Empty when the row omits it or the value was rejected.
    /// </summary>
    Cpe: string;
  end;

  /// <summary>
  /// A parsed components.json file.
  /// </summary>
  TComponentManifest = record
    /// <summary>True when parsing succeeded.</summary>
    Loaded: Boolean;
    /// <summary>schema_version, when present. "1.0" is this manifest's version.</summary>
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
    /// <summary>
    /// Folders whose units are the project's own code (own_code_folders).
    /// Subfolders are included. After a successful load each entry is an
    /// absolute path.
    /// </summary>
    OwnCodeFolders: TArray<string>;
    /// <summary>Non-fatal schema notes. Fatal problems are returned separately.</summary>
    Warnings: TArray<string>;
    /// <summary>Path or label the text was loaded from.</summary>
    SourcePath: string;
    /// <summary>
    /// units_prefix rule. Missing match.prefixes means corroborated.
    /// </summary>
    PrefixMode: TPrefixMatchMode;
    /// <summary>
    /// Delphi install root for this run. Empty when the caller has no
    /// toolchain root. A prefix does not assign a unit under a product
    /// shipped path of this root. The engine writes it onto the in-memory
    /// manifest. It is not a field of the components file.
    /// </summary>
    InstallRoot: string;
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
/// OR, AND, and WITH make an expression only when each operand is a known
/// SPDX id or a LicenseRef id. A name that merely contains those English
/// words stays a name.
/// </summary>
function ClassifyLicence(const AValue: string; out ANormalised: string): TLicenceKind;

/// <summary>
/// Classifies a CPE value. A CPE 2.3 formatted string is ckCpe23. A CPE 2.2
/// URI is ckCpe22. Both are the forms named by the CycloneDX 1.6 schema.
/// Anything else, including an empty string, is ckNone. The value is not
/// rewritten and no CPE is derived from a name or a version.
/// </summary>
function ClassifyCpe(const AValue: string): TCpeKind;

/// <summary>
/// Appends CycloneDX 1.6 licenses to a component. An empty value writes
/// nothing. An SPDX id or a name is written twice, concluded then declared.
/// An expression is one concluded entry. A URL is omitted for an expression.
/// </summary>
procedure AddCycloneDxLicences(AComponent: TJSONObject; const ALicence,
  ALicenceUrl: string);

/// <summary>
/// Appends a licenses element. An empty value writes nothing.
/// Indent is two spaces per level, the same as the XML writer.
/// </summary>
procedure AppendCycloneDxLicencesXml(ALines: TStrings; const ALicence,
  ALicenceUrl: string; AIndentLevel: Integer);

/// <summary>
/// SPDX 2.3 token for a licence value. NOASSERTION when empty.
/// A name becomes LicenseRef- followed by a sanitized id.
/// A value that already starts with LicenseRef- keeps that prefix.
/// Only the characters after the prefix are sanitized.
/// </summary>
function SpdxLicenceTokenFor(const ALicence: string; out AKind: TLicenceKind): string;

/// <summary>
/// Licence written on one SBOM component, and the title used for that
/// component in the report licence overview.
/// The built program uses the product licence. An empty product licence
/// stays empty, which is the previous output.
/// A unit classified as own code through own_code_units, own_code_prefixes,
/// or own_code_folders uses the product licence when one is set. With no
/// product licence those units keep the previous output, unless the unit
/// is also Embarcadero.
/// A unit whose origin is Embarcadero RTL, Embarcadero VCL, Embarcadero FMX,
/// or another label that starts with "Embarcadero ", uses that label. That
/// is the identifier the resolver already writes for those units.
/// A unit matched to a manifest library stays empty. The library component
/// carries the row licence.
/// </summary>
function ComponentLicenceFor(const AArtefact: TArtefactInfo;
  AIsDeliverable: Boolean; const AProductLicence: string;
  const AManifest: TComponentManifest): string;

/// <summary>
/// Version written on one SBOM component and in the report tables.
/// A version already stored on the artefact is kept. A third-party file
/// is left as it is, including an empty version and a file-date stand-in.
/// The built program, and a second copy of that file, uses the product
/// version when it has no version of its own. A file-date stand-in is not
/// a version of its own. The product version is the SBOM header value, or
/// the project version when the header is empty. That is the value the
/// report header shows. A unit is not the built program.
/// </summary>
function ComponentVersionFor(const AArtefact: TArtefactInfo;
  AIsDeliverable: Boolean; const AProductVersion, AProjectVersion: string): string;

/// <summary>
/// True when AWrittenVersion is the file modification time stored on
/// AArtefact. A product version used in its place is not a file date, so
/// the versionSource property must not be written for it.
/// </summary>
function ComponentVersionFromFileDate(const AArtefact: TArtefactInfo;
  const AWrittenVersion: string): Boolean;

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
/// Invalid JSON names the source file, the line and the position.
/// Schema gaps are warnings on a successfully loaded manifest.
/// A prefix used by more than one row is a warning. The units go to the
/// first row in the file.
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
/// Matches one unit. units_exact beats own_code_units, those beat a folder,
/// a folder beats a prefix, and a library prefix beats own_code_prefixes.
/// The longest matching folder wins, then the longest matching prefix.
/// On a tie the first row wins, and a component folder beats an own-code
/// folder of the same length. A units_prefix matches when the unit name
/// starts with it. A trailing dot is not required. The longest matching
/// prefix wins, and the same prefix on more than one row assigns the units
/// to the first row in the file. The name is tried as written and with its
/// scope prefix removed. A prefix assigns a library only when the prefix
/// mode allows it. corroborated requires a dot in the prefix. legacy allows
/// a prefix with no dot. Neither mode assigns a unit whose file is in an
/// Embarcadero product path under InstallRoot. own_code_prefixes are not
/// that rule. ASourcePath is the unit's source file. Folder rules do not
/// match when it is empty.
/// </summary>
function MatchManifestUnit(const AManifest: TComponentManifest;
  const AUnitName: string; const ASourcePath: string = ''): TManifestMatch;

/// <summary>
/// True when APath is a product shipped path under AInstallRoot.
/// Product source trees are source\rtl, source\vcl, source\fmx, source\data,
/// and the other source trees shipped in that folder. Product lib folders
/// are lib\&lt;platform&gt;\release, lib\&lt;platform&gt;\debug, and the DCUs
/// Delphi places in lib\&lt;platform&gt;. An empty root is never a product path.
/// </summary>
function IsEmbarcaderoProductPath(const APath, AInstallRoot: string): Boolean;

/// <summary>
/// True when a units_prefix would have selected a library and the prefix
/// rule did not assign it. APrefix and ARowName name that prefix and row.
/// A stronger rule (units_exact, own_code_units, or a folder) leaves this
/// false, because the prefix was not the assignment.
/// </summary>
function TryRejectedLibraryPrefix(const AManifest: TComponentManifest;
  const AUnitName, ASourcePath: string; out APrefix, ARowName: string): Boolean;

/// <summary>
/// Log line for a prefix that was not applied. Names the unit, the prefix,
/// the row, and the origin that was kept.
/// </summary>
function RejectedPrefixLogLine(const AUnitName, APrefix, ARowName,
  AKeptOrigin: string): string;

/// <summary>
/// One log line per artefact whose winning units_prefix was not applied.
/// Build mode lists those as unit-evidence. Library mode lists a shipped
/// .pas, .dpr, or .dpk as a file, and those are included too. The origin
/// on the artefact is the origin that was kept.
/// </summary>
function RejectedPrefixLogLines(const AManifest: TComponentManifest;
  const AArtefacts: TArtefactList): TArray<string>;

/// <summary>
/// One log line when a units_folder match is kept for a file that sits in
/// an Embarcadero product path. The folder is explicit, so the match stays.
/// Build mode and library mode both contribute, the same files as
/// RejectedPrefixLogLines.
/// </summary>
function ProductFolderMatchLogLines(const AManifest: TComponentManifest;
  const AArtefacts: TArtefactList): TArray<string>;

/// <summary>
/// Rewrites the in-memory manifest JSON so a later parse sees the install
/// root and, when APrefixMode is not empty, match.prefixes. The components
/// file on disk is not changed. An empty APrefixMode leaves match.prefixes
/// as the file wrote it.
/// </summary>
function ManifestJsonWithRuntimeContext(const AJson, AInstallRoot,
  APrefixMode: string): string;

/// <summary>
/// Source path used for folder rules. The resolver's source path when it
/// recorded one, otherwise FilePath when that file is a .pas or a shipped
/// .pas, .dpr, or .dpk. Empty when only a unit name, or a DCU in an output
/// folder, is known.
/// </summary>
function ArtefactFolderPath(const AArtefact: TArtefactInfo): string;

/// <summary>
/// Path passed to MatchManifestUnit. The folder path, or FilePath when that
/// file is in an Embarcadero product path and no source path was recorded.
/// A DCU in the project output folder stays unmatched by a folder.
/// </summary>
function ArtefactMatchPath(const AManifest: TComponentManifest;
  const AArtefact: TArtefactInfo): string;

/// <summary>
/// Unit name of a unit-evidence artefact. The stored unit name when it is
/// set, otherwise the file name without its extension. A library-mode
/// source file that is a .pas, .dpr, or .dpk uses that file name, so a
/// manifest row can match it. Empty for every other artefact.
/// </summary>
function ArtefactUnitName(const AArtefact: TArtefactInfo): string;

/// <summary>
/// Adds a unit-evidence artefact for a MAP unit that has no file, when that
/// unit matches a library row. Returns False when the name is empty, the
/// unit does not match a library, or an artefact for that unit is already
/// present. Units that do not match a library are left out.
/// </summary>
function TryAddNameOnlyLibraryUnit(const AManifest: TComponentManifest;
  const AUnitName, AOrigin, AEvidence, AConfidence: string;
  const AArtefacts: TArtefactList): Boolean;

/// <summary>
/// Groups artefacts that match a library row. Build mode matches
/// unit-evidence. Library mode matches a shipped .pas, .dpr, or .dpk.
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
/// An explicit supplier URL is not replaced by the manifest URL.
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
/// the manifest did not group, except a unit another unit uses. Each
/// library depends on its matched units.
/// </summary>
procedure AppendManifestDependenciesXml(ALines: TStrings; const AManifestJson: string;
  const AArtefacts: TArtefactList; const AProjectBomRef: string;
  AIndentLevel: Integer; const AUsesGraph: TUsesDependencyGraph;
  const ACovered: TArray<Boolean>; const AOutputFilePath: string = '');

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
  System.StrUtils,
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
  /// Practical SPDX identifier subset. A listed value is classified as an
  /// SPDX identifier. Anything else becomes a name.
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

  // CycloneDX 1.6 XSD simple type "cpe", anchored so the whole string must
  // match. The schema accepts a CPE 2.3 formatted string and a CPE 2.2 URI.
  // A single quote in the 2.3 pattern is written twice because this is a
  // Pascal string. The 2.3 literal is split: one Pascal string literal
  // cannot be longer than 255 characters.
  scCpe23Pattern =
    '^cpe:2\.3:[aho\*\-](:(((\?*|\*?)([a-zA-Z0-9\-\._]|(\\[\\\*\?!"#$$%&''\(\)\+,/:;<=>@\[\]\^`\{\|}~]))+(\?*|\*?))|[\*\-])){5}' +
    '(:(([a-zA-Z]{2,3}(-([a-zA-Z]{2}|[0-9]{3}))?)|[\*\-]))(:(((\?*|\*?)([a-zA-Z0-9\-\._]|(\\[\\\*\?!"#$$%&''\(\)\+,/:;<=>@\[\]\^`\{\|}~]))+(\?*|\*?))|[\*\-])){4}$';
  scCpe22Pattern = '^[c][pP][eE]:/[AHOaho]?(:[A-Za-z0-9\._\-~%]*){0,6}$';

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

function IsKnownSpdxId(const AToken: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(cKnownSpdxIds) to High(cKnownSpdxIds) do
    if SameText(AToken, cKnownSpdxIds[I]) then
      Exit(True);
end;

function IsLicenseRefToken(const AToken: string): Boolean;
const
  cPrefix = 'LicenseRef-';
var
  LRest: string;
  LIndex: Integer;
begin
  Result := False;
  if not StartsText(cPrefix, AToken) then
    Exit;
  LRest := Copy(AToken, Length(cPrefix) + 1, MaxInt);
  if LRest = '' then
    Exit;
  for LIndex := 1 to Length(LRest) do
    if not CharInSet(LRest[LIndex], ['A'..'Z', 'a'..'z', '0'..'9', '.', '-']) then
      Exit;
  Result := True;
end;

function IsSpdxLicenceExpression(const AValue: string): Boolean;
var
  LPos: Integer;
  LOperators: Integer;

  function ParseExpr: Boolean; forward;

  procedure SkipSpace;
  begin
    while (LPos <= Length(AValue)) and (AValue[LPos] = ' ') do
      Inc(LPos);
  end;

  function AtEnd: Boolean;
  begin
    Result := LPos > Length(AValue);
  end;

  function StartsWithWord(const AWord: string): Boolean;
  var
    LNext: Integer;
  begin
    Result := False;
    if not StartsText(AWord, Copy(AValue, LPos, Length(AWord))) then
      Exit;
    LNext := LPos + Length(AWord);
    // "or" inside a longer token, such as GPL-2.0-or-later, is not an operator.
    if (LNext <= Length(AValue)) and CharInSet(AValue[LNext],
      ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', '+']) then
      Exit;
    Result := True;
  end;

  function TakeOperator: Boolean;
  var
    LMark: Integer;
  begin
    LMark := LPos;
    SkipSpace;
    if StartsWithWord('OR') then
      Inc(LPos, 2)
    else if StartsWithWord('AND') then
      Inc(LPos, 3)
    else if StartsWithWord('WITH') then
      Inc(LPos, 4)
    else
    begin
      LPos := LMark;
      Exit(False);
    end;
    Result := True;
  end;

  function ReadToken: string;
  var
    LStart: Integer;
  begin
    LStart := LPos;
    while (LPos <= Length(AValue)) and CharInSet(AValue[LPos],
      ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', '+']) do
      Inc(LPos);
    Result := Copy(AValue, LStart, LPos - LStart);
  end;

  function ParseOperand: Boolean;
  var
    LToken: string;
  begin
    SkipSpace;
    if AtEnd then
      Exit(False);
    if AValue[LPos] = '(' then
    begin
      Inc(LPos);
      Result := ParseExpr;
      SkipSpace;
      if AtEnd or (AValue[LPos] <> ')') then
        Exit(False);
      Inc(LPos);
      Exit;
    end;
    LToken := ReadToken;
    Result := (LToken <> '') and (IsKnownSpdxId(LToken) or IsLicenseRefToken(LToken));
  end;

  function ParseExpr: Boolean;
  begin
    Result := ParseOperand;
    while Result and TakeOperator do
    begin
      Inc(LOperators);
      Result := ParseOperand;
    end;
  end;

begin
  // A single id, including one wrapped in parentheses, is not an expression.
  LPos := 1;
  LOperators := 0;
  Result := ParseExpr;
  SkipSpace;
  Result := Result and AtEnd and (LOperators > 0);
end;

function ClassifyLicence(const AValue: string; out ANormalised: string): TLicenceKind;
var
  I: Integer;
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

  // "Freeware with source" and "Free and open" contain the operator words
  // but the operands are not SPDX ids, so they stay names and are sanitized.
  if IsSpdxLicenceExpression(ANormalised) then
    Exit(lkExpression);

  Result := lkName;
end;

function ClassifyCpe(const AValue: string): TCpeKind;
begin
  // Checked in this order so a formatted string is not read as a URI.
  // The two shapes do not overlap: 2.3 starts with "cpe:2.3:" and 2.2
  // starts with "cpe:/".
  if (AValue <> '') and TRegEx.IsMatch(AValue, scCpe23Pattern) then
    Exit(ckCpe23);
  if (AValue <> '') and TRegEx.IsMatch(AValue, scCpe22Pattern) then
    Exit(ckCpe22);
  Result := ckNone;
end;

function SpdxCpeReferenceType(AKind: TCpeKind): string;
begin
  case AKind of
    ckCpe23: Result := 'cpe23Type';
    ckCpe22: Result := 'cpe22Type';
  else
    Result := '';
  end;
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

function IsShippedPascalFile(const AArtefact: TArtefactInfo): Boolean;
var
  LExt: string;
begin
  Result := False;
  if not AArtefact.LibrarySourceFile then
    Exit;
  LExt := TPath.GetExtension(AArtefact.RelativePath);
  if LExt = '' then
    LExt := TPath.GetExtension(AArtefact.FilePath);
  Result := SameText(LExt, '.pas') or SameText(LExt, '.dpr') or
    SameText(LExt, '.dpk');
end;

function ArtefactUnitName(const AArtefact: TArtefactInfo): string;

  function NameFromPath: string;
  begin
    Result := TPath.GetFileNameWithoutExtension(AArtefact.RelativePath);
    if Result = '' then
      Result := TPath.GetFileNameWithoutExtension(AArtefact.FilePath);
  end;

begin
  Result := '';
  if SameText(AArtefact.ArtefactType, 'unit-evidence') then
  begin
    Result := Trim(AArtefact.UnitName);
    if Result <> '' then
      Exit;
    Exit(NameFromPath);
  end;

  // Library mode lists shipped source as type file. The manifest matches a
  // .pas, .dpr, or .dpk by the file name, the same name the uses graph uses.
  if IsShippedPascalFile(AArtefact) then
    Result := NameFromPath;
end;

function ArtefactFolderPath(const AArtefact: TArtefactInfo): string;
begin
  // The .pas the resolver recorded. A DCU in the output folder is not a
  // package folder: without a source path, folder rules do not match it.
  // A shipped .pas, .dpr, or .dpk uses its file path the same way.
  Result := Trim(AArtefact.SourcePath);
  if Result <> '' then
    Exit;
  if SameText(TPath.GetExtension(AArtefact.FilePath), '.pas') or
    IsShippedPascalFile(AArtefact) then
    Result := AArtefact.FilePath;
end;

function ArtefactMatchPath(const AManifest: TComponentManifest;
  const AArtefact: TArtefactInfo): string;
begin
  Result := ArtefactFolderPath(AArtefact);
  if Result <> '' then
    Exit;
  // A product DCU, such as lib\Win32\release, is the file the prefix veto
  // has to see. An output DCU is not a product path, so it stays out.
  if IsEmbarcaderoProductPath(AArtefact.FilePath, AManifest.InstallRoot) then
    Result := Trim(AArtefact.FilePath);
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
    // Commercial is a plain name the manifest accepts on purpose.
    // LicenseRef- is already an SPDX licence reference, in any letter
    // case. The README and the header dialog suggest LicenseRef-Proprietary,
    // so that form must not raise the unrecognised-identifier warning.
    if (LKind = lkName) and not SameText(Result.Licence, 'Commercial') and
      not StartsText('LicenseRef-', Trim(Result.Licence)) then
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

  LStatus := ReadJsonText(AObject, 'copyright', Result.Copyright);
  if LStatus = jtsWrongType then
    AddWarning(AWarnings, LContext + ': "copyright" should be a string and was ignored');

  // A blank cpe is the same as leaving the field out. A non-string is
  // ignored. A string that is neither CPE form is omitted and the row
  // still matches. The run is not failed.
  LStatus := ReadJsonText(AObject, 'cpe', Result.Cpe);
  if LStatus = jtsWrongType then
  begin
    Result.Cpe := '';
    AddWarning(AWarnings, LContext + ': "cpe" should be a string and was ignored');
  end
  else if (Result.Cpe <> '') and (ClassifyCpe(Result.Cpe) = ckNone) then
  begin
    AddWarning(AWarnings, LContext + ': "cpe" "' + Result.Cpe +
      '" is not a CPE 2.3 formatted string (cpe:2.3:part:vendor:product:version:...) ' +
      'or a CPE 2.2 URI (cpe:/part:vendor:product:version:...) and was omitted');
    Result.Cpe := '';
  end;

  Result.Prefixes := ReadStringArray(AObject, 'units_prefix', LContext, AWarnings);
  Result.ExactUnits := ReadStringArray(AObject, 'units_exact', LContext, AWarnings);
  Result.ExcludeUnits := ReadStringArray(AObject, 'units_exclude', LContext, AWarnings);
  Result.Folders := ReadStringArray(AObject, 'units_folder', LContext, AWarnings);

  if (Length(Result.Prefixes) = 0) and (Length(Result.ExactUnits) = 0) and
    (Length(Result.Folders) = 0) then
    AddWarning(AWarnings, LContext +
      ': no units_prefix, units_exact, or units_folder; this row will not match any unit');
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
  LMatchValue: TJSONValue;
  LText: string;
  I, J: Integer;
  LContext: string;
  LPrefix: string;
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
  AManifest.OwnCodeFolders := ReadStringArray(ARoot, 'own_code_folders', 'Manifest', AWarnings);
  for I := 0 to High(AManifest.OwnCodePrefixes) do
    if Length(AManifest.OwnCodePrefixes[I]) < cMinPrefixLength then
      AddWarning(AWarnings, 'own_code_prefixes: prefix "' + AManifest.OwnCodePrefixes[I] +
        '" is shorter than 3 characters');

  // match.prefixes is optional. A missing value stays corroborated, which
  // is the zero value of PrefixMode.
  LMatchValue := ARoot.GetValue('match');
  if (LMatchValue <> nil) and not (LMatchValue is TJSONNull) then
  begin
    if not (LMatchValue is TJSONObject) then
      AddWarning(AWarnings, 'match should be an object and was ignored')
    else
    begin
      LStatus := ReadJsonText(TJSONObject(LMatchValue), 'prefixes', LText);
      if LStatus = jtsWrongType then
        AddWarning(AWarnings, 'match.prefixes should be a string and was ignored')
      else if LStatus = jtsValue then
      begin
        if SameText(LText, 'legacy') then
          AManifest.PrefixMode := pmmLegacy
        else if SameText(LText, 'corroborated') then
          AManifest.PrefixMode := pmmCorroborated
        else
          AddWarning(AWarnings, 'match.prefixes "' + LText +
            '" is not corroborated or legacy. corroborated is used');
      end;
    end;
  end;

  // Written by the engine onto the in-memory copy. Not a components-file field.
  LStatus := ReadJsonText(ARoot, 'dxInstallRoot', LText);
  if LStatus = jtsValue then
    AManifest.InstallRoot := LText;

  for I := 0 to High(AManifest.Components) do
  begin
    if AManifest.Components[I].Name <> '' then
      LContext := 'Component[' + IntToStr(I) + '] "' + AManifest.Components[I].Name + '"'
    else
      LContext := 'Component[' + IntToStr(I) + ']';
    for J := 0 to High(AManifest.Components[I].Prefixes) do
    begin
      LPrefix := AManifest.Components[I].Prefixes[J];
      if Length(LPrefix) < cMinPrefixLength then
      begin
        if AManifest.PrefixMode = pmmLegacy then
          AddWarning(AWarnings, LContext + ': prefix "' + LPrefix +
            '" is shorter than 3 characters. It is still applied. Use units_exclude ' +
            'to leave out units of other libraries that start with it')
        else
          AddWarning(AWarnings, LContext + ': prefix "' + LPrefix +
            '" is shorter than 3 characters. It is not applied. Use units_folder or units_exact');
      end
      else if (AManifest.PrefixMode = pmmCorroborated) and (Pos('.', LPrefix) = 0) then
        AddWarning(AWarnings, LContext + ': prefix "' + LPrefix +
          '" has no dot. It is not applied on its own. Use units_folder or units_exact. ' +
          'For this release, match.prefixes legacy still applies it outside an Embarcadero product path');
    end;
  end;
end;

function BaseDirFromSourceName(const ASourceName: string): string;
var
  LName, LFull: string;
begin
  Result := '';
  LName := Trim(ASourceName);
  if LName = '' then
    Exit;
  // A label such as "test" is not a file location. A path has a separator
  // or a root (a drive, or a UNC share).
  if (Pos('\', LName) = 0) and (Pos('/', LName) = 0) and
    not TPath.IsPathRooted(LName) then
    Exit;
  try
    LFull := TPath.GetFullPath(LName);
  except
    Exit;
  end;
  Result := TPath.GetDirectoryName(LFull);
end;

function TryNormalizeFullPath(const APath: string; out AFull: string): Boolean;
begin
  AFull := '';
  Result := False;
  if Trim(APath) = '' then
    Exit;
  try
    AFull := TPath.GetFullPath(APath);
    Result := AFull <> '';
  except
    Result := False;
  end;
end;

/// A folder matches a file inside it or inside a subfolder. A sibling whose
/// name only starts with the folder name does not match.
function FileIsInsideFolder(const AFileFull, AFolderFull: string): Boolean;
var
  LFolder, LFile: string;
begin
  Result := False;
  if (Trim(AFileFull) = '') or (Trim(AFolderFull) = '') then
    Exit;
  LFolder := IncludeTrailingPathDelimiter(LowerCase(
    ExcludeTrailingPathDelimiter(AFolderFull)));
  LFile := LowerCase(ExcludeTrailingPathDelimiter(AFileFull));
  Result := LFile.StartsWith(LFolder);
end;

function TryAcceptFolder(const AText, ABaseDir: string;
  out AFull, AWarning: string): Boolean;
var
  LText, LCombined: string;
begin
  AFull := '';
  AWarning := '';
  Result := False;
  LText := Trim(AText);
  if LText = '' then
    Exit;

  if TPath.IsRelativePath(LText) then
  begin
    if Trim(ABaseDir) = '' then
    begin
      AWarning := 'relative path "' + LText +
        '" was not applied because the manifest file location is unknown';
      Exit;
    end;
    LCombined := TPath.Combine(ABaseDir, LText);
  end
  else
    LCombined := LText;

  if not TryNormalizeFullPath(LCombined, AFull) then
  begin
    AWarning := 'path "' + LText + '" could not be resolved and was not applied';
    AFull := '';
    Exit;
  end;
  AFull := ExcludeTrailingPathDelimiter(AFull);

  if TDirectory.Exists(AFull) then
    Exit(True);

  if TFile.Exists(AFull) then
  begin
    AWarning := 'path "' + LText + '" is a file, not a folder, and was not applied';
    AFull := '';
    Exit;
  end;

  // The directory is missing. The rule stays, so a unit whose source path
  // is under that folder still matches. The warning names the typo.
  if SameText(AFull, ExcludeTrailingPathDelimiter(LText)) then
    AWarning := 'folder "' + LText + '" was not found. It is still applied'
  else
    AWarning := 'folder "' + LText + '" was not found (' + AFull +
      '). It is still applied';
  Result := True;
end;

procedure ResolveFolderList(const ARaw: TArray<string>; const ABaseDir, AContext,
  AField: string; AWarnings: TList<string>; out AResolved: TArray<string>);
var
  LList: TList<string>;
  LFull, LWarning: string;
  I: Integer;
begin
  LList := TList<string>.Create;
  try
    for I := 0 to High(ARaw) do
    begin
      if TryAcceptFolder(ARaw[I], ABaseDir, LFull, LWarning) then
        LList.Add(LFull);
      if LWarning <> '' then
        AddWarning(AWarnings, AContext + ': ' + AField + ': ' + LWarning);
    end;
    AResolved := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function ComponentFolderContext(const AEntry: TComponentEntry; AIndex: Integer): string;
begin
  if Trim(AEntry.Name) <> '' then
    Result := Format('Component[%d] "%s"', [AIndex, AEntry.Name])
  else
    Result := Format('Component[%d]', [AIndex]);
end;

procedure ResolveManifestFolders(var AManifest: TComponentManifest;
  AWarnings: TList<string>; const ABaseDir: string);
var
  I: Integer;
  LEntry: TComponentEntry;
  LResolved: TArray<string>;
begin
  for I := 0 to High(AManifest.Components) do
  begin
    // Copy the record out and back. Assigning a field of a dynamic-array
    // element is easy to get wrong, and this stays correct either way.
    LEntry := AManifest.Components[I];
    ResolveFolderList(LEntry.Folders, ABaseDir, ComponentFolderContext(LEntry, I),
      'units_folder', AWarnings, LResolved);
    LEntry.Folders := LResolved;
    AManifest.Components[I] := LEntry;
  end;
  ResolveFolderList(AManifest.OwnCodeFolders, ABaseDir, 'Manifest',
    'own_code_folders', AWarnings, LResolved);
  AManifest.OwnCodeFolders := LResolved;
end;

function RewriteFolderArray(AArray: TJSONArray; const ABaseDir: string;
  out AChanged: Boolean): TJSONArray;
var
  I: Integer;
  LText, LFull, LWarning: string;
  LCopy: TJSONValue;
begin
  AChanged := False;
  Result := TJSONArray.Create;
  for I := 0 to AArray.Count - 1 do
  begin
    if AArray.Items[I] is TJSONString then
    begin
      LText := AArray.Items[I].Value;
      if TryAcceptFolder(LText, ABaseDir, LFull, LWarning) then
      begin
        if not SameText(LText, LFull) then
          AChanged := True;
        Result.Add(LFull);
      end
      else
        Result.Add(LText);
    end
    else
    begin
      LCopy := TJSONObject.ParseJSONValue(AArray.Items[I].Format(0));
      // Add accepts a string, a number, or an object. A copied TJSONValue
      // goes through AddElement, which takes ownership of it.
      if LCopy <> nil then
        Result.AddElement(LCopy);
    end;
  end;
end;

procedure RewriteFolderField(AObject: TJSONObject; const AName, ABaseDir: string;
  var AChanged: Boolean);
var
  LValue: TJSONValue;
  LNew: TJSONArray;
  LFieldChanged: Boolean;
  LPair: TJSONPair;
begin
  LValue := AObject.GetValue(AName);
  if not (LValue is TJSONArray) then
    Exit;
  LNew := RewriteFolderArray(TJSONArray(LValue), ABaseDir, LFieldChanged);
  if not LFieldChanged then
  begin
    LNew.Free;
    Exit;
  end;
  LPair := AObject.RemovePair(AName);
  LPair.Free;
  AObject.AddPair(AName, LNew);
  AChanged := True;
end;

procedure RewriteFolderFields(AValue: TJSONValue; const ABaseDir: string;
  var AChanged: Boolean);
var
  I: Integer;
  LArray: TJSONArray;
  LComponents: TJSONValue;
begin
  if AValue is TJSONArray then
  begin
    // A bare array is the component list.
    LArray := TJSONArray(AValue);
    for I := 0 to LArray.Count - 1 do
      if LArray.Items[I] is TJSONObject then
        RewriteFolderField(TJSONObject(LArray.Items[I]), 'units_folder',
          ABaseDir, AChanged);
  end
  else if AValue is TJSONObject then
  begin
    RewriteFolderField(TJSONObject(AValue), 'own_code_folders', ABaseDir, AChanged);
    LComponents := TJSONObject(AValue).GetValue('components');
    if LComponents <> nil then
      RewriteFolderFields(LComponents, ABaseDir, AChanged);
  end;
end;

function ManifestJsonWithAbsoluteFolders(const AJson, ABaseDir: string): string;
var
  LValue: TJSONValue;
  LChanged: Boolean;
begin
  Result := AJson;
  if Trim(ABaseDir) = '' then
    Exit;
  if (Pos('units_folder', LowerCase(AJson)) = 0) and
    (Pos('own_code_folders', LowerCase(AJson)) = 0) then
    Exit;

  LValue := TJSONObject.ParseJSONValue(AJson);
  if LValue = nil then
    Exit;
  try
    LChanged := False;
    RewriteFolderFields(LValue, ABaseDir, LChanged);
    if LChanged then
      Result := LValue.Format(0);
  finally
    LValue.Free;
  end;
end;

type
  /// <summary>
  /// Finds the first JSON syntax error so a bad components file can name
  /// the line and the column. System.JSON drops that position when it
  /// returns nil.
  /// </summary>
  TJsonSyntaxScan = class
  private
    FText: string;
    FPos: Integer;
    FLine: Integer;
    FCol: Integer;
    FFailed: Boolean;
    FErrLine: Integer;
    FErrCol: Integer;
    function AtEnd: Boolean;
    function Cur: Char;
    procedure Advance;
    procedure Fail;
    procedure SkipWs;
    procedure ParseValue;
    procedure ParseObject;
    procedure ParseArray;
    procedure ParseString;
    procedure ParseNumber;
    procedure ParseLiteral(const ALiteral: string);
    function IsDigit(AChar: Char): Boolean;
    function IsIdentChar(AChar: Char): Boolean;
  public
    constructor Create(const AText: string);
    procedure Run;
    function HasError: Boolean;
    function ErrorLine: Integer;
    function ErrorColumn: Integer;
  end;

constructor TJsonSyntaxScan.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  FLine := 1;
  FCol := 1;
  FErrLine := 1;
  FErrCol := 1;
  if (FText <> '') and (FText[1] = #$FEFF) then
    FPos := 2;
end;

function TJsonSyntaxScan.AtEnd: Boolean;
begin
  Result := FPos > Length(FText);
end;

function TJsonSyntaxScan.Cur: Char;
begin
  if AtEnd then
    Result := #0
  else
    Result := FText[FPos];
end;

function TJsonSyntaxScan.IsDigit(AChar: Char): Boolean;
begin
  Result := (AChar >= '0') and (AChar <= '9');
end;

function TJsonSyntaxScan.IsIdentChar(AChar: Char): Boolean;
begin
  Result := ((AChar >= 'A') and (AChar <= 'Z')) or
    ((AChar >= 'a') and (AChar <= 'z')) or IsDigit(AChar) or (AChar = '_');
end;

procedure TJsonSyntaxScan.Advance;
begin
  if AtEnd then
    Exit;
  if FText[FPos] = #13 then
  begin
    Inc(FPos);
    if (not AtEnd) and (FText[FPos] = #10) then
      Inc(FPos);
    Inc(FLine);
    FCol := 1;
  end
  else if FText[FPos] = #10 then
  begin
    Inc(FPos);
    Inc(FLine);
    FCol := 1;
  end
  else
  begin
    Inc(FPos);
    Inc(FCol);
  end;
end;

procedure TJsonSyntaxScan.Fail;
begin
  if FFailed then
    Exit;
  FFailed := True;
  FErrLine := FLine;
  FErrCol := FCol;
end;

procedure TJsonSyntaxScan.SkipWs;
begin
  while (not AtEnd) and ((Cur = ' ') or (Cur = #9) or (Cur = #10) or (Cur = #13)) do
    Advance;
end;

procedure TJsonSyntaxScan.ParseLiteral(const ALiteral: string);
var
  I: Integer;
begin
  if FFailed then
    Exit;
  for I := 1 to Length(ALiteral) do
  begin
    if AtEnd or (Cur <> ALiteral[I]) then
    begin
      Fail;
      Exit;
    end;
    Advance;
  end;
  if (not AtEnd) and IsIdentChar(Cur) then
    Fail;
end;

procedure TJsonSyntaxScan.ParseNumber;
begin
  if FFailed then
    Exit;
  if (not AtEnd) and (Cur = '-') then
    Advance;
  if AtEnd or not IsDigit(Cur) then
  begin
    Fail;
    Exit;
  end;
  while (not AtEnd) and IsDigit(Cur) do
    Advance;
  if (not AtEnd) and (Cur = '.') then
  begin
    Advance;
    if AtEnd or not IsDigit(Cur) then
    begin
      Fail;
      Exit;
    end;
    while (not AtEnd) and IsDigit(Cur) do
      Advance;
  end;
  if (not AtEnd) and ((Cur = 'e') or (Cur = 'E')) then
  begin
    Advance;
    if (not AtEnd) and ((Cur = '+') or (Cur = '-')) then
      Advance;
    if AtEnd or not IsDigit(Cur) then
    begin
      Fail;
      Exit;
    end;
    while (not AtEnd) and IsDigit(Cur) do
      Advance;
  end;
end;

procedure TJsonSyntaxScan.ParseString;
var
  LHex: Integer;
begin
  if FFailed then
    Exit;
  if AtEnd or (Cur <> '"') then
  begin
    Fail;
    Exit;
  end;
  Advance;
  while not AtEnd do
  begin
    if Cur = '"' then
    begin
      Advance;
      Exit;
    end;
    if (Cur = #10) or (Cur = #13) then
    begin
      Fail;
      Exit;
    end;
    if Cur = '\' then
    begin
      Advance;
      if AtEnd then
      begin
        Fail;
        Exit;
      end;
      if Cur = 'u' then
      begin
        Advance;
        for LHex := 1 to 4 do
        begin
          if AtEnd or not (IsDigit(Cur) or
            ((Cur >= 'a') and (Cur <= 'f')) or
            ((Cur >= 'A') and (Cur <= 'F'))) then
          begin
            Fail;
            Exit;
          end;
          Advance;
        end;
      end
      else
        Advance;
      Continue;
    end;
    Advance;
  end;
  Fail;
end;

procedure TJsonSyntaxScan.ParseObject;
begin
  if FFailed then
    Exit;
  Advance;
  SkipWs;
  if (not AtEnd) and (Cur = '}') then
  begin
    Advance;
    Exit;
  end;
  while not FFailed do
  begin
    if AtEnd or (Cur <> '"') then
    begin
      Fail;
      Exit;
    end;
    ParseString;
    if FFailed then
      Exit;
    SkipWs;
    if AtEnd or (Cur <> ':') then
    begin
      Fail;
      Exit;
    end;
    Advance;
    ParseValue;
    if FFailed then
      Exit;
    SkipWs;
    if AtEnd then
    begin
      Fail;
      Exit;
    end;
    if Cur = '}' then
    begin
      Advance;
      Exit;
    end;
    if Cur <> ',' then
    begin
      Fail;
      Exit;
    end;
    Advance;
    SkipWs;
  end;
end;

procedure TJsonSyntaxScan.ParseArray;
begin
  if FFailed then
    Exit;
  Advance;
  SkipWs;
  if (not AtEnd) and (Cur = ']') then
  begin
    Advance;
    Exit;
  end;
  while not FFailed do
  begin
    ParseValue;
    if FFailed then
      Exit;
    SkipWs;
    if AtEnd then
    begin
      Fail;
      Exit;
    end;
    if Cur = ']' then
    begin
      Advance;
      Exit;
    end;
    if Cur <> ',' then
    begin
      Fail;
      Exit;
    end;
    Advance;
    SkipWs;
  end;
end;

procedure TJsonSyntaxScan.ParseValue;
begin
  if FFailed then
    Exit;
  SkipWs;
  if AtEnd then
  begin
    Fail;
    Exit;
  end;
  case Cur of
    '{': ParseObject;
    '[': ParseArray;
    '"': ParseString;
    't': ParseLiteral('true');
    'f': ParseLiteral('false');
    'n': ParseLiteral('null');
    '-', '0'..'9': ParseNumber;
  else
    Fail;
  end;
end;

procedure TJsonSyntaxScan.Run;
begin
  ParseValue;
  if FFailed then
    Exit;
  SkipWs;
  if not AtEnd then
    Fail;
end;

function TJsonSyntaxScan.HasError: Boolean;
begin
  Result := FFailed;
end;

function TJsonSyntaxScan.ErrorLine: Integer;
begin
  Result := FErrLine;
end;

function TJsonSyntaxScan.ErrorColumn: Integer;
begin
  Result := FErrCol;
end;

function DescribeInvalidJson(const AJson, ASourceName: string): string;
var
  LScan: TJsonSyntaxScan;
begin
  LScan := TJsonSyntaxScan.Create(AJson);
  try
    LScan.Run;
    if LScan.HasError then
    begin
      if ASourceName = '' then
        Result := 'Invalid JSON at line ' + IntToStr(LScan.ErrorLine) +
          ', position ' + IntToStr(LScan.ErrorColumn)
      else
        Result := 'Invalid JSON in "' + ASourceName + '" at line ' +
          IntToStr(LScan.ErrorLine) + ', position ' + IntToStr(LScan.ErrorColumn);
    end
    else if ASourceName = '' then
      Result := 'Invalid JSON'
    else
      Result := 'Invalid JSON in "' + ASourceName + '"';
  finally
    LScan.Free;
  end;
end;

procedure WarnSharedPrefixes(const AManifest: TComponentManifest;
  AWarnings: TList<string>);
var
  LOrder: TList<string>;
  LGroups: TObjectDictionary<string, TList<Integer>>;
  LShown: TDictionary<string, string>;
  LIndexes: TList<Integer>;
  LNames: TArray<string>;
  LKey: string;
  I, J: Integer;

  function ComponentLabel(AIndex: Integer): string;
  begin
    Result := Trim(AManifest.Components[AIndex].Name);
    if Result = '' then
      Result := 'component[' + IntToStr(AIndex) + ']'
    else
      Result := '"' + Result + '"';
  end;

  function JoinLabels(const ALabels: TArray<string>): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to High(ALabels) do
    begin
      if K = 0 then
        Result := ALabels[K]
      else if K = High(ALabels) then
        Result := Result + ' and ' + ALabels[K]
      else
        Result := Result + ', ' + ALabels[K];
    end;
  end;

begin
  LOrder := TList<string>.Create;
  LGroups := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  LShown := TDictionary<string, string>.Create;
  try
    for I := 0 to High(AManifest.Components) do
      for J := 0 to High(AManifest.Components[I].Prefixes) do
      begin
        LKey := LowerCase(AManifest.Components[I].Prefixes[J]);
        if LKey = '' then
          Continue;
        if not LGroups.TryGetValue(LKey, LIndexes) then
        begin
          LIndexes := TList<Integer>.Create;
          LGroups.Add(LKey, LIndexes);
          LOrder.Add(LKey);
          LShown.Add(LKey, AManifest.Components[I].Prefixes[J]);
        end;
        if LIndexes.IndexOf(I) < 0 then
          LIndexes.Add(I);
      end;

    for I := 0 to LOrder.Count - 1 do
    begin
      LKey := LOrder[I];
      LIndexes := LGroups[LKey];
      if LIndexes.Count < 2 then
        Continue;
      SetLength(LNames, LIndexes.Count);
      for J := 0 to LIndexes.Count - 1 do
        LNames[J] := ComponentLabel(LIndexes[J]);
      AddWarning(AWarnings, 'units_prefix "' + LShown[LKey] +
        '" is shared by ' + JoinLabels(LNames) +
        '. Units that start with it are assigned to ' + LNames[0] +
        ', the first row in the file. Use units_exact or a more specific ' +
        'units_prefix for the other rows.');
    end;
  finally
    LShown.Free;
    LGroups.Free;
    LOrder.Free;
  end;
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
    AError := DescribeInvalidJson(AJson, ASourceName);
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
      AManifest.SourcePath := ASourceName;
      WarnSharedPrefixes(AManifest, LWarnings);
      // Relative folders are resolved from the components file. A label such
      // as "test" has no directory, so only absolute folders apply then.
      ResolveManifestFolders(AManifest, LWarnings, BaseDirFromSourceName(ASourceName));
      AManifest.Warnings := LWarnings.ToArray;
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
  // Writers parse this text again, without the file path. Absolute folders
  // still match. The file on disk is left as the caller wrote it.
  if Result then
    AJson := ManifestJsonWithAbsoluteFolders(AJson,
      BaseDirFromSourceName(AFilePath));
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

function ProductPathIsUnder(const APath, ABaseDirectory: string): Boolean;
var
  LBase: string;
  LPath: string;
begin
  Result := False;
  if (Trim(APath) = '') or (Trim(ABaseDirectory) = '') then
    Exit;
  try
    LBase := IncludeTrailingPathDelimiter(LowerCase(TPath.GetFullPath(ABaseDirectory)));
    LPath := LowerCase(TPath.GetFullPath(APath));
  except
    Exit;
  end;
  Result := LPath.StartsWith(LBase) or
    SameText(ExcludeTrailingPathDelimiter(LBase), LPath);
end;

function ProductFirstSegment(const APath, ABaseDirectory: string;
  out AName: string; out AHasMore: Boolean): Boolean;
var
  LBase: string;
  LPath: string;
  LRest: string;
  LSlash: Integer;
begin
  AName := '';
  AHasMore := False;
  Result := False;
  if not ProductPathIsUnder(APath, ABaseDirectory) then
    Exit;
  try
    LBase := ExcludeTrailingPathDelimiter(LowerCase(TPath.GetFullPath(ABaseDirectory)));
    LPath := LowerCase(TPath.GetFullPath(APath));
  except
    Exit;
  end;
  if Length(LPath) <= Length(LBase) then
    Exit;
  LRest := Copy(LPath, Length(LBase) + 1, MaxInt);
  if LRest.StartsWith('\') or LRest.StartsWith('/') then
    LRest := Copy(LRest, 2, MaxInt);
  if LRest = '' then
    Exit;
  LSlash := Pos('\', LRest);
  if LSlash = 0 then
    LSlash := Pos('/', LRest);
  if LSlash = 0 then
    AName := LRest
  else
  begin
    AName := Copy(LRest, 1, LSlash - 1);
    AHasMore := Length(LRest) > LSlash;
  end;
  Result := AName <> '';
end;

function IsProductSourcePath(const APath, ARootDir: string): Boolean;
const
  // First-level folders of the product source tree. A library copied into
  // source\, or installed under Extras or CatalogRepository, is not here.
  cSourceFolders: array[0..23] of string = (
    'rtl', 'vcl', 'fmx', 'data', 'databinding', 'dataexplorer',
    'dunit', 'dunitx', 'experts', 'flatbox2d', 'ibx',
    'indy', 'indy10', 'indyimpl', 'internet', 'property editors',
    'soap', 'tethering', 'toolsapi', 'visualizers', 'xml',
    'db', 'websnap', 'clx');
var
  I: Integer;
  LName: string;
  LHasMore: Boolean;
  LSource: string;
begin
  Result := False;
  LSource := TPath.Combine(ARootDir, 'source');
  if not ProductFirstSegment(APath, LSource, LName, LHasMore) then
    Exit;
  for I := Low(cSourceFolders) to High(cSourceFolders) do
    if SameText(LName, cSourceFolders[I]) then
      Exit(True);
end;

function IsProductLibPlatform(const AName: string): Boolean;
const
  cPlatforms: array[0..21] of string = (
    'win32', 'win64', 'win64x', 'winarm64',
    'linux32', 'linux64', 'linuxarm64',
    'osx32', 'osx64', 'osxarm64', 'macos64', 'macosarm64',
    'android', 'android32', 'android64',
    'iosdevice', 'iosdevice32', 'iosdevice64',
    'iossim32', 'iossim64', 'iossimarm64', 'iossimulator');
var
  I: Integer;
begin
  Result := False;
  for I := Low(cPlatforms) to High(cPlatforms) do
    if SameText(AName, cPlatforms[I]) then
      Exit(True);
end;

function IsProductLibPath(const APath, ARootDir: string): Boolean;
var
  LFirst: string;
  LFirstMore: Boolean;
  LSecond: string;
  LSecondMore: Boolean;
  LLib: string;
begin
  // Product DCUs live in lib\<platform>\release, lib\<platform>\debug,
  // directly in lib\<platform>, or (older installs) directly in lib.
  // lib\<package>\... is a library added under the install.
  Result := False;
  LLib := TPath.Combine(ARootDir, 'lib');
  if not ProductFirstSegment(APath, LLib, LFirst, LFirstMore) then
    Exit;
  if not LFirstMore then
    Exit(True);
  if SameText(LFirst, 'release') or SameText(LFirst, 'debug') then
    Exit(True);
  if not IsProductLibPlatform(LFirst) then
    Exit;
  if not ProductFirstSegment(APath, TPath.Combine(LLib, LFirst), LSecond, LSecondMore) then
    Exit;
  if SameText(LSecond, 'release') or SameText(LSecond, 'debug') then
    Exit(True);
  if not LSecondMore then
    Exit(True);
end;

function IsEmbarcaderoProductPath(const APath, AInstallRoot: string): Boolean;
begin
  Result := False;
  if (Trim(APath) = '') or (Trim(AInstallRoot) = '') then
    Exit;
  Result := IsProductSourcePath(APath, AInstallRoot) or
    IsProductLibPath(APath, AInstallRoot);
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

function IsExcludedUnit(const AEntry: TComponentEntry; const AUnitName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(AEntry.ExcludeUnits) do
    if SameText(AUnitName, AEntry.ExcludeUnits[I]) then
      Exit(True);
end;

procedure FindPrefix(const AManifest: TComponentManifest; const AUnitName: string;
  const AFullUnitName: string; out AIndex: Integer; out APrefix: string);
var
  I, J: Integer;
  LLower: string;
  LBestLength: Integer;
  LPrefix: string;
begin
  // The longest matching prefix wins, whatever the row order, so "Neslib.Xml"
  // beats "Neslib" (issue #129). A prefix matches the start of the unit name.
  // A trailing dot is not required. On equal length the first row wins.
  AIndex := -1;
  APrefix := '';
  LBestLength := 0;
  LLower := LowerCase(AUnitName);
  for I := 0 to High(AManifest.Components) do
  begin
    // units_exclude takes a unit out of this row's prefixes only. When the
    // name was shortened by its Delphi scope (Vcl.Skia to Skia), an entry
    // with the full name excludes it as well.
    if IsExcludedUnit(AManifest.Components[I], AUnitName) or
      ((AFullUnitName <> '') and IsExcludedUnit(AManifest.Components[I], AFullUnitName)) then
      Continue;
    for J := 0 to High(AManifest.Components[I].Prefixes) do
    begin
      LPrefix := AManifest.Components[I].Prefixes[J];
      if (LPrefix <> '') and (Length(LPrefix) > LBestLength) and
        LLower.StartsWith(LowerCase(LPrefix)) then
      begin
        AIndex := I;
        APrefix := LPrefix;
        LBestLength := Length(LPrefix);
      end;
    end;
  end;
end;

function PrefixContainsDot(const APrefix: string): Boolean;
begin
  Result := Pos('.', APrefix) > 0;
end;

function PrefixMayAssign(const AManifest: TComponentManifest;
  const APrefix, ASourcePath: string): Boolean;
begin
  // A product shipped path contradicts a third-party prefix. The file wins
  // over the name in both modes. A stronger rule is decided before this.
  if IsEmbarcaderoProductPath(ASourcePath, AManifest.InstallRoot) then
    Exit(False);
  if AManifest.PrefixMode = pmmLegacy then
    Exit(True);
  Result := PrefixContainsDot(APrefix);
end;

procedure SelectPrefix(const AManifest: TComponentManifest; const AUnitName,
  AStripped: string; out AIndex: Integer; out APrefix: string);
var
  LIndex: Integer;
  LPrefix: string;
begin
  // The name as written wins over the scope-stripped name when both match,
  // which is the order MatchManifestUnit already used.
  FindPrefix(AManifest, AUnitName, '', AIndex, APrefix);
  if (AIndex < 0) and not SameText(AStripped, AUnitName) then
  begin
    FindPrefix(AManifest, AStripped, AUnitName, LIndex, LPrefix);
    AIndex := LIndex;
    APrefix := LPrefix;
  end;
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

function FolderIsExcluded(const AEntry: TComponentEntry; const AUnitName,
  AStripped: string): Boolean;
begin
  // The same names units_exclude already uses for prefixes: the unit as
  // written, and the name with one Delphi scope removed.
  Result := IsExcludedUnit(AEntry, AUnitName);
  if Result then
    Exit;
  if not SameText(AStripped, AUnitName) then
    Result := IsExcludedUnit(AEntry, AStripped);
end;

procedure ConsiderFolder(const AFolderFull, AFileFull: string; ALength: Integer;
  var ABestLength: Integer; var ABestIndex: Integer; AIndex: Integer;
  var AOwnCode: Boolean; AIsOwnCode: Boolean);
begin
  if (ALength > ABestLength) and FileIsInsideFolder(AFileFull, AFolderFull) then
  begin
    ABestLength := ALength;
    ABestIndex := AIndex;
    AOwnCode := AIsOwnCode;
  end;
end;

function FindFolder(const AManifest: TComponentManifest; const AUnitName,
  AStripped, ASourcePath: string; out AOwnCode: Boolean): Integer;
var
  I, J: Integer;
  LFileFull: string;
  LBestLength, LLength: Integer;
  LFolder: string;
begin
  // Component folders are visited first, so on equal length a library wins
  // over an own-code folder and the first row wins. A longer path wins
  // either way, which is how a package checked into the source tree stays
  // a library and a patch folder under that package stays own code.
  Result := -1;
  AOwnCode := False;
  if not TryNormalizeFullPath(ASourcePath, LFileFull) then
    Exit;
  LBestLength := 0;

  for I := 0 to High(AManifest.Components) do
  begin
    if FolderIsExcluded(AManifest.Components[I], AUnitName, AStripped) then
      Continue;
    for J := 0 to High(AManifest.Components[I].Folders) do
    begin
      LFolder := AManifest.Components[I].Folders[J];
      LLength := Length(IncludeTrailingPathDelimiter(LFolder));
      ConsiderFolder(LFolder, LFileFull, LLength, LBestLength, Result, I, AOwnCode, False);
    end;
  end;

  for J := 0 to High(AManifest.OwnCodeFolders) do
  begin
    LFolder := AManifest.OwnCodeFolders[J];
    LLength := Length(IncludeTrailingPathDelimiter(LFolder));
    ConsiderFolder(LFolder, LFileFull, LLength, LBestLength, Result, -1, AOwnCode, True);
  end;
end;

function MatchManifestUnit(const AManifest: TComponentManifest;
  const AUnitName, ASourcePath: string): TManifestMatch;
var
  LStripped: string;
  LIndex: Integer;
  LOwnCode: Boolean;
  LPrefix: string;
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

  if Trim(ASourcePath) <> '' then
  begin
    LIndex := FindFolder(AManifest, AUnitName, LStripped, ASourcePath, LOwnCode);
    if LOwnCode then
    begin
      Result.Kind := mmOwnCode;
      Exit;
    end;
    if LIndex >= 0 then
    begin
      Result.Kind := mmLibrary;
      Result.ComponentIndex := LIndex;
      Exit;
    end;
  end;

  SelectPrefix(AManifest, AUnitName, LStripped, LIndex, LPrefix);
  if (LIndex >= 0) and PrefixMayAssign(AManifest, LPrefix, ASourcePath) then
  begin
    Result.Kind := mmLibrary;
    Result.ComponentIndex := LIndex;
    Exit;
  end;

  if IsOwnCodePrefix(AManifest, AUnitName) or
    ((not SameText(LStripped, AUnitName)) and IsOwnCodePrefix(AManifest, LStripped)) then
    Result.Kind := mmOwnCode;
end;

function ComponentRowName(const AManifest: TComponentManifest; AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(AManifest.Components)) and
    (Trim(AManifest.Components[AIndex].Name) <> '') then
    Result := AManifest.Components[AIndex].Name
  else
    Result := 'component[' + IntToStr(AIndex) + ']';
end;

function TryRejectedLibraryPrefix(const AManifest: TComponentManifest;
  const AUnitName, ASourcePath: string; out APrefix, ARowName: string): Boolean;
var
  LStripped: string;
  LIndex: Integer;
  LOwnCode: Boolean;
  LPrefix: string;
begin
  Result := False;
  APrefix := '';
  ARowName := '';
  if not AManifest.Loaded or (Trim(AUnitName) = '') then
    Exit;

  LStripped := StripDelphiScopePrefix(AUnitName);
  LIndex := FindExact(AManifest, AUnitName);
  if (LIndex < 0) and not SameText(LStripped, AUnitName) then
    LIndex := FindExact(AManifest, LStripped);
  if LIndex >= 0 then
    Exit;
  if IsListedOwnCode(AManifest, AUnitName) or
    ((not SameText(LStripped, AUnitName)) and IsListedOwnCode(AManifest, LStripped)) then
    Exit;
  if Trim(ASourcePath) <> '' then
  begin
    LIndex := FindFolder(AManifest, AUnitName, LStripped, ASourcePath, LOwnCode);
    if LOwnCode or (LIndex >= 0) then
      Exit;
  end;

  SelectPrefix(AManifest, AUnitName, LStripped, LIndex, LPrefix);
  if (LIndex < 0) or PrefixMayAssign(AManifest, LPrefix, ASourcePath) then
    Exit;
  APrefix := LPrefix;
  ARowName := ComponentRowName(AManifest, LIndex);
  Result := True;
end;

function RejectedPrefixLogLine(const AUnitName, APrefix, ARowName,
  AKeptOrigin: string): string;
var
  LOrigin: string;
begin
  LOrigin := Trim(AKeptOrigin);
  if LOrigin = '' then
    LOrigin := 'Unknown';
  Result := 'Prefix match not applied: unit ' + Trim(AUnitName) +
    ', prefix ' + APrefix + ', row ' + ARowName + ', kept origin ' + LOrigin;
end;

function RejectedPrefixLogLines(const AManifest: TComponentManifest;
  const AArtefacts: TArtefactList): TArray<string>;
var
  LLines: TList<string>;
  I: Integer;
  LPrefix: string;
  LRow: string;
  LName: string;
begin
  Result := nil;
  if not AManifest.Loaded or not Assigned(AArtefacts) then
    Exit;
  LLines := TList<string>.Create;
  try
    for I := 0 to AArtefacts.Count - 1 do
    begin
      // ArtefactUnitName is empty unless this is unit-evidence or a shipped
      // .pas, .dpr, or .dpk. Library mode uses the file type, so a type
      // check for unit-evidence would drop the product-path veto log.
      LName := ArtefactUnitName(AArtefacts[I]);
      if LName = '' then
        Continue;
      if TryRejectedLibraryPrefix(AManifest, LName, ArtefactMatchPath(AManifest, AArtefacts[I]),
        LPrefix, LRow) then
        LLines.Add(RejectedPrefixLogLine(LName, LPrefix, LRow, AArtefacts[I].Origin));
    end;
    Result := LLines.ToArray;
  finally
    LLines.Free;
  end;
end;

function ProductFolderMatchLogLines(const AManifest: TComponentManifest;
  const AArtefacts: TArtefactList): TArray<string>;
var
  LLines: TList<string>;
  I: Integer;
  LName: string;
  LPath: string;
  LStripped: string;
  LIndex: Integer;
  LOwnCode: Boolean;
  LOrigin: string;
begin
  Result := nil;
  if not AManifest.Loaded or not Assigned(AArtefacts) then
    Exit;
  if Trim(AManifest.InstallRoot) = '' then
    Exit;
  LLines := TList<string>.Create;
  try
    for I := 0 to AArtefacts.Count - 1 do
    begin
      LName := ArtefactUnitName(AArtefacts[I]);
      if LName = '' then
        Continue;
      LPath := ArtefactMatchPath(AManifest, AArtefacts[I]);
      if (LName = '') or (LPath = '') then
        Continue;
      if not IsEmbarcaderoProductPath(LPath, AManifest.InstallRoot) then
        Continue;
      LStripped := StripDelphiScopePrefix(LName);
      if FindExact(AManifest, LName) >= 0 then
        Continue;
      if (not SameText(LStripped, LName)) and (FindExact(AManifest, LStripped) >= 0) then
        Continue;
      LIndex := FindFolder(AManifest, LName, LStripped, LPath, LOwnCode);
      if LOwnCode or (LIndex < 0) then
        Continue;
      LOrigin := Trim(AArtefacts[I].Origin);
      if LOrigin = '' then
        LOrigin := 'Unknown';
      LLines.Add('Folder match kept on an Embarcadero product path: unit ' +
        LName + ', row ' + ComponentRowName(AManifest, LIndex) +
        ', kept origin ' + LOrigin);
    end;
    Result := LLines.ToArray;
  finally
    LLines.Free;
  end;
end;

function ManifestJsonWithRuntimeContext(const AJson, AInstallRoot,
  APrefixMode: string): string;
var
  LValue: TJSONValue;
  LRoot: TJSONObject;
  LMatch: TJSONObject;
  LPair: TJSONPair;
begin
  Result := AJson;
  if (Trim(AInstallRoot) = '') and (Trim(APrefixMode) = '') then
    Exit;
  if Trim(AJson) = '' then
    Exit;
  LValue := TJSONObject.ParseJSONValue(AJson);
  if not (LValue is TJSONObject) then
  begin
    LValue.Free;
    Exit;
  end;
  LRoot := TJSONObject(LValue);
  try
    if Trim(AInstallRoot) <> '' then
    begin
      LPair := LRoot.RemovePair('dxInstallRoot');
      LPair.Free;
      LRoot.AddPair('dxInstallRoot', AInstallRoot);
    end;
    if Trim(APrefixMode) <> '' then
    begin
      if LRoot.GetValue('match') is TJSONObject then
        LMatch := TJSONObject(LRoot.GetValue('match'))
      else
      begin
        LPair := LRoot.RemovePair('match');
        LPair.Free;
        LMatch := TJSONObject.Create;
        LRoot.AddPair('match', LMatch);
      end;
      LPair := LMatch.RemovePair('prefixes');
      LPair.Free;
      LMatch.AddPair('prefixes', APrefixMode);
    end;
    Result := LRoot.ToJSON;
  finally
    LRoot.Free;
  end;
end;

function ArtefactListHasUnit(const AArtefacts: TArtefactList;
  const AUnitName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if not Assigned(AArtefacts) then
    Exit;
  for I := 0 to AArtefacts.Count - 1 do
    if SameText(ArtefactUnitName(AArtefacts[I]), AUnitName) then
      Exit(True);
end;

function TryAddNameOnlyLibraryUnit(const AManifest: TComponentManifest;
  const AUnitName, AOrigin, AEvidence, AConfidence: string;
  const AArtefacts: TArtefactList): Boolean;
var
  LName: string;
  LArtefact: TArtefactInfo;
  LMatch: TManifestMatch;
begin
  Result := False;
  if not AManifest.Loaded or not Assigned(AArtefacts) then
    Exit;
  LName := Trim(AUnitName);
  if LName = '' then
    Exit;
  if ArtefactListHasUnit(AArtefacts, LName) then
    Exit;
  LMatch := MatchManifestUnit(AManifest, LName);
  if LMatch.Kind <> mmLibrary then
    Exit;
  LArtefact := Default(TArtefactInfo);
  LArtefact.UnitName := LName;
  LArtefact.RelativePath := LName + '.pas';
  LArtefact.ArtefactType := 'unit-evidence';
  LArtefact.Origin := AOrigin;
  LArtefact.Evidence := AEvidence;
  LArtefact.Confidence := AConfidence;
  LArtefact.FileSize := -1;
  AArtefacts.Add(LArtefact);
  Result := True;
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

      LMatch := MatchManifestUnit(AManifest, LUnitName,
        ArtefactMatchPath(AManifest, AArtefacts[I]));
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
      if (Length(LEntry.Prefixes) = 0) and (Length(LEntry.ExactUnits) = 0) and
        (Length(LEntry.Folders) = 0) then
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
    if Trim(AMetadata.SupplierUrl) = '' then
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

procedure AddCycloneDxLicences(AComponent: TJSONObject; const ALicence,
  ALicenceUrl: string);
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
    if ALicenceUrl <> '' then
      LLicence.AddPair('url', ALicenceUrl);
  end;

begin
  if not Assigned(AComponent) then
    Exit;
  LKind := ClassifyLicence(ALicence, LValue);
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
    // The row declares the licence, and it is also the distribution
    // licence we assert. Same id or name, once concluded and once declared.
    // LicenseRef-* stays a name. CycloneDX 1.6 license.id is the SPDX
    // license list, which does not include LicenseRef, so an id would
    // fail the schema. A name stays valid.
    AddNamed('concluded');
    AddNamed('declared');
  end;
end;

procedure AddLicenceJson(AComponent: TJSONObject; const AEntry: TComponentEntry);
begin
  AddCycloneDxLicences(AComponent, AEntry.Licence, AEntry.LicenceUrl);
end;

procedure AppendCycloneDxLicencesXml(ALines: TStrings; const ALicence,
  ALicenceUrl: string; AIndentLevel: Integer);
var
  LKind: TLicenceKind;
  LValue: string;

  procedure AddLine(ALevel: Integer; const AText: string);
  begin
    ALines.Add(StringOfChar(' ', ALevel * 2) + AText);
  end;

  procedure EmitNamed(const AAcknowledgement: string);
  begin
    AddLine(AIndentLevel + 1, '<license acknowledgement="' + AAcknowledgement + '">');
    if LKind = lkSpdxId then
      AddLine(AIndentLevel + 2, '<id>' + EscapeXml(LValue) + '</id>')
    else
      AddLine(AIndentLevel + 2, '<name>' + EscapeXml(LValue) + '</name>');
    if ALicenceUrl <> '' then
      AddLine(AIndentLevel + 2, '<url>' + EscapeXml(ALicenceUrl) + '</url>');
    AddLine(AIndentLevel + 1, '</license>');
  end;

begin
  if not Assigned(ALines) then
    Exit;
  LKind := ClassifyLicence(ALicence, LValue);
  if LKind = lkNone then
    Exit;
  AddLine(AIndentLevel, '<licenses>');
  if LKind = lkExpression then
    AddLine(AIndentLevel + 1, '<expression acknowledgement="concluded">' +
      EscapeXml(LValue) + '</expression>')
  else
  begin
    // Same choice as the JSON writer: LicenseRef-* is a name, not an id.
    EmitNamed('concluded');
    EmitNamed('declared');
  end;
  AddLine(AIndentLevel, '</licenses>');
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

  // CycloneDX 1.6 places copyright after licenses and before purl.
  // A row with no text keeps the field out, so the component stays as it
  // was when copyright was not part of the manifest.
  if AEntry.Copyright <> '' then
    Result.AddPair('copyright', AEntry.Copyright);

  // CycloneDX 1.6 places cpe after copyright and before purl. A row with
  // no accepted value keeps the field out.
  if ClassifyCpe(AEntry.Cpe) <> ckNone then
    Result.AddPair('cpe', AEntry.Cpe);

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
  begin
    AppendCycloneDxLicencesXml(ALines, AEntry.Licence, AEntry.LicenceUrl, ALevel);
  end;

  procedure EmitLibrary(const AEntry: TComponentEntry; AIndex: Integer; const ABomRef: string);
  var
    LPurl: string;
  begin
    // bom-1.6.xsd component order: supplier, author, name, version,
    // hashes, licenses, copyright, cpe, purl, externalReferences.
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
    // Same slot as the JSON property: after licenses, before purl, and
    // only when the row has copyright text.
    if AEntry.Copyright <> '' then
      AddLine(AIndentLevel + 1, '<copyright>' + EscapeXml(AEntry.Copyright) +
        '</copyright>');
    // Same slot as the JSON property: after copyright, before purl, and
    // only when the row has an accepted CPE.
    if ClassifyCpe(AEntry.Cpe) <> ckNone then
      AddLine(AIndentLevel + 1, '<cpe>' + EscapeXml(AEntry.Cpe) + '</cpe>');
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
  const AUsesGraph: TUsesDependencyGraph; const ACovered: TArray<Boolean>;
  const AOutputFilePath: string);
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
    LTargetIndex := FindDeliverableTargetIndex(AArtefacts, AProjectBomRef,
      AOutputFilePath);

  AddLine(AIndentLevel, '<dependencies>');
  AddLine(AIndentLevel + 1, '<dependency ref="' + EscapeXml(AProjectBomRef) + '">');
  if LTargetIndex >= 0 then
    AddLine(AIndentLevel + 2, '<dependency ref="comp-' + IntToStr(LTargetIndex) + '"/>')
  else if Assigned(AArtefacts) then
  begin
    for I := 0 to AArtefacts.Count - 1 do
      if ((I > High(LGrouped)) or not LGrouped[I]) and
        not IsCoveredUnit(ACovered, I) then
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
             ((I > High(LGrouped)) or not LGrouped[I]) and
             not IsCoveredUnit(ACovered, I) then
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

function SpdxLicenceTokenFor(const ALicence: string; out AKind: TLicenceKind): string;
const
  cLicenseRefPrefix = 'LicenseRef-';
var
  LValue: string;

  function TokenForName(const AValue: string): string;
  var
    LId: string;

    function IdHasLetterOrDigit(const AId: string): Boolean;
    var
      LIndex: Integer;
    begin
      // SanitizeSpdxId turns "!!!" into "---". Hyphens and dots alone are
      // not an id, so that result is treated as empty. The sanitizer itself
      // stays unchanged because package ids use it too.
      Result := False;
      for LIndex := 1 to Length(AId) do
        if CharInSet(AId[LIndex], ['A'..'Z', 'a'..'z', '0'..'9']) then
          Exit(True);
    end;

  begin
    // A value that already starts with LicenseRef- is kept, in the letter
    // case it was written. Only the id characters are sanitized, so
    // LicenseRef-Proprietary is not written as LicenseRef-LicenseRef-Proprietary.
    if StartsText(cLicenseRefPrefix, AValue) then
      LId := SanitizeSpdxId(Copy(AValue, Length(cLicenseRefPrefix) + 1, MaxInt))
    else
      LId := SanitizeSpdxId(AValue);
    if not IdHasLetterOrDigit(LId) then
      Result := 'LicenseRef-Custom'
    else if StartsText(cLicenseRefPrefix, AValue) then
      Result := Copy(AValue, 1, Length(cLicenseRefPrefix)) + LId
    else
      Result := cLicenseRefPrefix + LId;
  end;

begin
  AKind := ClassifyLicence(ALicence, LValue);
  case AKind of
    lkNone:
      Result := 'NOASSERTION';
    lkSpdxId, lkExpression:
      Result := LValue;
  else
    Result := TokenForName(LValue);
  end;
end;

function IsEmbarcaderoOrigin(const AOrigin: string): Boolean;
begin
  // The resolver writes "Embarcadero RTL", "Embarcadero VCL", and
  // "Embarcadero FMX". A later Embarcadero origin uses the same prefix.
  Result := StartsText('Embarcadero ', Trim(AOrigin));
end;

function ComponentLicenceFor(const AArtefact: TArtefactInfo;
  AIsDeliverable: Boolean; const AProductLicence: string;
  const AManifest: TComponentManifest): string;
var
  LProduct: string;
  LMatch: TManifestMatch;
begin
  LProduct := Trim(AProductLicence);
  Result := '';
  // A deliverable match applies to the built program. A unit keeps the
  // own-code and origin rules below.
  if AIsDeliverable and
    not SameText(AArtefact.ArtefactType, 'unit-evidence') then
    Exit(LProduct);

  if not SameText(AArtefact.ArtefactType, 'unit-evidence') then
    Exit;

  // Own code belongs to the product. A library row keeps its own licence
  // on the library component, so the unit itself stays without one.
  if AManifest.Loaded then
  begin
    LMatch := MatchManifestUnit(AManifest, ArtefactUnitName(AArtefact),
      ArtefactMatchPath(AManifest, AArtefact));
    if (LMatch.Kind = mmOwnCode) and (LProduct <> '') then
      Exit(LProduct);
    if LMatch.Kind = mmLibrary then
      Exit;
  end;

  if IsEmbarcaderoOrigin(AArtefact.Origin) then
    Result := Trim(AArtefact.Origin);
end;

function ComponentVersionFor(const AArtefact: TArtefactInfo;
  AIsDeliverable: Boolean; const AProductVersion, AProjectVersion: string): string;
var
  LProduct: string;
begin
  Result := Trim(AArtefact.Version);
  // A third-party file keeps the version it has, including none and a
  // file-date stand-in. The product version is not copied onto it.
  if not AIsDeliverable then
    Exit;
  // A unit is not the built program. ComponentLicenceFor uses the same guard.
  if SameText(AArtefact.ArtefactType, 'unit-evidence') then
    Exit;
  // A file-date stamp is the stand-in used when the file has no version
  // resource. The header version replaces it on the built program only.
  if (Result <> '') and not AArtefact.VersionFromFileDate then
    Exit;
  LProduct := Trim(AProductVersion);
  if LProduct = '' then
    LProduct := Trim(AProjectVersion);
  if LProduct <> '' then
    Result := LProduct;
end;

function ComponentVersionFromFileDate(const AArtefact: TArtefactInfo;
  const AWrittenVersion: string): Boolean;
begin
  Result := AArtefact.VersionFromFileDate and (Trim(AWrittenVersion) <> '') and
    SameText(Trim(AArtefact.Version), Trim(AWrittenVersion));
end;

function SpdxLicenceToken(const AEntry: TComponentEntry; out AKind: TLicenceKind): string;
begin
  Result := SpdxLicenceTokenFor(AEntry.Licence, AKind);
end;

function BuildSpdxLibraryPackage(const AEntry: TComponentEntry; AIndex: Integer;
  const ASpdxId: string): TJSONObject;
var
  LKind: TLicenceKind;
  LCpeKind: TCpeKind;
  LToken, LPurl, LCpeType: string;
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
  // SPDX 2.3 requires copyrightText. The manifest text is that value.
  // A blank row stays NOASSERTION, the same as a package with no notice.
  if AEntry.Copyright <> '' then
    Result.AddPair('copyrightText', AEntry.Copyright)
  else
    Result.AddPair('copyrightText', 'NOASSERTION');

  LPurl := BuildDelphiPurl(AEntry.Name, AEntry.Version, AEntry.Purl);
  LCpeKind := ClassifyCpe(AEntry.Cpe);
  LCpeType := SpdxCpeReferenceType(LCpeKind);
  // A package with no purl, no website, and no CPE keeps externalRefs out,
  // which is the previous output.
  if (LPurl <> '') or (AEntry.VendorUrl <> '') or (LCpeType <> '') then
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
    if LCpeType <> '' then
    begin
      LRef := TJSONObject.Create;
      LRefs.Add(LRef);
      LRef.AddPair('referenceCategory', 'SECURITY');
      LRef.AddPair('referenceType', LCpeType);
      LRef.AddPair('referenceLocator', AEntry.Cpe);
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
