/// <summary>
/// DX.Comply.Tests.SbomHeaderConfig
/// DUnitX tests for reading, merging and writing the SBOM header keys.
/// </summary>
///
/// <remarks>
/// TSbomHeaderConfig backs the IDE SBOM header dialog. The tests check that
/// the CLI reads what the dialog writes, that other keys survive a write,
/// and that the validation matches the engine.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.SbomHeaderConfig;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.SbomHeaderConfig;

type
  [TestFixture]
  TSbomHeaderConfigTests = class
  private
    function SampleHeader: TSbomHeaderData;
  public
    [Test]
    procedure TryParse_ReadsAllHeaderKeys;

    [Test]
    procedure TryParse_NoHeaderKeys_ReturnsEmpty;

    [Test]
    procedure TryParse_InvalidJson_Fails;

    [Test]
    procedure TryParse_ProductNotObject_Fails;

    [Test]
    procedure TryParse_NonStringValue_Fails;

    [Test]
    procedure TryMerge_EmptyText_CreatesKeys;

    [Test]
    procedure TryMerge_KeepsOtherKeysAndOrder;

    [Test]
    procedure TryMerge_EmptyField_RemovesKey;

    [Test]
    procedure TryMerge_AllEmpty_RemovesHeaderOnlyProduct;

    [Test]
    procedure TryMerge_AllEmpty_KeepsProductWithOtherKeys;

    [Test]
    procedure TryMerge_RootNotObject_Fails;

    [Test]
    procedure TryRead_MissingFile_ReturnsEmpty;

    [Test]
    procedure TryWrite_EngineLoadConfigReadsSameValues;

    [Test]
    procedure TryWrite_InvalidFile_LeavesFileUnchanged;

    [Test]
    procedure Validate_SbomCreator_LikeEngine;

    [Test]
    procedure Validate_SupplierUrl_MustBeHttp;

    [Test]
    procedure ApplyToConfig_EmptyFieldsKeepConfig;

    [Test]
    procedure ConfigPathForProject_UsesProjectFolder;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  DX.Comply.Engine;

function TSbomHeaderConfigTests.SampleHeader: TSbomHeaderData;
begin
  Result := TSbomHeaderData.Empty;
  Result.SbomCreator := 'sbom@example.com';
  Result.Supplier := 'Acme GmbH';
  Result.SupplierUrl := 'https://acme.example';
  Result.Licence := 'LicenseRef-Proprietary';
  Result.ProductVersion := '2.1.0';
end;

procedure TSbomHeaderConfigTests.TryParse_ReadsAllHeaderKeys;
var
  LHeader: TSbomHeaderData;
  LError: string;
begin
  Assert.IsTrue(TSbomHeaderConfig.TryParse(
    '{"sbomCreator":" https://acme.example/sbom ","product":{"name":"App",' +
    '"supplier":"Acme GmbH","supplierUrl":"https://acme.example","licence":"MIT",' +
    '"version":"3.0.1"}}', LHeader, LError), LError);
  Assert.AreEqual('https://acme.example/sbom', LHeader.SbomCreator);
  Assert.AreEqual('Acme GmbH', LHeader.Supplier);
  Assert.AreEqual('https://acme.example', LHeader.SupplierUrl);
  Assert.AreEqual('MIT', LHeader.Licence);
  Assert.AreEqual('3.0.1', LHeader.ProductVersion);
end;

procedure TSbomHeaderConfigTests.TryParse_NoHeaderKeys_ReturnsEmpty;
var
  LHeader: TSbomHeaderData;
  LError: string;
begin
  Assert.IsTrue(TSbomHeaderConfig.TryParse('{"manifest":"components.json"}', LHeader, LError));
  Assert.AreEqual('', LHeader.SbomCreator);
  Assert.AreEqual('', LHeader.Supplier);
  Assert.AreEqual('', LHeader.ProductVersion);
  Assert.IsTrue(TSbomHeaderConfig.TryParse('', LHeader, LError));
end;

procedure TSbomHeaderConfigTests.TryParse_InvalidJson_Fails;
var
  LHeader: TSbomHeaderData;
  LError: string;
