/// <summary>
/// DX.Comply.Tests.Cpe
/// DUnitX tests for CPE names, dictionary XML, NVD responses and the API key.
/// </summary>
///
/// <remarks>
/// XML tests check escaping, provenance comments and CPE 2.3 formatting.
/// The NVD test reads a recorded API 2.0 body and does not call the network.
/// Key tests use a stand-in for the environment and the registry.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Cpe;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.Cpe,
  DX.Comply.Cpe.Nvd,
  DX.Comply.Cpe.NvdKey;

type
  /// <summary>Stand-in that records which sources the resolver asked for.</summary>
  TFakeNvdApiKeySources = class(TInterfacedObject, INvdApiKeySources)
  public
    EnvironmentValue: string;
    RegistryValue: string;
    EnvironmentReads: Integer;
    RegistryReads: Integer;
    function ReadEnvironmentValue: string;
    function ReadRegistryValue: string;
  end;

  [TestFixture]
  TCpeFormatTests = class
  public
    [Test]
    procedure FormatCpe23_VendorProductVersion;

    [Test]
    procedure FormatCpe23_EscapesSpecialsAndSpaces;

    [Test]
    procedure FormatCpe23_EmptyVersionIsAny;

    [Test]
    procedure FormatCpe22_OmitsEmptyVersion;
  end;

  [TestFixture]
  TCpeDictionaryTests = class
  public
    [Test]
    procedure DictionaryXml_EscapesTitleAndHref;

    [Test]
    procedure DictionaryXml_ProvenanceCommentsAndCpe23Item;

    [Test]
    procedure DictionaryXml_CommentDoesNotContainDoubleHyphen;

    [Test]
    procedure MailText_NamesTheMailboxAndDoesNotSend;

    [Test]
    procedure WriteFiles_NextToSbom;
  end;

  [TestFixture]
  TNvdCpeResponseTests = class
  public
    [Test]
    procedure Parse_RecordedFixture_TitleDeprecationAndTotal;

    [Test]
    procedure Parse_InvalidJson_SetsError;

    [Test]
    procedure Parse_EmptyProducts_SucceedsWithNoMatches;

    [Test]
    procedure Search_EmptyKeyword_DoesNotDescribeATransportError;

    [Test]
    procedure LookupReport_PrintsMatchesAndOmitsTheKey;

    [Test]
    procedure LookupReport_ZeroMatchesNamesDictionary;

    /// <summary>
    /// The NVD returns one page. When it reports more names than the page
    /// holds, the count says so.
    /// </summary>
    [Test]
    procedure LookupReport_MoreThanOnePage_NamesTheTotal;
  end;

  [TestFixture]
  TNvdApiKeyTests = class
  public
    [Test]
    procedure Resolve_OptionWinsAndSkipsLaterSources;

    [Test]
    procedure Resolve_EnvironmentWinsOverRegistry;

    [Test]
    procedure Resolve_RegistryWhenOptionAndEnvironmentAreBlank;

    [Test]
    procedure Resolve_NoneWhenEverySourceIsBlank;

    [Test]
    procedure LogLine_NamesTheSourceAndOmitsTheKey;

    [Test]
    procedure RegistryPath_IsThePerUserNistKey;
  end;

  [TestFixture]
  TProductCpeWriterTests = class
  public
    [Test]
    procedure CycloneDx_WritesProductCpeOnMetadataAndDeliverable;

    [Test]
    procedure CycloneDx_OmitsInvalidProductCpe;

    [Test]
    procedure Spdx_WritesSecurityExternalRefOnDeliverable;

    /// <summary>SPDX 3.0.1 keeps the product CPE as an external identifier.</summary>
    [Test]
    procedure Spdx3_WritesProductCpeAsExternalIdentifier;

    [Test]
    procedure ProductCpe_RoundTripThroughConfig;

    [Test]
    procedure Cli_CpeAndApiKeyStayOutOfTheConfigFile;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  DX.Comply.ComponentManifest,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.CycloneDx.XmlWriter,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.SbomHeaderConfig,
  DX.Comply.Spdx.Writer,
  DX.Comply.Spdx3.Writer,
  DX.Comply.CLI.Options,
  DX.Comply.Tests.Paths;

