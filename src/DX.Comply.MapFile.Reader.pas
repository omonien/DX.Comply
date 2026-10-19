/// <summary>
/// DX.Comply.MapFile.Reader
/// Reads unit membership evidence from a detailed Delphi map file.
/// </summary>
///
/// <remarks>
/// The first implementation slice focuses on the most reliable signal in a
/// detailed Delphi map file: "Line numbers for <Unit>(<File>) ..." sections.
/// These entries prove that code from a unit participated in the linked result.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.MapFile.Reader;

interface

type
  /// <summary>
  /// Reads unit names from a detailed Delphi map file.
  /// </summary>
  TMapFileReader = class
  private
    /// <summary>
    /// Tries to extract a unit name from a "Line numbers for" section header.
    /// </summary>
    class function TryExtractLineNumbersUnitName(const ALine: string; out AUnitName: string): Boolean; static;
    /// <summary>
    /// Tries to extract a unit name from a "Detailed map of segments" entry (M=UnitName).
    /// </summary>
    class function TryExtractSegmentUnitName(const ALine: string; out AUnitName: string): Boolean; static;
  public
    /// <summary>
    /// Reads unique unit names from the specified detailed map file.
    /// </summary>
    class function ReadUnitNames(const AMapFilePath: string): TArray<string>; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.RegularExpressions,
  System.SysUtils;

/// <summary>
/// Adds a unit name to AUnitNames only once, case-insensitively. ASeen holds
/// the names added so far, so each call is O(1) instead of a scan of the list.
/// The first spelling and the order of first appearance are kept.
/// </summary>
procedure AddUniqueUnitName(const AUnitName: string;
  const ASeen: TDictionary<string, Boolean>; const AUnitNames: TList<string>);
begin
  if Trim(AUnitName) = '' then
    Exit;

  if ASeen.ContainsKey(AUnitName) then
    Exit;

  ASeen.Add(AUnitName, True);
  AUnitNames.Add(AUnitName);
end;

class function TMapFileReader.ReadUnitNames(const AMapFilePath: string): TArray<string>;
var
  LLine: string;
  LLines: TStringList;
  LUnitName: string;
begin
  Result := nil;
  if not TFile.Exists(AMapFilePath) then
    Exit;

  var LSeen := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  var LUnitNames := TList<string>.Create;
  LLines := TStringList.Create;
  try
    LLines.LoadFromFile(AMapFilePath);
    for LLine in LLines do
    begin
      if TryExtractLineNumbersUnitName(LLine, LUnitName) then
      begin
        AddUniqueUnitName(LUnitName, LSeen, LUnitNames);
      end
      else if TryExtractSegmentUnitName(LLine, LUnitName) then
      begin
        AddUniqueUnitName(LUnitName, LSeen, LUnitNames);
      end;
    end;
    Result := LUnitNames.ToArray;
  finally
    LLines.Free;
    LUnitNames.Free;
    LSeen.Free;
  end;
end;

class function TMapFileReader.TryExtractLineNumbersUnitName(const ALine: string;
  out AUnitName: string): Boolean;
var
  LMatch: TMatch;
begin
  AUnitName := '';
  LMatch := TRegEx.Match(ALine,
    '^\s*Line numbers for\s+([A-Za-z0-9_\.]+)\s*\(', [roIgnoreCase]);
  Result := LMatch.Success;
  if Result then
    AUnitName := Trim(LMatch.Groups[1].Value);
end;

class function TMapFileReader.TryExtractSegmentUnitName(const ALine: string;
  out AUnitName: string): Boolean;
var
  LMatch: TMatch;
begin
  AUnitName := '';
  LMatch := TRegEx.Match(ALine,
    '\bM=([A-Za-z0-9_\.]+)\b');
  Result := LMatch.Success;
  if Result then
    AUnitName := Trim(LMatch.Groups[1].Value);
end;

end.