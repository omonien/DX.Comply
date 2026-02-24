/// <summary>
/// dxcomply
/// Command-line entry point for DX.Comply SBOM generation.
/// </summary>
///
/// <remarks>
/// Parses command-line arguments via TCliOptions, constructs a
/// TDxComplyGenerator with the resulting TSbomConfig, and writes the SBOM to
/// the requested output path.
///
/// Exit codes:
///   0 - SBOM generated successfully
///   1 - Generation failed
///   2 - Invalid arguments
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

program dxcomply;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.IOUtils,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.CLI.Options in 'DX.Comply.CLI.Options.pas';

// ---------------------------------------------------------------------------
// Progress callback — negative progress signals an error
// ---------------------------------------------------------------------------

procedure OnProgress(const AMessage: string; const AProgress: Integer);
begin
  if AProgress < 0 then
    Writeln('[ERROR] ', AMessage)
  else if AProgress = 100 then
    Writeln('[DONE ] ', AMessage)
  else
    Writeln(Format('[%3d%%] %s', [AProgress, AMessage]));
end;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

var
  LNoPause: Boolean;
  LOptions: TCliOptions;
  LGenerator: TDxComplyGenerator;
  LConfig: TSbomConfig;
  LSuccess: Boolean;

begin
  LNoPause := False;
  LOptions := TCliOptions.Create;
  try
    if not LOptions.Parse then
    begin
      if LOptions.ParseError <> '' then
      begin
        Writeln('Error: ', LOptions.ParseError);
        Writeln('Run dxcomply --help for usage.');
        ExitCode := 2;
        Exit;
      end;
    end;

    if LOptions.Help then
    begin
      LOptions.PrintHelp;
      Exit;
    end;

    if LOptions.Project = '' then
    begin
      Writeln('Error: --project is required.');
      Writeln('Run dxcomply --help for usage.');
      ExitCode := 2;
      Exit;
    end;

    // Capture before the try/finally so it is accessible after LOptions.Free
    LNoPause := LOptions.NoPause;
    LConfig  := LOptions.ToSbomConfig;

    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress :=
        procedure(const AMessage: string; const AProgress: Integer)
        begin
          OnProgress(AMessage, AProgress);
        end;

      if LOptions.CiMode and TFile.Exists(LOptions.ConfigFile) then
        LSuccess := LGenerator.GenerateFromConfig(LOptions.Project, LOptions.ConfigFile)
      else
        LSuccess := LGenerator.Generate(LOptions.Project, LConfig.OutputPath, LConfig.Format);

      if LSuccess then
      begin
        Writeln('SBOM generated: ', LConfig.OutputPath);
        ExitCode := 0;
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
