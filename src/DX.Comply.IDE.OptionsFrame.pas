/// <summary>
/// DX.Comply.IDE.OptionsFrame
/// Implements the Tools &gt; Options UI for the DX.Comply IDE plugin.
/// </summary>
///
/// <remarks>
/// The frame is created programmatically to keep the package lightweight and to avoid
/// additional DFM management for the initial options surface.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.OptionsFrame;

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  DX.Comply.IDE.Settings;

type
  /// <summary>
  /// Options frame hosted inside the RAD Studio environment options dialog.
  /// </summary>
  TFrameDXComplyOptions = class(TFrame)
  private
    FAutoBuildModeComboBox: TComboBox;
    FBuildScriptPathEdit: TEdit;
    FBrowseScriptButton: TButton;
    FContinueOnBuildFailureCheckBox: TCheckBox;
    FDelphiVersionEdit: TEdit;
    FPromptBeforeBuildCheckBox: TCheckBox;
    FSaveAllModifiedFilesCheckBox: TCheckBox;
    FUseActiveBuildConfigurationCheckBox: TCheckBox;
    FWarnWhenCompositionEmptyCheckBox: TCheckBox;
    function AutoBuildModeFromSelection: TIDEAutoBuildMode;
    procedure AddCheckBox(const ACaption: string; var ACheckBox: TCheckBox; var ATop: Integer);
    procedure BrowseScriptButtonClick(Sender: TObject);
    procedure CreateLabeledControl(const ACaption: string; const AControl: TControl;
      var ATop: Integer; const AButton: TControl = nil);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadSettings(const ASettings: TDXComplyIDESettings);
    function SaveSettings: TDXComplyIDESettings;
    function ValidateSettings(out AMessage: string): Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Vcl.Dialogs;

const
  cLeftMargin = 16;
  cLabelWidth = 220;
  cEditWidth = 360;

constructor TFrameDXComplyOptions.Create(AOwner: TComponent);
var
  LTop: Integer;
begin
  inherited Create(AOwner);
  Align := alClient;
  AutoScroll := True;
  Width := 660;
  Height := 360;

  LTop := 16;

  FAutoBuildModeComboBox := TComboBox.Create(Self);
  FAutoBuildModeComboBox.Parent := Self;
  FAutoBuildModeComboBox.Style := csDropDownList;
  FAutoBuildModeComboBox.Items.Add('Disabled');
  FAutoBuildModeComboBox.Items.Add('Only when the expected MAP file is missing');
  FAutoBuildModeComboBox.Items.Add('Always before SBOM generation');
  CreateLabeledControl('Deep-Evidence auto-build', FAutoBuildModeComboBox, LTop);

  AddCheckBox('Prompt before starting the Deep-Evidence build', FPromptBeforeBuildCheckBox, LTop);
  AddCheckBox('Save all modified editors before the build', FSaveAllModifiedFilesCheckBox, LTop);
  AddCheckBox('Use the active IDE configuration and platform', FUseActiveBuildConfigurationCheckBox, LTop);
  AddCheckBox('Continue with artefact-only SBOM when the build fails', FContinueOnBuildFailureCheckBox, LTop);
  AddCheckBox('Warn when no composition units were resolved', FWarnWhenCompositionEmptyCheckBox, LTop);

  FBuildScriptPathEdit := TEdit.Create(Self);
  FBuildScriptPathEdit.Parent := Self;
  FBrowseScriptButton := TButton.Create(Self);
  FBrowseScriptButton.Parent := Self;
  FBrowseScriptButton.Caption := 'Browse...';
  FBrowseScriptButton.OnClick := BrowseScriptButtonClick;
  CreateLabeledControl('Build script path override', FBuildScriptPathEdit, LTop, FBrowseScriptButton);

  FDelphiVersionEdit := TEdit.Create(Self);
  FDelphiVersionEdit.Parent := Self;
  CreateLabeledControl('Delphi version override (0 = auto)', FDelphiVersionEdit, LTop);
end;

procedure TFrameDXComplyOptions.AddCheckBox(const ACaption: string;
  var ACheckBox: TCheckBox; var ATop: Integer);
begin
  ACheckBox := TCheckBox.Create(Self);
  ACheckBox.Parent := Self;
  ACheckBox.Left := cLeftMargin;
  ACheckBox.Top := ATop;
  ACheckBox.Width := 520;
  ACheckBox.Caption := ACaption;
  Inc(ATop, 28);
