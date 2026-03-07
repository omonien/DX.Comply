/// <summary>
/// DX.Comply.Tests.Engine
/// DUnitX tests for TDxComplyGenerator (engine facade).
/// </summary>
///
/// <remarks>
/// Covers project validation, progress-event firing, full end-to-end
/// SBOM generation against the real engine .dproj, configuration defaults,
/// and GenerateFromConfig fall-back behaviour when no config file exists.
///
/// Integration tests (Generate_ValidProject_*) require DX.Comply.Engine.dproj
/// to be reachable at build\Win32\Debug\..\..\..\src\.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Engine;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.BuildOrchestrator,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// DUnitX test fixture for TDxComplyGenerator.
  /// </summary>
  [TestFixture]
  TEngineTests = class
  private
    FTempDir: string;
    FOutputFile: string;
    FProgressMessages: TStringList;
    FProgressValues: TList<Integer>;
    /// <summary>
    /// Absolute path to DX.Comply.Engine.dproj resolved from the test binary location.
    /// </summary>
    FEngineDprojPath: string;
    /// <summary>
    /// Progress callback – captures messages and percentage values for assertion.
    /// </summary>
    procedure OnProgress(const AMessage: string; const AProgress: Integer);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // ---- ValidateProject ----------------------------------------------------

    /// <summary>ValidateProject must return True for the existing engine dproj.</summary>
    [Test]
    procedure ValidateProject_ValidDproj_ReturnsTrue;

    /// <summary>ValidateProject must return False for a non-existent file.</summary>
    [Test]
    procedure ValidateProject_NonExistentFile_ReturnsFalse;

    /// <summary>ValidateProject must return False for a file with a wrong extension.</summary>
    [Test]
    procedure ValidateProject_WrongExtension_ReturnsFalse;

    // ---- Generate — failure path -------------------------------------------

    /// <summary>Generate with an invalid project path must return False.</summary>
    [Test]
    procedure Generate_InvalidProject_ReturnsFalse;

    /// <summary>A failed Generate must fire a progress event with value -1.</summary>
    [Test]
    procedure Generate_InvalidProject_FiresNegativeProgress;

    // ---- Generate — happy path (integration) --------------------------------

    /// <summary>Generate with the engine dproj must return True and write the output file.</summary>
    [Test]
    procedure Generate_ValidProject_WritesFile;

    /// <summary>A successful Generate must fire a progress event with value 100.</summary>
    [Test]
    procedure Generate_ValidProject_FiresProgress100;

    /// <summary>The generated file must contain valid CycloneDX JSON.</summary>
    [Test]
    procedure Generate_OutputFileContainsValidJson;

    // ---- GenerateFromConfig -------------------------------------------------

    /// <summary>GenerateFromConfig with a missing config must fall back to defaults and succeed.</summary>
    [Test]
    procedure GenerateFromConfig_MissingConfig_UsesDefaults;

    // ---- TSbomConfig --------------------------------------------------------

    /// <summary>TSbomConfig.Default.Format must be sfCycloneDxJson.</summary>
    [Test]
    procedure Config_Default_HasCycloneDxJson;

    /// <summary>TSbomConfig.Default.OutputPath must be 'bom.json'.</summary>
    [Test]
    procedure Config_Default_OutputPathIsBomJson;

    /// <summary>Deep-Evidence builds must be disabled by default.</summary>
    [Test]
    procedure Config_Default_DeepEvidenceBuildDisabled;
  end;

implementation

{ TEngineTests }

procedure TEngineTests.Setup;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FTempDir := TPath.Combine(TPath.GetTempPath, GUIDToString(LGuid).Trim(['{', '}']));
  TDirectory.CreateDirectory(FTempDir);

  FOutputFile := TPath.Combine(FTempDir, 'bom.json');

  FProgressMessages := TStringList.Create;
  FProgressValues   := TList<Integer>.Create;

  // Resolve path to the engine dproj fixture.
  // Test binary is placed in: build\<Platform>\<Config>\
  // Engine dproj is at:       src\DX.Comply.Engine.dproj
  FEngineDprojPath := TPath.GetFullPath(
    TPath.Combine(TPath.GetDirectoryName(ParamStr(0)),
      '..' + PathDelim + '..' + PathDelim + '..' + PathDelim +
      'src' + PathDelim + 'DX.Comply.Engine.dproj'));
end;

procedure TEngineTests.TearDown;
begin
  if TFile.Exists(FOutputFile) then
    TFile.Delete(FOutputFile);
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);

  FProgressMessages.Free;
  FProgressValues.Free;
end;

procedure TEngineTests.OnProgress(const AMessage: string; const AProgress: Integer);
begin
  FProgressMessages.Add(AMessage);
  FProgressValues.Add(AProgress);
end;

// ---- ValidateProject --------------------------------------------------------

procedure TEngineTests.ValidateProject_ValidDproj_ReturnsTrue;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    Assert.IsTrue(LGen.ValidateProject(FEngineDprojPath),
      'ValidateProject must return True for the existing engine dproj');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.ValidateProject_NonExistentFile_ReturnsFalse;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    Assert.IsFalse(LGen.ValidateProject('C:\DoesNotExist\Missing.dproj'),
      'ValidateProject must return False for a non-existent file');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.ValidateProject_WrongExtension_ReturnsFalse;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    Assert.IsFalse(LGen.ValidateProject('C:\Temp\readme.txt'),
      'ValidateProject must return False for a wrong file extension');
  finally
    LGen.Free;
  end;
