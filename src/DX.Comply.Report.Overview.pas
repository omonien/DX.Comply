/// <summary>
/// DX.Comply.Report.Overview
/// Builds the licence, origin and supplier summaries of the human-readable reports.
/// </summary>
///
/// <remarks>
/// The model is built from the same data the SBOM writers use: the artefact list and
/// the component manifest stored in the SBOM metadata. Both report writers render
/// the same model, so the Markdown and HTML reports always agree.
/// Issues #112 (licence overview), #113 (origin and supplier summary), #114
/// (third-party units without manifest) and #157 (the log line is omitted
/// when no unit is missing). Issue #156 lists each component of a
/// licence group on its own row, with the manifest version and copyright.
/// Embarcadero units use their origin label as the licence (issue #165).
/// Own-code units use the product licence when one is set (issue #166).
/// A third-party origin that matches own_code_* is own code, so it is not
/// counted as an unknown supplier. Units that stay under Unknown supplier
/// are named on that row, grouped by prefix (issue #176).
/// The built program's licence row uses its own version, or the product
/// version from the SBOM header when the file has none. A third-party file
/// does not inherit that version.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Report.Overview;

interface

uses
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf;

const
  /// <summary>Licence group title for components without licence data.</summary>
  cNoLicenceGroupTitle = 'No licence information';
  /// <summary>Supplier group title for third-party units without a known supplier.</summary>
  cUnknownSupplierTitle = 'Unknown supplier';
  /// <summary>Origin title for component manifest libraries.</summary>
  cManifestLibraryOrigin = 'Component manifest library';
  /// <summary>Origin title for DLLs.</summary>
  cDllOrigin = 'DLL';
  /// <summary>Origin title for runtime packages.</summary>
  cRuntimePackageOrigin = 'Runtime package';
  /// <summary>Origin title for other files, such as the built program or resources.</summary>
  cOtherFileOrigin = 'Other file';
  /// <summary>Report section anchors.</summary>
  cAnchorOrigins = 'origin-summary';
  cAnchorLicences = 'licences';
  cAnchorWithoutManifest = 'third-party-units-without-manifest';
  cAnchorPrefixRejections = 'prefix-matches-not-applied';
  cAnchorArtefacts = 'artefacts';
  cAnchorUnitEvidence = 'unit-evidence';
  /// <summary>Names listed per group before the rest is counted.</summary>
  cMaxGroupNames = 20;

type
  /// <summary>
  /// One row of an overview table: a title, the component names in it and an
  /// optional note.
  /// </summary>
  TReportGroup = record
    Title: string;
    Names: TArray<string>;
    /// <summary>Hint text, such as a licence review note or the missing fields.</summary>
    Note: string;
    /// <summary>Section anchor with the detailed list, or empty.</summary>
    Anchor: string;
    /// <summary>
    /// Lines shown under the title. The Unknown supplier row lists its
    /// units by prefix. Empty for every other group.
    /// </summary>
    Detail: TArray<string>;
    function Count: Integer;
    /// <summary>Names joined by comma, at most AMax, then "and N more".</summary>
    function NamesText(AMax: Integer = cMaxGroupNames): string;
  end;

  /// <summary>
  /// One component in a licence group. Version and copyright come from the
  /// component manifest and are empty when that row does not set them.
  /// </summary>
  TLicenceComponent = record
    /// <summary>Component name, without the version.</summary>
    Name: string;
    /// <summary>Manifest version. Empty for the product, files and units.</summary>
    Version: string;
    /// <summary>Manifest copyright text. Empty when the field is not set.</summary>
    Copyright: string;
  end;

  /// <summary>
  /// One declared licence and its components. Components are sorted by name,
  /// case-insensitive, then by version.
  /// </summary>
  TLicenceGroup = record
    /// <summary>Declared licence, or the no-licence title.</summary>
    Title: string;
    /// <summary>Review hint for this licence, or empty.</summary>
    Note: string;
    /// <summary>One entry per component.</summary>
    Components: TArray<TLicenceComponent>;
    function Count: Integer;
  end;

  /// <summary>
  /// One units_prefix that matched a unit and was not applied.
  /// </summary>
  TPrefixRejectionRow = record
    /// <summary>Unit name from the MAP file or the source file.</summary>
    UnitName: string;
    /// <summary>The prefix that was not applied.</summary>
    Prefix: string;
    /// <summary>Manifest row name.</summary>
    RowName: string;
    /// <summary>Origin left on the unit.</summary>
    KeptOrigin: string;
  end;

  /// <summary>
  /// Licence, origin and supplier summaries for one report.
  /// </summary>
  TReportOverview = record
    /// <summary>
    /// Groups per licence, sorted by title. The no-licence group is last.
    /// Each group lists one component per row.
    /// </summary>
    Licences: TArray<TLicenceGroup>;
    /// <summary>Counts per origin class. The sum equals TotalComponents.</summary>
    Origins: TArray<TReportGroup>;
    /// <summary>Third-party units per supplier, from the component manifest.</summary>
    Suppliers: TArray<TReportGroup>;
    /// <summary>Third-party units without a manifest row, grouped by unit prefix.</summary>
    WithoutManifest: TArray<TReportGroup>;
    /// <summary>Number of third-party units without a manifest row.</summary>
    WithoutManifestCount: Integer;
    /// <summary>Number of third-party units.</summary>
    ThirdPartyUnitCount: Integer;
    /// <summary>Number of components in the SBOM (artefacts plus manifest libraries).</summary>
    TotalComponents: Integer;
    /// <summary>True when a component manifest was used.</summary>
    ManifestUsed: Boolean;
    /// <summary>
    /// Prefixes that matched a unit and were not applied. Empty when every
    /// prefix match was applied, or when no prefix matched.
    /// </summary>
    PrefixRejections: TArray<TPrefixRejectionRow>;
  end;

