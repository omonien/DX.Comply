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
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf;

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

  for LRuntimePackage in Result.RuntimePackages do
    AddEvidenceItem(Result, besProjectMetadata, 'Runtime package', '',
      LRuntimePackage, '', 'RuntimePackages');
end;

end.