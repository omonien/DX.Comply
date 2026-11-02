/// <summary>
/// DX.Comply.Spdx3.Writer
/// Generates SPDX 3.0.1 SBOM documents in JSON-LD format.
/// </summary>
///
/// <remarks>
/// BSI TR-03183-2 v2.1.0 chapter 4 accepts SPDX 3.0.1 or later (issue #108).
/// The writer builds the SPDX 2.3 document in memory with TSpdxJsonWriter and
/// converts it, so packages, IDs, manifest libraries, licences and the uses
/// graph are the same in both SPDX versions.
///
/// Mapping:
/// - creationInfo becomes one CreationInfo blank node. The tool is a Tool in
///   createdUsing. The supplier organisation and an SBOM creator email are
///   agents in createdBy. Without either, a SoftwareAgent named DX.Comply is
///   the creator.
/// - Packages become software_Package with verifiedUsing hashes (sha256,
///   sha512), software_packageUrl, suppliedBy and originatedBy.
/// - Licences become simplelicensing_LicenseExpression elements linked with
///   hasDeclaredLicense and hasConcludedLicense. A licence name that is not
///   an SPDX identifier keeps its LicenseRef- token and gets a
///   simplelicensing_SimpleLicensingText.
/// - Relationships with the same source and type are one Relationship.
///   completeness carries what CycloneDX writes as compositions.
/// - The TR properties (filename, executable, archive, structured) stay in
///   the package comment, as in SPDX 2.3. software_primaryPurpose is set
///   from the file extension.
///
/// SPDX 3.0.1 specification: https://spdx.github.io/spdx-spec/v3.0.1/
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Spdx3.Writer;

interface

uses
  System.JSON,
  DX.Comply.Engine.Intf;

const
  /// <summary>SPDX 3.0.1 JSON-LD context.</summary>
  cSpdx3Context = 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld';
  /// <summary>SPDX specification version written in CreationInfo.</summary>
  cSpdx3SpecVersion = '3.0.1';
  /// <summary>Value of --spdx-version and the spdxVersion key that selects this writer.</summary>
  cSpdxVersion301 = '3.0.1';
  /// <summary>Value that selects the SPDX 2.3 writer, the default.</summary>
  cSpdxVersion23 = '2.3';

type
  /// <summary>
  /// Implementation of ISbomWriter for SPDX 3.0.1 JSON-LD.
  /// </summary>
  TSpdx3JsonWriter = class(TInterfacedObject, ISbomWriter)
  public
    /// <summary>
    /// Builds the SPDX 3.0.1 document. The caller owns the result.
    /// </summary>
    function BuildDocument(const AMetadata: TSbomMetadata;
      const AArtefacts: TArtefactList; const AProjectInfo: TProjectInfo): TJSONObject;
    function Write(const AOutputPath: string;
      const AMetadata: TSbomMetadata;
      const AArtefacts: TArtefactList;
      const AProjectInfo: TProjectInfo): Boolean;
    function GetFormat: TSbomFormat;
    function Validate(const AContent: string): Boolean;
  end;

/// <summary>
/// True when AValue names a supported SPDX version: empty, 2.3 or 3.0.1.
/// </summary>
function IsSupportedSpdxVersion(const AValue: string): Boolean;

/// <summary>
/// The writer format for AFormat and the SPDX version. An SPDX format follows
/// ASpdxVersion: 3.0.1 gives sfSpdx3Json, 2.3 gives sfSpdxJson. An empty
/// version or a non-SPDX format returns AFormat unchanged.
/// </summary>
function ApplySpdxVersion(AFormat: TSbomFormat; const ASpdxVersion: string): TSbomFormat;