begin
  Assert.IsFalse(TSbomHeaderConfig.TryParse('{"sbomCreator":', LHeader, LError));
  Assert.AreNotEqual('', LError);
end;

procedure TSbomHeaderConfigTests.TryParse_ProductNotObject_Fails;
var
  LHeader: TSbomHeaderData;
  LError: string;
begin
  Assert.IsFalse(TSbomHeaderConfig.TryParse('{"product":"Acme"}', LHeader, LError));
  Assert.IsTrue(Pos('product', LError) > 0, LError);
end;

procedure TSbomHeaderConfigTests.TryParse_NonStringValue_Fails;
var
  LHeader: TSbomHeaderData;
  LError: string;
begin
  Assert.IsFalse(TSbomHeaderConfig.TryParse('{"sbomCreator":["a@b.example"]}', LHeader, LError));
  Assert.IsTrue(Pos('sbomCreator', LError) > 0, LError);
end;

procedure TSbomHeaderConfigTests.TryMerge_EmptyText_CreatesKeys;
var
  LMerged: string;
  LError: string;
  LHeader: TSbomHeaderData;
begin
  Assert.IsTrue(TSbomHeaderConfig.TryMerge('', SampleHeader, LMerged, LError), LError);
  Assert.IsTrue(TSbomHeaderConfig.TryParse(LMerged, LHeader, LError), LError);
  Assert.AreEqual('sbom@example.com', LHeader.SbomCreator);
  Assert.AreEqual('Acme GmbH', LHeader.Supplier);
  Assert.AreEqual('https://acme.example', LHeader.SupplierUrl);
  Assert.AreEqual('LicenseRef-Proprietary', LHeader.Licence);
  Assert.AreEqual('2.1.0', LHeader.ProductVersion);
end;

procedure TSbomHeaderConfigTests.TryMerge_KeepsOtherKeysAndOrder;
var
  LMerged: string;
  LError: string;
begin
  var LExisting :=
    '{"manifest":"components.json","sbomCreator":"old@example.com",' +
    '"product":{"name":"App","supplier":"Old"},' +
    '"report":{"enabled":true,"format":"html"},"scanDirs":["bin"]}';
  Assert.IsTrue(TSbomHeaderConfig.TryMerge(LExisting, SampleHeader, LMerged, LError), LError);

  var LRoot := TJSONObject.ParseJSONValue(LMerged) as TJSONObject;
  try
    Assert.AreEqual(5, LRoot.Count);
    Assert.AreEqual('manifest', LRoot.Pairs[0].JsonString.Value);
    Assert.AreEqual('sbomCreator', LRoot.Pairs[1].JsonString.Value);
    Assert.AreEqual('product', LRoot.Pairs[2].JsonString.Value);
    Assert.AreEqual('report', LRoot.Pairs[3].JsonString.Value);
    Assert.AreEqual('scanDirs', LRoot.Pairs[4].JsonString.Value);
    Assert.AreEqual('components.json', LRoot.GetValue<string>('manifest'));
    Assert.AreEqual('sbom@example.com', LRoot.GetValue<string>('sbomCreator'));
    Assert.AreEqual('html', LRoot.GetValue<string>('report.format'));
    Assert.IsTrue(LRoot.GetValue<Boolean>('report.enabled'));
    Assert.AreEqual('bin', (LRoot.GetValue('scanDirs') as TJSONArray).Items[0].Value);

    var LProduct := LRoot.GetValue('product') as TJSONObject;
    Assert.AreEqual('name', LProduct.Pairs[0].JsonString.Value);
    Assert.AreEqual('App', LProduct.GetValue<string>('name'));
    Assert.AreEqual('supplier', LProduct.Pairs[1].JsonString.Value);
    Assert.AreEqual('Acme GmbH', LProduct.GetValue<string>('supplier'));
  finally
    LRoot.Free;
  end;
end;

procedure TSbomHeaderConfigTests.TryMerge_EmptyField_RemovesKey;
var
  LMerged: string;
  LError: string;
