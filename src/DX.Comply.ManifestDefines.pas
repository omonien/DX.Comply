/// <summary>
/// DX.Comply.ManifestDefines
/// Named values for $(name) placeholders in manifest path fields.
/// </summary>
///
/// <remarks>
/// A definition comes from --define, the defines object in .dxcomply.json,
/// or the IDE options. $(name) reads a definition. $(env.NAME) reads the
/// environment variable NAME when no definition of that full name exists.
/// A definition wins over the environment. $$ is an escape for a literal $.
/// An unknown name is an error. The text names the variable, the manifest
/// row, and the field. Issue #185.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.ManifestDefines;

interface

uses
  System.Classes,
  System.JSON,
  System.Generics.Collections;

const
  /// <summary>
  /// How many substitutions one path may nest. A cycle fails before this.
  /// </summary>
  cMaxManifestDefineDepth = 8;

type
  /// <summary>
  /// One manifest path variable. Name is compared without case.
  /// </summary>
  TManifestDefine = record
    /// <summary>Variable name, such as path.libs or env.LIBS.</summary>
    Name: string;
    /// <summary>Replacement text. A path may contain spaces and backslashes.</summary>
    Value: string;
  end;

  /// <summary>
  /// One placeholder that was replaced. The log line names these fields.
  /// </summary>
  TManifestVariableUse = record
    /// <summary>The name inside $(name), including an env. prefix.</summary>
    Name: string;
    /// <summary>The text that replaced it, after nested placeholders.</summary>
    Value: string;
    /// <summary>define or environment.</summary>
    Source: string;
    /// <summary>Manifest row, or Manifest for a root field.</summary>
    Context: string;
    /// <summary>units_folder or own_code_folders.</summary>
    Field: string;
  end;

/// <summary>
/// True when AName is a letter or underscore, then letters, digits,
/// underscore, or dot. path.libs and env.LIBS are valid.
/// </summary>
function IsValidManifestDefineName(const AName: string): Boolean;

/// <summary>
/// Parses name=value. A surrounding pair of double quotes on the value is
/// removed. Backslashes are kept. The value is trimmed.
/// </summary>
function TryParseDefineAssignment(const AText: string;
  out ADefine: TManifestDefine; out AError: string): Boolean;

/// <summary>
/// Parses one name=value per line. A blank line is skipped.
/// </summary>
function TryManifestDefinesFromLines(ALines: TStrings;
  out ADefines: TArray<TManifestDefine>; out AError: string): Boolean;

/// <summary>
/// One name=value line per definition, in order.
/// </summary>
function ManifestDefinesToLines(const ADefines: TArray<TManifestDefine>): TArray<string>;

/// <summary>
/// Later entries of AOverride replace the same name in ABase.
/// Names only in ABase stay. Comparison ignores case.
/// </summary>
function MergeManifestDefines(const ABase, AOverride: TArray<TManifestDefine>): TArray<TManifestDefine>;

/// <summary>
/// The last definition of AName. Comparison ignores case.
/// </summary>
function FindManifestDefine(const ADefines: TArray<TManifestDefine>;
  const AName: string; out AValue: string): Boolean;

/// <summary>
/// True when the environment variable exists, including when its value is
/// empty. False when it is not set.
/// </summary>
function TryReadEnvironmentVariable(const AName: string; out AValue: string): Boolean;

/// <summary>
/// Reads a defines object. A missing value yields an empty list.
/// A value that is not an object, a name that is not valid, or a value
/// that is not a string is skipped and named in AWarnings.
/// </summary>
function ReadManifestDefines(AValue: TJSONValue; const ASourceName: string;
  AWarnings: TList<string>): TArray<TManifestDefine>;

/// <summary>
/// Replaces $(name) and $(env.NAME) in AText. $$ becomes one dollar, so
/// $$(name) stays as the characters $(name). Expansion is done before the
/// caller normalizes a path. AUses may be nil. On failure AError names the
/// variable, AContext, and AField.
/// </summary>
function TryExpandManifestPath(const AText, AContext, AField: string;
  const ADefines: TArray<TManifestDefine>;
  out AExpanded, AError: string;
  AUses: TList<TManifestVariableUse>): Boolean;

/// <summary>
/// Info line for one substitution. The CLI prints lines that start with Info.
/// </summary>
function ManifestVariableLogLine(const AUse: TManifestVariableUse): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Winapi.Windows;

function IsValidManifestDefineName(const AName: string): Boolean;
var
  I: Integer;
  LChar: Char;