function TFakeNvdApiKeySources.ReadEnvironmentValue: string;
begin
  Inc(EnvironmentReads);
  Result := EnvironmentValue;
end;

function TFakeNvdApiKeySources.ReadRegistryValue: string;
begin
  Inc(RegistryReads);
  Result := RegistryValue;
end;

function SampleSubmission: TCpeSubmission;
begin
  Result.Vendor := 'Acme GmbH';
  Result.Product := 'My App';
  Result.Version := '1.2.3';
  Result.References := CpeReferencesFromUrls('https://acme.example/product',
    'https://github.com/acme/app');
end;

procedure TCpeFormatTests.FormatCpe23_VendorProductVersion;
begin
  Assert.AreEqual('cpe:2.3:a:acme_gmbh:my_app:1.2.3:*:*:*:*:*:*:*',
    FormatCpe23('Acme GmbH', 'My App', '1.2.3'));
end;

procedure TCpeFormatTests.FormatCpe23_EscapesSpecialsAndSpaces;
begin
  Assert.AreEqual('cpe:2.3:a:smith_\&_sons:widget\+:1.0\+build:*:*:*:*:*:*:*',
    FormatCpe23('Smith & Sons', 'Widget+', '1.0+build'));
end;

procedure TCpeFormatTests.FormatCpe23_EmptyVersionIsAny;
begin
  Assert.AreEqual('cpe:2.3:a:acme:widget:*:*:*:*:*:*:*:*',
    FormatCpe23('Acme', 'Widget', '   '));
end;

procedure TCpeFormatTests.FormatCpe22_OmitsEmptyVersion;
begin
  Assert.AreEqual('cpe:/a:smith_%26_sons:widget%2b:1.0%2bbuild',
    FormatCpe22('Smith & Sons', 'Widget+', '1.0+build'));
  Assert.AreEqual('cpe:/a:acme:widget', FormatCpe22('Acme', 'Widget', ''));
end;

procedure TCpeDictionaryTests.DictionaryXml_EscapesTitleAndHref;
var
  LSubmission: TCpeSubmission;
  LXml: string;
begin
  LSubmission.Vendor := 'Acme <Labs> & Co';
  LSubmission.Product := 'Widget "Pro"';
  LSubmission.Version := '1.0';
  LSubmission.References := CpeReferencesFromUrls(
    'https://acme.example/a?x=1&y=2', '');
  LXml := BuildCpeDictionaryXml(LSubmission);
  Assert.IsTrue(Pos('Acme &lt;Labs&gt; &amp; Co', LXml) > 0, LXml);
  Assert.IsTrue(Pos('Widget &quot;Pro&quot;', LXml) > 0, LXml);
  Assert.IsTrue(Pos('href="https://acme.example/a?x=1&amp;y=2"', LXml) > 0, LXml);
  Assert.AreEqual(0, Pos('<Labs>', LXml), LXml);
end;

procedure TCpeDictionaryTests.DictionaryXml_ProvenanceCommentsAndCpe23Item;
var
  LXml: string;
begin
  LXml := BuildCpeDictionaryXml(SampleSubmission);
  Assert.IsTrue(Pos('<cpe-23:cpe23-item name="cpe:2.3:a:acme_gmbh:my_app:1.2.3:*:*:*:*:*:*:*"/>',
    LXml) > 0, LXml);
  Assert.IsTrue(Pos('name="cpe:/a:acme_gmbh:my_app:1.2.3"', LXml) > 0, LXml);
  Assert.IsTrue(Pos('<!-- Provenance: https://acme.example/product -->', LXml) > 0, LXml);
  Assert.IsTrue(Pos('<!-- Provenance: https://github.com/acme/app -->', LXml) > 0, LXml);
  Assert.IsTrue(Pos('<reference href="https://acme.example/product">Product</reference>',
    LXml) > 0, LXml);
  Assert.IsTrue(Pos('<reference href="https://github.com/acme/app">Repository</reference>',
    LXml) > 0, LXml);
  Assert.IsTrue(Pos('NIST may normalize them.', LXml) > 0, LXml);
  Assert.IsTrue(Pos('<!-- Provenance: https://acme.example/product -->', LXml) <
    Pos('<references>', LXml), LXml);
