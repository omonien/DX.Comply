/// <summary>
/// DX.Comply.IDE.Wizard
/// Delphi IDE wizard that exposes SBOM generation via the Help menu and
/// a dedicated Project menu entry.
/// </summary>
///
/// <remarks>
/// TDxComplyWizard implements IOTAWizard + IOTAMenuWizard, which causes
/// Delphi to add an entry to the Help menu automatically. A separate
/// TMenuItem is also injected into the Project menu from the constructor
/// so users find the action in the most logical location.
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
  System.Classes,
  System.IOUtils,
  System.UITypes,
  Winapi.Windows,
  Vcl.Menus,
  Vcl.Dialogs,
  ToolsAPI,
  DX.Comply.BuildOrchestrator,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.IDE.Settings,
  DX.Comply.ProjectScanner,
  DX.Comply.IDE.Logger;

type
  /// <summary>
  /// IDE wizard that adds SBOM generation to the Delphi IDE menus.
  /// </summary>
  TDxComplyWizard = class(TInterfacedObject, IOTANotifier, IOTAWizard, IOTAMenuWizard)
  private
    FDeepEvidenceMenuItem: TMenuItem;
    FOptionsPage: INTAAddInOptions;
    FProjectMenuItem: TMenuItem;
    FProjectMenuSeparator: TMenuItem;
    /// <summary>
    /// Injects the DX.Comply menu items into the main Project menu.
    /// Called once from the constructor.
    /// </summary>
    procedure AddProjectMenuItems;
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
    /// Event handler for the explicit Deep-Evidence menu entry.
    /// </summary>
    procedure OnDeepEvidenceMenuItemClick(ASender: TObject);
    /// <summary>
    /// Saves all modified editors before a Deep-Evidence build.
    /// </summary>
    procedure SaveModifiedFiles;
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

    // IOTAMenuWizard
    function GetMenuText: string;
  end;

/// <summary>
/// Called automatically by the IDE when the design-time package is installed.
/// Wizard registration is performed in initialization/finalization instead,
/// so this procedure is intentionally empty.
/// </summary>
procedure Register;

implementation

uses
  DX.Comply.IDE.Options;

var
  /// <summary>
  /// Handle returned by IOTAWizardServices.AddWizard; required for removal in
  /// finalization. Initialised to -1 so that a failed registration is detectable.
  /// </summary>
  GWizardIndex: Integer = -1;

{ TDxComplyWizard }

constructor TDxComplyWizard.Create;
begin
  inherited Create;
  FDeepEvidenceMenuItem := nil;
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
  LMenuItem: TMenuItem;
  LProjectMenu: TMenuItem;
  I: Integer;
begin
  try
    if not Supports(BorlandIDEServices, INTAServices, LNTASvc) then
      Exit;

    LMainMenu := LNTASvc.GetMainMenu;
    if not Assigned(LMainMenu) then
      Exit;

    // Locate the top-level 'Project' menu by caption, stripping accelerators.
    LProjectMenu := nil;
    for I := 0 to LMainMenu.Items.Count - 1 do
    begin
      if SameText(StringReplace(LMainMenu.Items[I].Caption, '&', '', [rfReplaceAll]), 'Project') then
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

    LMenuItem := TMenuItem.Create(nil);
    LMenuItem.Caption := 'Generate CRA compliance documentation (SBOM)...';
    LMenuItem.OnClick := OnProjectMenuItemClick;
    LProjectMenu.Add(LMenuItem);
    FProjectMenuItem := LMenuItem;

    LMenuItem := TMenuItem.Create(nil);
    LMenuItem.Caption := 'Generate CRA compliance documentation (SBOM + Deep Evidence)...';
    LMenuItem.OnClick := OnDeepEvidenceMenuItemClick;
    LProjectMenu.Add(LMenuItem);
    FDeepEvidenceMenuItem := LMenuItem;
  except
    // Never crash the IDE during menu manipulation.
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
  Result.ContinueOnDeepEvidenceBuildFailure :=
    ASettings.ContinueWithoutDeepEvidenceOnBuildFailure;
  Result.WarnOnEmptyCompositionEvidence := ASettings.WarnWhenCompositionEvidenceIsEmpty;

  case ASettings.AutoBuildMode of
    abmWhenMapMissing: Result.DeepEvidenceMode := debWhenMapMissing;
    abmAlways: Result.DeepEvidenceMode := debAlways;
  else
    Result.DeepEvidenceMode := debDisabled;
  end;

  if AForceDeepEvidence then
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
  LGenerator: TDxComplyGenerator;
  LOutputPath: string;
  LProject: IOTAProject;
  LProjectPath: string;
  LSettings: TDXComplyIDESettings;
  LSuccess: Boolean;
