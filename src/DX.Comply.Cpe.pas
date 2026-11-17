/// <summary>
/// DX.Comply.Cpe
/// CPE 2.3 names and a CPE Dictionary 2.3 submission.
/// </summary>
///
/// <remarks>
/// Formats a vendor, product and version into a CPE 2.3 formatted string
/// and the matching CPE 2.2 URI, then builds the dictionary XML and the
/// mail text for cpe_dictionary@nist.gov. Nothing in this unit sends mail
/// or contacts the network. NIST may normalize the vendor and product.
/// The binding follows NISTIR 7695: unreserved characters stay, specials
/// are backslash-escaped in the formatted string and percent-encoded in
/// the URI, and an empty attribute is ANY.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Cpe;

interface

uses
  System.SysUtils;

const
  /// <summary>Mailbox NIST publishes for new CPE dictionary entries.</summary>
  cCpeDictionaryMailAddress = 'cpe_dictionary@nist.gov';
  /// <summary>
  /// Public NVD page that searches the CPE dictionary. The IDE search calls
  /// the API. This page is the same dictionary for a manual check.
  /// </summary>
  cNvdCpeWebSearchUrl = 'https://nvd.nist.gov/products/cpe/search';

type
  /// <summary>One provenance link written into the dictionary submission.</summary>
  TCpeReference = record
    /// <summary>Absolute http or https URL.</summary>
    Href: string;
    /// <summary>Short label, for example Product or Repository.</summary>
    Caption: string;
  end;

  /// <summary>
  /// The product identity a dictionary submission is built from.
  /// Vendor, product and version are the human-readable proposal.
  /// </summary>
  TCpeSubmission = record
    /// <summary>Supplier or vendor name, before CPE normalization.</summary>
    Vendor: string;
    /// <summary>Product name, before CPE normalization.</summary>
    Product: string;
    /// <summary>Product version, before CPE normalization.</summary>
    Version: string;
    /// <summary>Provenance links. Empty when no http(s) URL is known.</summary>
    References: TArray<TCpeReference>;
    /// <summary>CPE 2.3 formatted string for this proposal.</summary>
    function ProposedCpe23: string;
    /// <summary>CPE 2.2 URI for the cpe-item name attribute.</summary>
    function ProposedCpe22: string;
    /// <summary>Human-readable title. Empty parts are left out.</summary>
    function Title: string;
  end;

/// <summary>
/// Logical CPE attribute: trimmed, lower case, whitespace runs become one
/// underscore, and characters outside the CPE set become an underscore.
/// Empty when AValue has nothing left. Escaping is applied later.
/// </summary>
function NormalizeCpeAttribute(const AValue: string): string;

/// <summary>
/// Binds a logical attribute to a CPE 2.3 formatted-string value.
/// Empty becomes * (ANY). Special characters are backslash-escaped.
/// </summary>
function BindCpeFormattedValue(const ALogical: string): string;

/// <summary>
/// Binds a logical attribute to a CPE 2.2 URI value.
/// Empty stays empty (ANY). Special characters are percent-encoded.
/// </summary>
function BindCpeUriValue(const ALogical: string): string;

/// <summary>
/// cpe:2.3:a:vendor:product:version:*:*:*:*:*:*:* for an application.
/// Vendor, product and version are normalized and then bound.
/// </summary>
function FormatCpe23(const AVendor, AProduct, AVersion: string): string;

/// <summary>
/// cpe:/a:vendor:product:version. A version that normalizes to empty is
/// omitted, which is ANY in the URI binding.
/// </summary>
function FormatCpe22(const AVendor, AProduct, AVersion: string): string;

/// <summary>
/// Product and repository links for the submission. Blank values and
/// values that are not http or https are left out. A repeated URL is
/// kept once. The supplier URL is captioned Product. The repository URL
/// is captioned Repository.
/// </summary>
function CpeReferencesFromUrls(const ASupplierUrl, ARepoUrl: string): TArray<TCpeReference>;

/// <summary>
/// Keyword for an NVD CPE search of the configured vendor and product.
/// Empty parts are skipped. Both empty returns an empty string.
/// </summary>
function CpeLookupKeyword(const AVendor, AProduct: string): string;

/// <summary>
/// CPE Dictionary 2.3 document: cpe-item, title, provenance comments,
/// references and cpe-23:cpe23-item. The vendor and product are described
/// as a proposal in a comment.
/// </summary>
function BuildCpeDictionaryXml(const ASubmission: TCpeSubmission): string;

/// <summary>
/// Ready-to-copy message for cpe_dictionary@nist.gov. The text names the
/// address. It does not send the message.
/// </summary>
function BuildCpeMailText(const ASubmission: TCpeSubmission): string;

