/// <summary>
/// DX.Comply.LibrarySource
/// Collects the source files of a library release for an SBOM.
/// </summary>
///
/// <remarks>
/// A .dpk contributes the contains clause (units that have an in path) and
/// the requires clause (package names). A .dpr contributes uses entries that
/// have an in path. Units without a path are RTL or search-path units and
/// are not part of the shipped source.
///
/// A source directory is walked recursively. The extensions are .pas, .inc,
/// .dpk, .dpr, .dproj, .dfm, .fmx, .res, .dcr, and .rc. {$I} files are not
/// opened. An include file is listed only when that walk finds it.
///
/// The .dpk or .dpr itself is listed too. The result is the union of
/// both sets, de-duplicated by full path and
/// sorted by relative path. This unit does not hash files and does not
/// write an SBOM.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.LibrarySource;

interface

uses
  System.SysUtils;

type
  /// <summary>
  /// One unit named in a contains or uses clause.
  /// WrittenPath is the text after in, or empty when the clause has no path.
  /// </summary>
  TLibraryUnitRef = record
    /// <summary>Unit name as written.</summary>
    Name: string;
    /// <summary>Path after in, as written. Empty when there is no path.</summary>
    WrittenPath: string;
  end;

  /// <summary>
  /// One source file selected for the library SBOM.
  /// </summary>
  TLibrarySourceFile = record
    /// <summary>Absolute path.</summary>
    FullPath: string;
    /// <summary>Path relative to the common root, with forward slashes.</summary>
    RelativePath: string;
  end;

/// <summary>
/// Units from the first contains clause. A unit with no in path is included
/// with an empty WrittenPath. Comments and strings are skipped.
/// </summary>
function ParsePackageContains(const AText: string): TArray<TLibraryUnitRef>;

/// <summary>
/// Package names from the first requires clause, in source order.
/// Duplicate names are dropped, case-insensitively. AClauseFound is True
/// when the requires keyword was present, including an empty clause.
/// </summary>
function ParsePackageRequires(const AText: string;
  out AClauseFound: Boolean): TArray<string>;

/// <summary>
/// Uses entries that have an in path. Every uses clause is read.
/// An entry without a path is omitted.
/// </summary>
function ParseProgramUsesIn(const AText: string): TArray<TLibraryUnitRef>;

/// <summary>
/// pkg:github/owner/repo@version when ARepoUrl is
/// https://github.com/owner/repo with an optional trailing .git or slash.
/// Empty when the URL is not that shape, or when AVersion is empty.
/// </summary>
function GithubPurlFromRepoUrl(const ARepoUrl, AVersion: string): string;

/// <summary>
/// True for the Delphi framework packages rtl, vcl, and fmx.
/// A longer name such as vclimg is not a framework package.
/// </summary>
function IsDelphiFrameworkPackage(const AName: string): Boolean;

/// <summary>
/// AFullPath relative to ACommonRoot, with forward slashes.
/// A path outside the root uses ../ segments.
/// </summary>
function LibraryForwardRelativePath(const AFullPath, ACommonRoot: string): string;

/// <summary>
/// Union of the project source (AMainSourcePath is a .dpk or a .dpr, or
/// empty) and the files under ASourceDirs. ACommonRoot is the base for
/// relative paths. Include and exclude patterns use the same globs as the
/// file scanner. An empty include list keeps every file the extension
/// filter already accepted.
/// </summary>
function CollectLibrarySourceFiles(const AMainSourcePath: string;
  const ASourceDirs: TArray<string>; const ACommonRoot: string;
  const AIncludePatterns, AExcludePatterns: TArray<string>;
  out ARequires: TArray<string>; out ARequiresClauseFound: Boolean;
  out AWarnings: TArray<string>): TArray<TLibrarySourceFile>;

implementation

uses
  System.IOUtils,
  System.Types,
  System.Generics.Collections,
  System.Generics.Defaults,
  DX.Comply.FileScanner;

procedure ParseSourceClauses(const AText: string;
  out AContains: TArray<TLibraryUnitRef>; out ARequires: TArray<string>;
  out ARequiresFound: Boolean; out AUsesIn: TArray<TLibraryUnitRef>);
