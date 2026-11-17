/// <summary>
/// DX.Comply.IDE.SbomHeaderDialog
/// Per-project dialog for the SBOM header and a CPE for the product.
/// </summary>
///
/// <remarks>
/// The SBOM tab edits sbomCreator, product.supplier, product.supplierUrl,
/// product.licence, product.version and product.cpe in the .dxcomply.json
/// next to the project. The CPE tab searches the NVD CPE API when the user
/// starts the search, applies a selected name to product.cpe, and can write
/// a CPE Dictionary 2.3 submission plus mail text. The NVD API key is stored
/// per Windows user in the registry, not in the project file and not in the
/// IDE options INI. DX.Comply does not send the mail.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.SbomHeaderDialog;

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Vcl.Dialogs,
  Vcl.ComCtrls,
  DX.Comply.Cpe.Nvd,
  DX.Comply.Cpe.NvdKey,
  DX.Comply.SbomHeaderConfig;

type
  /// <summary>
  /// Modal dialog that edits the SBOM header keys of one project and can
  /// look up or request a CPE for that product.
  /// </summary>
  TFormDXComplySbomHeaderDialog = class(TForm)
  private
    FProjectPath: string;
    FConfigPath: string;
    FRepoUrl: string;
    FApiKeyLoading: Boolean;
    FApiKeyEdited: Boolean;
    FSearchSerial: Integer;
    FPages: TPageControl;
    FSbomTab: TTabSheet;
    FEditSbomCreator: TEdit;
    FEditSupplier: TEdit;
    FEditSupplierUrl: TEdit;
    FEditLicence: TEdit;
    FEditProductVersion: TEdit;
    FEditVendor: TEdit;
    FEditProduct: TEdit;
    FEditVersion: TEdit;
    FEditKeyword: TEdit;
    FEditApiKey: TEdit;
    FEditCpe: TEdit;
    FListMatches: TListView;
    FLabelError: TLabel;
    FLabelStatus: TLabel;
    FLabelPaths: TLabel;
    FButtonSearch: TButton;
    FButtonSave: TButton;
    FButtonCancel: TButton;
    function S(AValue: Integer): Integer;
    procedure BuildUI(const AProjectPath: string; const AWarnings: TArray<string>);
    function AddField(AParent: TWinControl; var ATop: Integer;
      const ACaption, AHint: string): TEdit;
    function GetHeader: TSbomHeaderData;
    procedure SetHeader(const AHeader: TSbomHeaderData);
    procedure LoadCpeProposal;
    procedure LoadApiKey;
    procedure OnSaveClick(ASender: TObject);
    procedure OnSearchClick(ASender: TObject);
    procedure OnKeywordEnter(ASender: TObject);
    procedure OnKeywordExit(ASender: TObject);
    procedure ShowSearchResult(const AResult: TNvdCpeSearchResult;
      const AResolved: TNvdApiKeyResolution);
    procedure FocusSbomField(AEdit: TEdit);
    procedure OnApplyClick(ASender: TObject);
    procedure OnSaveApiKeyClick(ASender: TObject);
    procedure OnApiKeyChange(ASender: TObject);
    procedure OnApiKeyLinkClick(ASender: TObject);
    procedure OnSubmissionClick(ASender: TObject);
    function SbomOutputPath: string;
  public
    constructor Create(AOwner: TComponent; const AProjectPath: string;
      const AWarnings: TArray<string>); reintroduce;
    destructor Destroy; override;
    property Header: TSbomHeaderData read GetHeader write SetHeader;
    property ConfigPath: string read FConfigPath;
  end;

/// <summary>
/// Shows the SBOM and CPE dialog for the project AProjectPath (.dproj).
/// AWarnings are the CRA/BSI header warnings of the last generation; when
/// not empty the dialog says that data is missing. Returns True when the
/// user saved the data to .dxcomply.json.
/// </summary>
function ShowSbomHeaderDialog(const AProjectPath: string;
  const AWarnings: TArray<string>): Boolean;

implementation

uses
  System.IOUtils,
  System.JSON,
  System.Math,
  System.SyncObjs,
  Winapi.ShellAPI,
  Vcl.Clipbrd,
  DX.Comply.Cpe,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.IDE.Logger,
  DX.Comply.IDE.Settings;

const
  cStateDeprecated = 'deprecated';
  cStateCurrent    = 'current';
  cColorHeader   = $2B2E36;
  cColorTitle    = $E8ECEF;
  cColorSubtitle = $9AA0A8;
  cColorHint     = $707070;
  cColorError    = $1C2BC4;
  cColorNote     = $D7F3FF;
  cDialogWidth   = 740;
  cMargin        = 16;
  cLabelWidth    = 150;

