/// <summary>
/// DX.Comply.MapFile.LldReader
/// Reads unit and native component evidence from an ARM/LLVM linker map.
/// </summary>
///
/// <remarks>
/// Delphi's ARM and LLVM targets (Android, iOS, Linux, macOS ARM) link with
/// LLD. Its map starts with the header "VMA LMA Size Align Out In Symbol" and
/// lists one input section per line:
///   VMA LMA Size Align  path\Unit.o:(.text.Symbol)
///   VMA LMA Size Align  path/libfoo.a(member.o):(.text.Symbol)
/// Paths are written with doubled backslashes. A plain object file is a
/// Delphi unit, named after the .o file. An archive member is a native
/// component, named after the archive. Linker-internal sections and NDK
/// objects (crtbegin_so.o and the like) are skipped. The file is streamed line
/// by line because a real map is tens of megabytes.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.MapFile.LldReader;

interface

uses
  System.SysUtils;

type
  /// <summary>
  /// What an LLD map contributes: unit names and native archive names.
  /// </summary>
  TLldMapContents = record
    /// <summary>True when the file starts with the LLD map header.</summary>
    IsLldMap: Boolean;
    /// <summary>Unique unit names in order of first appearance.</summary>
    UnitNames: TArray<string>;
    /// <summary>Unique archive file names (libfoo.a) in order of first appearance.</summary>
    NativeComponents: TArray<string>;
  end;

  /// <summary>
  /// Reads an ARM/LLVM (LLD) linker map.
  /// </summary>
  TLldMapReader = class
  private
    class function ReadWithEncoding(const AMapFilePath: string;
      AEncoding: TEncoding): TLldMapContents; static;
  public
    /// <summary>
    /// True when ALine is the LLD map header "VMA LMA Size Align Out In Symbol".
    /// </summary>
    class function IsHeaderLine(const ALine: string): Boolean; static;
    /// <summary>
    /// Parses one input-section line. Returns True for a Delphi unit (AUnitName
    /// set) or an archive member (AArchiveName set). Linker-internal sections,
    /// NDK objects and every other line return False.
    /// </summary>
    class function TryParseInputLine(const ALine: string; out AUnitName,
      AArchiveName: string): Boolean; static;
    /// <summary>
    /// Streams AMapFilePath and returns its units and native components.
    /// IsLldMap is False, and nothing is read, when the header is missing.
    /// The file is read as UTF-8. A file with bytes that are not UTF-8, such
    /// as a Windows map in the ANSI code page, is read again in the ANSI code
    /// page instead of raising an encoding error.
    /// </summary>
    class function Read(const AMapFilePath: string): TLldMapContents; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.RegularExpressions,
  System.StrUtils;

const
  /// <summary>Input section of an object file: VMA, LMA, Size, Align, path.o:(section).</summary>
  cInputLinePattern = '^\s*[0-9a-f]+\s+[0-9a-f]+\s+[0-9a-f]+\s+\d+\s+(.+?)\.o:\(([^)]*)\)\s*$';
  /// <summary>Input section of an archive member: path\lib.a(member.o):(section).</summary>
  cArchiveLinePattern =
    '^\s*[0-9a-f]+\s+[0-9a-f]+\s+[0-9a-f]+\s+\d+\s+(.+?\.a)\(([^()]+)\.o\):\(([^)]*)\)\s*$';
  /// <summary>The header must appear within this many leading lines.</summary>
  cHeaderSearchLines = 20;
  /// <summary>Cheap tests before a regular expression runs.</summary>
  cInputLineMarker = '.o:(';
  cArchiveLineMarker = '.o):(';

var
  // Compiled once in the initialization section. TRegEx.Match as a class
  // function compiles its pattern on every call, which is far too slow for a
  // map with a million lines.
  GInputLineRegEx: TRegEx;
  GArchiveLineRegEx: TRegEx;

