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
  Winapi.Windows,
  Vcl.Menus,
  Vcl.Dialogs,
  ToolsAPI,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.IDE.Logger;

type
  /// <summary>
  /// IDE wizard that adds SBOM generation to the Delphi IDE menus.
  /// </summary>
  TDxComplyWizard = class(TInterfacedObject, IOTANotifier, IOTAWizard, IOTAMenuWizard)
  private
    FProjectMenuItem: TMenuItem;
    /// <summary>
    /// Injects a TMenuItem into the main Project menu.
    /// Called once from the constructor.
    /// </summary>
    procedure AddProjectMenuItem;
    /// <summary>
    /// Removes the previously injected Project menu item on unload.
    /// </summary>
    procedure RemoveProjectMenuItem;
    /// <summary>
    /// Event handler for the injected Project menu item.
    /// </summary>
    procedure OnProjectMenuItemClick(ASender: TObject);
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
  FProjectMenuItem := nil;
  AddProjectMenuItem;
end;

destructor TDxComplyWizard.Destroy;
begin
  RemoveProjectMenuItem;
  inherited;
end;

procedure TDxComplyWizard.AddProjectMenuItem;
var
  LNTASvc: INTAServices;
  LMainMenu: TMainMenu;
  LProjectMenu: TMenuItem;
  LSeparator: TMenuItem;
  LMenuItem: TMenuItem;
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
    LSeparator := TMenuItem.Create(nil);
    LSeparator.Caption := '-';
    LProjectMenu.Add(LSeparator);

    LMenuItem := TMenuItem.Create(nil);
    LMenuItem.Caption := 'SBOM generieren (DX.Comply)...';
    LMenuItem.OnClick := OnProjectMenuItemClick;
    LProjectMenu.Add(LMenuItem);

    // Remember the item so we can surgically remove it (and its separator) later.
    FProjectMenuItem := LMenuItem;
  except
    // Never crash the IDE during menu manipulation.
  end;
end;

procedure TDxComplyWizard.RemoveProjectMenuItem;
var
  LParent: TMenuItem;
  LIdx: Integer;
begin
  try
    if not Assigned(FProjectMenuItem) then
      Exit;

    LParent := FProjectMenuItem.Parent;
    if Assigned(LParent) then
    begin
      LIdx := FProjectMenuItem.MenuIndex;
      // Remove the separator that was inserted immediately before our item.
      if (LIdx > 0) and (LParent.Items[LIdx - 1].Caption = '-') then
        LParent.Delete(LIdx - 1);

      LParent.Remove(FProjectMenuItem);
    end;

    FProjectMenuItem.Free;
    FProjectMenuItem := nil;
  except
  end;
end;

procedure TDxComplyWizard.OnProjectMenuItemClick(ASender: TObject);
begin
  Execute;
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
  // Caption shown in Help > <entry> added automatically by the IDE.
  Result := 'SBOM generieren (DX.Comply)...';
end;

procedure TDxComplyWizard.Execute;
var
  LProject: IOTAProject;
  LProjectPath: string;
  LOutputPath: string;
  LGenerator: TDxComplyGenerator;
  LSuccess: Boolean;
begin
  TIDELogger.Clear;
  TIDELogger.Info('DX.Comply: Starting SBOM generation...');

  try
    // GetActiveProject is a ToolsAPI global helper function
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

    // Place bom.json beside the .dproj so it is easy to locate.
    LOutputPath := TPath.Combine(TPath.GetDirectoryName(LProjectPath), 'bom.json');
    TIDELogger.Info('DX.Comply: Project : ' + LProjectPath);
    TIDELogger.Info('DX.Comply: Output  : ' + LOutputPath);

    LGenerator := TDxComplyGenerator.Create;
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