var
  // The dialog that may still receive a search result. A result that
  // arrives after the dialog was closed is dropped.
  GActiveDialog: TFormDXComplySbomHeaderDialog = nil;
  // Counts searches over all dialog instances, so a late result is not
  // taken for the answer to a newer search.
  GSearchSerial: Integer = 0;
  // Search threads that still run code of this package.
  GSearchThreads: Integer = 0;

{ TFormDXComplySbomHeaderDialog }

constructor TFormDXComplySbomHeaderDialog.Create(AOwner: TComponent;
  const AProjectPath: string; const AWarnings: TArray<string>);
begin
  inherited CreateNew(AOwner);
  FProjectPath := AProjectPath;
  FConfigPath := TSbomHeaderConfig.ConfigPathForProject(AProjectPath);
  BuildUI(AProjectPath, AWarnings);
  LoadCpeProposal;
  LoadApiKey;
  GActiveDialog := Self;
end;

destructor TFormDXComplySbomHeaderDialog.Destroy;
begin
  if GActiveDialog = Self then
    GActiveDialog := nil;
  inherited;
end;

function TFormDXComplySbomHeaderDialog.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

function TFormDXComplySbomHeaderDialog.AddField(AParent: TWinControl;
  var ATop: Integer; const ACaption, AHint: string): TEdit;
begin
  var LLabel := TLabel.Create(Self);
  LLabel.Parent := AParent;
  LLabel.Caption := ACaption;
  LLabel.Left := S(cMargin);
  LLabel.Top := ATop + S(3);

  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.Left := S(cMargin + cLabelWidth);
  Result.Top := ATop;
  Result.Width := S(cDialogWidth - 2 * cMargin - cLabelWidth - 8);
  LLabel.FocusControl := Result;

  var LHint := TLabel.Create(Self);
  LHint.Parent := AParent;
  LHint.AutoSize := False;
  LHint.WordWrap := True;
  LHint.Left := Result.Left;
  LHint.Top := Result.Top + Result.Height + S(2);
  LHint.Width := Result.Width;
  LHint.Height := S(28);
  LHint.Caption := AHint;
  LHint.Font.Size := 8;
  LHint.Font.Color := cColorHint;

  ATop := LHint.Top + LHint.Height + S(6);
end;

procedure TFormDXComplySbomHeaderDialog.BuildUI(const AProjectPath: string;
  const AWarnings: TArray<string>);
var
  LTop, LSbomBottom, LContentHeight, LWanted, LAvailable: Integer;
  LCpeTab: TTabSheet;
  LSbomBox, LCpeBox: TScrollBox;
  LColumn: TListColumn;
