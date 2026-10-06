/// <summary>
/// DX.Comply.Spdx.Writer
/// Generates SPDX 2.3 SBOM documents in JSON format.
/// </summary>
///
/// <remarks>
/// This unit provides TSpdxJsonWriter which generates SPDX 2.3 JSON SBOMs:
/// - Document creation information (tool, timestamp, namespace)
/// - Package list with checksums (SHA-256)
/// - Relationship graph (DESCRIBES, CONTAINS)
/// - Extracted licensing information
///
/// SPDX 2.3 specification: https://spdx.github.io/spdx-spec/v2.3/
///
/// Package SPDX IDs are derived from the relative path plus a short stable
/// hash so the same filename in two folders does not collide (issue #39).
/// creationInfo.created is UTC YYYY-MM-DDThh:mm:ssZ. Package external
/// references use a percent-encoded pkg:generic PURL so the locator has no
/// whitespace (issue #40). licenseConcluded and licenseDeclared are
/// NOASSERTION. supplier uses Organization: when metadata supplies a name.
///
/// Note: This is a Pro-tier feature but is included in the Community edition
/// for completeness. Access control is handled at the application level.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Spdx.Writer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Generics.Collections,
  System.DateUtils,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Implementation of ISbomWriter for SPDX 2.3 JSON format.
  /// </summary>
  TSpdxJsonWriter = class(TInterfacedObject, ISbomWriter)
  private
    const
      cSpdxVersion = 'SPDX-2.3';
      cDataLicense = 'CC0-1.0';
      cToolName = 'DX.Comply';
      cToolVersion = '1.0.0';
      cSpdxIdPrefix = 'SPDXRef-';
  private
    function GenerateUuid: string;
    function SanitizeSpdxId(const AValue: string): string;
    function NormalizeSpdxPath(const APath: string): string;
    function BuildPackageSpdxId(const ARelativePath: string): string;
    function CollectPackageSpdxIds(const AArtefacts: TArtefactList): TArray<string>;
    function FormatSpdxCreated(const ATimestamp: string): string;
    function TryParseSpdxTimestamp(const ATimestamp: string; out AUtc: TDateTime): Boolean;
    function BuildGenericPurl(const ARelativePath: string): string;
    function BuildCreationInfo(const AMetadata: TSbomMetadata): TJSONObject;
    function BuildPackage(const AArtefact: TArtefactInfo; const ASpdxId,
      ASupplier: string): TJSONObject;
    function BuildRelationships(const APackageIds: TArray<string>;
      const ADocumentSpdxId: string): TJSONArray;
  public
    function Write(const AOutputPath: string;
      const AMetadata: TSbomMetadata;
      const AArtefacts: TArtefactList;
      const AProjectInfo: TProjectInfo): Boolean;
    function GetFormat: TSbomFormat;
    function Validate(const AContent: string): Boolean;
  end;

implementation

uses
  System.Hash;

{ TSpdxJsonWriter }

function TSpdxJsonWriter.GenerateUuid: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := GUIDToString(LGuid);
  Result := Result.Substring(1, Result.Length - 2);
end;

function TSpdxJsonWriter.SanitizeSpdxId(const AValue: string): string;
var
  I: Integer;
  LChar: Char;
begin
  // SPDX identifiers may only contain letters, numbers, '.', and '-'
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

