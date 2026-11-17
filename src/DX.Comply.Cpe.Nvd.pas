/// <summary>
/// DX.Comply.Cpe.Nvd
/// NVD CPE API 2.0 keyword search and response parsing.
/// </summary>
///
/// <remarks>
/// ParseNvdCpeResponse reads a recorded JSON document and does not use the
/// network. SearchNvdCpes calls the public API only when the caller asks.
/// An empty keyword returns before any request. The call works without an
/// API key. When a key is passed it is sent as the apiKey header and is
/// not written into the URL or into error text. A timeout or an HTTP
/// failure becomes a message the caller can show.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Cpe.Nvd;

interface

uses
  System.SysUtils;

const
  /// <summary>NVD CPE API 2.0 collection.</summary>
  cNvdCpeApiUrl = 'https://services.nvd.nist.gov/rest/json/cpes/2.0';

type
  /// <summary>One CPE name from an NVD CPE API 2.0 products entry.</summary>
  TNvdCpeMatch = record
    /// <summary>cpeName, a CPE 2.3 formatted string when the service sends one.</summary>
    CpeName: string;
    /// <summary>English title when one is present, otherwise the first title.</summary>
    Title: string;
    /// <summary>True when the service marks the name deprecated.</summary>
    Deprecated: Boolean;
    /// <summary>cpeNameId. Empty when the response omits it.</summary>
    CpeNameId: string;
  end;

  /// <summary>Parsed NVD CPE API 2.0 keyword response, or a search error.</summary>
  TNvdCpeSearchResult = record
    /// <summary>totalResults. Zero when the body could not be parsed.</summary>
    TotalResults: Integer;
    /// <summary>The products returned in this page.</summary>
    Matches: TArray<TNvdCpeMatch>;
    /// <summary>Empty when the body was accepted. A search failure is set here.</summary>
    Error: string;
    /// <summary>True when Error is empty.</summary>
    function IsSuccess: Boolean;
  end;

/// <summary>
/// Parses an NVD CPE API 2.0 JSON body. Does not call the network.
/// A body that is not a JSON object sets Error and leaves Matches empty.
/// </summary>
function ParseNvdCpeResponse(const AJson: string): TNvdCpeSearchResult;

/// <summary>
/// Keyword search against the NVD CPE API 2.0. A blank keyword does not
/// open a connection. AApiKey empty sends no apiKey header. The key is
/// not placed in the URL or in Error. Connection and response each wait
/// up to 20 seconds.
/// </summary>
function SearchNvdCpes(const AKeyword, AApiKey: string): TNvdCpeSearchResult;

/// <summary>
/// Number of matches as text. One page holds up to 50 names. When the
/// service reports more, the text is "50 of 312", so the reader knows the
/// list is not complete.
/// </summary>
function NvdCpeMatchCountText(const AResult: TNvdCpeSearchResult): string;

/// <summary>
/// Text --cpe-lookup prints. AKeyLogLine is the source line from
/// NvdApiKeyLogLine. The key itself is not accepted here. A failed search
/// stops after the keyword. Zero matches names --cpe-dictionary and says
/// that NIST may normalize the vendor and product.
/// </summary>
function FormatNvdCpeLookupReport(const AKeyword, AKeyLogLine: string;
  const AResult: TNvdCpeSearchResult): string;

implementation

uses
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.Net.URLClient,
  System.Net.HttpClient,
  System.NetEncoding,
  DX.Comply.Cpe.NvdKey;

function TNvdCpeSearchResult.IsSuccess: Boolean;
begin
  Result := Error = '';
end;

function JsonObject(AValue: TJSONValue): TJSONObject;
begin
  if AValue is TJSONObject then
    Result := TJSONObject(AValue)
  else
    Result := nil;
end;

function JsonArray(AValue: TJSONValue): TJSONArray;
begin
  if AValue is TJSONArray then
    Result := TJSONArray(AValue)
  else
    Result := nil;
end;

function JsonText(AObject: TJSONObject; const AName: string): string;
var
  LValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  LValue := AObject.GetValue(AName);
  if (LValue = nil) or (LValue is TJSONNull) then
    Exit;
  if (LValue is TJSONString) or (LValue is TJSONNumber) then
    Result := LValue.Value;
end;

function PreferredTitle(ACpe: TJSONObject): string;
var
  LTitles: TJSONArray;
  LItem: TJSONValue;
  LTitle: TJSONObject;
  LLang, LText, LFirst: string;
