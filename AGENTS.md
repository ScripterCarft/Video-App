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
Verhalten. Bei nativen Build-Problemen: `patches/` enthält bereits einen
`patch-package`-Fix für einen bekannten `expo-modules-jsi`-Bug beim
Xcode-27-Archivieren.

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
