/// <summary>
/// DX.Comply.Tests.ManifestDefines
/// DUnitX tests for manifest path variables.
/// </summary>
///
/// <remarks>
/// Covers parsing, expansion, the environment fallback, an undefined name,
/// the $$ escape, config precedence, and library mode. Issue #185.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.ManifestDefines;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  /// DUnitX fixture for $(name) in manifest path fields.
  /// </summary>
  [TestFixture]
  TManifestDefineTests = class
  public
    /// <summary>$(path.libs) becomes the defined folder and matches a unit there.</summary>
    [Test]
    procedure Expand_ReplacesFolderAndMatchesUnit;

    /// <summary>A relative result is resolved from the manifest file directory.</summary>
    [Test]
    procedure Expand_RelativeResolvesFromManifestDirectory;

    /// <summary>Text after the placeholder is kept, so a subfolder can be appended.</summary>
    [Test]
    procedure Expand_ConcatenatesSubfolder;

    /// <summary>$(env.NAME) reads the environment when that name is not defined.</summary>
    [Test]
    procedure Expand_EnvFallbackWhenNoDefine;

    /// <summary>A definition of env.NAME wins over the environment variable NAME.</summary>
    [Test]
    procedure Expand_DefineNamedEnvWinsOverEnvironment;

    /// <summary>$(NAME) does not read the environment.</summary>
    [Test]
    procedure Expand_PlainNameDoesNotReadEnvironment;

    /// <summary>An unknown name fails and names the variable, the row, and the field.</summary>
    [Test]
    procedure Expand_UndefinedNamesVariableRowAndField;

    /// <summary>An unknown name in own_code_folders names the root field.</summary>
    [Test]
    procedure Expand_OwnCodeFoldersUndefinedNamesManifest;

    /// <summary>$$(name) stays as the characters $(name) and does not require a definition.</summary>
    [Test]
    procedure Expand_EscapeKeepsLiteralAndDoesNotRequireVariable;

    /// <summary>$$ becomes one dollar sign.</summary>
    [Test]
    procedure Expand_DoubleDollarBecomesOneDollar;

    /// <summary>A placeholder without a closing parenthesis is an error.</summary>
    [Test]
    procedure Expand_UnclosedPlaceholderErrors;

    /// <summary>The JSON writers re-parse has the expanded path, not the placeholder.</summary>
    [Test]
    procedure Load_JsonHasExpandedPath;

    /// <summary>.dxcomply.json defines is loaded.</summary>
    [Test]
    procedure Config_LoadReadsDefines;

    /// <summary>A CLI name wins. A file name that was not passed stays.</summary>
    [Test]
    procedure Config_CliNameWinsAndOtherNamesStay;

    /// <summary>IDE options, then the project file, then the CLI. Each name is merged.</summary>
    [Test]
    procedure Merge_IdeThenFileThenCli;

    /// <summary>Library mode expands, matches, and does not write the placeholder.</summary>
    [Test]
    procedure LibraryMode_ExpandMatchesAndReportHasNoPlaceholder;

    /// <summary>Library mode fails the run when a path variable is undefined.</summary>
    [Test]
    procedure LibraryMode_UndefinedFailsGenerate;

    /// <summary>An unset variable is missing. An empty value is present.</summary>
    [Test]
    procedure Env_UnsetAndEmpty;
  end;

implementation

uses
  System.JSON,
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Winapi.Windows,
  DX.Comply.CLI.Options,
  DX.Comply.ComponentManifest,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.ManifestDefines,
  DX.Comply.Report.Intf;

const
  cEnvName = 'DXCOMPLY_MANIFEST_DEFINE_TEST';

function JsonSlash(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '\\', [rfReplaceAll]);
end;

function OneDefine(const AName, AValue: string): TArray<TManifestDefine>;
begin
  SetLength(Result, 1);
  Result[0].Name := AName;
  Result[0].Value := AValue;
end;

