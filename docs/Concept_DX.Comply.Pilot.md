# Konzept: DX.Comply Pilot, Begleiter fuer die technische Dokumentation

## Was DX.Comply heute schreibt

DX.Comply schreibt eine Komponentenliste (SBOM) und Build-Nachweise. Es listet die Units, Packages und DLL-Namen, die es aus dem Build sehen kann, und einen Hash, wo es die Datei oeffnen konnte. Diese Liste ist ein Anfang fuer den SBOM-Teil der technischen Dokumentation nach dem EU Cyber Resilience Act (Anhang I Teil II, Anhang VII). Sie macht ein Produkt nicht konform und ersetzt die uebrige technische Dokumentation nicht.

Lieferant, Version und Lizenz fuer Komponenten Dritter schreibt DX.Comply, wenn ein Komponenten-Manifest (components.json) sie enthaelt. Der Rest der technischen Dokumentation fehlt weiterhin: Verfahren zur Behandlung von Schwachstellen, Offenlegungspolitik, Auslieferung von Updates und Risikobewertung. Schwachstellenmanagement und Meldewesen liegen ausserhalb dieses Werkzeugs.

Die Pruefung im Werkzeug ist eine strukturelle Pruefung. Das CycloneDX-JSON-Beispiel in diesem Repository besteht die offizielle CycloneDX-1.5-JSON-Schema-Pruefung mit check-jsonschema. SPDX und CycloneDX-XML werden im Werkzeug nicht gegen offizielle Schemas geprueft.

Die BSI TR-03183-2 Version 2.1.0 verlangt CycloneDX 1.6 oder neuer und SPDX 3.0.1 oder neuer. DX.Comply bleibt bei CycloneDX 1.5 und SPDX 2.3. Es schreibt SHA-512 neben SHA-256, den Dateinamen und die Eigenschaften executable, archive und structured, wenn die Datei geoeffnet werden konnte. Den Ersteller der SBOM schreibt es nur, wenn eine E-Mail oder eine http(s)-URL angegeben wird. Lizenzen und Herstellerangaben kommen aus dem Komponenten-Manifest, wenn eines angegeben wird. Rekursive Abhaengigkeiten schreibt es nicht. Das ist keine Zertifizierung und keine volle Abdeckung der Richtlinie.

## Vision

**DX.Comply Pilot** ist ein Konzept fuer eine spaetere eigenstaendige FMX-Anwendung. Sie soll weitere Teile der technischen Dokumentation begleiten. Die SBOM-Generierung der DX.Comply Engine waere darin ein Baustein. Dieses Dokument beschreibt keinen heutigen Funktionsumfang.

> **Die SBOM ist ein Schritt von vielen.** Das Konzept soll aus den weiteren EU-Vorgaben konkrete Arbeitsschritte machen und den Fortschritt festhalten.

---

## Zielgruppe

- Delphi-Entwickler und Software-Unternehmen, die unter den CRA fallen
- Compliance-Beauftragte ohne tiefe technische Kenntnisse
- Auditoren, die den Compliance-Status pruefen muessen

---

## Architektur-Ueberblick

```
DX.Comply Pilot (FMX Standalone App)
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

**Bereits implementiert in DX.Comply v1.2.0.** DX.Comply Pilot bindet die Engine als Package ein.

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

**Speicherung:** Alle Daten lokal im Projektverzeichnis als JSON (`.dxcomply-pilot/`), Git-freundlich und versionierbar.

---

### 4. Schwachstellen-Management (Vulnerability Dashboard)

Die SBOM wird aktiv genutzt:

- **CVE-Check:** Automatischer Abgleich der SBOM-Komponenten mit Online-Datenbanken (NVD, OSV)
- **Dashboard:** Uebersicht ueber bekannte Schwachstellen in verwendeten Komponenten
- **Meldewesen-Assistent:** Vorbereitete Formulare fuer die 24h-Meldung an die ENISA (ab Sept. 2026)
- **Update-Prozess:** Dokumentation des Prozesses zur zeitnahen Verteilung von Sicherheitsupdates

---

### 5. Kennzeichnung & Konformitaet

- **EU-Konformitaetserklaerung:** Geplantes Formular, vorbefuellt mit Produktdaten und Klassifizierung. Ein Entwurf, keine Zertifizierung.
- **CE-Kennzeichen-Leitfaden:** Anleitung zur korrekten Anbringung
- **Nutzer-Sicherheitsleitfaden:** Template fuer die Endkunden-Dokumentation (sichere Installation, Konfiguration, Support-Zeitraum)

---

### 6. Report Generator

Geplant ist ein Export der erfassten Daten in diese Dokumente. Das ist nicht Teil des aktuellen Werkzeugs:

| Dokument | Format | Inhalt |
|---|---|---|
| **Compliance-Report** | PDF / HTML | Gesamtuebersicht: Klassifizierung, SBOM-Zusammenfassung, Evidence-Status, Schwachstellen |
| **EU-Konformitaetserklaerung** | PDF | Entwurf eines Formulars, kein Nachweis einer Zertifizierung |
| **Technisches Dossier** | Strukturiertes Archiv (ZIP) | Alle Nachweise, SBOM, Test-Reports, Design-Docs |
| **Nutzer-Sicherheitsleitfaden** | PDF / Markdown | Endkunden-Information |
| **Audit-Trail** | JSON / CSV | Chronologische Aenderungshistorie |

---

## Geplante Checkliste

DX.Comply Pilot soll durch diese Schritte fuehren. Die Liste ist Konzept. Das aktuelle Werkzeug erzeugt sie nicht und bescheinigt keine CRA-Konformitaet:

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
    DX.Comply Pilot/
      DX.Comply Pilot.dproj            # FMX Standalone App
      DX.Comply Pilot.Main.Form.pas    # Hauptformular mit Navigation
      DX.Comply Pilot.Classification/   # Self-Assessment Wizard
      DX.Comply Pilot.Evidence/         # Evidence Collector
      DX.Comply Pilot.Vulnerability/    # CVE-Check, Dashboard
      DX.Comply Pilot.Reports/          # Report-Generierung
      DX.Comply Pilot.Project/          # Projektdaten, Persistence (.dxcomply-pilot/)
```

### Datenhaltung
- **Lokal im Projektverzeichnis:** `.dxcomply-pilot/` Ordner mit JSON-Dateien
- **Git-freundlich:** Keine Binaerdaten, alles Klartext und diffbar
- **Portabel:** Kein Server, keine Cloud-Abhaengigkeit, keine Registrierung

### Engine-Integration
- DX.Comply Engine Package wird referenziert (nicht kopiert)
- `TDxComplyGenerator` wird direkt aus DX.Comply Pilot aufgerufen
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