/// <summary>
/// Dictionary file next to an SBOM. bom.json becomes bom.cpe-dictionary.xml.
/// </summary>
function CpeDictionaryFileName(const ASbomPath: string): string;

/// <summary>
/// Mail text file next to an SBOM. bom.json becomes bom.cpe-mail.txt.
/// </summary>
function CpeMailFileName(const ASbomPath: string): string;

/// <summary>
/// Writes the dictionary XML and the mail text next to ASbomPath.
/// A relative SBOM path is resolved from AProjectPath when that file is
/// set, and from the current directory otherwise. Returns False with
/// AError when a file cannot be written. Does not send mail.
/// </summary>
function WriteCpeSubmissionFiles(const ASbomPath, AProjectPath: string;
  const ASubmission: TCpeSubmission; out ADictionaryPath, AMailPath,
  AError: string): Boolean;

/// <summary>
/// Fills empty Vendor, Product and Version from the project file.
/// Vendor uses CompanyName. Product uses the project name. Version uses
/// the project version. Values that are already set stay. A missing or
/// unreadable project leaves the record unchanged and does not raise.
/// </summary>
procedure FillEmptyCpeNamesFromProject(const AProjectPath, APlatform,
  AConfiguration: string; var ASubmission: TCpeSubmission);

implementation

uses
  System.Classes,
  System.IOUtils,
  DX.Comply.Engine.Intf,
  DX.Comply.ProjectScanner;