begin
  Caption := 'DX.Comply - SBOM and CPE';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  Color := clWhite;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := S(cDialogWidth);

  var LHeaderPanel := TPanel.Create(Self);
  LHeaderPanel.Parent := Self;
  LHeaderPanel.Align := alTop;
  LHeaderPanel.Height := S(64);
  LHeaderPanel.BevelOuter := bvNone;
  LHeaderPanel.Color := cColorHeader;
  LHeaderPanel.ParentBackground := False;

  var LTitle := TLabel.Create(Self);
  LTitle.Parent := LHeaderPanel;
  LTitle.Left := S(cMargin);
  LTitle.Top := S(10);
  LTitle.Caption := 'SBOM and CPE';
  LTitle.Font.Name := 'Segoe UI Semibold';
  LTitle.Font.Size := 14;
  LTitle.Font.Color := cColorTitle;

  var LSubtitle := TLabel.Create(Self);
  LSubtitle.Parent := LHeaderPanel;
  LSubtitle.Left := S(cMargin);
  LSubtitle.Top := S(38);
  LSubtitle.Caption := ExtractFileName(AProjectPath);
  LSubtitle.Font.Color := cColorSubtitle;

  var LBottom := TPanel.Create(Self);
  LBottom.Parent := Self;
  LBottom.Align := alBottom;
  LBottom.Height := S(78);
  LBottom.BevelOuter := bvNone;
  LBottom.Color := clWhite;
  LBottom.ParentBackground := False;

  FLabelError := TLabel.Create(Self);
  FLabelError.Parent := LBottom;
  FLabelError.AutoSize := False;
  FLabelError.WordWrap := True;
  FLabelError.Left := S(cMargin);
  FLabelError.Top := S(4);
  FLabelError.Width := S(cDialogWidth - 2 * cMargin);
  FLabelError.Height := S(32);
  FLabelError.Font.Color := cColorError;
  FLabelError.Caption := '';

  var LFile := TLabel.Create(Self);
  LFile.Parent := LBottom;
  LFile.AutoSize := False;
  LFile.EllipsisPosition := epPathEllipsis;
  LFile.Left := S(cMargin);
  LFile.Top := S(40);
  LFile.Width := S(cDialogWidth - 2 * cMargin - 190);
  LFile.Caption := 'File: ' + FConfigPath;
  LFile.Hint := FConfigPath;
  LFile.ShowHint := True;
  LFile.Font.Color := cColorHint;

  FButtonCancel := TButton.Create(Self);
  FButtonCancel.Parent := LBottom;
  FButtonCancel.Caption := 'Cancel';
  FButtonCancel.Cancel := True;
  FButtonCancel.ModalResult := mrCancel;
  FButtonCancel.Width := S(85);
  FButtonCancel.Height := S(28);
  FButtonCancel.Left := S(cDialogWidth - cMargin - 85);
  FButtonCancel.Top := S(36);

  FButtonSave := TButton.Create(Self);
  FButtonSave.Parent := LBottom;
  FButtonSave.Caption := 'Save';
  FButtonSave.Default := True;
  FButtonSave.Width := S(85);
  FButtonSave.Height := S(28);
  FButtonSave.Left := FButtonCancel.Left - S(85 + 8);
  FButtonSave.Top := FButtonCancel.Top;
  FButtonSave.OnClick := OnSaveClick;

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;

  FSbomTab := TTabSheet.Create(Self);
  FSbomTab.PageControl := FPages;
  FSbomTab.Caption := 'SBOM';

  LCpeTab := TTabSheet.Create(Self);
  LCpeTab.PageControl := FPages;
  LCpeTab.Caption := 'CPE';

  // The fields sit in a scroll box per tab. On a low screen the dialog is
  // made shorter and the tab scrolls, so Save and Cancel stay visible.
  LSbomBox := TScrollBox.Create(Self);
  LSbomBox.Parent := FSbomTab;
  LSbomBox.Align := alClient;
  LSbomBox.BorderStyle := bsNone;
  LSbomBox.HorzScrollBar.Visible := False;

  LCpeBox := TScrollBox.Create(Self);
  LCpeBox.Parent := LCpeTab;
  LCpeBox.Align := alClient;
  LCpeBox.BorderStyle := bsNone;
  LCpeBox.HorzScrollBar.Visible := False;

  LTop := S(12);
  if Length(AWarnings) > 0 then
  begin
    var LNote := TPanel.Create(Self);
    LNote.Parent := LSbomBox;
    LNote.Left := S(cMargin);
    LNote.Top := LTop;
    LNote.Width := S(cDialogWidth - 2 * cMargin - 8);
    LNote.Height := S(40);
    LNote.BevelOuter := bvNone;
    LNote.Color := cColorNote;
    LNote.ParentBackground := False;

    var LNoteLabel := TLabel.Create(Self);
    LNoteLabel.Parent := LNote;
    LNoteLabel.AutoSize := False;
    LNoteLabel.WordWrap := True;
    LNoteLabel.Left := S(8);
    LNoteLabel.Top := S(4);
    LNoteLabel.Width := LNote.Width - S(16);
    LNoteLabel.Height := LNote.Height - S(8);
    LNoteLabel.Caption := Format('The last SBOM generation reported %d CRA/BSI warning(s) ' +
      'about missing header data. Fill in the fields below and generate the SBOM again.',
      [Length(AWarnings)]);
    LTop := LNote.Top + LNote.Height + S(10);
  end;

  var LIntro := TLabel.Create(Self);
  LIntro.Parent := LSbomBox;
  LIntro.AutoSize := False;
  LIntro.WordWrap := True;
  LIntro.Left := S(cMargin);
  LIntro.Top := LTop;
  LIntro.Width := S(cDialogWidth - 2 * cMargin - 8);
  LIntro.Height := S(42);
  LIntro.Caption := 'BSI TR-03183-2 and the Cyber Resilience Act expect these values in the ' +
    'SBOM header. They are saved in the .dxcomply.json of this project, so the ' +
    'command line tool (dxcomply --ci) uses the same values. Leave a field empty to ' +
    'remove it from the file.';
  LTop := LIntro.Top + LIntro.Height + S(6);

  FEditSbomCreator := AddField(LSbomBox, LTop, 'SBOM creator:',
    'Email address or http(s) URL of the person or organisation that creates the SBOM. ' +
    'Required by BSI TR-03183-2 section 5.2.1. Key: sbomCreator');
  FEditSupplier := AddField(LSbomBox, LTop, 'Supplier / manufacturer:',
    'Name of the manufacturer. Empty uses CompanyName from the project version info. ' +
    'Key: product.supplier');
  FEditSupplierUrl := AddField(LSbomBox, LTop, 'Supplier URL:',
    'http(s) contact of the manufacturer. Not needed when the supplier is an email ' +
    'address. Key: product.supplierUrl');
  FEditLicence := AddField(LSbomBox, LTop, 'Licence:',
    'Distribution licence as SPDX expression, for example MIT, Apache-2.0 or ' +
    'LicenseRef-Proprietary. Key: product.licence');
  FEditProductVersion := AddField(LSbomBox, LTop, 'Product version:',
    'Optional. Empty uses the version info of the project. Key: product.version');
  FEditCpe := AddField(LSbomBox, LTop, 'Product CPE:',
    'Optional CPE 2.3 formatted string or CPE 2.2 URI. Written on the product and on ' +
    'the built program. Key: product.cpe. The CPE tab can search for one.');
  LSbomBottom := LTop;

  LTop := S(12);
  var LCpeNote := TLabel.Create(Self);
  LCpeNote.Parent := LCpeBox;
  LCpeNote.AutoSize := False;
  LCpeNote.WordWrap := True;
  LCpeNote.Left := S(cMargin);
  LCpeNote.Top := LTop;
  LCpeNote.Width := S(cDialogWidth - 2 * cMargin - 8);
  LCpeNote.Height := S(32);
  LCpeNote.Caption := 'The vendor and product strings are a proposal. NIST may normalize them. ' +
    'A search runs only when you click Search.';
  LTop := LCpeNote.Top + LCpeNote.Height + S(4);

  FEditVendor := AddField(LCpeBox, LTop, 'Vendor:',
    'Proposal for the CPE search and for a dictionary submission. Saving the SBOM tab does not replace product.supplier with this value.');
  FEditProduct := AddField(LCpeBox, LTop, 'Product:',
    'Proposal for the search. Empty starts from product.name, then the project file name.');
  FEditVersion := AddField(LCpeBox, LTop, 'Version:',
    'Proposal for a new CPE. Empty starts from product.version, then the project version info.');
  FEditKeyword := AddField(LCpeBox, LTop, 'Keyword:',
    'Sent to the NVD CPE API as keywordSearch. Filled once from the vendor and product. You can edit it.');
  // Enter in this field starts the search instead of Save.
  FEditKeyword.OnEnter := OnKeywordEnter;
  FEditKeyword.OnExit := OnKeywordExit;

  var LKeyLabel := TLabel.Create(Self);
  LKeyLabel.Parent := LCpeBox;
  LKeyLabel.Caption := 'NVD API key:';
  LKeyLabel.Left := S(cMargin);
  LKeyLabel.Top := LTop + S(3);

  FEditApiKey := TEdit.Create(Self);
  FEditApiKey.Parent := LCpeBox;
  FEditApiKey.Left := S(cMargin + cLabelWidth);
  FEditApiKey.Top := LTop;
  FEditApiKey.Width := S(280);
  FEditApiKey.PasswordChar := '*';
  FEditApiKey.OnChange := OnApiKeyChange;
  LKeyLabel.FocusControl := FEditApiKey;

  var LSaveKey := TButton.Create(Self);
  LSaveKey.Parent := LCpeBox;
  LSaveKey.Caption := 'Save key';
  LSaveKey.Left := FEditApiKey.Left + FEditApiKey.Width + S(8);
  LSaveKey.Top := LTop - S(1);
  LSaveKey.Width := S(80);
  LSaveKey.Height := S(24);
  LSaveKey.OnClick := OnSaveApiKeyClick;

  var LKeyHint := TLabel.Create(Self);
  LKeyHint.Parent := LCpeBox;
  LKeyHint.AutoSize := False;
  LKeyHint.WordWrap := True;
  LKeyHint.Left := FEditApiKey.Left;
  LKeyHint.Top := FEditApiKey.Top + FEditApiKey.Height + S(2);
  LKeyHint.Width := S(cDialogWidth - cMargin - cLabelWidth - 24);
  LKeyHint.Height := S(28);
  LKeyHint.Font.Size := 8;
  LKeyHint.Font.Color := cColorHint;
  LKeyHint.Caption := 'Optional. Saved per Windows user in HKCU\Software\Developer Experts\DX.Comply\NIST. ' +
    'Other IDE settings stay in the options INI. Not written to .dxcomply.json.';

  var LKeyLink := TLabel.Create(Self);
  LKeyLink.Parent := LCpeBox;
  LKeyLink.AutoSize := True;
  LKeyLink.Left := FEditApiKey.Left;
  LKeyLink.Top := LKeyHint.Top + LKeyHint.Height;
  LKeyLink.Caption := cNvdApiKeyRequestUrl;
  LKeyLink.Font.Color := clBlue;
  LKeyLink.Font.Style := [fsUnderline];
  LKeyLink.Cursor := crHandPoint;
  LKeyLink.OnClick := OnApiKeyLinkClick;
  LTop := LKeyLink.Top + LKeyLink.Height + S(8);

  FButtonSearch := TButton.Create(Self);
  FButtonSearch.Parent := LCpeBox;
  FButtonSearch.Caption := 'Search';
  FButtonSearch.Left := S(cMargin + cLabelWidth);
  FButtonSearch.Top := LTop;
  FButtonSearch.Width := S(90);
  FButtonSearch.Height := S(26);
  FButtonSearch.OnClick := OnSearchClick;

  FLabelStatus := TLabel.Create(Self);
  FLabelStatus.Parent := LCpeBox;
  FLabelStatus.AutoSize := False;
  FLabelStatus.WordWrap := True;
  FLabelStatus.Left := FButtonSearch.Left + FButtonSearch.Width + S(8);
  FLabelStatus.Top := LTop;
  FLabelStatus.Width := S(cDialogWidth - cMargin - cLabelWidth - 120);
  FLabelStatus.Height := S(32);
  FLabelStatus.Caption := '';
  LTop := FButtonSearch.Top + FButtonSearch.Height + S(8);

  FListMatches := TListView.Create(Self);
  FListMatches.Parent := LCpeBox;
  FListMatches.Left := S(cMargin);
  FListMatches.Top := LTop;
  FListMatches.Width := S(cDialogWidth - 2 * cMargin - 8);
  FListMatches.Height := S(120);
  FListMatches.ViewStyle := vsReport;
  FListMatches.ReadOnly := True;
  FListMatches.RowSelect := True;
  FListMatches.HideSelection := False;
  LColumn := FListMatches.Columns.Add;
  LColumn.Caption := 'CPE';
  LColumn.Width := S(360);
  LColumn := FListMatches.Columns.Add;
  LColumn.Caption := 'Title';
  LColumn.Width := S(220);
  LColumn := FListMatches.Columns.Add;
  LColumn.Caption := 'State';
  LColumn.Width := S(90);
  LTop := FListMatches.Top + FListMatches.Height + S(8);

  var LApply := TButton.Create(Self);
  LApply.Parent := LCpeBox;
  LApply.Caption := 'Apply selected CPE';
  LApply.Left := S(cMargin);
  LApply.Top := LTop;
  LApply.Width := S(140);
  LApply.Height := S(26);
  LApply.OnClick := OnApplyClick;

  var LSubmit := TButton.Create(Self);
  LSubmit.Parent := LCpeBox;
  LSubmit.Caption := 'Save dictionary and mail text';
  LSubmit.Left := LApply.Left + LApply.Width + S(8);
  LSubmit.Top := LTop;
  LSubmit.Width := S(200);
  LSubmit.Height := S(26);
  LSubmit.OnClick := OnSubmissionClick;
  LTop := LApply.Top + LApply.Height + S(6);

  FLabelPaths := TLabel.Create(Self);
  FLabelPaths.Parent := LCpeBox;
  FLabelPaths.AutoSize := False;
  FLabelPaths.WordWrap := True;
  FLabelPaths.Left := S(cMargin);
  FLabelPaths.Top := LTop;
  FLabelPaths.Width := S(cDialogWidth - 2 * cMargin - 8);
  FLabelPaths.Height := S(44);
  FLabelPaths.Font.Color := cColorHint;
  FLabelPaths.Caption := 'Dictionary and mail text are written next to the SBOM when you ask. DX.Comply does not send the message.';

  // Height of the taller tab, plus the tab row, the header and the buttons.
  // Limited to the work area of the screen.
  LContentHeight := Max(LSbomBottom, FLabelPaths.Top + FLabelPaths.Height) + S(8);
  LWanted := LHeaderPanel.Height + LBottom.Height + S(34) + LContentHeight;
  LAvailable := Screen.WorkAreaHeight - S(48);
  if LAvailable < S(320) then
    LAvailable := S(320);
  ClientHeight := Min(LWanted, LAvailable);
  ActiveControl := FEditSbomCreator;