end;

function TFrameDXComplyOptions.AutoBuildModeFromSelection: TIDEAutoBuildMode;
begin
  case FAutoBuildModeComboBox.ItemIndex of
    1: Result := abmWhenMapMissing;
    2: Result := abmAlways;
  else
    Result := abmDisabled;
  end;
end;

procedure TFrameDXComplyOptions.BrowseScriptButtonClick(Sender: TObject);
var
  LDialog: TOpenDialog;
begin
  LDialog := TOpenDialog.Create(nil);
  try
    LDialog.Filter := 'PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*';
    LDialog.FileName := FBuildScriptPathEdit.Text;
    if LDialog.Execute then
      FBuildScriptPathEdit.Text := LDialog.FileName;
  finally
    LDialog.Free;
  end;
end;

procedure TFrameDXComplyOptions.CreateLabeledControl(const ACaption: string;
  const AControl: TControl; var ATop: Integer; const AButton: TControl);
var
  LLabel: TLabel;
begin
  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.Left := cLeftMargin;
  LLabel.Top := ATop + 4;
  LLabel.Width := cLabelWidth;
  LLabel.Caption := ACaption;

  AControl.Left := cLeftMargin + cLabelWidth + 12;
  AControl.Top := ATop;
  AControl.Width := cEditWidth;

  if Assigned(AButton) then
  begin
    AButton.Left := AControl.Left + AControl.Width + 8;
    AButton.Top := ATop - 1;
    AButton.Width := 88;
  end;

  Inc(ATop, 34);
end;

procedure TFrameDXComplyOptions.LoadSettings(const ASettings: TDXComplyIDESettings);
begin
  case ASettings.AutoBuildMode of
    abmWhenMapMissing: FAutoBuildModeComboBox.ItemIndex := 1;
    abmAlways: FAutoBuildModeComboBox.ItemIndex := 2;
  else
    FAutoBuildModeComboBox.ItemIndex := 0;
  end;

  FPromptBeforeBuildCheckBox.Checked := ASettings.PromptBeforeBuild;
  FSaveAllModifiedFilesCheckBox.Checked := ASettings.SaveAllModifiedFilesBeforeBuild;
  FUseActiveBuildConfigurationCheckBox.Checked := ASettings.UseActiveBuildConfiguration;
  FContinueOnBuildFailureCheckBox.Checked := ASettings.ContinueWithoutDeepEvidenceOnBuildFailure;
  FWarnWhenCompositionEmptyCheckBox.Checked := ASettings.WarnWhenCompositionEvidenceIsEmpty;
  FBuildScriptPathEdit.Text := ASettings.BuildScriptPath;
  FDelphiVersionEdit.Text := IntToStr(ASettings.DelphiVersionOverride);
end;

function TFrameDXComplyOptions.SaveSettings: TDXComplyIDESettings;
begin
  Result := TDXComplyIDESettings.Default;
  Result.AutoBuildMode := AutoBuildModeFromSelection;
  Result.PromptBeforeBuild := FPromptBeforeBuildCheckBox.Checked;
  Result.SaveAllModifiedFilesBeforeBuild := FSaveAllModifiedFilesCheckBox.Checked;
  Result.UseActiveBuildConfiguration := FUseActiveBuildConfigurationCheckBox.Checked;
  Result.ContinueWithoutDeepEvidenceOnBuildFailure := FContinueOnBuildFailureCheckBox.Checked;
  Result.WarnWhenCompositionEvidenceIsEmpty := FWarnWhenCompositionEmptyCheckBox.Checked;
  Result.BuildScriptPath := Trim(FBuildScriptPathEdit.Text);
  Result.DelphiVersionOverride := StrToIntDef(Trim(FDelphiVersionEdit.Text), -1);
end;

function TFrameDXComplyOptions.ValidateSettings(out AMessage: string): Boolean;
var
  LSettings: TDXComplyIDESettings;
begin
  LSettings := SaveSettings;
  Result := False;

  if LSettings.DelphiVersionOverride < 0 then
  begin
    AMessage := 'The Delphi version override must be 0 or a positive integer.';
    Exit;
  end;

  if (LSettings.BuildScriptPath <> '') and not TFile.Exists(LSettings.BuildScriptPath) then
  begin
    AMessage := 'The configured build script path does not exist: ' + LSettings.BuildScriptPath;
    Exit;
  end;

  AMessage := '';
  Result := True;
end;

end.