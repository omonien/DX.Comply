/// <summary>
/// DX.Comply.Tests.CraChecks
/// DUnitX tests for CRA and BSI header warnings.
/// </summary>
///
/// <remarks>
/// Each warning is built from records in memory. The deployable check uses
/// the hash fields on the artefact list and does not read a file.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.CraChecks;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DX.Comply.CraChecks,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf;

type
  [TestFixture]
  TCraChecksTests = class
  private
    const
      cOutputPath = 'C:\build\Win64\Release\AcmeApp.exe';
      cNoSupplier =
        'CRA/BSI: The SBOM names no supplier for the product. BSI TR-03183-2 section 5.2.2 requires the component creator, and CRA Annex II point 1 requires the name and contact of the manufacturer. Pass --supplier=<name>, set product.supplier in .dxcomply.json, or fill CompanyName in the project version info.';
      cNoSbomCreator =
        'CRA/BSI: The SBOM creator contact is missing. BSI TR-03183-2 section 5.2.1 requires the email address or URL of the entity that created the SBOM. Pass --sbom-creator=<email-or-url> or set sbomCreator in .dxcomply.json.';
      cNoVersion =
        'CRA/BSI: The product has no version. BSI TR-03183-2 section 5.2.2 requires the component version, and CRA Annex II point 3 requires information that identifies the product uniquely. Pass --version=<version>, set product.version in .dxcomply.json, or set the version info in the project options.';
      cDefaultVersion =
        'CRA/BSI: The product version is 1.0.0.0, the Delphi default for new projects. BSI TR-03183-2 section 5.2.2 requires the version the creator uses to tell releases apart, and CRA Annex II point 3 requires information that identifies the product uniquely. If 1.0.0.0 is not the real release version, pass --version=<version>, set product.version in .dxcomply.json, or update the version info in the project options.';
      cNoLicence =
        'CRA/BSI: The product has no distribution licence. BSI TR-03183-2 section 5.2.2 requires the distribution licences of each component, named by SPDX identifier (section 6.1). Pass --licence=<SPDX expression> or set product.licence in .dxcomply.json.';
    function SupplierContactWarning(const ASupplier: string): string;
    function DeployableWarning(const APath: string): string;
    procedure FillComplete(out AConfig: TSbomConfig; out AMetadata: TSbomMetadata;
      out AProject: TProjectInfo; const AArtefacts: TArtefactList);
    function HasWarning(const AWarnings: TArray<string>; const AText: string): Boolean;
  public
    [Test]
    procedure Warn_NoSupplier;

    [Test]
    procedure Warn_SupplierWithoutContact;

    [Test]
    procedure Warn_NoSbomCreator;

    [Test]
    procedure Warn_NoVersion;

    [Test]
    procedure Warn_DefaultVersion;

    [Test]
    procedure Warn_NoLicence;

    [Test]
    procedure Warn_DeployableNotHashed;

    [Test]
    procedure CompleteInput_NoWarnings;

    [Test]
    procedure ExplicitDefaultVersion_NoDefaultWarning;

    [Test]
    procedure EmailSupplier_NoContactWarning;
  end;

implementation

function TCraChecksTests.SupplierContactWarning(const ASupplier: string): string;
begin
  Result := 'CRA/BSI: The supplier "' + ASupplier +
    '" has no email address or URL. BSI TR-03183-2 section 5.2.2 requires the component creator as an email address, or a URL when there is none, and CRA Annex II point 1 requires an email address or other digital contact of the manufacturer. Pass --supplier-url=<url> or set product.supplierUrl in .dxcomply.json.';
end;

function TCraChecksTests.DeployableWarning(const APath: string): string;
begin
  Result := 'CRA/BSI: The built file ' + APath +
    ' was not found, so the SBOM has no hash for it. BSI TR-03183-2 section 5.2.2 requires the SHA-512 of the deployable component, and CRA Annex I Part II point 1 requires an SBOM of the product. Build the project first, or check the output directory, --platform and --config-name.';
end;

procedure TCraChecksTests.FillComplete(out AConfig: TSbomConfig;
  out AMetadata: TSbomMetadata; out AProject: TProjectInfo;
  const AArtefacts: TArtefactList);
var
  LArtefact: TArtefactInfo;
begin
  AConfig := TSbomConfig.Default;
  AConfig.ProductVersion := '2.1.0';
  AConfig.Supplier := 'Acme GmbH';
  AConfig.SupplierUrl := 'https://acme.example';
  AConfig.SbomCreator := 'sbom@example.com';
  AConfig.Licence := 'MIT';

  AMetadata := Default(TSbomMetadata);
  AMetadata.ProductName := 'Acme App';
  AMetadata.ProductVersion := '2.1.0';
  AMetadata.Supplier := 'Acme GmbH';
  AMetadata.SupplierUrl := 'https://acme.example';
  AMetadata.SbomCreator := 'sbom@example.com';
  AMetadata.Licence := 'MIT';

  AProject := Default(TProjectInfo);
  AProject.ProjectName := 'AcmeApp';
  AProject.OutputFilePath := cOutputPath;

  AArtefacts.Clear;
  LArtefact := Default(TArtefactInfo);
  LArtefact.FilePath := cOutputPath;
  LArtefact.RelativePath := 'AcmeApp.exe';
  LArtefact.ArtefactType := 'application';
  LArtefact.Hash := 'aa';
  LArtefact.HashSha512 := 'bb';
  AArtefacts.Add(LArtefact);
