/// <summary>
/// DX.Comply.Tests.Schema.Validator
/// DUnitX tests for TSbomValidator.
/// </summary>
///
/// <remarks>
/// Verifies schema validation for CycloneDX JSON, CycloneDX XML, and SPDX JSON:
/// - Valid documents pass validation
/// - Missing required fields are reported
/// - Invalid field values are caught
/// - Auto-detection of format works correctly
/// - Hash format validation works
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Schema.Validator;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  DUnitX.TestFramework,
  DX.Comply.Schema.Validator,
  DX.Comply.Engine.Intf;

type
  [TestFixture]
  TSchemaValidatorTests = class
  private
    FValidator: TSbomValidator;
    function MakeValidCycloneDxJson: string;
    function MakeValidCycloneDxXml: string;
    function MakeValidSpdxJson: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // CycloneDX JSON
    [Test]
    procedure CycloneDxJson_ValidDocument_PassesValidation;

    [Test]
    procedure CycloneDxJson_MissingBomFormat_ReportsError;

    [Test]
    procedure CycloneDxJson_WrongBomFormat_ReportsError;

    [Test]
    procedure CycloneDxJson_MissingComponents_ReportsError;

    [Test]
    procedure CycloneDxJson_InvalidHash_ReportsError;

    [Test]
    procedure CycloneDxJson_DuplicateBomRef_ReportsError;

    [Test]
    procedure CycloneDxJson_EmptyString_ReportsError;

    // CycloneDX XML
    [Test]
    procedure CycloneDxXml_ValidDocument_PassesValidation;

    [Test]
    procedure CycloneDxXml_MissingNamespace_ReportsError;

    [Test]
    procedure CycloneDxXml_MissingMetadata_ReportsError;

    [Test]
    procedure CycloneDxXml_EmptyString_ReportsError;

    [Test]
    procedure CycloneDxXml_PropertiesBeforeTools_ReportsError;

    [Test]
    procedure CycloneDxXml_PurlBeforeHashes_ReportsError;

    [Test]
    procedure CycloneDxXml_SchemaOrder_PassesValidation;

    // SPDX JSON
    [Test]
    procedure SpdxJson_ValidDocument_PassesValidation;

    [Test]
    procedure SpdxJson_WrongDataLicense_ReportsError;

    [Test]
    procedure SpdxJson_MissingCreationInfo_ReportsError;

    [Test]
    procedure SpdxJson_MissingSpdxVersion_ReportsError;

    [Test]
    procedure SpdxJson_EmptyString_ReportsError;

    // Auto-detect
    [Test]
    procedure AutoDetect_CycloneDxJson_DetectsCorrectly;

    [Test]
    procedure AutoDetect_CycloneDxXml_DetectsCorrectly;

    [Test]
    procedure AutoDetect_SpdxJson_DetectsCorrectly;

    [Test]
    procedure AutoDetect_UnknownFormat_ReportsError;
  end;

implementation

{ TSchemaValidatorTests }

procedure TSchemaValidatorTests.Setup;
begin
  FValidator := TSbomValidator.Create;
end;

procedure TSchemaValidatorTests.TearDown;
begin
  FValidator.Free;
end;

function TSchemaValidatorTests.MakeValidCycloneDxJson: string;
begin
  Result :=
    '{' +
    '  "bomFormat": "CycloneDX",' +
    '  "specVersion": "1.5",' +
    '  "serialNumber": "urn:uuid:12345678-1234-1234-1234-123456789012",' +
    '  "version": 1,' +
    '  "metadata": {' +
    '    "timestamp": "2026-02-24T10:00:00+01:00",' +
    '    "component": {' +
    '      "type": "application",' +
    '      "name": "TestApp"' +
    '    }' +
    '  },' +
    '  "components": [' +
    '    {' +
    '      "type": "library",' +
    '      "name": "TestLib.dll",' +
    '      "bom-ref": "comp-0",' +
    '      "hashes": [' +
    '        {' +
    '          "alg": "SHA-256",' +
    '          "content": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"' +
    '        }' +
    '      ]' +
    '    }' +
    '  ],' +
    '  "dependencies": [' +
    '    {' +
    '      "ref": "TestApp",' +
    '      "dependsOn": ["comp-0"]' +
    '    }' +
    '  ]' +
    '}';
