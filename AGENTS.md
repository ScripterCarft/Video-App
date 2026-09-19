# Expo-Version-Hinweis

Dieses Projekt nutzt **Expo SDK 58 (Preview)** mit **React Native 0.88
(RC)** und **React Navigation 8 (Alpha)**, um gegen **iOS 27 / Xcode 27**
zu bauen. Das sind bewusst Pre-Release-Versionen, weil iOS 27 brandneue
UIKit-APIs mitbringt (native Tab-Bar-Minimize-Behavior, Bottom-Accessory,
System-Suchtab), die erst in diesen Versionen unterstützt werden.

Für Pre-Release-Versionen gibt es oft **keine** oder nur unvollständige
Docs unter docs.expo.dev/versions/. Verlass dich nicht auf Trainingswissen
(das kennt iOS 27 nicht) und nicht blind auf ältere versionierte Docs –
prüfe stattdessen die exakten Typdefinitionen/Kommentare direkt in
`node_modules/` (z.B. `node_modules/@react-navigation/bottom-tabs/lib/typescript/src/types.d.ts`),
das ist hier die verlässlichste Quelle für das tatsächlich installierte
Verhalten.

## Native Patches (`patches/`, via `patch-package`)

`postinstall` wendet die Patches bei jedem `npm install`/`npm ci` (auch
in der CI) automatisch wieder an. Zwei Patches liegen aktuell drin:

- **`expo-modules-jsi`**: Workaround für einen Xcode-27-Bug beim
  `xcodebuild archive` (die `-quiet`-Flag im Build-Skript hat den Build
  kaputt gemacht).
- **`react-native-screens`** (`ios/RNSScreenStackHeaderConfig.mm`, drei
  Änderungen in `buildAppearance:`/`applyConfig...`):
  1. `configureWithOpaqueBackground` → `configureWithDefaultBackground` –
     nur Letzteres adoptiert laut Apple das echte iOS-26/27-Liquid-Glass-
     Material für die Nav-Bar. Ohne diesen Patch bleibt die Nav-Bar auf
     altem, solidem Chrome, **egal gegen welches SDK gebaut wird**.
  2. `appearance.backgroundEffect = nil` für den Default-Blur-Fall
     entfernt – ohne diese Änderung hätte react-native-screens das gerade
     gesetzte Glass-Material sofort wieder gelöscht, weil `headerBlurEffect`
     bei uns nirgends gesetzt ist und auf `'none'` defaultet.
  3. `largeTitleDisplayMode`: `Always` → `Inline` (neuer iOS-26-Wert,
     `UINavigationItem.LargeTitleDisplayMode.inline`) für den kompakten,
     Podcasts-artigen Large-Title-Look statt des klassischen
     Auf-/Zuklapp-Verhaltens.

  **Wichtige Falle beim Patchen von react-native-screens:** Das Paket
  enthält *zwei parallele* native Header-Implementierungen – die
  klassische unter `ios/*.mm` (Fabric-Komponente `RNSScreenStackHeaderConfig`)
  und eine neuere, komplett separate unter `ios/gamma/`
  (`RNSStackScreenHeaderCoordinator`). `@react-navigation/native-stack`
  läuft (Stand jetzt) über die **klassische** Implementierung – verifiziert
  über die Importkette in `useHeaderConfigProps.js`/`NativeStackView.native.js`
  bis zum `codegenNativeComponent('RNSScreenStackHeaderConfig')`-Aufruf.
  Ein erster Patch-Versuch landete fälschlich in `ios/gamma/` und hatte
  dadurch schlicht keine Wirkung. Vor jedem neuen Patch-Versuch: erst
  über die Fabric-Komponenten-Namen nachverfolgen, welche `.mm`-Datei
  wirklich lädt, nicht raten.

  Bekanntes, noch offenes Upstream-Issue dazu:
  software-mansion/react-native-screens#4021 ("Adopt
  `UINavigationBarAppearance.configureWithDefaultBackground`"). Bei einem
  react-native-screens-Update prüfen, ob der Patch noch anwendbar ist
  (`patch-package` bricht beim `postinstall` laut ab, wenn nicht) und ob
  das Upstream-Issue inzwischen selbst gefixt wurde – dann kann der
  Patch weg.

# VideoApp

Persönliches Spaßprojekt: eine iOS-App, die YouTube-Videos in einer waschechten
Apple-UI anzeigt – im Prinzip "YouTube, aber wie eine native Apple-App gebaut
(Musik/TV-App-Stil)".

Kein Firmenprojekt, keine App-Store-Veröffentlichung geplant. Nur für den
eigenen privaten Gebrauch (Sideloading via Sideloadly, kostenlose Apple-ID).

## Leitprinzipien

- **iOS first.** Es wird ausschließlich für iOS entwickelt und getestet.
  Android/Web sind kein Ziel, auch wenn React Native es theoretisch könnte.