begin
  var LHeader := SampleHeader;
  LHeader.SbomCreator := '  ';
  LHeader.ProductVersion := '';
  Assert.IsTrue(TSbomHeaderConfig.TryMerge(
    '{"sbomCreator":"old@example.com","product":{"version":"1.2.3"}}',
    LHeader, LMerged, LError), LError);
  var LRoot := TJSONObject.ParseJSONValue(LMerged) as TJSONObject;
  try
    Assert.IsNull(LRoot.GetValue('sbomCreator'));
    Assert.IsNull((LRoot.GetValue('product') as TJSONObject).GetValue('version'));
    Assert.AreEqual('Acme GmbH', LRoot.GetValue<string>('product.supplier'));
  finally
    LRoot.Free;
  end;
end;

procedure TSbomHeaderConfigTests.TryMerge_AllEmpty_RemovesHeaderOnlyProduct;
var
  LMerged: string;
  LError: string;
begin
  Assert.IsTrue(TSbomHeaderConfig.TryMerge(
    '{"manifest":"m.json","product":{"supplier":"Acme","licence":"MIT"}}',
    TSbomHeaderData.Empty, LMerged, LError), LError);
  var LRoot := TJSONObject.ParseJSONValue(LMerged) as TJSONObject;
  try
    Assert.AreEqual(1, LRoot.Count);
    Assert.AreEqual('m.json', LRoot.GetValue<string>('manifest'));
  finally
    LRoot.Free;
  end;
end;

procedure TSbomHeaderConfigTests.TryMerge_AllEmpty_KeepsProductWithOtherKeys;
var
  LMerged: string;
  LError: string;
begin
  Assert.IsTrue(TSbomHeaderConfig.TryMerge(
    '{"product":{"name":"App","supplier":"Acme","repoUrl":"https://github.com/acme/app"}}',
    TSbomHeaderData.Empty, LMerged, LError), LError);
  var LRoot := TJSONObject.ParseJSONValue(LMerged) as TJSONObject;
  try
    var LProduct := LRoot.GetValue('product') as TJSONObject;
    Assert.AreEqual(2, LProduct.Count);
    Assert.AreEqual('App', LProduct.GetValue<string>('name'));
    Assert.AreEqual('https://github.com/acme/app', LProduct.GetValue<string>('repoUrl'));
  finally
    LRoot.Free;
  end;
end;

procedure TSbomHeaderConfigTests.TryMerge_RootNotObject_Fails;
var
  LMerged: string;
  LError: string;
begin
  Assert.IsFalse(TSbomHeaderConfig.TryMerge('[1,2]', SampleHeader, LMerged, LError));
  Assert.AreEqual('', LMerged);
  Assert.IsFalse(TSbomHeaderConfig.TryMerge('{"product":42}', SampleHeader, LMerged, LError));
end;

procedure TSbomHeaderConfigTests.TryRead_MissingFile_ReturnsEmpty;
var
  LHeader: TSbomHeaderData;
  LError: string;
begin
  var LPath := TPath.Combine(TPath.GetTempPath, 'dxc-missing-' + TGUID.NewGuid.ToString + '.json');
  Assert.IsTrue(TSbomHeaderConfig.TryRead(LPath, LHeader, LError), LError);
  Assert.AreEqual('', LHeader.SbomCreator);
end;

procedure TSbomHeaderConfigTests.TryWrite_EngineLoadConfigReadsSameValues;
var
  LError: string;
  LHeader: TSbomHeaderData;
