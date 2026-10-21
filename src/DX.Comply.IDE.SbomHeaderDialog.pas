/// <summary>
/// DX.Comply.IDE.SbomHeaderDialog
/// Per-project dialog for the SBOM header data the CRA/BSI warnings ask for.
/// </summary>
///
/// <remarks>
/// The dialog edits sbomCreator, product.supplier, product.supplierUrl,
/// product.licence and product.version in the .dxcomply.json next to the
/// project. TSbomHeaderConfig does the reading, validation and merging, so
/// other keys in the file stay as they are and the CLI reads the same values.
/// The form is built in code like the progress dialog and scales with the
/// screen DPI.
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
  DX.Comply.SbomHeaderConfig;

type
  /// <summary>
  /// Modal dialog that edits the SBOM header keys of one project.
  /// </summary>
  TFormDXComplySbomHeaderDialog = class(TForm)
  private
    FConfigPath: string;
    FEditSbomCreator: TEdit;
    FEditSupplier: TEdit;
    FEditSupplierUrl: TEdit;
    FEditLicence: TEdit;
    FEditProductVersion: TEdit;
    FLabelError: TLabel;
    FButtonSave: TButton;
    FButtonCancel: TButton;
    function S(AValue: Integer): Integer;
    procedure BuildUI(const AProjectPath: string; const AWarnings: TArray<string>);
    function AddField(AParent: TWinControl; var ATop: Integer;
      const ACaption, AHint: string): TEdit;
    function GetHeader: TSbomHeaderData;
    procedure SetHeader(const AHeader: TSbomHeaderData);
    procedure OnSaveClick(ASender: TObject);
  public
    constructor Create(AOwner: TComponent; const AProjectPath: string;
      const AWarnings: TArray<string>); reintroduce;
    property Header: TSbomHeaderData read GetHeader write SetHeader;
    property ConfigPath: string read FConfigPath;
  end;

/// <summary>
/// Shows the SBOM header dialog for the project AProjectPath (.dproj).
/// AWarnings are the CRA/BSI header warnings of the last generation; when
/// not empty the dialog says that data is missing. Returns True when the
/// user saved the data to .dxcomply.json.
/// </summary>
function ShowSbomHeaderDialog(const AProjectPath: string;
  const AWarnings: TArray<string>): Boolean;

implementation

uses
  DX.Comply.Engine.Intf;

const
  cColorHeader   = $2B2E36;
  cColorTitle    = $E8ECEF;
  cColorSubtitle = $9AA0A8;
  cColorHint     = $707070;
  cColorError    = $1C2BC4;
  cColorNote     = $D7F3FF;
  cDialogWidth   = 620;
  cMargin        = 20;
  cLabelWidth    = 150;

{ TFormDXComplySbomHeaderDialog }

constructor TFormDXComplySbomHeaderDialog.Create(AOwner: TComponent;
  const AProjectPath: string; const AWarnings: TArray<string>);
begin
  inherited CreateNew(AOwner);
  FConfigPath := TSbomHeaderConfig.ConfigPathForProject(AProjectPath);
  BuildUI(AProjectPath, AWarnings);
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
  Result.Width := S(cDialogWidth - 2 * cMargin - cLabelWidth);
  LLabel.FocusControl := Result;

  var LHint := TLabel.Create(Self);
  LHint.Parent := AParent;
  LHint.AutoSize := False;
  LHint.WordWrap := True;
  LHint.Left := Result.Left;
  LHint.Top := Result.Top + Result.Height + S(2);
  LHint.Width := Result.Width;
  LHint.Height := S(32);
  LHint.Caption := AHint;
  LHint.Font.Size := 8;
  LHint.Font.Color := cColorHint;

  ATop := LHint.Top + LHint.Height + S(8);
end;

procedure TFormDXComplySbomHeaderDialog.BuildUI(const AProjectPath: string;
  const AWarnings: TArray<string>);