end;

function TSchemaValidatorTests.MakeValidCycloneDxXml: string;
begin
  Result :=
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<bom xmlns="http://cyclonedx.org/schema/bom/1.5" version="1" ' +
    'serialNumber="urn:uuid:12345678-1234-1234-1234-123456789012">' +
    '  <metadata>' +
    '    <timestamp>2026-02-24T10:00:00+01:00</timestamp>' +
    '  </metadata>' +
    '  <components>' +
    '    <component type="application">' +
    '      <name>TestApp</name>' +
    '    </component>' +
    '  </components>' +
    '</bom>';
end;

function TSchemaValidatorTests.MakeValidSpdxJson: string;
begin
  Result :=
    '{' +
    '  "spdxVersion": "SPDX-2.3",' +
    '  "dataLicense": "CC0-1.0",' +
    '  "SPDXID": "SPDXRef-DOCUMENT",' +
    '  "name": "TestProject",' +
    '  "documentNamespace": "https://spdx.org/spdxdocs/test-12345",' +
    '  "creationInfo": {' +
    '    "created": "2026-02-24T10:00:00+01:00",' +
    '    "creators": ["Tool: DX.Comply-1.0.0"]' +
    '  },' +
    '  "packages": [' +
    '    {' +
    '      "SPDXID": "SPDXRef-Package-TestLib",' +
    '      "name": "TestLib.dll",' +
    '      "downloadLocation": "NOASSERTION"' +
    '    }' +
    '  ],' +
    '  "relationships": [' +
    '    {' +
    '      "spdxElementId": "SPDXRef-DOCUMENT",' +
    '      "relationshipType": "DESCRIBES",' +
    '      "relatedSpdxElement": "SPDXRef-Package-TestLib"' +
    '    }' +
    '  ]' +
    '}';
end;

// --- CycloneDX JSON Tests ---

procedure TSchemaValidatorTests.CycloneDxJson_ValidDocument_PassesValidation;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxJson(MakeValidCycloneDxJson);
  Assert.IsTrue(LResult.IsValid, 'Valid CycloneDX JSON should pass validation');
  Assert.AreEqual(NativeInt(0), NativeInt(Length(LResult.Errors)));
end;

procedure TSchemaValidatorTests.CycloneDxJson_MissingBomFormat_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxJson('{"specVersion": "1.5", "version": 1, "metadata": {}, "components": []}');
  Assert.IsFalse(LResult.IsValid);
  Assert.IsTrue(Length(LResult.Errors) > 0);
end;

procedure TSchemaValidatorTests.CycloneDxJson_WrongBomFormat_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxJson('{"bomFormat": "SPDX", "specVersion": "1.5", "version": 1, "metadata": {}, "components": []}');
  Assert.IsFalse(LResult.IsValid);
end;

procedure TSchemaValidatorTests.CycloneDxJson_MissingComponents_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxJson('{"bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1, "metadata": {}}');
  Assert.IsFalse(LResult.IsValid);
end;

procedure TSchemaValidatorTests.CycloneDxJson_InvalidHash_ReportsError;
var
  LResult: TValidationResult;
  LJson: string;
begin
  LJson :=
    '{' +
    '  "bomFormat": "CycloneDX",' +
    '  "specVersion": "1.5",' +
    '  "version": 1,' +
    '  "metadata": {"timestamp": "2026-01-01T00:00:00Z"},' +
    '  "components": [' +
    '    {' +
    '      "type": "library",' +
    '      "name": "test",' +
    '      "hashes": [' +
    '        {"alg": "SHA-256", "content": "tooshort"}' +
    '      ]' +
    '    }' +
    '  ]' +
    '}';
  LResult := FValidator.ValidateCycloneDxJson(LJson);
  Assert.IsFalse(LResult.IsValid, 'Invalid SHA-256 hash should fail validation');
end;

procedure TSchemaValidatorTests.CycloneDxJson_DuplicateBomRef_ReportsError;
var
  LResult: TValidationResult;
  LJson: string;
