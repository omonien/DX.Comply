/// <summary>
/// DX.Comply.Tests.MapFile.LldReader
/// DUnitX tests for TLldMapReader.
/// </summary>
///
/// <remarks>
/// Uses single lines and tests\fixtures\lldmap\android-map-sample.txt, an
/// 81-line excerpt of the Android64 map libCipher_FMX.so.map (issues #99, #100).
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.MapFile.LldReader;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.MapFile.LldReader;

type
  /// <summary>
  /// DUnitX fixture for the ARM/LLVM linker map reader.
  /// </summary>
  [TestFixture]
  TLldMapReaderTests = class
  private
    function SamplePath: string;
  public
    /// <summary>The LLD header is recognised regardless of column spacing.</summary>
    [Test]
    procedure IsHeaderLine_LldHeader_ReturnsTrue;

    /// <summary>A classic Delphi segment header is not an LLD header.</summary>
    [Test]
    procedure IsHeaderLine_ClassicHeader_ReturnsFalse;

    /// <summary>A unit object with doubled backslashes and "(x86)" in its path.</summary>
    [Test]
    procedure TryParseInputLine_UnitObject_ReturnsObjectFileName;

    /// <summary>A relative DCU output path keeps the dotted unit name.</summary>
    [Test]
    procedure TryParseInputLine_RelativeUnitObject_ReturnsUnitName;

    /// <summary>An archive member lib.a(x.o) is a native component.</summary>
    [Test]
    procedure TryParseInputLine_ArchiveMember_ReturnsArchiveName;

    /// <summary>Linker-internal sections, NDK objects and symbol lines are skipped.</summary>
    [Test]
    procedure TryParseInputLine_InternalNdkAndSymbol_ReturnFalse;

    /// <summary>The fixture yields its four units and two archives, deduplicated.</summary>
    [Test]
    procedure Read_AndroidSample_ReturnsUniqueUnitsAndArchives;

    /// <summary>A file without the LLD header is not read.</summary>
    [Test]
    procedure Read_ClassicMap_IsNotLldMap;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Tests.Paths;

const
  cSystemLine =
    '          dbef30           dbef30     16f8     4         c:\\program files (x86)\\embarcadero\\' +
    'studio\\37.0\\lib\\Android64\\Release\\System.o:(.gcc_except_table)';
  cRelativeLine =
    '         184e348          184e348        4     4         .\\..\\..\\Compiled\\' +
    'DCU_IDE37.0_Android64__Demos\\FMX.Controls.Presentation.o:(.text._ZN3Fmx8Controls)';
  cArchiveLine =
    '         184e42c          184e42c       c8     4         c:\\program files (x86)\\embarcadero\\' +
    'studio\\37.0\\lib\\Android64\\Release/libunwind.a(UnwindLevel1.o):(.text._Unwind_RaiseException)';
  cInternalLine =
    '             2d0              2d0       24     4         <internal>:(.note.gnu.build-id)';
  cNdkLine =
    '             238              238       98     4         C:\\Users\\Public\\Documents\\Embarcadero\\' +
    'Studio\\37.0\\CatalogRepository\\AndroidSDK-37.0.60952.8797\\ndk\\27.1.12297006\\toolchains\\llvm\\' +
    'prebuilt\\windows-x86_64\\sysroot\\usr\\lib\\aarch64-linux-android\\24\\crtbegin_so.o:(.note.android.ident)';
  cSymbolLine =
    '         184e348          184e348        4     1                 Cipher_fmx::Finalization()';

function TLldMapReaderTests.SamplePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests' + PathDelim + 'fixtures' + PathDelim + 'lldmap' +
    PathDelim + 'android-map-sample.txt');
end;

procedure TLldMapReaderTests.IsHeaderLine_LldHeader_ReturnsTrue;
begin
  Assert.IsTrue(TLldMapReader.IsHeaderLine(
    '             VMA              LMA     Size Align Out     In      Symbol'));
  Assert.IsTrue(TLldMapReader.IsHeaderLine('VMA LMA Size Align Out In Symbol'));
end;

procedure TLldMapReaderTests.IsHeaderLine_ClassicHeader_ReturnsFalse;
begin
  Assert.IsFalse(TLldMapReader.IsHeaderLine(' Start         Length     Name                   Class'));
  Assert.IsFalse(TLldMapReader.IsHeaderLine(''));
end;

procedure TLldMapReaderTests.TryParseInputLine_UnitObject_ReturnsObjectFileName;
begin
  var LUnitName: string;
  var LArchiveName: string;
  Assert.IsTrue(TLldMapReader.TryParseInputLine(cSystemLine, LUnitName, LArchiveName));
  Assert.AreEqual('System', LUnitName);
  Assert.AreEqual('', LArchiveName);
end;

procedure TLldMapReaderTests.TryParseInputLine_RelativeUnitObject_ReturnsUnitName;
begin
  var LUnitName: string;
  var LArchiveName: string;
  Assert.IsTrue(TLldMapReader.TryParseInputLine(cRelativeLine, LUnitName, LArchiveName));
  Assert.AreEqual('FMX.Controls.Presentation', LUnitName);
  Assert.AreEqual('', LArchiveName);
end;

procedure TLldMapReaderTests.TryParseInputLine_ArchiveMember_ReturnsArchiveName;
begin
  var LUnitName: string;
  var LArchiveName: string;
  Assert.IsTrue(TLldMapReader.TryParseInputLine(cArchiveLine, LUnitName, LArchiveName));
  Assert.AreEqual('', LUnitName, 'An archive member is not a Delphi unit');
  Assert.AreEqual('libunwind.a', LArchiveName);
end;

procedure TLldMapReaderTests.TryParseInputLine_InternalNdkAndSymbol_ReturnFalse;
begin
  var LUnitName: string;
  var LArchiveName: string;
  Assert.IsFalse(TLldMapReader.TryParseInputLine(cInternalLine, LUnitName, LArchiveName), 'internal');
  Assert.IsFalse(TLldMapReader.TryParseInputLine(cNdkLine, LUnitName, LArchiveName), 'NDK object');
  Assert.IsFalse(TLldMapReader.TryParseInputLine(cSymbolLine, LUnitName, LArchiveName), 'symbol');
  Assert.AreEqual('', LUnitName);
  Assert.AreEqual('', LArchiveName);
end;

procedure TLldMapReaderTests.Read_AndroidSample_ReturnsUniqueUnitsAndArchives;
begin
  var LPath := SamplePath;
  Assert.IsTrue(TFile.Exists(LPath), 'Fixture missing: ' + LPath);

  var LContents := TLldMapReader.Read(LPath);
  Assert.IsTrue(LContents.IsLldMap);
  Assert.AreEqual('SysInit,System,Cipher_FMX,DECCipherBase', string.Join(',', LContents.UnitNames));
  Assert.AreEqual('libunwind.a,libpcre.a', string.Join(',', LContents.NativeComponents));
end;

procedure TLldMapReaderTests.Read_ClassicMap_IsNotLldMap;
begin
  var LPath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LPath,
      ' Start         Length     Name                   Class' + sLineBreak +
      '  0001:00000000 000067FCH .text                  CODE' + sLineBreak + cSystemLine + sLineBreak,
      TEncoding.UTF8);

    var LContents := TLldMapReader.Read(LPath);
    Assert.IsFalse(LContents.IsLldMap);
    Assert.AreEqual(NativeInt(0), NativeInt(Length(LContents.UnitNames)));
    Assert.AreEqual(NativeInt(0), NativeInt(Length(LContents.NativeComponents)));
  finally
    TFile.Delete(LPath);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLldMapReaderTests);

end.
