/// <summary>
/// DX.Comply.IDE.Wizard
/// Delphi IDE wizard that exposes CRA compliance documentation generation
/// through a dedicated Project menu entry.
/// </summary>
///
/// <remarks>
/// TDxComplyWizard implements IOTAWizard and injects a dedicated submenu
/// into the Project menu so users find the workflow in the most logical place.
///
/// Registration follows the standard designtime package pattern:
///   initialization  - AddWizard
///   finalization    - RemoveWizard
///
/// The Execute method retrieves the active project through
/// IOTAProjectManager.GetCurrentProject, derives the output path next to
/// the .dproj file, and delegates generation to TDxComplyGenerator.
///
/// Progress events are routed to the IDE message window via an anonymous
/// closure that delegates to TIDELogger.Progress.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.Wizard;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.IOUtils,
  System.UITypes,
  Winapi.Windows,
  Winapi.ShellAPI,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Dialogs,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.StdCtrls,
  ToolsAPI,
  DX.Comply.BuildOrchestrator,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.IDE.Settings,
  DX.Comply.ProjectScanner,
  DX.Comply.IDE.Logger,
  DX.Comply.Report.Intf;

type
  /// <summary>
  /// IDE wizard that adds SBOM generation to the Delphi IDE menus.
  /// </summary>
  TDxComplyWizard = class(TInterfacedObject, IOTANotifier, IOTAWizard)
  private
    FOptionsPage: INTAAddInOptions;
    FProjectMenuItem: TMenuItem;
    FProjectMenuSeparator: TMenuItem;
    /// <summary>
    /// Injects the DX.Comply menu items into the main Project menu.
    /// Called once from the constructor.
    /// </summary>
    procedure AddProjectMenuItems;
    /// <summary>
    /// Assigns the DX.Comply bitmap to the Project menu root entry.
    /// </summary>
    procedure AssignProjectMenuBitmap;
    /// <summary>
    /// Removes the previously injected Project menu items on unload.
    /// </summary>
    procedure RemoveProjectMenuItems;
    /// <summary>
    /// Builds the engine configuration from global IDE settings.
    /// </summary>
    function BuildConfig(const AProject: IOTAProject;
      const ASettings: TDXComplyIDESettings; AForceDeepEvidence: Boolean): TSbomConfig;
    /// <summary>
    /// Executes SBOM generation, optionally forcing a Deep-Evidence build.
    /// </summary>
    procedure ExecuteGeneration(AForceDeepEvidence: Boolean);
    /// <summary>
    /// Event handler for the injected Project menu item.
    /// </summary>
    procedure OnProjectMenuItemClick(ASender: TObject);
    /// <summary>
    /// Opens the DX.Comply options page.
    /// </summary>
    procedure OnOptionsMenuItemClick(ASender: TObject);
    /// <summary>
    /// Shows the About dialog.
    /// </summary>
    procedure OnAboutMenuItemClick(ASender: TObject);
    /// <summary>
    /// Opens the configured output in the default browser or shell handler.
    /// </summary>
    function OpenInDefaultBrowser(const ATarget: string): Boolean;
    /// <summary>
    /// Opens the registered Tools &gt; Options page for DX.Comply.
    /// </summary>
    procedure OpenOptionsPage;
    /// <summary>
    /// Resolves the base output path for companion reports next to the SBOM.
    /// </summary>
    function ResolveReportOutputBasePath(const ASbomOutputPath: string;
      const AConfig: THumanReadableReportConfig): string;
    /// <summary>
    /// Resolves the concrete output file path for one report format.
    /// </summary>
    function ResolveReportOutputPath(const AOutputBasePath: string;
      AFormat: THumanReadableReportFormat): string;
    /// <summary>
    /// Saves all modified editors before a Deep-Evidence build.
    /// </summary>
    procedure SaveModifiedFiles;
    /// <summary>
    /// Shows an informational About dialog with a GitHub link.
    /// </summary>
    procedure ShowAboutDialog;
    /// <summary>
    /// Shows the build confirmation dialog and returns True when the user confirms.
    /// </summary>
    function ShowBuildConfirmationDialog(const AProjectPath: string;
      const APlan: TDeepEvidenceBuildPlan; out ADisablePrompt: Boolean): Boolean;
    /// <summary>
    /// Opens the generated HTML report when the current settings request it.
    /// </summary>
    procedure TryOpenHtmlReport(const ASbomOutputPath: string;
      const ASettings: TDXComplyIDESettings; const AConfig: TSbomConfig);
    /// <summary>
    /// Prepares optional Deep-Evidence automation and adjusts the config if the user declines it.
    /// </summary>
    function TryPrepareDeepEvidenceBuild(const AProjectPath: string;
      const ASettings: TDXComplyIDESettings; var AConfig: TSbomConfig;
      AForceDeepEvidence: Boolean): Boolean;
    /// <summary>
    /// Registers the Tools &gt; Options page.
    /// </summary>
    procedure RegisterOptionsPage;
    /// <summary>
    /// Unregisters the Tools &gt; Options page.
    /// </summary>
    procedure UnregisterOptionsPage;
  public
    constructor Create;
    destructor Destroy; override;

    // IOTANotifier
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;

    // IOTAWizard
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