- **Apple Human Interface Guidelines.** Navigation, Abstände, Typografie,
  Icons (SF Symbols), Gesten – alles soll sich anfühlen wie eine native
  Apple-App, nicht wie eine Cross-Platform-App mit iOS-Skin.
- **Liquid Glass wo möglich.** System-Komponenten (Tab-Bar, Navigation-Bar)
  sollen die native Liquid-Glass-Optik (seit iOS 26, jetzt iOS 27)
  automatisch bekommen (native UIKit-Komponenten, gebaut gegen aktuelles
  SDK). Eigene Glass-Oberflächen nur, wenn es ohne aufwändige native
  Bridges sauber machbar ist. Farben über `PlatformColor(...)` (z.B.
  `label`, `secondaryLabel`, `systemBackground`, `separator`) statt
  hartkodierter Hex-Werte, damit sie sich systemkonform verhalten.
- **Ruhig, kein Lärm.** Keine Werbung außerhalb der Videos selbst, keine
  Shorts, keine aggressiven Empfehlungs-Popups. Kommentare sind sichtbar,
  aber pro Nutzer ein/ausschaltbar.
- **Kein Swift.** Bewusste Entscheidung des Nutzers – die App wird in
  React Native (TypeScript) entwickelt. Kleine native Swift-Snippets sind
  nur als letzter Ausweg für sehr spezielle native APIs akzeptabel, nicht
  die Regel.
- **UI-Sprache: Englisch als Standard, aber mehrsprachig vorbereitet.**
  Alle sichtbaren UI-Texte laufen über `src/i18n/strings.ts` (aktuell nur
  `en` befüllt), nicht als hartkodierte Strings in Screens/Navigation.
  `app.json` registriert `en` unter `expo.locales`, damit iOS die
  unterstützte Sprache korrekt kennt (`CFBundleLocalizations`). Neue
  Sprache hinzufügen = neues Objekt (z.B. `de`) in `strings.ts` +
  passender Eintrag in `app.json`/`locales/`.

## Tech-Stack

- **React Native (Expo)**, TypeScript.
- Navigation: `@react-navigation/native-stack` (echter `UINavigationController`)
  + `@react-navigation/bottom-tabs` mit `implementation="native"` (echter
  `UITabBarController`, inkl. `tabBarMinimizeBehavior` und
  `tabBarSystemItem: 'search'` für den abgesetzten Such-Tab auf iOS 26+)
  für nativen Look statt gemalter JS-Tab-Bar. Kein eigener
  Profil-Button/Header-Icon mehr – Header sind reine native Large-Title-Bars
  ohne Custom-Content.
- Build: GitHub Actions mit macOS-Runner (`xcode-27`-Label, Xcode 27
  explizit via `xcode-select` gewählt), produziert eine **unsignierte
  .ipa** als Build-Artifact (kein Apple-Developer-Account im CI nötig).
- Installation aufs iPhone: **Sideloadly** (Windows) mit kostenloser
  Apple-ID. Zertifikat läuft alle 7 Tage ab, dann erneut installieren.

## Aktuelle Phase: UI-Prototyp mit Dummy-Daten

Es geht erstmal **nur um die Optik und Struktur**, nicht um echte
YouTube-Integration. Alle Videos/Kanäle/Abos sind Mock-Daten.

Noch nicht relevant und bewusst später zu entscheiden:
- Wie Videos tatsächlich abgespielt werden (offizieller YouTube-Player,
  iframe, yt-dlp-basierter Ansatz o.ä.)
- Echte YouTube-Datenanbindung / API
- Eigene Recommendation-Engine

### Navigation (Tab-Bar unten)

1. **Home** – Feed/Übersicht (Dummy-Videos)
2. **Suchen** – Suchleiste + Ergebnisliste (Dummy)
3. **Abos** – abonnierte Kanäle, deren Videos
4. **Library / Mediathek** – gespeicherte/gesehene Videos, Wiedergabeverlauf

(Benennung/Icons können sich noch ändern, Struktur orientiert sich an
Apple Music / Apple TV.)

### Feature-Leitplanken für den Prototyp

- Keine Shorts – weder UI-Element noch Datenmodell dafür vorsehen.
- Keine Werbung/Banner außerhalb des eigentlichen Videoinhalts.
- Kommentare pro Video ein-/ausblendbar (Toggle, lokal gespeichert reicht
  fürs Prototyp-Stadium).
- Ruhige, aufgeräumte Optik – lieber weniger UI-Elemente als YouTube-typische
  Reizüberflutung.

## Nicht-Ziele

- Kein App-Store-Release, keine Firmen-Signierung, kein bezahlter Apple
  Developer Account.
- Kein Android/Web-Support.
- Keine Monetarisierung/Werbung.