procedure TManifestDefineTests.Expand_ReplacesFolderAndMatchesUnit;
var
  LDir, LError: string;
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-def-match');
  TDirectory.CreateDirectory(LDir);
  try
    Assert.IsTrue(TryParseComponentManifest(
      '{"components":[{"name":"Vendor Pack","version":"1","vendor":"Acme",' +
      '"licence":"MIT","type":"library","units_folder":["$(path.libs)"]}]}',
      'C:\temp\manifests\components.json',
      OneDefine('path.libs', LDir), LManifest, LError), LError);
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LManifest.Components[0].Folders)));
    Assert.AreEqual(ExcludeTrailingPathDelimiter(TPath.GetFullPath(LDir)),
      LManifest.Components[0].Folders[0]);
    LMatch := MatchManifestUnit(LManifest, 'VendorUnit',
      TPath.Combine(LDir, 'VendorUnit.pas'));
    Assert.AreEqual(NativeInt(Ord(mmLibrary)), NativeInt(Ord(LMatch.Kind)));
    Assert.AreEqual(0, LMatch.ComponentIndex);
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LManifest.UsedVariables)));
    Assert.AreEqual('path.libs', LManifest.UsedVariables[0].Name);
    Assert.AreEqual('define', LManifest.UsedVariables[0].Source);
    Assert.AreEqual('units_folder', LManifest.UsedVariables[0].Field);
  finally
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TManifestDefineTests.Expand_RelativeResolvesFromManifestDirectory;
var
  LRoot, LManifestDir, LVendor, LManifestPath, LJson, LError: string;
  LManifest: TComponentManifest;
  LMatch: TManifestMatch;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'dxm-def-rel');
  LManifestDir := TPath.Combine(LRoot, 'manifests');
  LVendor := TPath.Combine(LRoot, 'libs', 'Vendor');
  TDirectory.CreateDirectory(LManifestDir);
  TDirectory.CreateDirectory(LVendor);
  try
    TFile.WriteAllText(TPath.Combine(LVendor, 'VendorUnit.pas'),
      'unit VendorUnit;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
    LManifestPath := TPath.Combine(LManifestDir, 'components.json');
    TFile.WriteAllText(LManifestPath,
      '{"components":[{"name":"Vendor Pack","version":"1","vendor":"Acme",' +
      '"licence":"MIT","type":"library","units_folder":["$(path.rel)"]}]}',
      TEncoding.UTF8);
    Assert.IsTrue(TryLoadComponentManifest(LManifestPath,
      OneDefine('path.rel', '..' + PathDelim + 'libs' + PathDelim + 'Vendor'),
      LManifest, LJson, LError), LError);
    Assert.AreEqual(ExcludeTrailingPathDelimiter(TPath.GetFullPath(LVendor)),
      LManifest.Components[0].Folders[0]);
    LMatch := MatchManifestUnit(LManifest, 'VendorUnit',
      TPath.Combine(LVendor, 'VendorUnit.pas'));
    Assert.AreEqual(NativeInt(Ord(mmLibrary)), NativeInt(Ord(LMatch.Kind)));
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TManifestDefineTests.Expand_ConcatenatesSubfolder;
var
  LRoot, LSub, LError: string;
  LManifest: TComponentManifest;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'dxm-def-sub');
  LSub := TPath.Combine(LRoot, 'sub');
  TDirectory.CreateDirectory(LSub);
  try
    Assert.IsTrue(TryParseComponentManifest(
      '{"components":[{"name":"Vendor Pack","units_folder":["$(path.libs)/sub"]}]}',
      'components.json',
      OneDefine('path.libs', LRoot), LManifest, LError), LError);
    Assert.AreEqual(ExcludeTrailingPathDelimiter(TPath.GetFullPath(LSub)),
      LManifest.Components[0].Folders[0]);
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TManifestDefineTests.Expand_EnvFallbackWhenNoDefine;
var
  LDir, LHad, LError, LExpanded: string;
  LHadValue: Boolean;
  LUses: TList<TManifestVariableUse>;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-def-env');
  TDirectory.CreateDirectory(LDir);
  LHadValue := TryReadEnvironmentVariable(cEnvName, LHad);
  Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), PChar(LDir));
  LUses := TList<TManifestVariableUse>.Create;
  try
    Assert.IsTrue(TryExpandManifestPath('$(env.' + cEnvName + ')',
      'Component[0] "Vendor Pack"', 'units_folder', nil, LExpanded, LError, LUses),
      LError);
    Assert.AreEqual(LDir, LExpanded);
    Assert.AreEqual(NativeInt(1), NativeInt(LUses.Count));
    Assert.AreEqual('environment', LUses[0].Source);
    Assert.AreEqual('units_folder', LUses[0].Field);
    Assert.AreEqual('Component[0] "Vendor Pack"', LUses[0].Context);
  finally
    LUses.Free;
    if LHadValue then
      Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), PChar(LHad))
    else
      Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), nil);
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TManifestDefineTests.Expand_DefineNamedEnvWinsOverEnvironment;
var
  LHad, LError, LExpanded: string;
  LHadValue: Boolean;
