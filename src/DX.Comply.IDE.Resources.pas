/// <summary>
/// DX.Comply.IDE.Resources
/// Loads RCDATA embedded in the IDE package.
/// </summary>
///
/// <remarks>
/// GetIt and the installer do not ship the repository tree, so the info page
/// cannot depend on finding README.md next to src\DX.Comply.Engine.dproj.
/// The package links DX.Comply.IDE.Resources.rc. A development checkout can
/// still fall back to the file when the resource is absent.
/// HInstance is this module. Inside the design package that is the BPL.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.Resources;

interface

uses
  Winapi.Windows;

const
  /// <summary>
  /// RCDATA name of the embedded README.md bytes.
  /// </summary>
  cDXComplyReadmeResource = 'DXCOMPLYREADME';
  /// <summary>
  /// RCDATA name of assets\DX.Comply.Icon.bmp.
  /// </summary>
  cDXComplyIconBmpResource = 'DXCOMPLYICONBMP';
  /// <summary>
  /// RCDATA name of assets\DX.Comply.Icon.png.
  /// </summary>
  cDXComplyIconPngResource = 'DXCOMPLYICONPNG';

/// <summary>
/// Copies an RCDATA resource into ABytes.
/// Pass 0 for AModule to read the module that contains this unit.
/// Returns False when the resource is missing or empty. Does not raise.
/// </summary>
function TryLoadDXComplyResourceBytes(AModule: HMODULE; const AResourceName: string;
  out ABytes: TBytes): Boolean;

/// <summary>
/// UTF-8 text of an RCDATA resource, without a leading BOM.
/// Pass 0 for AModule to read the module that contains this unit.
/// Returns False when the resource is missing or empty. Does not raise.
/// </summary>
function TryLoadDXComplyResourceText(AModule: HMODULE; const AResourceName: string;
  out AText: string): Boolean;

implementation

uses
  System.Classes,
  System.SysUtils;

function TryLoadDXComplyResourceBytes(AModule: HMODULE; const AResourceName: string;
  out ABytes: TBytes): Boolean;
var
  LModule: HMODULE;
  LSize: Integer;
  LStream: TResourceStream;
begin
  Result := False;
  SetLength(ABytes, 0);
  if AResourceName = '' then
    Exit;

  if AModule = 0 then
    LModule := HInstance
  else
    LModule := AModule;

  try
    if FindResource(LModule, PChar(AResourceName), RT_RCDATA) = 0 then
      Exit;

    LStream := TResourceStream.Create(LModule, AResourceName, RT_RCDATA);
    try
      if (LStream.Size <= 0) or (LStream.Size > MaxInt) then
        Exit;
      LSize := Integer(LStream.Size);
      SetLength(ABytes, LSize);
      LStream.ReadBuffer(ABytes[0], LSize);
      Result := True;
    finally
      LStream.Free;
    end;
  except
    SetLength(ABytes, 0);
    Result := False;
  end;
end;

function TryLoadDXComplyResourceText(AModule: HMODULE; const AResourceName: string;
  out AText: string): Boolean;
var
  LBytes: TBytes;
begin
  AText := '';
  Result := TryLoadDXComplyResourceBytes(AModule, AResourceName, LBytes);
  if not Result then
    Exit;

  try
    AText := TEncoding.UTF8.GetString(LBytes);
    if AText.StartsWith(#$FEFF) then
      Delete(AText, 1, 1);
  except
    AText := '';
    Result := False;
  end;
end;

end.