end;

function TFormDXComplySbomHeaderDialog.GetHeader: TSbomHeaderData;
begin
  Result.SbomCreator := Trim(FEditSbomCreator.Text);
  Result.Supplier := Trim(FEditSupplier.Text);
  Result.SupplierUrl := Trim(FEditSupplierUrl.Text);
  Result.Licence := Trim(FEditLicence.Text);
  Result.ProductVersion := Trim(FEditProductVersion.Text);
  Result.Cpe := Trim(FEditCpe.Text);
end;

procedure TFormDXComplySbomHeaderDialog.SetHeader(const AHeader: TSbomHeaderData);
begin
  FEditSbomCreator.Text := AHeader.SbomCreator;
  FEditSupplier.Text := AHeader.Supplier;
  FEditSupplierUrl.Text := AHeader.SupplierUrl;
  FEditLicence.Text := AHeader.Licence;
  FEditProductVersion.Text := AHeader.ProductVersion;
  FEditCpe.Text := AHeader.Cpe;
end;

procedure TFormDXComplySbomHeaderDialog.LoadCpeProposal;
var
  LRootValue: TJSONValue;
  LRoot, LProduct: TJSONObject;
  LSubmission: TCpeSubmission;
  LText: string;
begin
  FRepoUrl := '';
  LSubmission.Vendor := '';
  LSubmission.Product := '';
  LSubmission.Version := '';
  if TFile.Exists(FConfigPath) then
  begin
    try
      LText := TFile.ReadAllText(FConfigPath, TEncoding.UTF8);
      LRootValue := TJSONObject.ParseJSONValue(LText);
      try
        if LRootValue is TJSONObject then
        begin
          LRoot := TJSONObject(LRootValue);
          if LRoot.GetValue('product') is TJSONObject then
          begin
            LProduct := TJSONObject(LRoot.GetValue('product'));
            if LProduct.GetValue('supplier') <> nil then
              LSubmission.Vendor := Trim(LProduct.GetValue('supplier').Value);
            if LProduct.GetValue('name') <> nil then
              LSubmission.Product := Trim(LProduct.GetValue('name').Value);
            if LProduct.GetValue('version') <> nil then
              LSubmission.Version := Trim(LProduct.GetValue('version').Value);
            if LProduct.GetValue('repoUrl') <> nil then
              FRepoUrl := Trim(LProduct.GetValue('repoUrl').Value);
          end;
        end;
      finally
        LRootValue.Free;
      end;
    except
      on Exception do
        ;
    end;
  end;
  FillEmptyCpeNamesFromProject(FProjectPath, '', '', LSubmission);
  if Trim(LSubmission.Product) = '' then
    LSubmission.Product := TPath.GetFileNameWithoutExtension(FProjectPath);
  FEditVendor.Text := LSubmission.Vendor;
  FEditProduct.Text := LSubmission.Product;
  FEditVersion.Text := LSubmission.Version;
  FEditKeyword.Text := CpeLookupKeyword(LSubmission.Vendor, LSubmission.Product);
