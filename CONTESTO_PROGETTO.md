# AI Reader - CONTESTO_PROGETTO

> File di contesto da allegare o incollare quando si apre una nuova chat di progetto.

## Nome e obiettivo

**Nome app:** AI Reader  
**Nome tecnico Flutter/package:** `pdf_translator`  
**Target principale:** Android

AI Reader è una app Flutter per leggere documenti **PDF** ed **EPUB** e usare funzioni AI sul testo selezionato.

Funzioni AI principali:

- Traduci
- Spiega
- Riassumi
- Vocabolario

Provider AI gestiti:

- OpenAI
- DeepSeek

L'app è pensata per lettura, traduzione e approfondimento di libri/documenti, con storico dei risultati e ripresa della posizione di lettura.

---

## Ambiente di sviluppo

- Windows
- Flutter
- Android SDK / emulatori Android
- VS Code
- Git

Comandi ricorrenti:

```powershell
flutter clean
flutter pub get
flutter run
flutter build apk --release
```

APK release:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Se `adb` non è nel PATH:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-release.apk
```

---

## Struttura principale

```text
lib/
  main.dart
  pages/
    home_page.dart
    settings_page.dart
    pdf_translator_page.dart
    epub_reader_page.dart
    history_page.dart
    result_page.dart
  services/
    ai_service.dart
    epub_service.dart
    storage_service.dart
    text_cleaner_service.dart
  widgets/
    translation_panel.dart
  models/
    history_item.dart
    recent_document.dart

android/
assets/
  icon/
    app_icon.png

pubspec.yaml
```

---

## Funzioni implementate

### Home

La Home è separata da PDF/EPUB.

Funzioni:

- Header grafico AI Reader
- Apri documento PDF o EPUB
- Ultimi documenti
- Rimozione singolo documento recente
- Svuota recenti
- Tipo documento PDF/EPUB
- Progresso EPUB nei recenti
- Info app
- Accesso a Impostazioni

### PDF

- Apertura PDF
- Ripristino posizione/pagina
- Selezione testo
- Pannello AI
- Cronologia risultati
- Cache AI
- Apertura PDF/EPUB da reader
- Barra strumenti semplificata senza titolo file
- Back standard Android, senza pulsante Home ridondante

### EPUB

- Apertura EPUB
- Lettura con tema chiaro/seppia/scuro
- Slider dimensione carattere
- Slider margini laterali
- Interlinea regolabile
- Navigazione indice capitoli
- Salvataggio posizione
- Progresso lettura nei recenti
- Selezione testo
- Pannello AI
- Cronologia risultati
- Cache AI
- Titolo capitolo reale mostrato nel pannello/storico, non numero fittizio
- Rendering ottimizzato/lazy per EPUB pesanti
- Navigazione capitoli migliorata con `scrollable_positioned_list`

### Pannello AI

File:

```text
lib/widgets/translation_panel.dart
```

Stato:

- Pulsanti AI compatti su una riga:
  - Traduci
  - Spiega
  - Riassumi
  - Vocab.
- Icone colorate
- Nessun pulsante generico “Azioni”
- Risultato AI in card leggibile
- Testo selezionato nascosto di default con toggle Mostra/Nascondi
- Provider selector
- Switch auto-traduzione
- Apertura pagina risultato
- Pulisci risultato/selezione

### Impostazioni app

File:

```text
lib/pages/settings_page.dart
```

Funzioni:

- Provider AI predefinito
- Auto-traduzione on/off
- Tema EPUB predefinito
- Svuota cache AI
- Info app

---

## Grafica e identità

Nome visibile:

```text
AI Reader
```

Identità:

- Tema blu/viola coerente
- Launcher icon personalizzata
- Splash screen Android personalizzato
- Home ridisegnata
- AppBar coerenti
- Pannello AI compatto e moderno

Icona app:

```text
assets/icon/app_icon.png
```

Launcher icon generata con:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.11.0

flutter_icons:
  android: true
  ios: false
  image_path: "assets/icon/app_icon.png"
  adaptive_icon_background: "#3F51B5"
  adaptive_icon_foreground: "assets/icon/app_icon.png"
```

Comando:

```powershell
dart run flutter_launcher_icons:main
```

Nota: `flutter_launcher_icons >=0.14.0` creava conflitto con `epubx ^4.0.0` per la dipendenza `image`.

---

## Dipendenze importanti

```yaml
syncfusion_flutter_pdfviewer
file_picker
http
flutter_dotenv
shared_preferences
path_provider
epubx
html_unescape
scrollable_positioned_list
flutter_launcher_icons
```