begin
  LHadValue := TryReadEnvironmentVariable(cEnvName, LHad);
  Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), 'from-env');
  try
    Assert.IsTrue(TryExpandManifestPath('$(env.' + cEnvName + ')',
      'Component[0] "Vendor Pack"', 'units_folder',
      OneDefine('env.' + cEnvName, 'D:\from-define'), LExpanded, LError, nil),
      LError);
    Assert.AreEqual('D:\from-define', LExpanded);
  finally
    if LHadValue then
      Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), PChar(LHad))
    else
      Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), nil);
  end;
end;

procedure TManifestDefineTests.Expand_PlainNameDoesNotReadEnvironment;
var
  LHad, LError, LExpanded: string;
  LHadValue: Boolean;
begin
  LHadValue := TryReadEnvironmentVariable(cEnvName, LHad);
  Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), 'from-env');
  try
    Assert.IsFalse(TryExpandManifestPath('$(' + cEnvName + ')',
      'Component[0] "Vendor Pack"', 'units_folder', nil, LExpanded, LError, nil));
    Assert.IsTrue(Pos('undefined variable "' + cEnvName + '"', LError) > 0, LError);
    Assert.IsTrue(Pos('units_folder', LError) > 0, LError);
  finally
    if LHadValue then
      Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), PChar(LHad))
    else
      Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), nil);
  end;
end;

procedure TManifestDefineTests.Expand_UndefinedNamesVariableRowAndField;
var
  LManifest: TComponentManifest;
  LError: string;
begin
  Assert.IsFalse(TryParseComponentManifest(
    '{"components":[{"name":"Vendor Pack","units_folder":["$(path.libs)"]}]}',
    'components.json', nil, LManifest, LError));
  Assert.IsTrue(Pos('undefined variable "path.libs"', LError) > 0, LError);
  Assert.IsTrue(Pos('Vendor Pack', LError) > 0, LError);
  Assert.IsTrue(Pos('units_folder', LError) > 0, LError);
  Assert.IsFalse(LManifest.Loaded);
end;

procedure TManifestDefineTests.Expand_OwnCodeFoldersUndefinedNamesManifest;
var
  LManifest: TComponentManifest;
  LError: string;
begin
  Assert.IsFalse(TryParseComponentManifest(
    '{"own_code_folders":["$(path.src)"],"components":[]}',
    'components.json', nil, LManifest, LError));
  Assert.IsTrue(Pos('Manifest: own_code_folders: undefined variable "path.src"',
    LError) > 0, LError);
end;

procedure TManifestDefineTests.Expand_EscapeKeepsLiteralAndDoesNotRequireVariable;
var
  LDir, LFile, LJson, LError, LExpanded: string;
  LManifest, LAgain: TComponentManifest;