end;

procedure TFormDXComplySbomHeaderDialog.LoadApiKey;
begin
  FApiKeyLoading := True;
  try
    FEditApiKey.Text := ReadNvdApiKeyFromRegistry;
    FApiKeyEdited := False;
  finally
    FApiKeyLoading := False;
  end;
end;

procedure TFormDXComplySbomHeaderDialog.OnApiKeyChange(ASender: TObject);
begin
  if not FApiKeyLoading then
    FApiKeyEdited := True;
end;

procedure TFormDXComplySbomHeaderDialog.OnApiKeyLinkClick(ASender: TObject);
begin
  ShellExecute(0, 'open', PChar(cNvdApiKeyRequestUrl), nil, nil, SW_SHOWNORMAL);
end;

procedure TFormDXComplySbomHeaderDialog.OnSaveApiKeyClick(ASender: TObject);
var
  LError: string;
begin
  if not TryWriteNvdApiKeyToRegistry(FEditApiKey.Text, LError) then
  begin
    FLabelStatus.Caption := LError;
    FLabelError.Caption := LError;
    Exit;
  end;
  FApiKeyEdited := False;
  if Trim(FEditApiKey.Text) = '' then
  begin
    FLabelStatus.Caption := 'NVD API key removed for this Windows user.';
    TIDELogger.Info('DX.Comply: NVD API key removed from the registry.');
  end
  else
  begin
    FLabelStatus.Caption := 'NVD API key saved for this Windows user.';
    TIDELogger.Info('DX.Comply: NVD API key saved in the registry.');
  end;
  FLabelError.Caption := '';