end;

// ---- Generate — failure path ------------------------------------------------

procedure TEngineTests.Generate_InvalidProject_ReturnsFalse;
var
  LGen: TDxComplyGenerator;
  LResult: Boolean;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LResult := LGen.Generate('C:\DoesNotExist\NoProject.dproj', FOutputFile);
    Assert.IsFalse(LResult, 'Generate must return False for an invalid project path');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_InvalidProject_FiresNegativeProgress;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LGen.Generate('C:\DoesNotExist\NoProject.dproj', FOutputFile);
    Assert.IsTrue(FProgressValues.Contains(-1),
      'A failed Generate must fire a progress event with value -1');
  finally
    LGen.Free;
  end;
end;

// ---- Generate — happy path (integration) ------------------------------------

procedure TEngineTests.Generate_ValidProject_WritesFile;
var
  LGen: TDxComplyGenerator;
  LResult: Boolean;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LResult := LGen.Generate(FEngineDprojPath, FOutputFile);
    Assert.IsTrue(LResult, 'Generate must return True for the engine dproj');
    Assert.IsTrue(TFile.Exists(FOutputFile),
      'Generate must write the output file to disk');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_ValidProject_FiresProgress100;
var
  LGen: TDxComplyGenerator;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LGen.Generate(FEngineDprojPath, FOutputFile);
    Assert.IsTrue(FProgressValues.Contains(100),
      'A successful Generate must fire a progress event with value 100');
  finally
    LGen.Free;
  end;
end;

procedure TEngineTests.Generate_OutputFileContainsValidJson;
var
  LGen: TDxComplyGenerator;
  LContent: string;
  LJson: TJSONObject;
begin
  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    LGen.Generate(FEngineDprojPath, FOutputFile);
    Assert.IsTrue(TFile.Exists(FOutputFile), 'Output file must exist');

    LContent := TFile.ReadAllText(FOutputFile, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
    try
      Assert.IsNotNull(LJson, 'Output file must contain valid parseable JSON');
      Assert.AreEqual('CycloneDX', LJson.GetValue<string>('bomFormat'),
        'bomFormat must be CycloneDX');
    finally
      LJson.Free;
    end;
  finally
    LGen.Free;
  end;
end;

// ---- GenerateFromConfig -----------------------------------------------------

procedure TEngineTests.GenerateFromConfig_MissingConfig_UsesDefaults;
var
  LGen: TDxComplyGenerator;
  LNonExistentConfig: string;
  LResult: Boolean;
begin
  // When the config file is absent, LoadConfig falls back to TSbomConfig.Default
  // and the generation should still succeed against the valid engine dproj.
  LNonExistentConfig := TPath.Combine(FTempDir, 'nonexistent.json');

  LGen := TDxComplyGenerator.Create;
  try
    LGen.OnProgress := OnProgress;
    // Override the output path to a known temp location so we can clean up.
    // GenerateFromConfig uses the config's OutputPath which defaults to 'bom.json'
    // relative to the project dir. We write to FOutputFile explicitly via Generate
    // after loading the (non-existent) config through the internal API. Since we
    // cannot override output path via GenerateFromConfig directly, we accept any
    // result and simply verify the call does not raise.
    Assert.WillNotRaise(
      procedure
      begin
        LResult := LGen.GenerateFromConfig(FEngineDprojPath, LNonExistentConfig);
      end,
      Exception,
      'GenerateFromConfig must not raise when config file is missing');
    // With a valid project and default config the call should succeed
    Assert.IsTrue(LResult,
      'GenerateFromConfig must succeed when config is missing and project is valid');
  finally
    LGen.Free;
  end;
end;

// ---- TSbomConfig ------------------------------------------------------------

procedure TEngineTests.Config_Default_HasCycloneDxJson;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.AreEqual(Ord(sfCycloneDxJson), Ord(LConfig.Format),
    'TSbomConfig.Default.Format must be sfCycloneDxJson');
end;

procedure TEngineTests.Config_Default_OutputPathIsBomJson;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.AreEqual('bom.json', LConfig.OutputPath,
    'TSbomConfig.Default.OutputPath must be ''bom.json''');
end;

procedure TEngineTests.Config_Default_DeepEvidenceBuildDisabled;
var
  LConfig: TSbomConfig;
begin
  LConfig := TSbomConfig.Default;
  Assert.AreEqual(NativeInt(Ord(debDisabled)), NativeInt(Ord(LConfig.DeepEvidenceMode)),
    'TSbomConfig.Default.DeepEvidenceMode must be debDisabled');
  Assert.AreEqual(0, LConfig.DeepEvidenceDelphiVersion,
    'TSbomConfig.Default.DeepEvidenceDelphiVersion must be 0');
  Assert.AreEqual('', LConfig.DeepEvidenceBuildScriptPath,
    'TSbomConfig.Default.DeepEvidenceBuildScriptPath must be empty');
  Assert.IsFalse(LConfig.WarnOnEmptyCompositionEvidence,
    'TSbomConfig.Default.WarnOnEmptyCompositionEvidence must be False');
end;

initialization
  TDUnitX.RegisterTestFixture(TEngineTests);

end.
