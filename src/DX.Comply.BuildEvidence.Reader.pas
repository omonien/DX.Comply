/// <summary>
/// DX.Comply.BuildEvidence.Reader
/// First-pass implementation of normalized build evidence collection.
/// </summary>
///
/// <remarks>
/// This reader does not yet inspect compiler response files, map files, or
/// package containers. Its job in the first implementation slice is to convert
/// already-resolved project metadata into a stable internal build evidence
/// representation that later resolver stages can consume.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.BuildEvidence.Reader;

interface

uses
  System.Generics.Collections,
  System.IOUtils,
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.MapFile.Reader;

type
  /// <summary>
  /// Implementation of IBuildEvidenceReader for the first evidence slice.
  /// </summary>
  TBuildEvidenceReader = class(TInterfacedObject, IBuildEvidenceReader)
  private
    /// <summary>
    /// Copies string list values into the target list without duplicates.
    /// </summary>
    procedure CopyUniqueValues(const ASource, ATarget: TList<string>);
    /// <summary>
    /// Adds a normalized evidence item.
    /// </summary>
    procedure AddEvidenceItem(var ABuildEvidence: TBuildEvidence;
      ASourceKind: TBuildEvidenceSourceKind; const ADisplayName, AFilePath,
      APackageName, AUnitName, ADetail: string);
  public
    /// <summary>
    /// Reads normalized build evidence from the supplied project metadata.
    /// </summary>
    function Read(const AProjectInfo: TProjectInfo): TBuildEvidence;
  end;

implementation

uses
  System.SysUtils;

procedure TBuildEvidenceReader.AddEvidenceItem(var ABuildEvidence: TBuildEvidence;
  ASourceKind: TBuildEvidenceSourceKind; const ADisplayName, AFilePath,
  APackageName, AUnitName, ADetail: string);
var
  LEvidenceItem: TBuildEvidenceItem;
begin
  LEvidenceItem := Default(TBuildEvidenceItem);
  LEvidenceItem.SourceKind := ASourceKind;
  LEvidenceItem.DisplayName := ADisplayName;
  LEvidenceItem.FilePath := AFilePath;
  LEvidenceItem.PackageName := APackageName;
  LEvidenceItem.UnitName := AUnitName;
  LEvidenceItem.Detail := ADetail;
  ABuildEvidence.EvidenceItems.Add(LEvidenceItem);
end;

procedure TBuildEvidenceReader.CopyUniqueValues(const ASource, ATarget: TList<string>);
var
  LValue: string;
begin
  if not Assigned(ASource) or not Assigned(ATarget) then
    Exit;

  for LValue in ASource do
  begin
    if not ATarget.Contains(LValue) then
      ATarget.Add(LValue);
  end;
end;

function TBuildEvidenceReader.Read(const AProjectInfo: TProjectInfo): TBuildEvidence;
var
  LMapUnitName: string;
  LMapUnitNames: TArray<string>;
  LRsmFilePath: string;
  LRuntimePackage: string;
begin
  Result := TBuildEvidence.Create;
  Result.ProjectPath := AProjectInfo.ProjectPath;
  Result.Platform := AProjectInfo.Platform;
  Result.Configuration := AProjectInfo.Configuration;
  Result.Paths.OutputDir := AProjectInfo.OutputDir;
  Result.Paths.DcuOutputDir := AProjectInfo.DcuOutputDir;
  Result.Paths.DcpOutputDir := AProjectInfo.DcpOutputDir;
  Result.Paths.BplOutputDir := AProjectInfo.BplOutputDir;
  Result.Paths.MapFilePath := AProjectInfo.MapFilePath;

  CopyUniqueValues(AProjectInfo.SearchPaths, Result.SearchPaths);
  CopyUniqueValues(AProjectInfo.UnitScopeNames, Result.UnitScopeNames);
  CopyUniqueValues(AProjectInfo.RuntimePackages, Result.RuntimePackages);
  CopyUniqueValues(AProjectInfo.Warnings, Result.Warnings);

  AddEvidenceItem(Result, besProjectMetadata, 'Project metadata',
    AProjectInfo.ProjectPath, '', '',
    Format('%s|%s', [AProjectInfo.Platform, AProjectInfo.Configuration]));

  if AProjectInfo.OutputDir <> '' then
    AddEvidenceItem(Result, besProjectMetadata, 'Primary output directory',
      AProjectInfo.OutputDir, '', '', 'OutputDir');

  if AProjectInfo.DcuOutputDir <> '' then
    AddEvidenceItem(Result, besProjectMetadata, 'DCU output directory',
      AProjectInfo.DcuOutputDir, '', '', 'DcuOutputDir');

  if AProjectInfo.DcpOutputDir <> '' then
    AddEvidenceItem(Result, besProjectMetadata, 'DCP output directory',
      AProjectInfo.DcpOutputDir, '', '', 'DcpOutputDir');

  if AProjectInfo.BplOutputDir <> '' then
    AddEvidenceItem(Result, besProjectMetadata, 'BPL output directory',
      AProjectInfo.BplOutputDir, '', '', 'BplOutputDir');

  if AProjectInfo.MapFilePath <> '' then
  begin
    AddEvidenceItem(Result, besProjectMetadata, 'Expected map file',
      AProjectInfo.MapFilePath, '', '', 'MapFilePath');

    if TFile.Exists(AProjectInfo.MapFilePath) then
    begin
      AddEvidenceItem(Result, besMapFile, 'Detailed map file',
        AProjectInfo.MapFilePath, '', '', 'MapFile');

      LMapUnitNames := TMapFileReader.ReadUnitNames(AProjectInfo.MapFilePath);
      for LMapUnitName in LMapUnitNames do
        AddEvidenceItem(Result, besMapFile, 'Unit from map file',
          AProjectInfo.MapFilePath, '', LMapUnitName, 'LineNumbersSection');
    end;

    if not TFile.Exists(AProjectInfo.MapFilePath) then
    begin
      Result.Warnings.Add('No detailed MAP file found: ' + AProjectInfo.MapFilePath);

      LRsmFilePath := ChangeFileExt(AProjectInfo.MapFilePath, '.rsm');
      if TFile.Exists(LRsmFilePath) then
        Result.Warnings.Add('Found RSM file without matching MAP file: ' + LRsmFilePath +
          '. Deep-Evidence unit resolution currently requires a detailed MAP file.');
    end;
  end;

  for LRuntimePackage in Result.RuntimePackages do
    AddEvidenceItem(Result, besProjectMetadata, 'Runtime package', '',
      LRuntimePackage, '', 'RuntimePackages');
end;

end.