end;

function TCraChecksTests.HasWarning(const AWarnings: TArray<string>;
  const AText: string): Boolean;
var
  LText: string;
begin
  Result := False;
  for LText in AWarnings do
    if LText = AText then
      Exit(True);
end;

procedure TCraChecksTests.Warn_NoSupplier;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LMetadata.Supplier := '';
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, cNoSupplier));
    Assert.IsFalse(HasWarning(LWarnings, SupplierContactWarning('Acme GmbH')));
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.Warn_SupplierWithoutContact;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
  LExpected: string;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LMetadata.SupplierUrl := '';
    LExpected := SupplierContactWarning('Acme GmbH');
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, LExpected));
    Assert.IsFalse(HasWarning(LWarnings, cNoSupplier));
    Assert.AreEqual(1, Integer(Length(LWarnings)));
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.Warn_NoSbomCreator;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LMetadata.SbomCreator := '';
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, cNoSbomCreator));
    Assert.AreEqual(1, Integer(Length(LWarnings)));

    LMetadata.SbomCreator := 'Acme GmbH';
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, cNoSbomCreator),
      'A creator that is neither an email nor a URL is missing');
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.Warn_NoVersion;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LMetadata.ProductVersion := '';
    LConfig.ProductVersion := '';
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, cNoVersion));
    Assert.IsFalse(HasWarning(LWarnings, cDefaultVersion));

    LMetadata.ProductVersion := '0.0.0.0';
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, cNoVersion), '0.0.0.0 is no version');
    Assert.IsFalse(HasWarning(LWarnings, cDefaultVersion));
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.Warn_DefaultVersion;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LMetadata.ProductVersion := '1.0.0.0';
    LConfig.ProductVersion := '';
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, cDefaultVersion));
    Assert.IsFalse(HasWarning(LWarnings, cNoVersion));
    Assert.AreEqual(1, Integer(Length(LWarnings)));

    Include(LConfig.ExplicitOverrides, scoProductVersion);
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, cDefaultVersion),
      'An empty --version still leaves 1.0.0.0 as the project default');
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.Warn_NoLicence;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LMetadata.Licence := '';
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, cNoLicence));
    Assert.AreEqual(1, Integer(Length(LWarnings)));
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.Warn_DeployableNotHashed;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
  LArtefact: TArtefactInfo;
  LExpected: string;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LArtefacts.Clear;
    LExpected := DeployableWarning(cOutputPath);
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, LExpected));
    Assert.AreEqual(1, Integer(Length(LWarnings)));

    LArtefact := Default(TArtefactInfo);
    LArtefact.FilePath := cOutputPath;
    LArtefact.RelativePath := 'AcmeApp.exe';
    LArtefact.ArtefactType := 'application';
    LArtefacts.Add(LArtefact);
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsTrue(HasWarning(LWarnings, LExpected),
      'An output file with no hash is still missing');

    LArtefact.HashSha512 := 'deadbeef';
    LArtefacts[0] := LArtefact;
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsFalse(HasWarning(LWarnings, LExpected));
    Assert.AreEqual(0, Integer(Length(LWarnings)));
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.CompleteInput_NoWarnings;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.AreEqual(0, Integer(Length(LWarnings)));
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.ExplicitDefaultVersion_NoDefaultWarning;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LMetadata.ProductVersion := '1.0.0.0';
    LConfig.ProductVersion := '1.0.0.0';
    Include(LConfig.ExplicitOverrides, scoProductVersion);
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsFalse(HasWarning(LWarnings, cDefaultVersion));
    Assert.IsFalse(HasWarning(LWarnings, cNoVersion));
    Assert.AreEqual(0, Integer(Length(LWarnings)));

    Exclude(LConfig.ExplicitOverrides, scoProductVersion);
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsFalse(HasWarning(LWarnings, cDefaultVersion),
      'product.version 1.0.0.0 is an explicit version');
  finally
    LArtefacts.Free;
  end;
end;

procedure TCraChecksTests.EmailSupplier_NoContactWarning;
var
  LConfig: TSbomConfig;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LArtefacts: TArtefactList;
  LWarnings: TArray<string>;
begin
  LArtefacts := TArtefactList.Create;
  try
    FillComplete(LConfig, LMetadata, LProject, LArtefacts);
    LMetadata.Supplier := ' release@acme.example ';
    LMetadata.SupplierUrl := '';
    LWarnings := BuildCraMetadataWarnings(LConfig, LMetadata, LProject, LArtefacts);
    Assert.IsFalse(HasWarning(LWarnings,
      SupplierContactWarning('release@acme.example')));
    Assert.IsFalse(HasWarning(LWarnings, cNoSupplier));
    Assert.AreEqual(0, Integer(Length(LWarnings)));
  finally
    LArtefacts.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCraChecksTests);

end.
