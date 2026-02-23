# DX.Comply – User Stories

## Personas
- **Delphi Developer**: creates releases and needs SBOMs for customers.
- **CI/CD Engineer**: automates SBOM generation in the build pipeline.
- **Security/Compliance Officer**: verifies completeness and compliance evidence.
- **Product Owner**: needs reports for audits and customers.

## IDE Flow (RAD Studio)
### US-IDE-01
**As a** Delphi Developer
**I want to** right-click and run "Generate SBOM"
**so that** I get an up-to-date SBOM without leaving my development context.
**Acceptance criteria:** Menu entry present, progress visible, bom.json in project folder.

### US-IDE-02
**As a** Delphi Developer
**I want to** select the output format (CycloneDX JSON/XML, SPDX)
**so that** I can meet customer-specific requirements.
**Acceptance criteria:** Format selection in dialog, valid output files produced.

### US-IDE-03
**As a** Delphi Developer
**I want to** configure include/exclude rules
**so that** only relevant artefacts are included in the SBOM.
**Acceptance criteria:** .dxcomply.json is read and applied correctly.

## CI/CD Flow
### US-CI-01
**As a** CI/CD Engineer
**I want to** run `dxcomply` in the build pipeline
**so that** every release pipeline automatically generates an SBOM.
**Acceptance criteria:** Non-zero exit code on errors, artefact upload possible.

### US-CI-02
**As a** CI/CD Engineer
**I want** deterministic SBOMs
**so that** I can prove reproducibility.
**Acceptance criteria:** Identical inputs produce identical outputs.

## Compliance / Reporting
### US-COMP-01
**As a** Compliance Officer
**I want** a validated CycloneDX SBOM
**so that** I can provide CRA-compliant evidence.
**Acceptance criteria:** Schema validation passes successfully.

### US-COMP-02
**As a** Product Owner
**I want** SBOM diffs between releases
**so that** I can communicate changes transparently.
**Acceptance criteria:** Diff report lists added and removed components.