begin
  Assert.IsTrue(TryExpandManifestPath('$$(path.libs)', 'Manifest', 'units_folder',
    nil, LExpanded, LError, nil), LError);
  Assert.AreEqual('$(path.libs)', LExpanded);
  Assert.IsTrue(TryParseComponentManifest(
    '{"components":[{"name":"Vendor Pack","units_folder":["$$(path.libs)"]}]}',
    'C:\temp\manifests\components.json', nil, LManifest, LError), LError);
  Assert.AreEqual(NativeInt(0), NativeInt(Length(LManifest.UsedVariables)));

  // The JSON writers parse again, without the definitions. The copy they
  // see must still be the literal $(path.libs), not an undefined variable.
  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-def-esc');
  TDirectory.CreateDirectory(LDir);
  try
    LFile := TPath.Combine(LDir, 'components.json');
    TFile.WriteAllText(LFile,
      '{"components":[{"name":"Vendor Pack","units_folder":["$$(path.libs)"]}]}',
      TEncoding.UTF8);
    Assert.IsTrue(TryLoadComponentManifest(LFile, nil, LManifest, LJson, LError), LError);
    Assert.IsTrue(TryParseComponentManifest(LJson, LFile, LAgain, LError), LError);
    Assert.IsTrue(Pos('$(path.libs)', LAgain.Components[0].Folders[0]) > 0,
      LAgain.Components[0].Folders[0]);
  finally
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TManifestDefineTests.Expand_DoubleDollarBecomesOneDollar;
var
  LError, LExpanded: string;
begin
  Assert.IsTrue(TryExpandManifestPath('C:\$$libs', 'Manifest', 'units_folder',
    nil, LExpanded, LError, nil), LError);
  Assert.AreEqual('C:\$libs', LExpanded);
end;

procedure TManifestDefineTests.Expand_UnclosedPlaceholderErrors;
var
  LError, LExpanded: string;
begin
  Assert.IsFalse(TryExpandManifestPath('$(path.libs', 'Component[0] "Vendor Pack"',
    'units_folder', nil, LExpanded, LError, nil));
  Assert.IsTrue(Pos('unclosed placeholder', LError) > 0, LError);
  Assert.IsTrue(Pos('Vendor Pack', LError) > 0, LError);
  Assert.IsTrue(Pos('units_folder', LError) > 0, LError);
end;

procedure TManifestDefineTests.Load_JsonHasExpandedPath;
var
  LRoot, LVendor, LPath, LJson, LError: string;
  LManifest: TComponentManifest;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, 'dxm-def-json');
  LVendor := TPath.Combine(LRoot, 'DxDefineVendor');
  TDirectory.CreateDirectory(LVendor);
  try
    LPath := TPath.Combine(LRoot, 'components.json');
    TFile.WriteAllText(LPath,
      '{"components":[{"name":"Vendor Pack","units_folder":["$(path.libs)"]}]}',
      TEncoding.UTF8);
    Assert.IsTrue(TryLoadComponentManifest(LPath,
      OneDefine('path.libs', LVendor), LManifest, LJson, LError), LError);
    Assert.IsTrue(Pos('$(path.libs)', LJson) = 0, LJson);
    Assert.IsTrue(Pos('$(', LJson) = 0, LJson);
    Assert.IsTrue(Pos('DxDefineVendor', LJson) > 0, LJson);
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TManifestDefineTests.Config_LoadReadsDefines;
var
  LPath, LValue: string;
  LGen: TDxComplyGenerator;
  LConfig: TSbomConfig;
begin
  LPath := TPath.Combine(TPath.GetTempPath, 'dxm-def-config.json');
  TFile.WriteAllText(LPath,
    '{"defines":{"path.libs":"D:/libs","path.keep":"D:/keep"}}', TEncoding.UTF8);
  LGen := TDxComplyGenerator.Create;
  try
    LConfig := LGen.LoadConfig(LPath);
    Assert.IsTrue(FindManifestDefine(LConfig.Defines, 'path.libs', LValue));
    Assert.AreEqual('D:/libs', LValue);
    Assert.IsTrue(FindManifestDefine(LConfig.Defines, 'path.keep', LValue));
    Assert.AreEqual('D:/keep', LValue);
  finally
    LGen.Free;
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
  end;
end;