end;

procedure TFormDXComplySbomHeaderDialog.OnKeywordEnter(ASender: TObject);
begin
  FButtonSave.Default := False;
  FButtonSearch.Default := True;
end;

procedure TFormDXComplySbomHeaderDialog.OnKeywordExit(ASender: TObject);
begin
  FButtonSearch.Default := False;
  FButtonSave.Default := True;
end;

procedure TFormDXComplySbomHeaderDialog.OnSearchClick(ASender: TObject);
var
  LOption, LKeyword, LKey: string;
  LResolved: TNvdApiKeyResolution;
  LSerial: Integer;
  LSelf: TFormDXComplySbomHeaderDialog;
begin
  FListMatches.Items.Clear;
  FLabelError.Caption := '';
  LKeyword := Trim(FEditKeyword.Text);
  if LKeyword = '' then
  begin
    FLabelStatus.Caption := 'Enter a keyword before searching the NVD.';
    Exit;
  end;
  if FApiKeyEdited and (Trim(FEditApiKey.Text) <> '') then
    LOption := Trim(FEditApiKey.Text)
  else
    LOption := '';
  LResolved := ResolveNvdApiKey(LOption, nil);
  LKey := LResolved.Key;
  TIDELogger.Info('DX.Comply: ' + NvdApiKeyLogLine(LResolved));
  FLabelStatus.Caption := 'Searching... ' + NvdApiKeyLogLine(LResolved);
  FButtonSearch.Enabled := False;

  // The request runs in a thread, so the IDE stays usable while the NVD
  // answers or the connection times out. The result comes back on the main
  // thread. It is dropped when the dialog was closed in the meantime or a
  // newer search was started.
  Inc(GSearchSerial);
  FSearchSerial := GSearchSerial;
  LSerial := FSearchSerial;
  LSelf := Self;
  TInterlocked.Increment(GSearchThreads);
  TThread.CreateAnonymousThread(
    procedure
    var
      LResult: TNvdCpeSearchResult;
    begin
      try
        LResult := SearchNvdCpes(LKeyword, LKey);
        TThread.Queue(nil,
          procedure
          begin
            if (GActiveDialog = LSelf) and (LSelf.FSearchSerial = LSerial) then
              LSelf.ShowSearchResult(LResult, LResolved);
          end);
      finally
        TInterlocked.Decrement(GSearchThreads);
      end;
    end).Start;
