/// <summary>
/// DX.Comply.IDE.ReadmeSupport
/// Loads and converts the project README into lightweight HTML for IDE display.
/// </summary>
///
/// <remarks>
/// The options page uses this unit to render a local, dependency-free README
/// preview inside a classic TWebBrowser host without relying on external tools
/// or network services.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.ReadmeSupport;

interface

function LoadDXComplyReadmeMarkdown: string;
function ConvertMarkdownToHtmlDocument(const AMarkdown, ATitle: string): string;
function BuildDXComplyReadmeHtmlDocument: string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.SysUtils,
  DX.Comply.IDE.PathSupport;

function EscapeHtml(const AValue: string): string;
begin
  Result := AValue;
  Result := Result.Replace('&', '&amp;');
  Result := Result.Replace('<', '&lt;');
  Result := Result.Replace('>', '&gt;');
  Result := Result.Replace('"', '&quot;');
end;

function ApplyInlineMarkdown(const AValue: string): string;
begin
  Result := EscapeHtml(AValue);
  Result := TRegEx.Replace(Result, '\[([^\]]+)\]\(([^\)]+)\)',
    '<a href="$2">$1</a>');
  Result := TRegEx.Replace(Result, '`([^`]+)`', '<code>$1</code>');
  Result := TRegEx.Replace(Result, '\*\*([^\*]+)\*\*', '<strong>$1</strong>');
  Result := TRegEx.Replace(Result, '\*([^\*]+)\*', '<em>$1</em>');
end;

function IsMarkdownTableSeparator(const ALine: string): Boolean;
var
  LSanitizedLine: string;
begin
  LSanitizedLine := Trim(ALine);
  if not LSanitizedLine.Contains('|') then
    Exit(False);

  LSanitizedLine := LSanitizedLine.Replace('|', '');
  LSanitizedLine := LSanitizedLine.Replace(':', '');
  LSanitizedLine := LSanitizedLine.Replace('-', '');
  Result := Trim(LSanitizedLine) = '';
end;

function SplitMarkdownTableRow(const ALine: string): TArray<string>;
var
  LRow: string;
  LValues: TArray<string>;
  I: Integer;
begin
  LRow := Trim(ALine);
  if LRow.StartsWith('|') then
    Delete(LRow, 1, 1);
  if LRow.EndsWith('|') then
    Delete(LRow, Length(LRow), 1);

  LValues := LRow.Split(['|']);
  for I := Low(LValues) to High(LValues) do
    LValues[I] := Trim(LValues[I]);
  Result := LValues;
end;

procedure FlushParagraph(ALines, AParagraphLines: TStrings);
begin
  if AParagraphLines.Count = 0 then
    Exit;
  ALines.Add('<p>' + ApplyInlineMarkdown(StringReplace(
    Trim(AParagraphLines.Text), sLineBreak, ' ', [rfReplaceAll])) + '</p>');
  AParagraphLines.Clear;
end;

function LoadDXComplyReadmeMarkdown: string;
var
  LReadmePath: string;
begin
  LReadmePath := FindDXComplyRepositoryFile('README.md');
  if LReadmePath = '' then
    Exit('# DX.Comply' + sLineBreak + sLineBreak +
      'README.md could not be located from the installed package path.');
  Result := TFile.ReadAllText(LReadmePath, TEncoding.UTF8);
end;

function ConvertMarkdownToHtmlDocument(const AMarkdown, ATitle: string): string;
type
  TListKind = (lkNone, lkUnordered, lkOrdered);
var
  I: Integer;
  LCurrentLine: string;
  LHeadingMatch: TMatch;
  LHtmlLines: TStringList;
  LInputLines: TStringList;
  LListKind: TListKind;
  LNormalizedMarkdown: string;
  LNextLine: string;
  LParagraphBuffer: TStringList;
  LHeadingLevel: Integer;

  procedure CloseList;
  begin
    case LListKind of
      lkUnordered: LHtmlLines.Add('</ul>');
      lkOrdered: LHtmlLines.Add('</ol>');
    end;
    LListKind := lkNone;
  end;

  procedure OpenList(AListKind: TListKind);
  begin
    if LListKind = AListKind then
      Exit;
    CloseList;
    case AListKind of
      lkUnordered: LHtmlLines.Add('<ul>');
      lkOrdered: LHtmlLines.Add('<ol>');
    end;
    LListKind := AListKind;
  end;

  procedure FlushParagraphBuffer;
  begin
    FlushParagraph(LHtmlLines, LParagraphBuffer);
  end;

  procedure AddTable;
  var
    LCells: TArray<string>;
    LCell: string;
  begin
    LHtmlLines.Add('<div class="table-wrap"><table><thead><tr>');
    LCells := SplitMarkdownTableRow(LCurrentLine);
    for LCell in LCells do
      LHtmlLines.Add('<th>' + ApplyInlineMarkdown(LCell) + '</th>');
    LHtmlLines.Add('</tr></thead><tbody>');

    Inc(I, 2);
    while I < LInputLines.Count do
    begin
      if not Trim(LInputLines[I]).StartsWith('|') then
        Break;
      LHtmlLines.Add('<tr>');
      LCells := SplitMarkdownTableRow(LInputLines[I]);
      for LCell in LCells do
        LHtmlLines.Add('<td>' + ApplyInlineMarkdown(LCell) + '</td>');
      LHtmlLines.Add('</tr>');
      Inc(I);
    end;
    LHtmlLines.Add('</tbody></table></div>');
    Dec(I);
  end;