end;

procedure TCpeDictionaryTests.DictionaryXml_CommentDoesNotContainDoubleHyphen;
var
  LSubmission: TCpeSubmission;
  LXml: string;
  LCommentAt, LCommentEnd: Integer;
  LComment: string;
begin
  LSubmission.Vendor := 'Acme';
  LSubmission.Product := 'Widget';
  LSubmission.Version := '1';
  LSubmission.References := CpeReferencesFromUrls('https://example.com/a--b', '');
  LXml := BuildCpeDictionaryXml(LSubmission);
  LCommentAt := Pos('Provenance:', LXml);
  Assert.IsTrue(LCommentAt > 0, LXml);
  LCommentEnd := Pos('-->', LXml, LCommentAt);
  LComment := Copy(LXml, LCommentAt, LCommentEnd - LCommentAt);
  Assert.AreEqual(0, Pos('--', LComment), LComment);
  Assert.IsTrue(Pos('https://example.com/a--b', LXml) > 0, LXml);
end;

procedure TCpeDictionaryTests.MailText_NamesTheMailboxAndDoesNotSend;
var
  LMail: string;
begin
  LMail := BuildCpeMailText(SampleSubmission);
  Assert.IsTrue(Pos('To: ' + cCpeDictionaryMailAddress, LMail) = 1, LMail);
  Assert.IsTrue(Pos('cpe:2.3:a:acme_gmbh:my_app:1.2.3:*:*:*:*:*:*:*', LMail) > 0, LMail);
  Assert.IsTrue(Pos('https://acme.example/product', LMail) > 0, LMail);
  Assert.IsTrue(Pos('does not send the message', LMail) > 0, LMail);
  Assert.AreEqual(0, Pos('mailto:', LowerCase(LMail)), LMail);
end;

procedure TCpeDictionaryTests.WriteFiles_NextToSbom;
var
  LDir, LSbom, LDictionary, LMail, LError: string;