end;

procedure TFormDXComplySbomHeaderDialog.ShowSearchResult(
  const AResult: TNvdCpeSearchResult; const AResolved: TNvdApiKeyResolution);
var
  LMatch: TNvdCpeMatch;
  LItem: TListItem;
  LState, LCount: string;
begin
  FButtonSearch.Enabled := True;
  if not AResult.IsSuccess then
  begin
    FLabelStatus.Caption := AResult.Error;
    MessageDlg(AResult.Error, mtError, [mbOK], 0);
    Exit;
  end;

  FListMatches.Items.BeginUpdate;
  try
    FListMatches.Items.Clear;
    for LMatch in AResult.Matches do
    begin
      LItem := FListMatches.Items.Add;
      LItem.Caption := LMatch.CpeName;
      LItem.SubItems.Add(LMatch.Title);
      if LMatch.Deprecated then
        LState := cStateDeprecated
      else
        LState := cStateCurrent;
      LItem.SubItems.Add(LState);
    end;
  finally
    FListMatches.Items.EndUpdate;
  end;

  if Length(AResult.Matches) = 0 then
    FLabelStatus.Caption := NvdApiKeyLogLine(AResolved) +
      '. No CPE was found. The vendor and product strings are a proposal. NIST may normalize them. ' +
      'Use Save dictionary and mail text to prepare a request. DX.Comply does not send it.'
  else
  begin
    LCount := NvdCpeMatchCountText(AResult);
    FLabelStatus.Caption := NvdApiKeyLogLine(AResolved) + '. Matches: ' + LCount + '.';
    if AResult.TotalResults > Length(AResult.Matches) then
      FLabelStatus.Caption := FLabelStatus.Caption + ' Narrow the keyword to see the others.';
  end;
end;