begin
  TIDELogger.Clear;
  if AForceDeepEvidence then
    TIDELogger.Info('DX.Comply: Starting SBOM generation with Deep-Evidence pre-build...')
  else
    TIDELogger.Info('DX.Comply: Starting SBOM generation...');

  try
    LProject := GetActiveProject;
    if not Assigned(LProject) then
    begin
      TIDELogger.Error('DX.Comply: No project is currently active. Open a project first.');
      Exit;
    end;

    LProjectPath := LProject.FileName;
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

    LGenerator := TDxComplyGenerator.Create(LConfig);
    try
      LGenerator.OnProgress :=
        procedure(const AMessage: string; const AProgress: Integer)
        begin
          TIDELogger.Progress(AMessage, AProgress);
        end;

      LSuccess := LGenerator.Generate(LProjectPath, LOutputPath, sfCycloneDxJson);

      if LSuccess then
        TIDELogger.Info('DX.Comply: SBOM generated successfully -> ' + LOutputPath)
      else
        TIDELogger.Error('DX.Comply: SBOM generation failed. Check messages above for details.');
    finally
      LGenerator.Free;
    end;
  except
    on E: Exception do
      TIDELogger.Error('DX.Comply: Unhandled exception: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TDxComplyWizard.Execute;
begin
  ExecuteGeneration(False);
end;

procedure TDxComplyWizard.OnDeepEvidenceMenuItemClick(ASender: TObject);
begin
  ExecuteGeneration(True);
end;

procedure TDxComplyWizard.OnProjectMenuItemClick(ASender: TObject);
begin
  ExecuteGeneration(False);
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

procedure TDxComplyWizard.RemoveProjectMenuItems;
var
  LParent: TMenuItem;
begin
  try
    if Assigned(FDeepEvidenceMenuItem) then
    begin
      LParent := FDeepEvidenceMenuItem.Parent;
      if Assigned(LParent) then
        LParent.Remove(FDeepEvidenceMenuItem);
      FDeepEvidenceMenuItem.Free;
      FDeepEvidenceMenuItem := nil;
    end;

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

function TDxComplyWizard.TryPrepareDeepEvidenceBuild(const AProjectPath: string;
  const ASettings: TDXComplyIDESettings; var AConfig: TSbomConfig;
  AForceDeepEvidence: Boolean): Boolean;
var
  LBuildOptions: TDeepEvidenceBuildOptions;
  LBuildOrchestrator: IBuildOrchestrator;
  LPlan: TDeepEvidenceBuildPlan;
  LProjectInfo: TProjectInfo;
  LProjectScanner: IProjectScanner;
  LPromptMessage: string;
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

      TIDELogger.Info('DX.Comply: Deep-Evidence build prepared for ' + LPlan.Configuration + '/' + LPlan.Platform + '.');
      if Trim(LPlan.ExpectedMapFilePath) <> '' then
        TIDELogger.Info('DX.Comply: Expected MAP file: ' + LPlan.ExpectedMapFilePath);

      if ASettings.PromptBeforeBuild then
      begin
        LPromptMessage := 'DX.Comply can start a dedicated Deep-Evidence build before SBOM generation.' + sLineBreak + sLineBreak +
          'Project: ' + ExtractFileName(AProjectPath) + sLineBreak +
          'Configuration: ' + LPlan.Configuration + sLineBreak +
          'Platform: ' + LPlan.Platform;

        if MessageDlg(LPromptMessage, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
        begin
          if AForceDeepEvidence then
          begin
            TIDELogger.Warning('DX.Comply: Deep-Evidence generation was cancelled by the user.');
            Result := False;
          end
          else
          begin
            AConfig.DeepEvidenceMode := debDisabled;
            TIDELogger.Warning('DX.Comply: Proceeding without the optional Deep-Evidence build.');
          end;
          Exit;
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
      TIDELogger.Warning('DX.Comply: Deep-Evidence preflight failed. Continuing with configured defaults. ' + E.Message);
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
  Result := 'Generate SBOM (DX.Comply)';
end;

function TDxComplyWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

// IOTAMenuWizard

function TDxComplyWizard.GetMenuText: string;
begin
  Result := 'Generate CRA compliance documentation (SBOM)...';
end;

{ Register }

procedure Register;
begin
  // Intentionally empty. Wizard registration is done in initialization/finalization
  // to ensure availability as soon as the package is loaded.
end;

initialization
  GWizardIndex := (BorlandIDEServices as IOTAWizardServices).AddWizard(TDxComplyWizard.Create);

finalization
  if GWizardIndex >= 0 then
  begin
    (BorlandIDEServices as IOTAWizardServices).RemoveWizard(GWizardIndex);
    GWizardIndex := -1;
  end;

end.
