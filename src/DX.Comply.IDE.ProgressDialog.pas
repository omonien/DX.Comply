/// <summary>
/// DX.Comply.IDE.ProgressDialog
/// Modal progress dialog for non-blocking SBOM generation in the Delphi IDE.
/// </summary>
///
/// <remarks>
/// TGenerationThread executes TDxComplyGenerator.Generate on a background thread
/// so the IDE UI remains responsive during SBOM generation.
///
/// Progress messages are posted back to the main thread via TThread.Queue and
/// displayed in a scrollable log panel. Cancellation is requested by setting
/// FCancelRequested on the thread; the next progress-callback invocation raises
/// EAbort, which terminates the generator and allows the thread to finish cleanly.
///
/// The form is constructed entirely at runtime so no DFM resource is required.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.ProgressDialog;

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Background thread that runs TDxComplyGenerator.Generate without blocking the IDE UI.
  /// Raises EAbort in the progress callback when cancellation is requested, which unwinds
  /// the generator cleanly through its existing try/finally blocks.
  /// </summary>
  TGenerationThread = class(TThread)
  private
    FConfig: TSbomConfig;
    FProjectPath: string;
    FOutputPath: string;
    FFormat: TSbomFormat;
    FSuccess: Boolean;
    FCancelRequested: Boolean;
    FOnProgress: TProgressEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(const AProjectPath, AOutputPath: string;
      AFormat: TSbomFormat; const AConfig: TSbomConfig;
      AOnProgress: TProgressEvent);
    /// <summary>
    /// Signals the thread to stop at the next progress checkpoint.
    /// </summary>
    procedure RequestCancel;
    property Success: Boolean read FSuccess;
    property CancelRequested: Boolean read FCancelRequested;
  end;

  /// <summary>
  /// Modal progress dialog, styled after the Delphi compiler output dialog.
  /// Shows a branded header, live progress bar, current step label, and a
  /// scrollable Consolas log panel. The action button switches from "Abort"
  /// to "Close" when the thread completes.
  /// </summary>
  TFormDXComplyProgressDialog = class(TForm)
  private
    FThread: TGenerationThread;
    FCompleted: Boolean;
    FSuccess: Boolean;
    FProjectPath: string;
    FOutputPath: string;
    FFormat: TSbomFormat;
    FConfig: TSbomConfig;
    // Controls
    FPanelHeader: TPanel;
    FLabelTitle: TLabel;
    FLabelSubtitle: TLabel;
    FPanelProgress: TPanel;
    FLabelStep: TLabel;
    FProgressBar: TProgressBar;
    FLabelPercent: TLabel;
    FMemoLog: TMemo;
    FPanelFooter: TPanel;
    FLabelStatus: TLabel;
    FButtonAction: TButton;
    procedure BuildUI;
    procedure FormCloseQuery(ASender: TObject; var ACanClose: Boolean);
    procedure OnActionClick(ASender: TObject);
    procedure OnThreadTerminate(ASender: TObject);
    /// <summary>
    /// Called on the main thread (via TThread.Queue) to update the UI with one
    /// progress message from the generation thread.
    /// </summary>
    procedure PostProgress(const AMessage: string; AProgress: Integer);
  public
    constructor Create(AOwner: TComponent; const AProjectPath, AOutputPath: string;
      AFormat: TSbomFormat; const AConfig: TSbomConfig); reintroduce;
    destructor Destroy; override;
    /// <summary>
    /// Creates and starts the background generation thread. Call before ShowModal.
    /// </summary>
    procedure StartGeneration;
    property Success: Boolean read FSuccess;
  end;

/// <summary>
/// Shows the SBOM generation progress dialog modally.
/// Returns True when generation completed successfully, False on failure or cancellation.
/// </summary>
function ShowDXComplyProgressDialog(
  const AProjectPath, AOutputPath: string;
  AFormat: TSbomFormat; const AConfig: TSbomConfig): Boolean;

implementation

const
  cColorHeader   = $2B2E36;  // Dark charcoal — branded header
  cColorTitle    = $E8ECEF;  // Near-white title text
  cColorSubtitle = $9AA0A8;  // Muted subtitle text
  cColorSuccess  = $107C10;  // Windows green
  cColorError    = $C42B1C;  // Windows red
  cColorNeutral  = $595959;  // Gray status text
  cColorSep      = $D4D4D4;  // Separator line
  cMargin        = 12;

