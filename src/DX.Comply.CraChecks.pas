/// <summary>
/// DX.Comply.CraChecks
/// Non-fatal CRA and BSI header and component warnings.
/// </summary>
///
/// <remarks>
/// BuildCraMetadataWarnings looks at the metadata that will be written and
/// at the hashed artefacts. It does not read the project from disk. A missing
/// deployable is an artefact with no hash, or no artefact for that path.
/// The caller prints each line and still writes the SBOM.
///
/// BuildThirdPartyComponentWarnings looks at third-party units and names
/// those without supplier or licence, grouped by unit prefix or manifest
/// library (issue #110).
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.CraChecks;

interface

uses
  DX.Comply.ComponentManifest,
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

/// <summary>
/// True for a warning from BuildCraMetadataWarnings that asks for SBOM
/// header data the user can enter (supplier, supplier URL, SBOM creator,
/// version, licence). False for the missing deployable and anything else.
/// A leading "Warning:" as written by the progress callback is ignored.
/// </summary>
function IsSbomHeaderWarning(const AText: string): Boolean;

/// <summary>
/// Warnings for third-party units (Origin "Third party") that have no
/// supplier or no licence. A unit gets both only from a component manifest
/// row. Units without a row are grouped by unit prefix, units of a row that
/// lacks vendor or licence by that row. At most cMaxComponentWarningGroups
/// groups are listed; one more line counts the rest. BSI TR-03183-2
/// sections 5.2.2 and 6.1.
/// </summary>
function BuildThirdPartyComponentWarnings(const AConfig: TSbomConfig;
  const AManifest: TComponentManifest; const AArtefacts: TArtefactList): TArray<string>;

/// <summary>
/// Group key of a unit name without a manifest row: the text before the
/// first dot, else the leading part up to the second capital letter
/// (JvComponent gives Jv, JclBase gives Jcl). A name without a second
/// capital is its own key.
/// </summary>
function ThirdPartyUnitPrefix(const AUnitName: string): string;

const
  /// <summary>Start of every warning from BuildThirdPartyComponentWarnings.</summary>
  cThirdPartyWarningPrefix = 'CRA/BSI: Third-party ';
  /// <summary>Groups listed one by one before the rest is counted.</summary>
  cMaxComponentWarningGroups = 10;
  /// <summary>
  /// Menu path of the IDE dialog that edits the SBOM header data. The IDE
  /// warning texts name it.
  /// </summary>
  cIdeSbomHeaderDialogPath = 'Project > DX.Comply - SBOM > SBOM Header Data';

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

const
  cNoSupplierBody =
    'CRA/BSI: The SBOM names no supplier for the product. BSI TR-03183-2 section 5.2.2 requires the component creator, and CRA Annex II point 1 requires the name and contact of the manufacturer. ';
  cNoSupplierCli =
    'Pass --supplier=<name>, set product.supplier in .dxcomply.json, or fill CompanyName in the project version info.';
  cNoSupplierIde =
    'Enter the supplier in ' + cIdeSbomHeaderDialogPath + ', or fill CompanyName in the project version info.';
  cNoSbomCreatorBody =
    'CRA/BSI: The SBOM creator contact is missing. BSI TR-03183-2 section 5.2.1 requires the email address or URL of the entity that created the SBOM. ';
  cNoSbomCreatorCli =
    'Pass --sbom-creator=<email-or-url> or set sbomCreator in .dxcomply.json.';
  cNoSbomCreatorIde =
    'Enter the SBOM creator in ' + cIdeSbomHeaderDialogPath + '.';
  cNoVersionBody =
    'CRA/BSI: The product has no version. BSI TR-03183-2 section 5.2.2 requires the component version, and CRA Annex II point 3 requires information that identifies the product uniquely. ';
  cNoVersionCli =
    'Pass --version=<version>, set product.version in .dxcomply.json, or set the version info in the project options.';
  cNoVersionIde =
    'Set the version info in the project options, or enter a product version in ' + cIdeSbomHeaderDialogPath + '.';
  cDefaultVersionBody =
    'CRA/BSI: The product version is 1.0.0.0, the Delphi default for new projects. BSI TR-03183-2 section 5.2.2 requires the version the creator uses to tell releases apart, and CRA Annex II point 3 requires information that identifies the product uniquely. ';
  cDefaultVersionCli =
    'If 1.0.0.0 is not the real release version, pass --version=<version>, set product.version in .dxcomply.json, or update the version info in the project options.';
  cDefaultVersionIde =
    'If 1.0.0.0 is not the real release version, update the version info in the project options, or enter a product version in ' + cIdeSbomHeaderDialogPath + '.';
  cNoLicenceBody =
    'CRA/BSI: The product has no distribution licence. BSI TR-03183-2 section 5.2.2 requires the distribution licences of each component, named by SPDX identifier (section 6.1). ';
  cNoLicenceCli =
    'Pass --licence=<SPDX expression> or set product.licence in .dxcomply.json.';
  cNoLicenceIde =
    'Enter the licence in ' + cIdeSbomHeaderDialogPath + '.';
  cSupplierContactCli =
    'Pass --supplier-url=<url> or set product.supplierUrl in .dxcomply.json.';
  cSupplierContactIde =
    'Enter the supplier URL in ' + cIdeSbomHeaderDialogPath + '.';
  cDeployablePrefix = 'CRA/BSI: The built file ';