/// <summary>
/// Builds the overview model from the report data.
/// </summary>
function BuildReportOverview(const AData: TComplianceReportData;
  AGroupByFolder: Boolean = False): TReportOverview;

/// <summary>
/// Compact lines for the units counted under Unknown supplier. Names are
/// grouped by unit prefix, the same key as the console warnings. At most
/// ten groups are listed, with at most five names in each group, then one
/// line counts the rest.
/// </summary>
function FormatUnknownSupplierLines(const ANames: TArray<string>): TArray<string>;

/// <summary>
/// Returns a review hint for a licence that usually needs a check before it ships
/// in a product with a different licence, or an empty string. Hints only, no
/// legal judgement.
/// </summary>
function LicenceReviewHint(const ALicence, AProductLicence: string): string;

/// <summary>
/// One-line count of third-party units without a manifest row, for the CLI and
/// the IDE log. Empty when no unit is missing a row, including when the build
/// has no third-party units. The HTML and Markdown reports leave the section
/// out in the same case.
/// </summary>
function ThirdPartyWithoutManifestLine(const AArtefacts: TArtefactList;
  const AManifestJson: string): string;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  System.StrUtils,
  System.SysUtils,
  DX.Comply.ComponentManifest,
  DX.Comply.CraChecks;

const
  cThirdPartyOrigin = 'Third party';
  cMissingAll = 'supplier, version, licence';

{ TReportGroup }

function TReportGroup.Count: Integer;
begin
  Result := Length(Names);
end;

function TReportGroup.NamesText(AMax: Integer): string;
begin
  Result := '';
  for var i := 0 to High(Names) do
  begin
    if i = AMax then
    begin
      Result := Result + Format(' and %d more', [Length(Names) - AMax]);
      Break;
    end;
    if i > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + Names[i];
  end;
end;

{ TLicenceGroup }

function TLicenceGroup.Count: Integer;
begin
  Result := Length(Components);
end;

type
  TGroupBuilder = class
  private
    FGroups: TDictionary<string, TList<string>>;
    FTitles: TDictionary<string, string>;
    FOrder: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ATitle, AName: string);
    procedure Touch(const ATitle: string);
    function ToArray(ASorted: Boolean): TArray<TReportGroup>;
  end;

constructor TGroupBuilder.Create;
begin
  inherited Create;
  FGroups := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FTitles := TDictionary<string, string>.Create;
  FOrder := TList<string>.Create;
end;

destructor TGroupBuilder.Destroy;
begin
  FOrder.Free;
  FTitles.Free;
  FGroups.Free;
  inherited;
