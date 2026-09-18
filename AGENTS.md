# Expo-Version-Hinweis

Dieses Projekt nutzt **Expo SDK 57**. Bevor du Code schreibst, der Expo-APIs
benutzt, prüfe die exakt versionierten Docs unter
https://docs.expo.dev/versions/v57.0.0/ statt dich auf Trainingswissen zu
verlassen – Expo ändert sich schnell zwischen Versionen.

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
  sollen die native Liquid-Glass-Optik von iOS 26 automatisch bekommen
  (native UIKit-Komponenten, gebaut gegen aktuelles SDK). Eigene
  Glass-Oberflächen nur, wenn es ohne aufwändige native Bridges sauber
  machbar ist.
- **Ruhig, kein Lärm.** Keine Werbung außerhalb der Videos selbst, keine
  Shorts, keine aggressiven Empfehlungs-Popups. Kommentare sind sichtbar,
  aber pro Nutzer ein/ausschaltbar.
- **Kein Swift.** Bewusste Entscheidung des Nutzers – die App wird in
  React Native (TypeScript) entwickelt. Kleine native Swift-Snippets sind
  nur als letzter Ausweg für sehr spezielle native APIs akzeptabel, nicht
  die Regel.

## Tech-Stack

- **React Native (Expo)**, TypeScript.
- Navigation: `@react-navigation/native-stack` (echter `UINavigationController`)
  + `react-native-bottom-tabs` (echter `UITabBarController`) für nativen Look
  statt gemalter JS-Tab-Bar.
- Build: GitHub Actions mit macOS-Runner, produziert eine **unsignierte
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
