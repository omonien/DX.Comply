/// <summary>
/// DX.Comply.CycloneDx.XmlWriter
/// Generates CycloneDX 1.5 SBOM documents in XML format.
/// </summary>
///
/// <remarks>
/// This unit provides TCycloneDxXmlWriter which generates CycloneDX 1.5 XML SBOMs:
/// - Full metadata section with tool information
/// - Component list with hashes (SHA-256)
/// - Basic dependency graph
/// - Schema validation support
///
/// The XML output conforms to the CycloneDX 1.5 XSD schema:
/// https://cyclonedx.org/schema/bom-1.5.xsd
///
/// Uses lightweight string-based XML generation to avoid MSXML/COM dependencies,
/// ensuring the writer works in all environments (IDE, CLI, test runners).
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.CycloneDx.XmlWriter;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.DateUtils,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Implementation of ISbomWriter for CycloneDX XML format.
  /// </summary>
  TCycloneDxXmlWriter = class(TInterfacedObject, ISbomWriter)
  private
    const
      cSpecVersion = '1.5';
      cNamespace = 'http://cyclonedx.org/schema/bom/1.5';
      cToolName = 'DX.Comply';
      cToolVersion = '1.0.0';
      cIndent = '  ';
  private
    FLines: TStringList;
    FIndentLevel: Integer;
    function GenerateUuid: string;
    function EscapeXml(const AValue: string): string;
    procedure AddLine(const ALine: string);
    procedure OpenTag(const ATag: string; const AAttributes: string = '');
    procedure CloseTag(const ATag: string);
    procedure AddElement(const ATag, AValue: string);
    procedure AddPropertyElements(const AProperties: TArray<TSbomProperty>);
    procedure BuildMetadata(const AMetadata: TSbomMetadata; const AProjectInfo: TProjectInfo);
    procedure BuildComponent(const AArtefact: TArtefactInfo; const AIndex: Integer);
    procedure BuildComponents(const AArtefacts: TArtefactList);
    procedure BuildDependencies(const AArtefacts: TArtefactList; const AProjectBomRef: string);
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
  System.RegularExpressions;

{ TCycloneDxXmlWriter }

function TCycloneDxXmlWriter.GenerateUuid: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := GUIDToString(LGuid);
  Result := Result.Substring(1, Result.Length - 2);
end;

function TCycloneDxXmlWriter.EscapeXml(const AValue: string): string;
begin
  Result := AValue;
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

procedure TCycloneDxXmlWriter.AddLine(const ALine: string);
var
  LPrefix: string;
  I: Integer;
begin
  LPrefix := '';
  for I := 1 to FIndentLevel do
    LPrefix := LPrefix + cIndent;
  FLines.Add(LPrefix + ALine);
end;

procedure TCycloneDxXmlWriter.OpenTag(const ATag: string; const AAttributes: string);
begin
  if AAttributes <> '' then
    AddLine('<' + ATag + ' ' + AAttributes + '>')
  else
    AddLine('<' + ATag + '>');
  Inc(FIndentLevel);
end;

procedure TCycloneDxXmlWriter.CloseTag(const ATag: string);
begin
  Dec(FIndentLevel);
  AddLine('</' + ATag + '>');
end;

procedure TCycloneDxXmlWriter.AddElement(const ATag, AValue: string);
begin
  AddLine('<' + ATag + '>' + EscapeXml(AValue) + '</' + ATag + '>');
end;

procedure TCycloneDxXmlWriter.AddPropertyElements(
  const AProperties: TArray<TSbomProperty>);
var
  LHasProperties: Boolean;
  LProperty: TSbomProperty;
begin
  LHasProperties := False;
  for LProperty in AProperties do
  begin
    if Trim(LProperty.Name) = '' then
      Continue;

    if not LHasProperties then
    begin
      OpenTag('properties');
      LHasProperties := True;
    end;

    AddLine('<property name="' + EscapeXml(LProperty.Name) + '">' +
      EscapeXml(LProperty.Value) + '</property>');
  end;

  if LHasProperties then
    CloseTag('properties');
end;

procedure TCycloneDxXmlWriter.BuildMetadata(const AMetadata: TSbomMetadata;
  const AProjectInfo: TProjectInfo);
begin
  OpenTag('metadata');

  if AMetadata.Timestamp <> '' then
    AddElement('timestamp', AMetadata.Timestamp)
  else
    AddElement('timestamp', DateToISO8601(Now, False));

  AddPropertyElements(AMetadata.Properties);

  // CycloneDX 1.5 XML uses <tools><tool> (not <tools><components>)
  OpenTag('tools');
  OpenTag('tool');
  AddElement('vendor', 'Olaf Monien');
  AddElement('name', cToolName);
  AddElement('version', cToolVersion);
  CloseTag('tool');
  CloseTag('tools');

  // Component (the project being documented)
  OpenTag('component', 'type="application" bom-ref="' +
    EscapeXml(AProjectInfo.ProjectName) + '"');
  AddElement('name', AProjectInfo.ProjectName);
  if AProjectInfo.Version <> '' then
    AddElement('version', AProjectInfo.Version);
  if AMetadata.Supplier <> '' then
  begin
    OpenTag('supplier');
    AddElement('name', AMetadata.Supplier);
    CloseTag('supplier');
  end;
  AddPropertyElements(AMetadata.ComponentProperties);
  CloseTag('component');

  CloseTag('metadata');
end;

procedure TCycloneDxXmlWriter.BuildComponent(const AArtefact: TArtefactInfo;
  const AIndex: Integer);
var
  LComponentType: string;
  LBomRef: string;
