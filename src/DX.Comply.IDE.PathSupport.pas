/// <summary>
/// DX.Comply.IDE.PathSupport
/// Shared repository and asset path helpers for the DX.Comply IDE package.
/// </summary>
///
/// <remarks>
/// These helpers centralize the logic that locates the repository root relative
/// to the loaded design package so dialogs, menu assets, and documentation views
/// stay aligned and avoid duplicating path traversal logic.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.PathSupport;

interface

function GetDXComplyModuleFilePath: string;
function FindDXComplyRepositoryFile(const ARelativePath: string): string;
function FindDXComplyAssetFile(const AFileName: string): string;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows;

function GetDXComplyModuleFilePath: string;
var
  LLength: Integer;
begin
  SetLength(Result, 1024);
  LLength := GetModuleFileName(HInstance, PChar(Result), Length(Result));
  if LLength <= 0 then
    Exit('');
  SetLength(Result, LLength);
end;

function FindDXComplyRepositoryRoot: string;
var
  LCurrentDirectory: string;
  LParentDirectory: string;
begin
  Result := '';
  LCurrentDirectory := ExtractFileDir(GetDXComplyModuleFilePath);
  while LCurrentDirectory <> '' do
  begin
    if TFile.Exists(TPath.Combine(LCurrentDirectory, 'README.md')) and
      TDirectory.Exists(TPath.Combine(LCurrentDirectory, 'src')) then
      Exit(LCurrentDirectory);

    LParentDirectory := ExtractFileDir(LCurrentDirectory);
    if SameText(LParentDirectory, LCurrentDirectory) then
      Break;
    LCurrentDirectory := LParentDirectory;
  end;
end;

function FindDXComplyRepositoryFile(const ARelativePath: string): string;
var
  LRepositoryRoot: string;
begin
  Result := '';
  LRepositoryRoot := FindDXComplyRepositoryRoot;
  if LRepositoryRoot = '' then
    Exit;

  Result := TPath.Combine(LRepositoryRoot, ARelativePath);
  if not TFile.Exists(Result) then
    Result := '';
end;

function FindDXComplyAssetFile(const AFileName: string): string;
begin
  Result := FindDXComplyRepositoryFile(TPath.Combine('assets', AFileName));
end;

end.