{ TGenerationThread }

constructor TGenerationThread.Create(const AProjectPath, AOutputPath: string;
  AFormat: TSbomFormat; const AConfig: TSbomConfig; AOnProgress: TProgressEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FProjectPath := AProjectPath;
  FOutputPath := AOutputPath;
  FFormat := AFormat;
  FConfig := AConfig;
  FOnProgress := AOnProgress;
  FSuccess := False;
  FCancelRequested := False;
end;

procedure TGenerationThread.RequestCancel;
begin
  FCancelRequested := True;
end;

procedure TGenerationThread.Execute;
var
  LGenerator: TDxComplyGenerator;
begin
  LGenerator := TDxComplyGenerator.Create(FConfig);
  try
    LGenerator.OnProgress :=
      procedure(const AMessage: string; const AProgress: Integer)
      begin
        // Raising EAbort here unwinds the generator through its existing
        // try/finally blocks, ensuring all objects are freed before the
        // exception reaches our handler below.
        if FCancelRequested then
          raise EAbort.Create('');
        if Assigned(FOnProgress) then
          FOnProgress(AMessage, AProgress);
      end;

    try
      FSuccess := LGenerator.Generate(FProjectPath, FOutputPath, FFormat);
    except
      on EAbort do
        FSuccess := False;
      on E: Exception do
      begin
        FSuccess := False;
        if Assigned(FOnProgress) and not FCancelRequested then
          FOnProgress('Unhandled error: ' + E.Message, -1);
      end;
    end;
  finally
    LGenerator.Free;
  end;
end;

{ TFormDXComplyProgressDialog }

constructor TFormDXComplyProgressDialog.Create(AOwner: TComponent;
  const AProjectPath, AOutputPath: string;
  AFormat: TSbomFormat; const AConfig: TSbomConfig);
begin
  inherited CreateNew(AOwner);
  FProjectPath := AProjectPath;
  FOutputPath := AOutputPath;
  FFormat := AFormat;
  FConfig := AConfig;
  FCompleted := False;
  FSuccess := False;
  FThread := nil;
  BuildUI;
  OnCloseQuery := FormCloseQuery;
end;

destructor TFormDXComplyProgressDialog.Destroy;
begin
  if Assigned(FThread) then
  begin
    FThread.RequestCancel;
    FThread.WaitFor;
    FThread.Free;
    FThread := nil;
  end;
  inherited;
end;

procedure TFormDXComplyProgressDialog.BuildUI;

  function S(AValue: Integer): Integer;
  begin
    Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
  end;

var
  LSepBelowProgress: TPanel;
  LFooterSep: TPanel;
  LLogWrapper: TPanel;
  LProgressContent: TPanel;
  LPercentPanel: TPanel;
  LM: Integer;
begin
  LM := S(20);

  Caption := 'DX.Comply - CRA Documentation Generator';
  ClientWidth := S(780);
  ClientHeight := S(560);
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  Color := clWhite;
  Font.Name := 'Segoe UI';
  Font.Size := 10;

  // === Dark branded header ===
  FPanelHeader := TPanel.Create(Self);
  FPanelHeader.Parent := Self;
  FPanelHeader.Align := alTop;
  FPanelHeader.Height := S(80);
  FPanelHeader.BevelOuter := bvNone;
  FPanelHeader.Color := cColorHeader;
  FPanelHeader.ParentBackground := False;
  FPanelHeader.Padding.Left := LM;
  FPanelHeader.Padding.Right := LM;

  FLabelTitle := TLabel.Create(FPanelHeader);
  FLabelTitle.Parent := FPanelHeader;
  FLabelTitle.Align := alTop;
  FLabelTitle.Caption := 'DX.Comply';
  FLabelTitle.Font.Name := 'Segoe UI Semibold';
  FLabelTitle.Font.Size := 18;
  FLabelTitle.Font.Style := [fsBold];
  FLabelTitle.Font.Color := cColorTitle;
  FLabelTitle.ParentFont := False;
  FLabelTitle.Layout := tlCenter;
  FLabelTitle.AlignWithMargins := True;
  FLabelTitle.Margins.Top := S(10);
  FLabelTitle.Margins.Bottom := 0;
  FLabelTitle.Margins.Left := 0;
  FLabelTitle.Margins.Right := 0;

  FLabelSubtitle := TLabel.Create(FPanelHeader);
  FLabelSubtitle.Parent := FPanelHeader;
  FLabelSubtitle.Align := alTop;
  FLabelSubtitle.Caption := 'Generating CRA compliance documentation';
  FLabelSubtitle.Font.Name := 'Segoe UI';
  FLabelSubtitle.Font.Size := 10;
  FLabelSubtitle.Font.Color := cColorSubtitle;
  FLabelSubtitle.ParentFont := False;
  FLabelSubtitle.AlignWithMargins := True;
  FLabelSubtitle.Margins.Top := S(4);
  FLabelSubtitle.Margins.Bottom := 0;
  FLabelSubtitle.Margins.Left := 0;
  FLabelSubtitle.Margins.Right := 0;

  // === Progress section (Align-based layout) ===
  FPanelProgress := TPanel.Create(Self);
  FPanelProgress.Parent := Self;
  FPanelProgress.Align := alTop;
  FPanelProgress.Height := S(80);
  FPanelProgress.BevelOuter := bvNone;
  FPanelProgress.Color := clWhite;
  FPanelProgress.ParentBackground := False;
  FPanelProgress.Padding.Left := LM;
  FPanelProgress.Padding.Right := LM;
  FPanelProgress.Padding.Top := S(12);
  FPanelProgress.Padding.Bottom := S(12);

  FLabelStep := TLabel.Create(FPanelProgress);
  FLabelStep.Parent := FPanelProgress;
  FLabelStep.Align := alTop;
  FLabelStep.Caption := 'Initializing...';
  FLabelStep.Font.Name := 'Segoe UI';
  FLabelStep.Font.Size := 10;
  FLabelStep.Font.Color := cColorNeutral;
  FLabelStep.ParentFont := False;
  FLabelStep.AutoSize := False;
  FLabelStep.Height := S(20);
  FLabelStep.EllipsisPosition := epEndEllipsis;
  FLabelStep.AlignWithMargins := True;
  FLabelStep.Margins.Bottom := S(8);
  FLabelStep.Margins.Top := 0;
  FLabelStep.Margins.Left := 0;
  FLabelStep.Margins.Right := 0;

  // Container for progress bar row
  LProgressContent := TPanel.Create(FPanelProgress);
  LProgressContent.Parent := FPanelProgress;
  LProgressContent.Align := alTop;
  LProgressContent.Height := S(22);
  LProgressContent.BevelOuter := bvNone;
  LProgressContent.Color := clWhite;
  LProgressContent.ParentBackground := False;

  // Percent label on the right side of the bar row
  LPercentPanel := TPanel.Create(LProgressContent);
  LPercentPanel.Parent := LProgressContent;
  LPercentPanel.Align := alRight;
  LPercentPanel.Width := S(50);
  LPercentPanel.BevelOuter := bvNone;
  LPercentPanel.Color := clWhite;
  LPercentPanel.ParentBackground := False;

  FLabelPercent := TLabel.Create(LPercentPanel);
  FLabelPercent.Parent := LPercentPanel;
  FLabelPercent.Align := alClient;
  FLabelPercent.Caption := '0%';
  FLabelPercent.Font.Name := 'Segoe UI';
  FLabelPercent.Font.Size := 10;
  FLabelPercent.Font.Color := cColorNeutral;
  FLabelPercent.ParentFont := False;
  FLabelPercent.Alignment := taRightJustify;
  FLabelPercent.Layout := tlCenter;

  FProgressBar := TProgressBar.Create(LProgressContent);
  FProgressBar.Parent := LProgressContent;
  FProgressBar.Align := alClient;
  FProgressBar.AlignWithMargins := True;
  FProgressBar.Margins.Right := S(12);
  FProgressBar.Margins.Top := 0;
  FProgressBar.Margins.Bottom := 0;
  FProgressBar.Margins.Left := 0;
  FProgressBar.Min := 0;
  FProgressBar.Max := 100;
  FProgressBar.Position := 0;
  FProgressBar.Smooth := True;

  // Thin separator between progress and log
  LSepBelowProgress := TPanel.Create(Self);
  LSepBelowProgress.Parent := Self;
  LSepBelowProgress.Align := alTop;
  LSepBelowProgress.Height := 1;
  LSepBelowProgress.BevelOuter := bvNone;
  LSepBelowProgress.Color := cColorSep;

  // === Footer ===
  FPanelFooter := TPanel.Create(Self);
  FPanelFooter.Parent := Self;
  FPanelFooter.Align := alBottom;
  FPanelFooter.Height := S(52);
  FPanelFooter.BevelOuter := bvNone;
  FPanelFooter.Color := clWhite;
  FPanelFooter.ParentBackground := False;
  FPanelFooter.Padding.Left := LM;
  FPanelFooter.Padding.Right := LM;

  LFooterSep := TPanel.Create(FPanelFooter);
  LFooterSep.Parent := FPanelFooter;
  LFooterSep.Align := alTop;
  LFooterSep.Height := 1;
  LFooterSep.BevelOuter := bvNone;
  LFooterSep.Color := cColorSep;

  FButtonAction := TButton.Create(FPanelFooter);
  FButtonAction.Parent := FPanelFooter;
  FButtonAction.Align := alRight;
  FButtonAction.AlignWithMargins := True;
  FButtonAction.Width := S(100);
  FButtonAction.Margins.Top := S(10);
  FButtonAction.Margins.Bottom := S(10);
  FButtonAction.Margins.Left := S(12);
  FButtonAction.Margins.Right := 0;
  FButtonAction.Caption := 'Abort';
  FButtonAction.Cancel := True;
  FButtonAction.OnClick := OnActionClick;

  FLabelStatus := TLabel.Create(FPanelFooter);
  FLabelStatus.Parent := FPanelFooter;
  FLabelStatus.Align := alClient;
  FLabelStatus.Caption := 'In progress...';
  FLabelStatus.Font.Name := 'Segoe UI';
  FLabelStatus.Font.Size := 10;
  FLabelStatus.Font.Color := cColorNeutral;
  FLabelStatus.ParentFont := False;
  FLabelStatus.Layout := tlCenter;
  FLabelStatus.AlignWithMargins := True;
  FLabelStatus.Margins.Top := S(10);
  FLabelStatus.Margins.Bottom := S(10);
  FLabelStatus.Margins.Left := 0;
  FLabelStatus.Margins.Right := 0;

  // === Scrollable log (fills remaining space) ===
  LLogWrapper := TPanel.Create(Self);
  LLogWrapper.Parent := Self;
  LLogWrapper.Align := alClient;
  LLogWrapper.BevelOuter := bvNone;
  LLogWrapper.Color := clWhite;
  LLogWrapper.Padding.Left := LM;
  LLogWrapper.Padding.Right := LM;
  LLogWrapper.Padding.Top := S(8);
  LLogWrapper.Padding.Bottom := S(8);

  FMemoLog := TMemo.Create(LLogWrapper);
  FMemoLog.Parent := LLogWrapper;
  FMemoLog.Align := alClient;
  FMemoLog.ReadOnly := True;
  FMemoLog.ScrollBars := ssVertical;
  FMemoLog.WordWrap := False;
  FMemoLog.Font.Name := 'Consolas';
  FMemoLog.Font.Size := 10;
  FMemoLog.Color := $F5F5F5;
  FMemoLog.BorderStyle := bsSingle;
  FMemoLog.Lines.Clear;
end;

procedure TFormDXComplyProgressDialog.StartGeneration;
begin
  FThread := TGenerationThread.Create(
    FProjectPath, FOutputPath, FFormat, FConfig,
    procedure(const AMessage: string; const AProgress: Integer)
    begin
      // This closure is called from the background thread.
      // Capture parameters by value so they survive until the queue fires.
      TThread.Queue(nil,
        procedure
        begin
          PostProgress(AMessage, AProgress);
        end);
    end);
  FThread.OnTerminate := OnThreadTerminate;
  FThread.Start;
end;

procedure TFormDXComplyProgressDialog.PostProgress(
  const AMessage: string; AProgress: Integer);
begin
  FMemoLog.Lines.Add(AMessage);
  // Scroll log to the latest entry
  SendMessage(FMemoLog.Handle, WM_VSCROLL, SB_BOTTOM, 0);

  // Update the step label with the last non-error progress message
  if (AProgress >= 0) and (Trim(AMessage) <> '') then
    FLabelStep.Caption := AMessage;

  // Advance progress bar (never go backwards)
  if AProgress > FProgressBar.Position then
  begin
    FProgressBar.Position := AProgress;
    FLabelPercent.Caption := IntToStr(AProgress) + '%';
  end;
end;

procedure TFormDXComplyProgressDialog.OnThreadTerminate(ASender: TObject);
begin
  FCompleted := True;
  FSuccess := FThread.Success;

  if FThread.CancelRequested then
  begin
    FLabelSubtitle.Caption := 'Generation cancelled';
    FLabelStep.Caption := 'Generation was cancelled by user.';
    FLabelStep.Font.Color := cColorError;
    FLabelStatus.Caption := 'Cancelled';
    FLabelStatus.Font.Color := cColorError;
    FMemoLog.Lines.Add('--- Generation cancelled by user ---');
  end
  else if FSuccess then
  begin
    FProgressBar.Position := 100;
    FLabelPercent.Caption := '100%';
    FPanelHeader.Color := cColorSuccess;
    FLabelSubtitle.Caption := 'CRA documentation generated successfully';
    FLabelSubtitle.Font.Color := cColorTitle;
    FLabelStep.Caption := 'All tasks completed.';
    FLabelStep.Font.Color := cColorSuccess;
    FLabelStatus.Caption := 'Completed successfully';
    FLabelStatus.Font.Color := cColorSuccess;
  end
  else
  begin
    FPanelHeader.Color := cColorError;
    FLabelSubtitle.Caption := 'Generation failed';
    FLabelSubtitle.Font.Color := cColorTitle;
    // Issue #29: the diagnostic output lives in the log memo on this same
    // progress dialog (FMemoLog above), NOT in the IDE Messages window —
    // DX.Comply routes its progress messages here, not to the IDE.
    FLabelStep.Caption := 'Generation failed - check the log output in this dialog above.';
    FLabelStep.Font.Color := cColorError;
    FLabelStatus.Caption := 'Failed';
    FLabelStatus.Font.Color := cColorError;
  end;

  FButtonAction.Cancel := False;
  FButtonAction.Default := True;
  FButtonAction.Caption := 'Close';
  FButtonAction.ModalResult := mrOk;
  FButtonAction.Enabled := True;
end;

procedure TFormDXComplyProgressDialog.OnActionClick(ASender: TObject);
begin
  if FCompleted then
  begin
    ModalResult := mrOk;
    Exit;
  end;

  FButtonAction.Enabled := False;
  FButtonAction.Caption := 'Aborting...';
  FLabelStep.Caption := 'Cancelling generation...';
  FLabelStatus.Caption := 'Cancelling...';
  if Assigned(FThread) then
    FThread.RequestCancel;
end;

procedure TFormDXComplyProgressDialog.FormCloseQuery(
  ASender: TObject; var ACanClose: Boolean);
begin
  if FCompleted then
  begin
    ACanClose := True;
    Exit;
  end;

  // Prevent closing while the thread is running; trigger cancellation instead.
  ACanClose := False;
  if Assigned(FThread) and not FThread.CancelRequested then
  begin
    FButtonAction.Enabled := False;
    FButtonAction.Caption := 'Aborting...';
    FLabelStep.Caption := 'Cancelling generation...';
    FLabelStatus.Caption := 'Cancelling...';
    FThread.RequestCancel;
  end;
end;

{ ShowDXComplyProgressDialog }

function ShowDXComplyProgressDialog(
  const AProjectPath, AOutputPath: string;
  AFormat: TSbomFormat; const AConfig: TSbomConfig): Boolean;
var
  LDialog: TFormDXComplyProgressDialog;
begin
  LDialog := TFormDXComplyProgressDialog.Create(nil,
    AProjectPath, AOutputPath, AFormat, AConfig);
  try
    LDialog.StartGeneration;
    LDialog.ShowModal;
    Result := LDialog.Success;
  finally
    LDialog.Free;
  end;
end;

end.
