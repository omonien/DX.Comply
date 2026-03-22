/// <summary>
/// DX.Comply.IDE.OptionsFrame
/// Implements the Tools &gt; Options UI for the DX.Comply IDE plugin.
/// </summary>
///
/// <remarks>
/// The frame uses a regular DFM-backed layout so RAD Studio can apply its normal
/// DPI scaling behavior consistently inside the Tools &gt; Options host dialog.
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
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.OleCtrls,
  Vcl.StdCtrls,
  SHDocVw,
  DX.Comply.IDE.Settings,
  DX.Comply.Report.Intf;

type
  /// <summary>
  /// Options frame hosted inside the RAD Studio environment options dialog.
  /// </summary>
  TFrameDXComplyOptions = class(TFrame)
    FPageControl: TPageControl;
    FSettingsTabSheet: TTabSheet;
    FInfoTabSheet: TTabSheet;
    FReadmeBrowserHostPanel: TPanel;
    FPromptBeforeBuildCheckBox: TCheckBox;
    FSaveAllModifiedFilesCheckBox: TCheckBox;
    FUseActiveBuildConfigurationCheckBox: TCheckBox;
    FOpenHtmlReportAfterGenerateCheckBox: TCheckBox;
    FWarnWhenCompositionEmptyCheckBox: TCheckBox;
    FContinueOnBuildFailureCheckBox: TCheckBox;
    FReportEnabledCheckBox: TCheckBox;
    ReportFormatLabel: TLabel;
    FReportFormatComboBox: TComboBox;
    ReportOutputBasePathLabel: TLabel;
    FReportOutputBasePathEdit: TEdit;
    FReportIncludeWarningsCheckBox: TCheckBox;
    FReportIncludeCompositionCheckBox: TCheckBox;
    FReportIncludeBuildEvidenceCheckBox: TCheckBox;
    FAboutButton: TButton;
  private
    FReadmeBrowser: TWebBrowser;
    procedure AboutButtonClick(Sender: TObject);
    procedure InitializeReadmeBrowser;
    procedure LoadReadmeInfoPage;
    /// <summary>
    /// Returns the cached temporary HTML file used by the embedded README preview.
    /// </summary>
    function GetReadmePreviewFilePath: string;
  public
    /// <summary>
    /// Returns the caption used for the single DX.Comply node in the IDE options tree.
    /// </summary>
    class function OptionsPageCaption: string; static;
    /// <summary>
    /// Scales a design-time pixel value from 96 PPI to the requested target PPI.
    /// </summary>
    class function ScaleDesignValue(const AValue, APixelsPerInch: Integer): Integer; static;
    constructor Create(AOwner: TComponent); override;
    procedure LoadSettings(const ASettings: TDXComplyIDESettings);
    function SaveSettings: TDXComplyIDESettings;
    function ValidateSettings(out AMessage: string): Boolean;
  end;

implementation

{$R *.dfm}

uses
  DX.Comply.IDE.AboutDialog,
  DX.Comply.IDE.ReadmeSupport,
  System.IOUtils,
  System.SysUtils,
  Vcl.Dialogs;

class function TFrameDXComplyOptions.OptionsPageCaption: string;
begin
  Result := DXComplyOptionsPageCaption;
end;

class function TFrameDXComplyOptions.ScaleDesignValue(const AValue, APixelsPerInch: Integer): Integer;
begin
  Result := DXComplyScaleDesignValue(AValue, APixelsPerInch);
end;

constructor TFrameDXComplyOptions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := alClient;
  FAboutButton.OnClick := AboutButtonClick;
  FPageControl.ActivePage := FSettingsTabSheet;
  InitializeReadmeBrowser;
  LoadReadmeInfoPage;
end;

procedure TFrameDXComplyOptions.AboutButtonClick(Sender: TObject);
begin
  ShowDXComplyAboutDialog;
end;

procedure TFrameDXComplyOptions.InitializeReadmeBrowser;
begin
  FReadmeBrowser := TWebBrowser.Create(Self);
  FReadmeBrowserHostPanel.InsertControl(FReadmeBrowser);
  FReadmeBrowser.Align := alClient;
  FReadmeBrowser.TabStop := False;
  FReadmeBrowser.Silent := True;
end;