end;

procedure TGroupBuilder.Touch(const ATitle: string);
begin
  var LKey := AnsiUpperCase(ATitle);
  if not FGroups.ContainsKey(LKey) then
  begin
    FGroups.Add(LKey, TList<string>.Create);
    FTitles.Add(LKey, ATitle);
    FOrder.Add(LKey);
  end;
end;

procedure TGroupBuilder.Add(const ATitle, AName: string);
begin
  Touch(ATitle);
  FGroups[AnsiUpperCase(ATitle)].Add(AName);
end;

function TGroupBuilder.ToArray(ASorted: Boolean): TArray<TReportGroup>;
begin
  var LKeys := FOrder.ToArray;
  if ASorted then
  begin
    TArray.Sort<string>(LKeys);
  end;
  SetLength(Result, Length(LKeys));
  for var i := 0 to High(LKeys) do
  begin
    Result[i] := Default(TReportGroup);
    Result[i].Title := FTitles[LKeys[i]];
    Result[i].Names := FGroups[LKeys[i]].ToArray;
  end;
end;

type
  /// <summary>
  /// Sort key for a licence component. Index keeps equal names and versions in
  /// the order they were added, so the sort does not shuffle them.
  /// </summary>
  TLicenceSortItem = record
    Component: TLicenceComponent;
    Index: Integer;
  end;

  /// <summary>
  /// Groups licence rows by title. The same title with different case is one
  /// group, and the first spelling is kept. Components stay in add order until
  /// ToArray sorts them.
  /// </summary>
  TLicenceGroupBuilder = class
  private
    FGroups: TObjectDictionary<string, TList<TLicenceComponent>>;
    FTitles: TDictionary<string, string>;
    FOrder: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ATitle, AName, AVersion, ACopyright: string);
    function ToArray: TArray<TLicenceGroup>;
  end;

procedure SortLicenceComponents(var AComponents: TArray<TLicenceComponent>);
var
  LItems: TArray<TLicenceSortItem>;
  i: Integer;
begin
  SetLength(LItems, Length(AComponents));
  for i := 0 to High(AComponents) do
  begin
    LItems[i].Component := AComponents[i];
    LItems[i].Index := i;
  end;
  TArray.Sort<TLicenceSortItem>(LItems, TComparer<TLicenceSortItem>.Construct(
    function(const ALeft, ARight: TLicenceSortItem): Integer
    begin
      Result := CompareText(ALeft.Component.Name, ARight.Component.Name);
      if Result = 0 then
        Result := CompareText(ALeft.Component.Version, ARight.Component.Version);
      if Result = 0 then
      begin
        if ALeft.Index < ARight.Index then
          Result := -1
        else if ALeft.Index > ARight.Index then
          Result := 1
        else
          Result := 0;
      end;
    end));
  for i := 0 to High(AComponents) do
    AComponents[i] := LItems[i].Component;
end;

constructor TLicenceGroupBuilder.Create;
begin
  inherited Create;
  FGroups := TObjectDictionary<string, TList<TLicenceComponent>>.Create([doOwnsValues]);
  FTitles := TDictionary<string, string>.Create;
  FOrder := TList<string>.Create;
end;

destructor TLicenceGroupBuilder.Destroy;
begin
  FOrder.Free;
  FTitles.Free;
  FGroups.Free;
  inherited;
end;

procedure TLicenceGroupBuilder.Add(const ATitle, AName, AVersion, ACopyright: string);
var
  LKey: string;
  LList: TList<TLicenceComponent>;
  LItem: TLicenceComponent;
begin
  LKey := AnsiUpperCase(ATitle);
  if not FGroups.TryGetValue(LKey, LList) then
  begin
    LList := TList<TLicenceComponent>.Create;
    FGroups.Add(LKey, LList);
    FTitles.Add(LKey, ATitle);
    FOrder.Add(LKey);
  end;
  LItem := Default(TLicenceComponent);
  LItem.Name := Trim(AName);
  LItem.Version := Trim(AVersion);
  LItem.Copyright := Trim(ACopyright);
  LList.Add(LItem);
end;

function TLicenceGroupBuilder.ToArray: TArray<TLicenceGroup>;
var
  LKeys: TArray<string>;
  i: Integer;