function TSpdxJsonWriter.NormalizeSpdxPath(const APath: string): string;
begin
  // Separator-insensitive so setup\foo.exe and setup/foo.exe stay one ID.
  Result := StringReplace(Trim(APath), '\', '/', [rfReplaceAll]);
end;

function TSpdxJsonWriter.BuildPackageSpdxId(const ARelativePath: string): string;
var
  LPath: string;
  LSanitized: string;
  LHash: string;
begin
  // Basename alone collides when the same file sits in two folders (issue #39).
  // The readable part is the sanitized relative path. A short SHA-1 of that
  // path keeps the ID stable and distinct when sanitizing would collapse two
  // different paths (for example "a/b" and "a-b").
  LPath := NormalizeSpdxPath(ARelativePath);
  if LPath = '' then
    LPath := 'unknown';

  LSanitized := SanitizeSpdxId(LPath);
  if LSanitized = '' then
    LSanitized := 'unknown';

  LHash := Copy(LowerCase(THashSHA1.GetHashString(TEncoding.UTF8.GetBytes(LPath))), 1, 8);
  Result := cSpdxIdPrefix + 'Package-' + LSanitized + '-' + LHash;
end;

function TSpdxJsonWriter.CollectPackageSpdxIds(
  const AArtefacts: TArtefactList): TArray<string>;
var
  LUsed: TDictionary<string, Integer>;
  I: Integer;
  LSuffix: Integer;
  LBase: string;
  LId: string;
begin
  SetLength(Result, AArtefacts.Count);
  LUsed := TDictionary<string, Integer>.Create;
  try
    for I := 0 to AArtefacts.Count - 1 do
    begin
      LBase := BuildPackageSpdxId(AArtefacts[I].RelativePath);
      LId := LBase;
      LSuffix := 2;
      // Identical paths still need unique IDs inside one document.
      while LUsed.ContainsKey(LId) do
      begin
        LId := LBase + '-' + IntToStr(LSuffix);
        Inc(LSuffix);
      end;
      LUsed.Add(LId, I);
      Result[I] := LId;
    end;
  finally
    LUsed.Free;
  end;
end;

function TSpdxJsonWriter.TryParseSpdxTimestamp(const ATimestamp: string;
  out AUtc: TDateTime): Boolean;
var
  LText: string;
  LYear, LMonth, LDay, LHour, LMinute, LSecond: Integer;
  LPos: Integer;
  LOffsetMinutes: Integer;
  LSign: Integer;
  LRemain: Integer;
  LOffHour: Integer;
  LOffMinute: Integer;
begin
  Result := False;
  AUtc := 0;
  LText := Trim(ATimestamp);
  // YYYY-MM-DDThh:mm:ss
  if Length(LText) < 19 then
    Exit;
  if (LText[5] <> '-') or (LText[8] <> '-') then
    Exit;
  if (LText[11] <> 'T') and (LText[11] <> 't') then
    Exit;
  if (LText[14] <> ':') or (LText[17] <> ':') then
    Exit;
  if not TryStrToInt(Copy(LText, 1, 4), LYear) then
    Exit;
  if not TryStrToInt(Copy(LText, 6, 2), LMonth) then
    Exit;
  if not TryStrToInt(Copy(LText, 9, 2), LDay) then
    Exit;
  if not TryStrToInt(Copy(LText, 12, 2), LHour) then
    Exit;
  if not TryStrToInt(Copy(LText, 15, 2), LMinute) then
    Exit;
  if not TryStrToInt(Copy(LText, 18, 2), LSecond) then
    Exit;
  if (LMonth < 1) or (LMonth > 12) or (LDay < 1) or (LDay > 31) or
     (LHour < 0) or (LHour > 23) or (LMinute < 0) or (LMinute > 59) or
     (LSecond < 0) or (LSecond > 59) then
    Exit;

  // Fractional seconds are not part of the SPDX 2.3 pattern. Drop them.
  LPos := 20;
  if (LPos <= Length(LText)) and (LText[LPos] = '.') then
  begin
    Inc(LPos);
    while (LPos <= Length(LText)) and CharInSet(LText[LPos], ['0'..'9']) do
      Inc(LPos);
  end;

  LOffsetMinutes := 0;
  if LPos <= Length(LText) then
  begin
    if (LText[LPos] = 'Z') or (LText[LPos] = 'z') then
    begin
      if LPos <> Length(LText) then
        Exit;
    end
    else if (LText[LPos] = '+') or (LText[LPos] = '-') then
    begin
      if LText[LPos] = '+' then
        LSign := 1
      else
        LSign := -1;
      LRemain := Length(LText) - LPos;
      LOffHour := 0;
      LOffMinute := 0;
      if LRemain = 5 then
      begin
        // ±HH:MM
        if LText[LPos + 3] <> ':' then
          Exit;
        if not TryStrToInt(Copy(LText, LPos + 1, 2), LOffHour) then
          Exit;
        if not TryStrToInt(Copy(LText, LPos + 4, 2), LOffMinute) then
          Exit;
      end
      else if LRemain = 4 then
      begin
        // ±HHMM
        if not TryStrToInt(Copy(LText, LPos + 1, 2), LOffHour) then
          Exit;
        if not TryStrToInt(Copy(LText, LPos + 3, 2), LOffMinute) then
          Exit;
      end
      else if LRemain = 2 then
      begin
        // ±HH
        if not TryStrToInt(Copy(LText, LPos + 1, 2), LOffHour) then
          Exit;
      end
      else
        Exit;
      if (LOffHour < 0) or (LOffHour > 14) or (LOffMinute < 0) or (LOffMinute > 59) then
        Exit;
      LOffsetMinutes := LSign * ((LOffHour * 60) + LOffMinute);
    end
    else
      Exit;
  end;

  try
    // Offset is minutes east of UTC. UTC clock = local clock - offset.
    AUtc := IncMinute(EncodeDateTime(Word(LYear), Word(LMonth), Word(LDay),
      Word(LHour), Word(LMinute), Word(LSecond), 0), -LOffsetMinutes);
    Result := True;
  except
    Result := False;
  end;
end;

function TSpdxJsonWriter.FormatSpdxCreated(const ATimestamp: string): string;
var
  LUtc: TDateTime;
begin
  // SPDX 2.3 requires YYYY-MM-DDThh:mm:ssZ. DateToISO8601(..., False) emits
  // a local offset and fractional seconds, which tools.spdx.org rejects.
  if not TryParseSpdxTimestamp(ATimestamp, LUtc) then
    LUtc := TTimeZone.Local.ToUniversalTime(Now);
  Result := FormatDateTime('yyyy-mm-dd''T''hh:nn:ss''Z''', LUtc);
end;

function TSpdxJsonWriter.BuildGenericPurl(const ARelativePath: string): string;
var
  LNormalized: string;
  LSegments: TArray<string>;
  LSegment: string;
  LBytes: TBytes;
  LByte: Byte;
  LEncoded: string;
  LHasName: Boolean;
begin
  // A file: path is not a Package URL, and spaces in it fail SPDX validation
  // (issue #40). pkg:generic/<segments> is a real purl. Each segment is
  // percent-encoded so the locator cannot contain whitespace or purl
  // delimiters (@ ? #).
  Result := '';
  LNormalized := StringReplace(Trim(ARelativePath), '\', '/', [rfReplaceAll]);
  LSegments := LNormalized.Split(['/']);
  LHasName := False;
  Result := 'pkg:generic';
  for LSegment in LSegments do
  begin
    if LSegment = '' then
      Continue;
    LEncoded := '';
    LBytes := TEncoding.UTF8.GetBytes(LSegment);
    for LByte in LBytes do
    begin
      if ((LByte >= Ord('a')) and (LByte <= Ord('z'))) or
         ((LByte >= Ord('A')) and (LByte <= Ord('Z'))) or
         ((LByte >= Ord('0')) and (LByte <= Ord('9'))) or
         (LByte = Ord('-')) or (LByte = Ord('.')) or
         (LByte = Ord('_')) or (LByte = Ord('~')) then
        LEncoded := LEncoded + Char(LByte)
      else
        LEncoded := LEncoded + '%' + IntToHex(LByte, 2);
    end;
    if LEncoded = '' then
      Continue;
    Result := Result + '/' + LEncoded;
    LHasName := True;
  end;
  if not LHasName then
    Result := '';
end;

function TSpdxJsonWriter.BuildCreationInfo(const AMetadata: TSbomMetadata): TJSONObject;
var
  LCreationInfo: TJSONObject;
  LCreators: TJSONArray;
begin
  LCreationInfo := TJSONObject.Create;

  LCreationInfo.AddPair('created', FormatSpdxCreated(AMetadata.Timestamp));
  LCreationInfo.AddPair('licenseListVersion', '3.19');

  LCreators := TJSONArray.Create;
  LCreators.Add('Tool: ' + cToolName + '-' + cToolVersion);
  if AMetadata.Supplier <> '' then
    LCreators.Add('Organization: ' + AMetadata.Supplier);
  LCreationInfo.AddPair('creators', LCreators);

  Result := LCreationInfo;
end;

function TSpdxJsonWriter.BuildPackage(const AArtefact: TArtefactInfo;
  const ASpdxId, ASupplier: string): TJSONObject;
var
  LPackage: TJSONObject;
  LChecksums: TJSONArray;
  LChecksum: TJSONObject;
  LFileName: string;
begin
  LPackage := TJSONObject.Create;

  LFileName := TPath.GetFileName(AArtefact.RelativePath);

  LPackage.AddPair('SPDXID', ASpdxId);
  LPackage.AddPair('name', LFileName);

  if AArtefact.Hash <> '' then
    LPackage.AddPair('versionInfo', Copy(AArtefact.Hash, 1, 12));

  LPackage.AddPair('downloadLocation', 'NOASSERTION');
  LPackage.AddPair('filesAnalyzed', TJSONBool.Create(False));
  LPackage.AddPair('licenseConcluded', 'NOASSERTION');
  LPackage.AddPair('licenseDeclared', 'NOASSERTION');

  // Package verification code is not applicable for binary-only analysis.
  // --supplier / product.supplier is an organization name, not an SPDX agent
  // string, so prefix it the same way creationInfo.creators does.
  if Trim(ASupplier) <> '' then
    LPackage.AddPair('supplier', 'Organization: ' + Trim(ASupplier))
  else
    LPackage.AddPair('supplier', 'NOASSERTION');
  LPackage.AddPair('copyrightText', 'NOASSERTION');

  // Checksums
  if AArtefact.Hash <> '' then
  begin
    LChecksums := TJSONArray.Create;
    LChecksum := TJSONObject.Create;
    LChecksum.AddPair('algorithm', 'SHA256');
    LChecksum.AddPair('checksumValue', LowerCase(AArtefact.Hash));
    LChecksums.Add(LChecksum);
    LPackage.AddPair('checksums', LChecksums);
  end;

  // External reference. Omitted when the path cannot form a purl name.
  var LPurl := BuildGenericPurl(AArtefact.RelativePath);
  if LPurl <> '' then
  begin
    var LExtRefs := TJSONArray.Create;
    var LExtRef := TJSONObject.Create;
    LExtRef.AddPair('referenceCategory', 'PACKAGE-MANAGER');
    LExtRef.AddPair('referenceType', 'purl');
    LExtRef.AddPair('referenceLocator', LPurl);
    LExtRefs.Add(LExtRef);
    LPackage.AddPair('externalRefs', LExtRefs);
  end;

  Result := LPackage;
end;

function TSpdxJsonWriter.BuildRelationships(const APackageIds: TArray<string>;
  const ADocumentSpdxId: string): TJSONArray;
var
  LRelationships: TJSONArray;
  LRel: TJSONObject;
  I: Integer;
begin
  LRelationships := TJSONArray.Create;

  // DESCRIBES relationship from document to each package. The related ID
  // must be the same value written on the package (issue #39).
  for I := 0 to High(APackageIds) do
  begin
    LRel := TJSONObject.Create;
    LRel.AddPair('spdxElementId', ADocumentSpdxId);
    LRel.AddPair('relationshipType', 'DESCRIBES');
    LRel.AddPair('relatedSpdxElement', APackageIds[I]);
    LRelationships.Add(LRel);
  end;

  Result := LRelationships;
end;

function TSpdxJsonWriter.Write(const AOutputPath: string;
  const AMetadata: TSbomMetadata;
  const AArtefacts: TArtefactList;
  const AProjectInfo: TProjectInfo): Boolean;
var
  LRoot: TJSONObject;
  LPackages: TJSONArray;
  LOutput: TStringList;
  LDocumentSpdxId: string;
  LDocNamespace: string;
  LPackageIds: TArray<string>;
  I: Integer;
begin
  Result := False;
  if AOutputPath = '' then
    Exit;

  var LOutputDir := TPath.GetDirectoryName(AOutputPath);
  if (LOutputDir <> '') and not TDirectory.Exists(LOutputDir) then
    TDirectory.CreateDirectory(LOutputDir);

  LDocumentSpdxId := cSpdxIdPrefix + 'DOCUMENT';
  LDocNamespace := 'https://spdx.org/spdxdocs/' +
    SanitizeSpdxId(AProjectInfo.ProjectName) + '-' + GenerateUuid;

  LRoot := TJSONObject.Create;
  try
    LRoot.AddPair('spdxVersion', cSpdxVersion);
    LRoot.AddPair('dataLicense', cDataLicense);
    LRoot.AddPair('SPDXID', LDocumentSpdxId);
    // Prefer metadata override (CLI --product) over project name — issue #26.
    if AMetadata.ProductName <> '' then
      LRoot.AddPair('name', AMetadata.ProductName)
    else
      LRoot.AddPair('name', AProjectInfo.ProjectName);
    LRoot.AddPair('documentNamespace', LDocNamespace);

    // Creation info
    LRoot.AddPair('creationInfo', BuildCreationInfo(AMetadata));

    // Packages. IDs are assigned once so relationships point at the same values.
    LPackageIds := CollectPackageSpdxIds(AArtefacts);
    LPackages := TJSONArray.Create;
    for I := 0 to AArtefacts.Count - 1 do
      LPackages.Add(BuildPackage(AArtefacts[I], LPackageIds[I], AMetadata.Supplier));
    LRoot.AddPair('packages', LPackages);

    // Relationships
    LRoot.AddPair('relationships', BuildRelationships(LPackageIds, LDocumentSpdxId));

    // Write to file
    LOutput := TStringList.Create;
    try
      LOutput.Text := LRoot.Format(2);
      LOutput.SaveToFile(AOutputPath, TEncoding.UTF8);
      Result := True;
    finally
      LOutput.Free;
    end;
  finally
    LRoot.Free;
  end;
end;

function TSpdxJsonWriter.GetFormat: TSbomFormat;
begin
  Result := sfSpdxJson;
end;

function TSpdxJsonWriter.Validate(const AContent: string): Boolean;
var
  LJson: TJSONObject;
begin
  Result := False;
  if Trim(AContent) = '' then
    Exit;

  try
    LJson := TJSONObject.ParseJSONValue(AContent) as TJSONObject;
    try
      if not Assigned(LJson) then
        Exit;

      // spdxVersion must be present
      if LJson.GetValue('spdxVersion') = nil then
        Exit;

      // dataLicense must be CC0-1.0
      if (LJson.GetValue('dataLicense') = nil) or
         (LJson.GetValue<string>('dataLicense') <> cDataLicense) then
        Exit;

      // SPDXID must be present
      if LJson.GetValue('SPDXID') = nil then
        Exit;

      // name must be present
      if LJson.GetValue('name') = nil then
        Exit;

      // documentNamespace must be present
      if LJson.GetValue('documentNamespace') = nil then
        Exit;

      // creationInfo must be present
      if not (LJson.GetValue('creationInfo') is TJSONObject) then
        Exit;

      // packages array must be present
      if not (LJson.GetValue('packages') is TJSONArray) then
        Exit;

      Result := True;
    finally
      LJson.Free;
    end;
  except
    Result := False;
  end;
end;

end.