begin
  LJson :=
    '{' +
    '  "bomFormat": "CycloneDX",' +
    '  "specVersion": "1.5",' +
    '  "version": 1,' +
    '  "metadata": {"timestamp": "2026-01-01T00:00:00Z"},' +
    '  "components": [' +
    '    {"type": "library", "name": "a", "bom-ref": "dup"},' +
    '    {"type": "library", "name": "b", "bom-ref": "dup"}' +
    '  ]' +
    '}';
  LResult := FValidator.ValidateCycloneDxJson(LJson);
  Assert.IsFalse(LResult.IsValid, 'Duplicate bom-ref should fail validation');
end;

procedure TSchemaValidatorTests.CycloneDxJson_EmptyString_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxJson('');
  Assert.IsFalse(LResult.IsValid);
end;

// --- CycloneDX XML Tests ---

procedure TSchemaValidatorTests.CycloneDxXml_ValidDocument_PassesValidation;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxXml(MakeValidCycloneDxXml);
  Assert.IsTrue(LResult.IsValid, 'Valid CycloneDX XML should pass validation');
end;

procedure TSchemaValidatorTests.CycloneDxXml_MissingNamespace_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxXml('<?xml version="1.0"?><bom><metadata><timestamp>2026-01-01T00:00:00Z</timestamp></metadata><components></components></bom>');
  Assert.IsFalse(LResult.IsValid);
end;

procedure TSchemaValidatorTests.CycloneDxXml_MissingMetadata_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxXml('<?xml version="1.0"?><bom xmlns="http://cyclonedx.org/schema/bom/1.5"><components></components></bom>');
  Assert.IsFalse(LResult.IsValid);
end;

procedure TSchemaValidatorTests.CycloneDxXml_EmptyString_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxXml('');
  Assert.IsFalse(LResult.IsValid);
end;

procedure TSchemaValidatorTests.CycloneDxXml_PropertiesBeforeTools_ReportsError;
const
  cXml =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<bom xmlns="http://cyclonedx.org/schema/bom/1.5" version="1" ' +
    'serialNumber="urn:uuid:12345678-1234-1234-1234-123456789012">' +
    '<metadata>' +
    '<timestamp>2026-02-24T10:00:00+01:00</timestamp>' +
    '<properties><property name="dx:profile">cra</property></properties>' +
    '<tools><tool><name>DX.Comply</name><version>1.3.0.0</version></tool></tools>' +
    '</metadata>' +
    '<components></components>' +
    '</bom>';
var
  LResult: TValidationResult;
  LError: string;
  LFound: Boolean;
begin
  LResult := FValidator.ValidateCycloneDxXml(cXml);
  Assert.IsFalse(LResult.IsValid, 'properties before tools must fail validation');
  LFound := False;
  for LError in LResult.Errors do
    if Pos('sequence order', LError) > 0 then
      LFound := True;
  Assert.IsTrue(LFound, 'The error list must mention the sequence order');
end;

procedure TSchemaValidatorTests.CycloneDxXml_PurlBeforeHashes_ReportsError;
const
  cXml =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<bom xmlns="http://cyclonedx.org/schema/bom/1.5" version="1" ' +
    'serialNumber="urn:uuid:12345678-1234-1234-1234-123456789012">' +
    '<metadata><timestamp>2026-02-24T10:00:00+01:00</timestamp></metadata>' +
    '<components><component type="file" bom-ref="comp-0">' +
    '<name>App.exe</name><purl>file:App.exe</purl>' +
    '<hashes><hash alg="SHA-256">' +
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789' +
    '</hash></hashes></component></components>' +
    '</bom>';
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxXml(cXml);
  Assert.IsFalse(LResult.IsValid, 'purl before hashes must fail validation');
end;

