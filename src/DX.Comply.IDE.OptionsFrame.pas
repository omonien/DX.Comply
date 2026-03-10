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
  System.Variants,
  Winapi.ActiveX,
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
    BuildScriptPathLabel: TLabel;
    FBuildScriptPathEdit: TEdit;
    FBrowseScriptButton: TButton;
    DelphiVersionLabel: TLabel;
    FDelphiVersionEdit: TEdit;
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
    FReadmeHtml: string;
    FReadmeHtmlLoaded: Boolean;
    procedure AboutButtonClick(Sender: TObject);
    procedure BrowseScriptButtonClick(Sender: TObject);
    procedure InitializeReadmeBrowser;
    procedure LoadReadmeInfoPage;
    procedure ReadmeBrowserDocumentComplete(ASender: TObject;
      const pDisp: IDispatch; const URL: OleVariant);
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
  FBrowseScriptButton.OnClick := BrowseScriptButtonClick;
  FAboutButton.OnClick := AboutButtonClick;
  FPageControl.ActivePage := FSettingsTabSheet;
  InitializeReadmeBrowser;
  LoadReadmeInfoPage;
end;

procedure TFrameDXComplyOptions.AboutButtonClick(Sender: TObject);
begin
  ShowDXComplyAboutDialog;
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

procedure TFrameDXComplyOptions.InitializeReadmeBrowser;
begin
  FReadmeBrowser := TWebBrowser.Create(Self);
  FReadmeBrowserHostPanel.InsertControl(FReadmeBrowser);
  FReadmeBrowser.Align := alClient;
  FReadmeBrowser.TabStop := False;
  FReadmeBrowser.Silent := True;
  FReadmeBrowser.OnDocumentComplete := ReadmeBrowserDocumentComplete;
end;

procedure TFrameDXComplyOptions.LoadReadmeInfoPage;
begin
  FReadmeHtml := BuildDXComplyReadmeHtmlDocument;
  FReadmeHtmlLoaded := False;
  if Assigned(FReadmeBrowser) then
    FReadmeBrowser.Navigate('about:blank');
end;

procedure TFrameDXComplyOptions.ReadmeBrowserDocumentComplete(ASender: TObject;
  const pDisp: IDispatch; const URL: OleVariant);
var
  LDocument: OleVariant;
  LUrl: string;
begin
  if FReadmeHtmlLoaded or (Trim(FReadmeHtml) = '') then
    Exit;

  LUrl := VarToStrDef(URL, '');
  if (LUrl <> '') and not SameText(LUrl, 'about:blank') then
    Exit;

  if not Assigned(FReadmeBrowser.Document) then
    Exit;

  LDocument := FReadmeBrowser.Document;
  FReadmeHtmlLoaded := True;
  LDocument.Open;
  LDocument.Write(VarArrayOf([FReadmeHtml]));
  LDocument.Close;
end;

procedure TFrameDXComplyOptions.LoadSettings(const ASettings: TDXComplyIDESettings);
begin
  FPromptBeforeBuildCheckBox.Checked := ASettings.PromptBeforeBuild;
  FSaveAllModifiedFilesCheckBox.Checked := ASettings.SaveAllModifiedFilesBeforeBuild;
  FUseActiveBuildConfigurationCheckBox.Checked := ASettings.UseActiveBuildConfiguration;
  FOpenHtmlReportAfterGenerateCheckBox.Checked := ASettings.OpenHtmlReportAfterGenerate;
  FWarnWhenCompositionEmptyCheckBox.Checked := ASettings.WarnWhenCompositionEvidenceIsEmpty;
  FBuildScriptPathEdit.Text := ASettings.BuildScriptPath;
  FDelphiVersionEdit.Text := IntToStr(ASettings.DelphiVersionOverride);
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
  Result.ContinueWithoutDeepEvidenceOnBuildFailure := False;
  Result.OpenHtmlReportAfterGenerate := FOpenHtmlReportAfterGenerateCheckBox.Checked;
  Result.WarnWhenCompositionEvidenceIsEmpty := FWarnWhenCompositionEmptyCheckBox.Checked;
  Result.BuildScriptPath := Trim(FBuildScriptPathEdit.Text);
  Result.DelphiVersionOverride := StrToIntDef(Trim(FDelphiVersionEdit.Text), -1);
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