begin
  LDir := TPath.Combine(TPath.GetTempPath, 'dxc-cpe-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LDir);
  try
    LSbom := TPath.Combine(LDir, 'bom.json');
    Assert.IsTrue(WriteCpeSubmissionFiles(LSbom, '', SampleSubmission,
      LDictionary, LMail, LError), LError);
    Assert.AreEqual(TPath.Combine(LDir, 'bom.cpe-dictionary.xml'), LDictionary);
    Assert.AreEqual(TPath.Combine(LDir, 'bom.cpe-mail.txt'), LMail);
    Assert.AreEqual(BuildCpeDictionaryXml(SampleSubmission),
      TFile.ReadAllText(LDictionary, TEncoding.UTF8));
    Assert.AreEqual(BuildCpeMailText(SampleSubmission),
      TFile.ReadAllText(LMail, TEncoding.UTF8));
  finally
    TDirectory.Delete(LDir, True);
  end;
end;

procedure TNvdCpeResponseTests.Parse_RecordedFixture_TitleDeprecationAndTotal;
var
  LPath: string;
  LParsed: TNvdCpeSearchResult;
begin
  LPath := TPath.Combine(RepoRoot, 'tests' + PathDelim + 'fixtures' + PathDelim +
    'nvd' + PathDelim + 'cpes-2.0-sample.json');
  LParsed := ParseNvdCpeResponse(TFile.ReadAllText(LPath, TEncoding.UTF8));
  Assert.AreEqual('', LParsed.Error);
  Assert.AreEqual(2, LParsed.TotalResults);
  Assert.AreEqual<Integer>(2, Length(LParsed.Matches));
  Assert.AreEqual('cpe:2.3:a:acme:widget:1.2.3:*:*:*:*:*:*:*', LParsed.Matches[0].CpeName);
  Assert.AreEqual('Acme Widget 1.2.3', LParsed.Matches[0].Title);
  Assert.IsFalse(LParsed.Matches[0].Deprecated);
  Assert.AreEqual('cpe:2.3:a:acme:widget:1.0:*:*:*:*:*:*:*', LParsed.Matches[1].CpeName);
  Assert.AreEqual('Altes Widget', LParsed.Matches[1].Title);
  Assert.IsTrue(LParsed.Matches[1].Deprecated);
end;

procedure TNvdCpeResponseTests.Parse_InvalidJson_SetsError;
var
  LParsed: TNvdCpeSearchResult;
begin
  LParsed := ParseNvdCpeResponse('{');
  Assert.IsFalse(LParsed.IsSuccess);
  Assert.IsTrue(Pos('not valid JSON', LParsed.Error) > 0, LParsed.Error);
  Assert.AreEqual<Integer>(0, Length(LParsed.Matches));
end;

procedure TNvdCpeResponseTests.Parse_EmptyProducts_SucceedsWithNoMatches;
var
  LParsed: TNvdCpeSearchResult;
begin
  LParsed := ParseNvdCpeResponse('{"totalResults":0,"products":[]}');
  Assert.IsTrue(LParsed.IsSuccess, LParsed.Error);
  Assert.AreEqual(0, LParsed.TotalResults);
  Assert.AreEqual<Integer>(0, Length(LParsed.Matches));
end;

procedure TNvdCpeResponseTests.LookupReport_PrintsMatchesAndOmitsTheKey;
var
  LParsed: TNvdCpeSearchResult;
  LReport: string;
begin
  LParsed := ParseNvdCpeResponse(TFile.ReadAllText(TPath.Combine(RepoRoot,
    'tests' + PathDelim + 'fixtures' + PathDelim + 'nvd' + PathDelim +
    'cpes-2.0-sample.json'), TEncoding.UTF8));
  LReport := FormatNvdCpeLookupReport('Acme Widget', 'NVD API key: registry', LParsed);
  Assert.IsTrue(Pos('NVD API key: registry', LReport) > 0, LReport);
  Assert.IsTrue(Pos('Keyword: Acme Widget', LReport) > 0, LReport);
  Assert.IsTrue(Pos('Matches: 2', LReport) > 0, LReport);
  Assert.IsTrue(Pos('cpe:2.3:a:acme:widget:1.2.3:*:*:*:*:*:*:*', LReport) > 0, LReport);
  Assert.IsTrue(Pos('Acme Widget 1.2.3', LReport) > 0, LReport);
  Assert.IsTrue(Pos('current', LReport) > 0, LReport);
  Assert.IsTrue(Pos('deprecated', LReport) > 0, LReport);
  Assert.AreEqual(0, Pos('secret-token-value', LReport), LReport);
end;

procedure TNvdCpeResponseTests.LookupReport_MoreThanOnePage_NamesTheTotal;
var
  LParsed: TNvdCpeSearchResult;
  LReport: string;
begin
  LParsed := ParseNvdCpeResponse(
    '{"totalResults":312,"products":[' +
    '{"cpe":{"cpeName":"cpe:2.3:a:acme:widget:1.0:*:*:*:*:*:*:*","deprecated":false}},' +
    '{"cpe":{"cpeName":"cpe:2.3:a:acme:widget:2.0:*:*:*:*:*:*:*","deprecated":false}}]}');
  Assert.AreEqual('2 of 312', NvdCpeMatchCountText(LParsed));
  LReport := FormatNvdCpeLookupReport('Acme Widget', 'NVD API key: none', LParsed);
  Assert.IsTrue(Pos('Matches: 2 of 312', LReport) > 0, LReport);
  Assert.IsTrue(Pos('Only the first page is listed', LReport) > 0, LReport);

  // The whole result on one page keeps the plain count.
  LParsed := ParseNvdCpeResponse(
    '{"totalResults":1,"products":[' +
    '{"cpe":{"cpeName":"cpe:2.3:a:acme:widget:1.0:*:*:*:*:*:*:*","deprecated":false}}]}');
  Assert.AreEqual('1', NvdCpeMatchCountText(LParsed));
  Assert.AreEqual(0, Pos('first page',
    FormatNvdCpeLookupReport('Acme Widget', 'NVD API key: none', LParsed)));
end;

procedure TNvdCpeResponseTests.LookupReport_ZeroMatchesNamesDictionary;
var
  LParsed: TNvdCpeSearchResult;
  LReport: string;
begin
  LParsed := ParseNvdCpeResponse('{"totalResults":0,"products":[]}');
  LReport := FormatNvdCpeLookupReport('Acme Widget', 'NVD API key: none', LParsed);
  Assert.IsTrue(Pos('Matches: 0', LReport) > 0, LReport);
  Assert.IsTrue(Pos('--cpe-dictionary', LReport) > 0, LReport);
  Assert.IsTrue(Pos('does not send the message', LReport) > 0, LReport);
  Assert.IsTrue(Pos('NIST may normalize them.', LReport) > 0, LReport);
end;

procedure TNvdCpeResponseTests.Search_EmptyKeyword_DoesNotDescribeATransportError;
var
  LParsed: TNvdCpeSearchResult;
begin
  LParsed := SearchNvdCpes('   ', 'secret-token-value');
  Assert.IsFalse(LParsed.IsSuccess);
  Assert.IsTrue(Pos('keyword', LParsed.Error) > 0, LParsed.Error);
  Assert.AreEqual(0, Pos('secret-token-value', LParsed.Error), LParsed.Error);
end;

procedure TNvdApiKeyTests.Resolve_OptionWinsAndSkipsLaterSources;
var
  LFake: TFakeNvdApiKeySources;
  LSources: INvdApiKeySources;
  LResolved: TNvdApiKeyResolution;
begin
  LFake := TFakeNvdApiKeySources.Create;
  LSources := LFake;
  LFake.EnvironmentValue := 'from-env';
  LFake.RegistryValue := 'from-registry';
  LResolved := ResolveNvdApiKey('  from-option  ', LSources);
  Assert.AreEqual('from-option', LResolved.Key);
  Assert.AreEqual(Ord(akoOption), Ord(LResolved.Origin));
  Assert.AreEqual(0, LFake.EnvironmentReads);
  Assert.AreEqual(0, LFake.RegistryReads);
end;

procedure TNvdApiKeyTests.Resolve_EnvironmentWinsOverRegistry;
var
  LFake: TFakeNvdApiKeySources;
  LSources: INvdApiKeySources;
  LResolved: TNvdApiKeyResolution;
begin
  LFake := TFakeNvdApiKeySources.Create;
  LSources := LFake;
  LFake.EnvironmentValue := 'from-env';
  LFake.RegistryValue := 'from-registry';
  LResolved := ResolveNvdApiKey('', LSources);
  Assert.AreEqual('from-env', LResolved.Key);
  Assert.AreEqual(Ord(akoEnvironment), Ord(LResolved.Origin));
  Assert.AreEqual(1, LFake.EnvironmentReads);
  Assert.AreEqual(0, LFake.RegistryReads);
end;

procedure TNvdApiKeyTests.Resolve_RegistryWhenOptionAndEnvironmentAreBlank;
var
  LFake: TFakeNvdApiKeySources;
  LSources: INvdApiKeySources;
  LResolved: TNvdApiKeyResolution;
begin
  LFake := TFakeNvdApiKeySources.Create;
  LSources := LFake;
  LFake.EnvironmentValue := '   ';
  LFake.RegistryValue := 'from-registry';
  LResolved := ResolveNvdApiKey('   ', LSources);
  Assert.AreEqual('from-registry', LResolved.Key);
  Assert.AreEqual(Ord(akoRegistry), Ord(LResolved.Origin));
  Assert.AreEqual(1, LFake.RegistryReads);
end;

procedure TNvdApiKeyTests.Resolve_NoneWhenEverySourceIsBlank;
var
  LFake: TFakeNvdApiKeySources;
  LSources: INvdApiKeySources;
  LResolved: TNvdApiKeyResolution;
begin
  LFake := TFakeNvdApiKeySources.Create;
  LSources := LFake;
  LResolved := ResolveNvdApiKey('', LSources);
  Assert.AreEqual('', LResolved.Key);
  Assert.AreEqual(Ord(akoNone), Ord(LResolved.Origin));
  Assert.AreEqual('NVD API key: none', NvdApiKeyLogLine(LResolved));
end;

procedure TNvdApiKeyTests.LogLine_NamesTheSourceAndOmitsTheKey;
var
  LResolved: TNvdApiKeyResolution;
  LLine: string;
begin
  LResolved.Key := 'secret-token-value';
  LResolved.Origin := akoOption;
  LLine := NvdApiKeyLogLine(LResolved);
  Assert.AreEqual('NVD API key: option', LLine);
  Assert.AreEqual(0, Pos('secret-token-value', LLine), LLine);
end;

procedure TNvdApiKeyTests.RegistryPath_IsThePerUserNistKey;
begin
  Assert.AreEqual('\Software\Developer Experts\DX.Comply\NIST', cNvdApiKeyRegistryPath);
  Assert.AreEqual('ApiKey', cNvdApiKeyRegistryValue);
  Assert.AreEqual('NVD_API_KEY', cNvdApiKeyEnvironmentVariable);
end;

function WriteProductCpe(AFormat: TSbomFormat; const ACpe: string): string;
var
  LWriter: ISbomWriter;
  LArtefacts: TArtefactList;
  LArtefact: TArtefactInfo;
  LMetadata: TSbomMetadata;
  LProject: TProjectInfo;
  LPath: string;
begin
  LPath := TPath.Combine(TPath.GetTempPath, 'dxc-cpe-sbom-' + TGUID.NewGuid.ToString);
  if AFormat = sfCycloneDxXml then
    LPath := LPath + '.xml'
  else
    LPath := LPath + '.json';
  LArtefacts := TArtefactList.Create;
  LProject := TProjectInfo.Create;
  try
    LArtefact := Default(TArtefactInfo);
    LArtefact.RelativePath := 'TestApp.exe';
    LArtefact.FilePath := 'TestApp.exe';
    LArtefact.ArtefactType := 'application';
    LArtefact.Hash := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    LArtefacts.Add(LArtefact);
    LMetadata := Default(TSbomMetadata);
    LMetadata.ProductName := 'TestApp';
    LMetadata.ProductVersion := '1.2.3';
    LMetadata.Supplier := 'Acme GmbH';
    LMetadata.Copyright := 'Copyright 2026 Acme';
    LMetadata.Cpe := ACpe;
    LMetadata.Timestamp := '2026-01-01T00:00:00Z';
    LMetadata.ToolName := 'DX.Comply';
    LProject.ProjectName := 'TestApp';
    LProject.Version := '1.2.3';
    if AFormat = sfCycloneDxXml then
      LWriter := TCycloneDxXmlWriter.Create
    else if AFormat = sfSpdxJson then
      LWriter := TSpdxJsonWriter.Create
    else if AFormat = sfSpdx3Json then
      LWriter := TSpdx3JsonWriter.Create
    else
      LWriter := TCycloneDxJsonWriter.Create;
    Assert.IsTrue(LWriter.Write(LPath, LMetadata, LArtefacts, LProject));
    Result := TFile.ReadAllText(LPath, TEncoding.UTF8);
  finally
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
    LProject.Free;
    LArtefacts.Free;
  end;
end;

procedure TProductCpeWriterTests.CycloneDx_WritesProductCpeOnMetadataAndDeliverable;
const
  cCpe = 'cpe:2.3:a:acme:widget:1.2.3:*:*:*:*:*:*:*';
var
  LJson: string;
  LRoot, LMeta, LComponent: TJSONObject;
  LComponents: TJSONArray;
begin
  LJson := WriteProductCpe(sfCycloneDxJson, cCpe);
  LRoot := TJSONObject.ParseJSONValue(LJson) as TJSONObject;
  try
    LMeta := TJSONObject(TJSONObject(LRoot.GetValue('metadata')).GetValue('component'));
    Assert.AreEqual(cCpe, LMeta.GetValue<string>('cpe'));
    Assert.IsTrue(Pos('"copyright"', LMeta.ToString) < Pos('"cpe"', LMeta.ToString), LMeta.ToString);
    LComponents := LRoot.GetValue<TJSONArray>('components');
    Assert.IsTrue(LComponents.Count > 0);
    LComponent := LComponents.Items[0] as TJSONObject;
    Assert.AreEqual(cCpe, LComponent.GetValue<string>('cpe'));
    Assert.IsTrue(Pos('"copyright"', LComponent.ToString) < Pos('"cpe"', LComponent.ToString),
      LComponent.ToString);
  finally
    LRoot.Free;
  end;

  LJson := WriteProductCpe(sfCycloneDxXml, cCpe);
  Assert.IsTrue(Pos('<cpe>' + cCpe + '</cpe>', LJson) > 0, LJson);
  Assert.IsTrue(Pos('<copyright>', LJson) < Pos('<cpe>', LJson), LJson);
end;

procedure TProductCpeWriterTests.CycloneDx_OmitsInvalidProductCpe;
var
  LJson: string;
begin
  LJson := WriteProductCpe(sfCycloneDxJson, 'not-a-cpe');
  Assert.AreEqual(0, Pos('"cpe"', LJson), LJson);
  Assert.AreEqual(0, Pos('not-a-cpe', LJson), LJson);
end;

procedure TProductCpeWriterTests.Spdx_WritesSecurityExternalRefOnDeliverable;
const
  cCpe = 'cpe:2.3:a:acme:widget:1.2.3:*:*:*:*:*:*:*';
var
  LJson: string;
  LRoot, LPackage, LRef: TJSONObject;
  LPackages, LRefs: TJSONArray;
  I: Integer;
  LFound: Boolean;
begin
  LJson := WriteProductCpe(sfSpdxJson, cCpe);
  LRoot := TJSONObject.ParseJSONValue(LJson) as TJSONObject;
  try
    LPackages := LRoot.GetValue<TJSONArray>('packages');
    Assert.IsTrue(LPackages.Count > 0);
    LPackage := LPackages.Items[0] as TJSONObject;
    LRefs := LPackage.GetValue<TJSONArray>('externalRefs');
    Assert.IsNotNull(LRefs);
    LFound := False;
    for I := 0 to LRefs.Count - 1 do
    begin
      LRef := LRefs.Items[I] as TJSONObject;
      if LRef.GetValue<string>('referenceType') = 'cpe23Type' then
      begin
        LFound := True;
        Assert.AreEqual('SECURITY', LRef.GetValue<string>('referenceCategory'));
        Assert.AreEqual(cCpe, LRef.GetValue<string>('referenceLocator'));
      end;
    end;
    Assert.IsTrue(LFound, LPackage.ToString);
  finally
    LRoot.Free;
  end;
end;

procedure TProductCpeWriterTests.Spdx3_WritesProductCpeAsExternalIdentifier;
const
  cCpe = 'cpe:2.3:a:acme:widget:1.2.3:*:*:*:*:*:*:*';
var
  LJson: string;
  LRoot, LElement, LIdentifier: TJSONObject;
  LGraph, LIdentifiers: TJSONArray;
  I, J: Integer;
  LFound: Boolean;
begin
  LJson := WriteProductCpe(sfSpdx3Json, cCpe);
  LRoot := TJSONObject.ParseJSONValue(LJson) as TJSONObject;
  Assert.IsNotNull(LRoot, LJson);
  try
    LGraph := LRoot.GetValue<TJSONArray>('@graph');
    LFound := False;
    for I := 0 to LGraph.Count - 1 do
    begin
      if not (LGraph.Items[I] is TJSONObject) then
        Continue;
      LElement := TJSONObject(LGraph.Items[I]);
      if not (LElement.GetValue('externalIdentifier') is TJSONArray) then
        Continue;
      LIdentifiers := TJSONArray(LElement.GetValue('externalIdentifier'));
      for J := 0 to LIdentifiers.Count - 1 do
      begin
        LIdentifier := LIdentifiers.Items[J] as TJSONObject;
        if LIdentifier.GetValue<string>('externalIdentifierType', '') = 'cpe23' then
        begin
          LFound := True;
          Assert.AreEqual(cCpe, LIdentifier.GetValue<string>('identifier', ''));
          Assert.AreEqual('software_Package', LElement.GetValue<string>('type', ''));
        end;
      end;
    end;
    Assert.IsTrue(LFound, 'The built program must carry the CPE: ' + LJson);
  finally
    LRoot.Free;
  end;
end;

procedure TProductCpeWriterTests.ProductCpe_RoundTripThroughConfig;
var
  LPath, LError: string;
  LHeader: TSbomHeaderData;
  LGenerator: TDxComplyGenerator;
  LConfig: TSbomConfig;
begin
  LPath := TPath.Combine(TPath.GetTempPath, 'dxc-cpe-cfg-' + TGUID.NewGuid.ToString + '.json');
  try
    TFile.WriteAllText(LPath, '{"product":{"name":"Widget","repoUrl":"https://github.com/acme/app"}}',
      TEncoding.UTF8);
    LHeader := TSbomHeaderData.Empty;
    LHeader.Supplier := 'Acme GmbH';
    LHeader.Cpe := 'cpe:2.3:a:acme:widget:1.2.3:*:*:*:*:*:*:*';
    Assert.IsTrue(TSbomHeaderConfig.TryWrite(LPath, LHeader, LError), LError);
    LGenerator := TDxComplyGenerator.Create;
    try
      LConfig := LGenerator.LoadConfig(LPath);
      Assert.AreEqual(LHeader.Cpe, LConfig.Cpe);
      Assert.AreEqual('Widget', LConfig.ProductName);
      Assert.AreEqual('https://github.com/acme/app', LConfig.RepoUrl);
    finally
      LGenerator.Free;
    end;
  finally
    if TFile.Exists(LPath) then
      TFile.Delete(LPath);
  end;
end;

procedure TProductCpeWriterTests.Cli_CpeAndApiKeyStayOutOfTheConfigFile;
const
  cSecret = 'secret-token-value';
  cCpe = 'cpe:2.3:a:acme:widget:1.2.3:*:*:*:*:*:*:*';
var
  LOptions: TCliOptions;
  LConfig: TSbomConfig;
  LHelp: string;
begin
  LOptions := TCliOptions.Create;
  try
    Assert.IsTrue(LOptions.Parse(['--project=MyApp.dproj', '--cpe=' + cCpe,
      '--nvd-api-key=' + cSecret, '--cpe-lookup', '--cpe-dictionary']));
    Assert.AreEqual(cCpe, LOptions.Cpe);
    Assert.AreEqual(cSecret, LOptions.NvdApiKey);
    Assert.IsTrue(LOptions.CpeLookup);
    Assert.IsTrue(LOptions.CpeDictionary);
    LConfig := LOptions.ToSbomConfig;
    Assert.AreEqual(cCpe, LConfig.Cpe);
    Assert.IsTrue(scoCpe in LConfig.ExplicitOverrides);
    Assert.AreEqual(0, Pos(cSecret, LConfig.OutputPath), LConfig.OutputPath);
    Assert.AreEqual(0, Pos(cSecret, LConfig.ProductName));
    Assert.AreEqual(0, Pos(cSecret, LConfig.Supplier));
    Assert.AreEqual(0, Pos(cSecret, LConfig.RepoUrl));
  finally
    LOptions.Free;
  end;

  LOptions := TCliOptions.Create;
  try
    Assert.IsFalse(LOptions.Parse(['--nvd-api-key=', '--project=MyApp.dproj']));
    Assert.IsTrue(Pos('empty', LOptions.ParseError) > 0, LOptions.ParseError);
    Assert.AreEqual(0, Pos(cSecret, LOptions.ParseError), LOptions.ParseError);
  finally
    LOptions.Free;
  end;

  LHelp := TCliOptions.HelpText;
  Assert.IsTrue(Pos('--nvd-api-key=<key>', LHelp) > 0, LHelp);
  Assert.IsTrue(Pos('--cpe-lookup', LHelp) > 0, LHelp);
  Assert.IsTrue(Pos('--cpe-dictionary', LHelp) > 0, LHelp);
  Assert.IsTrue(Pos('NVD_API_KEY', LHelp) > 0, LHelp);
  Assert.IsTrue(Pos('Not read from .dxcomply.json.', LHelp) > 0, LHelp);
  Assert.IsTrue(Pos('is not printed', LHelp) > 0, LHelp);
  Assert.AreEqual(0, Pos(cSecret, LHelp), LHelp);
end;

initialization
  TDUnitX.RegisterTestFixture(TCpeFormatTests);
  TDUnitX.RegisterTestFixture(TCpeDictionaryTests);
  TDUnitX.RegisterTestFixture(TNvdCpeResponseTests);
  TDUnitX.RegisterTestFixture(TNvdApiKeyTests);
  TDUnitX.RegisterTestFixture(TProductCpeWriterTests);
end.
