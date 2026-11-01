/// <summary>
/// DX.Comply.SbomHeaderConfig
/// Reads and writes the SBOM header keys of a project's .dxcomply.json.
/// </summary>
///
/// <remarks>
/// The header keys are the ones the CRA/BSI warnings ask for:
///   sbomCreator, product.supplier, product.supplierUrl, product.licence
///   and product.version.
/// The CLI reads the same keys in TDxComplyGenerator.LoadConfig, so a file
/// written here works for both the IDE and DX.Comply.CLI.exe --ci.
/// Writing keeps every other key and the order of existing keys. An empty
/// field removes its key. An empty product object that only held header
/// keys is removed as well. A file that is not a JSON object is never
/// overwritten.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.SbomHeaderConfig;

interface

uses
  DX.Comply.Engine;

type
  /// <summary>
  /// SBOM header data stored per project. Empty means not set.
  /// </summary>
  TSbomHeaderData = record
    /// <summary>sbomCreator: email address or http(s) URL of the SBOM creator.</summary>
    SbomCreator: string;
    /// <summary>product.supplier: manufacturer or supplier name.</summary>
    Supplier: string;
    /// <summary>product.supplierUrl: supplier contact URL.</summary>
    SupplierUrl: string;
    /// <summary>product.licence: distribution licence, an SPDX expression.</summary>
    Licence: string;
    /// <summary>product.version: version override. Empty uses the project version info.</summary>
    ProductVersion: string;
    /// <summary>All fields empty.</summary>
    class function Empty: TSbomHeaderData; static;
    /// <summary>Copy with every field trimmed.</summary>
    function Trimmed: TSbomHeaderData;
  end;

  /// <summary>
  /// Read, merge, validate and apply the SBOM header keys.
  /// </summary>
  TSbomHeaderConfig = class
  public
    const
      cConfigFileName = '.dxcomply.json';
    /// <summary>
    /// Path of .dxcomply.json in the folder of AProjectPath.
    /// </summary>
    class function ConfigPathForProject(const AProjectPath: string): string; static;
    /// <summary>
    /// Reads the header keys from JSON text. Missing keys stay empty.
    /// False with AError when the text is not a JSON object, product is not
    /// an object, or a header value is not a string or number.
    /// </summary>
    class function TryParse(const AJson: string; out AHeader: TSbomHeaderData;
      out AError: string): Boolean; static;
    /// <summary>
    /// Reads the header keys from a file. A missing file is not an error
    /// and returns empty data.
    /// </summary>
    class function TryRead(const AConfigPath: string; out AHeader: TSbomHeaderData;
      out AError: string): Boolean; static;
    /// <summary>
    /// Writes AHeader into the existing JSON text and returns the result,
    /// formatted with two spaces. Empty AExistingJson starts a new object.
    /// Other keys are kept. False with AError when AExistingJson is not a
    /// JSON object or product is not an object.
    /// </summary>
    class function TryMerge(const AExistingJson: string; const AHeader: TSbomHeaderData;
      out AMergedJson: string; out AError: string): Boolean; static;
    /// <summary>
    /// Merges AHeader into the file (created when missing) and saves it as
    /// UTF-8 without BOM. The file is left unchanged when the merge fails.
    /// </summary>
    class function TryWrite(const AConfigPath: string; const AHeader: TSbomHeaderData;
      out AError: string): Boolean; static;
    /// <summary>
    /// Problems the user must fix before saving. Empty when AHeader is valid.
    /// The SBOM creator is checked like the engine does (IsAcceptableBsiCreator),
    /// the supplier URL must be an http(s) URL. Empty fields are valid.
    /// </summary>
    class function Validate(const AHeader: TSbomHeaderData): TArray<string>; static;
    /// <summary>
    /// Copies every non-empty header field onto AConfig. Empty fields leave
    /// AConfig unchanged, so the project version info still fills them.
    /// </summary>
    class procedure ApplyToConfig(const AHeader: TSbomHeaderData;
      var AConfig: TSbomConfig); static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  DX.Comply.Engine.Intf;

const
  cKeySbomCreator = 'sbomCreator';
  cKeyProduct = 'product';
  cKeySupplier = 'supplier';
  cKeySupplierUrl = 'supplierUrl';
  cKeyLicence = 'licence';
  cKeyVersion = 'version';

