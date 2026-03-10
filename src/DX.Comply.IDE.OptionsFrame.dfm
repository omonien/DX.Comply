object FrameDXComplyOptions: TFrameDXComplyOptions
  Left = 0
  Top = 0
  Width = 660
  Height = 560
  TabOrder = 0
  object FPageControl: TPageControl
    Left = 0
    Top = 0
    Width = 660
    Height = 560
    ActivePage = FSettingsTabSheet
    Align = alClient
    TabOrder = 0
    object FSettingsTabSheet: TTabSheet
      Caption = 'General'
      object FPromptBeforeBuildCheckBox: TCheckBox
        Left = 16
        Top = 16
        Width = 520
        Height = 21
        Caption = 'Prompt before starting the CRA compliance documentation build'
        TabOrder = 0
      end
      object FSaveAllModifiedFilesCheckBox: TCheckBox
        Left = 16
        Top = 44
        Width = 520
        Height = 21
        Caption = 'Save all modified editors before the build'
        TabOrder = 1
      end
      object FUseActiveBuildConfigurationCheckBox: TCheckBox
        Left = 16
        Top = 72
        Width = 520
        Height = 21
        Caption = 'Use the active IDE configuration and platform'
        TabOrder = 2
      end
      object FOpenHtmlReportAfterGenerateCheckBox: TCheckBox
        Left = 16
        Top = 100
        Width = 520
        Height = 21
        Caption = 'Open the generated HTML report in the default browser'
        TabOrder = 3
      end
      object FWarnWhenCompositionEmptyCheckBox: TCheckBox
        Left = 16
        Top = 128
        Width = 520
        Height = 21
        Caption = 'Warn when no composition units were resolved'
        TabOrder = 4
      end
      object BuildScriptPathLabel: TLabel
        Left = 16
        Top = 165
        Width = 127
        Height = 15
        Caption = 'Build script path override'
      end
      object FBuildScriptPathEdit: TEdit
        Left = 248
        Top = 160
        Width = 304
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 5
      end
      object FBrowseScriptButton: TButton
        Left = 560
        Top = 159
        Width = 84
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Browse...'
        TabOrder = 6
      end
      object DelphiVersionLabel: TLabel
        Left = 16
        Top = 199
        Width = 173
        Height = 15
        Caption = 'Delphi version override (0 = auto)'
      end
      object FDelphiVersionEdit: TEdit
        Left = 248
        Top = 194
        Width = 396
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 7
      end
      object FReportEnabledCheckBox: TCheckBox
        Left = 16
        Top = 228
        Width = 520
        Height = 21
        Caption = 'Generate an additional human-readable report'
        TabOrder = 8
      end
      object ReportFormatLabel: TLabel
        Left = 16
        Top = 265
        Width = 136
        Height = 15
        Caption = 'Human-readable report format'
      end
      object FReportFormatComboBox: TComboBox
        Left = 248
        Top = 260
        Width = 396
        Height = 23
        Style = csDropDownList
        Anchors = [akLeft, akTop, akRight]
        ItemIndex = 0
        TabOrder = 9
        Text = 'Markdown'
        Items.Strings = (
          'Markdown'
          'HTML'
          'Markdown + HTML')
      end
      object ReportOutputBasePathLabel: TLabel
        Left = 16
        Top = 299
        Width = 160
        Height = 15
        Caption = 'Report output base path (optional)'
      end
      object FReportOutputBasePathEdit: TEdit
        Left = 248
        Top = 294
        Width = 396
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 10
      end
      object FReportIncludeWarningsCheckBox: TCheckBox
        Left = 16
        Top = 332
        Width = 520
        Height = 21
        Caption = 'Include warnings in the human-readable report'
        TabOrder = 11
      end
      object FReportIncludeCompositionCheckBox: TCheckBox
        Left = 16
        Top = 360
        Width = 520
        Height = 21
        Caption = 'Include composition evidence in the human-readable report'
        TabOrder = 12
      end
      object FReportIncludeBuildEvidenceCheckBox: TCheckBox
        Left = 16
        Top = 388
        Width = 520
        Height = 21
        Caption = 'Include build evidence in the human-readable report'
        TabOrder = 13
      end
      object FAboutButton: TButton
        Left = 16
        Top = 424
        Width = 160
        Height = 30
        Caption = 'About DX.Comply...'
        TabOrder = 14
      end
    end
    object FInfoTabSheet: TTabSheet
      Caption = 'Info'
      ImageIndex = 1
      object FReadmeBrowserHostPanel: TPanel
        Left = 0
        Top = 0
        Width = 652
        Height = 530
        Align = alClient
        BevelOuter = bvNone
        BorderWidth = 12
        TabOrder = 0
      end
    end
  end
end