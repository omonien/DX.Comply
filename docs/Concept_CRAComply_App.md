# Konzept: CRAComply — CRA-Compliance-Begleiter

## Vision

**CRAComply** ist eine eigenstandige FMX-Anwendung innerhalb des DX.Comply-Projekts, die Software-Unternehmen als interaktiver Begleiter durch den gesamten EU Cyber Resilience Act (CRA) Compliance-Prozess fuehrt. Die SBOM-Generierung (DX.Comply Engine) ist dabei ein integrierter Baustein — der Wizard deckt den gesamten Compliance-Lebenszyklus ab.

> **SBOM = ein Schritt von vielen.** CRAComply verwandelt abstrakte EU-Vorgaben in konkrete, erfassbare Arbeitsschritte und dokumentiert den Fortschritt nachvollziehbar.

---

## Zielgruppe

- Delphi-Entwickler und Software-Unternehmen, die unter den CRA fallen
- Compliance-Beauftragte ohne tiefe technische Kenntnisse
- Auditoren, die den Compliance-Status pruefen muessen

---

## Architektur-Ueberblick

```
CRAComply (FMX Standalone App)
    |
    +-- Produkt-Klassifizierung (Wizard/Self-Assessment)
    |
    +-- SBOM-Generierung (DX.Comply Engine Integration)
    |
    +-- Dokumentation & Evidence Collector
    |       +-- Technisches Dossier
    |       +-- Nutzeranleitung / Sicherheitsleitfaden
    |       +-- Support-Zusagen & End-of-Life
    |
    +-- Schwachstellen-Management
    |       +-- CVE-Abgleich gegen SBOM-Komponenten
    |       +-- ENISA-Meldewesen-Assistent (24h-Meldepflicht)
    |       +-- Update-Prozess-Dokumentation
    |
    +-- Kennzeichnung & Konformitaet
    |       +-- EU-Konformitaetserklaerung (Template)
    |       +-- CE-Kennzeichen-Leitfaden
    |
    +-- Report Generator
            +-- Compliance-Report (PDF/HTML)
            +-- Technisches Dossier (strukturiertes Archiv)
            +-- Audit-Trail / Aenderungshistorie
```

---

## Module im Detail

### 1. Produkt-Klassifizierung (Self-Assessment Wizard)

Ein gefuehrter Fragebogen, der die CRA-Klasse des Produkts bestimmt:

**Beispiel-Fragen:**
- Wird die Software als eigenstaendiges Produkt auf dem EU-Markt bereitgestellt?
- Enthaelt die Software kryptografische Funktionen?
- Wird die Software als Browser, Betriebssystem oder Netzwerk-Infrastruktur eingesetzt?
- Verarbeitet die Software personenbezogene oder sicherheitskritische Daten?

**Ergebnis:**
- Dokumentierte Einstufung: **Standard** (Selbstbewertung) vs. **Wichtig Klasse I/II** (Notified Body) vs. **Kritisch**
- Empfehlung zum Konformitaetsweg
- Exportierbar als Teil des Technischen Dossiers

**Status-Indikator:** Die Klassifizierung bestimmt den Umfang aller weiteren Schritte.

---

### 2. SBOM-Generierung (DX.Comply Engine)

Integration der bestehenden DX.Comply Engine:

- **Deep-Evidence-Analyse** auf Basis der Compiler-generierten MAP-Datei
- **Unit-Resolution** mit SHA-256 Hashes und Origin-Klassifizierung
- **Runtime-Package-Erkennung** (BPL-Abhaengigkeiten aus .dproj)
- **Externer DLL-Scan** (Source-Scan nach `external` und `LoadLibrary`)
- **CycloneDX 1.5 / SPDX 2.3** Ausgabeformate

**Bereits implementiert in DX.Comply v1.2.0.** CRAComply bindet die Engine als Package ein.

---

### 3. Evidence Collector (Daten-Tresor)

Ein System zur Erfassung der fuer das "Technische Dossier" notwendigen Nachweise:

| Nachweis-Kategorie | Erfassung | Beispiel |
|---|---|---|
| **Design-Entscheidungen** | Textfelder / Markdown-Editor | Beschreibung der Sicherheitsarchitektur, Threat Model |
| **Security-by-Design** | Checkliste + Freitext | Eingabevalidierung, Verschluesselung, Least Privilege |
| **Test-Nachweise** | Datei-Upload / Verlinkung | Unit-Test-Reports, Pentest-Ergebnisse, Code-Analyse |
| **Support-Zusagen** | Datumsfelder + Validierung | End-of-Life Datum (automatische Pruefung der 5-Jahre-Regel) |
| **Aenderungshistorie** | Automatisch via Git-Integration | Wann wurde was geaendert, wer hat es freigegeben |

**Speicherung:** Alle Daten lokal im Projektverzeichnis als JSON (`.cracomply/`), Git-freundlich und versionierbar.

---

### 4. Schwachstellen-Management (Vulnerability Dashboard)

Die SBOM wird aktiv genutzt:

