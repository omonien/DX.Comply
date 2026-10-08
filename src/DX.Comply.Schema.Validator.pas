/// <summary>
/// DX.Comply.Schema.Validator
/// Structural check for CycloneDX and SPDX SBOM documents.
/// </summary>
///
/// <remarks>
/// Provides TSbomValidator with deep structural validation of generated SBOMs:
/// - CycloneDX 1.6 JSON: validates required fields, component structure, hash format
/// - CycloneDX 1.6 XML: validates namespace, element presence, attribute correctness
/// - SPDX 2.3 JSON: validates document structure, package fields, relationships
///
/// Validation errors are collected in a TValidationResult record which contains
/// both a pass/fail indicator and a list of human-readable error messages.
///
/// Since full JSON Schema / XSD validation would require heavy external dependencies,
/// this validator performs structural checks for required fields and value
/// constraints. CycloneDX XML checks also enforce the 1.6 child order of
/// metadata and component. That is still not a substitute for xmllint against
/// bom-1.6.xsd.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Schema.Validator;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.RegularExpressions,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Result of a schema validation operation.
  /// </summary>
  TValidationResult = record
    /// <summary>True if the document passed all validation checks.</summary>
    IsValid: Boolean;
    /// <summary>List of validation error messages.</summary>
    Errors: TArray<string>;
    /// <summary>List of validation warning messages (non-fatal).</summary>
    Warnings: TArray<string>;
    /// <summary>Creates an empty (valid) result.</summary>
    class function CreateValid: TValidationResult; static;
  end;

  /// <summary>
  /// Structural checker for CycloneDX and SPDX SBOM documents.
  /// </summary>
  TSbomValidator = class
  private
    FErrors: TList<string>;
    FWarnings: TList<string>;
    procedure AddError(const AMessage: string);
    procedure AddWarning(const AMessage: string);
    procedure ValidateCycloneDxJsonInternal(const AJson: TJSONObject);
    procedure ValidateCycloneDxJsonMetadata(const AMetadata: TJSONObject);
    procedure ValidateCycloneDxJsonComponent(const AComponent: TJSONObject; const AContext: string);
    procedure ValidateCycloneDxJsonComponents(const AComponents: TJSONArray);
    procedure ValidateCycloneDxJsonDependencies(const ADependencies: TJSONArray);
    procedure ValidateHashValue(const AAlgorithm, AHash, AContext: string);
    procedure ValidateSpdxJsonInternal(const AJson: TJSONObject);
    procedure ValidateSpdxJsonPackage(const APackage: TJSONObject; const AContext: string);
    function BuildResult: TValidationResult;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>
    /// Validates a CycloneDX 1.6 JSON document.
    /// </summary>
    function ValidateCycloneDxJson(const AContent: string): TValidationResult;
    /// <summary>
    /// Validates a CycloneDX 1.6 XML document.
    /// </summary>
    function ValidateCycloneDxXml(const AContent: string): TValidationResult;
    /// <summary>
    /// Validates an SPDX 2.3 JSON document.
    /// </summary>
    function ValidateSpdxJson(const AContent: string): TValidationResult;
    /// <summary>
    /// Auto-detects the format and validates accordingly.
    /// </summary>
    function ValidateAuto(const AContent: string): TValidationResult;
  end;

/// <summary>
/// Returns CycloneDX 1.6 sequence errors for metadata and component children.
/// An empty array means those elements are in an order the XSD accepts.
/// This does not validate the rest of the document.
/// </summary>
function CycloneDxXmlSequenceErrors(const AContent: string): TArray<string>;

implementation

{ TValidationResult }

class function TValidationResult.CreateValid: TValidationResult;
begin
  Result.IsValid := True;
  SetLength(Result.Errors, 0);
  SetLength(Result.Warnings, 0);
end;

{ TSbomValidator }