begin
  Result := '';
  LFirst := '';
  if ACpe = nil then
    Exit;
  LTitles := JsonArray(ACpe.GetValue('titles'));
  if LTitles = nil then
    Exit;
  for LItem in LTitles do
  begin
    LTitle := JsonObject(LItem);
    if LTitle = nil then
      Continue;
    LText := Trim(JsonText(LTitle, 'title'));
    if LText = '' then
      Continue;
    if LFirst = '' then
      LFirst := LText;
    LLang := LowerCase(Trim(JsonText(LTitle, 'lang')));
    if (LLang = 'en') or LLang.StartsWith('en-') then
      Exit(LText);
  end;
  Result := LFirst;
end;

function ParseNvdCpeResponse(const AJson: string): TNvdCpeSearchResult;
var
  LRootValue: TJSONValue;
  LRoot, LProduct, LCpe: TJSONObject;
  LProducts: TJSONArray;
  LItem: TJSONValue;
  LMatch: TNvdCpeMatch;
  LTotal: TJSONValue;
begin
  Result.TotalResults := 0;
  SetLength(Result.Matches, 0);
  Result.Error := '';
  LRootValue := TJSONObject.ParseJSONValue(AJson);
  if LRootValue = nil then
  begin
    Result.Error := 'The NVD response is not valid JSON.';
    Exit;
  end;
  try
    LRoot := JsonObject(LRootValue);
    if LRoot = nil then
    begin
      Result.Error := 'The NVD response is not a JSON object.';
      Exit;
    end;
    LTotal := LRoot.GetValue('totalResults');
    if LTotal is TJSONNumber then
      Result.TotalResults := TJSONNumber(LTotal).AsInt
    else if (LTotal is TJSONString) and (Trim(LTotal.Value) <> '') then
      Result.TotalResults := StrToIntDef(Trim(LTotal.Value), 0);
    LProducts := JsonArray(LRoot.GetValue('products'));
    if LProducts = nil then
      Exit;
    for LItem in LProducts do
    begin
      LProduct := JsonObject(LItem);
      if LProduct = nil then
        Continue;
      LCpe := JsonObject(LProduct.GetValue('cpe'));
      if LCpe = nil then
        Continue;
      LMatch.CpeName := Trim(JsonText(LCpe, 'cpeName'));
      LMatch.Title := PreferredTitle(LCpe);
      LMatch.Deprecated := False;
      if LCpe.GetValue('deprecated') is TJSONBool then
        LMatch.Deprecated := TJSONBool(LCpe.GetValue('deprecated')).AsBoolean;
      LMatch.CpeNameId := Trim(JsonText(LCpe, 'cpeNameId'));
      if LMatch.CpeName = '' then
        Continue;
      SetLength(Result.Matches, Length(Result.Matches) + 1);
      Result.Matches[High(Result.Matches)] := LMatch;
    end;
  finally
    LRootValue.Free;
  end;
end;

function OneLineSnippet(const ABody: string): string;
var
  LText: string;
  LChar: Char;
begin
  LText := '';
  for LChar in ABody do
  begin
    if LChar < ' ' then
    begin
      if (LText <> '') and (LText[Length(LText)] <> ' ') then
        LText := LText + ' ';
    end
    else
      LText := LText + LChar;
    if Length(LText) >= 160 then
      Break;
  end;
  Result := Trim(LText);
end;

function NvdHttpFailureMessage(AStatus: Integer; const ABody: string;
  AKeyWasSet: Boolean): string;
var
  LSnippet: string;
begin
  if (AStatus = 403) or (AStatus = 429) then
  begin
    if AKeyWasSet then
      Result := Format('The NVD CPE search was refused (HTTP %d). The key was not accepted, ' +
        'or the service is limiting requests. Wait and try again.', [AStatus])
    else
      Result := Format('The NVD CPE search was refused (HTTP %d). The public service limits ' +
        'how often it answers when no API key is set. Request a key at %s. ' +
        'Save it on the CPE tab, pass --nvd-api-key, or set %s.',
        [AStatus, cNvdApiKeyRequestUrl, cNvdApiKeyEnvironmentVariable]);
    Exit;
  end;
  Result := Format('The NVD CPE search failed (HTTP %d).', [AStatus]);
  LSnippet := OneLineSnippet(ABody);
  if LSnippet <> '' then
    Result := Result + ' ' + LSnippet;
