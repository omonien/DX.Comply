/// <summary>
/// DX.Comply.IDE.Logger
/// IDE message window output wrapper for DX.Comply.
/// </summary>
///
/// <remarks>
/// Provides TIDELogger with class methods for writing categorised messages
/// (Info, Warning, Error, Progress) to the Delphi IDE message window via
/// IOTAMessageServices. All calls are guarded against unavailable IDE
/// services so the unit is safe to use during package load/unload.
///
/// TIDELogger.Progress routes to Error or Info based on the sign of APercent.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.Logger;

interface

uses
  System.SysUtils,
  ToolsAPI;

type
  /// <summary>
  /// Writes categorised messages to the Delphi IDE message window.
  /// All methods are class-level so no instance is required.
  /// </summary>
  TIDELogger = class
  private
    class function TryGetMessageServices(out AMsgSvc: IOTAMessageServices): Boolean;
  public
    /// <summary>
    /// Clears all messages from the IDE message panel.
    /// </summary>
    class procedure Clear;
    /// <summary>
    /// Writes an informational message to the IDE message window.
    /// </summary>
    /// <param name="AMessage">The message text to display.</param>
    class procedure Info(const AMessage: string);
    /// <summary>
    /// Writes a warning message to the IDE message window.
    /// </summary>
    /// <param name="AMessage">The message text to display.</param>
    class procedure Warning(const AMessage: string);
    /// <summary>
    /// Writes an error message to the IDE message window.
    /// </summary>
    /// <param name="AMessage">The message text to display.</param>
    class procedure Error(const AMessage: string);
    /// <summary>
    /// Writes a progress update to the IDE message window.
    /// Negative APercent values are treated as errors.
    /// </summary>
    /// <param name="AMessage">The message text to display.</param>
    /// <param name="APercent">Completion percentage (0-100). Use -1 to signal an error.</param>
    class procedure Progress(const AMessage: string; const APercent: Integer);
  end;

implementation

{ TIDELogger }

class function TIDELogger.TryGetMessageServices(out AMsgSvc: IOTAMessageServices): Boolean;
begin
  Result := Supports(BorlandIDEServices, IOTAMessageServices, AMsgSvc);
end;

class procedure TIDELogger.Clear;
var
  LMsgSvc: IOTAMessageServices;
begin
  try
    if TryGetMessageServices(LMsgSvc) then
      LMsgSvc.ClearToolMessages;
  except
    // Guard against IDE services being unavailable during package load/unload.
  end;
end;

class procedure TIDELogger.Info(const AMessage: string);
var
  LMsgSvc: IOTAMessageServices;
begin
  try
    if TryGetMessageServices(LMsgSvc) then
    begin
      LMsgSvc.AddTitleMessage(AMessage, nil);
      LMsgSvc.ShowMessageView(nil);
    end;
  except
  end;
end;

class procedure TIDELogger.Warning(const AMessage: string);
var
  LMsgSvc: IOTAMessageServices;
begin
  try
    if TryGetMessageServices(LMsgSvc) then
    begin
      LMsgSvc.AddTitleMessage('[WARNING] ' + AMessage, nil);
      LMsgSvc.ShowMessageView(nil);
    end;
  except
  end;
end;

class procedure TIDELogger.Error(const AMessage: string);
var
  LMsgSvc: IOTAMessageServices;
begin
  try
    if TryGetMessageServices(LMsgSvc) then
    begin
      LMsgSvc.AddTitleMessage('[ERROR] ' + AMessage, nil);
      LMsgSvc.ShowMessageView(nil);
    end;
  except
  end;
end;

class procedure TIDELogger.Progress(const AMessage: string; const APercent: Integer);
begin
  // Negative percent signals an error condition from the engine.
  if APercent < 0 then
    Error(AMessage)
  else
    Info(Format('[%d%%] %s', [APercent, AMessage]));
end;


end.
