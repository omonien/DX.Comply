// DX.Comply: remove stale GetIt library path entries (issue #67)
//
// A GetIt install of DX.Comply adds folders of its CatalogRepository copy,
// for example ...\CatalogRepository\DXComply-13\1.0.1\lib, src and assets,
// to the Delphi library and browsing paths. When that copy is gone but the
// entries stay, every compile shows hint H2675 "directory not found".
//
// This file is included in the [Code] section of DX.Comply.D13.iss. It
// removes only entries that point into a DXComply-* folder of the GetIt
// CatalogRepository and whose folder does not exist. Entries of an installed
// GetIt copy, and every other entry, stay unchanged.

const
  DXComplyLibraryKey = '{#BDSRegKey}\Library';

function DXComplyCatalogRepositoryDir: String;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER,
    '{#BDSRegKey}\Environment Variables', 'BDSCatalogRepository', Result) or
    (Result = '') then
    Result := ExpandConstant('{userdocs}\Embarcadero\Studio\{#BDSVersion}\CatalogRepository');
end;

function DXComplyExpandPathEntry(const AEntry: String): String;
begin
  Result := Trim(AEntry);
  StringChangeEx(Result, '$(BDSCatalogRepository)', DXComplyCatalogRepositoryDir, True);
end;

function IsStaleDXComplyGetItEntry(const AEntry: String): Boolean;
var
  LLower: String;
  LExpanded: String;
begin
  Result := False;
  LLower := Lowercase(AEntry);
  if (Pos('catalogrepository', LLower) = 0) or (Pos('\dxcomply-', LLower) = 0) then
    Exit;
  LExpanded := DXComplyExpandPathEntry(AEntry);
  // A macro that is not resolved here, such as $(Platform), cannot be
  // checked. Such an entry is kept.
  if Pos('$(', LExpanded) > 0 then
    Exit;
  Result := not DirExists(LExpanded);
end;

function RemoveStaleDXComplyEntries(const AValue: String; var AChanged: Boolean): String;
var
  LRest: String;
  LEntry: String;
  LPos: Integer;
begin
  Result := '';
  AChanged := False;
  LRest := AValue;
  while LRest <> '' do
  begin
    LPos := Pos(';', LRest);
    if LPos > 0 then
    begin
      LEntry := Copy(LRest, 1, LPos - 1);
      Delete(LRest, 1, LPos);
    end
    else
    begin
      LEntry := LRest;
      LRest := '';
    end;

    if IsStaleDXComplyGetItEntry(LEntry) then
      AChanged := True
    else if LEntry <> '' then
    begin
      if Result <> '' then
        Result := Result + ';';
      Result := Result + LEntry;
    end;
  end;
end;

procedure CleanStaleDXComplyGetItPaths;
var
  LPlatforms: TArrayOfString;
  LValueNames: TArrayOfString;
  LKey: String;
  LValue: String;
  LNewValue: String;
  LChanged: Boolean;
  I: Integer;
  J: Integer;
begin
  if not RegGetSubkeyNames(HKEY_CURRENT_USER, DXComplyLibraryKey, LPlatforms) then
    Exit;

  SetArrayLength(LValueNames, 3);
  LValueNames[0] := 'Search Path';
  LValueNames[1] := 'Browsing Path';
  LValueNames[2] := 'Debug DCU Path';

  for I := 0 to GetArrayLength(LPlatforms) - 1 do
  begin
    LKey := DXComplyLibraryKey + '\' + LPlatforms[I];
    for J := 0 to GetArrayLength(LValueNames) - 1 do
      if RegQueryStringValue(HKEY_CURRENT_USER, LKey, LValueNames[J], LValue) then
      begin
        LNewValue := RemoveStaleDXComplyEntries(LValue, LChanged);
        if LChanged then
        begin
          Log('DX.Comply: removed stale GetIt entries from ' + LKey + '\' + LValueNames[J]);
          RegWriteStringValue(HKEY_CURRENT_USER, LKey, LValueNames[J], LNewValue);
        end;
      end;
  end;
end;