- **CVE-Check:** Automatischer Abgleich der SBOM-Komponenten mit Online-Datenbanken (NVD, OSV)
- **Dashboard:** Uebersicht ueber bekannte Schwachstellen in verwendeten Komponenten
- **Meldewesen-Assistent:** Vorbereitete Formulare fuer die 24h-Meldung an die ENISA (ab Sept. 2026)
- **Update-Prozess:** Dokumentation des Prozesses zur zeitnahen Verteilung von Sicherheitsupdates

---

### 5. Kennzeichnung & Konformitaet

- **EU-Konformitaetserklaerung:** Vorgefertigtes Template, automatisch befuellt mit Produktdaten und Klassifizierung
- **CE-Kennzeichen-Leitfaden:** Anleitung zur korrekten Anbringung
- **Nutzer-Sicherheitsleitfaden:** Template fuer die Endkunden-Dokumentation (sichere Installation, Konfiguration, Support-Zeitraum)

---

### 6. Report Generator

Per Knopfdruck werden alle erfassten Daten in formelle Dokumente exportiert:

| Dokument | Format | Inhalt |
|---|---|---|
| **Compliance-Report** | PDF / HTML | Gesamtuebersicht: Klassifizierung, SBOM-Zusammenfassung, Evidence-Status, Schwachstellen |
| **EU-Konformitaetserklaerung** | PDF | Formelles Dokument zur CRA-Einhaltung |
| **Technisches Dossier** | Strukturiertes Archiv (ZIP) | Alle Nachweise, SBOM, Test-Reports, Design-Docs |
| **Nutzer-Sicherheitsleitfaden** | PDF / Markdown | Endkunden-Information |
| **Audit-Trail** | JSON / CSV | Chronologische Aenderungshistorie |

---

## CRA-Compliance-Checkliste (integriert)

CRAComply fuehrt den User durch diese Schritte und trackt den Fortschritt:

### Produkt-Klassifizierung
- [ ] Klassifizierung pruefen: Standard / Wichtig (Klasse I/II) / Kritisch
- [ ] Konformitaetsweg festlegen: Selbstbewertung vs. Notified Body

### Dokumentation & SBOM
- [ ] SBOM erzeugen (DX.Comply Engine)
- [ ] Technisches Dossier: Design, Entwicklung, Testprozess (Security-by-Design)
- [ ] Nutzeranleitung: Sichere Installation, Support-Zeitraum (mind. 5 Jahre)
- [ ] EU-Konformitaetserklaerung erstellen

### Schwachstellen-Management
- [ ] Monitoring: SBOM gegen CVE-Datenbanken abgleichen
- [ ] Meldepflicht: Prozess fuer 24h-Meldung an ENISA (ab Sept. 2026)
- [ ] Update-Prozess: Sicherheitsupdates zeitnah an Kunden verteilen

### Kennzeichnung
- [ ] CE-Kennzeichen auf Produkt oder Dokumentation

---

## Technische Umsetzung

### Plattform
- **FMX Standalone-Anwendung** (Windows, potentiell macOS)
- Eigenes Projekt innerhalb des DX.Comply Repositories
- DX.Comply Engine als Package-Referenz (kein Code-Duplikat)

### Projektstruktur (geplant)
```
<projekt>/
  src/
    CRAComply/
      CRAComply.dproj            # FMX Standalone App
      CRAComply.Main.Form.pas    # Hauptformular mit Navigation
      CRAComply.Classification/   # Self-Assessment Wizard
      CRAComply.Evidence/         # Evidence Collector
      CRAComply.Vulnerability/    # CVE-Check, Dashboard
      CRAComply.Reports/          # Report-Generierung
      CRAComply.Project/          # Projektdaten, Persistence (.cracomply/)
```

### Datenhaltung
- **Lokal im Projektverzeichnis:** `.cracomply/` Ordner mit JSON-Dateien
- **Git-freundlich:** Keine Binaerdaten, alles Klartext und diffbar
- **Portabel:** Kein Server, keine Cloud-Abhaengigkeit, keine Registrierung

### Engine-Integration
- DX.Comply Engine Package wird referenziert (nicht kopiert)
- `TDxComplyGenerator` wird direkt aus CRAComply aufgerufen
- SBOM-Generierung als ein Schritt im Gesamtprozess

### Moegliche KI-Assistenz
- Analyse des Quellcodes zur Unterstuetzung beim Ausfuellen technischer Beschreibungen
- Automatische Vorschlaege fuer Security-by-Design-Massnahmen basierend auf dem Projekt
- Optional, nicht Kern-Feature

---

## Priorisierung / Phasen

| Phase | Umfang | Abhaengigkeiten |
|---|---|---|
| **Phase 1** | Grundgeruest: FMX App, Navigation, Projekt-Persistence, Klassifizierungs-Wizard | Keine |
| **Phase 2** | SBOM-Integration: DX.Comply Engine einbinden, SBOM als Schritt im Wizard | DX.Comply Engine Package |
| **Phase 3** | Evidence Collector: Textfelder, Datei-Uploads, Support-Zeitraum-Validierung | Phase 1 |
| **Phase 4** | Report Generator: PDF/HTML Export, Konformitaetserklaerung-Template | Phase 1-3 |
| **Phase 5** | Vulnerability Dashboard: CVE-Check, ENISA-Meldewesen | Phase 2 (SBOM), Online-API |

---

*Status: Konzeptphase. Dieses Dokument dient als Grundlage fuer die Implementierungsplanung.*