/// <summary>
/// Called automatically by the IDE when the design-time package is installed.
/// Wizard registration is performed in initialization/finalization instead,
/// so this procedure is intentionally empty.
/// </summary>
procedure Register;

implementation

uses
  DX.Comply.IDE.AboutDialog,
  DX.Comply.IDE.BuildConfirmationDialog,
  DX.Comply.IDE.Options,
  DX.Comply.IDE.OptionsFrame,
  DX.Comply.IDE.PathSupport,
  DX.Comply.IDE.ProgressDialog;

var
  /// <summary>
  /// Handle returned by IOTAWizardServices.AddWizard; required for removal in
  /// finalization. Initialised to -1 so that a failed registration is detectable.
  /// </summary>
  GWizardIndex: Integer = -1;
  /// <summary>
  /// Handle returned by IOTAAboutBoxServices.AddPluginInfo; required for removal
  /// in finalization. Initialised to -1 so that a failed registration is detectable.
  /// </summary>
  GAboutBoxIndex: Integer = -1;

const
  cProjectMenuCaption = 'DX.Comply - CRA Compliance';

{ TDxComplyWizard }

constructor TDxComplyWizard.Create;
begin
  inherited Create;
  FOptionsPage := nil;
  FProjectMenuItem := nil;
  FProjectMenuSeparator := nil;
  RegisterOptionsPage;
  AddProjectMenuItems;
end;

destructor TDxComplyWizard.Destroy;
begin
  RemoveProjectMenuItems;
  UnregisterOptionsPage;
  inherited;
end;

procedure TDxComplyWizard.AddProjectMenuItems;
var
  LNTASvc: INTAServices;
  LMainMenu: TMainMenu;
  LProjectMenu: TMenuItem;
  LSubMenuItem: TMenuItem;
  I: Integer;