{ TSbomHeaderData }

class function TSbomHeaderData.Empty: TSbomHeaderData;
begin
  Result.SbomCreator := '';
  Result.Supplier := '';
  Result.SupplierUrl := '';
  Result.Licence := '';
  Result.ProductVersion := '';
end;

function TSbomHeaderData.Trimmed: TSbomHeaderData;
begin
  Result.SbomCreator := Trim(SbomCreator);
  Result.Supplier := Trim(Supplier);
  Result.SupplierUrl := Trim(SupplierUrl);
  Result.Licence := Trim(Licence);
  Result.ProductVersion := Trim(ProductVersion);
end;

{ Helpers }

function TryReadText(const AObject: TJSONObject; const AKey, APath: string;
  var AValue: string; var AError: string): Boolean;
begin
  Result := True;
  var LValue := AObject.GetValue(AKey);
  if (LValue = nil) or (LValue is TJSONNull) then
    Exit;
  if not ((LValue is TJSONString) or (LValue is TJSONNumber)) then
  begin
    AError := APath + ' must be a string';
    Exit(False);
  end;
  AValue := Trim(LValue.Value);
end;

procedure SetOrRemove(const AObject: TJSONObject; const AKey, AValue: string);
begin
  var LPair := AObject.Get(AKey);
  if AValue = '' then
  begin
    if Assigned(LPair) then
    begin
      AObject.RemovePair(AKey).Free;
    end;
  end
  else if Assigned(LPair) then
  begin
    // Replacing the value keeps the key at its position.
    LPair.JsonValue := TJSONString.Create(AValue);
  end
  else
  begin
    AObject.AddPair(AKey, AValue);
  end;
end;

function ParseRoot(const AJson: string; out ARoot: TJSONObject;
  out AError: string): Boolean;
begin
  ARoot := nil;
  AError := '';
  if Trim(AJson) = '' then
  begin
    ARoot := TJSONObject.Create;
    Exit(True);
  end;

  var LValue := TJSONObject.ParseJSONValue(AJson);
  if LValue = nil then
  begin
    AError := 'Invalid JSON';
    Exit(False);
  end;
  if not (LValue is TJSONObject) then
  begin
    LValue.Free;
    AError := 'Config root must be a JSON object';
    Exit(False);
  end;
  ARoot := TJSONObject(LValue);
  Result := True;
end;

{ TSbomHeaderConfig }

class function TSbomHeaderConfig.ConfigPathForProject(const AProjectPath: string): string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(AProjectPath), cConfigFileName);
end;

class function TSbomHeaderConfig.TryParse(const AJson: string;
  out AHeader: TSbomHeaderData; out AError: string): Boolean;
var
  LRoot: TJSONObject;
begin
  AHeader := TSbomHeaderData.Empty;
  if not ParseRoot(AJson, LRoot, AError) then
    Exit(False);
  try
    if not TryReadText(LRoot, cKeySbomCreator, cKeySbomCreator, AHeader.SbomCreator, AError) then
      Exit(False);

    var LProductValue := LRoot.GetValue(cKeyProduct);
    if Assigned(LProductValue) and not (LProductValue is TJSONNull) then
    begin
      if not (LProductValue is TJSONObject) then
      begin
        AError := 'product must be a JSON object';
        Exit(False);
      end;
      var LProduct := TJSONObject(LProductValue);
      if not TryReadText(LProduct, cKeySupplier, 'product.supplier', AHeader.Supplier, AError) then
        Exit(False);
      if not TryReadText(LProduct, cKeySupplierUrl, 'product.supplierUrl', AHeader.SupplierUrl, AError) then
        Exit(False);
      if not TryReadText(LProduct, cKeyLicence, 'product.licence', AHeader.Licence, AError) then
        Exit(False);
      if not TryReadText(LProduct, cKeyVersion, 'product.version', AHeader.ProductVersion, AError) then
        Exit(False);
    end;
    Result := True;
  finally
    LRoot.Free;
  end;
end;

class function TSbomHeaderConfig.TryRead(const AConfigPath: string;
  out AHeader: TSbomHeaderData; out AError: string): Boolean;
begin
  AHeader := TSbomHeaderData.Empty;
  AError := '';
  if not TFile.Exists(AConfigPath) then
    Exit(True);
  try
    Result := TryParse(TFile.ReadAllText(AConfigPath, TEncoding.UTF8), AHeader, AError);
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

