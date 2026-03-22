object FormDXComplyBuildConfirmationDialog: TFormDXComplyBuildConfirmationDialog
  Left = 0
  Top = 0
  Margins.Left = 6
  Margins.Top = 6
  Margins.Right = 6
  Margins.Bottom = 6
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'DX.Comply CRA Compliance Generation'
  ClientHeight = 632
  ClientWidth = 1280
  Color = clBtnFace
  Constraints.MinHeight = 632
  Constraints.MinWidth = 1280
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -24
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  PixelsPerInch = 192
  DesignSize = (
    1280
    632)
  TextHeight = 32
  object TitleLabel: TLabel
    Left = 40
    Top = 40
    Width = 1012
    Height = 51
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Generate CRA compliance documentation with DX.Comply'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -38
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object DescriptionLabel: TLabel
    Left = 40
    Top = 116
    Width = 1200
    Height = 80
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    AutoSize = False
    Caption = 
      'DX.Comply will run a dedicated Deep-Evidence build with detailed' +
      ' MAP generation before creating the SBOM and the companion compl' +
      'iance report.'
    WordWrap = True
  end
  object ProjectCaptionLabel: TLabel
    Left = 40
    Top = 244
    Width = 82
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Project:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -24
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object ProjectValueLabel: TLabel
    Left = 280
    Top = 244
    Width = 960
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    AutoSize = False
    Caption = 'ProjectValueLabel'
  end
  object ConfigurationCaptionLabel: TLabel
    Left = 40
    Top = 300
    Width = 156
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Configuration:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -24
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object ConfigurationComboBox: TComboBox
    Left = 280
    Top = 296
    Width = 960
    Height = 40
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Style = csDropDownList
    Anchors = [akLeft, akTop, akRight]
    TabOrder = 3
  end
  object PlatformCaptionLabel: TLabel
    Left = 40
    Top = 356
    Width = 100
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Platform:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -24
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object PlatformValueLabel: TLabel
    Left = 280
    Top = 356
    Width = 960
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    AutoSize = False
    Caption = 'PlatformValueLabel'
  end
  object MapCaptionLabel: TLabel
    Left = 40
    Top = 412
    Width = 203
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Expected MAP file:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -24
    Font.Name = 'Segoe UI Semibold'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object MapValueLabel: TLabel
    Left = 280
    Top = 412
    Width = 960
    Height = 72
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    AutoSize = False
    Caption = 'MapValueLabel'
    WordWrap = True
  end
  object DisablePromptCheckBox: TCheckBox
    Left = 40
    Top = 516
    Width = 560
    Height = 42
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Do not show this confirmation again'
    TabOrder = 0
  end
  object OkButton: TButton
    Left = 888
    Top = 540
    Width = 176
    Height = 60
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Anchors = [akRight, akBottom]
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 1
  end
  object CancelButton: TButton
    Left = 1088
    Top = 540
    Width = 176
    Height = 60
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 2
  end
end