procedure TFormDXComplySbomHeaderDialog.OnApplyClick(ASender: TObject);
begin
  if (FListMatches.Selected = nil) or (Trim(FListMatches.Selected.Caption) = '') then
  begin
    FLabelStatus.Caption := 'Select a CPE name first.';
    Exit;
  end;
  // The NVD keeps a deprecated name only for reference. It was replaced.
  if (FListMatches.Selected.SubItems.Count > 1) and
     SameText(FListMatches.Selected.SubItems[1], cStateDeprecated) then
  begin
    if MessageDlg('The NVD marks this CPE name as deprecated. It was replaced by another name. ' +
      'Use it anyway?', mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;
  // Nothing is written here. Save writes product.cpe with the other
  // fields, and Cancel leaves the file as it was.
  FEditCpe.Text := Trim(FListMatches.Selected.Caption);
  FLabelError.Caption := '';
  FLabelStatus.Caption := 'Product CPE set on the SBOM tab. Click Save to write product.cpe.';
end;

function TFormDXComplySbomHeaderDialog.SbomOutputPath: string;
var
  LGenerator: TDxComplyGenerator;
  LFileConfig: TSbomConfig;
  LSettings: TDXComplyIDESettings;
begin
  LGenerator := TDxComplyGenerator.Create;
  try
    LFileConfig := LGenerator.LoadConfig(FConfigPath);
  finally
    LGenerator.Free;
  end;
  LSettings := TDXComplyIDESettingsStore.Load;
  Result := TSbomConfig.ResolveSbomOutputPath('bom.json',
    TSbomConfig.ChooseOutputDirectory(LSettings.OutputDir, LFileConfig.OutputDir),
    TPath.GetDirectoryName(FProjectPath), LFileConfig.Platform, LFileConfig.Configuration,
    False, False);
end;

procedure TFormDXComplySbomHeaderDialog.OnSubmissionClick(ASender: TObject);
var
  LSubmission: TCpeSubmission;
  LDictionary, LMail, LError: string;
begin
  LSubmission.Vendor := Trim(FEditVendor.Text);
  LSubmission.Product := Trim(FEditProduct.Text);
  LSubmission.Version := Trim(FEditVersion.Text);
  LSubmission.References := CpeReferencesFromUrls(Trim(FEditSupplierUrl.Text), FRepoUrl);
  if not WriteCpeSubmissionFiles(SbomOutputPath, FProjectPath, LSubmission,
    LDictionary, LMail, LError) then
  begin
    FLabelError.Caption := LError;
    FLabelStatus.Caption := LError;
    MessageDlg(LError, mtError, [mbOK], 0);
    Exit;
  end;
  Clipboard.AsText := BuildCpeMailText(LSubmission);
  FLabelError.Caption := '';
  FLabelStatus.Caption := 'Dictionary and mail text saved. The mail text is on the clipboard. DX.Comply does not send the message.';
  FLabelPaths.Caption := LDictionary + sLineBreak + LMail;
  TIDELogger.Info('DX.Comply: CPE dictionary written to ' + LDictionary);
end;

procedure TFormDXComplySbomHeaderDialog.FocusSbomField(AEdit: TEdit);
begin
  // The fields are on the SBOM tab. SetFocus raises for a control on a tab
  // that is not shown, so the tab is selected first.
  FPages.ActivePage := FSbomTab;
  if AEdit.CanFocus then
    AEdit.SetFocus;
end;

procedure TFormDXComplySbomHeaderDialog.OnSaveClick(ASender: TObject);
begin
  var LHeader := GetHeader;
  var LErrors := TSbomHeaderConfig.Validate(LHeader);
  if Length(LErrors) > 0 then
  begin
    FLabelError.Caption := string.Join(' ', LErrors);
    if not IsAcceptableBsiCreator(LHeader.SbomCreator) then
      FocusSbomField(FEditSbomCreator)
    else if (Trim(LHeader.SupplierUrl) <> '') and not IsBsiHttpUrl(LHeader.SupplierUrl) then
      FocusSbomField(FEditSupplierUrl)
    else
      FocusSbomField(FEditCpe);
    Exit;
  end;

  var LError: string;
  if not TSbomHeaderConfig.TryWrite(FConfigPath, LHeader, LError) then
  begin
    FLabelError.Caption := 'Could not save ' + FConfigPath + ': ' + LError;
    Exit;
  end;
  ModalResult := mrOk;
end;

function ShowSbomHeaderDialog(const AProjectPath: string;
  const AWarnings: TArray<string>): Boolean;
var
  LHeader: TSbomHeaderData;
  LError: string;
begin
  Result := False;
  var LConfigPath := TSbomHeaderConfig.ConfigPathForProject(AProjectPath);
  if not TSbomHeaderConfig.TryRead(LConfigPath, LHeader, LError) then
  begin
    MessageDlg('DX.Comply cannot read ' + LConfigPath + ':' + sLineBreak + LError +
      sLineBreak + sLineBreak + 'Fix the file in an editor, then open this dialog again.',
      mtError, [mbOK], 0);
    Exit;
  end;

  var LDialog := TFormDXComplySbomHeaderDialog.Create(nil, AProjectPath, AWarnings);
  try
    LDialog.Header := LHeader;
    Result := LDialog.ShowModal = mrOk;
  finally
    LDialog.Free;
  end;
end;

initialization

finalization
  // A search thread runs code of this package. When the package is unloaded
  // while a search is open, wait for it. Its own timeouts end it after
  // 40 seconds at the latest. Results still queued are then run, and they
  // do nothing because no dialog is left.
  while GSearchThreads > 0 do
    CheckSynchronize(50);
  CheckSynchronize(0);

end.