begin
  LKeys := FOrder.ToArray;
  TArray.Sort<string>(LKeys);
  SetLength(Result, Length(LKeys));
  for i := 0 to High(LKeys) do
  begin
    Result[i] := Default(TLicenceGroup);
    Result[i].Title := FTitles[LKeys[i]];
    Result[i].Components := FGroups[LKeys[i]].ToArray;
    SortLicenceComponents(Result[i].Components);
  end;
end;

function IsCopyleftToken(const AToken: string): Boolean;
const
  cCopyleft: array[0..7] of string = ('GPL', 'LGPL', 'AGPL', 'MPL', 'EPL', 'EUPL', 'CDDL', 'OSL');
begin
  var LToken := UpperCase(AToken);
  for var LPrefix in cCopyleft do
  begin
    if LToken.StartsWith(LPrefix + '-') or (LToken = LPrefix) then
      Exit(True);
  end;
  Result := False;
end;

function HasCopyleftToken(const ALicence: string): Boolean;
begin
  var LText := StringReplace(StringReplace(ALicence, '(', ' ', [rfReplaceAll]), ')', ' ',
    [rfReplaceAll]);
  for var LToken in LText.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    if IsCopyleftToken(LToken) then
      Exit(True);
  end;
  Result := False;
end;

function LicenceReviewHint(const ALicence, AProductLicence: string): string;
begin
  Result := '';
  if not HasCopyleftToken(ALicence) then
    Exit;
  if SameText(Trim(ALicence), Trim(AProductLicence)) then
    Exit;
  Result := 'Copyleft licence. Check its terms for distribution with this product.';
end;

function ArtefactDisplayName(const AArtefact: TArtefactInfo): string;
begin
  if SameText(AArtefact.ArtefactType, 'unit-evidence') then
  begin
    Result := ArtefactUnitName(AArtefact);
  end
  else
  begin
    Result := ExtractFileName(AArtefact.RelativePath);
  end;
  if Result = '' then
  begin
    Result := Trim(AArtefact.ComponentName);
  end;
  if Result = '' then
  begin
    Result := ExtractFileName(AArtefact.FilePath);
  end;
end;

function OriginTitle(const AArtefact: TArtefactInfo): string;
begin
  if SameText(AArtefact.ArtefactType, 'unit-evidence') then
  begin
    Result := Trim(AArtefact.Origin);
    if Result = '' then
    begin
      Result := 'Unknown';
    end;
  end
  else if SameText(AArtefact.ArtefactType, 'library') then
  begin
    Result := cDllOrigin;
  end
  else if SameText(AArtefact.ArtefactType, 'runtime-package') or
    SameText(AArtefact.ArtefactType, 'required-package') or
    SameText(AArtefact.ArtefactType, 'package') then
  begin
    Result := cRuntimePackageOrigin;
  end
  else
  begin
    Result := cOtherFileOrigin;
  end;
end;

function IsThirdPartyUnit(const AArtefact: TArtefactInfo): Boolean;
begin
  Result := SameText(AArtefact.ArtefactType, 'unit-evidence') and
    SameText(AArtefact.Origin, cThirdPartyOrigin);
end;

function LoadManifest(const AManifestJson: string; const AArtefacts: TArtefactList;
  const AInstallRoot: string; out AManifest: TComponentManifest;
  out APlan: TManifestPlan): Boolean;
begin
  AManifest := Default(TComponentManifest);
  APlan := Default(TManifestPlan);
  Result := False;
  if Trim(AManifestJson) = '' then
    Exit;
  var LError: string;
  if not TryParseComponentManifest(AManifestJson, '', AManifest, LError) then
    Exit;
  // The project toolchain root wins over dxInstallRoot in the in-memory
  // JSON. A report built without a project keeps the value the engine wrote.
  if Trim(AInstallRoot) <> '' then
    AManifest.InstallRoot := AInstallRoot;
  APlan := BuildManifestPlan(AManifest, AArtefacts);
  Result := True;
end;

function FormatUnknownSupplierLines(const ANames: TArray<string>): TArray<string>;
const
  // Same cap as JoinNames in the console warnings.
  cShownNames = 5;

  function CountText(ACount: Integer; const AOne, AMany: string): string;
  begin
    if ACount = 1 then
      Result := '1 ' + AOne
    else
      Result := IntToStr(ACount) + ' ' + AMany;
  end;

