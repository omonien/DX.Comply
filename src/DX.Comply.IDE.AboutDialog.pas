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
  DX.Comply.IDE.PathSupport;

type
  /// <summary>
  /// Selected version information loaded from the current DX.Comply package.
  /// </summary>
  TPackageVersionInfo = record
    CompanyName: string;
    ProductVersion: string;
  end;

  /// <summary>
  /// Language/code-page translation entry from a Windows version resource.
  /// </summary>
  TTranslationInfo = packed record
    Language: Word;
    CodePage: Word;
  end;

const
  cRepositoryUrl = 'https://github.com/omonien/DX.Comply';
  cCycloneDxUrl = 'https://cyclonedx.org/';
  cCycloneDxSbomUrl = 'https://cyclonedx.org/capabilities';
  cCraOverviewUrl = 'https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act';
  cCraRegulationUrl = 'https://eur-lex.europa.eu/eli/reg/2024/2847/oj/eng';
  cAboutBodyText =
    'The EU Cyber Resilience Act (CRA) requires software vendors to document ' +
    'what is inside their products. DX.Comply generates that Software Bill of ' +
    'Materials directly from your RAD Studio project, together with optional ' +
    'human-readable Markdown and HTML reports. You generate it, archive it, ' +
    'and keep it ready for CRA documentation and audit review workflows.';
  cHeaderBitmapFileName = 'DX.Comply.Icon.bmp';
  cHeaderPngFileName = 'DX.Comply.Icon.png';

function OpenInDefaultBrowser(const ATarget: string): Boolean;
begin
  Result := NativeUInt(ShellExecute(0, 'open', PChar(ATarget), nil, nil,
    SW_SHOWNORMAL)) > 32;
end;

function QueryVersionString(const AVersionData: TBytes; const AName: string): string;
const
  cFallbackTranslations: array [0 .. 2] of string = ('040704E4', '040904E4', '040904B0');
var
  I: Integer;
  LQueryPath: string;
  LTextLength: UINT;
  LTextPointer: PChar;
  LTranslation: ^TTranslationInfo;
  LTranslationId: string;
  LTranslationLength: UINT;

  function TryQueryString(const ATranslationId: string): Boolean;
  begin
    LQueryPath := Format('\StringFileInfo\%s\%s', [ATranslationId, AName]);
    Result := VerQueryValue(@AVersionData[0], PChar(LQueryPath), Pointer(LTextPointer),
      LTextLength) and (LTextLength > 0);
    if Result then
      Result := Trim(string(LTextPointer)) <> '';
  end;

begin
  Result := '';
  if Length(AVersionData) = 0 then
    Exit;

  if VerQueryValue(@AVersionData[0], '\VarFileInfo\Translation', Pointer(LTranslation),
    LTranslationLength) and (LTranslationLength >= SizeOf(TTranslationInfo)) then
  begin
    LTranslationId := Format('%.4x%.4x', [LTranslation^.Language, LTranslation^.CodePage]);
    if TryQueryString(LTranslationId) then
      Exit(Trim(string(LTextPointer)));
  end;

  for I := Low(cFallbackTranslations) to High(cFallbackTranslations) do
    if TryQueryString(cFallbackTranslations[I]) then
      Exit(Trim(string(LTextPointer)));
end;

function QueryFixedProductVersion(const AVersionData: TBytes): string;
var
  LVersionInfo: PVSFixedFileInfo;
  LVersionLength: UINT;
begin
  Result := '';
  if (Length(AVersionData) = 0) or
    not VerQueryValue(@AVersionData[0], '\', Pointer(LVersionInfo), LVersionLength) or
    (LVersionLength < SizeOf(VS_FIXEDFILEINFO)) then
    Exit;

  Result := Format('%d.%d.%d.%d', [
    HiWord(LVersionInfo^.dwProductVersionMS),
    LoWord(LVersionInfo^.dwProductVersionMS),
    HiWord(LVersionInfo^.dwProductVersionLS),
    LoWord(LVersionInfo^.dwProductVersionLS)]);
end;

function ReadCurrentPackageVersionInfo: TPackageVersionInfo;
var
  LDummyHandle: DWORD;
  LModuleFilePath: string;
  LVersionData: TBytes;
  LVersionDataSize: DWORD;
begin
  Result.CompanyName := 'Olaf Monien';
  Result.ProductVersion := '1.0.0.0';

  LModuleFilePath := GetDXComplyModuleFilePath;
  if LModuleFilePath = '' then
    Exit;

  LVersionDataSize := GetFileVersionInfoSize(PChar(LModuleFilePath), LDummyHandle);
  if LVersionDataSize = 0 then
    Exit;

  SetLength(LVersionData, LVersionDataSize);
  if not GetFileVersionInfo(PChar(LModuleFilePath), 0, LVersionDataSize, @LVersionData[0]) then
    Exit;

  Result.CompanyName := QueryVersionString(LVersionData, 'CompanyName');
  if Result.CompanyName = '' then
    Result.CompanyName := 'Olaf Monien';

  Result.ProductVersion := QueryVersionString(LVersionData, 'ProductVersion');
  if Result.ProductVersion = '' then
    Result.ProductVersion := QueryFixedProductVersion(LVersionData);
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