constructor TSbomValidator.Create;
begin
  inherited Create;
  FErrors := TList<string>.Create;
  FWarnings := TList<string>.Create;
end;

destructor TSbomValidator.Destroy;
begin
  FErrors.Free;
  FWarnings.Free;
  inherited;
end;

procedure TSbomValidator.AddError(const AMessage: string);
begin
  FErrors.Add(AMessage);
end;

procedure TSbomValidator.AddWarning(const AMessage: string);
begin
  FWarnings.Add(AMessage);
end;

function TSbomValidator.BuildResult: TValidationResult;
begin
  Result.IsValid := FErrors.Count = 0;
  Result.Errors := FErrors.ToArray;
  Result.Warnings := FWarnings.ToArray;
end;

procedure TSbomValidator.ValidateHashValue(const AAlgorithm, AHash, AContext: string);
var
  LExpected: Integer;
  LLabel: string;
begin
  if SameText(AAlgorithm, 'SHA-256') or SameText(AAlgorithm, 'SHA256') then
  begin
    LExpected := 64;
    LLabel := 'SHA-256';
  end
  else if SameText(AAlgorithm, 'SHA-512') or SameText(AAlgorithm, 'SHA512') then
  begin
    LExpected := 128;
    LLabel := 'SHA-512';
  end
  else
    Exit;

  if AHash = '' then
  begin
    AddWarning(AContext + ': hash is empty');
    Exit;
  end;
  if Length(AHash) <> LExpected then
    AddError(AContext + ': ' + LLabel + ' hash must be ' + IntToStr(LExpected) +
      ' hex characters, got ' + IntToStr(Length(AHash)));
  if not TRegEx.IsMatch(AHash, '^[0-9a-fA-F]{' + IntToStr(LExpected) + '}$') then
    AddError(AContext + ': ' + LLabel + ' hash contains invalid characters');
end;

// ---------------------------------------------------------------------------
// CycloneDX JSON Validation
// ---------------------------------------------------------------------------

function TSbomValidator.ValidateCycloneDxJson(const AContent: string): TValidationResult;
var
  LJson: TJSONObject;
begin
  FErrors.Clear;
  FWarnings.Clear;

  if Trim(AContent) = '' then
  begin
    AddError('Document is empty');
    Exit(BuildResult);
  end;

  try
    LJson := TJSONObject.ParseJSONValue(AContent) as TJSONObject;
    try
      if not Assigned(LJson) then
      begin
        AddError('Invalid JSON: could not parse document');
        Exit(BuildResult);
      end;
      ValidateCycloneDxJsonInternal(LJson);
    finally
      LJson.Free;
    end;
  except
    on E: Exception do
      AddError('JSON parse error: ' + E.Message);
  end;

  Result := BuildResult;
end;

procedure TSbomValidator.ValidateCycloneDxJsonInternal(const AJson: TJSONObject);
var
  LValue: TJSONValue;
  LSerialNumber, LSpecVersion, LBomFormat: string;