const
  cCpeSpecials = ['!', '"', '#', '$', '%', '&', '''', '(', ')', '*', '+', ',',
    '/', ':', ';', '<', '=', '>', '?', '@', '[', '\', ']', '^', '`', '{', '|',
    '}', '~'];

function IsCpeUnreserved(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['a'..'z', '0'..'9', '_', '.', '-']);
end;

function NormalizeCpeAttribute(const AValue: string): string;
var
  LSource: string;
  LChar: Char;
  LPendingBreak: Boolean;
  LLastWasUnderscore: Boolean;
  LBuilder: TStringBuilder;
begin
  LSource := LowerCase(Trim(AValue));
  LBuilder := TStringBuilder.Create;
  try
    LPendingBreak := False;
    LLastWasUnderscore := False;
    for LChar in LSource do
    begin
      if LChar <= ' ' then
      begin
        if LBuilder.Length > 0 then
          LPendingBreak := True;
        Continue;
      end;
      if LPendingBreak then
      begin
        LBuilder.Append('_');
        LPendingBreak := False;
        LLastWasUnderscore := True;
      end;
      if IsCpeUnreserved(LChar) or CharInSet(LChar, cCpeSpecials) then
      begin
        LBuilder.Append(LChar);
        LLastWasUnderscore := LChar = '_';
      end
      else if not LLastWasUnderscore then
      begin
        LBuilder.Append('_');
        LLastWasUnderscore := True;
      end;
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function BindCpeFormattedValue(const ALogical: string): string;
var
  LChar: Char;
  LBuilder: TStringBuilder;
begin
  if ALogical = '' then
    Exit('*');
  LBuilder := TStringBuilder.Create;
  try
    for LChar in ALogical do
    begin
      if CharInSet(LChar, cCpeSpecials) then
        LBuilder.Append('\');
      LBuilder.Append(LChar);
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function BindCpeUriValue(const ALogical: string): string;
var
  LChar: Char;
  LBuilder: TStringBuilder;
begin
  if ALogical = '' then
    Exit('');
  LBuilder := TStringBuilder.Create;
  try
    for LChar in ALogical do
    begin
      if CharInSet(LChar, cCpeSpecials) then
        LBuilder.Append('%').Append(LowerCase(IntToHex(Ord(LChar), 2)))
      else
        LBuilder.Append(LChar);
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function FormatCpe23(const AVendor, AProduct, AVersion: string): string;
begin
  Result := 'cpe:2.3:a:' +
    BindCpeFormattedValue(NormalizeCpeAttribute(AVendor)) + ':' +
    BindCpeFormattedValue(NormalizeCpeAttribute(AProduct)) + ':' +
    BindCpeFormattedValue(NormalizeCpeAttribute(AVersion)) +
    ':*:*:*:*:*:*:*';
end;

function FormatCpe22(const AVendor, AProduct, AVersion: string): string;
var
  LVersion: string;
begin
  Result := 'cpe:/a:' +
    BindCpeUriValue(NormalizeCpeAttribute(AVendor)) + ':' +
    BindCpeUriValue(NormalizeCpeAttribute(AProduct));
  LVersion := BindCpeUriValue(NormalizeCpeAttribute(AVersion));
  if LVersion <> '' then
    Result := Result + ':' + LVersion;
end;

function IsHttpUrl(const AValue: string): Boolean;
begin
  Result := AValue.StartsWith('http://', True) or AValue.StartsWith('https://', True);
end;

procedure AppendReference(var AReferences: TArray<TCpeReference>;
  const AHref, ACaption: string);
var
  I: Integer;
  LHref: string;
begin
  LHref := Trim(AHref);
  if (LHref = '') or not IsHttpUrl(LHref) then
    Exit;
  for I := 0 to High(AReferences) do
    if SameText(AReferences[I].Href, LHref) then
      Exit;
  SetLength(AReferences, Length(AReferences) + 1);
  AReferences[High(AReferences)].Href := LHref;
  AReferences[High(AReferences)].Caption := ACaption;
end;

function CpeReferencesFromUrls(const ASupplierUrl, ARepoUrl: string): TArray<TCpeReference>;
begin
  SetLength(Result, 0);
  AppendReference(Result, ASupplierUrl, 'Product');
  AppendReference(Result, ARepoUrl, 'Repository');
end;

function CpeLookupKeyword(const AVendor, AProduct: string): string;
var
  LVendor, LProduct: string;
begin
  LVendor := Trim(AVendor);
  LProduct := Trim(AProduct);
  if (LVendor <> '') and (LProduct <> '') then
    Result := LVendor + ' ' + LProduct
  else
    Result := LVendor + LProduct;
end;

function EscapeXml(const AValue: string): string;
begin
  Result := AValue;
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

function XmlComment(const AText: string): string;
var
  LText: string;
begin
  // A comment must not contain "--", and it must not end with "-".
  LText := StringReplace(AText, '--', '- -', [rfReplaceAll]);
  if (LText <> '') and (LText[Length(LText)] = '-') then
    LText := LText + ' ';
  Result := '<!-- ' + LText + ' -->';
end;

function JoinTitle(const AParts: array of string): string;
var
  LPart: string;
begin
  Result := '';
  for LPart in AParts do
  begin
    if Trim(LPart) = '' then
      Continue;
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Trim(LPart);
  end;
end;

function TCpeSubmission.ProposedCpe23: string;
begin
  Result := FormatCpe23(Vendor, Product, Version);
end;

function TCpeSubmission.ProposedCpe22: string;
begin
  Result := FormatCpe22(Vendor, Product, Version);
end;

function TCpeSubmission.Title: string;
begin
  Result := JoinTitle([Vendor, Product, Version]);
end;

function BuildCpeDictionaryXml(const ASubmission: TCpeSubmission): string;
var
  LLines: TStringList;
  LReference: TCpeReference;
  LTitle: string;
begin
  LTitle := ASubmission.Title;
  if LTitle = '' then
    LTitle := 'Untitled product';
  LLines := TStringList.Create;
  try
    LLines.WriteBOM := False;
    LLines.Add('<?xml version="1.0" encoding="UTF-8"?>');
    LLines.Add('<cpe-list xmlns="http://cpe.mitre.org/dictionary/2.0" ' +
      'xmlns:cpe-23="http://scap.nist.gov/schema/cpe-extension/2.3" ' +
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
      'xsi:schemaLocation="http://cpe.mitre.org/dictionary/2.0 ' +
      'https://scap.nist.gov/schema/cpe/2.3/cpe-dictionary_2.3.xsd ' +
      'http://scap.nist.gov/schema/cpe-extension/2.3 ' +
      'https://scap.nist.gov/schema/cpe/2.3/cpe-dictionary-extension_2.3.xsd">');
    LLines.Add('  <cpe-item name="' + EscapeXml(ASubmission.ProposedCpe22) + '">');
    LLines.Add('    ' + XmlComment(
      'The vendor and product strings are a proposal. NIST may normalize them.'));
    LLines.Add('    <title xml:lang="en-US">' + EscapeXml(LTitle) + '</title>');
    for LReference in ASubmission.References do
      LLines.Add('    ' + XmlComment('Provenance: ' + LReference.Href));
    if Length(ASubmission.References) > 0 then
    begin
      LLines.Add('    <references>');
      for LReference in ASubmission.References do
        LLines.Add('      <reference href="' + EscapeXml(LReference.Href) + '">' +
          EscapeXml(LReference.Caption) + '</reference>');
      LLines.Add('    </references>');
    end;
    LLines.Add('    <cpe-23:cpe23-item name="' +
      EscapeXml(ASubmission.ProposedCpe23) + '"/>');
    LLines.Add('  </cpe-item>');
    LLines.Add('</cpe-list>');
    Result := LLines.Text;
  finally
    LLines.Free;
  end;
end;

function BuildCpeMailText(const ASubmission: TCpeSubmission): string;
var
  LLines: TStringList;
  LReference: TCpeReference;
  LTitle: string;
begin
  LTitle := ASubmission.Title;
  if LTitle = '' then
    LTitle := 'Untitled product';
  LLines := TStringList.Create;
  try
    LLines.WriteBOM := False;
    LLines.Add('To: ' + cCpeDictionaryMailAddress);
    LLines.Add('Subject: CPE dictionary submission for ' + LTitle);
    LLines.Add('');
    LLines.Add('Please add the CPE name in the attached dictionary file.');
    LLines.Add('');
    LLines.Add('Proposed CPE: ' + ASubmission.ProposedCpe23);
    LLines.Add('Vendor: ' + Trim(ASubmission.Vendor));
    LLines.Add('Product: ' + Trim(ASubmission.Product));
    LLines.Add('Version: ' + Trim(ASubmission.Version));
    LLines.Add('');
    LLines.Add('The vendor and product strings are a proposal. NIST may normalize them.');
    LLines.Add('');
    LLines.Add('Provenance:');
    if Length(ASubmission.References) = 0 then
      LLines.Add('(none)');
    for LReference in ASubmission.References do
      LLines.Add(LReference.Href);
    LLines.Add('');
    LLines.Add('DX.Comply prepared this text and the attached XML file. It does not send the message.');
    Result := LLines.Text;
  finally
    LLines.Free;
  end;
end;

function CpeDictionaryFileName(const ASbomPath: string): string;
begin
  Result := TPath.ChangeExtension(ASbomPath, '.cpe-dictionary.xml');
end;

function CpeMailFileName(const ASbomPath: string): string;
begin
  Result := TPath.ChangeExtension(ASbomPath, '.cpe-mail.txt');
end;

function ResolveSbomPath(const ASbomPath, AProjectPath: string): string;
begin
  Result := Trim(ASbomPath);
  if Result = '' then
    Result := 'bom.json';
  if TPath.IsRelativePath(Result) then
  begin
    if Trim(AProjectPath) <> '' then
      Result := TPath.Combine(TPath.GetDirectoryName(TPath.GetFullPath(AProjectPath)), Result)
    else
      Result := TPath.Combine(GetCurrentDir, Result);
  end;
end;

function WriteUtf8File(const APath, AText: string; out AError: string): Boolean;
var
  LEncoding: TUTF8Encoding;
  LDirectory: string;
begin
  AError := '';
  try
    LDirectory := TPath.GetDirectoryName(APath);
    if (LDirectory <> '') and not TDirectory.Exists(LDirectory) then
      TDirectory.CreateDirectory(LDirectory);
    LEncoding := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(APath, AText, LEncoding);
    finally
      LEncoding.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function WriteCpeSubmissionFiles(const ASbomPath, AProjectPath: string;
  const ASubmission: TCpeSubmission; out ADictionaryPath, AMailPath,
  AError: string): Boolean;
var
  LSbomPath: string;
begin
  ADictionaryPath := '';
  AMailPath := '';
  AError := '';
  LSbomPath := ResolveSbomPath(ASbomPath, AProjectPath);
  ADictionaryPath := CpeDictionaryFileName(LSbomPath);
  AMailPath := CpeMailFileName(LSbomPath);
  if not WriteUtf8File(ADictionaryPath, BuildCpeDictionaryXml(ASubmission), AError) then
    Exit(False);
  if not WriteUtf8File(AMailPath, BuildCpeMailText(ASubmission), AError) then
    Exit(False);
  Result := True;
end;

procedure FillEmptyCpeNamesFromProject(const AProjectPath, APlatform,
  AConfiguration: string; var ASubmission: TCpeSubmission);
var
  LScanner: IProjectScanner;
  LInfo: TProjectInfo;
  LPlatform, LConfiguration: string;
begin
  if Trim(AProjectPath) = '' then
    Exit;
  if (Trim(ASubmission.Vendor) <> '') and (Trim(ASubmission.Product) <> '') and
     (Trim(ASubmission.Version) <> '') then
    Exit;
  LPlatform := Trim(APlatform);
  if LPlatform = '' then
    LPlatform := 'Win32';
  LConfiguration := Trim(AConfiguration);
  if LConfiguration = '' then
    LConfiguration := 'Release';
  // Held as an interface, as the engine does. The scanner is reference
  // counted, so it must not be freed through an object reference.
  try
    LScanner := TProjectScanner.Create;
    LInfo := LScanner.Scan(AProjectPath, LPlatform, LConfiguration);
    try
      if Trim(ASubmission.Vendor) = '' then
        ASubmission.Vendor := Trim(LInfo.CompanyName);
      if Trim(ASubmission.Product) = '' then
        ASubmission.Product := Trim(LInfo.ProjectName);
      if Trim(ASubmission.Version) = '' then
        ASubmission.Version := Trim(LInfo.Version);
    finally
      LInfo.Free;
    end;
  except
    on Exception do
      ;
  end;
end;

end.
