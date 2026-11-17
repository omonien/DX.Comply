/// <summary>
/// dxcomply
/// Command-line entry point for DX.Comply SBOM generation in CI/CD workflows.
/// </summary>
///
/// <remarks>
/// Parses command-line arguments via TCliOptions, constructs a
/// TDxComplyGenerator with the resulting TSbomConfig, and writes the SBOM to
/// the requested output path so pipeline runs do not depend on the IDE plugin.
///
/// Exit codes:
///   0 - SBOM generated successfully, or --cpe-lookup found no error
///   1 - Generation failed, the NVD search failed, or the CPE files could
///       not be written. --no-build uses this code when a build would run.
///   2 - Invalid arguments
///   3 - SBOM generated, but --strict is set and a CRA/BSI warning was raised.
///       Used only when a requested CPE dictionary file was written as well.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

program dxcomply;

{$APPTYPE CONSOLE}

{$R 'dxcomply.res'}

uses
  DX.Comply.Locale.EN, // Must be first — forces English RTL messages
  System.SysUtils,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.Cpe,
  DX.Comply.Cpe.Nvd,
  DX.Comply.Cpe.NvdKey,
  DX.Comply.CLI.Options in 'DX.Comply.CLI.Options.pas',
  DX.Comply.CLI.GitTag in 'DX.Comply.CLI.GitTag.pas';

const
  cExitStrictWarnings = 3;

// ---------------------------------------------------------------------------
// CPE lookup. Does not write an SBOM.
// ---------------------------------------------------------------------------

function RunCpeLookup(AOptions: TCliOptions;
  const AResolution: TConfigPathResolution): Boolean;
var
  LConfig: TSbomConfig;
  LGenerator: TDxComplyGenerator;
  LSubmission: TCpeSubmission;
  LResolved: TNvdApiKeyResolution;
  LSearch: TNvdCpeSearchResult;
  LKeyword: string;
begin
  Result := False;
  LConfig := AOptions.ToSbomConfig;
  if AOptions.CiMode and AResolution.Found then
  begin
    LGenerator := TDxComplyGenerator.Create;
    try
      LConfig := LGenerator.MergedConfig(AOptions.ToSbomConfig, AResolution.Path);
    finally
      LGenerator.Free;
    end;
  end;

  LSubmission.Vendor := LConfig.Supplier;
  LSubmission.Product := LConfig.ProductName;
  LSubmission.Version := LConfig.ProductVersion;
  LSubmission.References := CpeReferencesFromUrls(LConfig.SupplierUrl, LConfig.RepoUrl);
  FillEmptyCpeNamesFromProject(AOptions.Project, LConfig.Platform,
    LConfig.Configuration, LSubmission);
  LKeyword := CpeLookupKeyword(LSubmission.Vendor, LSubmission.Product);
  if LKeyword = '' then
  begin
    Writeln('Error: --cpe-lookup needs a vendor and a product. Set product.supplier and product.name, or pass --supplier and --product.');
    ExitCode := 2;
    Exit;
  end;

  LResolved := ResolveNvdApiKey(AOptions.NvdApiKey, nil);
  LSearch := SearchNvdCpes(LKeyword, LResolved.Key);
  Writeln(FormatNvdCpeLookupReport(LKeyword, NvdApiKeyLogLine(LResolved), LSearch));
  if not LSearch.IsSuccess then
  begin
    Writeln('Error: ', LSearch.Error);
    ExitCode := 1;
    Exit;
  end;
  Result := True;
  ExitCode := 0;
end;

procedure OnProgress(const AMessage: string; const AProgress: Integer);
begin
  if AProgress < 0 then
    Writeln('[ERROR] ', AMessage)
  else if AProgress = 100 then
    Writeln('[DONE ] ', AMessage)
  else if AMessage.StartsWith('Warning:', True) then
    Writeln('[WARN ] ', AMessage)
  else if AMessage.StartsWith('Info: ', True) then
    Writeln('[INFO ] ', AMessage.Substring(Length('Info: ')))
  else
    Writeln(Format('[%3d%%] %s', [AProgress, AMessage]));
end;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

var
  LOptions: TCliOptions;
  LGenerator: TDxComplyGenerator;
  LConfig: TSbomConfig;
  LSuccess: Boolean;
  LVerbose: Boolean;
  LLibraryWithoutProject: Boolean;
  LFileConfig: TSbomConfig;
  LPeek: TDxComplyGenerator;
  LGitTagWarning: string;
  LConfigResolution: TConfigPathResolution;
  LConfigWarning: string;
  {$IFNDEF CI}
  LNoPause: Boolean;
  {$ENDIF}

