/// <summary>
/// DX.Comply.IDE.AboutDialog
/// Provides the shared About dialog for the DX.Comply IDE integration.
/// </summary>
///
/// <remarks>
/// The dialog is shared between the wizard menu entry and the options page so
/// product information and reference links stay consistent in one place.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.AboutDialog;

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.StdCtrls;

type
  /// <summary>
  /// Displays product information and reference links for the DX.Comply IDE package.
  /// </summary>
  TFormDXComplyAboutDialog = class(TForm)
    HeaderPanel: TPanel;
    HeaderIconImage: TImage;
    TitleLabel: TLabel;
    SubtitleLabel: TLabel;
    VersionLabel: TLabel;
    BodyLabel: TLabel;
    ReferenceLinksLabel: TLabel;
    RepositoryCaptionLabel: TLabel;
    RepositoryLinkLabel: TLabel;
    CycloneDxCaptionLabel: TLabel;
    CycloneDxLinkLabel: TLabel;
    CycloneDxSbomCaptionLabel: TLabel;
    CycloneDxSbomLinkLabel: TLabel;
    CraOverviewCaptionLabel: TLabel;
    CraOverviewLinkLabel: TLabel;
    CraRegulationCaptionLabel: TLabel;
    CraRegulationLinkLabel: TLabel;
    CloseButton: TButton;
    procedure FormCreate(Sender: TObject);
    procedure LinkLabelClick(Sender: TObject);
  private
    procedure ConfigureLinkLabel(ALabel: TLabel; const AUrl: string);
    procedure LoadHeaderGraphic;
  end;

/// <summary>
/// Displays the About dialog for the DX.Comply IDE integration.
/// </summary>
procedure ShowDXComplyAboutDialog;

implementation

{$R *.dfm}

uses
  System.SysUtils,
  Winapi.ShellAPI,
  Winapi.Windows,
  DX.Comply.IDE.Logger,
  DX.Comply.IDE.PathSupport,
  DX.Comply.VersionInfo;

type
  /// <summary>
  /// Selected version information loaded from the current DX.Comply package.
  /// </summary>
  TPackageVersionInfo = record
    CompanyName: string;
    ProductVersion: string;
  end;

const
  cRepositoryUrl = 'https://github.com/omonien/DX.Comply';
  cCycloneDxUrl = 'https://cyclonedx.org/';
  cCycloneDxSbomUrl = 'https://cyclonedx.org/capabilities';
  cCraOverviewUrl = 'https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act';
  cCraRegulationUrl = 'https://eur-lex.europa.eu/eli/reg/2024/2847/oj/eng';
  cAboutBodyText =
    'DX.Comply lists the units, packages and DLL names it can see in a Delphi ' +
    'build, with a hash where it could open the file. The SBOM is a starting ' +
    'point for the SBOM part of EU CRA technical documentation. It does not ' +
    'make a product compliant.';
  cHeaderBitmapFileName = 'DX.Comply.Icon.bmp';
  cHeaderPngFileName = 'DX.Comply.Icon.png';

function OpenInDefaultBrowser(const ATarget: string): Boolean;
begin
  Result := NativeUInt(ShellExecute(0, 'open', PChar(ATarget), nil, nil,
    SW_SHOWNORMAL)) > 32;
end;

function ReadCurrentPackageVersionInfo: TPackageVersionInfo;
begin
  // HInstance is the IDE BPL when this unit is linked into the design package.
  Result.CompanyName := GetModuleVersionString(HInstance, 'CompanyName');
  if Result.CompanyName = '' then
    Result.CompanyName := 'Olaf Monien';

  Result.ProductVersion := GetModuleProductVersion(HInstance);
  if Result.ProductVersion = '' then
    Result.ProductVersion := '1.0.0.0';
end;

procedure TFormDXComplyAboutDialog.ConfigureLinkLabel(ALabel: TLabel;
  const AUrl: string);
begin
  ALabel.Caption := AUrl;
  ALabel.Cursor := crHandPoint;
  ALabel.Font.Color := clHotLight;
  ALabel.Font.Style := [fsUnderline];
  ALabel.ShowHint := False;
end;

procedure TFormDXComplyAboutDialog.FormCreate(Sender: TObject);
var
  LVersionInfo: TPackageVersionInfo;
begin
  LoadHeaderGraphic;
  BodyLabel.Caption := cAboutBodyText;

  LVersionInfo := ReadCurrentPackageVersionInfo;
  VersionLabel.Caption := Format('Version %s · %s', [
    LVersionInfo.ProductVersion,
    LVersionInfo.CompanyName]);

  ConfigureLinkLabel(RepositoryLinkLabel, cRepositoryUrl);
  ConfigureLinkLabel(CycloneDxLinkLabel, cCycloneDxUrl);
  ConfigureLinkLabel(CycloneDxSbomLinkLabel, cCycloneDxSbomUrl);
  ConfigureLinkLabel(CraOverviewLinkLabel, cCraOverviewUrl);
  ConfigureLinkLabel(CraRegulationLinkLabel, cCraRegulationUrl);
end;

procedure TFormDXComplyAboutDialog.LinkLabelClick(Sender: TObject);
var
  LTarget: string;
begin
  if not (Sender is TLabel) then
    Exit;

  LTarget := Trim(TLabel(Sender).Caption);
  if LTarget = '' then
    Exit;

  if not OpenInDefaultBrowser(LTarget) then
    TIDELogger.Warning('DX.Comply: Failed to open external link: ' + LTarget);
end;

procedure TFormDXComplyAboutDialog.LoadHeaderGraphic;
var
  LAssetPath: string;
begin
  LAssetPath := FindDXComplyAssetFile(cHeaderBitmapFileName);
  if LAssetPath = '' then
    LAssetPath := FindDXComplyAssetFile(cHeaderPngFileName);
  if LAssetPath = '' then
    Exit;

  try
    HeaderIconImage.Picture.LoadFromFile(LAssetPath);
  except
    on E: Exception do
      TIDELogger.Warning('DX.Comply: Failed to load About dialog header image: ' +
        E.Message);
  end;
end;

procedure ShowDXComplyAboutDialog;
begin
  with TFormDXComplyAboutDialog.Create(nil) do
  try
    ShowModal;
  finally
    Free;
  end;
end;

end.