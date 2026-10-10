/// <summary>
/// DX.Comply.DependencyGraph
/// Direct uses-clause edges between units already present in the SBOM.
/// </summary>
///
/// <remarks>
/// Edges come from a uses clause that was read, matched to unit-evidence
/// components already in the document. A name that is not in the SBOM is
/// omitted. No component is created for it. DCU-only units stay leaves.
/// The walk is not recursive: A uses B and B uses C produces A to B and
/// B to C, not A to C. A cycle is stored as both direct edges.
/// Targets are sorted by unit name, case-insensitive, then by index.
/// On the MAP path the resolver caches the clause, so this unit does not
/// read that .pas again.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.DependencyGraph;

interface

uses
  System.Classes,
  System.JSON,
  DX.Comply.Engine.Intf;

const
  /// <summary>
  /// Property written on a unit whose Pascal source was not read.
  /// </summary>
  cUnresolvedDependenciesProperty = 'net.developer-experts.dx-comply:dependencies';
  /// <summary>Value of cUnresolvedDependenciesProperty.</summary>
  cUnresolvedDependenciesValue = 'unresolved-no-source';

type
  /// <summary>
  /// How far the uses clause of one component could be matched.
  /// </summary>
  TUnitUsesStatus = (
    /// <summary>Not unit evidence. The component stays in the incomplete set.</summary>
    uusNotUnit,
    /// <summary>Unit evidence with no readable .pas.</summary>
    uusMissingSource,
    /// <summary>Source was read, and at least one uses name is not in this SBOM.</summary>
    uusPartial,
    /// <summary>Source was read, and every uses name matches a unit in this SBOM.</summary>
    uusComplete
  );

  /// <summary>
  /// One direct uses edge list. TargetIndexes is sorted and never empty.
  /// </summary>
  TUsesDependency = record
    /// <summary>Index into the artefact list. The bom-ref is comp- plus this index.</summary>
    SourceIndex: Integer;
    /// <summary>Indexes of unit-evidence components this source uses.</summary>
    TargetIndexes: TArray<Integer>;
  end;

  /// <summary>
  /// Direct uses edges and a status for every artefact.
  /// </summary>
  TUsesDependencyGraph = record
    /// <summary>Sources that have at least one target, in source index order.</summary>
    Dependencies: TArray<TUsesDependency>;
    /// <summary>One status per artefact. Empty when the artefact list is nil.</summary>
    Status: TArray<TUnitUsesStatus>;
  end;

/// <summary>
/// Builds direct uses edges. Does not walk the disk except to read a .pas
/// that the resolver has not already cached.
/// </summary>
function BuildUsesDependencyGraph(const AArtefacts: TArtefactList): TUsesDependencyGraph;

/// <summary>
/// Appends one dependency object per uses edge list. Does not emit an empty
/// dependsOn. Leaves the grouped deliverable list unchanged.
/// </summary>
procedure AppendUsesDependenciesJson(ADependencies: TJSONArray;
  const AGraph: TUsesDependencyGraph);

/// <summary>
/// Writes uses dependency elements at AIndentLevel + 1. AIndentLevel is the
/// indent of the surrounding dependencies element (two spaces per level).
/// </summary>
procedure WriteUsesDependenciesXml(ALines: TStrings; AIndentLevel: Integer;
  const AGraph: TUsesDependencyGraph);

/// <summary>
/// Splits bom-refs into the incomplete and complete composition sets.
/// The project name is first in the incomplete set. Does nothing when the
/// project name is empty. Manifest library refs are appended to the complete
/// set in the order given.
/// </summary>
procedure BuildCompositionRefLists(const AProjectName: string;
  const AGraph: TUsesDependencyGraph; const ALibraryRefs: TArray<string>;
  out AIncomplete, AComplete: TArray<string>);

/// <summary>
/// Writes compositions. Incomplete first, then complete when that set is
/// not empty. Omitted when the project name is empty.
/// </summary>
procedure WriteCompositionsJson(ARoot: TJSONObject; const AProjectName: string;
  const AGraph: TUsesDependencyGraph; const ALibraryRefs: TArray<string>);

type
  /// <summary>
  /// One CycloneDX composition aggregate for a library source SBOM.
  /// </summary>
  TLibraryCompositionGroup = record
    /// <summary>complete, incomplete, or unknown.</summary>
    Aggregate: string;
    /// <summary>bom-ref values in that aggregate.</summary>
    Refs: TArray<string>;
  end;

/// <summary>
/// File components are one aggregate: complete when AFilesComplete, otherwise
/// incomplete. An empty file list omits that group. Requires components
/// (framework and required-package) are complete when ARequiresDeclared and
/// the list is not empty. When the requires clause was not declared, one
/// unknown aggregate names the root bom-ref.
/// </summary>
function BuildLibraryCompositionGroups(const AArtefacts: TArtefactList;
  const ARootBomRef: string; AFilesComplete, ARequiresDeclared: Boolean):
  TArray<TLibraryCompositionGroup>;

