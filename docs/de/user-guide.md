# 👤 ERNI-KI Benutzerhandbuch

> **Dokumentversion:** 3.0 **Aktualisierungsdatum:** 2025-07-15 **Zielgruppe:**
> Endbenutzer

## 🎯 Einführung

ERNI-KI ist eine moderne AI-Plattform, die eine benutzerfreundliche
Weboberfläche für die Arbeit mit Sprachmodellen bietet. Das System unterstützt
AI-Chat, Internetsuche, Dokumentenverarbeitung und Sprachinteraktion.

## 🚀 Erste Schritte

### Systemzugang

1. Öffnen Sie den Browser und navigieren Sie zur Adresse Ihres ERNI-KI Systems
2. Erstellen Sie beim ersten Zugang ein Administrator-Konto
3. Melden Sie sich mit den erstellten Anmeldedaten an

### System-Interface

Das Hauptinterface besteht aus:

- **Seitenleiste** - Chat-Liste und Einstellungen
- **Zentraler Bereich** - Chat-Fenster mit AI
- **Eingabefeld** - Feld für Nachrichten und Aktionsschaltflächen
- **Obere Leiste** - Modellauswahl und zusätzliche Einstellungen

## 💬 Arbeiten mit Chats

### Neuen Chat erstellen

1. Klicken Sie auf **"+ Neuer Chat"** in der Seitenleiste
2. Wählen Sie ein Sprachmodell aus der Dropdown-Liste
3. Geben Sie Ihre erste Frage oder Anfrage ein
4. Drücken Sie **Enter** oder die Senden-Schaltfläche

### Chat-Verwaltung

- **Umbenennen**: Klicken Sie auf den Chat-Namen → "Umbenennen"
- **Löschen**: Klicken Sie auf das Papierkorb-Symbol neben dem Chat
- **Archivieren**: Verschieben Sie alte Chats ins Archiv
- **Suchen**: Verwenden Sie die Suche zum schnellen Finden von Chats

### Nachrichtentypen

- **Textnachrichten** - normale Kommunikation mit AI
- **System-Prompts** - spezielle Anweisungen für AI
- **Dateien und Dokumente** - Upload zur Analyse
- **Bilder** - Analyse und Beschreibung von Bildern

## 🔍 RAG-Suche mit SearXNG

### Was ist RAG-Suche

RAG (Retrieval-Augmented Generation) ist eine Technologie, die es der AI
ermöglicht, aktuelle Informationen aus dem Internet für präzisere Antworten zu
erhalten.

### Web-Suche verwenden

1. **Automatische Suche**: AI sucht automatisch nach Informationen bei Bedarf
2. **Manuelle Suche**: Verwenden Sie den Befehl `/search Ihre Anfrage`
3. **Sucheinstellungen**: In den Einstellungen können Sie die Auto-Suche
   ein-/ausschalten

### Beispiele für Suchanfragen

```
Erzähle mir über die neuesten Nachrichten im AI-Bereich
/search Dollarkurs heute
Wie ist das Wetter in Berlin?
Finde Informationen über neue Technologien 2024
```

### Informationsquellen

SearXNG sucht Informationen in:

- Google, Bing, DuckDuckGo
- Wikipedia
- Nachrichtenseiten
- Wissenschaftliche Publikationen
- Spezialisierte Ressourcen

## 📄 Arbeiten mit Dokumenten

### Unterstützte Formate

- **PDF** - Dokumente, Bücher, Artikel
- **DOCX/DOC** - Microsoft Word Dokumente
- **PPTX/PPT** - PowerPoint Präsentationen
- **TXT** - Textdateien
- **MD** - Markdown-Dateien
- **HTML** - Webseiten

### Dokumente hochladen

1. Klicken Sie auf die **"📎"** (Büroklammer) Schaltfläche im Eingabefeld
2. Wählen Sie eine Datei vom Computer (bis zu 100MB)
3. Warten Sie auf die Dokumentenverarbeitung
4. Stellen Sie Fragen zum Dokumentinhalt

### Dokumentenanalyse

Nach dem Upload können Sie:

- **Fragen stellen** zum Inhalt
- **Zusammenfassung erhalten** des Dokuments
- **Schlüsselinformationen extrahieren**
- **Inhalte übersetzen** in andere Sprachen
- **Präsentationen erstellen** basierend auf dem Dokument

### Beispiele für Dokumentenarbeit

```
Erstelle eine Zusammenfassung dieses Dokuments
Finde Preisinformationen im Dokument
Übersetze diesen Text ins Englische
Erstelle einen Präsentationsplan aus diesem Material
Hebe die Hauptthesen aus dem Dokument hervor
```

## 🎤 Sprachfunktionen

### Spracheingabe

