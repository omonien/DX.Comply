/// <summary>
/// DX.Comply.Report.Overview
/// Builds the licence, origin and supplier summaries of the human-readable reports.
/// </summary>
///
/// <remarks>
/// The model is built from the same data the SBOM writers use: the artefact list and
/// the component manifest stored in the SBOM metadata. Both report writers render
/// the same model, so the Markdown and HTML reports always agree.
/// Issues #112 (licence overview), #113 (origin and supplier summary) and #114
/// (third-party units without manifest).
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
    function Count: Integer;
    /// <summary>Names joined by comma, at most AMax, then "and N more".</summary>
    function NamesText(AMax: Integer = cMaxGroupNames): string;
  end;

  /// <summary>
  /// Licence, origin and supplier summaries for one report.
  /// </summary>
  TReportOverview = record
    /// <summary>Groups per licence, sorted by title. The no-licence group is last.</summary>
    Licences: TArray<TReportGroup>;
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
  end;

/// <summary>
/// Builds the overview model from the report data.
/// </summary>
function BuildReportOverview(const AData: TComplianceReportData;
  AGroupByFolder: Boolean = False): TReportOverview;

/// <summary>
/// Returns a review hint for a licence that usually needs a check before it ships
/// in a product with a different licence, or an empty string. Hints only, no
/// legal judgement.
/// </summary>
function LicenceReviewHint(const ALicence, AProductLicence: string): string;

/// <summary>
/// One-line count of third-party units without a manifest row, for the CLI and
/// the IDE log. Empty when the build has no third-party units.
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
  out AManifest: TComponentManifest; out APlan: TManifestPlan): Boolean;
begin
  AManifest := Default(TComponentManifest);
  APlan := Default(TManifestPlan);
  Result := False;
  if Trim(AManifestJson) = '' then
    Exit;
  var LError: string;
  if not TryParseComponentManifest(AManifestJson, '', AManifest, LError) then
    Exit;
  APlan := BuildManifestPlan(AManifest, AArtefacts);
  Result := True;
end;

function BuildReportOverview(const AData: TComplianceReportData;
  AGroupByFolder: Boolean = False): TReportOverview;
begin
  Result := Default(TReportOverview);
  var LManifest: TComponentManifest;
  var LPlan: TManifestPlan;
  Result.ManifestUsed := LoadManifest(AData.Metadata.ComponentManifestJson, AData.Artefacts,
    LManifest, LPlan);

  var LLicences := TGroupBuilder.Create;
  var LOrigins := TGroupBuilder.Create;
  var LSuppliers := TGroupBuilder.Create;
  var LWithout := TGroupBuilder.Create;
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
      LLicences.Add(Trim(AData.Metadata.Licence), LProductName + ' (product)');
    end
    else
    begin
      LLicences.Add(cNoLicenceGroupTitle, LProductName + ' (product)');
    end;

    // Manifest libraries carry the licence of their row.
    for var LLib in LPlan.Libraries do
    begin
      var LEntry := LManifest.Components[LLib.ComponentIndex];
      var LName := LEntry.Name;
      if Trim(LEntry.Version) <> '' then
      begin
        LName := LName + ' ' + Trim(LEntry.Version);
      end;
      if Trim(LEntry.Licence) <> '' then
      begin
        LLicences.Add(Trim(LEntry.Licence), LName);
      end
      else
      begin
        LLicences.Add(cNoLicenceGroupTitle, LName);
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
        // Units in a manifest library are covered by the library's licence.
        if IsSameDeliverableFile(AData.Artefacts, i, LDeliverable) and
          (Trim(AData.Metadata.Licence) <> '') then
        begin
          LLicences.Add(Trim(AData.Metadata.Licence), LName);
        end
        else if not LGrouped.ContainsKey(i) then
        begin
          LLicences.Add(cNoLicenceGroupTitle, LName);
        end;
        if IsThirdPartyUnit(LArtefact) then
        begin
          Inc(Result.ThirdPartyUnitCount);
          var LComponentIndex: Integer;
          if LGrouped.TryGetValue(i, LComponentIndex) and
            (Trim(LManifest.Components[LComponentIndex].Vendor) <> '') then
          begin
            LSuppliers.Add(Trim(LManifest.Components[LComponentIndex].Vendor), LName);
          end
          else
          begin
            LSuppliers.Add(cUnknownSupplierTitle, LName);
          end;
          var LMatchKind := mmNone;
          if Result.ManifestUsed then
          begin
            LMatchKind := MatchManifestUnit(LManifest, ArtefactUnitName(LArtefact)).Kind;
          end;
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

    // Licences: sorted, the no-licence group last, with review hints.
    var LAll := LLicences.ToArray(True);
    var LList := TList<TReportGroup>.Create;
    try
      var LNoLicence := Default(TReportGroup);
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
    Result.WithoutManifest := LWithout.ToArray(True);
    for var i := 0 to High(Result.WithoutManifest) do
    begin
      Result.WithoutManifest[i].Note := cMissingAll;
    end;
  finally
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
  if LOverview.ThirdPartyUnitCount = 0 then
    Exit;
  Result := Format('%d of %d third-party units have no component manifest row. ' +
    'The report lists them under "Third-party units without manifest".',
    [LOverview.WithoutManifestCount, LOverview.ThirdPartyUnitCount]);
end;

end.