procedure TManifestDefineTests.Config_CliNameWinsAndOtherNamesStay;
var
  LDir, LConfigPath, LValue: string;
  LOptions: TCliOptions;
  LGen: TDxComplyGenerator;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-def-prec');
  TDirectory.CreateDirectory(LDir);
  LConfigPath := TPath.Combine(LDir, '.dxcomply.json');
  TFile.WriteAllText(LConfigPath,
    '{"defines":{"path.libs":"from-file","path.keep":"kept"}}', TEncoding.UTF8);
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse([
      '--project=missing.dproj',
      '--define:path.libs=from-cli']));
    LGen := TDxComplyGenerator.Create(LOptions.ToSbomConfig);
    try
      Assert.IsFalse(LGen.GenerateFromConfig(
        TPath.Combine(LDir, 'missing.dproj'), LConfigPath));
      Assert.IsTrue(FindManifestDefine(LGen.Config.Defines, 'path.libs', LValue));
      Assert.AreEqual('from-cli', LValue);
      Assert.IsTrue(FindManifestDefine(LGen.Config.Defines, 'path.keep', LValue));
      Assert.AreEqual('kept', LValue);
    finally
      LGen.Free;
    end;
  finally
    LOptions.Free;
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TManifestDefineTests.Merge_IdeThenFileThenCli;
var
  LIde, LFile, LCli, LMerged: TArray<TManifestDefine>;
  LValue: string;
begin
  SetLength(LIde, 2);
  LIde[0].Name := 'path.libs';
  LIde[0].Value := 'from-ide';
  LIde[1].Name := 'path.ide';
  LIde[1].Value := 'only-ide';
  SetLength(LFile, 2);
  LFile[0].Name := 'path.libs';
  LFile[0].Value := 'from-file';
  LFile[1].Name := 'path.file';
  LFile[1].Value := 'only-file';
  SetLength(LCli, 1);
  LCli[0].Name := 'path.libs';
  LCli[0].Value := 'from-cli';
  LMerged := MergeManifestDefines(MergeManifestDefines(LIde, LFile), LCli);
  Assert.IsTrue(FindManifestDefine(LMerged, 'path.libs', LValue));
  Assert.AreEqual('from-cli', LValue);
  Assert.IsTrue(FindManifestDefine(LMerged, 'path.ide', LValue));
  Assert.AreEqual('only-ide', LValue);
  Assert.IsTrue(FindManifestDefine(LMerged, 'path.file', LValue));
  Assert.AreEqual('only-file', LValue);
end;

