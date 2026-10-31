/// <summary>
/// DX.Comply.MapFile.Reader
/// Reads unit membership evidence from a detailed Delphi map file.
/// </summary>
///
/// <remarks>
/// The first implementation slice focuses on the most reliable signal in a
/// detailed Delphi map file: "Line numbers for <Unit>(<File>) ..." sections.
/// These entries prove that code from a unit participated in the linked result.
/// An ARM or LLVM map (libProject.so.map and the Linux linker map) is not
/// parsed here. When those sections are absent the caller reports that the
/// format is unknown. No other pattern is guessed.
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

const
  /// <summary>"Line numbers for &lt;Unit&gt;(&lt;File&gt;) ..." section header.</summary>
  cLineNumbersPattern = '^\s*Line numbers for\s+([A-Za-z0-9_\.]+)\s*\(';
  /// <summary>"Detailed map of segments" entry (M=UnitName).</summary>
  cSegmentPattern = '\bM=([A-Za-z0-9_\.]+)\b';

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

/// <summary>
/// Tries to extract a unit name with ARegEx, whose first group captures it.
/// </summary>
/// <param name="ARegEx">cLineNumbersPattern or cSegmentPattern, compiled once by
/// ReadUnitNames.</param>
function TryExtractUnitName(const ARegEx: TRegEx; const ALine: string;
  out AUnitName: string): Boolean;
var
  LMatch: TMatch;
begin
  AUnitName := '';
  LMatch := ARegEx.Match(ALine);
  Result := LMatch.Success;

  if Result then
  begin
    AUnitName := Trim(LMatch.Groups[1].Value);
  end;
end;

class function TMapFileReader.ReadUnitNames(const AMapFilePath: string): TArray<string>;
var
  LLine: string;
  LLineNumbersRegEx: TRegEx;
  LLines: TStringList;
  LSegmentRegEx: TRegEx;
  LUnitName: string;
begin
  Result := nil;
  if not TFile.Exists(AMapFilePath) then
    Exit;

  // Compiled once per file. The class function TRegEx.Match compiles its
  // pattern on every call, which made large map files take minutes.
  LLineNumbersRegEx := TRegEx.Create(cLineNumbersPattern, [roIgnoreCase, roCompiled]);
  LSegmentRegEx := TRegEx.Create(cSegmentPattern, [roCompiled]);

  var LSeen := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  var LUnitNames := TList<string>.Create;
  LLines := TStringList.Create;
  try
    LLines.LoadFromFile(AMapFilePath);
    for LLine in LLines do
    begin
      if TryExtractUnitName(LLineNumbersRegEx, LLine, LUnitName) or
        TryExtractUnitName(LSegmentRegEx, LLine, LUnitName) then
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

end.