begin
  // bomFormat (required, must be 'CycloneDX')
  LValue := AJson.GetValue('bomFormat');
  if LValue = nil then
    AddError('Missing required field: bomFormat')
  else
  begin
    LBomFormat := LValue.Value;
    if LBomFormat <> 'CycloneDX' then
      AddError('bomFormat must be "CycloneDX", got "' + LBomFormat + '"');
  end;

  // specVersion (required, must be 1.4 or 1.5 or 1.6)
  LValue := AJson.GetValue('specVersion');
  if LValue = nil then
    AddError('Missing required field: specVersion')
  else
  begin
    LSpecVersion := LValue.Value;
    if (LSpecVersion <> '1.4') and (LSpecVersion <> '1.5') and (LSpecVersion <> '1.6') then
      AddWarning('specVersion "' + LSpecVersion + '" is not 1.4, 1.5, or 1.6');
  end;

  // serialNumber (optional but recommended; must start with urn:uuid: if present)
  LValue := AJson.GetValue('serialNumber');
  if LValue <> nil then
  begin
    LSerialNumber := LValue.Value;
    if not LSerialNumber.StartsWith('urn:uuid:') then
      AddError('serialNumber must start with "urn:uuid:", got "' + LSerialNumber + '"');
    // Validate UUID format after prefix
    if LSerialNumber.StartsWith('urn:uuid:') then
    begin
      var LUUID := LSerialNumber.Substring(9);
      if not TRegEx.IsMatch(LUUID, '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
        AddWarning('serialNumber UUID format may be non-standard: ' + LUUID);
    end;
  end
  else
    AddWarning('Missing recommended field: serialNumber');

  // version (required, must be a positive integer)
  LValue := AJson.GetValue('version');
  if LValue = nil then
    AddError('Missing required field: version')
  else if not (LValue is TJSONNumber) then
    AddError('version must be a number');

  // metadata (required)
  LValue := AJson.GetValue('metadata');
  if LValue = nil then
    AddError('Missing required field: metadata')
  else if LValue is TJSONObject then
    ValidateCycloneDxJsonMetadata(LValue as TJSONObject)
  else
    AddError('metadata must be a JSON object');

  // components (required, must be an array)
  LValue := AJson.GetValue('components');
  if LValue = nil then
    AddError('Missing required field: components')
  else if LValue is TJSONArray then
    ValidateCycloneDxJsonComponents(LValue as TJSONArray)
  else
    AddError('components must be a JSON array');

  // dependencies (optional but recommended)
  LValue := AJson.GetValue('dependencies');
  if LValue = nil then
    AddWarning('Missing recommended field: dependencies')
  else if LValue is TJSONArray then
    ValidateCycloneDxJsonDependencies(LValue as TJSONArray)
  else
    AddError('dependencies must be a JSON array');
end;

procedure TSbomValidator.ValidateCycloneDxJsonMetadata(const AMetadata: TJSONObject);
var
  LValue: TJSONValue;
  LTimestamp: string;
begin
  // timestamp (required)
  LValue := AMetadata.GetValue('timestamp');
  if LValue = nil then
    AddError('metadata: missing required field: timestamp')
  else
  begin
    LTimestamp := LValue.Value;
    // Basic ISO 8601 validation
    if (Length(LTimestamp) < 10) or (Pos('T', LTimestamp) = 0) then
      AddWarning('metadata.timestamp may not be valid ISO 8601: ' + LTimestamp);
  end;

  // component (required; describes the subject of the SBOM)
  LValue := AMetadata.GetValue('component');
  if LValue = nil then
    AddWarning('metadata: missing recommended field: component')
  else if LValue is TJSONObject then
    ValidateCycloneDxJsonComponent(LValue as TJSONObject, 'metadata.component')
  else
    AddError('metadata.component must be a JSON object');

  // tools (optional but recommended)
  LValue := AMetadata.GetValue('tools');
  if LValue = nil then
    AddWarning('metadata: missing recommended field: tools');
end;

procedure TSbomValidator.ValidateCycloneDxJsonComponent(const AComponent: TJSONObject;
  const AContext: string);
var
  LValue: TJSONValue;
  LComponentType: string;
begin
  // type (required)
  LValue := AComponent.GetValue('type');
  if LValue = nil then
    AddError(AContext + ': missing required field: type')
  else
  begin
    LComponentType := LValue.Value;
    if not TRegEx.IsMatch(LComponentType,
      '^(application|framework|library|container|platform|device-driver|firmware|file|machine-learning-model|data)$') then
      AddError(AContext + ': invalid component type: "' + LComponentType + '"');
  end;

  // name (required)
  LValue := AComponent.GetValue('name');
  if LValue = nil then
    AddError(AContext + ': missing required field: name');

  // hashes validation (if present)
  LValue := AComponent.GetValue('hashes');
  if (LValue <> nil) and (LValue is TJSONArray) then
  begin
    var LHashes := LValue as TJSONArray;
    var I: Integer;
    for I := 0 to LHashes.Count - 1 do
    begin
      if LHashes.Items[I] is TJSONObject then
      begin
        var LHash := LHashes.Items[I] as TJSONObject;
        var LAlg := LHash.GetValue('alg');
        var LContent := LHash.GetValue('content');
        if LAlg = nil then
          AddError(AContext + '.hashes[' + IntToStr(I) + ']: missing required field: alg');
        if LContent = nil then
          AddError(AContext + '.hashes[' + IntToStr(I) + ']: missing required field: content')
        else if (LAlg <> nil) and
          (SameText(LAlg.Value, 'SHA-256') or SameText(LAlg.Value, 'SHA-512')) then
          ValidateHashValue(LAlg.Value, LContent.Value,
            AContext + '.hashes[' + IntToStr(I) + ']');
      end;
    end;
  end;
end;

procedure TSbomValidator.ValidateCycloneDxJsonComponents(const AComponents: TJSONArray);
var
  I: Integer;
  LBomRefs: TDictionary<string, Integer>;
  LBomRef: string;
  LComponent: TJSONObject;
begin
  LBomRefs := TDictionary<string, Integer>.Create;
  try
    for I := 0 to AComponents.Count - 1 do
    begin
      if not (AComponents.Items[I] is TJSONObject) then
      begin
        AddError('components[' + IntToStr(I) + ']: must be a JSON object');
        Continue;
      end;

      LComponent := AComponents.Items[I] as TJSONObject;
      ValidateCycloneDxJsonComponent(LComponent, 'components[' + IntToStr(I) + ']');

      // Check for duplicate bom-ref
      if LComponent.GetValue('bom-ref') <> nil then
      begin
        LBomRef := LComponent.GetValue<string>('bom-ref');
        if LBomRefs.ContainsKey(LBomRef) then
          AddError('Duplicate bom-ref: "' + LBomRef + '" in components[' +
            IntToStr(LBomRefs[LBomRef]) + '] and components[' + IntToStr(I) + ']')
        else
          LBomRefs.Add(LBomRef, I);
      end;
    end;
  finally
    LBomRefs.Free;
  end;
end;

procedure TSbomValidator.ValidateCycloneDxJsonDependencies(const ADependencies: TJSONArray);
var
  I: Integer;
  LDep: TJSONObject;
begin
  for I := 0 to ADependencies.Count - 1 do
  begin
    if not (ADependencies.Items[I] is TJSONObject) then
    begin
      AddError('dependencies[' + IntToStr(I) + ']: must be a JSON object');
      Continue;
    end;

    LDep := ADependencies.Items[I] as TJSONObject;

    // ref (required)
    if LDep.GetValue('ref') = nil then
      AddError('dependencies[' + IntToStr(I) + ']: missing required field: ref');

    // dependsOn (optional, must be array if present)
    var LDependsOn := LDep.GetValue('dependsOn');
    if (LDependsOn <> nil) and not (LDependsOn is TJSONArray) then
      AddError('dependencies[' + IntToStr(I) + ']: dependsOn must be a JSON array');
  end;
end;

// ---------------------------------------------------------------------------
// CycloneDX XML Validation
// ---------------------------------------------------------------------------

function TSbomValidator.ValidateCycloneDxXml(const AContent: string): TValidationResult;
var
  LMatch: TMatch;
begin
  FErrors.Clear;
  FWarnings.Clear;

  if Trim(AContent) = '' then
  begin
    AddError('Document is empty');
    Exit(BuildResult);
  end;

  // XML declaration
  if not AContent.StartsWith('<?xml') then
    AddError('Missing XML declaration (<?xml ...?>)');

  // CycloneDX namespace
  if Pos('http://cyclonedx.org/schema/bom/', AContent) = 0 then
    AddError('Missing CycloneDX namespace (http://cyclonedx.org/schema/bom/...)');

  // <bom> root element
  if Pos('<bom', AContent) = 0 then
    AddError('Missing root element: <bom>');

  // serialNumber attribute
  LMatch := TRegEx.Match(AContent, 'serialNumber="(urn:uuid:[^"]*?)"', [roIgnoreCase]);
  if not LMatch.Success then
    AddWarning('Missing recommended attribute: serialNumber on <bom>')
  else
  begin
    var LSerial := LMatch.Groups[1].Value;
    if not LSerial.StartsWith('urn:uuid:') then
      AddError('serialNumber must start with "urn:uuid:"');
  end;

  // <metadata> section
  if Pos('<metadata>', AContent) = 0 then
    AddError('Missing required element: <metadata>');

  // <timestamp> in metadata
  LMatch := TRegEx.Match(AContent, '<timestamp>([^<]+)</timestamp>', [roIgnoreCase]);
  if not LMatch.Success then
    AddError('Missing required element: <timestamp> in <metadata>')
  else
  begin
    var LTimestamp := LMatch.Groups[1].Value;
    if (Length(LTimestamp) < 10) or (Pos('T', LTimestamp) = 0) then
      AddWarning('timestamp may not be valid ISO 8601: ' + LTimestamp);
  end;

  // <components> section
  if Pos('<components>', AContent) = 0 then
    AddError('Missing required element: <components>');

  // <component> elements with type attribute
  LMatch := TRegEx.Match(AContent, '<component\s+type="([^"]*)"', [roIgnoreCase]);
  if not LMatch.Success then
    AddWarning('No <component> elements found with type attribute');

  // Hash elements validation
  var LHashMatches := TRegEx.Matches(AContent,
    '<hash\s+alg="(SHA-256|SHA-512)">([^<]*)</hash>', [roIgnoreCase]);
  var LHashMatch: TMatch;
  for LHashMatch in LHashMatches do
    ValidateHashValue(LHashMatch.Groups[1].Value, LHashMatch.Groups[2].Value,
      'XML hash element');

  // <dependencies> section (recommended)
  if Pos('<dependencies>', AContent) = 0 then
    AddWarning('Missing recommended element: <dependencies>');

  for var LSequenceError in CycloneDxXmlSequenceErrors(AContent) do
    AddError(LSequenceError);

  Result := BuildResult;
end;

function CycloneDxXmlSequenceErrors(const AContent: string): TArray<string>;
const
  cMetadataOrder: array[0..9] of string = (
    'timestamp', 'lifecycles', 'tools', 'authors', 'component',
    'manufacturer', 'manufacture', 'supplier', 'licenses', 'properties');
  cComponentOrder: array[0..28] of string = (
    'supplier', 'manufacturer', 'authors', 'author', 'publisher', 'group',
    'name', 'version', 'description', 'scope', 'hashes', 'licenses',
    'copyright', 'cpe', 'purl', 'omniborId', 'swhid', 'swid', 'modified',
    'pedigree', 'externalReferences', 'properties', 'components', 'evidence',
    'releaseNotes', 'modelCard', 'data', 'cryptoProperties', 'tags');
var
  LErrors: TList<string>;
  LPos: Integer;
  LStack: TArray<string>;
  LChildren: TArray<TArray<string>>;
  LName: string;
  LClosing, LSelfClosing: Boolean;
  LQuote: Char;

  procedure CheckOrder(const AParent: string; const ANames: TArray<string>;
    const AExpected: array of string);
  var
    I, J, LIndex, LLast: Integer;
  begin
    LLast := -1;
    for I := 0 to High(ANames) do
    begin
      LIndex := -1;
      for J := Low(AExpected) to High(AExpected) do
        if SameText(AExpected[J], ANames[I]) then
        begin
          LIndex := J;
          Break;
        end;
      if LIndex < 0 then
        Continue;
      if LIndex < LLast then
        LErrors.Add('<' + AParent + '>: <' + ANames[I] +
          '> is out of CycloneDX 1.6 sequence order');
      LLast := LIndex;
    end;
  end;

  procedure Push(const AName: string);
  var
    LFrame: Integer;
  begin
    LFrame := Length(LStack);
    SetLength(LStack, LFrame + 1);
    SetLength(LChildren, LFrame + 1);
    LStack[LFrame] := AName;
    SetLength(LChildren[LFrame], 0);
  end;

  procedure Pop;
  var
    LFrame: Integer;
    LParent: string;
    LNames: TArray<string>;
  begin
    if Length(LStack) = 0 then
      Exit;
    LFrame := High(LStack);
    LParent := LStack[LFrame];
    LNames := LChildren[LFrame];
    SetLength(LStack, LFrame);
    SetLength(LChildren, LFrame);
    if SameText(LParent, 'metadata') then
      CheckOrder(LParent, LNames, cMetadataOrder)
    else if SameText(LParent, 'component') then
      CheckOrder(LParent, LNames, cComponentOrder);
  end;

  procedure AddChild(const AName: string);
  var
    LCount, LFrame: Integer;
  begin
    if Length(LStack) = 0 then
      Exit;
    LFrame := High(LStack);
    LCount := Length(LChildren[LFrame]);
    SetLength(LChildren[LFrame], LCount + 1);
    LChildren[LFrame][LCount] := AName;
  end;

begin
  LErrors := TList<string>.Create;
  try
    LPos := 1;
    SetLength(LStack, 0);
    SetLength(LChildren, 0);
    while LPos <= Length(AContent) do
    begin
      if AContent[LPos] <> '<' then
      begin
        Inc(LPos);
        Continue;
      end;

      if (LPos < Length(AContent)) and (AContent[LPos + 1] = '?') then
      begin
        Inc(LPos);
        while (LPos < Length(AContent)) and
          not ((AContent[LPos] = '?') and (AContent[LPos + 1] = '>')) do
          Inc(LPos);
        Inc(LPos, 2);
        Continue;
      end;

      if Copy(AContent, LPos, 4) = '<!--' then
      begin
        Inc(LPos, 4);
        while (LPos <= Length(AContent) - 2) and (Copy(AContent, LPos, 3) <> '-->') do
          Inc(LPos);
        Inc(LPos, 3);
        Continue;
      end;

      Inc(LPos);
      LClosing := (LPos <= Length(AContent)) and (AContent[LPos] = '/');
      if LClosing then
        Inc(LPos);

      LName := '';
      while (LPos <= Length(AContent)) and (AContent[LPos] > ' ') and
        (AContent[LPos] <> '>') and (AContent[LPos] <> '/') do
      begin
        LName := LName + AContent[LPos];
        Inc(LPos);
      end;
      if Pos(':', LName) > 0 then
        LName := Copy(LName, Pos(':', LName) + 1, MaxInt);

      LSelfClosing := False;
      LQuote := #0;
      while LPos <= Length(AContent) do
      begin
        if LQuote <> #0 then
        begin
          if AContent[LPos] = LQuote then
            LQuote := #0;
          Inc(LPos);
          Continue;
        end;
        if (AContent[LPos] = '"') or (AContent[LPos] = '''') then
        begin
          LQuote := AContent[LPos];
          Inc(LPos);
          Continue;
        end;
        if AContent[LPos] = '/' then
          LSelfClosing := True;
        if AContent[LPos] = '>' then
        begin
          Inc(LPos);
          Break;
        end;
        Inc(LPos);
      end;

      if LName = '' then
        Continue;

      if LClosing then
        Pop
      else
      begin
        AddChild(LName);
        if not LSelfClosing then
          Push(LName);
      end;
    end;

    Result := LErrors.ToArray;
  finally
    LErrors.Free;
  end;
end;

// ---------------------------------------------------------------------------
// SPDX JSON Validation
// ---------------------------------------------------------------------------

function TSbomValidator.ValidateSpdxJson(const AContent: string): TValidationResult;
var
  LJson: TJSONObject;
begin
  FErrors.Clear;
  FWarnings.Clear;

  if Trim(AContent) = '' then
  begin
    AddError('Document is empty');
    Exit(BuildResult);
  end;

  try
    LJson := TJSONObject.ParseJSONValue(AContent) as TJSONObject;
    try
      if not Assigned(LJson) then
      begin
        AddError('Invalid JSON: could not parse document');
        Exit(BuildResult);
      end;
      ValidateSpdxJsonInternal(LJson);
    finally
      LJson.Free;
    end;
  except
    on E: Exception do
      AddError('JSON parse error: ' + E.Message);
  end;

  Result := BuildResult;
end;

procedure TSbomValidator.ValidateSpdxJsonInternal(const AJson: TJSONObject);
var
  LValue: TJSONValue;
  LSpdxVersion, LDataLicense, LSpdxId: string;
begin
  // spdxVersion (required)
  LValue := AJson.GetValue('spdxVersion');
  if LValue = nil then
    AddError('Missing required field: spdxVersion')
  else
  begin
    LSpdxVersion := LValue.Value;
    if not LSpdxVersion.StartsWith('SPDX-') then
      AddError('spdxVersion must start with "SPDX-", got "' + LSpdxVersion + '"');
  end;

  // dataLicense (required, must be CC0-1.0)
  LValue := AJson.GetValue('dataLicense');
  if LValue = nil then
    AddError('Missing required field: dataLicense')
  else
  begin
    LDataLicense := LValue.Value;
    if LDataLicense <> 'CC0-1.0' then
      AddError('dataLicense must be "CC0-1.0", got "' + LDataLicense + '"');
  end;

  // SPDXID (required, must be SPDXRef-DOCUMENT)
  LValue := AJson.GetValue('SPDXID');
  if LValue = nil then
    AddError('Missing required field: SPDXID')
  else
  begin
    LSpdxId := LValue.Value;
    if LSpdxId <> 'SPDXRef-DOCUMENT' then
      AddError('Document SPDXID must be "SPDXRef-DOCUMENT", got "' + LSpdxId + '"');
  end;

  // name (required)
  if AJson.GetValue('name') = nil then
    AddError('Missing required field: name');

  // documentNamespace (required)
  LValue := AJson.GetValue('documentNamespace');
  if LValue = nil then
    AddError('Missing required field: documentNamespace')
  else
  begin
    var LNamespace := LValue.Value;
    if not LNamespace.StartsWith('https://') then
      AddWarning('documentNamespace should be an HTTPS URI: ' + LNamespace);
  end;

  // creationInfo (required)
  LValue := AJson.GetValue('creationInfo');
  if LValue = nil then
    AddError('Missing required field: creationInfo')
  else if LValue is TJSONObject then
  begin
    var LCreationInfo := LValue as TJSONObject;
    // created (required)
    if LCreationInfo.GetValue('created') = nil then
      AddError('creationInfo: missing required field: created');
    // creators (required, must be non-empty array)
    var LCreators := LCreationInfo.GetValue('creators');
    if LCreators = nil then
      AddError('creationInfo: missing required field: creators')
    else if not (LCreators is TJSONArray) then
      AddError('creationInfo.creators must be a JSON array')
    else if (LCreators as TJSONArray).Count = 0 then
      AddError('creationInfo.creators must not be empty');
  end
  else
    AddError('creationInfo must be a JSON object');

  // packages (required)
  LValue := AJson.GetValue('packages');
  if LValue = nil then
    AddError('Missing required field: packages')
  else if LValue is TJSONArray then
  begin
    var LPackages := LValue as TJSONArray;
    var I: Integer;
    for I := 0 to LPackages.Count - 1 do
    begin
      if LPackages.Items[I] is TJSONObject then
        ValidateSpdxJsonPackage(LPackages.Items[I] as TJSONObject, 'packages[' + IntToStr(I) + ']')
      else
        AddError('packages[' + IntToStr(I) + ']: must be a JSON object');
    end;
  end
  else
    AddError('packages must be a JSON array');

  // relationships (recommended)
  LValue := AJson.GetValue('relationships');
  if LValue = nil then
    AddWarning('Missing recommended field: relationships')
  else if not (LValue is TJSONArray) then
    AddError('relationships must be a JSON array');
end;

procedure TSbomValidator.ValidateSpdxJsonPackage(const APackage: TJSONObject;
  const AContext: string);
var
  LValue: TJSONValue;
  LSpdxId: string;
begin
  // SPDXID (required)
  LValue := APackage.GetValue('SPDXID');
  if LValue = nil then
    AddError(AContext + ': missing required field: SPDXID')
  else
  begin
    LSpdxId := LValue.Value;
    if not LSpdxId.StartsWith('SPDXRef-') then
      AddError(AContext + ': SPDXID must start with "SPDXRef-", got "' + LSpdxId + '"');
  end;

  // name (required)
  if APackage.GetValue('name') = nil then
    AddError(AContext + ': missing required field: name');

  // downloadLocation (required)
  if APackage.GetValue('downloadLocation') = nil then
    AddError(AContext + ': missing required field: downloadLocation');

  // checksums validation (if present)
  LValue := APackage.GetValue('checksums');
  if (LValue <> nil) and (LValue is TJSONArray) then
  begin
    var LChecksums := LValue as TJSONArray;
    var I: Integer;
    for I := 0 to LChecksums.Count - 1 do
    begin
      if LChecksums.Items[I] is TJSONObject then
      begin
        var LChecksum := LChecksums.Items[I] as TJSONObject;
        var LAlg := LChecksum.GetValue('algorithm');
        var LVal := LChecksum.GetValue('checksumValue');
        if LAlg = nil then
          AddError(AContext + '.checksums[' + IntToStr(I) + ']: missing required field: algorithm');
        if LVal = nil then
          AddError(AContext + '.checksums[' + IntToStr(I) + ']: missing required field: checksumValue')
        else if (LAlg <> nil) and
          (SameText(LAlg.Value, 'SHA256') or SameText(LAlg.Value, 'SHA512')) then
          ValidateHashValue(LAlg.Value, LVal.Value,
            AContext + '.checksums[' + IntToStr(I) + ']');
      end;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Auto-detect and validate
// ---------------------------------------------------------------------------

function TSbomValidator.ValidateAuto(const AContent: string): TValidationResult;
var
  LTrimmed: string;
begin
  FErrors.Clear;
  FWarnings.Clear;

  LTrimmed := Trim(AContent);
  if LTrimmed = '' then
  begin
    AddError('Document is empty');
    Exit(BuildResult);
  end;

  // Detect format by content
  if LTrimmed.StartsWith('<?xml') or LTrimmed.StartsWith('<bom') then
    Result := ValidateCycloneDxXml(AContent)
  else if LTrimmed.StartsWith('{') then
  begin
    // Try to distinguish CycloneDX JSON from SPDX JSON
    if Pos('"bomFormat"', LTrimmed) > 0 then
      Result := ValidateCycloneDxJson(AContent)
    else if Pos('"spdxVersion"', LTrimmed) > 0 then
      Result := ValidateSpdxJson(AContent)
    else
    begin
      AddError('Cannot determine SBOM format: no "bomFormat" or "spdxVersion" field found');
      Result := BuildResult;
    end;
  end
  else
  begin
    AddError('Cannot determine SBOM format: content does not start with JSON or XML');
    Result := BuildResult;
  end;
end;

end.
