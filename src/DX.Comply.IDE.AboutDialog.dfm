object FormDXComplyAboutDialog: TFormDXComplyAboutDialog
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'About DX.Comply'
  ClientHeight = 510
  ClientWidth = 860
  Color = clWhite
  Constraints.MinHeight = 510
  Constraints.MinWidth = 860
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  Scaled = True
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 15
  object HeaderPanel: TPanel
    Left = 0
    Top = 0
    Width = 860
    Height = 124
    Align = alTop
    BevelOuter = bvNone
    Caption = ''
    Color = 16316148
    ParentBackground = False
    TabOrder = 0
    object HeaderIconImage: TImage
      Left = 24
      Top = 24
      Width = 72
      Height = 72
      Center = True
      Proportional = True
      Stretch = True
      Transparent = True
    end
    object TitleLabel: TLabel
      Left = 116
      Top = 18
      Width = 180
      Height = 37
      Caption = 'DX.Comply'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -32
      Font.Name = 'Segoe UI Semibold'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object SubtitleLabel: TLabel
      Left = 116
      Top = 56
      Width = 328
      Height = 21
      Caption = 'CRA compliance documentation for Delphi projects'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object VersionLabel: TLabel
      Left = 116
      Top = 86
      Width = 163
      Height = 21
      Caption = 'Version 1.0.0.0 · Olaf Monien'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
  end
  object BodyLabel: TLabel
    Left = 24
    Top = 146
    Width = 812
    Height = 52
    AutoSize = False
    Caption =
      'DX.Comply generates formal SBOM artefacts together with optional human-' +
      'readable compliance reports. The IDE integration prepares Deep-Evid' +
      'ence build artefacts, including detailed MAP files, to support tracea' +
      'ble CRA documentation and audit review workflows.'
    Transparent = True
    WordWrap = True
  end
  object ReferenceLinksLabel: TLabel
    Left = 24
    Top = 226
    Width = 102
    Height = 21
    Caption = 'Reference links'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object RepositoryCaptionLabel: TLabel
    Left = 24
    Top = 262
    Width = 77
    Height = 21
    Caption = 'Repository'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object RepositoryLinkLabel: TLabel
    Left = 220
    Top = 260
    Width = 616
    Height = 30
    AutoSize = False
    Caption = 'https://github.com/omonien/DX.Comply'
    Cursor = crHandPoint
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clHotLight
    Font.Height = -16
    Font.Name = 'Segoe UI'
    Font.Style = [fsUnderline]
    ParentFont = False
    Transparent = True
    WordWrap = True
    OnClick = LinkLabelClick
  end
  object CycloneDxCaptionLabel: TLabel
    Left = 24
    Top = 304
    Width = 76
    Height = 21
    Caption = 'CycloneDX'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object CycloneDxLinkLabel: TLabel
    Left = 220
    Top = 302
    Width = 616
    Height = 30
    AutoSize = False
    Caption = 'https://cyclonedx.org/'
    Cursor = crHandPoint
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clHotLight
    Font.Height = -16
    Font.Name = 'Segoe UI'
    Font.Style = [fsUnderline]
    ParentFont = False
    Transparent = True
    WordWrap = True
    OnClick = LinkLabelClick
  end
  object CycloneDxSbomCaptionLabel: TLabel
    Left = 24
    Top = 346
    Width = 117
    Height = 21
    Caption = 'CycloneDX SBOM'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object CycloneDxSbomLinkLabel: TLabel
    Left = 220
    Top = 344
    Width = 616
    Height = 30
    AutoSize = False
    Caption = 'https://cyclonedx.org/capabilities'
    Cursor = crHandPoint
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clHotLight
    Font.Height = -16
    Font.Name = 'Segoe UI'
    Font.Style = [fsUnderline]
    ParentFont = False
    Transparent = True
    WordWrap = True
    OnClick = LinkLabelClick
  end
  object CraOverviewCaptionLabel: TLabel
    Left = 24
    Top = 388
    Width = 118
    Height = 21
    Caption = 'EU CRA overview'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object CraOverviewLinkLabel: TLabel
    Left = 220
    Top = 386
    Width = 616
    Height = 30
    AutoSize = False
    Caption = 'https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act'
    Cursor = crHandPoint
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clHotLight
    Font.Height = -16
    Font.Name = 'Segoe UI'
    Font.Style = [fsUnderline]
    ParentFont = False
    Transparent = True
    WordWrap = True
    OnClick = LinkLabelClick
  end
  object CraRegulationCaptionLabel: TLabel
    Left = 24
    Top = 430
    Width = 127
    Height = 21
    Caption = 'EU CRA regulation'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object CraRegulationLinkLabel: TLabel
    Left = 220
    Top = 428
    Width = 616
    Height = 30
    AutoSize = False
    Caption = 'https://eur-lex.europa.eu/eli/reg/2024/2847/oj/eng'
    Cursor = crHandPoint
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clHotLight
    Font.Height = -16
    Font.Name = 'Segoe UI'
    Font.Style = [fsUnderline]
    ParentFont = False
    Transparent = True
    WordWrap = True
    OnClick = LinkLabelClick
  end
  object CloseButton: TButton
    Left = 748
    Top = 466
    Width = 88
    Height = 30
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Close'
    Default = True
    ModalResult = 1
    TabOrder = 1
  end
end