begin
  LHtmlLines := TStringList.Create;
  LInputLines := TStringList.Create;
  LParagraphBuffer := TStringList.Create;
  try
    LNormalizedMarkdown := StringReplace(AMarkdown, #13#10, #10, [rfReplaceAll]);
    LNormalizedMarkdown := StringReplace(LNormalizedMarkdown, #13, #10,
      [rfReplaceAll]);
    LNormalizedMarkdown := StringReplace(LNormalizedMarkdown, #10, sLineBreak,
      [rfReplaceAll]);
    LInputLines.Text := LNormalizedMarkdown;

    Result := '';
    LHtmlLines.Add('<!DOCTYPE html>');
    LHtmlLines.Add('<html><head><meta charset="utf-8" />');
    LHtmlLines.Add('<meta http-equiv="X-UA-Compatible" content="IE=edge" />');
    LHtmlLines.Add('<title>' + EscapeHtml(ATitle) + '</title>');
    LHtmlLines.Add('<style>body{font-family:Segoe UI,Tahoma,Arial,sans-serif;margin:0;background:#ffffff;color:#1f2937;line-height:1.55;}main{max-width:1100px;margin:0 auto;padding:24px;}h1,h2,h3,h4,h5,h6{color:#0f172a;margin:1.2em 0 0.5em;}p,ul,ol,blockquote,pre,.table-wrap{margin:0 0 1em;}blockquote{border-left:4px solid #7dd3fc;background:#f0f9ff;padding:12px 16px;}code{font-family:Cascadia Mono,Consolas,monospace;background:#f3f4f6;padding:1px 4px;}pre{background:#0f172a;color:#e2e8f0;padding:16px;overflow:auto;}pre code{background:transparent;padding:0;color:inherit;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #d1d5db;padding:8px 10px;vertical-align:top;}th{background:#f8fafc;text-align:left;}a{color:#0369a1;text-decoration:none;}a:hover{text-decoration:underline;}hr{border:none;border-top:1px solid #d1d5db;margin:1.5em 0;}</style></head><body><main>');

    LListKind := lkNone;
    I := 0;
    while I < LInputLines.Count do
    begin
      LCurrentLine := TrimRight(LInputLines[I]);
      LNextLine := '';
      if I + 1 < LInputLines.Count then
        LNextLine := Trim(LInputLines[I + 1]);

      if Trim(LCurrentLine) = '' then
      begin
        FlushParagraphBuffer;
        CloseList;
        Inc(I);
        Continue;
      end;

      if LCurrentLine.StartsWith('```') then
      begin
        FlushParagraphBuffer;
        CloseList;
        LHtmlLines.Add('<pre><code>');
        Inc(I);
        while (I < LInputLines.Count) and not TrimRight(LInputLines[I]).StartsWith('```') do
        begin
          LHtmlLines.Add(EscapeHtml(LInputLines[I]));
          Inc(I);
        end;
        LHtmlLines.Add('</code></pre>');
        Inc(I);
        Continue;
      end;

      if Trim(LCurrentLine).StartsWith('|') and IsMarkdownTableSeparator(LNextLine) then
      begin
        FlushParagraphBuffer;
        CloseList;
        AddTable;
        Inc(I);
        Continue;
      end;

      LHeadingMatch := TRegEx.Match(Trim(LCurrentLine), '^(#{1,6})\s+(.+)$');
      if LHeadingMatch.Success then
      begin
        FlushParagraphBuffer;
        CloseList;
        LHeadingLevel := LHeadingMatch.Groups[1].Value.Length;
        LHtmlLines.Add(Format('<h%d>%s</h%d>', [LHeadingLevel,
          ApplyInlineMarkdown(LHeadingMatch.Groups[2].Value), LHeadingLevel]));
        Inc(I);
        Continue;
      end;

      if TRegEx.IsMatch(Trim(LCurrentLine), '^[-*]{3,}$') then
      begin
        FlushParagraphBuffer;
        CloseList;
        LHtmlLines.Add('<hr />');
        Inc(I);
        Continue;
      end;

      if TRegEx.IsMatch(Trim(LCurrentLine), '^[-*]\s+') then
      begin
        FlushParagraphBuffer;
        OpenList(lkUnordered);
        LHtmlLines.Add('<li>' + ApplyInlineMarkdown(TRegEx.Replace(Trim(LCurrentLine), '^[-*]\s+', '')) + '</li>');
        Inc(I);
        Continue;
      end;

      if TRegEx.IsMatch(Trim(LCurrentLine), '^[0-9]+\.\s+') then
      begin
        FlushParagraphBuffer;
        OpenList(lkOrdered);
        LHtmlLines.Add('<li>' + ApplyInlineMarkdown(TRegEx.Replace(Trim(LCurrentLine), '^[0-9]+\.\s+', '')) + '</li>');
        Inc(I);
        Continue;
      end;

      if Trim(LCurrentLine).StartsWith('>') then
      begin
        FlushParagraphBuffer;
        CloseList;
        LHtmlLines.Add('<blockquote><p>' + ApplyInlineMarkdown(
          Trim(TRegEx.Replace(Trim(LCurrentLine), '^>\s*', ''))) + '</p></blockquote>');
        Inc(I);
        Continue;
      end;

      LParagraphBuffer.Add(Trim(LCurrentLine));
      Inc(I);
    end;

    FlushParagraphBuffer;
    CloseList;
    LHtmlLines.Add('</main></body></html>');
    Result := LHtmlLines.Text;
  finally
    LParagraphBuffer.Free;
    LInputLines.Free;
    LHtmlLines.Free;
  end;
end;

function BuildDXComplyReadmeHtmlDocument: string;
begin
  Result := ConvertMarkdownToHtmlDocument(LoadDXComplyReadmeMarkdown,
    'DX.Comply README');
end;

end.