begin
  if AArtefact.ArtefactType = 'application' then
    LComponentType := 'application'
  else if (AArtefact.ArtefactType = 'library') or (AArtefact.ArtefactType = 'unit-evidence') or (AArtefact.ArtefactType = 'package') then
    LComponentType := 'library'
  else
    LComponentType := 'file';

  LBomRef := 'comp-' + IntToStr(AIndex);

  OpenTag('component', 'type="' + LComponentType + '" bom-ref="' + EscapeXml(LBomRef) + '"');

  AddElement('name', TPath.GetFileName(AArtefact.RelativePath));

  if AArtefact.Hash <> '' then
    AddElement('version', Copy(AArtefact.Hash, 1, 12));

  AddElement('purl', 'file:' + AArtefact.RelativePath);

  if AArtefact.Hash <> '' then
  begin
    OpenTag('hashes');
    OpenTag('hash', 'alg="SHA-256"');
    // Hash content goes directly without a sub-element
    Dec(FIndentLevel);
    // Replace last line with inline content
    FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
      '<hash alg="SHA-256">' + LowerCase(AArtefact.Hash) + '</hash>';
    CloseTag('hashes');
  end;

  if (AArtefact.FileSize >= 0) or (Trim(AArtefact.Origin) <> '') then
  begin
    OpenTag('properties');
    if AArtefact.FileSize >= 0 then
    begin
      OpenTag('property', 'name="file:size"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="file:size">' + IntToStr(AArtefact.FileSize) + '</property>';
    end;
    if Trim(AArtefact.Origin) <> '' then
    begin
      OpenTag('property', 'name="net.developer-experts.dx-comply:origin"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="net.developer-experts.dx-comply:origin">' + EscapeXml(AArtefact.Origin) + '</property>';
    end;
    if Trim(AArtefact.Evidence) <> '' then
    begin
      OpenTag('property', 'name="net.developer-experts.dx-comply:evidence"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="net.developer-experts.dx-comply:evidence">' + EscapeXml(AArtefact.Evidence) + '</property>';
    end;
    if Trim(AArtefact.Confidence) <> '' then
    begin
      OpenTag('property', 'name="net.developer-experts.dx-comply:confidence"');
      Dec(FIndentLevel);
      FLines[FLines.Count - 1] := StringOfChar(' ', FIndentLevel * 2) +
        '<property name="net.developer-experts.dx-comply:confidence">' + EscapeXml(AArtefact.Confidence) + '</property>';
    end;
    CloseTag('properties');
  end;

  CloseTag('component');
end;

procedure TCycloneDxXmlWriter.BuildComponents(const AArtefacts: TArtefactList);
var
  I: Integer;
begin
  OpenTag('components');
  for I := 0 to AArtefacts.Count - 1 do
    BuildComponent(AArtefacts[I], I);
  CloseTag('components');
end;

procedure TCycloneDxXmlWriter.BuildDependencies(const AArtefacts: TArtefactList;
  const AProjectBomRef: string);
var
  I: Integer;
begin
  OpenTag('dependencies');
  OpenTag('dependency', 'ref="' + EscapeXml(AProjectBomRef) + '"');
  for I := 0 to AArtefacts.Count - 1 do
    AddLine('<dependency ref="comp-' + IntToStr(I) + '"/>');
  CloseTag('dependency');
  CloseTag('dependencies');
end;

function TCycloneDxXmlWriter.Write(const AOutputPath: string;
  const AMetadata: TSbomMetadata;
  const AArtefacts: TArtefactList;
  const AProjectInfo: TProjectInfo): Boolean;
var
  LOutputDir: string;
begin
  Result := False;
  if AOutputPath = '' then
    Exit;

  LOutputDir := TPath.GetDirectoryName(AOutputPath);
  if (LOutputDir <> '') and not TDirectory.Exists(LOutputDir) then
    TDirectory.CreateDirectory(LOutputDir);

  FLines := TStringList.Create;
  try
    FIndentLevel := 0;

    // XML declaration
    FLines.Add('<?xml version="1.0" encoding="UTF-8"?>');

    // Root element with namespace and serial number
    OpenTag('bom', 'xmlns="' + cNamespace + '" version="1" serialNumber="urn:uuid:' +
      GenerateUuid + '"');

    BuildMetadata(AMetadata, AProjectInfo);
    BuildComponents(AArtefacts);
    BuildDependencies(AArtefacts, AProjectInfo.ProjectName);

    CloseTag('bom');

    FLines.WriteBOM := False;
    FLines.SaveToFile(AOutputPath, TEncoding.UTF8);
    Result := True;
  finally
    FLines.Free;
    FLines := nil;
  end;
end;

function TCycloneDxXmlWriter.GetFormat: TSbomFormat;
begin
  Result := sfCycloneDxXml;
end;

function TCycloneDxXmlWriter.Validate(const AContent: string): Boolean;
var
  LMatch: TMatch;
begin
  Result := False;
  if Trim(AContent) = '' then
    Exit;

  // Check for XML declaration
  if not AContent.StartsWith('<?xml') then
    Exit;

  // Check for CycloneDX namespace
  if Pos(cNamespace, AContent) = 0 then
    Exit;

  // Check for <bom element
  if Pos('<bom', AContent) = 0 then
    Exit;

  // Check for serialNumber with urn:uuid:
  LMatch := TRegEx.Match(AContent, 'serialNumber="urn:uuid:[^"]+?"', [roIgnoreCase]);
  if not LMatch.Success then
    Exit;

  // Check for components section
  if Pos('<components', AContent) = 0 then
    Exit;

  // Check for metadata section
  if Pos('<metadata', AContent) = 0 then
    Exit;

  Result := True;
end;

end.
