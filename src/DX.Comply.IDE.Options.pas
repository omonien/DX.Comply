/// <summary>
/// DX.Comply.IDE.Options
/// Registers the DX.Comply options page in RAD Studio.
/// </summary>
///
/// <remarks>
/// The options page persists global plugin settings that control optional Deep-Evidence
/// auto-build behavior for the IDE integration.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.Options;

interface

uses
  System.SysUtils,
  ToolsAPI,
  Vcl.Dialogs,
  Vcl.Forms,
  DX.Comply.IDE.OptionsFrame;

type
  /// <summary>
  /// Provides the Tools &gt; Options page for the DX.Comply IDE plugin.
  /// </summary>
  TDXComplyIDEOptionsPage = class(TInterfacedObject, INTAAddInOptions)
  private
    FFrame: TFrameDXComplyOptions;
  public
    procedure DialogClosed(Accepted: Boolean);
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
    function ValidateContents: Boolean;
  end;

implementation

uses
  DX.Comply.IDE.Settings;

procedure TDXComplyIDEOptionsPage.DialogClosed(Accepted: Boolean);
var
  LSettings: TDXComplyIDESettings;
begin
  if Accepted and Assigned(FFrame) then
  begin
    LSettings := FFrame.SaveSettings;
    TDXComplyIDESettingsStore.Save(LSettings);
  end;

  FFrame := nil;
end;

procedure TDXComplyIDEOptionsPage.FrameCreated(AFrame: TCustomFrame);
begin
  if AFrame is TFrameDXComplyOptions then
  begin
    FFrame := TFrameDXComplyOptions(AFrame);
    FFrame.LoadSettings(TDXComplyIDESettingsStore.Load);
  end;
end;

function TDXComplyIDEOptionsPage.GetArea: string;
begin
  Result := '';
end;

function TDXComplyIDEOptionsPage.GetCaption: string;
begin
  Result := 'DX.Comply';
end;

function TDXComplyIDEOptionsPage.GetFrameClass: TCustomFrameClass;
begin
  Result := TFrameDXComplyOptions;
end;

function TDXComplyIDEOptionsPage.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TDXComplyIDEOptionsPage.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

function TDXComplyIDEOptionsPage.ValidateContents: Boolean;
var
  LMessage: string;
begin
  Result := not Assigned(FFrame) or FFrame.ValidateSettings(LMessage);
  if not Result then
    MessageDlg(LMessage, mtError, [mbOK], 0);
end;

end.