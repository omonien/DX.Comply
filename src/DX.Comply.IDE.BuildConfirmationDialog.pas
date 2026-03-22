/// <summary>
/// DX.Comply.IDE.BuildConfirmationDialog
/// Provides the confirmation dialog shown before a Deep-Evidence IDE build starts.
/// </summary>
///
/// <remarks>
/// The dialog lets the user choose which build configuration to use as the
/// basis for the MAP build. The active IDE configuration is pre-selected.
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
  end;

/// <summary>
/// Shows the Deep-Evidence build confirmation dialog with a configuration
/// selector. Returns True when the user accepts the build.
/// </summary>
function ShowDXComplyBuildConfirmationDialog(const AProjectPath: string;
  const AConfigurations: TArray<string>; const AActiveConfiguration: string;
  const APlatform, AExpectedMapFilePath: string;
  out ASelectedConfiguration: string;
  out ADisablePrompt: Boolean): Boolean;

implementation

{$R *.dfm}

uses
  System.SysUtils;

function ShowDXComplyBuildConfirmationDialog(const AProjectPath: string;
  const AConfigurations: TArray<string>; const AActiveConfiguration: string;
  const APlatform, AExpectedMapFilePath: string;
  out ASelectedConfiguration: string;
  out ADisablePrompt: Boolean): Boolean;
var
  LDialog: TFormDXComplyBuildConfirmationDialog;
  LConfig: string;
  LActiveIndex: Integer;
begin
  ADisablePrompt := False;
  ASelectedConfiguration := AActiveConfiguration;

  LDialog := TFormDXComplyBuildConfirmationDialog.Create(nil);
  try
    LDialog.ProjectValueLabel.Caption := ExtractFileName(AProjectPath);
    LDialog.PlatformValueLabel.Caption := APlatform;
    LDialog.MapValueLabel.Caption := AExpectedMapFilePath;

    LActiveIndex := 0;
    for LConfig in AConfigurations do
    begin
      LDialog.ConfigurationComboBox.Items.Add(LConfig);
      if SameText(LConfig, AActiveConfiguration) then
        LActiveIndex := LDialog.ConfigurationComboBox.Items.Count - 1;
    end;

    if LDialog.ConfigurationComboBox.Items.Count > 0 then
      LDialog.ConfigurationComboBox.ItemIndex := LActiveIndex
    else
    begin
      LDialog.ConfigurationComboBox.Items.Add(AActiveConfiguration);
      LDialog.ConfigurationComboBox.ItemIndex := 0;
    end;

    Result := LDialog.ShowModal = mrOk;
    if Result then
    begin
      ASelectedConfiguration := LDialog.ConfigurationComboBox.Text;
      ADisablePrompt := LDialog.DisablePromptCheckBox.Checked;
    end;
  finally
    LDialog.Free;
  end;
end;

end.