begin
  Result := nil;
  if High(ANames) < 0 then
    Exit;

  // The first spelling of a prefix is kept. jvEdit and JvComponent share
  // one group, as they do in the console warnings.
  var LGroups := TObjectDictionary<string, TList<string>>.Create([doOwnsValues],
    TIStringComparer.Ordinal);
  var LOrder := TList<string>.Create;
  var LLines := TList<string>.Create;
  try
    for var LName in ANames do
    begin
      var LPrefix := ThirdPartyUnitPrefix(LName);
      var LNames: TList<string>;
      if not LGroups.TryGetValue(LPrefix, LNames) then
      begin
        LNames := TList<string>.Create;
        LGroups.Add(LPrefix, LNames);
        LOrder.Add(LPrefix);
      end;
      LNames.Add(LName);
    end;

    var LRestGroups := 0;
    var LRestUnits := 0;
    for var i := 0 to LOrder.Count - 1 do
    begin
      var LNames := LGroups[LOrder[i]];
      if i >= cMaxComponentWarningGroups then
      begin
        Inc(LRestGroups);
        Inc(LRestUnits, LNames.Count);
        Continue;
      end;
      var LShown := '';
      for var j := 0 to LNames.Count - 1 do
      begin
        if j = cShownNames then
        begin
          LShown := LShown + ', ...';
          Break;
        end;
        if LShown <> '' then
          LShown := LShown + ', ';
        LShown := LShown + LNames[j];
      end;
      LLines.Add(LOrder[i] + ': ' + CountText(LNames.Count, 'unit', 'units') +
        ' (' + LShown + ')');
    end;
    if LRestGroups > 0 then
      LLines.Add(CountText(LRestGroups, 'more group', 'more groups') + ', ' +
        CountText(LRestUnits, 'unit', 'units'));
    Result := LLines.ToArray;
  finally
    LLines.Free;
    LOrder.Free;
    LGroups.Free;
  end;
end;

function BuildReportOverview(const AData: TComplianceReportData;
  AGroupByFolder: Boolean = False): TReportOverview;