var
  LText: string;
  LIndex: Integer;
  LClause: Integer;
  LContainsDone: Boolean;
  LRequiresDone: Boolean;
  LExpectPath: Boolean;
  LContains: TList<TLibraryUnitRef>;
  LUses: TList<TLibraryUnitRef>;
  LRequires: TList<string>;
  LSeenRequires: TDictionary<string, Boolean>;
  LRef: TLibraryUnitRef;
  LName: string;

  function IsIdentStart(AChar: Char): Boolean;
  begin
    Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '_']);
  end;

  function IsIdentChar(AChar: Char): Boolean;
  begin
    Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']);
  end;

  function SkipTrivia: Boolean;
  begin
    Result := False;
    while LIndex <= Length(LText) do
    begin
      if LText[LIndex] <= ' ' then
      begin
        Inc(LIndex);
        Continue;
      end;

      if LText[LIndex] = '/' then
      begin
        if (LIndex < Length(LText)) and (LText[LIndex + 1] = '/') then
        begin
          Inc(LIndex, 2);
          while (LIndex <= Length(LText)) and (LText[LIndex] <> #10) and
                (LText[LIndex] <> #13) do
            Inc(LIndex);
          Continue;
        end;
        Exit(True);
      end;

      if LText[LIndex] = '{' then
      begin
        Inc(LIndex);
        while (LIndex <= Length(LText)) and (LText[LIndex] <> '}') do
          Inc(LIndex);
        if LIndex <= Length(LText) then
          Inc(LIndex);
        Continue;
      end;

      if LText[LIndex] = '(' then
      begin
        if (LIndex < Length(LText)) and (LText[LIndex + 1] = '*') then
        begin
          Inc(LIndex, 2);
          while LIndex <= Length(LText) do
          begin
            if (LText[LIndex] = '*') and (LIndex < Length(LText)) and
               (LText[LIndex + 1] = ')') then
            begin
              Inc(LIndex, 2);
              Break;
            end;
            Inc(LIndex);
          end;
          Continue;
        end;
        Exit(True);
      end;

      Exit(True);
    end;
  end;

  function ReadString: string;
  begin
    Result := '';
    if (LIndex > Length(LText)) or (LText[LIndex] <> '''') then
      Exit;
    Inc(LIndex);
    while LIndex <= Length(LText) do
    begin
      if LText[LIndex] = '''' then
      begin
        if (LIndex < Length(LText)) and (LText[LIndex + 1] = '''') then
        begin
          Result := Result + '''';
          Inc(LIndex, 2);
        end
        else
        begin
          Inc(LIndex);
          Exit;
        end;
      end
      else
      begin
        Result := Result + LText[LIndex];
        Inc(LIndex);
      end;
    end;
  end;

  function ReadIdent: string;
  begin
    Result := '';
    while (LIndex <= Length(LText)) and IsIdentChar(LText[LIndex]) do
    begin
      Result := Result + LText[LIndex];
      Inc(LIndex);
    end;
  end;

  procedure SetLastPath(const APath: string);
  var
    LItem: TLibraryUnitRef;
  begin
    if LClause = 1 then
    begin
      if LContains.Count = 0 then
        Exit;
      LItem := LContains[LContains.Count - 1];
      LItem.WrittenPath := APath;
      LContains[LContains.Count - 1] := LItem;
    end
    else if LClause = 3 then
    begin
      if LUses.Count = 0 then
        Exit;
      LItem := LUses[LUses.Count - 1];
      LItem.WrittenPath := APath;
      LUses[LUses.Count - 1] := LItem;
    end;
  end;

  procedure AddName(const AIdent: string);
  begin
    if AIdent = '' then
      Exit;
    if LClause = 2 then
      LRequires.Add(AIdent)
    else
    begin
      LRef.Name := AIdent;
      LRef.WrittenPath := '';
      if LClause = 1 then
        LContains.Add(LRef)
      else if LClause = 3 then
        LUses.Add(LRef);
    end;
  end;

  procedure EndClause;
  begin
    if LClause = 1 then
      LContainsDone := True
    else if LClause = 2 then
      LRequiresDone := True;
    LClause := 0;
    LExpectPath := False;
  end;

begin
  AContains := nil;
  ARequires := nil;
  ARequiresFound := False;
  AUsesIn := nil;

  LText := AText;
  LIndex := 1;
  if (LText <> '') and (LText[1] = #$FEFF) then
    LIndex := 2;

  // 0 none, 1 contains, 2 requires, 3 uses.
  LClause := 0;
  LContainsDone := False;
  LRequiresDone := False;
  LExpectPath := False;
  LContains := TList<TLibraryUnitRef>.Create;
  LUses := TList<TLibraryUnitRef>.Create;
  LRequires := TList<string>.Create;
  LSeenRequires := TDictionary<string, Boolean>.Create;
  try
    while SkipTrivia do
    begin
      if LText[LIndex] = '''' then
      begin
        LName := Trim(ReadString);
        if LExpectPath then
        begin
          SetLastPath(LName);
          LExpectPath := False;
        end;
      end
      else if IsIdentStart(LText[LIndex]) then
      begin
        LName := ReadIdent;
        if LExpectPath then
          LExpectPath := False;
        if LClause = 0 then
        begin
          if SameText(LName, 'contains') and not LContainsDone then
            LClause := 1
          else if SameText(LName, 'requires') and not LRequiresDone then
          begin
            LClause := 2;
            ARequiresFound := True;
          end
          else if SameText(LName, 'uses') then
            LClause := 3;
        end
        else if SameText(LName, 'in') then
          LExpectPath := True
        else
          AddName(LName);
      end
      else if LText[LIndex] = ';' then
      begin
        EndClause;
        Inc(LIndex);
      end
      else
        Inc(LIndex);
    end;

    AContains := LContains.ToArray;
    SetLength(ARequires, 0);
    for LName in LRequires do
    begin
      if LSeenRequires.ContainsKey(LowerCase(LName)) then
        Continue;
      LSeenRequires.Add(LowerCase(LName), True);
      SetLength(ARequires, Length(ARequires) + 1);
      ARequires[High(ARequires)] := LName;
    end;

    SetLength(AUsesIn, 0);
    for LRef in LUses do
      if Trim(LRef.WrittenPath) <> '' then
      begin
        SetLength(AUsesIn, Length(AUsesIn) + 1);
        AUsesIn[High(AUsesIn)] := LRef;
      end;
  finally
    LSeenRequires.Free;
    LRequires.Free;
    LUses.Free;
    LContains.Free;
  end;
end;

function ParsePackageContains(const AText: string): TArray<TLibraryUnitRef>;
var
  LRequires: TArray<string>;
  LUsesIn: TArray<TLibraryUnitRef>;
  LFound: Boolean;
begin
  ParseSourceClauses(AText, Result, LRequires, LFound, LUsesIn);
end;

function ParsePackageRequires(const AText: string;
  out AClauseFound: Boolean): TArray<string>;
var
  LContains: TArray<TLibraryUnitRef>;
  LUsesIn: TArray<TLibraryUnitRef>;
begin
  ParseSourceClauses(AText, LContains, Result, AClauseFound, LUsesIn);
end;

function ParseProgramUsesIn(const AText: string): TArray<TLibraryUnitRef>;
var
  LContains: TArray<TLibraryUnitRef>;
  LRequires: TArray<string>;
  LFound: Boolean;
begin
  ParseSourceClauses(AText, LContains, LRequires, LFound, Result);
end;

function GithubPurlFromRepoUrl(const ARepoUrl, AVersion: string): string;
var
  LUrl: string;
  LRest: string;
  LOwner: string;
  LRepo: string;
  LSlash: Integer;
begin
  Result := '';
  LUrl := Trim(ARepoUrl);
  while (LUrl <> '') and
        ((LUrl[Length(LUrl)] = '/') or (LUrl[Length(LUrl)] = '\')) do
    Delete(LUrl, Length(LUrl), 1);

  if not LUrl.StartsWith('https://github.com/', True) then
    Exit;

  LRest := Copy(LUrl, Length('https://github.com/') + 1, MaxInt);
  if (LRest = '') or (Pos('?', LRest) > 0) or (Pos('#', LRest) > 0) or
     (Pos(' ', LRest) > 0) then
    Exit;

  LSlash := Pos('/', LRest);
  if LSlash <= 1 then
    Exit;
  LOwner := Copy(LRest, 1, LSlash - 1);
  LRepo := Copy(LRest, LSlash + 1, MaxInt);
  if (LOwner = '') or (LRepo = '') or (Pos('/', LRepo) > 0) then
    Exit;
  if LRepo.EndsWith('.git', True) then
    LRepo := Copy(LRepo, 1, Length(LRepo) - 4);
  if (LRepo = '') or (Trim(AVersion) = '') then
    Exit;

  Result := 'pkg:github/' + LOwner + '/' + LRepo + '@' + Trim(AVersion);
end;

function IsDelphiFrameworkPackage(const AName: string): Boolean;
var
  LName: string;
begin
  LName := Trim(AName);
  Result := SameText(LName, 'rtl') or SameText(LName, 'vcl') or
    SameText(LName, 'fmx');
end;

function StripTrailingSeparator(const APath: string): string;
begin
  Result := APath;
  while (Length(Result) > 1) and
        ((Result[Length(Result)] = '\') or (Result[Length(Result)] = '/')) do
  begin
    if (Length(Result) = 3) and (Result[2] = ':') then
      Break;
    Delete(Result, Length(Result), 1);
  end;
end;

function ToForwardSlashes(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

function NormalizedFullPath(const APath: string): string;
begin
  Result := APath;
  if Result = '' then
    Exit;
  try
    Result := TPath.GetFullPath(Result);
  except
    on EInOutArgumentException do
      ;
  end;
  Result := StripTrailingSeparator(Result);
end;

function LibraryForwardRelativePath(const AFullPath, ACommonRoot: string): string;
var
  LFull: string;
  LRoot: string;
  LParent: string;
  LUp: string;
  LFullSlash: string;
  LRemainder: string;

  function TryUnder(const ARootSlash: string; out ARemainder: string): Boolean;
  var
    LPrefix: string;
  begin
    // A drive root keeps its slash (C:/). Any other root is compared as
    // root + '/'. SameText covers the path that is the root itself.
    ARemainder := '';
    Result := False;
    if ARootSlash = '' then
      Exit;
    if ARootSlash[Length(ARootSlash)] = '/' then
      LPrefix := ARootSlash
    else
      LPrefix := ARootSlash + '/';
    if LFullSlash.StartsWith(LPrefix, True) then
    begin
      ARemainder := Copy(LFullSlash, Length(LPrefix) + 1, MaxInt);
      Exit(True);
    end;
    if SameText(LFullSlash, ARootSlash) then
      Exit(True);
    if (Length(ARootSlash) > 1) and (ARootSlash[Length(ARootSlash)] = '/') and
       SameText(LFullSlash, Copy(ARootSlash, 1, Length(ARootSlash) - 1)) then
      Exit(True);
  end;

begin
  LFull := NormalizedFullPath(AFullPath);
  LRoot := NormalizedFullPath(ACommonRoot);
  LFullSlash := ToForwardSlashes(LFull);
  LUp := '';

  while LRoot <> '' do
  begin
    if TryUnder(ToForwardSlashes(LRoot), LRemainder) then
    begin
      if LUp = '' then
        Exit(LRemainder);
      if LRemainder = '' then
        Exit(Copy(LUp, 1, Length(LUp) - 1));
      Exit(LUp + LRemainder);
    end;

    LParent := StripTrailingSeparator(TPath.GetDirectoryName(LRoot));
    if (LParent = '') or SameText(LParent, LRoot) then
      Break;
    LUp := LUp + '../';
    LRoot := LParent;
  end;

  Result := LFullSlash;
end;

function IsLibrarySourceExtension(const AExtension: string): Boolean;
const
  cExtensions: array[0..9] of string = (
    '.pas', '.inc', '.dpk', '.dpr', '.dproj', '.dfm', '.fmx', '.res',
    '.dcr', '.rc');
var
  I: Integer;
begin
  Result := False;
  for I := Low(cExtensions) to High(cExtensions) do
    if AExtension = cExtensions[I] then
      Exit(True);
end;

function ResolveDeclaredPath(const ABaseDir, AWrittenPath: string): string;
var
  LPath: string;
begin
  LPath := Trim(AWrittenPath);
  LPath := StringReplace(LPath, '/', PathDelim, [rfReplaceAll]);
  LPath := StringReplace(LPath, '\', PathDelim, [rfReplaceAll]);
  if (ABaseDir <> '') and ((LPath = '') or TPath.IsRelativePath(LPath)) then
    LPath := TPath.Combine(ABaseDir, LPath);
  try
    Result := TPath.GetFullPath(LPath);
  except
    on EInOutArgumentException do
      Result := LPath;
  end;
end;

function CollectLibrarySourceFiles(const AMainSourcePath: string;
  const ASourceDirs: TArray<string>; const ACommonRoot: string;
  const AIncludePatterns, AExcludePatterns: TArray<string>;
  out ARequires: TArray<string>; out ARequiresClauseFound: Boolean;
  out AWarnings: TArray<string>): TArray<TLibrarySourceFile>;
var
  LWarnings: TList<string>;
  LFiles: TList<TLibrarySourceFile>;
  LSeen: TDictionary<string, Boolean>;
  LScanner: TFileScanner;
  LExt: string;
  LText: string;
  LBaseDir: string;
  LUnits: TArray<TLibraryUnitRef>;
  LUnit: TLibraryUnitRef;
  LFull: string;
  LDir: string;
  LFound: TStringDynArray;
  LPath: string;
  LWarning: string;
  LItem: TLibrarySourceFile;

  procedure AddFile(const AFullPath: string; AFromProject: Boolean);
  var
    LKey: string;
    LRel: string;
    LFileExt: string;
  begin
    if Trim(AFullPath) = '' then
      Exit;
    LKey := LowerCase(AFullPath);
    if LSeen.ContainsKey(LKey) then
      Exit;
    LSeen.Add(LKey, True);

    if not AFromProject then
    begin
      LFileExt := LowerCase(TPath.GetExtension(AFullPath));
      if not IsLibrarySourceExtension(LFileExt) then
        Exit;
    end;

    LRel := LibraryForwardRelativePath(AFullPath, ACommonRoot);
    if LRel = '' then
      LRel := ToForwardSlashes(TPath.GetFileName(AFullPath));
    if not LScanner.LibraryPathSelected(LRel) then
      Exit;

    LItem.FullPath := AFullPath;
    LItem.RelativePath := LRel;
    LFiles.Add(LItem);
  end;

  procedure AddSiblingForms(const APasPath: string);
  var
    LSibling: string;
  begin
    if not SameText(TPath.GetExtension(APasPath), '.pas') then
      Exit;
    LSibling := TPath.ChangeExtension(APasPath, '.dfm');
    if TFile.Exists(LSibling) then
      AddFile(LSibling, True);
    LSibling := TPath.ChangeExtension(APasPath, '.fmx');
    if TFile.Exists(LSibling) then
      AddFile(LSibling, True);
  end;

begin
  ARequires := nil;
  ARequiresClauseFound := False;
  AWarnings := nil;
  Result := nil;

  LWarnings := TList<string>.Create;
  LFiles := TList<TLibrarySourceFile>.Create;
  LSeen := TDictionary<string, Boolean>.Create;
  LScanner := TFileScanner.Create;
  try
    LScanner.BeginLibraryFilter(AIncludePatterns, AExcludePatterns);

    LExt := LowerCase(TPath.GetExtension(AMainSourcePath));
    if (AMainSourcePath <> '') and ((LExt = '.dpk') or (LExt = '.dpr')) then
    begin
      if not TFile.Exists(AMainSourcePath) then
        LWarnings.Add('Library main source was not found: ' + AMainSourcePath)
      else
      begin
        try
          LText := TFile.ReadAllText(AMainSourcePath);
        except
          on E: Exception do
          begin
            LText := '';
            LWarnings.Add('Could not read library main source: ' + E.Message);
          end;
        end;

        // The package or program source ships with the units it names.
        AddFile(ResolveDeclaredPath('', AMainSourcePath), True);
        LBaseDir := TPath.GetDirectoryName(AMainSourcePath);
        if LExt = '.dpk' then
        begin
          ARequires := ParsePackageRequires(LText, ARequiresClauseFound);
          LUnits := ParsePackageContains(LText);
        end
        else
          LUnits := ParseProgramUsesIn(LText);

        for LUnit in LUnits do
        begin
          if Trim(LUnit.WrittenPath) = '' then
            Continue;
          LFull := ResolveDeclaredPath(LBaseDir, LUnit.WrittenPath);
          AddFile(LFull, True);
          AddSiblingForms(LFull);
        end;
      end;
    end;

    for LDir in ASourceDirs do
    begin
      if Trim(LDir) = '' then
        Continue;
      if not TDirectory.Exists(LDir) then
      begin
        LWarnings.Add('Source directory not found: ' + LDir);
        Continue;
      end;

      try
        LFound := TDirectory.GetFiles(LDir, '*', TSearchOption.soAllDirectories);
      except
        on E: Exception do
        begin
          LWarnings.Add('Could not read source directory "' + LDir + '": ' +
            E.Message);
          Continue;
        end;
      end;

      for LPath in LFound do
        AddFile(LPath, False);
    end;

    for LWarning in LScanner.PatternWarnings do
      if LWarnings.IndexOf(LWarning) < 0 then
        LWarnings.Add(LWarning);

    Result := LFiles.ToArray;
    TArray.Sort<TLibrarySourceFile>(Result,
      TComparer<TLibrarySourceFile>.Construct(
        function(const ALeft, ARight: TLibrarySourceFile): Integer
        begin
          Result := CompareText(ALeft.RelativePath, ARight.RelativePath);
          if Result = 0 then
            Result := CompareText(ALeft.FullPath, ARight.FullPath);
        end));
    AWarnings := LWarnings.ToArray;
  finally
    LScanner.Free;
    LSeen.Free;
    LFiles.Free;
    LWarnings.Free;
  end;
end;

end.