begin
  try
    if not Supports(BorlandIDEServices, INTAServices, LNTASvc) then
      Exit;

    LMainMenu := LNTASvc.GetMainMenu;
    if not Assigned(LMainMenu) then
      Exit;

    // Locate the top-level 'Project' menu. The Name property is language-independent,
    // whereas Caption is localized (e.g., "Projekt" in German, "Projet" in French).
    LProjectMenu := nil;
    for I := 0 to LMainMenu.Items.Count - 1 do
    begin
      if ContainsText(LMainMenu.Items[I].Name, 'Project') then
      begin
        LProjectMenu := LMainMenu.Items[I];
        Break;
      end;
    end;

    if not Assigned(LProjectMenu) then
      Exit;

    // Separator before our entry for visual grouping.
    FProjectMenuSeparator := TMenuItem.Create(nil);
    FProjectMenuSeparator.Caption := '-';
    LProjectMenu.Add(FProjectMenuSeparator);

    FProjectMenuItem := TMenuItem.Create(nil);
    FProjectMenuItem.Caption := cProjectMenuCaption;
    AssignProjectMenuBitmap;

    LSubMenuItem := TMenuItem.Create(FProjectMenuItem);
    LSubMenuItem.Caption := 'Generate documentation...';
    LSubMenuItem.OnClick := OnProjectMenuItemClick;
    FProjectMenuItem.Add(LSubMenuItem);

    LSubMenuItem := TMenuItem.Create(FProjectMenuItem);
    LSubMenuItem.Caption := 'Options';
    LSubMenuItem.OnClick := OnOptionsMenuItemClick;
    FProjectMenuItem.Add(LSubMenuItem);

    LSubMenuItem := TMenuItem.Create(FProjectMenuItem);
    LSubMenuItem.Caption := 'About DX.Comply';
    LSubMenuItem.OnClick := OnAboutMenuItemClick;
    FProjectMenuItem.Add(LSubMenuItem);

    LProjectMenu.Add(FProjectMenuItem);
  except
    // Never crash the IDE during menu manipulation.
  end;
end;

procedure TDxComplyWizard.AssignProjectMenuBitmap;
var
  LBitmapPath: string;
  LMenuBitmap: TBitmap;
  LSourceBitmap: TBitmap;
  LMenuBitmapSize: Integer;
begin
  if not Assigned(FProjectMenuItem) then
    Exit;

  LBitmapPath := FindDXComplyAssetFile('DX.Comply.Icon.bmp');
  if LBitmapPath = '' then
    Exit;

  LSourceBitmap := TBitmap.Create;
  LMenuBitmap := TBitmap.Create;
  try
    LSourceBitmap.LoadFromFile(LBitmapPath);
    LMenuBitmapSize := GetSystemMetrics(SM_CXMENUCHECK);
    if LMenuBitmapSize <= 0 then
      LMenuBitmapSize := 16;

    LMenuBitmap.SetSize(LMenuBitmapSize, LMenuBitmapSize);
    LMenuBitmap.PixelFormat := pf24bit;
    LMenuBitmap.Canvas.Brush.Color := clWhite;
    LMenuBitmap.Canvas.FillRect(Rect(0, 0, LMenuBitmap.Width,
      LMenuBitmap.Height));
    LMenuBitmap.Canvas.StretchDraw(Rect(0, 0, LMenuBitmap.Width,
      LMenuBitmap.Height), LSourceBitmap);
    FProjectMenuItem.Bitmap.Assign(LMenuBitmap);
  finally
    LMenuBitmap.Free;
    LSourceBitmap.Free;
  end;
end;

function TDxComplyWizard.BuildConfig(const AProject: IOTAProject;
  const ASettings: TDXComplyIDESettings; AForceDeepEvidence: Boolean): TSbomConfig;
begin
  Result := TSbomConfig.Default;
  Result.OutputPath := 'bom.json';
  Result.Format := sfCycloneDxJson;
  Result.DeepEvidenceBuildScriptPath := ASettings.BuildScriptPath;
  Result.DeepEvidenceDelphiVersion := ASettings.DelphiVersionOverride;
  Result.ContinueOnDeepEvidenceBuildFailure := False;
  Result.WarnOnEmptyCompositionEvidence := ASettings.WarnWhenCompositionEvidenceIsEmpty;
  Result.HumanReadableReport := ASettings.HumanReadableReport;
  Result.DeepEvidenceMode := debAlways;

  if ASettings.UseActiveBuildConfiguration and Assigned(AProject) then
  begin
    if Trim(AProject.CurrentPlatform) <> '' then
      Result.Platform := AProject.CurrentPlatform;
    if Trim(AProject.CurrentConfiguration) <> '' then
      Result.Configuration := AProject.CurrentConfiguration;
  end;