/// <summary>
/// Writes library compositions. Omitted when there are no groups.
/// </summary>
procedure WriteLibraryCompositionsJson(ARoot: TJSONObject;
  const AGroups: TArray<TLibraryCompositionGroup>);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  DX.Comply.ComponentManifest,
  DX.Comply.UsesClauseParser;

function ShortUnitName(const ALowerName: string): string;
var
  LDot: Integer;
begin
  LDot := LastDelimiter('.', ALowerName);
  if LDot <= 0 then
    Result := ''
  else
    Result := Copy(ALowerName, LDot + 1, MaxInt);
end;

procedure RememberName(const ADict: TDictionary<string, Integer>;
  const AName: string; AIndex: Integer);
var
  LExisting: Integer;
begin
  if AName = '' then
    Exit;
  if not ADict.TryGetValue(AName, LExisting) then
    ADict.Add(AName, AIndex)
  else if LExisting <> AIndex then
    ADict[AName] := -1;
end;

function ResolveUsesName(const AExact, AShort: TDictionary<string, Integer>;
  const AName: string): Integer;
var
  LKey: string;
begin
  Result := -1;
  LKey := LowerCase(Trim(AName));
  if LKey = '' then
    Exit;
  if AExact.TryGetValue(LKey, Result) then
  begin
    if Result < 0 then
      Result := -1;
    Exit;
  end;
  if AShort.TryGetValue(LKey, Result) then
  begin
    if Result < 0 then
      Result := -1;
    Exit;
  end;
  Result := -1;
end;

function PascalPath(const AArtefact: TArtefactInfo): string;
begin
  Result := '';
  if SameText(TPath.GetExtension(AArtefact.FilePath), '.pas') then
    Exit(AArtefact.FilePath);
  if SameText(TPath.GetExtension(AArtefact.RelativePath), '.pas') then
    Result := AArtefact.RelativePath;
end;

function ReadPasFile(const APath: string; out AText: string): Boolean;
var
  LLines: TStringList;
begin
  Result := False;
  AText := '';
  if not TFile.Exists(APath) then
    Exit;

  LLines := TStringList.Create;
  try
    try
      LLines.LoadFromFile(APath, TEncoding.UTF8);
    except
      try
        LLines.LoadFromFile(APath);
      except
        Exit;
      end;
    end;
    AText := LLines.Text;
    Result := True;
  finally
    LLines.Free;
  end;
end;

function TryReadUsedUnits(const AArtefact: TArtefactInfo;
  out ANames: TArray<string>): Boolean;
var
  LPath, LText: string;
begin
  Result := False;
  ANames := nil;
  if not SameText(AArtefact.ArtefactType, 'unit-evidence') then
    Exit;

  LPath := PascalPath(AArtefact);
  if AArtefact.UsesCached then
  begin
    // The resolver already parsed this .pas, including an empty uses clause.
    // A cached DCU is not a .pas, so it stays unresolved.
    if LPath = '' then
      Exit;
    ANames := AArtefact.UsedUnitNames;
    Result := True;
    Exit;
  end;

  if (LPath = '') or not ReadPasFile(LPath, LText) then
    Exit;
  ANames := TUsesClauseParser.ExtractUsedUnits(LText);
  Result := True;
end;

procedure SortTargetIndexes(var ATargets: TArray<Integer>;
  const ANames: TArray<string>);
begin
  TArray.Sort<Integer>(ATargets, TComparer<Integer>.Construct(
    function(const Left, Right: Integer): Integer
    begin
      Result := CompareText(ANames[Left], ANames[Right]);
      if Result <> 0 then
        Exit;
      if Left < Right then
        Result := -1
      else if Left > Right then
        Result := 1
      else
        Result := 0;
    end));
end;

function BuildUsesDependencyGraph(const AArtefacts: TArtefactList): TUsesDependencyGraph;
var
  LExact, LShort: TDictionary<string, Integer>;
  LNames: TArray<string>;
  LUsed: TArray<string>;
  LTargets: TList<Integer>;
  LSeen: TDictionary<Integer, Byte>;
  LDeps: TList<TUsesDependency>;
  LDep: TUsesDependency;
  LShortName: string;
  I, J, LTarget: Integer;
  LAllResolved: Boolean;
