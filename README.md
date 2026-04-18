# Tankapp

iOS-App zum Finden günstiger Tankstellen via [Tankerkönig API](https://creativecommons.tankerkoenig.de/).

Status: **MVP — Phase 0/1 (Setup + API-Client mit Tests).** Siehe [ROADMAP.md](ROADMAP.md) für den Gesamtplan.

---

## Setup

### 1. Tankerkönig-API-Key beantragen

Per Mail anfragen: <https://creativecommons.tankerkoenig.de/#register> (kostenlos, dauert üblicherweise <24 h).

### 2. API-Key eintragen

Sobald die Mail kommt:

```bash
# Datei existiert bereits mit Platzhalter — einfach den Key ersetzen
$EDITOR Secrets.xcconfig
```

`Secrets.xcconfig` ist gitignored, landet also nie im Repo.

### 3. Xcode-Projekt generieren

Das `.xcodeproj` wird aus `project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen) erzeugt:

```bash
brew install xcodegen          # einmalig
xcodegen generate              # erzeugt Tankapp.xcodeproj
open Tankapp.xcodeproj
```

> Das `.xcodeproj` ist absichtlich gitignored — wir committen nur die `project.yml` als Source of Truth. Nach jedem Pull oder Datei-Add neu generieren.

### 4. Bauen & Laufen

In Xcode: Scheme `Tankapp` → dein iPhone (oder Simulator) → Run.

---

## Projekt-Struktur

```
Tankapp/
├── App/                         # App-Entry, Root-View
├── Core/
│   ├── Models/                  # Station, FuelType (Domain)
│   └── API/                     # TankerkoenigClient, DTOs, APIError
├── DesignSystem/                # (kommt in Phase 3)
├── Features/                    # (kommt in Phase 3)
└── Resources/Assets.xcassets    # AppIcon, AccentColor

TankappTests/
├── Fixtures/                    # JSON-Beispielantworten
├── MockURLProtocol.swift        # URL-Mock für Networking-Tests
└── TankerkoenigClientTests.swift
```

## Was kann der API-Client jetzt?

Eine Methode, bewusst minimal:

```swift
let client = TankerkoenigClient.fromBundle()
let stations = try await client.searchStations(
    latitude: 52.034,
    longitude: 8.534,
    radiusKm: 5
)
```

- Liefert immer **alle** Spritsorten und sortiert nach Entfernung — Sort/Filter-Wechsel im UI braucht **keine** neue Anfrage.
- Radius wird auf 1–25 km geclampt (API-Limit).
- Behandelt `null` und `false` als „Preis nicht verfügbar" korrekt.

Fehler-Typen in `APIError`: `missingAPIKey`, `invalidURL`, `network`, `http`, `decoding`, `apiError`.

## Tests

```bash
xcodebuild test \
  -project Tankapp.xcodeproj \
  -scheme Tankapp \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=18.3'
```

Oder einfach in Xcode: ⌘U.

### Bekanntes lokales Problem: Simulator startet nicht

Auf diesem Mac ist `~/Library/Developer/CoreSimulator` ein Symlink nach `/Volumes/Data/Xcode/CoreSimulator/`. Dadurch verweigert macOS dem `CoreSimulatorService` den Zugriff (TCC). Folge: `simctl list devices` ist leer und neue Simulatoren bleiben in „Creating" hängen.

**Lösungsvorschläge (eine Option reicht):**

1. **Full Disk Access für CoreSimulator** — System Settings → Privacy & Security → Full Disk Access → `+` → in Finder per ⌘⇧G den Pfad öffnen:
   `/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/XPCServices/com.apple.CoreSimulator.CoreSimulatorService.xpc`
   und auswählen.
2. **Symlink entfernen, Originalort nutzen** — wenn genug Platz auf dem System-Volume:
   ```bash
   rm ~/Library/Developer/CoreSimulator
   mkdir -p ~/Library/Developer/CoreSimulator/{Devices,Caches,Temp}
   ```
3. **Auf physischem iPhone testen** — kein Simulator nötig.

Sobald der Simulator wieder läuft:
```bash
xcrun simctl create "iPhone-15-Pro-Test" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-18-3
```

## Lizenz-Hinweis

Daten von **MTS-K** unter CC BY 4.0 via tankerkoenig.de. Ein entsprechender Hinweis kommt in den About-Screen, sobald dieser implementiert ist.
# tankapp
