/// <summary>
/// DX.Comply.Tests
/// DUnitX console test runner for DX.Comply.
/// </summary>
///
/// <remarks>
/// Registers all test fixtures and executes them via DUnitX.
/// Exit code is set to EXIT_ERRORS when any test fails,
/// enabling CI pipelines to detect failures automatically.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

program DX.Comply.Tests;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  DX.Comply.Tests.BuildEvidence.Intf in 'DX.Comply.Tests.BuildEvidence.Intf.pas',
  DX.Comply.Tests.BuildEvidence.Reader in 'DX.Comply.Tests.BuildEvidence.Reader.pas',
  DX.Comply.Tests.HashService in 'DX.Comply.Tests.HashService.pas',
  DX.Comply.Tests.FileScanner in 'DX.Comply.Tests.FileScanner.pas',
  DX.Comply.Tests.ProjectScanner in 'DX.Comply.Tests.ProjectScanner.pas',
  DX.Comply.Tests.CycloneDx.Writer in 'DX.Comply.Tests.CycloneDx.Writer.pas',
  DX.Comply.Tests.CycloneDx.XmlWriter in 'DX.Comply.Tests.CycloneDx.XmlWriter.pas',
  DX.Comply.Tests.Spdx.Writer in 'DX.Comply.Tests.Spdx.Writer.pas',
  DX.Comply.Tests.Schema.Validator in 'DX.Comply.Tests.Schema.Validator.pas',
  DX.Comply.Tests.Engine in 'DX.Comply.Tests.Engine.pas';

var
  LRunner: ITestRunner;
  LResults: IRunResults;
  LLogger: ITestLogger;
  LNunitLogger: ITestLogger;

begin
  try
    TDUnitX.RegisterTestFixture(THashServiceTests);
    TDUnitX.RegisterTestFixture(TCycloneDxWriterTests);
    TDUnitX.RegisterTestFixture(TCycloneDxXmlWriterTests);
    TDUnitX.RegisterTestFixture(TSpdxWriterTests);
    TDUnitX.RegisterTestFixture(TSchemaValidatorTests);
    // Other fixtures register themselves via the initialization section
    // and the [TestFixture] attribute — picked up through LRunner.UseRTTI.

    LRunner := TDUnitX.CreateRunner;
    LRunner.UseRTTI := True;
    LLogger := TDUnitXConsoleLogger.Create(True);
    LNunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    LRunner.AddLogger(LLogger);
    LRunner.AddLogger(LNunitLogger);
    LRunner.FailsOnNoAsserts := False;

    LResults := LRunner.Execute;
    if not LResults.AllPassed then
      ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    System.Write('Done. Press <Enter> key to quit.');
    System.Readln;
    {$ENDIF}
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      ExitCode := EXIT_ERRORS;
    end;
  end;
end.