begin
  Result := Default(TUsesDependencyGraph);
  if not Assigned(AArtefacts) then
    Exit;

  SetLength(Result.Status, AArtefacts.Count);
  SetLength(LNames, AArtefacts.Count);
  LExact := TDictionary<string, Integer>.Create;
  LShort := TDictionary<string, Integer>.Create;
  LDeps := TList<TUsesDependency>.Create;
  try
    for I := 0 to AArtefacts.Count - 1 do
    begin
      LNames[I] := LowerCase(ArtefactUnitName(AArtefacts[I]));
      if LNames[I] = '' then
        Continue;
      RememberName(LExact, LNames[I], I);
      LShortName := ShortUnitName(LNames[I]);
      if (LShortName <> '') and not SameText(LShortName, LNames[I]) then
        RememberName(LShort, LShortName, I);
    end;

    for I := 0 to AArtefacts.Count - 1 do
    begin
      if LNames[I] = '' then
      begin
        Result.Status[I] := uusNotUnit;
        Continue;
      end;

      if not TryReadUsedUnits(AArtefacts[I], LUsed) then
      begin
        Result.Status[I] := uusMissingSource;
        Continue;
      end;

      LTargets := TList<Integer>.Create;
      LSeen := TDictionary<Integer, Byte>.Create;
      try
        LAllResolved := True;
        for J := 0 to High(LUsed) do
        begin
          LTarget := ResolveUsesName(LExact, LShort, LUsed[J]);
          if LTarget < 0 then
          begin
            LAllResolved := False;
            Continue;
          end;
          // A name that only matches this unit is resolved. It is not an edge.
          if (LTarget = I) or LSeen.ContainsKey(LTarget) then
            Continue;
          LSeen.Add(LTarget, 0);
          LTargets.Add(LTarget);
        end;

        if LAllResolved then
          Result.Status[I] := uusComplete
        else
          Result.Status[I] := uusPartial;

        if LTargets.Count = 0 then
          Continue;

        LDep.SourceIndex := I;
        LDep.TargetIndexes := LTargets.ToArray;
        SortTargetIndexes(LDep.TargetIndexes, LNames);
        LDeps.Add(LDep);
      finally
        LSeen.Free;
        LTargets.Free;
      end;
    end;

    Result.Dependencies := LDeps.ToArray;
  finally
    LDeps.Free;
    LShort.Free;
    LExact.Free;
  end;
end;

procedure AppendUsesDependenciesJson(ADependencies: TJSONArray;
  const AGraph: TUsesDependencyGraph);
var
  LDep: TUsesDependency;
  LObj: TJSONObject;
  LDepends: TJSONArray;
  LTarget: Integer;
begin
  if not Assigned(ADependencies) then
    Exit;

  for LDep in AGraph.Dependencies do
  begin
    if Length(LDep.TargetIndexes) = 0 then
      Continue;
    LObj := TJSONObject.Create;
    LDepends := TJSONArray.Create;
    LObj.AddPair('ref', 'comp-' + IntToStr(LDep.SourceIndex));
    for LTarget in LDep.TargetIndexes do
      LDepends.Add('comp-' + IntToStr(LTarget));
    LObj.AddPair('dependsOn', LDepends);
    ADependencies.Add(LObj);
  end;
end;

procedure WriteUsesDependenciesXml(ALines: TStrings; AIndentLevel: Integer;
  const AGraph: TUsesDependencyGraph);
var
  LDep: TUsesDependency;
  LTarget: Integer;

  procedure AddLine(ALevel: Integer; const AText: string);
  begin
    ALines.Add(StringOfChar(' ', ALevel * 2) + AText);
  end;

begin
  if not Assigned(ALines) then
    Exit;

  for LDep in AGraph.Dependencies do
  begin
    if Length(LDep.TargetIndexes) = 0 then
      Continue;
    AddLine(AIndentLevel + 1, '<dependency ref="comp-' +
      IntToStr(LDep.SourceIndex) + '">');
    for LTarget in LDep.TargetIndexes do
      AddLine(AIndentLevel + 2, '<dependency ref="comp-' +
        IntToStr(LTarget) + '"/>');
    AddLine(AIndentLevel + 1, '</dependency>');
  end;
end;

procedure BuildCompositionRefLists(const AProjectName: string;
  const AGraph: TUsesDependencyGraph; const ALibraryRefs: TArray<string>;
  out AIncomplete, AComplete: TArray<string>);
var
  LIncomplete, LComplete: TList<string>;
  I: Integer;
  LRef: string;
begin
  AIncomplete := nil;
  AComplete := nil;
  if Trim(AProjectName) = '' then
    Exit;

  LIncomplete := TList<string>.Create;
  LComplete := TList<string>.Create;
  try
    LIncomplete.Add(AProjectName);
    for I := 0 to High(AGraph.Status) do
    begin
      LRef := 'comp-' + IntToStr(I);
      if AGraph.Status[I] = uusComplete then
        LComplete.Add(LRef)
      else
        LIncomplete.Add(LRef);
    end;
    for LRef in ALibraryRefs do
      if LRef <> '' then
        LComplete.Add(LRef);
    AIncomplete := LIncomplete.ToArray;
    AComplete := LComplete.ToArray;
  finally
    LComplete.Free;
    LIncomplete.Free;
  end;
