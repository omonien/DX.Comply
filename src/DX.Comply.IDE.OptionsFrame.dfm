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
      object FContinueOnBuildFailureCheckBox: TCheckBox
        Left = 16
        Top = 156
        Width = 520
        Height = 21
        Caption = 'Continue SBOM generation when Deep-Evidence build fails'
        TabOrder = 5
      end
      object FReportEnabledCheckBox: TCheckBox
        Left = 16
        Top = 194
        Width = 520
        Height = 21
        Caption = 'Generate an additional human-readable report'
        TabOrder = 6
      end
      object ReportFormatLabel: TLabel
        Left = 16
        Top = 231
        Width = 136
        Height = 15
        Caption = 'Human-readable report format'
      end
      object FReportFormatComboBox: TComboBox
        Left = 248
        Top = 226
        Width = 396
        Height = 23
        Style = csDropDownList
        Anchors = [akLeft, akTop, akRight]
        ItemIndex = 0
        TabOrder = 7
        Text = 'Markdown'
        Items.Strings = (
          'Markdown'
          'HTML'
          'Markdown + HTML')
      end
      object ReportOutputBasePathLabel: TLabel
        Left = 16
        Top = 265
        Width = 160
        Height = 15
        Caption = 'Report output base path (optional)'
      end
      object FReportOutputBasePathEdit: TEdit
        Left = 248
        Top = 260
        Width = 396
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 8
      end
      object FReportIncludeWarningsCheckBox: TCheckBox
        Left = 16
        Top = 298
        Width = 520
        Height = 21
        Caption = 'Include warnings in the human-readable report'
        TabOrder = 9
      end
      object FReportIncludeCompositionCheckBox: TCheckBox
        Left = 16
        Top = 326
        Width = 520
        Height = 21
        Caption = 'Include composition evidence in the human-readable report'
        TabOrder = 10
      end
      object FReportIncludeBuildEvidenceCheckBox: TCheckBox
        Left = 16
        Top = 354
        Width = 520
        Height = 21
        Caption = 'Include build evidence in the human-readable report'
        TabOrder = 11
      end
      object FAboutButton: TButton
        Left = 16
        Top = 390
        Width = 160
        Height = 30
        Caption = 'About DX.Comply...'
        TabOrder = 12
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