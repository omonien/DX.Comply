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
      object FSettingsScrollBox: TScrollBox
        Left = 0
        Top = 0
        Width = 652
        Height = 530
        Align = alClient
        BorderStyle = bsNone
        TabOrder = 0
        HorzScrollBar.Visible = False
        object FPromptBeforeBuildCheckBox: TCheckBox
          Left = 12
          Top = 0
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Prompt before starting the SBOM build'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 0
          WordWrap = True
        end
        object FSaveAllModifiedFilesCheckBox: TCheckBox
          Left = 12
          Top = 32
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Save all modified editors before the build'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 1
          WordWrap = True
        end
        object FUseActiveBuildConfigurationCheckBox: TCheckBox
          Left = 12
          Top = 64
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Use the active IDE configuration and platform'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 2
          WordWrap = True
        end
        object FOpenHtmlReportAfterGenerateCheckBox: TCheckBox
          Left = 12
          Top = 96
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Open the generated HTML report in the default browser'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 3
          WordWrap = True
        end
        object FWarnWhenCompositionEmptyCheckBox: TCheckBox
          Left = 12
          Top = 128
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Warn when no composition units were resolved'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 4
          WordWrap = True
        end
        object FContinueOnBuildFailureCheckBox: TCheckBox
          Left = 12
          Top = 160
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Continue SBOM generation when Deep-Evidence build fails'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 5
          WordWrap = True
        end
        object FBuildScriptRowPanel: TPanel
          Left = 12
          Top = 192
          Width = 620
          Height = 40
          Align = alTop
          AlignWithMargins = True
          BevelOuter = bvNone
          Caption = ''
          ParentBackground = True
          TabOrder = 6
          Margins.Left = 12
          Margins.Top = 8
          Margins.Right = 12
          Margins.Bottom = 0
          object FBrowseScriptButton: TButton
            Left = 512
            Top = 2
            Width = 96
            Height = 30
            Align = alRight
            AlignWithMargins = True
            Caption = 'Browse...'
            Margins.Left = 8
            Margins.Top = 2
            Margins.Right = 0
            Margins.Bottom = 2
            TabOrder = 0
          end
          object BuildScriptPathLabel: TLabel
            Left = 0
            Top = 4
            Width = 220
            Height = 32
            Align = alLeft
            AlignWithMargins = True
            AutoSize = False
            Caption = 'Build script path override'
            Layout = tlCenter
            Margins.Left = 0
            Margins.Top = 4
            Margins.Right = 8
            Margins.Bottom = 4
            WordWrap = True
          end
          object FBuildScriptPathEdit: TEdit
            Left = 228
            Top = 6
            Width = 276
            Height = 23
            Align = alClient
            AlignWithMargins = True
            Margins.Left = 0
            Margins.Top = 6
            Margins.Right = 0
            Margins.Bottom = 6
            TabOrder = 1
          end
        end
        object FDelphiVersionRowPanel: TPanel
          Left = 12
          Top = 240
          Width = 620
          Height = 40
          Align = alTop
          AlignWithMargins = True
          BevelOuter = bvNone
          Caption = ''
          ParentBackground = True
          TabOrder = 7
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          object DelphiVersionLabel: TLabel
            Left = 0
            Top = 4
            Width = 220
            Height = 32
            Align = alLeft
            AlignWithMargins = True
            AutoSize = False
            Caption = 'Delphi version override (empty = none)'
            Layout = tlCenter
            Margins.Left = 0
            Margins.Top = 4
            Margins.Right = 8
            Margins.Bottom = 4
            WordWrap = True
          end
          object FDelphiVersionEdit: TEdit
            Left = 228
            Top = 6
            Width = 380
            Height = 23
            Align = alClient
            AlignWithMargins = True
            Margins.Left = 0
            Margins.Top = 6
            Margins.Right = 0
            Margins.Bottom = 6
            TabOrder = 0
          end
        end
        object FReportEnabledCheckBox: TCheckBox
          Left = 12
          Top = 284
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Generate an additional human-readable report'
          Margins.Left = 12
          Margins.Top = 8
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 8
          WordWrap = True
        end
        object FReportFormatRowPanel: TPanel
          Left = 12
          Top = 320
          Width = 620
          Height = 40
          Align = alTop
          AlignWithMargins = True
          BevelOuter = bvNone
          Caption = ''
          ParentBackground = True
          TabOrder = 9
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          object ReportFormatLabel: TLabel
            Left = 0
            Top = 4
            Width = 220
            Height = 32
            Align = alLeft
            AlignWithMargins = True
            AutoSize = False
            Caption = 'Human-readable report format'
            Layout = tlCenter
            Margins.Left = 0
            Margins.Top = 4
            Margins.Right = 8
            Margins.Bottom = 4
            WordWrap = True
          end
          object FReportFormatComboBox: TComboBox
            Left = 228
            Top = 6
            Width = 380
            Height = 23
            Align = alClient
            AlignWithMargins = True
            Style = csDropDownList
            Margins.Left = 0
            Margins.Top = 6
            Margins.Right = 0
            Margins.Bottom = 6
            ItemIndex = 0
            TabOrder = 0
            Text = 'Markdown'
            Items.Strings = (
              'Markdown'
              'HTML'
              'Markdown + HTML')
          end
        end
        object FReportOutputRowPanel: TPanel
          Left = 12
          Top = 364
          Width = 620
          Height = 40
          Align = alTop
          AlignWithMargins = True
          BevelOuter = bvNone
          Caption = ''
          ParentBackground = True
          TabOrder = 10
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          object ReportOutputBasePathLabel: TLabel
            Left = 0
            Top = 4
            Width = 220
            Height = 32
            Align = alLeft
            AlignWithMargins = True
            AutoSize = False
            Caption = 'Report output base path (optional)'
            Layout = tlCenter
            Margins.Left = 0
            Margins.Top = 4
            Margins.Right = 8
            Margins.Bottom = 4
            WordWrap = True
          end
          object FReportOutputBasePathEdit: TEdit
            Left = 228
            Top = 6
            Width = 380
            Height = 23
            Align = alClient
            AlignWithMargins = True
            Margins.Left = 0
            Margins.Top = 6
            Margins.Right = 0
            Margins.Bottom = 6
            TabOrder = 0
          end
        end
        object FReportIncludeWarningsCheckBox: TCheckBox
          Left = 12
          Top = 408
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Include warnings in the human-readable report'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 11
          WordWrap = True
        end
        object FReportIncludeCompositionCheckBox: TCheckBox
          Left = 12
          Top = 440
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Include composition evidence in the human-readable report'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 12
          WordWrap = True
        end
        object FReportIncludeBuildEvidenceCheckBox: TCheckBox
          Left = 12
          Top = 472
          Width = 620
          Height = 36
          Align = alTop
          AlignWithMargins = True
          Caption = 'Include build evidence in the human-readable report'
          Margins.Left = 12
          Margins.Top = 4
          Margins.Right = 12
          Margins.Bottom = 0
          TabOrder = 13
          WordWrap = True
        end
        object FAboutRowPanel: TPanel
          Left = 12
          Top = 508
          Width = 620
          Height = 44
          Align = alTop
          AlignWithMargins = True
          BevelOuter = bvNone
          Caption = ''
          ParentBackground = True
          TabOrder = 14
          Margins.Left = 12
          Margins.Top = 8
          Margins.Right = 12
          Margins.Bottom = 8
          object FAboutButton: TButton
            Left = 0
            Top = 6
            Width = 168
            Height = 30
            Align = alLeft
            AlignWithMargins = True
            Caption = 'About DX.Comply...'
            Margins.Left = 0
            Margins.Top = 6
            Margins.Right = 0
            Margins.Bottom = 6
            TabOrder = 0
          end
        end
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