function ForContext(const AContext: TSbomWarningContext;
  const ABody, ACliHint, AIdeHint: string): string;
begin
  if AContext = swcIde then
  begin
    Result := ABody + AIdeHint;
  end
  else
  begin
    Result := ABody + ACliHint;
  end;
end;

function SupplierContactWarning(const ASupplier: string;
  const AContext: TSbomWarningContext): string;
begin
  Result := ForContext(AContext, 'CRA/BSI: The supplier "' + ASupplier +
    '" has no email address or URL. BSI TR-03183-2 section 5.2.2 requires the component creator as an email address, or a URL when there is none, and CRA Annex II point 1 requires an email address or other digital contact of the manufacturer. ',
    cSupplierContactCli, cSupplierContactIde);
end;

function DeployableWarning(const APath: string;
  const AContext: TSbomWarningContext): string;
begin
  Result := ForContext(AContext, cDeployablePrefix + APath +
    ' was not found, so the SBOM has no hash for it. BSI TR-03183-2 section 5.2.2 requires the SHA-512 of the deployable component, and CRA Annex I Part II point 1 requires an SBOM of the product. ',
    'Build the project first, or check the output directory, --platform and --config-name.',
    'Build the project first, or check the output directory and the active platform and configuration.');
end;

function IsSbomHeaderWarning(const AText: string): Boolean;
var
  LText: string;
begin
  LText := Trim(AText);
  if LText.StartsWith('Warning:', True) then
  begin
    LText := Trim(Copy(LText, Length('Warning:') + 1, MaxInt));
  end;
  Result := LText.StartsWith('CRA/BSI:') and not LText.StartsWith(cDeployablePrefix) and
    not LText.StartsWith(cThirdPartyWarningPrefix);
end;

function ThirdPartyUnitPrefix(const AUnitName: string): string;
begin
  var LName := Trim(AUnitName);
  var LDot := Pos('.', LName);
  if LDot > 1 then
    Exit(Copy(LName, 1, LDot - 1));
  for var i := 2 to Length(LName) do
  begin
    if CharInSet(LName[i], ['A'..'Z']) then
      Exit(Copy(LName, 1, i - 1));
  end;
  Result := LName;
end;

function JoinNames(const ANames: TList<string>): string;
const
  cShown = 5;
begin
  Result := '';
  for var i := 0 to ANames.Count - 1 do
  begin
    if i = cShown then
    begin
      Result := Result + ', ...';
      Break;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + ANames[i];
  end;
end;

function UnitCountText(ACount: Integer): string;
begin
  if ACount = 1 then
  begin
    Result := '1 unit';
  end
  else
  begin
    Result := IntToStr(ACount) + ' units';
  end;
end;

function BuildThirdPartyComponentWarnings(const AConfig: TSbomConfig;
  const AManifest: TComponentManifest; const AArtefacts: TArtefactList): TArray<string>;
const
  cRule = ' BSI TR-03183-2 sections 5.2.2 and 6.1 require the creator and the distribution licence of each component. ';
  cHintCli = 'Add a row for them to a component manifest (components.json) and pass --manifest=<file> or set manifest in .dxcomply.json. See README, section Component manifest.';
  cHintIde = 'Add a row for them to a component manifest (components.json) next to the project. See README, section Component manifest.';
