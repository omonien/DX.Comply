/// <summary>
/// DX.Comply.IDE.BuildConfirmationDialog
/// Provides the confirmation dialog shown before a Deep-Evidence IDE build starts.
/// </summary>
///
/// <remarks>
/// The dialog lets the user choose which build configuration to use as the
/// basis for the MAP build. The active IDE configuration is pre-selected.
/// Changing the configuration or the platform refreshes the expected MAP
/// file, and whether that file is missing, with the same resolution the
/// build uses (issue #153).
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.BuildConfirmationDialog;

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls;

type
  /// <summary>
  /// Displays the confirmation UI before DX.Comply starts the build pipeline.
  /// </summary>
  TFormDXComplyBuildConfirmationDialog = class(TForm)
    TitleLabel: TLabel;
    DescriptionLabel: TLabel;
    ProjectCaptionLabel: TLabel;
    ProjectValueLabel: TLabel;
    ConfigurationCaptionLabel: TLabel;
    ConfigurationComboBox: TComboBox;
    PlatformCaptionLabel: TLabel;
    PlatformValueLabel: TLabel;
    MapCaptionLabel: TLabel;
    MapValueLabel: TLabel;
    DisablePromptCheckBox: TCheckBox;
    OkButton: TButton;
    CancelButton: TButton;
    procedure ConfigurationComboBoxChange(Sender: TObject);
  private
    FExpectedMapFilePath: string;
    FMapFileMissing: Boolean;
    FPlatform: string;
    FProjectPath: string;
    function SelectedConfiguration: string;
    procedure RefreshExpectedMapFile;
    procedure SetPlatform(const APlatform: string);
  end;

/// <summary>
/// Shows the Deep-Evidence build confirmation dialog with a configuration
/// selector. Returns True when the user accepts the build.
/// AExpectedMapFilePath is the path shown for the selected configuration
/// and platform. That is the path generation looks for.
/// </summary>
function ShowDXComplyBuildConfirmationDialog(const AProjectPath: string;
  const AConfigurations: TArray<string>; const AActiveConfiguration: string;
  const APlatform: string;
  out ASelectedConfiguration: string;
  out AExpectedMapFilePath: string;
  out ADisablePrompt: Boolean): Boolean;

implementation

{$R *.dfm}

uses
  System.SysUtils,
  DX.Comply.IDE.ExpectedMapFile,
  DX.Comply.IDE.Logger;

function TFormDXComplyBuildConfirmationDialog.SelectedConfiguration: string;
begin
  // ItemIndex is stored before the window exists. Text is not, so reading
  // Text while the dialog is still being filled would resolve the wrong
  // configuration (the scanner treats an empty name as Debug).
  if (ConfigurationComboBox.ItemIndex >= 0) and
     (ConfigurationComboBox.ItemIndex < ConfigurationComboBox.Items.Count) then
    Result := ConfigurationComboBox.Items[ConfigurationComboBox.ItemIndex]
  else
    Result := Trim(ConfigurationComboBox.Text);
end;

procedure TFormDXComplyBuildConfirmationDialog.RefreshExpectedMapFile;
var
  LState: TExpectedMapFileState;
begin
  // The label used to keep the MAP path of the configuration that was active
  // when the dialog opened (issue #153). Generation scans the configuration
  // and platform that are selected now, so the label and the missing-file
  // hint have to follow that same scan.
  LState := ResolveExpectedMapFileState(FProjectPath, FPlatform,
    SelectedConfiguration);
  FExpectedMapFilePath := LState.Path;
  FMapFileMissing := LState.Missing;
  MapValueLabel.Caption := LState.Path;
  MapValueLabel.Hint := ExpectedMapFileMissingHint(LState);
  MapValueLabel.ShowHint := FMapFileMissing;
end;

procedure TFormDXComplyBuildConfirmationDialog.SetPlatform(const APlatform: string);
begin
  FPlatform := APlatform;
  PlatformValueLabel.Caption := APlatform;
  RefreshExpectedMapFile;
end;

procedure TFormDXComplyBuildConfirmationDialog.ConfigurationComboBoxChange(
  Sender: TObject);
begin
  if Sender <> ConfigurationComboBox then
    Exit;

  // An exception here is raised inside ShowModal, so the wizard's try/except
  // does not see it. Keep the form open and clear the path so OK does not
  // confirm a file from the previous configuration.
  try
    RefreshExpectedMapFile;
  except
    on E: Exception do
    begin
      FExpectedMapFilePath := '';
      FMapFileMissing := True;
      MapValueLabel.Caption := '';
      MapValueLabel.Hint := E.Message;
      MapValueLabel.ShowHint := True;
      TIDELogger.Warning('DX.Comply: Could not resolve the expected MAP file: ' +
        E.Message);
    end;
  end;
end;

function ShowDXComplyBuildConfirmationDialog(const AProjectPath: string;
  const AConfigurations: TArray<string>; const AActiveConfiguration: string;
  const APlatform: string;
  out ASelectedConfiguration: string;
  out AExpectedMapFilePath: string;
  out ADisablePrompt: Boolean): Boolean;
var
  LDialog: TFormDXComplyBuildConfirmationDialog;
  LConfig: string;
  LActiveIndex: Integer;
begin
  ADisablePrompt := False;
  ASelectedConfiguration := AActiveConfiguration;
  AExpectedMapFilePath := '';

  LDialog := TFormDXComplyBuildConfirmationDialog.Create(nil);
  try
    LDialog.FProjectPath := AProjectPath;
    LDialog.ProjectValueLabel.Caption := ExtractFileName(AProjectPath);

    LActiveIndex := 0;
    for LConfig in AConfigurations do
    begin
      LDialog.ConfigurationComboBox.Items.Add(LConfig);
      if SameText(LConfig, AActiveConfiguration) then
        LActiveIndex := LDialog.ConfigurationComboBox.Items.Count - 1;
    end;

    if LDialog.ConfigurationComboBox.Items.Count = 0 then
    begin
      LDialog.ConfigurationComboBox.Items.Add(AActiveConfiguration);
      LActiveIndex := 0;
    end;
    LDialog.ConfigurationComboBox.ItemIndex := LActiveIndex;

    // SetPlatform resolves the path. OnChange covers a later configuration
    // change. Assign it after ItemIndex so opening does not resolve twice.
    LDialog.ConfigurationComboBox.OnChange := LDialog.ConfigurationComboBoxChange;
    LDialog.SetPlatform(APlatform);

    Result := LDialog.ShowModal = mrOk;
    if Result then
    begin
      ASelectedConfiguration := LDialog.SelectedConfiguration;
      AExpectedMapFilePath := LDialog.FExpectedMapFilePath;
      ADisablePrompt := LDialog.DisablePromptCheckBox.Checked;
    end;
  finally
    LDialog.Free;
  end;
end;

end.