class function TSbomHeaderConfig.TryMerge(const AExistingJson: string;
  const AHeader: TSbomHeaderData; out AMergedJson: string; out AError: string): Boolean;
var
  LRoot: TJSONObject;
begin
  AMergedJson := '';
  if not ParseRoot(AExistingJson, LRoot, AError) then
    Exit(False);
  try
    var LHeader := AHeader.Trimmed;
    var LProductValue := LRoot.GetValue(cKeyProduct);
    if Assigned(LProductValue) and not (LProductValue is TJSONObject) and
       not (LProductValue is TJSONNull) then
    begin
      AError := 'product must be a JSON object';
      Exit(False);
    end;

    SetOrRemove(LRoot, cKeySbomCreator, LHeader.SbomCreator);

    var LProduct: TJSONObject := nil;
    if LProductValue is TJSONObject then
    begin
      LProduct := TJSONObject(LProductValue);
    end
    else if (LHeader.Supplier <> '') or (LHeader.SupplierUrl <> '') or
            (LHeader.Licence <> '') or (LHeader.ProductVersion <> '') then
    begin
      if Assigned(LProductValue) then
      begin
        LRoot.RemovePair(cKeyProduct).Free;
      end;
      LProduct := TJSONObject.Create;
      LRoot.AddPair(cKeyProduct, LProduct);
    end;

    if Assigned(LProduct) then
    begin
      SetOrRemove(LProduct, cKeySupplier, LHeader.Supplier);
      SetOrRemove(LProduct, cKeySupplierUrl, LHeader.SupplierUrl);
      SetOrRemove(LProduct, cKeyLicence, LHeader.Licence);
      SetOrRemove(LProduct, cKeyVersion, LHeader.ProductVersion);
      if LProduct.Count = 0 then
      begin
        LRoot.RemovePair(cKeyProduct).Free;
      end;
    end;

    AMergedJson := LRoot.Format(2);
    Result := True;
  finally
    LRoot.Free;
  end;
end;

class function TSbomHeaderConfig.TryWrite(const AConfigPath: string;
  const AHeader: TSbomHeaderData; out AError: string): Boolean;
var
  LExisting: string;
  LMerged: string;
begin
  AError := '';
  try
    LExisting := '';
    if TFile.Exists(AConfigPath) then
    begin
      LExisting := TFile.ReadAllText(AConfigPath, TEncoding.UTF8);
    end;
    if not TryMerge(LExisting, AHeader, LMerged, AError) then
      Exit(False);
    TFile.WriteAllText(AConfigPath, LMerged + sLineBreak, TUTF8Encoding.Create(False));
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

class function TSbomHeaderConfig.Validate(const AHeader: TSbomHeaderData): TArray<string>;
begin
  var LHeader := AHeader.Trimmed;
  var LErrors := TList<string>.Create;
  try
    if not IsAcceptableBsiCreator(LHeader.SbomCreator) then
    begin
      LErrors.Add('The SBOM creator must be an email address or an http(s) URL, not a name.');
    end;
    if (LHeader.SupplierUrl <> '') and not IsBsiHttpUrl(LHeader.SupplierUrl) then
    begin
      LErrors.Add('The supplier URL must start with http:// or https://.');
    end;
    Result := LErrors.ToArray;
  finally
    LErrors.Free;
  end;
end;

class procedure TSbomHeaderConfig.ApplyToConfig(const AHeader: TSbomHeaderData;
  var AConfig: TSbomConfig);
begin
  var LHeader := AHeader.Trimmed;
  if LHeader.SbomCreator <> '' then
  begin
    AConfig.SbomCreator := LHeader.SbomCreator;
  end;
  if LHeader.Supplier <> '' then
  begin
    AConfig.Supplier := LHeader.Supplier;
  end;
  if LHeader.SupplierUrl <> '' then
  begin
    AConfig.SupplierUrl := LHeader.SupplierUrl;
  end;
  if LHeader.Licence <> '' then
  begin
    AConfig.Licence := LHeader.Licence;
  end;
  if LHeader.ProductVersion <> '' then
  begin
    AConfig.ProductVersion := LHeader.ProductVersion;
  end;
end;

end.