---

## Ottimizzazione EPUB

### Problema iniziale

Su EPUB pesanti, soprattutto su dispositivi vecchi come Samsung M31:

- apertura molto lenta
- scroll scattoso/bloccato
- primo frame circa 11 secondi

Log rilevato:

```text
[EPUB PERF] chapters: 206, chars: 1460482
[EPUB PERF] first frame: 11295 ms
```

### Causa

Il reader costruiva tutto il libro insieme:

```text
SingleChildScrollView
  SelectionArea
    Column
      tutti i capitoli
```

Questo creava 1,46 milioni di caratteri prima del primo frame.

### Soluzione

Rendering lazy per capitoli e poi navigazione con `scrollable_positioned_list`.

Risultati dopo ottimizzazione:

```text
first frame: 1498 ms
first frame: 425 ms
first frame: 382 ms
```

Lo scroll è diventato molto più fluido.

### Note importanti

- Non tornare a `SingleChildScrollView + Column + tutti i capitoli`.
- Con rendering lazy, non usare `GlobalKey + ensureVisible` su capitoli non costruiti.
- I vecchi elementi di storico creati prima del cambio navigazione potevano non tornare al punto giusto.
- Dopo cancellazione vecchio storico e creazione nuovi risultati, il ritorno ai punti dello storico funziona.
- Lo storico ora mostra il titolo capitolo reale invece di “Capitolo X” basato sulla struttura EPUB.

---

## Storico, cache, recenti

### Storico AI

Salva:

- azione
- provider
- testo originale
- risultato
- documento
- posizione/pagina/capitolo
- per EPUB: usare titolo capitolo come label utente

### Cache AI

Usata per non ripetere richieste uguali.

Svuotare cache non deve cancellare:

- storico
- recenti
- posizioni salvate

### Recenti

- separati da storico/cache
- rimozione singola
- svuota recenti
- progresso EPUB mostrato nei recenti

---

## Problemi già risolti

### Kotlin/Gradle cache

Errore ricorrente:

```text
Daemon compilation failed
Could not close incremental caches
this and base files have different roots
```

Soluzione in `android/gradle.properties`:

```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

Eventuale opzione ulteriore:

```properties
org.gradle.daemon=false
```

### `adb` non riconosciuto

Usare:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
```

---

## Stato attuale stabile

Aree funzionanti:

- Home
- PDF reader
- EPUB reader ottimizzato
- Pannello AI
- Cronologia PDF/EPUB
- Impostazioni app
- Icona/splash/tema
- APK release

Commit importanti del percorso:

- Aggiunge slider lettura EPUB e corregge menu
- Migliora apertura e scorrimento EPUB
- Migliora navigazione capitoli EPUB
- Migliora etichette capitoli EPUB
- Limita log prestazioni EPUB al debug
- Aggiunge impostazioni app

---

## Attenzioni per modifiche future

### EPUB

Non proporre di tornare a:

```text
SingleChildScrollView + Column + tutti i capitoli
```

perché distrugge le prestazioni sugli EPUB grandi.

Per navigazione capitoli usare logica basata su lista posizionabile/indice.

### SelectionArea

Evitare chiavi che forzano ricostruzione completa:

```dart
key: ValueKey(_selectionClearVersion)
```

Possono causare salti di posizione o rebuild pesanti.

### Log performance

I log `[EPUB PERF]` devono restare solo in debug mode con:

```dart
kDebugMode
```

### Dipendenze

Evitare aggiornamenti massivi pacchetti senza motivo. Attenzione a:

- `epubx`
- `flutter_launcher_icons`
- `image`
- Syncfusion PDF viewer

---

## Idee future possibili

- Ricerca dentro EPUB
- Ricerca dentro PDF
- Preferiti/documenti fissati in alto
- Note personali sul testo selezionato
- Esportazione storico in TXT/Markdown
- Tema scuro completo app
- Modalità studio/domande AI
- Miglioramento gestione capitoli EPUB se emergono altri casi limite
- Firma release Android più seria per distribuzione esterna

---

## Prompt da usare in nuova chat

```text
Sto continuando il progetto Flutter AI Reader.

Leggi il file CONTESTO_PROGETTO.md e usalo come contesto principale.
Prima di proporre modifiche, considera lo stato attuale e le note tecniche.
Non suggerire di tornare a SingleChildScrollView + Column per EPUB perché è stato ottimizzato con rendering lazy.
Procediamo sempre con modifiche mirate e commit frequenti.
```
