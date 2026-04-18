# Tankapp — Roadmap

iOS-App zum Finden günstiger Tankstellen über die [Tankerkönig API](https://creativecommons.tankerkoenig.de/).

---

## Vision

Eine schicke, übersichtliche iOS-App in drei Ausbaustufen:

1. **MVP — Umkreissuche** — Tankstellen im einstellbaren Radius um den aktuellen Standort oder eine Adresse finden, sortiert nach Preis oder Entfernung.
2. **Routensuche** — Günstige Tankstellen entlang einer Route von A nach B.
3. **Bester Preis im Radius** — Direkter „Cheapest“-Modus mit großer Preis-Anzeige (Glance-View).

---

## Tech-Stack

| Bereich | Wahl | Warum |
|---|---|---|
| OS | iOS 17+ | Neueste SwiftUI-APIs (`MapKit` SwiftUI, `@Observable`, `ContentUnavailableView`) |
| UI | SwiftUI | Schnell, deklarativ, gutes Look-&-Feel out of the box |
| Architektur | MVVM mit `@Observable` | Klar, testbar, ohne Combine-Boilerplate |
| Networking | `URLSession` + `async/await` | Standard, keine externe Lib nötig |
| Karten | MapKit (SwiftUI) | Native, kostenlos, integriert sich nahtlos |
| Standort | CoreLocation | Standard |
| Geocoding | `CLGeocoder` | Adresse ↔ Koordinaten, kostenlos, eingebaut |
| Persistenz | `UserDefaults` (Settings), `FileManager` (Cache) | Klein halten — keine SwiftData/CoreData für MVP |
| Tests | XCTest + Swift Testing | Unit-Tests für API-Client und ViewModels |
| Min. Deployment | iOS 17.0 | Sweet Spot 2026: erfasst >95 % der iPhones |

**Bewusst weggelassen für MVP:** SwiftData, Combine, externe Dependencies (Alamofire etc.), Push-Notifications, Widgets.

---

## Projekt-Struktur

```
tankapp/
├── Tankapp.xcodeproj
├── Tankapp/
│   ├── App/
│   │   └── TankappApp.swift              # @main, AppState
│   ├── Features/
│   │   ├── Search/
│   │   │   ├── SearchView.swift          # Hauptscreen MVP
│   │   │   ├── SearchViewModel.swift
│   │   │   ├── StationListView.swift
│   │   │   ├── StationRowView.swift
│   │   │   └── StationDetailView.swift
│   │   └── Settings/
│   │       └── SettingsView.swift        # Spritsorte, Default-Radius
│   ├── Core/
│   │   ├── API/
│   │   │   ├── TankerkoenigClient.swift  # API-Client
│   │   │   ├── APIError.swift
│   │   │   └── DTOs/                     # Decodable-Modelle
│   │   ├── Location/
│   │   │   └── LocationManager.swift     # CoreLocation-Wrapper
│   │   ├── Geocoding/
│   │   │   └── AddressGeocoder.swift     # CLGeocoder-Wrapper
│   │   └── Models/
│   │       ├── Station.swift             # Domain-Modell
│   │       └── FuelType.swift            # enum: e5, e10, diesel
│   ├── DesignSystem/
│   │   ├── Colors.swift                  # Asset-Catalog Wrapper
│   │   ├── Typography.swift
│   │   └── Components/
│   │       ├── PriceTag.swift            # Hervorgehobener Preis
│   │       ├── BrandBadge.swift          # Logo / Brand-Pille
│   │       └── EmptyState.swift
│   ├── Resources/
│   │   ├── Assets.xcassets               # Brand-Logos, AppIcon, Colors
│   │   └── Localizable.xcstrings         # DE / EN
│   └── Info.plist                        # Location-Usage-Description
├── TankappTests/
│   ├── TankerkoenigClientTests.swift
│   └── SearchViewModelTests.swift
├── Secrets.xcconfig                      # gitignored: API_KEY=...
├── .gitignore
└── ROADMAP.md
```

---

## Tankerkönig API — Cheatsheet

- **Basis-URL:** `https://creativecommons.tankerkoenig.de/json/`
- **API-Key:** Pro Person/Projekt einmalig per Mail anfragen (kostenlos, [Anleitung](https://creativecommons.tankerkoenig.de/#register)).
- **Lizenz-Hinweis** (Pflicht): Im Impressum/About-Screen die [CC-BY 4.0 Quelle der MTS-K](https://creativecommons.tankerkoenig.de/#about) nennen.

### Endpunkte für MVP

| Endpoint | Zweck | Wichtige Params |
|---|---|---|
| `list.php` | Stationen im Umkreis | `lat`, `lng`, `rad` (max 25 km), `sort` (`dist`/`price`), `type` (`e5`/`e10`/`diesel`/`all`), `apikey` |
| `detail.php` | Detail einer Station | `id`, `apikey` |
| `prices.php` | Preise für bis zu 10 Stationen (für Feature 2) | `ids` (komma-getrennt), `apikey` |

**Stolperfallen:**
- `sort=price` funktioniert nur mit konkretem Spritsorte (`type ≠ all`).
- Radius hart auf 25 km begrenzt — UI muss das durchsetzen.
- Preise können `false` sein (Station hat aktuell keinen Preis gemeldet) → defensiv decoden.
- Rate-Limit: laut FAQ keine harte Obergrenze, aber „angemessen“ — wir cachen 60 s.

---

## MVP — Feature 1: Umkreissuche

### User-Story

> Als Autofahrer öffne ich die App, sehe sofort die günstigsten Tankstellen in meiner Nähe, kann den Radius und die Spritsorte anpassen, und bei Bedarf statt meines Standorts eine Adresse eintippen.

### Screens

1. **SearchView** (Hauptscreen)
   - Top: Adress-Suchfeld mit „📍 Aktueller Standort"-Button als Default
   - Filter-Bar: Spritsorte (Segmented: E5 / E10 / Diesel) · Radius-Slider (1–25 km) · Sort-Toggle (Preis / Entfernung)
   - Liste der Tankstellen (Cards mit Marke, Name, Entfernung, Preis groß)
   - Pull-to-refresh
   - Map-Toggle (oben rechts) für später (Stub, kein MVP-Blocker)

2. **StationDetailView**
   - Adresse, Öffnungszeiten-Info (`isOpen`)
   - Alle drei Spritsorten-Preise nebeneinander
   - Buttons: „In Karten öffnen" (Apple Maps), „Anrufen" (falls Telefonnummer)
   - Mini-Map mit Pin

3. **SettingsView**
   - Default-Spritsorte
   - Default-Radius
   - About / Impressum (CC-BY-Lizenz-Hinweis, App-Version)

### Interaktions-Flow

```
App-Start
  ↓
Location-Permission-Request (beim ersten Tap)
  ↓
SearchView lädt → Stationen via TankerkoenigClient
  ↓
Liste erscheint (Skeleton-Loader während Loading)
  ↓
Tap auf Card → StationDetailView (Push)
  ↓
Tap auf Adress-Feld → System-Keyboard, Geocoding bei Submit
```

---

## Phasen-Plan (MVP)

> Aufwand grob geschätzt für eine fokussierte Person, frei skalierbar.

### Phase 0 — Setup *(0,5 Tag)*
- [ ] Xcode-Projekt anlegen (`Tankapp`, SwiftUI, iOS 17, Swift 5.9)
- [ ] Git-Repo init (`.gitignore` aus GitHub-Template + `Secrets.xcconfig`)
- [ ] `Secrets.xcconfig` mit `TANKERKOENIG_API_KEY` einbinden, `Info.plist`-Variable
- [ ] **User-Aktion:** API-Key bei Tankerkönig per Mail anfragen
- [ ] Projekt-Skeleton-Ordner anlegen

### Phase 1 — Core-Domain *(1 Tag)*
- [ ] `FuelType` enum
- [ ] `Station` Domain-Modell
- [ ] `TankerkoenigClient` mit `searchStations(lat:lng:radius:type:sort:)` (async throws)
- [ ] DTO-Layer + Mapping zu Domain
- [ ] `APIError` enum (network, decoding, apiError mit Tankerkönig-Message, noKey)
- [ ] **Tests:** `TankerkoenigClientTests` mit Mock-`URLSession` (Response-Fixtures)

### Phase 2 — Location & Geocoding *(1 Tag)*
- [ ] `LocationManager` (`@Observable`) — `requestAuthorization`, `currentLocation`-Publisher
- [ ] `Info.plist`: `NSLocationWhenInUseUsageDescription` (DE/EN)
- [ ] `AddressGeocoder` (`CLGeocoder`-Wrapper) — `geocode(_ address: String) async throws -> CLLocation`
- [ ] Edge-Cases: kein Permission, kein GPS-Signal, Adresse nicht gefunden

### Phase 3 — UI / Design-System *(1,5 Tage)*
- [ ] Farbpalette im Asset-Catalog (Primary, Background, Card, PriceLow/Mid/High)
- [ ] `PriceTag`-Component (große, monospaced Ziffern)
- [ ] `BrandBadge`-Component (kleines Asset-basiertes Logo + Fallback-Initialen)
- [ ] `StationRowView` — Card mit Brand · Name · Entfernung · Preis
- [ ] `SearchView` — Adress-Bar, Filter-Bar, Liste, Loading- und Empty-States
- [ ] `StationDetailView` — Detail mit Mini-Map und Action-Buttons
- [ ] Dark-Mode prüfen, Dynamic Type prüfen

### Phase 4 — ViewModel & Verdrahtung *(1 Tag)*
- [ ] `SearchViewModel` (`@Observable`)
  - `query` (Adresse oder leer = Standort)
  - `radius`, `fuelType`, `sortMode` (mit `@AppStorage` für Defaults)
  - `state: .idle | .loading | .results([Station]) | .empty | .error(String)`
  - `func search() async`
- [ ] Debounce bei Adress-Eingabe (kein Auto-Search bei jedem Tipper, sondern bei Submit + Button)
- [ ] **Tests:** `SearchViewModelTests` mit Stub-Client und Stub-Location

### Phase 5 — Polish *(0,5–1 Tag)*
- [ ] App-Icon (Platzhalter SF-Symbol-basiert, später echtes Icon)
- [ ] Haptic-Feedback bei Suche
- [ ] Skeleton-Loader statt einfachem Spinner
- [ ] Smooth-Scroll-Animationen
- [ ] Pull-to-Refresh
- [ ] CC-BY-Lizenz im About-Screen
- [ ] Fehler-UI: konkrete Texte, „Nochmal versuchen"-Button

### Phase 6 — Testen mit dir *(offen)*
- [ ] Build auf physischem iPhone
- [ ] Echte API-Aufrufe verifizieren
- [ ] Feedback einsammeln → Issues sammeln in einer `TODO.md`

---

## Definition-of-Done für den MVP

- [ ] Suche um aktuellen Standort funktioniert (E5/E10/Diesel, 1–25 km)
- [ ] Suche um eingetippte Adresse funktioniert
- [ ] Sortierung Preis ↔ Entfernung umschaltbar
- [ ] Detail-View zeigt alle drei Spritsorten und Öffnungs-Status
- [ ] „In Karten öffnen" funktioniert
- [ ] Funktioniert in Dark + Light Mode
- [ ] Keine Crashes bei: kein Permission, kein Internet, leere Resultate, ungültige Adresse
- [ ] CC-BY-Quelle nennt MTS-K im About-Screen
- [ ] API-Key liegt nicht im Repo (in `Secrets.xcconfig`, gitignored)
- [ ] Unit-Tests für `TankerkoenigClient` und `SearchViewModel` grün

---

## Spätere Features — Vorschau

### Feature 2 — Routensuche
- MapKit `MKDirections` für Route A→B
- Polyline samplen (z.B. alle 5 km), pro Sample-Punkt `list.php` mit kleinem Radius
- Deduplizieren → günstigste N Stationen entlang der Route
- Karten-Ansicht mit Pins + Route-Linie

### Feature 3 — Günstigster Preis im Radius
- Im Grunde Spezialfall von Feature 1 mit `sort=price` und Top-1-Anzeige
- Eigener „Glance"-Screen: ein riesiger Preis, eine Tankstelle, ein Tap → Navigieren
- Optional: Home-Screen-Widget, das das gleiche zeigt

---

## Offene Fragen / nächste Entscheidungen

1. **App-Name & Bundle-ID** — z.B. `de.kilianvolz.tankapp` ok? Eigener Name gewünscht?
2. **Brand-Logos** — Pragmatisch: Initialen-Badge mit Brand-Farbe als Fallback. Echte Logos später, falls rechtlich okay.
3. **Telemetrie** — Bewusst keine im MVP. Ok?
4. **iCloud-Sync für Settings** — Erstmal nein, geht später per `NSUbiquitousKeyValueStore` einfach nach.

---

## Reihenfolge der Umsetzung (Vorschlag)

1. Du fragst den Tankerkönig-API-Key per Mail an *(läuft parallel, kommt meist innerhalb 24 h)*
2. Ich baue Phase 0–4 mit einem Stub-API-Client (Fixture-Daten)
3. Du trägst API-Key in `Secrets.xcconfig` ein
4. Phase 5 + erste End-to-End-Tests gemeinsam
5. Du testest auf deinem iPhone, sammelst Feedback
6. Iteration → dann Feature 2 & 3