procedure TManifestDefineTests.LibraryMode_ExpandMatchesAndReportHasNoPlaceholder;
var
  LDir, LVendor, LManifestPath, LOutput, LHtml, LText, LJoined: string;
  LConfig: TSbomConfig;
  LGenerator: TDxComplyGenerator;
  LMessages: TList<string>;
  LCapture: TProgressEvent;
  LOk: Boolean;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-def-lib');
  LVendor := TPath.Combine(LDir, 'DxDefineVendor');
  TDirectory.CreateDirectory(LVendor);
  LMessages := TList<string>.Create;
  try
    LCapture :=
      procedure(const AMessage: string; const AProgress: Integer)
      begin
        LMessages.Add(AMessage);
      end;
    TFile.WriteAllText(TPath.Combine(LVendor, 'VendorUnit.pas'),
      'unit VendorUnit;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
    LManifestPath := TPath.Combine(LDir, 'components.json');
    TFile.WriteAllText(LManifestPath,
      '{"supplier":{"name":"Acme"},"components":[' +
      '{"name":"Vendor Pack","version":"1.0","vendor":"Acme","licence":"MIT",' +
      '"type":"library","units_folder":["$(path.libs)"]}]}',
      TEncoding.UTF8);

    LConfig := TSbomConfig.Default;
    LConfig.LibraryMode := True;
    LConfig.SourceDirs := [LVendor];
    LConfig.ManifestFile := LManifestPath;
    LConfig.Defines := OneDefine('path.libs', LVendor);
    LConfig.Supplier := 'Acme';
    LConfig.Licence := 'MIT';
    LConfig.SbomCreator := 'sbom@acme.example';
    LConfig.HumanReadableReport.Enabled := True;
    LConfig.HumanReadableReport.Format := hrfHtml;
    LConfig.HumanReadableReport.OutputBasePath := TPath.Combine(LDir, 'report.html');

    LOutput := TPath.Combine(LDir, 'lib.cdx.json');
    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress := LCapture;
      LOk := LGenerator.Generate('', LOutput, sfCycloneDxJson);
      LJoined := string.Join(sLineBreak, LMessages.ToArray);
      Assert.IsTrue(LOk, LJoined);
    finally
      LGenerator.Free;
    end;

    LJoined := string.Join(sLineBreak, LMessages.ToArray);
    Assert.IsTrue(Pos('Info: Manifest variable "path.libs"', LJoined) > 0, LJoined);
    Assert.IsTrue(Pos('DxDefineVendor', LJoined) > 0, LJoined);
    LText := TFile.ReadAllText(LOutput, TEncoding.UTF8);
    Assert.IsTrue(Pos('Vendor Pack', LText) > 0, LText);
    Assert.IsTrue(Pos('$(path.libs)', LText) = 0, LText);
    Assert.IsTrue(Pos('$(', LText) = 0, LText);
    LHtml := TPath.Combine(LDir, 'report.html');
    Assert.IsTrue(TFile.Exists(LHtml), LHtml);
    LText := TFile.ReadAllText(LHtml, TEncoding.UTF8);
    Assert.IsTrue(Pos('Vendor Pack', LText) > 0, LText);
    Assert.IsTrue(Pos('$(path.libs)', LText) = 0, LText);
    Assert.IsTrue(Pos('$(', LText) = 0, LText);
  finally
    LMessages.Free;
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TManifestDefineTests.LibraryMode_UndefinedFailsGenerate;
var
  LDir, LManifestPath, LJoined: string;
  LConfig: TSbomConfig;
  LGenerator: TDxComplyGenerator;
  LMessages: TList<string>;
  LCapture: TProgressEvent;
  LOk: Boolean;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxm-def-lib-bad');
  TDirectory.CreateDirectory(LDir);
  LMessages := TList<string>.Create;
  try
    LCapture :=
      procedure(const AMessage: string; const AProgress: Integer)
      begin
        LMessages.Add(AMessage);
      end;
    LManifestPath := TPath.Combine(LDir, 'components.json');
    TFile.WriteAllText(LManifestPath,
      '{"components":[{"name":"Vendor Pack","units_folder":["$(path.libs)"]}]}',
      TEncoding.UTF8);
    LConfig := TSbomConfig.Default;
    LConfig.LibraryMode := True;
    LConfig.SourceDirs := [LDir];
    LConfig.ManifestFile := LManifestPath;
    LConfig.SbomCreator := 'sbom@acme.example';
    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress := LCapture;
      LOk := LGenerator.Generate('', TPath.Combine(LDir, 'lib.cdx.json'));
    finally
      LGenerator.Free;
    end;
    Assert.IsFalse(LOk);
    LJoined := string.Join(sLineBreak, LMessages.ToArray);
    Assert.IsTrue(Pos('undefined variable "path.libs"', LJoined) > 0, LJoined);
    Assert.IsTrue(Pos('Vendor Pack', LJoined) > 0, LJoined);
    Assert.IsTrue(Pos('units_folder', LJoined) > 0, LJoined);
  finally
    LMessages.Free;
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TManifestDefineTests.Env_UnsetAndEmpty;
var
  LHad, LValue: string;
  LHadValue: Boolean;
begin
  LHadValue := TryReadEnvironmentVariable(cEnvName, LHad);
  Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), nil);
  try
    Assert.IsFalse(TryReadEnvironmentVariable(cEnvName, LValue));
    Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), PChar(''));
    Assert.IsTrue(TryReadEnvironmentVariable(cEnvName, LValue));
    Assert.AreEqual('', LValue);
  finally
    if LHadValue then
      Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), PChar(LHad))
    else
      Winapi.Windows.SetEnvironmentVariable(PChar(cEnvName), nil);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TManifestDefineTests);

end.