begin
  Caption := 'DX.Comply - SBOM Header Data';
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
  LTitle.Caption := 'SBOM Header Data';
  LTitle.Font.Name := 'Segoe UI Semibold';
  LTitle.Font.Size := 14;
  LTitle.Font.Color := cColorTitle;

  var LSubtitle := TLabel.Create(Self);
  LSubtitle.Parent := LHeaderPanel;
  LSubtitle.Left := S(cMargin);
  LSubtitle.Top := S(38);
  LSubtitle.Caption := ExtractFileName(AProjectPath);
  LSubtitle.Font.Color := cColorSubtitle;

  var LBody := TPanel.Create(Self);
  LBody.Parent := Self;
  LBody.Align := alClient;
  LBody.BevelOuter := bvNone;
  LBody.Color := clWhite;
  LBody.ParentBackground := False;

  var LTop := S(14);
  if Length(AWarnings) > 0 then
  begin
    var LNote := TPanel.Create(Self);
    LNote.Parent := LBody;
    LNote.Left := S(cMargin);
    LNote.Top := LTop;
    LNote.Width := S(cDialogWidth - 2 * cMargin);
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
    LTop := LNote.Top + LNote.Height + S(12);
  end;

  var LIntro := TLabel.Create(Self);
  LIntro.Parent := LBody;
  LIntro.AutoSize := False;
  LIntro.WordWrap := True;
  LIntro.Left := S(cMargin);
  LIntro.Top := LTop;
  LIntro.Width := S(cDialogWidth - 2 * cMargin);
  LIntro.Height := S(48);
  LIntro.Caption := 'BSI TR-03183-2 and the Cyber Resilience Act expect these values in the ' +
    'SBOM header. They are saved in the .dxcomply.json of this project, so the ' +
    'command line tool (dxcomply --ci) uses the same values. Leave a field empty to ' +
    'remove it from the file.';
  LTop := LIntro.Top + LIntro.Height + S(8);

  FEditSbomCreator := AddField(LBody, LTop, 'SBOM creator:',
    'Email address or http(s) URL of the person or organisation that creates the SBOM. ' +
    'Required by BSI TR-03183-2 section 5.2.1. Key: sbomCreator');
  FEditSupplier := AddField(LBody, LTop, 'Supplier / manufacturer:',
    'Name of the manufacturer. Empty uses CompanyName from the project version info. ' +
    'Key: product.supplier');
  FEditSupplierUrl := AddField(LBody, LTop, 'Supplier URL:',
    'http(s) contact of the manufacturer. Not needed when the supplier is an email ' +
    'address. Key: product.supplierUrl');
  FEditLicence := AddField(LBody, LTop, 'Licence:',
    'Distribution licence as SPDX expression, for example MIT, Apache-2.0 or ' +
    'LicenseRef-Proprietary. Key: product.licence');
  FEditProductVersion := AddField(LBody, LTop, 'Product version:',
    'Optional. Empty uses the version info of the project. Key: product.version');

  FLabelError := TLabel.Create(Self);
  FLabelError.Parent := LBody;
  FLabelError.AutoSize := False;
  FLabelError.WordWrap := True;
  FLabelError.Left := S(cMargin);
  FLabelError.Top := LTop;
  FLabelError.Width := S(cDialogWidth - 2 * cMargin);
  FLabelError.Height := S(34);
  FLabelError.Font.Color := cColorError;
  FLabelError.Caption := '';
  LTop := FLabelError.Top + FLabelError.Height;

  var LFile := TLabel.Create(Self);
  LFile.Parent := LBody;
  LFile.AutoSize := False;
  LFile.EllipsisPosition := epPathEllipsis;
  LFile.Left := S(cMargin);
  LFile.Top := LTop + S(10);
  LFile.Width := S(cDialogWidth - 2 * cMargin - 190);
  LFile.Caption := 'File: ' + FConfigPath;
  LFile.Hint := FConfigPath;
  LFile.ShowHint := True;
  LFile.Font.Color := cColorHint;

  FButtonCancel := TButton.Create(Self);
  FButtonCancel.Parent := LBody;
  FButtonCancel.Caption := 'Cancel';
  FButtonCancel.Cancel := True;
  FButtonCancel.ModalResult := mrCancel;
  FButtonCancel.Width := S(85);
  FButtonCancel.Height := S(28);
  FButtonCancel.Left := S(cDialogWidth - cMargin - 85);
  FButtonCancel.Top := LTop + S(4);

  FButtonSave := TButton.Create(Self);
  FButtonSave.Parent := LBody;
  FButtonSave.Caption := 'Save';
  FButtonSave.Default := True;
  FButtonSave.Width := S(85);
  FButtonSave.Height := S(28);
  FButtonSave.Left := FButtonCancel.Left - S(85 + 8);
  FButtonSave.Top := FButtonCancel.Top;
  FButtonSave.OnClick := OnSaveClick;

  ClientHeight := LHeaderPanel.Height + FButtonCancel.Top + FButtonCancel.Height + S(16);
  ActiveControl := FEditSbomCreator;
end;

function TFormDXComplySbomHeaderDialog.GetHeader: TSbomHeaderData;
begin
  Result.SbomCreator := Trim(FEditSbomCreator.Text);
  Result.Supplier := Trim(FEditSupplier.Text);
  Result.SupplierUrl := Trim(FEditSupplierUrl.Text);
  Result.Licence := Trim(FEditLicence.Text);
  Result.ProductVersion := Trim(FEditProductVersion.Text);
end;

procedure TFormDXComplySbomHeaderDialog.SetHeader(const AHeader: TSbomHeaderData);
begin
  FEditSbomCreator.Text := AHeader.SbomCreator;
  FEditSupplier.Text := AHeader.Supplier;
  FEditSupplierUrl.Text := AHeader.SupplierUrl;
  FEditLicence.Text := AHeader.Licence;
  FEditProductVersion.Text := AHeader.ProductVersion;
end;

procedure TFormDXComplySbomHeaderDialog.OnSaveClick(ASender: TObject);
begin
  var LHeader := GetHeader;
  var LErrors := TSbomHeaderConfig.Validate(LHeader);
  if Length(LErrors) > 0 then
  begin
    FLabelError.Caption := string.Join(' ', LErrors);
    if not IsAcceptableBsiCreator(LHeader.SbomCreator) then
    begin
      FEditSbomCreator.SetFocus;
    end
    else
    begin
      FEditSupplierUrl.SetFocus;
    end;
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

end.