/// <summary>
/// Undoubles backslashes and turns forward slashes into backslashes.
/// </summary>
function NormalizeMapPath(const APath: string): string;
begin
  Result := StringReplace(APath, '\\', '\', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
end;

/// <summary>
/// The part after the last backslash. ExtractFileName is not used because a
/// Linux or macOS build of DX.Comply would not split on backslashes.
/// </summary>
function LastPathSegment(const APath: string): string;
begin
  var LPos := LastDelimiter('\', APath);
  Result := Copy(APath, LPos + 1, MaxInt);
end;

/// <summary>
/// True for objects of the Android NDK toolchain (crtbegin_so.o, libc++ ...).
/// They are not Delphi units and not components the project chose.
/// </summary>
function IsNdkPath(const ANormalizedPath: string): Boolean;
begin
  // An ndk folder counts only with a folder the NDK itself ships below it,
  // so a project kept in D:\Work\NDK\MyApp keeps its units.
  var LPath := LowerCase(ANormalizedPath);
  Result := ContainsText(LPath, '\sysroot\') or
    (ContainsText(LPath, '\ndk\') and
     (ContainsText(LPath, '\toolchains\') or ContainsText(LPath, '\platforms\') or
      ContainsText(LPath, '\sources\')));
end;

procedure AddUnique(const AValue: string; const ASeen: TDictionary<string, Boolean>;
  const AValues: TList<string>);
begin
  if (AValue = '') or ASeen.ContainsKey(AValue) then
    Exit;

  ASeen.Add(AValue, True);
  AValues.Add(AValue);
end;

class function TLldMapReader.IsHeaderLine(const ALine: string): Boolean;
begin
  var LWords := TRegEx.Replace(Trim(ALine), '\s+', ' ');
  Result := SameText(LWords, 'VMA LMA Size Align Out In Symbol');
end;

class function TLldMapReader.TryParseInputLine(const ALine: string; out AUnitName,
  AArchiveName: string): Boolean;
begin
  AUnitName := '';
  AArchiveName := '';
  Result := False;

  if Pos(cArchiveLineMarker, ALine) > 0 then
  begin
    var LArchiveMatch := GArchiveLineRegEx.Match(ALine);
    if not LArchiveMatch.Success then
      Exit;

    var LArchivePath := NormalizeMapPath(Trim(LArchiveMatch.Groups[1].Value));
    if IsNdkPath(LArchivePath) then
      Exit;

    AArchiveName := Trim(LastPathSegment(LArchivePath));
    Result := AArchiveName <> '';
    Exit;
  end;

  if Pos(cInputLineMarker, ALine) = 0 then
    Exit;

  var LMatch := GInputLineRegEx.Match(ALine);
  if not LMatch.Success then
    Exit;

  // The path itself may contain parentheses, e.g. "program files (x86)".
  var LPath := NormalizeMapPath(Trim(LMatch.Groups[1].Value));
  if (LPath = '') or StartsText('<internal>', LPath) or IsNdkPath(LPath) then
    Exit;

  AUnitName := Trim(LastPathSegment(LPath));
  Result := AUnitName <> '';
end;

class function TLldMapReader.Read(const AMapFilePath: string): TLldMapContents;
begin
  // This reader also runs for every Windows map without unit sections, and
  // those are written in the ANSI code page. Strict UTF-8 raises on such
  // bytes, so the file is read again in the ANSI code page, which accepts
  // every byte.
  try
    Result := ReadWithEncoding(AMapFilePath, TEncoding.UTF8);
  except
    on E: EEncodingError do
      Result := ReadWithEncoding(AMapFilePath, TEncoding.ANSI);
  end;
end;

class function TLldMapReader.ReadWithEncoding(const AMapFilePath: string;
  AEncoding: TEncoding): TLldMapContents;
begin
  Result := Default(TLldMapContents);
  if not TFile.Exists(AMapFilePath) then
    Exit;

  var LUnitSeen := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  var LArchiveSeen := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  var LUnitNames := TList<string>.Create;
  var LArchives := TList<string>.Create;
  var LReader := TStreamReader.Create(AMapFilePath, AEncoding, True, 65536);
  try
    var LLineCount := 0;
    while not LReader.EndOfStream do
    begin
      var LLine := LReader.ReadLine;
      if not Result.IsLldMap then
      begin
        Inc(LLineCount);
        if IsHeaderLine(LLine) then
        begin
          Result.IsLldMap := True;
        end
        else if LLineCount >= cHeaderSearchLines then
        begin
          Exit;
        end;
        Continue;
      end;

      var LUnitName: string;
      var LArchiveName: string;
      if TryParseInputLine(LLine, LUnitName, LArchiveName) then
      begin
        AddUnique(LUnitName, LUnitSeen, LUnitNames);
        AddUnique(LArchiveName, LArchiveSeen, LArchives);
      end;
    end;
    Result.UnitNames := LUnitNames.ToArray;
    Result.NativeComponents := LArchives.ToArray;
  finally
    LReader.Free;
    LArchives.Free;
    LUnitNames.Free;
    LArchiveSeen.Free;
    LUnitSeen.Free;
  end;
end;

initialization
  GInputLineRegEx := TRegEx.Create(cInputLinePattern, [roIgnoreCase, roCompiled]);
  GArchiveLineRegEx := TRegEx.Create(cArchiveLinePattern, [roIgnoreCase, roCompiled]);

end.