begin
  Result := False;
  if AName = '' then
    Exit;
  LChar := AName[1];
  if not CharInSet(LChar, ['A'..'Z', 'a'..'z', '_']) then
    Exit;
  for I := 2 to Length(AName) do
  begin
    LChar := AName[I];
    if not CharInSet(LChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
      Exit;
  end;
  Result := True;
end;

function StripMatchingQuotes(const AValue: string): string;
begin
  Result := AValue;
  if (Length(Result) >= 2) and (Result[1] = '"') and
    (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function TryParseDefineAssignment(const AText: string;
  out ADefine: TManifestDefine; out AError: string): Boolean;
var
  LText, LName, LValue: string;
  LPos: Integer;
begin
  ADefine := Default(TManifestDefine);
  AError := '';
  Result := False;
  LText := Trim(AText);
  LPos := Pos('=', LText);
  if LPos < 1 then
  begin
    AError := 'expected name=value.';
    Exit;
  end;
  LName := Trim(Copy(LText, 1, LPos - 1));
  // Quotes are removed. Backslashes stay, so a Windows path is unchanged.
  LValue := Trim(StripMatchingQuotes(Copy(LText, LPos + 1, MaxInt)));
  if LName = '' then
  begin
    AError := 'name is empty.';
    Exit;
  end;
  if not IsValidManifestDefineName(LName) then
  begin
    AError := 'name "' + LName +
      '" is not a valid variable name. Use a letter or underscore, then letters, digits, underscore, or dot.';
    Exit;
  end;
  ADefine.Name := LName;
  ADefine.Value := LValue;
  Result := True;
end;

function TryManifestDefinesFromLines(ALines: TStrings;
  out ADefines: TArray<TManifestDefine>; out AError: string): Boolean;
var
  LList: TList<TManifestDefine>;
  I: Integer;
  LLine: string;
  LDefine: TManifestDefine;
begin
  SetLength(ADefines, 0);
  AError := '';
  Result := True;
  if not Assigned(ALines) then
    Exit;
  LList := TList<TManifestDefine>.Create;
  try
    for I := 0 to ALines.Count - 1 do
    begin
      LLine := Trim(ALines[I]);
      if LLine = '' then
        Continue;
      if not TryParseDefineAssignment(LLine, LDefine, AError) then
      begin
        AError := 'line ' + IntToStr(I + 1) + ': ' + AError;
        SetLength(ADefines, 0);
        Exit(False);
      end;
      LList.Add(LDefine);
    end;
    ADefines := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function ManifestDefinesToLines(const ADefines: TArray<TManifestDefine>): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(ADefines));
  for I := 0 to High(ADefines) do
    Result[I] := ADefines[I].Name + '=' + ADefines[I].Value;
end;

function MergeManifestDefines(const ABase, AOverride: TArray<TManifestDefine>): TArray<TManifestDefine>;
var
  LList: TList<TManifestDefine>;
  I, J: Integer;
  LFound: Boolean;
  LItem: TManifestDefine;
begin
  LList := TList<TManifestDefine>.Create;
  try
    for I := 0 to High(ABase) do
      LList.Add(ABase[I]);
    for I := 0 to High(AOverride) do
    begin
      LFound := False;
      for J := LList.Count - 1 downto 0 do
        if SameText(LList[J].Name, AOverride[I].Name) then
        begin
          LItem := AOverride[I];
          LList[J] := LItem;
          LFound := True;
          Break;
        end;
      if not LFound then
        LList.Add(AOverride[I]);
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function FindManifestDefine(const ADefines: TArray<TManifestDefine>;
  const AName: string; out AValue: string): Boolean;
var
  I: Integer;
begin
  AValue := '';
  Result := False;
  for I := High(ADefines) downto 0 do
    if SameText(ADefines[I].Name, AName) then
    begin
      AValue := ADefines[I].Value;
      Exit(True);
    end;
end;

function TryReadEnvironmentVariable(const AName: string; out AValue: string): Boolean;
var
  LLen: DWORD;
begin
  AValue := '';
  Result := False;
  if AName = '' then
    Exit;
  // A zero length means the variable is not set. A length of one means it
  // is set to an empty string (the buffer counts the terminating null).
  LLen := GetEnvironmentVariable(PChar(AName), nil, 0);
  if LLen = 0 then
    Exit;
  SetLength(AValue, LLen - 1);
  if LLen > 1 then
    GetEnvironmentVariable(PChar(AName), PChar(AValue), LLen);
  Result := True;
end;

function ReadManifestDefines(AValue: TJSONValue; const ASourceName: string;
  AWarnings: TList<string>): TArray<TManifestDefine>;
var
  LObject: TJSONObject;
  I: Integer;
  LPair: TJSONPair;
  LName, LText: string;
  LList: TList<TManifestDefine>;
  LDefine: TManifestDefine;

  procedure Warn(const AMessage: string);
  begin
    if Assigned(AWarnings) then
      AWarnings.Add(AMessage);
  end;

begin
  Result := nil;
  if (AValue = nil) or (AValue is TJSONNull) then
    Exit;
  if not (AValue is TJSONObject) then
  begin
    Warn('defines in ' + ASourceName + ' should be an object and was ignored');
    Exit;
  end;

  LObject := TJSONObject(AValue);
  LList := TList<TManifestDefine>.Create;
  try
    for I := 0 to LObject.Count - 1 do
    begin
      LPair := LObject.Pairs[I];
      LName := Trim(LPair.JsonString.Value);
      if not IsValidManifestDefineName(LName) then
      begin
        Warn('defines in ' + ASourceName + ': name "' + LName +
          '" is not a valid variable name and was ignored');
        Continue;
      end;
      if not (LPair.JsonValue is TJSONString) then
      begin
        Warn('defines in ' + ASourceName + ': "' + LName +
          '" should be a string and was ignored');
        Continue;
      end;
      LText := Trim(TJSONString(LPair.JsonValue).Value);
      LDefine.Name := LName;
      LDefine.Value := LText;
      LList.Add(LDefine);
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function StackContains(AStack: TList<string>; const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to AStack.Count - 1 do
    if SameText(AStack[I], AName) then
      Exit(True);
end;

function TryExpandManifestPath(const AText, AContext, AField: string;
  const ADefines: TArray<TManifestDefine>;
  out AExpanded, AError: string;
  AUses: TList<TManifestVariableUse>): Boolean;
var
  LStack: TList<string>;

  function ExpandText(const AInput: string; out AOutput: string): Boolean;
  var
    I, LClose: Integer;
    LName, LValue, LExpandedValue, LSource, LEnvName: string;
    LUse: TManifestVariableUse;
  begin
    Result := True;
    AOutput := '';
    I := 1;
    while I <= Length(AInput) do
    begin
      if AInput[I] <> '$' then
      begin
        AOutput := AOutput + AInput[I];
        Inc(I);
        Continue;
      end;

      // $$ is one literal dollar. The next character is not expanded,
      // so $$(name) is the four characters $(name).
      if (I < Length(AInput)) and (AInput[I + 1] = '$') then
      begin
        AOutput := AOutput + '$';
        Inc(I, 2);
        Continue;
      end;

      if (I >= Length(AInput)) or (AInput[I + 1] <> '(') then
      begin
        AOutput := AOutput + '$';
        Inc(I);
        Continue;
      end;

      LClose := Pos(')', AInput, I + 2);
      if LClose = 0 then
      begin
        AError := AContext + ': ' + AField + ': unclosed placeholder "' +
          Copy(AInput, I, Length(AInput) - I + 1) + '"';
        Exit(False);
      end;

      LName := Trim(Copy(AInput, I + 2, LClose - (I + 2)));
      if LName = '' then
      begin
        AError := AContext + ': ' + AField + ': empty variable name';
        Exit(False);
      end;
      if not IsValidManifestDefineName(LName) then
      begin
        AError := AContext + ': ' + AField + ': invalid variable name "' + LName + '"';
        Exit(False);
      end;
      if StackContains(LStack, LName) then
      begin
        AError := AContext + ': ' + AField + ': variable "' + LName + '" refers to itself';
        Exit(False);
      end;
      if LStack.Count >= cMaxManifestDefineDepth then
      begin
        AError := AContext + ': ' + AField + ': variable "' + LName + '" is nested too deeply';
        Exit(False);
      end;

      // A definition of the full name wins, including a name that starts
      // with env. Only an unmatched env. prefix reads the environment.
      if FindManifestDefine(ADefines, LName, LValue) then
        LSource := 'define'
      else if StartsText('env.', LName) and (Length(LName) > Length('env.')) then
      begin
        LEnvName := Copy(LName, Length('env.') + 1, MaxInt);
        if not TryReadEnvironmentVariable(LEnvName, LValue) then
        begin
          AError := AContext + ': ' + AField + ': undefined variable "' + LName + '"';
          Exit(False);
        end;
        LSource := 'environment';
      end
      else
      begin
        AError := AContext + ': ' + AField + ': undefined variable "' + LName + '"';
        Exit(False);
      end;

      LStack.Add(LName);
      try
        if not ExpandText(LValue, LExpandedValue) then
          Exit(False);
      finally
        LStack.Delete(LStack.Count - 1);
      end;

      if Assigned(AUses) then
      begin
        LUse.Name := LName;
        LUse.Value := LExpandedValue;
        LUse.Source := LSource;
        LUse.Context := AContext;
        LUse.Field := AField;
        AUses.Add(LUse);
      end;
      AOutput := AOutput + LExpandedValue;
      I := LClose + 1;
    end;
  end;

begin
  AExpanded := '';
  AError := '';
  Result := True;
  if Pos('$', AText) = 0 then
  begin
    AExpanded := AText;
    Exit;
  end;

  LStack := TList<string>.Create;
  try
    Result := ExpandText(AText, AExpanded);
    if not Result then
      AExpanded := '';
  finally
    LStack.Free;
  end;
end;

function ManifestVariableLogLine(const AUse: TManifestVariableUse): string;
begin
  Result := 'Info: Manifest variable "' + AUse.Name + '" = "' + AUse.Value +
    '" (' + AUse.Source + ', ' + AUse.Field + ', ' + AUse.Context + ')';
end;

end.