begin
  Result := nil;
  if not Assigned(AArtefacts) then
    Exit;

  // Key: 'p:' + prefix for units without a row, 'm:' + index for a row.
  // Unit names are not case-sensitive, so jclBase and JclSysUtils share a group.
  var LGroups := TObjectDictionary<string, TList<string>>.Create([doOwnsValues],
    TIStringComparer.Ordinal);
  var LOrder := TList<string>.Create;
  var LWarnings := TList<string>.Create;
  try
    for var i := 0 to AArtefacts.Count - 1 do
    begin
      var LArtefact := AArtefacts[i];
      if not SameText(LArtefact.ArtefactType, 'unit-evidence') or
         not SameText(LArtefact.Origin, 'Third party') then
        Continue;
      var LUnitName := ArtefactUnitName(LArtefact);
      if LUnitName = '' then
        Continue;

      var LMatch := MatchManifestUnit(AManifest, LUnitName,
        ArtefactFolderPath(LArtefact));
      var LKey: string;
      case LMatch.Kind of
        mmOwnCode:
          Continue;
        mmLibrary:
          begin
            var LEntry := AManifest.Components[LMatch.ComponentIndex];
            if (Trim(LEntry.Vendor) <> '') and (Trim(LEntry.Licence) <> '') then
              Continue;
            LKey := 'm:' + IntToStr(LMatch.ComponentIndex);
          end;
      else
        LKey := 'p:' + ThirdPartyUnitPrefix(LUnitName);
      end;

      var LNames: TList<string>;
      if not LGroups.TryGetValue(LKey, LNames) then
      begin
        LNames := TList<string>.Create;
        LGroups.Add(LKey, LNames);
        LOrder.Add(LKey);
      end;
      LNames.Add(LUnitName);
    end;

    var LHint: string;
    if AConfig.WarningContext = swcIde then
    begin
      LHint := cHintIde;
    end
    else
    begin
      LHint := cHintCli;
    end;

    var LRestGroups := 0;
    var LRestUnits := 0;
    for var i := 0 to LOrder.Count - 1 do
    begin
      var LNames := LGroups[LOrder[i]];
      if i >= cMaxComponentWarningGroups then
      begin
        Inc(LRestGroups);
        Inc(LRestUnits, LNames.Count);
        Continue;
      end;
      if LOrder[i].StartsWith('m:') then
      begin
        var LEntry := AManifest.Components[StrToInt(Copy(LOrder[i], 3, MaxInt))];
        var LMissing: string;
        if Trim(LEntry.Vendor) = '' then
        begin
          LMissing := 'no supplier (vendor)';
        end;
        if Trim(LEntry.Licence) = '' then
        begin
          if LMissing <> '' then
          begin
            LMissing := LMissing + ' and ';
          end;
          LMissing := LMissing + 'no licence';
        end;
        LWarnings.Add(cThirdPartyWarningPrefix + 'library "' + LEntry.Name + '" in the component manifest has ' +
          LMissing + ', ' + UnitCountText(LNames.Count) + ' (' + JoinNames(LNames) + ').' + cRule +
          'Fill vendor and licence for that row.');
      end
      else
      begin
        LWarnings.Add(cThirdPartyWarningPrefix + 'units with prefix "' + Copy(LOrder[i], 3, MaxInt) +
          '" have no supplier and no licence, ' + UnitCountText(LNames.Count) + ' (' + JoinNames(LNames) +
          ').' + cRule + LHint);
      end;
    end;
    if LRestGroups > 0 then
    begin
      LWarnings.Add(cThirdPartyWarningPrefix + 'units in ' + IntToStr(LRestGroups) +
        ' more groups have no supplier or no licence, ' + UnitCountText(LRestUnits) + '.' + cRule + LHint);
    end;
    Result := LWarnings.ToArray;
  finally
    LWarnings.Free;
    LOrder.Free;
    LGroups.Free;
  end;
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
  var LContext := AConfig.WarningContext;
  LWarnings := TList<string>.Create;
  try
    LSupplier := Trim(AMetadata.Supplier);
    if LSupplier = '' then
    begin
      Add(ForContext(LContext, cNoSupplierBody, cNoSupplierCli, cNoSupplierIde));
    end
    else if (Trim(AMetadata.SupplierUrl) = '') and
            not IsBsiEmailAddress(LSupplier) then
    begin
      Add(SupplierContactWarning(LSupplier, LContext));
    end;

    if BsiCreatorKind(AMetadata.SbomCreator) = '' then
    begin
      Add(ForContext(LContext, cNoSbomCreatorBody, cNoSbomCreatorCli, cNoSbomCreatorIde));
    end;

    LVersion := Trim(AMetadata.ProductVersion);
    if (LVersion = '') or (LVersion = '0.0.0.0') then
    begin
      Add(ForContext(LContext, cNoVersionBody, cNoVersionCli, cNoVersionIde));
    end
    else if (LVersion = '1.0.0.0') and (Trim(AConfig.ProductVersion) = '') then
    begin
      Add(ForContext(LContext, cDefaultVersionBody, cDefaultVersionCli, cDefaultVersionIde));
    end;

    if Trim(AMetadata.Licence) = '' then
    begin
      Add(ForContext(LContext, cNoLicenceBody, cNoLicenceCli, cNoLicenceIde));
    end;

    // Library mode has no deliverable binary. A package project still
    // names a .bpl that was never built.
    if not AConfig.LibraryMode then
    begin
      LOutput := Trim(AProjectInfo.OutputFilePath);
      if (LOutput <> '') and not DeployableWasHashed(LOutput, AArtefacts) then
        Add(DeployableWarning(LOutput, LContext));
    end;

    Result := LWarnings.ToArray;
  finally
    LWarnings.Free;
  end;
end;

end.