end;

procedure WriteCompositionsJson(ARoot: TJSONObject; const AProjectName: string;
  const AGraph: TUsesDependencyGraph; const ALibraryRefs: TArray<string>);
var
  LIncomplete, LComplete: TArray<string>;
  LCompositions: TJSONArray;

  procedure AddOne(const AAggregate: string; const ARefs: TArray<string>);
  var
    LComposition: TJSONObject;
    LDeps: TJSONArray;
    LRef: string;
  begin
    if Length(ARefs) = 0 then
      Exit;
    LComposition := TJSONObject.Create;
    LDeps := TJSONArray.Create;
    LComposition.AddPair('aggregate', AAggregate);
    for LRef in ARefs do
      LDeps.Add(LRef);
    LComposition.AddPair('dependencies', LDeps);
    LCompositions.Add(LComposition);
  end;

begin
  if not Assigned(ARoot) or (Trim(AProjectName) = '') then
    Exit;

  BuildCompositionRefLists(AProjectName, AGraph, ALibraryRefs,
    LIncomplete, LComplete);
  if Length(LIncomplete) = 0 then
    Exit;

  LCompositions := TJSONArray.Create;
  AddOne('incomplete', LIncomplete);
  AddOne('complete', LComplete);
  ARoot.AddPair('compositions', LCompositions);
end;

function BuildLibraryCompositionGroups(const AArtefacts: TArtefactList;
  const ARootBomRef: string; AFilesComplete, ARequiresDeclared: Boolean):
  TArray<TLibraryCompositionGroup>;
var
  LFiles: TList<string>;
  LRequires: TList<string>;
  LGroups: TList<TLibraryCompositionGroup>;
  LGroup: TLibraryCompositionGroup;
  LType: string;
  I: Integer;
begin
  Result := nil;
  LFiles := TList<string>.Create;
  LRequires := TList<string>.Create;
  LGroups := TList<TLibraryCompositionGroup>.Create;
  try
    if Assigned(AArtefacts) then
      for I := 0 to AArtefacts.Count - 1 do
      begin
        LType := AArtefacts[I].ArtefactType;
        if SameText(LType, 'file') then
          LFiles.Add('comp-' + IntToStr(I))
        else if SameText(LType, 'framework') or
                SameText(LType, 'required-package') then
          LRequires.Add('comp-' + IntToStr(I));
      end;

    if LFiles.Count > 0 then
    begin
      LGroup.Aggregate := 'incomplete';
      if AFilesComplete then
        LGroup.Aggregate := 'complete';
      LGroup.Refs := LFiles.ToArray;
      LGroups.Add(LGroup);
    end;

    if ARequiresDeclared then
    begin
      if LRequires.Count > 0 then
      begin
        LGroup.Aggregate := 'complete';
        LGroup.Refs := LRequires.ToArray;
        LGroups.Add(LGroup);
      end;
    end
    else if Trim(ARootBomRef) <> '' then
    begin
      LGroup.Aggregate := 'unknown';
      SetLength(LGroup.Refs, 1);
      LGroup.Refs[0] := ARootBomRef;
      LGroups.Add(LGroup);
    end;

    Result := LGroups.ToArray;
  finally
    LGroups.Free;
    LRequires.Free;
    LFiles.Free;
  end;
end;

procedure WriteLibraryCompositionsJson(ARoot: TJSONObject;
  const AGroups: TArray<TLibraryCompositionGroup>);
var
  LCompositions: TJSONArray;
  LGroup: TLibraryCompositionGroup;
  LComposition: TJSONObject;
  LDeps: TJSONArray;
  LRef: string;
begin
  if not Assigned(ARoot) or (Length(AGroups) = 0) then
    Exit;

  LCompositions := TJSONArray.Create;
  for LGroup in AGroups do
  begin
    if Length(LGroup.Refs) = 0 then
      Continue;
    LComposition := TJSONObject.Create;
    LDeps := TJSONArray.Create;
    LComposition.AddPair('aggregate', LGroup.Aggregate);
    for LRef in LGroup.Refs do
      LDeps.Add(LRef);
    LComposition.AddPair('dependencies', LDeps);
    LCompositions.Add(LComposition);
  end;

  if LCompositions.Count = 0 then
  begin
    LCompositions.Free;
    Exit;
  end;
  ARoot.AddPair('compositions', LCompositions);
end;

end.
