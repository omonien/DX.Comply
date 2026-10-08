/// <summary>
/// DX.Comply.Tests.IDE.ReadmeSupport
/// Tests the README loading and lightweight Markdown-to-HTML conversion.
/// </summary>
///
/// <remarks>
/// These tests protect the IDE info tab against regressions in the repository
/// path discovery logic and the small markdown renderer used by the embedded
/// browser preview.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.IDE.ReadmeSupport;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIDEReadmeSupportTests = class
  public
    [Test]
    procedure ConvertMarkdownToHtmlDocument_RendersCommonReadmeStructures;
    [Test]
    procedure LoadDXComplyReadmeMarkdown_LoadsRepositoryReadme;
    [Test]
    procedure EmbeddedReadme_MatchesRepositoryFile;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows,
  DX.Comply.IDE.ReadmeSupport,
  DX.Comply.IDE.Resources,
  DX.Comply.Tests.Paths;

procedure TIDEReadmeSupportTests.ConvertMarkdownToHtmlDocument_RendersCommonReadmeStructures;
const
  cMarkdown =
    '# Title' + sLineBreak + sLineBreak +
    'Intro with [link](https://example.com) and `code`.' + sLineBreak + sLineBreak +
    '- Bullet one' + sLineBreak +
    '- Bullet two' + sLineBreak + sLineBreak +
    '1. First' + sLineBreak +
    '2. Second' + sLineBreak + sLineBreak +
    '| Name | Value |' + sLineBreak +
    '| ---- | ----- |' + sLineBreak +
    '| A | B |' + sLineBreak + sLineBreak +
    '```pascal' + sLineBreak +
    'ShowMessage(''Hi'');' + sLineBreak +
    '```';
var
  LHtml: string;
begin
  LHtml := ConvertMarkdownToHtmlDocument(cMarkdown, 'Sample');

  Assert.Contains(LHtml, '<h1>Title</h1>');
  Assert.Contains(LHtml, '<a href="https://example.com">link</a>');
  Assert.Contains(LHtml, '<code>code</code>');
  Assert.Contains(LHtml, '<ul>');
  Assert.Contains(LHtml, '<ol>');
  Assert.Contains(LHtml, '<table>');
  Assert.Contains(LHtml, '<pre><code>');
  Assert.Contains(LHtml, 'ShowMessage(''Hi'');');
end;

function NormalizeReadmeText(const AValue: string): string;
begin
  Result := AValue;
  if Result.StartsWith(#$FEFF) then
    Delete(Result, 1, 1);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

procedure TIDEReadmeSupportTests.LoadDXComplyReadmeMarkdown_LoadsRepositoryReadme;
var
  LMarkdown: string;
begin
  LMarkdown := LoadDXComplyReadmeMarkdown;

  Assert.Contains(LMarkdown, '# DX.Comply');
  Assert.Contains(LMarkdown, '## Why DX.Comply?');
  Assert.IsFalse(LMarkdown.Contains('could not be located'),
    'The info page must load the README instead of the missing-file message');
end;

procedure TIDEReadmeSupportTests.EmbeddedReadme_MatchesRepositoryFile;
var
  LFromRepo: string;
  LFromResource: string;
begin
  Assert.IsTrue(
    TryLoadDXComplyResourceText(HInstance, cDXComplyReadmeResource, LFromResource),
    'DXCOMPLYREADME must be linked into the test executable');

  LFromRepo := TFile.ReadAllText(TPath.Combine(RepoRoot, 'README.md'), TEncoding.UTF8);
  Assert.AreEqual(NormalizeReadmeText(LFromRepo), NormalizeReadmeText(LFromResource),
    'The embedded README must match README.md at the repository root');
  Assert.AreEqual(NormalizeReadmeText(LFromResource),
    NormalizeReadmeText(LoadDXComplyReadmeMarkdown),
    'The info page must prefer the embedded README over a file lookup');
end;

initialization
  TDUnitX.RegisterTestFixture(TIDEReadmeSupportTests);

end.