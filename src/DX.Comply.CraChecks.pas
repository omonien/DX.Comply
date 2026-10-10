/// <summary>
/// DX.Comply.CraChecks
/// Non-fatal CRA and BSI header warnings.
/// </summary>
///
/// <remarks>
/// BuildCraMetadataWarnings looks at the metadata that will be written and
/// at the hashed artefacts. It does not read the project from disk. A missing
/// deployable is an artefact with no hash, or no artefact for that path.
/// The caller prints each line and still writes the SBOM.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.CraChecks;

interface

uses
  DX.Comply.Engine,
  DX.Comply.Engine.Intf;

/// <summary>
/// Warnings for a product header that does not yet meet CRA Annex II and
/// BSI TR-03183-2 sections 5.2.1 and 5.2.2. The order is supplier, SBOM
/// creator, version, distribution licence, then the deployable hash.
/// A version counts as explicit when AConfig.ProductVersion is not empty.
/// That field is set by --version and by product.version. The project
/// version is copied onto metadata only when the config version is empty,
/// so 1.0.0.0 from the project file is the Delphi default and 1.0.0.0
/// passed in is not.
/// </summary>
function BuildCraMetadataWarnings(const AConfig: TSbomConfig;
  const AMetadata: TSbomMetadata; const AProjectInfo: TProjectInfo;
  const AArtefacts: TArtefactList): TArray<string>;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections;

const
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
begin
  Result := 'CRA/BSI: The supplier "' + ASupplier +
    '" has no email address or URL. BSI TR-03183-2 section 5.2.2 requires the component creator as an email address, or a URL when there is none, and CRA Annex II point 1 requires an email address or other digital contact of the manufacturer. Pass --supplier-url=<url> or set product.supplierUrl in .dxcomply.json.';
end;

function DeployableWarning(const APath: string): string;
begin
  Result := 'CRA/BSI: The built file ' + APath +
    ' was not found, so the SBOM has no hash for it. BSI TR-03183-2 section 5.2.2 requires the SHA-512 of the deployable component, and CRA Annex I Part II point 1 requires an SBOM of the product. Build the project first, or check the output directory, --platform and --config-name.';
end;

function ArtefactIsHashed(const AArtefact: TArtefactInfo): Boolean;
begin
  Result := (Trim(AArtefact.Hash) <> '') or (Trim(AArtefact.HashSha512) <> '');
end;

function SameOutputName(const ALeft, ARight: string): Boolean;
var
  LLeft, LRight: string;
begin
  LLeft := TPath.GetFileName(ALeft);
  LRight := TPath.GetFileName(ARight);
  Result := (LLeft <> '') and (LRight <> '') and SameText(LLeft, LRight);
end;

function DeployableWasHashed(const AOutputFilePath: string;
  const AArtefacts: TArtefactList): Boolean;
var
  I: Integer;
  LArtefact: TArtefactInfo;
begin
  Result := False;
  if (Trim(AOutputFilePath) = '') or not Assigned(AArtefacts) then
    Exit;

  for I := 0 to AArtefacts.Count - 1 do
  begin
    LArtefact := AArtefacts[I];
    if not ArtefactIsHashed(LArtefact) then
      Continue;
    if SameText(LArtefact.FilePath, AOutputFilePath) or
       SameText(LArtefact.RelativePath, AOutputFilePath) or
       SameOutputName(LArtefact.FilePath, AOutputFilePath) or
       SameOutputName(LArtefact.RelativePath, AOutputFilePath) then
      Exit(True);
  end;
end;

function BuildCraMetadataWarnings(const AConfig: TSbomConfig;
  const AMetadata: TSbomMetadata; const AProjectInfo: TProjectInfo;
  const AArtefacts: TArtefactList): TArray<string>;
var
  LWarnings: TList<string>;
  LSupplier, LVersion, LOutput: string;

  procedure Add(const AText: string);
  begin
    LWarnings.Add(AText);
  end;

begin
  LWarnings := TList<string>.Create;
  try
    LSupplier := Trim(AMetadata.Supplier);
    if LSupplier = '' then
      Add(cNoSupplier)
    else if (Trim(AMetadata.SupplierUrl) = '') and
            not IsBsiEmailAddress(LSupplier) then
      Add(SupplierContactWarning(LSupplier));

    if BsiCreatorKind(AMetadata.SbomCreator) = '' then
      Add(cNoSbomCreator);

    LVersion := Trim(AMetadata.ProductVersion);
    if (LVersion = '') or (LVersion = '0.0.0.0') then
      Add(cNoVersion)
    else if (LVersion = '1.0.0.0') and (Trim(AConfig.ProductVersion) = '') then
      Add(cDefaultVersion);

    if Trim(AMetadata.Licence) = '' then
      Add(cNoLicence);

    // Library mode has no deliverable binary. A package project still
    // names a .bpl that was never built.
    if not AConfig.LibraryMode then
    begin
      LOutput := Trim(AProjectInfo.OutputFilePath);
      if (LOutput <> '') and not DeployableWasHashed(LOutput, AArtefacts) then
        Add(DeployableWarning(LOutput));
    end;

    Result := LWarnings.ToArray;
  finally
    LWarnings.Free;
  end;
end;

end.