end;

procedure TDxComplyWizard.ExecuteGeneration(AForceDeepEvidence: Boolean);
var
  LConfig: TSbomConfig;
  LOutputPath: string;
  LProject: IOTAProject;
  LProjectPath: string;
  LSettings: TDXComplyIDESettings;
  LSuccess: Boolean;
begin
  TIDELogger.Clear;
  TIDELogger.Info('DX.Comply: Starting CRA compliance documentation generation...');

  try
    LProject := GetActiveProject;
    if not Assigned(LProject) then
    begin
      TIDELogger.Error('DX.Comply: No project is currently active. Open a project first.');
      Exit;
    end;

    LProjectPath := Trim(LProject.FileName);
    if LProjectPath = '' then
    begin
      TIDELogger.Error('DX.Comply: The active project has no file name. Save the project first.');
      Exit;
    end;

    if not LProjectPath.EndsWith('.dproj', True) then
    begin
      TIDELogger.Error('DX.Comply: The active project is not a .dproj file: ' + LProjectPath);
      Exit;
    end;

    LSettings := TDXComplyIDESettingsStore.Load;
    LConfig := BuildConfig(LProject, LSettings, AForceDeepEvidence);
    if not TryPrepareDeepEvidenceBuild(LProjectPath, LSettings, LConfig, AForceDeepEvidence) then
      Exit;

    LOutputPath := TPath.Combine(TPath.GetDirectoryName(LProjectPath), 'bom.json');
    TIDELogger.Info('DX.Comply: Project : ' + LProjectPath);
    TIDELogger.Info('DX.Comply: Output  : ' + LOutputPath);

    LSuccess := ShowDXComplyProgressDialog(LProjectPath, LOutputPath, sfCycloneDxJson, LConfig);

    if LSuccess then
    begin
      TryOpenHtmlReport(LOutputPath, LSettings, LConfig);
      TIDELogger.Info('DX.Comply: SBOM generated successfully -> ' + LOutputPath);
    end
    else
      TIDELogger.Warning('DX.Comply: SBOM generation failed or was cancelled.');
  except
    on E: Exception do
      TIDELogger.Error('DX.Comply: Unhandled exception: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TDxComplyWizard.Execute;
begin
  ExecuteGeneration(True);
end;

procedure TDxComplyWizard.OnAboutMenuItemClick(ASender: TObject);
begin
  ShowAboutDialog;
end;

procedure TDxComplyWizard.OnOptionsMenuItemClick(ASender: TObject);
begin
  OpenOptionsPage;
end;

procedure TDxComplyWizard.OnProjectMenuItemClick(ASender: TObject);
begin
  ExecuteGeneration(True);
end;

procedure TDxComplyWizard.RegisterOptionsPage;
var
  LOptionsServices: INTAEnvironmentOptionsServices;
begin
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, LOptionsServices) then
  begin
    FOptionsPage := TDXComplyIDEOptionsPage.Create;
    LOptionsServices.RegisterAddInOptions(FOptionsPage);
  end;
end;

procedure TDxComplyWizard.OpenOptionsPage;
var
  LOTAServices: IOTAServices;
begin
  if Supports(BorlandIDEServices, IOTAServices, LOTAServices) then
    LOTAServices.GetEnvironmentOptions.EditOptions('', DXComplyOptionsPageCaption)
  else
    TIDELogger.Warning('DX.Comply: RAD Studio did not expose the environment options service.');
end;

procedure TDxComplyWizard.RemoveProjectMenuItems;
var
  LParent: TMenuItem;
begin
  try
    if Assigned(FProjectMenuItem) then
    begin
      LParent := FProjectMenuItem.Parent;
      if Assigned(LParent) then
        LParent.Remove(FProjectMenuItem);
      FProjectMenuItem.Free;
      FProjectMenuItem := nil;
    end;

    if Assigned(FProjectMenuSeparator) then
    begin
      LParent := FProjectMenuSeparator.Parent;
      if Assigned(LParent) then
        LParent.Remove(FProjectMenuSeparator);
      FProjectMenuSeparator.Free;
      FProjectMenuSeparator := nil;
    end;
  except
  end;
