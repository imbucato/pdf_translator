# AI Reader - CONTESTO_PROGETTO

> File di contesto da allegare/incollare quando si apre una nuova chat di progetto.  
> Aggiornato dopo il reset e il reinserimento controllato delle funzioni utili.

---

## Nome e obiettivo

**Nome app:** AI Reader  
**Package Flutter:** `pdf_translator`  
**Target principale:** Android  
**Repository:** `https://github.com/imbucato/pdf_translator`

AI Reader è una app Flutter per leggere **PDF** ed **EPUB** e usare funzioni AI sul testo selezionato.

Funzioni AI principali:

- Traduci
- Spiega
- Riassumi
- Vocabolario

Provider AI gestiti:

- OpenAI
- DeepSeek

L’app è usata soprattutto per **lettura di piacere**, traduzione e approfondimento leggero. Non proporre come priorità funzioni da studio pesante, flashcard o ricerca avanzata.

---

## Ambiente

- Windows
- Flutter
- Android SDK / emulatori Android
- VS Code
- Git

Comandi ricorrenti:

```powershell
git status
flutter analyze
flutter run
```

Build APK:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" uninstall com.example.pdf_translator
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install build\app\outputs\flutter-apk\app-release.apk
```

Nota importante: ogni volta che viene indicato `flutter build apk --release`, aggiungere sempre subito dopo anche i comandi per disinstallare e reinstallare l’APK.

APK release:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Su dispositivi vecchi, per esempio Lenovo M10, `flutter run` debug può essere molto lento. Per test prestazioni usare APK release installato manualmente.

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
    bookmarks_page.dart
  services/
    ai_service.dart
    epub_service.dart
    storage_service.dart
    text_cleaner_service.dart
    pdf_thumbnail_service.dart       # se presente
  widgets/
    translation_panel.dart
    document_thumbnail.dart          # se presente
  models/
    history_item.dart
    recent_document.dart
    bookmark_item.dart

assets/
  icon/
    app_icon.png

pubspec.yaml
```

Controllare sempre il repository reale prima di proporre modifiche: alcuni file possono cambiare in base ai commit di Codex.

---

## Stato attuale stabile

Dopo un reset per problemi di prestazioni PDF, sono state reintrodotte solo le modifiche utili e più leggere.

Funzioni attuali:

- Home funzionante
- Un solo pulsante principale **Apri**
- PDF reader
- EPUB reader ottimizzato
- Pannello AI
- Storico AI PDF/EPUB
- Cache AI
- Impostazioni
- Icona/splash/tema
- Recenti
- Documenti fissati nei recenti
- Segnalibri PDF/EPUB
- Segnalibri multipli nello stesso capitolo EPUB
- Copertine EPUB nei recenti e segnalibri
- Titolo/autore nei recenti e segnalibri
- Anteprime PDF leggere nei recenti e segnalibri
- Barra avanzamento EPUB
- Barra avanzamento PDF leggera
- Card **Continua a leggere**

Funzioni da non considerare presenti / da non riproporre ora:

- Libreria completa separata
- Home/catalogo pesante
- Modalità lettura immersiva EPUB
- Ricerca PDF/EPUB come priorità
- Flashcard/modalità studio
- Esportazione storico come priorità

---

## Aggiornamento recente: archivio interno, segnalibri e lettura EPUB

Stato aggiornato dopo le ultime modifiche:

- L'app AI Reader importa i PDF/EPUB aperti tramite file picker in una cartella interna persistente dell'app:

```text
app_flutter/ai_reader_documents
```

- I recenti, il progresso, i segnalibri e le note devono usare il path persistente interno, non la cache temporanea di `file_picker`.
- I vecchi documenti che puntano a `/cache/file_picker/...` vengono migrati alla cartella persistente quando vengono riaperti, se il file cache esiste ancora.
- Dopo la migrazione il secondo open usa direttamente il path persistente, con log import `alreadyPersistent=true`.
- La gestione dei documenti mancanti/non disponibili mostra una UI gentile e permette di rimuovere riferimenti interni senza cancellare file esterni.
- La Home ha un accesso discreto alla pagina **Documenti importati** / **Archivio documenti**.
- La pagina **Documenti importati**:
  - mostra i file presenti in `ai_reader_documents`
  - mostra tipo PDF/EPUB
  - mostra dimensione file e spazio totale usato
  - permette apertura del documento
  - permette eliminazione della copia interna con conferma
  - elimina solo file dentro la cartella interna sicura
  - rimuove riferimenti collegati: recenti, fissati, progresso, segnalibri e note se associati al path