begin
  LOptions := TCliOptions.Create;
  try
    if not LOptions.Parse then
    begin
      if LOptions.ParseError <> '' then
      begin
        Writeln('Error: ', LOptions.ParseError);
        Writeln(TCliOptions.UsageHint);
        ExitCode := 2;
        Exit;
      end;
    end;

    if LOptions.Help then
    begin
      LOptions.PrintHelp;
      Exit;
    end;

    // A relative config path used to be TFile.Exists against the working
    // directory only. A batch file started elsewhere then ignored the
    // .dxcomply.json next to the project. The folder of dxcomply.exe is
    // not searched. The warning is not a CRA/BSI warning, so --strict still
    // exits with code 3 only when one of those warnings was raised.
    LConfigResolution := TCliOptions.ResolveConfigPath(
      LOptions.ConfigFile, LOptions.Project);
    LConfigWarning := TCliOptions.ConfigFileWarning(LOptions.CiMode, LConfigResolution);
    if LConfigWarning <> '' then
      Writeln(LConfigWarning);

    if LOptions.CpeLookup then
    begin
      if not RunCpeLookup(LOptions, LConfigResolution) then
        Exit;
      if not LOptions.CpeDictionary then
        Exit;
    end;

    if LOptions.Project = '' then
    begin
      // --library and --source-dir on the command line are enough.
      // With --ci the same keys may be present only in the config file.
      LConfig := LOptions.ToSbomConfig;
      LLibraryWithoutProject := LConfig.LibraryMode and
        (Length(LConfig.SourceDirs) > 0);
      if (not LLibraryWithoutProject) and LOptions.CiMode and
         LConfigResolution.Found then
      begin
        LPeek := TDxComplyGenerator.Create;
        try
          LFileConfig := LPeek.LoadConfig(LConfigResolution.Path);
        finally
          LPeek.Free;
        end;
        if scoLibraryMode in LConfig.ExplicitOverrides then
          LFileConfig.LibraryMode := LConfig.LibraryMode;
        if scoSourceDirs in LConfig.ExplicitOverrides then
          LFileConfig.SourceDirs := LConfig.SourceDirs;
        LLibraryWithoutProject := LFileConfig.LibraryMode and
          (Length(LFileConfig.SourceDirs) > 0);
      end;
      if not LLibraryWithoutProject then
      begin
        Writeln('Error: --project is required.');
        Writeln(TCliOptions.UsageHint);
        ExitCode := 2;
        Exit;
      end;
    end;

    {$IFNDEF CI}
    // Capture before the try/finally so it is accessible after LOptions.Free.
    LNoPause := LOptions.NoPause;
    {$ENDIF}
    // Capture verbose flag before LOptions is freed.
    LVerbose := LOptions.Verbose;
    LConfig  := LOptions.ToSbomConfig;

    // --version-from-git-tag: an explicit --version still wins. Without git
    // or a tag the warning is printed and the usual version source is used.
    if LOptions.VersionFromGitTag then
    begin
      if ApplyVersionFromGitTag(LConfig, LOptions.GitTagDirectory, LGitTagWarning) then
      begin
        if LVerbose then
          Writeln('Version from git tag: ', LConfig.ProductVersion);
      end
      else if LGitTagWarning <> '' then
        OnProgress(LGitTagWarning, 0);
    end;

    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress :=
        procedure(const AMessage: string; const AProgress: Integer)
        begin
          // Without --verbose only errors, warnings and the final done
          // message are printed. Warnings (e.g. the Deep-Evidence rebuild
          // was skipped) must always reach the user — issue #29/#31.
          if LVerbose
            or (AProgress < 0)
            or (AProgress = 100)
            or AMessage.StartsWith('Warning:', True)
            or AMessage.StartsWith('Info: ', True)
            or AMessage.StartsWith('[WARN', True) then
            OnProgress(AMessage, AProgress);
        end;

      // With --ci, the file fills defaults and any flag the user actually
      // passed (recorded on TSbomConfig.ExplicitOverrides) wins. Issue #50.
      if LOptions.CiMode and LConfigResolution.Found then
      begin
        LSuccess := LGenerator.GenerateFromConfig(LOptions.Project, LConfigResolution.Path);
        LConfig := LGenerator.Config;
      end
      else
        LSuccess := LGenerator.Generate(LOptions.Project, LConfig.OutputPath, LConfig.Format);

      if LSuccess then
      begin
        Writeln('SBOM generated: ', LConfig.OutputPath);
        ExitCode := 0;
        var LDictionaryWritten := not LOptions.CpeDictionary;
        if LOptions.CpeDictionary then
        begin
          var LSubmission: TCpeSubmission;
          var LDictionaryPath, LMailPath, LFileError: string;
          LSubmission.Vendor := LConfig.Supplier;
          LSubmission.Product := LConfig.ProductName;
          LSubmission.Version := LConfig.ProductVersion;
          LSubmission.References := CpeReferencesFromUrls(LConfig.SupplierUrl, LConfig.RepoUrl);
          FillEmptyCpeNamesFromProject(LOptions.Project, LConfig.Platform,
            LConfig.Configuration, LSubmission);
          if WriteCpeSubmissionFiles(LConfig.OutputPath, LOptions.Project, LSubmission,
            LDictionaryPath, LMailPath, LFileError) then
          begin
            Writeln('CPE dictionary: ', LDictionaryPath);
            Writeln('CPE mail text: ', LMailPath);
            Writeln('DX.Comply does not send the message.');
            LDictionaryWritten := True;
          end
          else
          begin
            Writeln('Error: Could not write the CPE dictionary files. ', LFileError);
            ExitCode := 1;
          end;
        end;
        // Issue #111: the SBOM and report are written, then strict mode fails
        // the run on any CRA/BSI warning with its own exit code. A failed
        // dictionary write keeps exit code 1.
        var LCraWarnings := LGenerator.CraWarnings;
        if LDictionaryWritten and LConfig.StrictMode and (Length(LCraWarnings) > 0) then
        begin
          Writeln(Format('Strict mode: %d CRA/BSI warning(s):', [Length(LCraWarnings)]));
          for var LWarning in LCraWarnings do
          begin
            Writeln('  - ', LWarning);
          end;
          ExitCode := cExitStrictWarnings;
        end;
      end
      else
      begin
        Writeln('Error: SBOM generation failed.');
        ExitCode := 1;
      end;
    finally
      LGenerator.Free;
    end;
  finally
    LOptions.Free;
  end;

  {$IFNDEF CI}
  if not LNoPause then
  begin
    Write('Press <Enter> to quit.');
    Readln;
  end;
  {$ENDIF}
end.