begin
  var LPath := TPath.GetTempFileName;
  try
    TFile.WriteAllText(LPath, '{"manifest":"components.json","product":{"name":"App"}}',
      TEncoding.UTF8);
    Assert.IsTrue(TSbomHeaderConfig.TryWrite(LPath, SampleHeader, LError), LError);

    var LGenerator := TDxComplyGenerator.Create;
    try
      var LConfig := LGenerator.LoadConfig(LPath);
      Assert.AreEqual('sbom@example.com', LConfig.SbomCreator);
      Assert.AreEqual('Acme GmbH', LConfig.Supplier);
      Assert.AreEqual('https://acme.example', LConfig.SupplierUrl);
      Assert.AreEqual('LicenseRef-Proprietary', LConfig.Licence);
      Assert.AreEqual('2.1.0', LConfig.ProductVersion);
      Assert.AreEqual('App', LConfig.ProductName);
      Assert.AreEqual('components.json', LConfig.ManifestFile);
    finally
      LGenerator.Free;
    end;

    Assert.IsTrue(TSbomHeaderConfig.TryRead(LPath, LHeader, LError), LError);
    Assert.AreEqual('sbom@example.com', LHeader.SbomCreator);
  finally
    TFile.Delete(LPath);
  end;
end;

procedure TSbomHeaderConfigTests.TryWrite_InvalidFile_LeavesFileUnchanged;
var
  LError: string;
begin
  var LPath := TPath.GetTempFileName;
  try
    var LBroken := '{"manifest": "components.json",';
    TFile.WriteAllText(LPath, LBroken, TEncoding.UTF8);
    Assert.IsFalse(TSbomHeaderConfig.TryWrite(LPath, SampleHeader, LError));
    Assert.AreNotEqual('', LError);
    Assert.AreEqual(LBroken, TFile.ReadAllText(LPath, TEncoding.UTF8));
  finally
    TFile.Delete(LPath);
  end;
end;

procedure TSbomHeaderConfigTests.Validate_SbomCreator_LikeEngine;
begin
  var LHeader := TSbomHeaderData.Empty;
  Assert.AreEqual(0, Integer(Length(TSbomHeaderConfig.Validate(LHeader))));
  LHeader.SbomCreator := 'sbom@example.com';
  Assert.AreEqual(0, Integer(Length(TSbomHeaderConfig.Validate(LHeader))));
  LHeader.SbomCreator := 'https://example.com/sbom';
  Assert.AreEqual(0, Integer(Length(TSbomHeaderConfig.Validate(LHeader))));
  LHeader.SbomCreator := 'Acme GmbH';
  var LErrors := TSbomHeaderConfig.Validate(LHeader);
  Assert.AreEqual(1, Integer(Length(LErrors)));
  Assert.IsTrue(Pos('SBOM creator', LErrors[0]) > 0, LErrors[0]);
end;

procedure TSbomHeaderConfigTests.Validate_SupplierUrl_MustBeHttp;
begin
  var LHeader := TSbomHeaderData.Empty;
  LHeader.SupplierUrl := 'acme.example';
  Assert.AreEqual(1, Integer(Length(TSbomHeaderConfig.Validate(LHeader))));
  LHeader.SupplierUrl := 'https://acme.example';
  Assert.AreEqual(0, Integer(Length(TSbomHeaderConfig.Validate(LHeader))));
end;

procedure TSbomHeaderConfigTests.ApplyToConfig_EmptyFieldsKeepConfig;
begin
  var LConfig := TSbomConfig.Default;
  LConfig.Supplier := 'From version info';
  LConfig.ProductVersion := '';
  var LHeader := TSbomHeaderData.Empty;
  LHeader.SbomCreator := ' sbom@example.com ';
  LHeader.Licence := 'MIT';
  TSbomHeaderConfig.ApplyToConfig(LHeader, LConfig);
  Assert.AreEqual('sbom@example.com', LConfig.SbomCreator);
  Assert.AreEqual('MIT', LConfig.Licence);
  Assert.AreEqual('From version info', LConfig.Supplier);
  Assert.AreEqual('', LConfig.ProductVersion);
  Assert.AreEqual('', LConfig.SupplierUrl);
end;

procedure TSbomHeaderConfigTests.ConfigPathForProject_UsesProjectFolder;
begin
  Assert.AreEqual(TPath.Combine('C:\Work\App', '.dxcomply.json'),
    TSbomHeaderConfig.ConfigPathForProject('C:\Work\App\App.dproj'));
end;

initialization
  TDUnitX.RegisterTestFixture(TSbomHeaderConfigTests);

end.