procedure TSchemaValidatorTests.CycloneDxXml_SchemaOrder_PassesValidation;
const
  cXml =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<bom xmlns="http://cyclonedx.org/schema/bom/1.5" version="1" ' +
    'serialNumber="urn:uuid:12345678-1234-1234-1234-123456789012">' +
    '<metadata>' +
    '<timestamp>2026-02-24T10:00:00+01:00</timestamp>' +
    '<tools><tool><vendor>Olaf Monien</vendor><name>DX.Comply</name>' +
    '<version>1.3.0.0</version></tool></tools>' +
    '<component type="application" bom-ref="App">' +
    '<supplier><name>Acme</name></supplier>' +
    '<name>App</name><version>1.3.0.0</version>' +
    '</component>' +
    '<properties><property name="dx:profile">cra</property></properties>' +
    '</metadata>' +
    '<components><component type="application" bom-ref="comp-0">' +
    '<name>App.exe</name><version>abcdef012345</version>' +
    '<hashes><hash alg="SHA-256">' +
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789' +
    '</hash></hashes>' +
    '<purl>file:App.exe</purl>' +
    '<properties><property name="file:size">12</property></properties>' +
    '</component></components>' +
    '<dependencies><dependency ref="App">' +
    '<dependency ref="comp-0"/>' +
    '</dependency></dependencies>' +
    '</bom>';
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateCycloneDxXml(cXml);
  Assert.IsTrue(LResult.IsValid, 'A document in XSD order must pass. ' +
    string.Join('; ', LResult.Errors));
  Assert.AreEqual(0, Length(CycloneDxXmlSequenceErrors(cXml)),
    'The sequence check must accept XSD order');
end;

// --- SPDX JSON Tests ---

procedure TSchemaValidatorTests.SpdxJson_ValidDocument_PassesValidation;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateSpdxJson(MakeValidSpdxJson);
  Assert.IsTrue(LResult.IsValid, 'Valid SPDX JSON should pass validation');
  Assert.AreEqual(NativeInt(0), NativeInt(Length(LResult.Errors)));
end;

procedure TSchemaValidatorTests.SpdxJson_WrongDataLicense_ReportsError;
var
  LResult: TValidationResult;
  LJson: string;
begin
  LJson := '{"spdxVersion": "SPDX-2.3", "dataLicense": "MIT", "SPDXID": "SPDXRef-DOCUMENT", "name": "test", "documentNamespace": "https://example.com/test", "creationInfo": {"created": "2026-01-01T00:00:00Z", "creators": ["Tool: test"]}, "packages": []}';
  LResult := FValidator.ValidateSpdxJson(LJson);
  Assert.IsFalse(LResult.IsValid);
end;

procedure TSchemaValidatorTests.SpdxJson_MissingCreationInfo_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateSpdxJson('{"spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT", "name": "test", "documentNamespace": "https://example.com/test", "packages": []}');
  Assert.IsFalse(LResult.IsValid);
end;

procedure TSchemaValidatorTests.SpdxJson_MissingSpdxVersion_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateSpdxJson('{"dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT", "name": "test", "documentNamespace": "https://example.com/test", "creationInfo": {"created": "2026-01-01T00:00:00Z", "creators": ["Tool: test"]}, "packages": []}');
  Assert.IsFalse(LResult.IsValid);
end;

procedure TSchemaValidatorTests.SpdxJson_EmptyString_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateSpdxJson('');
  Assert.IsFalse(LResult.IsValid);
end;

// --- Auto-detect Tests ---

procedure TSchemaValidatorTests.AutoDetect_CycloneDxJson_DetectsCorrectly;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateAuto(MakeValidCycloneDxJson);
  Assert.IsTrue(LResult.IsValid);
end;

procedure TSchemaValidatorTests.AutoDetect_CycloneDxXml_DetectsCorrectly;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateAuto(MakeValidCycloneDxXml);
  Assert.IsTrue(LResult.IsValid);
end;

procedure TSchemaValidatorTests.AutoDetect_SpdxJson_DetectsCorrectly;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateAuto(MakeValidSpdxJson);
  Assert.IsTrue(LResult.IsValid);
end;

procedure TSchemaValidatorTests.AutoDetect_UnknownFormat_ReportsError;
var
  LResult: TValidationResult;
begin
  LResult := FValidator.ValidateAuto('{"foo": "bar"}');
  Assert.IsFalse(LResult.IsValid);
end;

end.