1. Klicken Sie auf die **🎤** Schaltfläche im Eingabefeld
2. Erlauben Sie Mikrofon-Zugriff im Browser
3. Sprechen Sie klar und deutlich
4. Klicken Sie auf die Stopp-Schaltfläche
5. Der Text erscheint automatisch im Eingabefeld

### Sprachausgabe (TTS)

1. Aktivieren Sie **"Sprachantworten"** in den Einstellungen
2. Wählen Sie bevorzugte Stimme und Sprache
3. AI wird ihre Antworten vorlesen
4. Verwenden Sie Play/Pause-Schaltflächen

### Unterstützte Sprachen

- **Deutsch** - männliche und weibliche Stimmen
- **Englisch** - verschiedene Akzente
- **Französisch, Spanisch, Italienisch**
- **Chinesisch, Japanisch, Koreanisch**

## ⚙️ Einstellungen und Personalisierung

### Modell-Einstellungen

- **Temperatur** (0.1-2.0) - Kreativität der Antworten
- **Top-p** (0.1-1.0) - Vielfalt der Antworten
- **Maximale Länge** - Token-Limit für Antworten
- **System-Prompt** - Grundanweisungen für AI

### Interface-Einstellungen

- **Theme** - helles/dunkles Design
- **Interface-Sprache** - Deutsch/Englisch
- **Schriftgröße** - Lesbarkeits-Anpassung
- **Auto-Speichern** - Häufigkeit der Chat-Speicherung

### Such-Einstellungen

- **Auto-Suche** - RAG-Suche ein-/ausschalten
- **Anzahl Ergebnisse** - wie viele Quellen verwenden
- **Such-Sprachen** - bevorzugte Ergebnis-Sprachen
- **Sichere Suche** - Inhaltsfilterung

## 🔧 Erweiterte Funktionen

### System-Prompts

Erstellen Sie spezialisierte Rollen für AI:

```
Du bist ein erfahrener Python-Programmierer. Hilf mit Code und erkläre komplexe Konzepte in einfacher Sprache.

Du bist ein Übersetzer. Übersetze Texte maximal genau unter Beibehaltung von Stil und Kontext.

Du bist ein Datenanalyst. Analysiere bereitgestellte Informationen und ziehe Schlüsse.
```

### Anfrage-Vorlagen

Speichern Sie häufig verwendete Anfragen:

- Dokumentenanalyse
- Präsentationserstellung
- Textübersetzung
- Code-Erstellung
- Aufgabenplanung

### Datenexport

- **Chat-Export** - Speichern als PDF/TXT
- **Einstellungs-Export** - Backup der Konfiguration
- **Anfrage-Historie** - Nutzungsanalyse

## 🛡️ Sicherheit und Datenschutz

### Datenschutz

- Alle Daten werden lokal auf Ihrem Server gespeichert
- Verbindungsverschlüsselung über HTTPS
- Regelmäßige Backups
- Zugriffskontrolle über JWT-Token

### Sicherheitsempfehlungen

- Verwenden Sie starke Passwörter
- Aktualisieren Sie das System regelmäßig
- Geben Sie keine vertraulichen Informationen weiter
- Richten Sie Backups ein

## ❓ Häufig gestellte Fragen

### **F: Wie wähle ich das passende Modell?**

A: Für schnelle Antworten verwenden Sie 3B-7B Parameter-Modelle. Für komplexe
Aufgaben - 13B+ Parameter.

### **F: Warum kann AI keine aktuellen Informationen finden?**

A: Stellen Sie sicher, dass RAG-Suche in den Einstellungen aktiviert ist.
Verwenden Sie `/search` für erzwungene Suche.

### **F: Wie kann ich die Antwortgeschwindigkeit erhöhen?**

A: Verwenden Sie GPU-Beschleunigung, wählen Sie ein kleineres Modell, reduzieren
Sie die maximale Antwortlänge.

### **F: Kann ERNI-KI offline verwendet werden?**

A: Ja, nach dem Laden der Modelle arbeitet das System vollständig autonom. Nur
RAG-Suche benötigt Internet.

### **F: Wie füge ich neue Sprachmodelle hinzu?**

A: Verwenden Sie `docker compose exec ollama ollama pull model-name` zum Laden
neuer Modelle.

## 🆘 Hilfe erhalten

### Technischer Support

- **Dokumentation**: Vollständige Dokumentation im `/docs` Ordner
- **System-Logs**: Verfügbar für Administrator
- **Community**: GitHub Issues für Fragen und Vorschläge

### Nützliche Ressourcen

- [Administrator-Handbuch](admin-guide.md) - für Systemkonfiguration
- [API-Dokumentation](../api-reference.md) - für Integrationen
- [Systemarchitektur](architecture.md) - technische Informationen

---

**💡 Tipp**: Experimentieren Sie mit verschiedenen Einstellungen und Modellen,
um die optimale Konfiguration für Ihre Aufgaben zu finden!