end;

function TDxComplyWizard.OpenInDefaultBrowser(const ATarget: string): Boolean;
begin
  Result := NativeUInt(ShellExecute(0, 'open', PChar(ATarget), nil, nil, SW_SHOWNORMAL)) > 32;
end;

function TDxComplyWizard.ResolveReportOutputBasePath(const ASbomOutputPath: string;
  const AConfig: THumanReadableReportConfig): string;
begin
  Result := Trim(AConfig.OutputBasePath);
  if Result = '' then
    Exit(TPath.Combine(TPath.GetDirectoryName(ASbomOutputPath),
      TPath.GetFileNameWithoutExtension(ASbomOutputPath) + '.report'));

  if TPath.IsRelativePath(Result) then
    Result := TPath.Combine(TPath.GetDirectoryName(ASbomOutputPath), Result);

  if Result.EndsWith('.md', True) or Result.EndsWith('.html', True) then
    Result := TPath.ChangeExtension(Result, '');
end;

function TDxComplyWizard.ResolveReportOutputPath(const AOutputBasePath: string;
  AFormat: THumanReadableReportFormat): string;
begin
  Result := AOutputBasePath;
  case AFormat of
    hrfMarkdown:
      Result := Result + '.md';
    hrfHtml:
      Result := Result + '.html';
  end;
end;

procedure TDxComplyWizard.SaveModifiedFiles;
var
  LEditorServices: IOTAEditorServices;
  LIterator: IOTAEditBufferIterator;
  I: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, LEditorServices) then
    Exit;

  if LEditorServices.GetEditBufferIterator(LIterator) then
    for I := 0 to LIterator.Count - 1 do
      if LIterator.EditBuffers[I].IsModified then
        LIterator.EditBuffers[I].Module.Save(False, False);
end;

procedure TDxComplyWizard.ShowAboutDialog;
begin
  ShowDXComplyAboutDialog;
end;

function TDxComplyWizard.ShowBuildConfirmationDialog(const AProjectPath: string;
  const APlan: TDeepEvidenceBuildPlan; out ADisablePrompt: Boolean): Boolean;
begin
  Result := ShowDXComplyBuildConfirmationDialog(AProjectPath, APlan,
    ADisablePrompt);
end;

procedure TDxComplyWizard.TryOpenHtmlReport(const ASbomOutputPath: string;
  const ASettings: TDXComplyIDESettings; const AConfig: TSbomConfig);
var
  LHtmlReportPath: string;
begin
  if not ASettings.OpenHtmlReportAfterGenerate then
    Exit;
  if not AConfig.HumanReadableReport.Enabled then
    Exit;
  if not (AConfig.HumanReadableReport.Format in [hrfHtml, hrfBoth]) then
    Exit;

  LHtmlReportPath := ResolveReportOutputPath(
    ResolveReportOutputBasePath(ASbomOutputPath, AConfig.HumanReadableReport),
    hrfHtml);
  if not TFile.Exists(LHtmlReportPath) then
  begin
    TIDELogger.Warning('DX.Comply: HTML report was not found after generation: ' + LHtmlReportPath);
    Exit;
  end;

  if OpenInDefaultBrowser(LHtmlReportPath) then
    TIDELogger.Info('DX.Comply: Opened HTML report in the default browser -> ' + LHtmlReportPath)
  else
    TIDELogger.Warning('DX.Comply: Failed to open the HTML report in the default browser: ' + LHtmlReportPath);
end;

function TDxComplyWizard.TryPrepareDeepEvidenceBuild(const AProjectPath: string;
  const ASettings: TDXComplyIDESettings; var AConfig: TSbomConfig;
  AForceDeepEvidence: Boolean): Boolean;
