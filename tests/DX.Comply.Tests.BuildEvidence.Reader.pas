/// <summary>
/// DX.Comply.Tests.BuildEvidence.Reader
/// DUnitX tests for TBuildEvidenceReader.
/// </summary>
///
/// <remarks>
/// Verifies the first-pass reader that maps already scanned TProjectInfo data
/// into a normalized TBuildEvidence structure.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.BuildEvidence.Reader;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.BuildEvidence.Reader;

type
  /// <summary>
  /// DUnitX fixture for the build evidence reader.
  /// </summary>
  [TestFixture]
  TBuildEvidenceReaderTests = class
  private
    FReader: IBuildEvidenceReader;
  public
    [Setup]
    procedure Setup;

    /// <summary>
    /// Scalar metadata and normalized path fields must be copied to TBuildEvidence.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_MapsScalarFields;

    /// <summary>
    /// Lists and warnings must be copied without duplication.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_CopiesListsAndWarnings;

    /// <summary>
    /// The reader must emit project metadata evidence items.
    /// </summary>
    [Test]
    procedure Read_ProjectInfo_CreatesEvidenceItems;
  end;

implementation

procedure TBuildEvidenceReaderTests.Setup;
begin
  FReader := TBuildEvidenceReader.Create;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_MapsScalarFields;
var
  LBuildEvidence: TBuildEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\Repo\src\DX.Comply.Engine.dproj';
    LProjectInfo.Platform := 'Win64';
    LProjectInfo.Configuration := 'Release';
    LProjectInfo.OutputDir := 'C:\Repo\build\Win64\Release';
    LProjectInfo.DcuOutputDir := 'C:\Repo\build\Win64\Release\dcu';
    LProjectInfo.DcpOutputDir := 'C:\Repo\build\Win64\Release\dcu';
    LProjectInfo.BplOutputDir := 'C:\Repo\build\Win64\Release';

    LBuildEvidence := FReader.Read(LProjectInfo);
    try
      Assert.AreEqual(LProjectInfo.ProjectPath, LBuildEvidence.ProjectPath,
        'ProjectPath must be copied into TBuildEvidence');
      Assert.AreEqual(LProjectInfo.Platform, LBuildEvidence.Platform,
        'Platform must be copied into TBuildEvidence');
      Assert.AreEqual(LProjectInfo.Configuration, LBuildEvidence.Configuration,
        'Configuration must be copied into TBuildEvidence');
      Assert.AreEqual(LProjectInfo.OutputDir, LBuildEvidence.Paths.OutputDir,
        'OutputDir must be copied into the build path set');
      Assert.AreEqual(LProjectInfo.DcuOutputDir, LBuildEvidence.Paths.DcuOutputDir,
        'DcuOutputDir must be copied into the build path set');
      Assert.AreEqual(LProjectInfo.DcpOutputDir, LBuildEvidence.Paths.DcpOutputDir,
        'DcpOutputDir must be copied into the build path set');
      Assert.AreEqual(LProjectInfo.BplOutputDir, LBuildEvidence.Paths.BplOutputDir,
        'BplOutputDir must be copied into the build path set');
    finally
      LBuildEvidence.Free;
    end;
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_CopiesListsAndWarnings;
var
  LBuildEvidence: TBuildEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.SearchPaths.Add('C:\Repo\src');
    LProjectInfo.SearchPaths.Add('C:\Repo\libs');
    LProjectInfo.UnitScopeNames.Add('System');
    LProjectInfo.UnitScopeNames.Add('Vcl');
    LProjectInfo.RuntimePackages.Add('rtl');
    LProjectInfo.RuntimePackages.Add('vcl');
    LProjectInfo.Warnings.Add('Synthetic warning');

    LBuildEvidence := FReader.Read(LProjectInfo);
    try
      Assert.AreEqual(2, LBuildEvidence.SearchPaths.Count,
        'SearchPaths must be copied to build evidence');
      Assert.AreEqual(2, LBuildEvidence.UnitScopeNames.Count,
        'UnitScopeNames must be copied to build evidence');
      Assert.AreEqual(2, LBuildEvidence.RuntimePackages.Count,
        'RuntimePackages must be copied to build evidence');
      Assert.AreEqual(1, LBuildEvidence.Warnings.Count,
        'Warnings must be copied to build evidence');
      Assert.AreEqual('Synthetic warning', LBuildEvidence.Warnings[0],
        'Warnings must preserve the original text');
    finally
      LBuildEvidence.Free;
    end;
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildEvidenceReaderTests.Read_ProjectInfo_CreatesEvidenceItems;
var
  LBuildEvidence: TBuildEvidence;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\Repo\src\DX.Comply.Engine.dproj';
    LProjectInfo.Platform := 'Win32';
    LProjectInfo.Configuration := 'Debug';
    LProjectInfo.OutputDir := 'C:\Repo\build\Win32\Debug';
    LProjectInfo.RuntimePackages.Add('rtl');

    LBuildEvidence := FReader.Read(LProjectInfo);
    try
      Assert.IsTrue(LBuildEvidence.EvidenceItems.Count >= 3,
        'The reader must emit at least project metadata, output dir, and runtime package evidence items');
      Assert.AreEqual(besProjectMetadata, LBuildEvidence.EvidenceItems[0].SourceKind,
        'The first evidence item must be tagged as project metadata');
      Assert.AreEqual('Project metadata', LBuildEvidence.EvidenceItems[0].DisplayName,
        'The first evidence item must describe the project metadata source');
    finally
      LBuildEvidence.Free;
    end;
  finally
    LProjectInfo.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildEvidenceReaderTests);

end.