function TFrameDXComplyOptions.GetReadmePreviewFilePath: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'DX.Comply');
  TDirectory.CreateDirectory(Result);
  Result := TPath.Combine(Result, 'readme-preview.html');
end;

procedure TFrameDXComplyOptions.LoadReadmeInfoPage;
var
  LPreviewFilePath: string;
begin
  LPreviewFilePath := GetReadmePreviewFilePath;
  TFile.WriteAllText(LPreviewFilePath, BuildDXComplyReadmeHtmlDocument,
    TEncoding.UTF8);
  if Assigned(FReadmeBrowser) then
    FReadmeBrowser.Navigate(LPreviewFilePath);
end;

procedure TFrameDXComplyOptions.LoadSettings(const ASettings: TDXComplyIDESettings);
begin
  FPromptBeforeBuildCheckBox.Checked := ASettings.PromptBeforeBuild;
  FSaveAllModifiedFilesCheckBox.Checked := ASettings.SaveAllModifiedFilesBeforeBuild;
  FUseActiveBuildConfigurationCheckBox.Checked := ASettings.UseActiveBuildConfiguration;
  FOpenHtmlReportAfterGenerateCheckBox.Checked := ASettings.OpenHtmlReportAfterGenerate;
  FWarnWhenCompositionEmptyCheckBox.Checked := ASettings.WarnWhenCompositionEvidenceIsEmpty;
  FContinueOnBuildFailureCheckBox.Checked := ASettings.ContinueWithoutDeepEvidenceOnBuildFailure;
  FReportEnabledCheckBox.Checked := ASettings.HumanReadableReport.Enabled;
  case ASettings.HumanReadableReport.Format of
    hrfHtml: FReportFormatComboBox.ItemIndex := 1;
    hrfBoth: FReportFormatComboBox.ItemIndex := 2;
  else
    FReportFormatComboBox.ItemIndex := 0;
  end;
  FReportOutputBasePathEdit.Text := ASettings.HumanReadableReport.OutputBasePath;
  FReportIncludeWarningsCheckBox.Checked := ASettings.HumanReadableReport.IncludeWarnings;
  FReportIncludeCompositionCheckBox.Checked := ASettings.HumanReadableReport.IncludeCompositionEvidence;
  FReportIncludeBuildEvidenceCheckBox.Checked := ASettings.HumanReadableReport.IncludeBuildEvidence;
end;

function TFrameDXComplyOptions.SaveSettings: TDXComplyIDESettings;
begin
  Result := TDXComplyIDESettings.Default;
  Result.AutoBuildMode := abmAlways;
  Result.PromptBeforeBuild := FPromptBeforeBuildCheckBox.Checked;
  Result.SaveAllModifiedFilesBeforeBuild := FSaveAllModifiedFilesCheckBox.Checked;
  Result.UseActiveBuildConfiguration := FUseActiveBuildConfigurationCheckBox.Checked;
  Result.ContinueWithoutDeepEvidenceOnBuildFailure := FContinueOnBuildFailureCheckBox.Checked;
  Result.OpenHtmlReportAfterGenerate := FOpenHtmlReportAfterGenerateCheckBox.Checked;
  Result.WarnWhenCompositionEvidenceIsEmpty := FWarnWhenCompositionEmptyCheckBox.Checked;
  Result.HumanReadableReport.Enabled := FReportEnabledCheckBox.Checked;
  case FReportFormatComboBox.ItemIndex of
    1: Result.HumanReadableReport.Format := hrfHtml;
    2: Result.HumanReadableReport.Format := hrfBoth;
  else
    Result.HumanReadableReport.Format := hrfMarkdown;
  end;
  Result.HumanReadableReport.OutputBasePath := Trim(FReportOutputBasePathEdit.Text);
  Result.HumanReadableReport.IncludeWarnings := FReportIncludeWarningsCheckBox.Checked;
  Result.HumanReadableReport.IncludeCompositionEvidence := FReportIncludeCompositionCheckBox.Checked;
  Result.HumanReadableReport.IncludeBuildEvidence := FReportIncludeBuildEvidenceCheckBox.Checked;
end;

function TFrameDXComplyOptions.ValidateSettings(out AMessage: string): Boolean;
begin
  AMessage := '';
  Result := True;
end;

end.