- I titoli PDF importati vengono puliti rimuovendo dal titolo visualizzato il suffisso timestamp tecnico, senza rinominare il file fisico.
- Sono stati aggiunti sfondi pagina EPUB: Bianco, Carta, Crema, Grigio tenue, con colore testo leggibile.
- Sono stati aggiunti altri font EPUB di sistema, inclusi Arial, Times, Comic, Corsivo, Sottile e Serif Mono.
- I segnalibri EPUB mostrano sia percentuale libro sia percentuale capitolo.
- I segnalibri PDF/EPUB possono avere note testuali opzionali.
- L'editor nota e' una pagina separata, non un dialog/bottom sheet, per evitare errori con tastiera e build scope.
- La grafica dell'editor note e' stata rifinita.
- Esiste una lista segnalibri nel reader PDF e nel reader EPUB accessibile dalla AppBar.

Non proporre:

- TTS / lettura ad alta voce
- tema scuro completo
- Libreria pesante

Vincoli tecnici da mantenere:

- Non modificare il rendering lazy EPUB.
- Non tornare mai a `SingleChildScrollView + Column` per EPUB.
- Non usare `GlobalKey + ensureVisible` su capitoli non costruiti.
- Non toccare PDF thumbnail/anteprime se non strettamente necessario.
- I log debug tipo `[AI_READER_DOC_OPEN]`, `[AI_READER_DOC_IMPORT]`, `[AI_READER_IMPORTED_DOCS]`, `[AI_READER_IMPORTED_DOC_DELETE]`, `[EPUB PERF]` sono ammessi solo in `kDebugMode`.

Nota build importante: quando viene indicato `flutter build apk --release`, subito dopo bisogna fornire anche i comandi per disinstallare e reinstallare l'APK sul dispositivo Android.

---

## Home

La Home è leggera e non deve diventare una libreria complessa.

Funzioni:

- Header AI Reader
- Un solo pulsante **Apri**
- Card **Continua a leggere**
- Ultimi documenti
- Documenti fissati in alto
- Rimozione singolo recente
- Svuota recenti
- Tipo PDF/EPUB
- Progresso EPUB nei recenti
- Copertine EPUB
- Anteprime PDF leggere
- Titolo/autore invece del filename
- Accesso a Segnalibri
- Info app
- Impostazioni

### Pulsante Apri

Mantenere un solo pulsante:

```text
Apri
```

Non proporre due pulsanti separati PDF/EPUB.

Il file picker apre PDF o EPUB e l’app riconosce il tipo da estensione.

### Continua a leggere

La card appare se esiste almeno un recente.

Deve scegliere il documento **più recentemente aperto**, non semplicemente quello fissato.

Mostra:

- copertina EPUB o anteprima PDF se disponibile
- placeholder se manca
- `displayTitle` o fallback pulito
- autore se disponibile
- tipo PDF/EPUB
- progresso EPUB se disponibile
- pagina/progresso PDF se disponibile

Tap:

- apre il documento come i recenti
- EPUB riprende posizione
- PDF riprende pagina
- se file assente: SnackBar gentile, niente crash

---

## Recenti e documenti fissati

Nei recenti si possono fissare documenti.

Regole:

- fissati sempre in alto
- fissati ordinati per apertura recente
- non fissati sotto, ordinati per apertura recente
- fissaggio persistente
- svuotare recenti svuota anche fissati
- segnalibri indipendenti dai recenti

Campo probabile:

```dart
isPinned
```

Retrocompatibilità: se manca, default `false`.

---

## Titolo/autore e nomi puliti

Nei recenti e segnalibri non mostrare come testo principale il filename grezzo.

### EPUB

Estrarre dai metadati EPUB:

- titolo
- autore

Fallback:

- titolo = nome file pulito
- autore assente = non mostrare riga autore

### PDF

Non usare metadati PDF pesanti.

Per PDF:

- titolo = nome file pulito
- autore = null/vuoto
- niente estrazione metadati pesante

Esempi:

```text
Blue_Remembered_Earth.pdf -> Blue Remembered Earth
relazione_finale_v2.pdf -> relazione finale v2
```

La UI deve usare:

```text
displayTitle se non vuoto
altrimenti fallback pulito da name/path
```

---

## Copertine EPUB e anteprime PDF leggere

### EPUB

- Estrarre copertina se disponibile
- Salvare/cache in app directory
- Non riestrarre inutilmente
- Se manca: placeholder EPUB

### PDF

Le anteprime PDF devono essere **leggere**.

Regole importanti:

- non generare thumbnail PDF dentro `pdf_translator_page.dart`
- non generare thumbnail durante apertura/scorrimento PDF
- generare solo fuori dal reader, per Home/Segnalibri
- se manca thumbnail: placeholder immediato
- non rigenerare se esiste in cache
- thumbnail piccola
- salvare solo path/cache path, non byte in `SharedPreferences`
- usare `cacheWidth`/`cacheHeight` se utile
- se fallisce: placeholder, niente crash

Questa parte è delicata per prestazioni su dispositivi vecchi.

---

## PDF reader

Funzioni:

- Apertura PDF
- Ripristino pagina
- Selezione testo
- Pannello AI
- Storico/cache
- Segnalibri PDF
- Barra avanzamento PDF leggera

### Prestazioni PDF

Regole assolute:

- `SfPdfViewer` non deve essere ricostruito a ogni cambio pagina
- evitare `setState()` frequenti nel parent che contiene `SfPdfViewer`
- evitare generazione thumbnail nel reader
- evitare estrazione metadati pesanti nel reader
- evitare `FutureBuilder`/calcoli pesanti intorno al viewer
- evitare chiavi dinamiche sul viewer

### Barra avanzamento PDF leggera

Mostra qualcosa tipo:

```text
Pagina 12 di 240 · 5%
```

Deve usare una soluzione leggera:

- `ValueNotifier`
- `ValueListenableBuilder`
- widget separato equivalente

`onPageChanged` aggiorna solo il notifier, non tutto il reader.

Calcolo:

```text
progress = currentPage / totalPages
```

Clamp tra `0.0` e `1.0`.

### Segnalibri PDF

Più segnalibri per documento.

Chiave logica:

```text
documentPath + pageNumber
```

Tap icona:

- se pagina già segnalibrata: rimuovi
- altrimenti: aggiungi

---

## EPUB reader

Funzioni:

- Apertura EPUB
- Tema chiaro/seppia/scuro
- Slider dimensione font
- Slider margini laterali
- Interlinea
- Indice capitoli
- Salvataggio posizione
- Progresso lettura nei recenti
- Barra avanzamento EPUB
- Selezione testo
- Pannello AI
- Storico/cache
- Titolo capitolo reale
- Rendering lazy con `scrollable_positioned_list`
- Segnalibri EPUB multipli
- Copertina EPUB
- Titolo/autore metadati

### Ottimizzazione EPUB

Non tornare mai a:

```text
SingleChildScrollView
  SelectionArea
    Column
      tutti i capitoli
```

Questa vecchia struttura rendeva EPUB pesanti lentissimi.

Usare rendering lazy e `scrollable_positioned_list`.

Non usare `GlobalKey + ensureVisible` su capitoli non costruiti.

### Barra avanzamento EPUB

Mostra progresso complessivo 0–100%, eventualmente con titolo capitolo reale.

Regole:

- non appesantire scroll
- non interferire con selezione testo
- non interferire con pannello AI
- clamp tra `0.0` e `1.0`
- evitare `setState` troppo frequenti

### Segnalibri EPUB

Devono poter esistere più segnalibri nello stesso capitolo.

Chiave logica:

```text
documentPath + chapterIndex + posizioneInterna
```

Campi probabili:

```dart
chapterIndex
chapterTitle
epubPositionInChapter
epubPositionLabel
```

Vecchi segnalibri solo con `chapterIndex` devono continuare a funzionare.

