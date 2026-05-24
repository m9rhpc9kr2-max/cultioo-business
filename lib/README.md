# Cultioo Business App - Ordnerstruktur

## 📁 Neue modulare Struktur

```
lib/
├── auth/                          # Authentifizierung
│   ├── pages/                     # Login, Signup, Register, 2FA
│   └── widgets/                   # 2FA Bottom Sheet
│
├── modules/                       # Hauptmodule
│   ├── business/                  # Business Management
│   │   ├── pages/                 # Business-spezifische Seiten
│   │   │   ├── business_home_page.dart      # Business Dashboard
│   │   │   ├── main_navigation.dart         # Business Navigation
│   │   │   ├── products_page.dart           # Produktmanagement
│   │   │   ├── orders_page.dart             # Bestellungsmanagement
│   │   │   └── settings_page.dart           # Business Settings
│   │   └── widgets/               # Business-spezifische Widgets
│   │
│   └── delvioo/                   # Delvioo Driver Module
│       ├── pages/                 # Driver-spezifische Seiten
│       │   └── delvioo_home_page.dart       # Driver Dashboard
│       └── widgets/               # Driver-spezifische Widgets
│
├── shared/                        # Geteilte Komponenten
│   ├── services/                  # API Service, App Settings
│   ├── widgets/                   # Glass Effect, etc.
│   └── models/                    # Datenmodelle
│
├── app_router.dart                # Routing basierend auf User Type
└── main.dart                      # App Entry Point
```

## 🎯 Funktionalitäten

### Business Module
- **Dashboard**: Übersicht über Bestellungen, Umsatz
- **Produktmanagement**: Produkte erstellen, bearbeiten, verwalten
- **Bestellungsmanagement**: Bestellungen verfolgen, bearbeiten
- **Einstellungen**: Business-spezifische Konfiguration

### Delvioo Module
- **Driver Dashboard**: Online/Offline Status, Verdienste
- **Aufträge**: Aktive Lieferungen, Auftragshistorie
- **Zeitplanung**: Arbeitszeiten, Verfügbarkeit
- **Support**: Driver-spezifischer Support

## 🔄 Navigation Flow

1. **Login** → User Type Detection
2. **Business User** → Business Dashboard mit Tabs
3. **Driver User** → Delvioo Driver Interface
4. **App Router** → Automatische Weiterleitung basierend auf User Type

## 📱 User Types

- **Business**: Komplette Business-Management-Suite
- **Driver**: Delvioo-Driver-Interface für Lieferfahrer

## 🛠 Technische Details

- Modulare Architektur für bessere Wartbarkeit
- Getrennte Navigation für verschiedene User Types
- Geteilte Services und Widgets
- Provider-basiertes State Management