end;

function IsTimeoutMessage(const AMessage: string): Boolean;
var
  LMessage: string;
begin
  LMessage := LowerCase(AMessage);
  Result := (Pos('timeout', LMessage) > 0) or (Pos('timed out', LMessage) > 0);
end;

function SearchNvdCpes(const AKeyword, AApiKey: string): TNvdCpeSearchResult;
var
  LKeyword, LApiKey, LUrl, LMessage: string;
  LClient: THTTPClient;
  LResponse: IHTTPResponse;
  LHeaders: TNetHeaders;
begin
  Result.TotalResults := 0;
  SetLength(Result.Matches, 0);
  Result.Error := '';
  LKeyword := Trim(AKeyword);
  if LKeyword = '' then
  begin
    Result.Error := 'Enter a keyword before searching the NVD.';
    Exit;
  end;
  LApiKey := Trim(AApiKey);
  LUrl := cNvdCpeApiUrl + '?keywordSearch=' + TNetEncoding.URL.Encode(LKeyword) +
    '&resultsPerPage=50';
  LClient := THTTPClient.Create;
  try
    try
      LClient.ConnectionTimeout := 20000;
      LClient.ResponseTimeout := 20000;
      LClient.UserAgent := 'DX.Comply';
      SetLength(LHeaders, 0);
      if LApiKey <> '' then
      begin
        SetLength(LHeaders, 1);
        LHeaders[0] := TNetHeader.Create('apiKey', LApiKey);
      end;
      LResponse := LClient.Get(LUrl, nil, LHeaders);
      if LResponse.StatusCode <> 200 then
      begin
        Result.Error := NvdHttpFailureMessage(LResponse.StatusCode,
          LResponse.ContentAsString, LApiKey <> '');
        Exit;
      end;
      Result := ParseNvdCpeResponse(LResponse.ContentAsString);
    except
      on E: Exception do
      begin
        // A transport error must not repeat the key if the client included it.
        LMessage := E.Message;
        if LApiKey <> '' then
          LMessage := StringReplace(LMessage, LApiKey, '(api key)', [rfReplaceAll]);
        if IsTimeoutMessage(LMessage) then
          Result.Error := 'The NVD CPE search timed out. Check the network connection and try again.'
        else
          Result.Error := 'The NVD CPE search failed: ' + LMessage;
      end;
    end;
  finally
    LClient.Free;
  end;
end;

function NvdCpeMatchCountText(const AResult: TNvdCpeSearchResult): string;
begin
  Result := IntToStr(Length(AResult.Matches));
  if AResult.TotalResults > Length(AResult.Matches) then
    Result := Result + ' of ' + IntToStr(AResult.TotalResults);
end;

function FormatNvdCpeLookupReport(const AKeyword, AKeyLogLine: string;
  const AResult: TNvdCpeSearchResult): string;
var
  LLines: TStringList;
  LMatch: TNvdCpeMatch;
  LState: string;
begin
  LLines := TStringList.Create;
  try
    LLines.WriteBOM := False;
    if Trim(AKeyLogLine) <> '' then
      LLines.Add(Trim(AKeyLogLine));
    LLines.Add('Keyword: ' + Trim(AKeyword));
    if not AResult.IsSuccess then
      Exit(LLines.Text);
    LLines.Add('Matches: ' + NvdCpeMatchCountText(AResult));
    if AResult.TotalResults > Length(AResult.Matches) then
      LLines.Add('Only the first page is listed. Use a narrower vendor and product to see the others.');
    for LMatch in AResult.Matches do
    begin
      LLines.Add(LMatch.CpeName);
      if Trim(LMatch.Title) <> '' then
        LLines.Add('  ' + Trim(LMatch.Title));
      if LMatch.Deprecated then
        LState := 'deprecated'
      else
        LState := 'current';
      LLines.Add('  ' + LState);
    end;
    if Length(AResult.Matches) = 0 then
    begin
      LLines.Add('No CPE was found for this vendor and product.');
      LLines.Add('The vendor and product strings are a proposal. NIST may normalize them.');
      LLines.Add('To request a new CPE, run again with --cpe-dictionary. That writes a dictionary file and a mail text next to the SBOM. DX.Comply does not send the message.');
    end;
    Result := LLines.Text;
  finally
    LLines.Free;
  end;
end;

end.