/// <summary>
/// SPDX 3.0.1 relationship type for an SPDX 2.3 one: DEPENDS_ON gives
/// dependsOn, CONTAINS gives contains.
/// </summary>
function Spdx3RelationshipType(const ASpdx23Type: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.StrUtils,
  DX.Comply.Spdx.Writer,
  DX.Comply.DependencyGraph;

const
  cCreationInfoId = '_:creationinfo';
  cNoneElement = 'NoneElement';
  cNoAssertionElement = 'NoAssertionElement';
  cManifestPackagePrefix = 'SPDXRef-Package-Manifest-';

function IsSupportedSpdxVersion(const AValue: string): Boolean;
begin
  var LValue := Trim(AValue);
  Result := (LValue = '') or (LValue = cSpdxVersion23) or (LValue = cSpdxVersion301);
end;

function ApplySpdxVersion(AFormat: TSbomFormat; const ASpdxVersion: string): TSbomFormat;
begin
  Result := AFormat;
  if not (AFormat in [sfSpdxJson, sfSpdx3Json]) or (Trim(ASpdxVersion) = '') then
    Exit;
  if Trim(ASpdxVersion) = cSpdxVersion301 then
    Result := sfSpdx3Json
  else
    Result := sfSpdxJson;
end;

function Spdx3RelationshipType(const ASpdx23Type: string): string;
begin
  // SPDX 2.3 names are upper snake case, SPDX 3 names lower camel case.
  Result := '';
  var LUpper := False;
  for var i := 1 to Length(ASpdx23Type) do
  begin
    var LChar := ASpdx23Type[i];
    if LChar = '_' then
    begin
      LUpper := True;
      Continue;
    end;
    if LUpper then
      Result := Result + UpperCase(LChar)
    else
      Result := Result + LowerCase(LChar);
    LUpper := False;
  end;
end;

function JsonText(AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if not Assigned(AObject) then
    Exit;
  var LValue := AObject.GetValue(AName);
  if Assigned(LValue) and not (LValue is TJSONNull) then
    Result := LValue.Value;
end;

function IdSuffix(const AValue: string): string;
begin
  Result := '';
  for var i := 1 to Length(AValue) do
  begin
    if CharInSet(AValue[i], ['a'..'z', 'A'..'Z', '0'..'9', '.', '-']) then
      Result := Result + AValue[i]
    else
      Result := Result + '-';
  end;
  if Result = '' then
    Result := 'unnamed';
end;

function PurposeForFileName(const AFileName: string): string;
begin
  var LExt := LowerCase(TPath.GetExtension(AFileName));
  if LExt = '.exe' then
    Result := 'application'
  else if (LExt = '.dll') or (LExt = '.bpl') or (LExt = '.so') or (LExt = '.dylib') or
    (LExt = '.dcp') or (LExt = '.a') or (LExt = '.lib') then
    Result := 'library'
  else if (LExt = '.pas') or (LExt = '.inc') or (LExt = '.dpr') or (LExt = '.dpk') then
    Result := 'source'
  else if (LExt = '.zip') or (LExt = '.7z') or (LExt = '.tar') or (LExt = '.gz') or
    (LExt = '.tgz') or (LExt = '.rar') or (LExt = '.cab') then
    Result := 'archive'
  else if AFileName <> '' then
    Result := 'file'
  else
    Result := '';
end;

type
  /// <summary>Converts one SPDX 2.3 document into SPDX 3.0.1 JSON-LD.</summary>
  TSpdx3Converter = class
  private
    FSource: TJSONObject;
    FNamespace: string;
    FGraph: TJSONArray;
    FElementIds: TList<string>;
    FAgents: TDictionary<string, string>;
    FLicences: TDictionary<string, string>;
    FLicenceTexts: TDictionary<string, string>;
    FExtracted: TDictionary<string, TJSONObject>;
    FRelationships: TDictionary<string, TJSONObject>;
    FRelationshipCount: Integer;
    function Id(const ALocalId: string): string;
    function NewElement(const AType, ALocalId: string; AListed: Boolean = True): TJSONObject;
    function AgentId(const AAgentText: string): string;
    function LicenceId(const AExpression: string): string;
    function LicenceTextId(const AToken: string): string;
    function Relationship(const AFrom, AType: string): TJSONObject;
    procedure AddRelationshipTarget(const AFrom, AType, ATo: string);
    procedure ConvertPackage(APackage: TJSONObject);
  public
    constructor Create(ASource: TJSONObject);
    destructor Destroy; override;
    function Convert(const AArtefacts: TArtefactList; const APackageIds: TArray<string>;
      const AProjectName: string): TJSONObject;
  end;

constructor TSpdx3Converter.Create(ASource: TJSONObject);
begin
  inherited Create;
  FSource := ASource;
  FNamespace := JsonText(ASource, 'documentNamespace');
  FGraph := TJSONArray.Create;
  FElementIds := TList<string>.Create;
  FAgents := TDictionary<string, string>.Create;
  FLicences := TDictionary<string, string>.Create;
  FLicenceTexts := TDictionary<string, string>.Create;
  FExtracted := TDictionary<string, TJSONObject>.Create;
  FRelationships := TDictionary<string, TJSONObject>.Create;
end;

destructor TSpdx3Converter.Destroy;
begin
  FRelationships.Free;
  FExtracted.Free;
  FLicenceTexts.Free;
  FLicences.Free;
  FAgents.Free;
  FElementIds.Free;
  FGraph.Free;
  inherited;
end;

function TSpdx3Converter.Id(const ALocalId: string): string;
begin
  Result := FNamespace + '#' + ALocalId;
end;

function TSpdx3Converter.NewElement(const AType, ALocalId: string; AListed: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', AType);
  Result.AddPair('spdxId', Id(ALocalId));
  Result.AddPair('creationInfo', cCreationInfoId);
  FGraph.Add(Result);
  if AListed then
    FElementIds.Add(Id(ALocalId));
end;

function TSpdx3Converter.AgentId(const AAgentText: string): string;
begin
  // SPDX 2.3 agents: "Organization: name" or "Person: name (email)".
  Result := '';
  var LText := Trim(AAgentText);
  if (LText = '') or SameText(LText, 'NOASSERTION') then
    Exit;
  if FAgents.TryGetValue(LText, Result) then
    Exit;

  var LType := 'Agent';
  var LName := LText;
  var LEmail := '';
  if LText.StartsWith('Organization:') then
  begin
    LType := 'Organization';
    LName := Trim(LText.Substring(Length('Organization:')));
  end
  else if LText.StartsWith('Person:') then
  begin
    LType := 'Person';
    LName := Trim(LText.Substring(Length('Person:')));
    var LOpen := LName.LastIndexOf('(');
    if (LOpen > 0) and LName.EndsWith(')') then
    begin
      LEmail := Trim(LName.Substring(LOpen + 1, LName.Length - LOpen - 2));
      LName := Trim(LName.Substring(0, LOpen));
    end;
  end;

  var LElement := NewElement(LType, 'SPDXRef-' + LType + '-' + IdSuffix(LName) + '-' +
    IntToStr(FAgents.Count + 1));
  LElement.AddPair('name', LName);
  if LEmail <> '' then
  begin
    var LIdentifiers := TJSONArray.Create;
    var LIdentifier := TJSONObject.Create;
    LIdentifier.AddPair('type', 'ExternalIdentifier');
    LIdentifier.AddPair('externalIdentifierType', 'email');
    LIdentifier.AddPair('identifier', LEmail);
    LIdentifiers.Add(LIdentifier);
    LElement.AddPair('externalIdentifier', LIdentifiers);
  end;
  Result := JsonText(LElement, 'spdxId');
  FAgents.Add(LText, Result);
end;

function TSpdx3Converter.LicenceTextId(const AToken: string): string;
begin
  Result := '';
  if FLicenceTexts.TryGetValue(AToken, Result) then
    Exit;
  var LInfo: TJSONObject;
  if not FExtracted.TryGetValue(UpperCase(AToken), LInfo) then
    Exit;
  var LElement := NewElement('simplelicensing_SimpleLicensingText', 'SPDXRef-LicenseText-' + IdSuffix(AToken));
  if JsonText(LInfo, 'name') <> '' then
    LElement.AddPair('name', JsonText(LInfo, 'name'));
  var LText := JsonText(LInfo, 'extractedText');
  if LText = '' then
    LText := AToken;
  LElement.AddPair('simplelicensing_licenseText', LText);
  Result := JsonText(LElement, 'spdxId');
  FLicenceTexts.Add(AToken, Result);
end;

function TSpdx3Converter.LicenceId(const AExpression: string): string;
begin
  Result := '';
  var LExpression := Trim(AExpression);
  if (LExpression = '') or SameText(LExpression, 'NOASSERTION') or SameText(LExpression, 'NONE') then
    Exit;
  if FLicences.TryGetValue(LExpression, Result) then
    Exit;

  var LElement := NewElement('simplelicensing_LicenseExpression', 'SPDXRef-License-' +
    IntToStr(FLicences.Count + 1));
  LElement.AddPair('simplelicensing_licenseExpression', LExpression);
  // SPDX 3 types this as SemVer, so 3.29 is written as 3.29.0.
  var LListVersion := cSpdxLicenseListVersion;
  if Length(LListVersion.Split(['.'])) = 2 then
    LListVersion := LListVersion + '.0';
  LElement.AddPair('simplelicensing_licenseListVersion', LListVersion);

  // LicenseRef- tokens point at their licence text.
  var LText := StringReplace(StringReplace(LExpression, '(', ' ', [rfReplaceAll]), ')', ' ',
    [rfReplaceAll]);
  var LMap: TJSONArray := nil;
  for var LToken in LText.Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if not LToken.StartsWith('LicenseRef-') then
      Continue;
    var LTextId := LicenceTextId(LToken);
    if LTextId = '' then
      Continue;
    if not Assigned(LMap) then
      LMap := TJSONArray.Create;
    var LEntry := TJSONObject.Create;
    LEntry.AddPair('type', 'DictionaryEntry');
    LEntry.AddPair('key', LToken);
    LEntry.AddPair('value', LTextId);
    LMap.Add(LEntry);
  end;
  if Assigned(LMap) then
    LElement.AddPair('simplelicensing_customIdToUri', LMap);

  Result := JsonText(LElement, 'spdxId');
  FLicences.Add(LExpression, Result);
end;

function TSpdx3Converter.Relationship(const AFrom, AType: string): TJSONObject;
begin
  var LKey := AFrom + '|' + AType;
  if FRelationships.TryGetValue(LKey, Result) then
    Exit;
  Inc(FRelationshipCount);
  Result := NewElement('Relationship', 'SPDXRef-Relationship-' + IntToStr(FRelationshipCount));
  Result.AddPair('from', AFrom);
  Result.AddPair('relationshipType', AType);
  Result.AddPair('to', TJSONArray.Create);
  FRelationships.Add(LKey, Result);
end;

procedure TSpdx3Converter.AddRelationshipTarget(const AFrom, AType, ATo: string);
begin
  var LTargets := Relationship(AFrom, AType).GetValue('to') as TJSONArray;
  for var i := 0 to LTargets.Count - 1 do
  begin
    if LTargets.Items[i].Value = ATo then
      Exit;
  end;
  LTargets.Add(ATo);
end;

procedure TSpdx3Converter.ConvertPackage(APackage: TJSONObject);
begin
  var LLocalId := JsonText(APackage, 'SPDXID');
  var LElement := NewElement('software_Package', LLocalId);
  var LPackageId := JsonText(LElement, 'spdxId');
  LElement.AddPair('name', JsonText(APackage, 'name'));
  if JsonText(APackage, 'comment') <> '' then
    LElement.AddPair('comment', JsonText(APackage, 'comment'));

  var LSupplier := AgentId(JsonText(APackage, 'supplier'));
  if LSupplier <> '' then
    LElement.AddPair('suppliedBy', LSupplier);
  var LOriginator := AgentId(JsonText(APackage, 'originator'));
  if LOriginator <> '' then
    LElement.AddPair('originatedBy', TJSONArray.Create.Add(LOriginator));

  // Hashes. SPDX 2.3 SHA256 and SHA512 become sha256 and sha512.
  if APackage.GetValue('checksums') is TJSONArray then
  begin
    var LHashes := TJSONArray.Create;
    for var LItem in TJSONArray(APackage.GetValue('checksums')) do
    begin
      if not (LItem is TJSONObject) then
        Continue;
      var LHash := TJSONObject.Create;
      LHash.AddPair('type', 'Hash');
      LHash.AddPair('algorithm', LowerCase(JsonText(TJSONObject(LItem), 'algorithm')));
      LHash.AddPair('hashValue', JsonText(TJSONObject(LItem), 'checksumValue'));
      LHashes.Add(LHash);
    end;
    LElement.AddPair('verifiedUsing', LHashes);
  end;

  var LPurpose := PurposeForFileName(JsonText(APackage, 'packageFileName'));
  if (LPurpose = '') and LLocalId.StartsWith(cManifestPackagePrefix) then
    LPurpose := 'library';
  if LPurpose <> '' then
    LElement.AddPair('software_primaryPurpose', LPurpose);

  var LDownload := JsonText(APackage, 'downloadLocation');
  if (LDownload <> '') and not SameText(LDownload, 'NOASSERTION') and not SameText(LDownload, 'NONE') then
    LElement.AddPair('software_downloadLocation', LDownload);

  if APackage.GetValue('externalRefs') is TJSONArray then
  begin
    for var LItem in TJSONArray(APackage.GetValue('externalRefs')) do
    begin
      if not (LItem is TJSONObject) then
        Continue;
      var LRef := TJSONObject(LItem);
      if SameText(JsonText(LRef, 'referenceType'), 'purl') then
        LElement.AddPair('software_packageUrl', JsonText(LRef, 'referenceLocator'))
      else if SameText(JsonText(LRef, 'referenceType'), 'website') then
        LElement.AddPair('software_homePage', JsonText(LRef, 'referenceLocator'));
    end;
  end;

  if JsonText(APackage, 'versionInfo') <> '' then
    LElement.AddPair('software_packageVersion', JsonText(APackage, 'versionInfo'));

  var LDeclared := LicenceId(JsonText(APackage, 'licenseDeclared'));
  if LDeclared <> '' then
    AddRelationshipTarget(LPackageId, 'hasDeclaredLicense', LDeclared);
  var LConcluded := LicenceId(JsonText(APackage, 'licenseConcluded'));
  if LConcluded <> '' then
    AddRelationshipTarget(LPackageId, 'hasConcludedLicense', LConcluded);
end;

function TSpdx3Converter.Convert(const AArtefacts: TArtefactList; const APackageIds: TArray<string>;
  const AProjectName: string): TJSONObject;
begin
  var LDocumentLocalId := JsonText(FSource, 'SPDXID');
  var LSourceInfo := FSource.GetValue('creationInfo') as TJSONObject;

  if FSource.GetValue('hasExtractedLicensingInfos') is TJSONArray then
  begin
    for var LItem in TJSONArray(FSource.GetValue('hasExtractedLicensingInfos')) do
    begin
      if LItem is TJSONObject then
        FExtracted.AddOrSetValue(UpperCase(JsonText(TJSONObject(LItem), 'licenseId')), TJSONObject(LItem));
    end;
  end;

  // Agents and tool from the SPDX 2.3 creators.
  var LCreatedBy := TJSONArray.Create;
  var LCreatedUsing := TJSONArray.Create;
  var LCreationInfo := TJSONObject.Create;
  LCreationInfo.AddPair('type', 'CreationInfo');
  LCreationInfo.AddPair('@id', cCreationInfoId);
  LCreationInfo.AddPair('specVersion', cSpdx3SpecVersion);
  LCreationInfo.AddPair('created', JsonText(LSourceInfo, 'created'));
  LCreationInfo.AddPair('createdBy', LCreatedBy);
  LCreationInfo.AddPair('createdUsing', LCreatedUsing);
  if JsonText(LSourceInfo, 'comment') <> '' then
    LCreationInfo.AddPair('comment', JsonText(LSourceInfo, 'comment'));
  FGraph.Add(LCreationInfo);

  if Assigned(LSourceInfo) and (LSourceInfo.GetValue('creators') is TJSONArray) then
  begin
    for var LItem in TJSONArray(LSourceInfo.GetValue('creators')) do
    begin
      var LText := LItem.Value;
      if LText.StartsWith('Tool:') then
      begin
        var LTool := NewElement('Tool', 'SPDXRef-Tool-' + IdSuffix(Trim(LText.Substring(5))));
        LTool.AddPair('name', Trim(LText.Substring(5)));
        LCreatedUsing.Add(JsonText(LTool, 'spdxId'));
      end
      else
      begin
        var LAgent := AgentId(LText);
        if LAgent <> '' then
          LCreatedBy.Add(LAgent);
      end;
    end;
  end;
  if LCreatedBy.Count = 0 then
  begin
    var LSoftwareAgent := NewElement('SoftwareAgent', 'SPDXRef-SoftwareAgent-DX.Comply');
    LSoftwareAgent.AddPair('name', 'DX.Comply');
    LCreatedBy.Add(JsonText(LSoftwareAgent, 'spdxId'));
  end;

  if FSource.GetValue('packages') is TJSONArray then
  begin
    for var LItem in TJSONArray(FSource.GetValue('packages')) do
    begin
      if LItem is TJSONObject then
        ConvertPackage(TJSONObject(LItem));
    end;
  end;

  // Relationships. DESCRIBES from the document becomes the root elements.
  var LDescribed := TList<string>.Create;
  try
    if FSource.GetValue('relationships') is TJSONArray then
    begin
      for var LItem in TJSONArray(FSource.GetValue('relationships')) do
      begin
        if not (LItem is TJSONObject) then
          Continue;
        var LRel := TJSONObject(LItem);
        var LFrom := JsonText(LRel, 'spdxElementId');
        var LTo := JsonText(LRel, 'relatedSpdxElement');
        var LType := JsonText(LRel, 'relationshipType');
        if (LFrom = LDocumentLocalId) and (LType = 'DESCRIBES') then
        begin
          LDescribed.Add(Id(LTo));
          Continue;
        end;
        AddRelationshipTarget(Id(LFrom), Spdx3RelationshipType(LType), Id(LTo));
      end;
    end;

    // Completeness, the same split CycloneDX writes as compositions.
    var LRootIndex := FindDeliverableTargetIndex(AArtefacts, AProjectName);
    if LRootIndex >= 0 then
    begin
      var LRootId := Id(APackageIds[LRootIndex]);
      var LRootRel: TJSONObject;
      if FRelationships.TryGetValue(LRootId + '|contains', LRootRel) then
        LRootRel.AddPair('completeness', 'incomplete');
      if FRelationships.TryGetValue(LRootId + '|dependsOn', LRootRel) then
        LRootRel.AddPair('completeness', 'incomplete');
    end;
    var LGraph := BuildUsesDependencyGraph(AArtefacts);
    for var i := 0 to High(LGraph.Status) do
    begin
      if (i = LRootIndex) or (i > High(APackageIds)) or
        not SameText(AArtefacts[i].ArtefactType, 'unit-evidence') then
        Continue;
      var LFrom := Id(APackageIds[i]);
      var LRel: TJSONObject;
      var LComplete := LGraph.Status[i] = uusComplete;
      if not FRelationships.TryGetValue(LFrom + '|dependsOn', LRel) then
      begin
        if LComplete then
          AddRelationshipTarget(LFrom, 'dependsOn', cNoneElement)
        else
          AddRelationshipTarget(LFrom, 'dependsOn', cNoAssertionElement);
        LRel := Relationship(LFrom, 'dependsOn');
      end;
      LRel.AddPair('completeness', IfThen(LComplete, 'complete', 'incomplete'));
    end;
    // Manifest libraries list every unit they group.
    for var LPair in FRelationships do
    begin
      if LPair.Key.StartsWith(Id(cManifestPackagePrefix)) and LPair.Key.EndsWith('|dependsOn') and
        (LPair.Value.GetValue('completeness') = nil) then
        LPair.Value.AddPair('completeness', 'complete');
    end;

    // Data licence of the document itself.
    var LDataLicence := LicenceId(JsonText(FSource, 'dataLicense'));

    var LSbom := NewElement('software_Sbom', 'SPDXRef-Sbom', False);
    var LRoots := TJSONArray.Create;
    if LRootIndex >= 0 then
      LRoots.Add(Id(APackageIds[LRootIndex]))
    else
    begin
      for var LRoot in LDescribed do
        LRoots.Add(LRoot);
    end;
    LSbom.AddPair('rootElement', LRoots);
    var LSbomElements := TJSONArray.Create;
    for var LId in FElementIds do
      LSbomElements.Add(LId);
    LSbom.AddPair('element', LSbomElements);
    LSbom.AddPair('software_sbomType', TJSONArray.Create.Add('build'));

    var LDocument := NewElement('SpdxDocument', LDocumentLocalId, False);
    LDocument.AddPair('name', JsonText(FSource, 'name'));
    if LDataLicence <> '' then
      LDocument.AddPair('dataLicense', LDataLicence);
    LDocument.AddPair('profileConformance',
      TJSONArray.Create.Add('core').Add('software').Add('simpleLicensing'));
    LDocument.AddPair('rootElement', TJSONArray.Create.Add(JsonText(LSbom, 'spdxId')));
    var LDocElements := TJSONArray.Create;
    LDocElements.Add(JsonText(LSbom, 'spdxId'));
    for var LId in FElementIds do
      LDocElements.Add(LId);
    LDocument.AddPair('element', LDocElements);
  finally
    LDescribed.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('@context', cSpdx3Context);
  Result.AddPair('@graph', FGraph);
  FGraph := nil;
end;

{ TSpdx3JsonWriter }

function TSpdx3JsonWriter.BuildDocument(const AMetadata: TSbomMetadata;
  const AArtefacts: TArtefactList; const AProjectInfo: TProjectInfo): TJSONObject;
begin
  var LPackageIds: TArray<string>;
  var LSpdx23Writer := TSpdxJsonWriter.Create;
  try
    var LSource := LSpdx23Writer.BuildDocument(AMetadata, AArtefacts, AProjectInfo, LPackageIds);
    try
      var LConverter := TSpdx3Converter.Create(LSource);
      try
        Result := LConverter.Convert(AArtefacts, LPackageIds, AProjectInfo.ProjectName);
      finally
        LConverter.Free;
      end;
    finally
      LSource.Free;
    end;
  finally
    LSpdx23Writer.Free;
  end;
end;

function TSpdx3JsonWriter.Write(const AOutputPath: string;
  const AMetadata: TSbomMetadata;
  const AArtefacts: TArtefactList;
  const AProjectInfo: TProjectInfo): Boolean;
begin
  Result := False;
  if AOutputPath = '' then
    Exit;

  var LOutputDir := TPath.GetDirectoryName(AOutputPath);
  if (LOutputDir <> '') and not TDirectory.Exists(LOutputDir) then
    TDirectory.CreateDirectory(LOutputDir);

  var LRoot := BuildDocument(AMetadata, AArtefacts, AProjectInfo);
  try
    var LOutput := TStringList.Create;
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

function TSpdx3JsonWriter.GetFormat: TSbomFormat;
begin
  Result := sfSpdx3Json;
end;

function TSpdx3JsonWriter.Validate(const AContent: string): Boolean;
begin
  Result := False;
  try
    var LValue := TJSONObject.ParseJSONValue(AContent);
    try
      if not (LValue is TJSONObject) then
        Exit;
      Result := (JsonText(TJSONObject(LValue), '@context') = cSpdx3Context) and
        (TJSONObject(LValue).GetValue('@graph') is TJSONArray);
    finally
      LValue.Free;
    end;
  except
    Result := False;
  end;
end;

end.
