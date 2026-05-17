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
    function BuildCreationInfo(const AMetadata: TSbomMetadata): TJSONObject;
    function BuildPackage(const AArtefact: TArtefactInfo; const AIndex: Integer;
      const AProjectInfo: TProjectInfo): TJSONObject;
    function BuildRelationships(const AArtefacts: TArtefactList;
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

function TSpdxJsonWriter.BuildCreationInfo(const AMetadata: TSbomMetadata): TJSONObject;
var
  LCreationInfo: TJSONObject;
  LCreators: TJSONArray;
  LTimestamp: string;
begin
  LCreationInfo := TJSONObject.Create;

  if AMetadata.Timestamp <> '' then
    LTimestamp := AMetadata.Timestamp
  else
    LTimestamp := DateToISO8601(Now, False);

  LCreationInfo.AddPair('created', LTimestamp);
  LCreationInfo.AddPair('licenseListVersion', '3.19');

  LCreators := TJSONArray.Create;
  LCreators.Add('Tool: ' + cToolName + '-' + cToolVersion);
  if AMetadata.Supplier <> '' then
    LCreators.Add('Organization: ' + AMetadata.Supplier);
  LCreationInfo.AddPair('creators', LCreators);

  Result := LCreationInfo;
end;

function TSpdxJsonWriter.BuildPackage(const AArtefact: TArtefactInfo;
  const AIndex: Integer; const AProjectInfo: TProjectInfo): TJSONObject;
var
  LPackage: TJSONObject;
  LChecksums: TJSONArray;
  LChecksum: TJSONObject;
  LSpdxId: string;
  LFileName: string;
begin
  LPackage := TJSONObject.Create;

  LFileName := TPath.GetFileName(AArtefact.RelativePath);
  LSpdxId := cSpdxIdPrefix + 'Package-' + SanitizeSpdxId(LFileName);

  LPackage.AddPair('SPDXID', LSpdxId);
  LPackage.AddPair('name', LFileName);

  if AArtefact.Hash <> '' then
    LPackage.AddPair('versionInfo', Copy(AArtefact.Hash, 1, 12));

  LPackage.AddPair('downloadLocation', 'NOASSERTION');
  LPackage.AddPair('filesAnalyzed', TJSONBool.Create(False));

  // Package verification code is not applicable for binary-only analysis
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

  // External references (purl)
  if AArtefact.RelativePath <> '' then
  begin
    var LExtRefs := TJSONArray.Create;
    var LExtRef := TJSONObject.Create;
    LExtRef.AddPair('referenceCategory', 'PACKAGE-MANAGER');
    LExtRef.AddPair('referenceType', 'purl');
    LExtRef.AddPair('referenceLocator', 'file:' + AArtefact.RelativePath);
    LExtRefs.Add(LExtRef);
    LPackage.AddPair('externalRefs', LExtRefs);
  end;

  Result := LPackage;
end;

function TSpdxJsonWriter.BuildRelationships(const AArtefacts: TArtefactList;
  const ADocumentSpdxId: string): TJSONArray;
var
  LRelationships: TJSONArray;
  LRel: TJSONObject;
  I: Integer;
  LFileName: string;
begin
  LRelationships := TJSONArray.Create;

  // DESCRIBES relationship from document to each package
  for I := 0 to AArtefacts.Count - 1 do
  begin
    LFileName := TPath.GetFileName(AArtefacts[I].RelativePath);

    LRel := TJSONObject.Create;
    LRel.AddPair('spdxElementId', ADocumentSpdxId);
    LRel.AddPair('relationshipType', 'DESCRIBES');
    LRel.AddPair('relatedSpdxElement', cSpdxIdPrefix + 'Package-' + SanitizeSpdxId(LFileName));
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

    // Packages
    LPackages := TJSONArray.Create;
    for I := 0 to AArtefacts.Count - 1 do
      LPackages.Add(BuildPackage(AArtefacts[I], I, AProjectInfo));
    LRoot.AddPair('packages', LPackages);

    // Relationships
    LRoot.AddPair('relationships', BuildRelationships(AArtefacts, LDocumentSpdxId));

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