begin
  Result := Default(TReportOverview);
  var LManifest: TComponentManifest;
  var LPlan: TManifestPlan;
  Result.ManifestUsed := LoadManifest(AData.Metadata.ComponentManifestJson, AData.Artefacts,
    AData.ProjectInfo.Toolchain.RootDir, LManifest, LPlan);

  var LLicences := TLicenceGroupBuilder.Create;
  var LOrigins := TGroupBuilder.Create;
  var LSuppliers := TGroupBuilder.Create;
  var LWithout := TGroupBuilder.Create;
  var LRejections := TList<TPrefixRejectionRow>.Create;
  var LGrouped := TDictionary<Integer, Integer>.Create;
  try
    // Artefact index -> manifest component index, for units in a library.
    for var LLib in LPlan.Libraries do
    begin
      for var LRef in LLib.UnitBomRefs do
      begin
        LGrouped.AddOrSetValue(StrToIntDef(Copy(LRef, Length('comp-') + 1, MaxInt), -1),
          LLib.ComponentIndex);
      end;
    end;

    // The product itself (metadata component).
    var LProductName := Trim(AData.Metadata.ProductName);
    if LProductName = '' then
    begin
      LProductName := AData.ProjectInfo.ProjectName;
    end;
    if Trim(AData.Metadata.Licence) <> '' then
    begin
      LLicences.Add(Trim(AData.Metadata.Licence), LProductName + ' (product)', '', '');
    end
    else
    begin
      LLicences.Add(cNoLicenceGroupTitle, LProductName + ' (product)', '', '');
    end;

    // Manifest libraries carry the licence of their row. The origin summary
    // still names the library with its version. The licence table keeps the
    // version, and the optional copyright, in their own columns (issue #156).
    for var LLib in LPlan.Libraries do
    begin
      var LEntry := LManifest.Components[LLib.ComponentIndex];
      var LVersion := Trim(LEntry.Version);
      var LName := LEntry.Name;
      if LVersion <> '' then
      begin
        LName := LName + ' ' + LVersion;
      end;
      if Trim(LEntry.Licence) <> '' then
      begin
        LLicences.Add(Trim(LEntry.Licence), LEntry.Name, LVersion, LEntry.Copyright);
      end
      else
      begin
        LLicences.Add(cNoLicenceGroupTitle, LEntry.Name, LVersion, LEntry.Copyright);
      end;
      LOrigins.Add(cManifestLibraryOrigin, LName);
    end;

    if Assigned(AData.Artefacts) then
    begin
      // The built program is the product, so it is listed under the product
      // licence, as in the SBOM (issues #131 and #155). A second copy of
      // that file is listed the same way.
      var LDeliverable := FindDeliverableTargetIndex(AData.Artefacts,
        AData.ProjectInfo.ProjectName, AData.ProjectInfo.OutputFilePath);
      for var i := 0 to AData.Artefacts.Count - 1 do
      begin
        var LArtefact := AData.Artefacts[i];
        var LName := ArtefactDisplayName(LArtefact);
        LOrigins.Add(OriginTitle(LArtefact), LName);
        // The built program uses the product licence. Own-code units do too
        // when that licence is set. Embarcadero units use their origin label.
        // A manifest library covers its units, so those units are not listed
        // again here (issues #131, #155, #165, #166).
        var LIsDeliverable := IsSameDeliverableFile(AData.Artefacts, i, LDeliverable);
        var LComponentLicence := ComponentLicenceFor(LArtefact, LIsDeliverable,
          AData.Metadata.Licence, LManifest);
        // The built program shows its own version, or the product version
        // from the SBOM header when it has none. A third-party file stays
        // empty here. Its version is not the product version.
        var LVersion := '';
        if LIsDeliverable then
          LVersion := ComponentVersionFor(LArtefact, True,
            AData.Metadata.ProductVersion, AData.ProjectInfo.Version);
        if LComponentLicence <> '' then
        begin
          LLicences.Add(LComponentLicence, LName, LVersion, '');
        end
        else if not LGrouped.ContainsKey(i) then
        begin
          LLicences.Add(cNoLicenceGroupTitle, LName, LVersion, '');
        end;
        if Result.ManifestUsed and SameText(LArtefact.ArtefactType, 'unit-evidence') then
        begin
          var LRejectPrefix := '';
          var LRejectRow := '';
          if TryRejectedLibraryPrefix(LManifest, ArtefactUnitName(LArtefact),
            ArtefactMatchPath(LManifest, LArtefact), LRejectPrefix, LRejectRow) then
          begin
            var LRejection: TPrefixRejectionRow;
            LRejection.UnitName := ArtefactUnitName(LArtefact);
            LRejection.Prefix := LRejectPrefix;
            LRejection.RowName := LRejectRow;
            LRejection.KeptOrigin := Trim(LArtefact.Origin);
            if LRejection.KeptOrigin = '' then
              LRejection.KeptOrigin := 'Unknown';
            LRejections.Add(LRejection);
          end;
        end;
        // A library row with a vendor counts here even when the units are
        // Local project. Those units are in the licence table and were
        // missing from the supplier list (issue #176).
        var LSupplierIndex: Integer;
        var LHasSupplier := Result.ManifestUsed and
          LGrouped.TryGetValue(i, LSupplierIndex) and
          (Trim(LManifest.Components[LSupplierIndex].Vendor) <> '');
        if LHasSupplier then
          LSuppliers.Add(Trim(LManifest.Components[LSupplierIndex].Vendor), LName);
        if IsThirdPartyUnit(LArtefact) then
        begin
          var LMatchKind := mmNone;
          if Result.ManifestUsed then
          begin
            LMatchKind := MatchManifestUnit(LManifest, ArtefactUnitName(LArtefact),
              ArtefactMatchPath(LManifest, LArtefact)).Kind;
          end;
          // own_code_* marks the project's own units, including a file that
          // lives outside the project folder and is therefore recorded as
          // Third party. The without-manifest list and the console warnings
          // already leave those units out, and they carry the product
          // licence. Counting them as an unknown supplier made a number
          // that no named list could explain (issue #176).
          if LMatchKind <> mmOwnCode then
          begin
            Inc(Result.ThirdPartyUnitCount);
            if not LHasSupplier then
              LSuppliers.Add(cUnknownSupplierTitle, LName);
            if LMatchKind = mmNone then
            begin
              // Issue #132: optional second level, the source folder, so one
              // prefix used by two libraries in different folders splits up.
              var LGroupTitle := ThirdPartyUnitPrefix(ArtefactUnitName(LArtefact));
              if AGroupByFolder then
              begin
                var LFolder := ExtractFileDir(LArtefact.FilePath);
                if LFolder = '' then
                begin
                  LFolder := ExtractFileDir(LArtefact.RelativePath);
                end;
                if LFolder <> '' then
                begin
                  LGroupTitle := LGroupTitle + ' (' + LFolder + ')';
                end;
              end;
              LWithout.Add(LGroupTitle, LName);
              Inc(Result.WithoutManifestCount);
            end;
          end;
        end;
      end;
    end;

    // Licences: sorted, the no-licence group last, with review hints.
    // Components inside a group are already sorted by name.
    var LAll := LLicences.ToArray;
    var LList := TList<TLicenceGroup>.Create;
    try
      var LNoLicence := Default(TLicenceGroup);
      for var LGroup in LAll do
      begin
        if SameText(LGroup.Title, cNoLicenceGroupTitle) then
        begin
          LNoLicence := LGroup;
          Continue;
        end;
        var LItem := LGroup;
        LItem.Note := LicenceReviewHint(LItem.Title, AData.Metadata.Licence);
        LList.Add(LItem);
      end;
      if LNoLicence.Count > 0 then
      begin
        LList.Add(LNoLicence);
      end;
      Result.Licences := LList.ToArray;
    finally
      LList.Free;
    end;

    Result.Origins := LOrigins.ToArray(False);
    for var i := 0 to High(Result.Origins) do
    begin
      if SameText(Result.Origins[i].Title, cThirdPartyOrigin) and (Result.WithoutManifestCount > 0) then
      begin
        Result.Origins[i].Anchor := cAnchorWithoutManifest;
      end
      else if SameText(Result.Origins[i].Title, cManifestLibraryOrigin) then
      begin
        Result.Origins[i].Anchor := cAnchorLicences;
      end
      else if SameText(Result.Origins[i].Title, cDllOrigin) or
        SameText(Result.Origins[i].Title, cRuntimePackageOrigin) or
        SameText(Result.Origins[i].Title, cOtherFileOrigin) then
      begin
        Result.Origins[i].Anchor := cAnchorArtefacts;
      end
      else
      begin
        Result.Origins[i].Anchor := cAnchorUnitEvidence;
      end;
      Inc(Result.TotalComponents, Result.Origins[i].Count);
    end;

    Result.Suppliers := LSuppliers.ToArray(True);
    for var i := 0 to High(Result.Suppliers) do
      if SameText(Result.Suppliers[i].Title, cUnknownSupplierTitle) then
        Result.Suppliers[i].Detail := FormatUnknownSupplierLines(Result.Suppliers[i].Names);
    Result.WithoutManifest := LWithout.ToArray(True);
    for var i := 0 to High(Result.WithoutManifest) do
    begin
      Result.WithoutManifest[i].Note := cMissingAll;
    end;
    Result.PrefixRejections := LRejections.ToArray;
  finally
    LRejections.Free;
    LGrouped.Free;
    LWithout.Free;
    LSuppliers.Free;
    LOrigins.Free;
    LLicences.Free;
  end;
end;

function ThirdPartyWithoutManifestLine(const AArtefacts: TArtefactList;
  const AManifestJson: string): string;
begin
  Result := '';
  var LData := Default(TComplianceReportData);
  LData.Artefacts := AArtefacts;
  LData.Metadata.ComponentManifestJson := AManifestJson;
  var LOverview := BuildReportOverview(LData);
  // A count of zero names a report section that is not written (issue #157).
  if LOverview.WithoutManifestCount = 0 then
    Exit;
  Result := Format('%d of %d third-party units have no component manifest row. ' +
    'The report lists them under "Third-party units without manifest".',
    [LOverview.WithoutManifestCount, LOverview.ThirdPartyUnitCount]);
end;

end.