var
  LDisablePrompt: Boolean;
  LBuildOptions: TDeepEvidenceBuildOptions;
  LBuildOrchestrator: IBuildOrchestrator;
  LPlan: TDeepEvidenceBuildPlan;
  LProjectInfo: TProjectInfo;
  LProjectScanner: IProjectScanner;
  LUpdatedSettings: TDXComplyIDESettings;
begin
  Result := True;
  if AConfig.DeepEvidenceMode = debDisabled then
    Exit;

  try
    LProjectScanner := TProjectScanner.Create;
    LProjectInfo := LProjectScanner.Scan(AProjectPath, AConfig.Platform, AConfig.Configuration);
    try
      LBuildOptions := TDeepEvidenceBuildOptions.Default;
      LBuildOptions.Mode := AConfig.DeepEvidenceMode;
      LBuildOptions.DelphiVersion := AConfig.DeepEvidenceDelphiVersion;
      LBuildOptions.BuildScriptPathOverride := AConfig.DeepEvidenceBuildScriptPath;
      LBuildOrchestrator := TBuildOrchestrator.Create;
      LPlan := LBuildOrchestrator.CreatePlan(LProjectInfo, LBuildOptions);

      if not LPlan.ShouldExecute then
      begin
        TIDELogger.Info('DX.Comply: Deep-Evidence auto-build is not required for the current project state.');
        Exit;
      end;

      if LPlan.ScriptPath = '' then
      begin
        TIDELogger.Warning('DX.Comply: Build script (DelphiBuildDPROJ.ps1) not found. ' +
          'Configure the path under Tools > Options > DX' + #$2024 + 'Comply, or place it ' +
          'in a "build" folder next to your project. Skipping Deep-Evidence build.');
        if AForceDeepEvidence and not ASettings.ContinueWithoutDeepEvidenceOnBuildFailure then
        begin
          Result := False;
          Exit;
        end;
        AConfig.DeepEvidenceMode := debDisabled;
        Exit;
      end;

      TIDELogger.Info('DX.Comply: Deep-Evidence build prepared for ' + LPlan.Configuration + '/' + LPlan.Platform + '.');
      if Trim(LPlan.ExpectedMapFilePath) <> '' then
        TIDELogger.Info('DX.Comply: Expected MAP file: ' + LPlan.ExpectedMapFilePath);

      if ASettings.PromptBeforeBuild then
      begin
        if not ShowBuildConfirmationDialog(AProjectPath, LPlan, LDisablePrompt) then
        begin
          TIDELogger.Warning('DX.Comply: CRA compliance generation was cancelled by the user.');
          Result := False;
          Exit;
        end;

        if LDisablePrompt then
        begin
          LUpdatedSettings := ASettings;
          LUpdatedSettings.PromptBeforeBuild := False;
          TDXComplyIDESettingsStore.Save(LUpdatedSettings);
          TIDELogger.Info('DX.Comply: The build confirmation dialog was disabled in IDE settings.');
        end;
      end;

      if ASettings.SaveAllModifiedFilesBeforeBuild then
      begin
        TIDELogger.Info('DX.Comply: Saving modified editors before the Deep-Evidence build...');
        SaveModifiedFiles;
      end;
    finally
      LProjectInfo.Free;
    end;
  except
    on E: Exception do
    begin
      if AForceDeepEvidence then
      begin
        TIDELogger.Error('DX.Comply: Deep-Evidence preflight failed. ' + E.Message);
        Result := False;
      end
      else
        TIDELogger.Warning('DX.Comply: Deep-Evidence preflight failed. ' + E.Message);
    end;
  end;
end;

procedure TDxComplyWizard.UnregisterOptionsPage;
var
  LOptionsServices: INTAEnvironmentOptionsServices;
begin
  if Assigned(FOptionsPage) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, LOptionsServices) then
    LOptionsServices.UnregisterAddInOptions(FOptionsPage);

  FOptionsPage := nil;