Nota pratica accettata: per aggiungere più segnalibri nello stesso capitolo può essere necessario toccare/interagire col testo per aggiornare la posizione interna.

---

## Pannello AI

File:

```text
lib/widgets/translation_panel.dart
```

Funzioni:

- Traduci
- Spiega
- Riassumi
- Vocab.
- Provider selector
- Auto-traduzione
- Risultato in card
- Testo selezionato nascosto con toggle
- Copia risultato/testo selezionato
- Pulisci risultato/selezione
- Apertura pagina risultato

Attenzione: modifiche a `SelectionArea` e gesture sono delicate.

---

## Segnalibri

Pagina:

```text
lib/pages/bookmarks_page.dart
```

Modello:

```text
lib/models/bookmark_item.dart
```

Funzioni:

- Lista segnalibri PDF/EPUB
- Ordinamento recente
- Eliminazione singolo segnalibro
- Apertura documento
- PDF: ritorno pagina
- EPUB: ritorno capitolo/posizione
- Miniatura:
  - copertina EPUB
  - anteprima PDF leggera
  - placeholder
- Titolo/autore
- Posizione leggibile

I segnalibri sono separati da:

- storico AI
- cache AI
- recenti
- posizioni salvate

Svuotare cache o recenti non cancella i segnalibri.

---

## Impostazioni

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

Verificare `pubspec.yaml` reale per eventuali dipendenze thumbnail PDF.

Evitare aggiornamenti massivi.

Attenzione a:

- `epubx`
- `image`
- `flutter_launcher_icons`
- Syncfusion PDF viewer
- librerie PDF thumbnail

---

## Problemi noti / soluzioni

### Gradle/Kotlin cache

Errore:

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

Eventuale:

```properties
org.gradle.daemon=false
```

### File Gradle/lint bloccato da Windows

Errore:

```text
FileSystemException ... lint-cache ... jar: Impossibile accedere al file. Il file è utilizzato da un altro processo
```

Soluzione:

```powershell
cd android
.\gradlew --stop
cd ..
taskkill /F /IM java.exe
flutter clean
```

Se serve:

```powershell
Remove-Item -Recurse -Force build
```

### adb non riconosciuto

Usare path completo:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
```

### Modalità lettura immersiva EPUB

Provata e scartata.

Problemi:

- AI non funzionava bene
- difficile uscire
- interferiva con selezione/controlli

Non riproporla senza ripensarla da zero.

---

## Modifiche da evitare ora

- Libreria completa
- Home pesante tipo catalogo
- ricerca testo come priorità
- flashcard/modalità studio
- export storico come priorità
- modalità immersiva
- anteprime PDF generate dentro il reader
- metadati PDF pesanti
- refactor massivi

---

## Idee future sensate

Orientate a lettura di piacere:

- Tema scuro completo app
- Piccoli miglioramenti Home, ma senza Libreria pesante
- Font EPUB serif/sans
- Allineamento testo EPUB
- Preset margini/interlinea
- Lettura ad alta voce / TTS
- Backup impostazioni/recenti/segnalibri
- Migliorare precisione segnalibri EPUB

---

## Prompt per nuova chat

```text
Sto continuando il progetto Flutter AI Reader.

Leggi il file CONTESTO_PROGETTO.md e usalo come contesto principale.
Prima di proporre modifiche, considera lo stato attuale e le note tecniche.
Non suggerire di tornare a SingleChildScrollView + Column per EPUB perché è stato ottimizzato con rendering lazy.
Non proporre Libreria pesante come priorità: uso l’app soprattutto per pochi libri e lettura di piacere.
Non proporre funzioni da studio/flashcard/ricerca come priorità.
Per modifiche PDF, attenzione alle prestazioni su dispositivi vecchi: testare con APK release, non solo flutter run.
Ogni volta che indichi flutter build apk --release, aggiungi subito dopo anche i comandi adb uninstall/install dell’APK.
Procediamo sempre con modifiche mirate e commit frequenti.
```

---

## Checklist APK

```powershell
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" uninstall com.example.pdf_translator
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install build\app\outputs\flutter-apk\app-release.apk
```