end;

// IOTANotifier – no-ops required by the interface contract.
procedure TDxComplyWizard.AfterSave;  begin end;
procedure TDxComplyWizard.BeforeSave; begin end;
procedure TDxComplyWizard.Destroyed;  begin end;
procedure TDxComplyWizard.Modified;   begin end;

// IOTAWizard

function TDxComplyWizard.GetIDString: string;
begin
  Result := 'DX.Comply.SBOM.Generator';
end;

function TDxComplyWizard.GetName: string;
begin
  Result := cProjectMenuCaption;
end;

function TDxComplyWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

{ Splash screen and About box registration }

{$R DX.Comply.IDE.Splash.res}

const
  cSplashTitle = 'DX.Comply - CRA Compliance Documentation';
  cSplashLicenseStatus = 'Open Source - MIT License';
  cAboutDescription =
    'Generates CycloneDX Software Bills of Materials (SBOMs) directly from ' +
    'RAD Studio projects for EU Cyber Resilience Act compliance.';

/// <summary>
/// Loads the 48x48 splash bitmap from the embedded resource.
/// The caller receives ownership of the returned HBITMAP handle.
/// Returns 0 if the resource cannot be loaded.
/// </summary>
function CreateSplashBitmap: HBITMAP;
var
  LBmp: TBitmap;
begin
  Result := 0;
  LBmp := TBitmap.Create;
  try
    try
      LBmp.LoadFromResourceName(HInstance, 'DXCOMPLYSPLASH');
      Result := LBmp.ReleaseHandle;
    except
      Result := 0;
    end;
  finally
    LBmp.Free;
  end;
end;

/// <summary>
/// Registers the DX.Comply plugin bitmap on the IDE splash screen.
/// </summary>
procedure RegisterSplashScreen;
var
  LSplashServices: IOTASplashScreenServices;
  LBitmap: HBITMAP;
begin
  if not Supports(SplashScreenServices, IOTASplashScreenServices, LSplashServices) then
    Exit;

  LBitmap := CreateSplashBitmap;
  if LBitmap <> 0 then
    LSplashServices.AddPluginBitmap(cSplashTitle, LBitmap, False, cSplashLicenseStatus);
end;

/// <summary>
/// Registers DX.Comply in the IDE Help &gt; About &gt; Installed Products list.
/// </summary>
procedure RegisterAboutBox;
var
  LAboutServices: IOTAAboutBoxServices;
  LBitmap: HBITMAP;
begin
  if not Supports(BorlandIDEServices, IOTAAboutBoxServices, LAboutServices) then
    Exit;

  LBitmap := CreateSplashBitmap;
  if LBitmap <> 0 then
    GAboutBoxIndex := LAboutServices.AddPluginInfo(
      cSplashTitle, cAboutDescription, LBitmap, False, cSplashLicenseStatus);
end;

/// <summary>
/// Removes the DX.Comply entry from the IDE About box.
/// </summary>
procedure UnregisterAboutBox;
var
  LAboutServices: IOTAAboutBoxServices;
begin
  if (GAboutBoxIndex >= 0) and
    Supports(BorlandIDEServices, IOTAAboutBoxServices, LAboutServices) then
  begin
    LAboutServices.RemovePluginInfo(GAboutBoxIndex);
    GAboutBoxIndex := -1;
  end;
end;

{ Register }

procedure Register;
begin
  // Intentionally empty. Wizard registration is done in initialization/finalization
  // to ensure availability as soon as the package is loaded.
end;

initialization
  RegisterSplashScreen;
  RegisterAboutBox;
  GWizardIndex := (BorlandIDEServices as IOTAWizardServices).AddWizard(TDxComplyWizard.Create);

finalization
  if GWizardIndex >= 0 then
  begin
    (BorlandIDEServices as IOTAWizardServices).RemoveWizard(GWizardIndex);
    GWizardIndex := -1;
  end;
  UnregisterAboutBox;

end.
