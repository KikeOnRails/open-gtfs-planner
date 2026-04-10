# Open GTFS Planner - Flutter

Una implementación Flutter del Open GTFS Planner: herramienta de visualización y simulación de datos GTFS (General Transit Feed Specification) para transporte público.

Diseñada principalmente para **web** y **escritorio** (Linux, macOS, Windows).

![Estado](https://img.shields.io/badge/status-alpha-red)
[![Flutter](https://img.shields.io/badge/Flutter-3.22+-blue.svg)](https://flutter.dev)

## 🌟 Funcionalidades

- **📁 Gestión de proyectos** — Crea y gestiona múltiples proyectos, cada uno con sus propios archivos GTFS.
- **📂 Importación GTFS** — Importa archivos GTFS en formato `.zip` o como carpeta descomprimida. Soporta múltiples archivos GTFS por proyecto.
- **🗺️ Mapa interactivo** — Visualiza rutas, shapes y paradas sobre OpenStreetMap (libre y sin coste).
- **🚌 Simulación en tiempo real** — Barra de simulación con fecha/hora seleccionable, control de reproducción y velocidades × 1, ×2, ×3, ×5.
- **📍 Posición teórica de vehículos** — Interpolación geodésica para calcular la posición de cada vehículo en el instante de simulación.
- **🚏 Información de paradas** — Al seleccionar una parada, muestra las próximas llegadas filtradas por los servicios activos de ese día.
- **🚍 Información de viajes** — Al seleccionar un vehículo, muestra la línea, cabecera, progreso de ruta y paradas.
- **📅 Servicios activos** — Calcula automáticamente los servicios activos según el calendario GTFS (`calendar.txt` + `calendar_dates.txt`) para la fecha de simulación.
- **🌙 Tema oscuro moderno** — Interfaz oscura con colores Material 3 personalizados.

## 🛠 Tecnologías

| Componente | Paquete |
|---|---|
| Base de datos local | `sqflite` + `sqflite_common_ffi` |
| Mapas | `flutter_map` (OpenStreetMap, libre) |
| Estado | `flutter_riverpod` |
| Navegación | `go_router` |
| Importación ZIP | `archive` |
| Parseo CSV | `csv` |
| Selector de archivos | `file_picker` |
| Tema de fuentes | `google_fonts` (Inter) |

## 📋 Requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) **≥ 3.22.0**
- Dart SDK **≥ 3.3.0**
- Para escritorio Linux: `sudo apt-get install libsqlite3-dev`
- Para escritorio Windows: las DLLs de SQLite se incluyen automáticamente

## 🚀 Instalación y ejecución

### 1. Instalar dependencias

```bash
cd flutter_app
flutter pub get
```

### 2. Ejecutar en escritorio (Linux/macOS/Windows)

```bash
# Linux
flutter run -d linux

# macOS
flutter run -d macos

# Windows
flutter run -d windows
```

### 3. Ejecutar en web

```bash
flutter run -d chrome
# o
flutter run -d web-server --web-port 8080
```

### 4. Compilar para producción

```bash
# Web
flutter build web --release

# Linux
flutter build linux --release

# Windows
flutter build windows --release
```

## 📂 Cómo importar GTFS

1. Abre la aplicación y crea un nuevo proyecto.
2. En el panel izquierdo "Capas GTFS", haz clic en el botón **+**.
3. Selecciona un archivo **GTFS `.zip`** o una **carpeta** con los ficheros `.txt` descomprimidos.
4. Espera a que la importación finalice (puede tomar unos segundos/minutos según el tamaño).
5. Usa los iconos de visibilidad en cada ruta para activar shapes y simulación.

## 🗺️ Interfaz

```
┌─────────────────────────────────────────────────────────────────┐
│  ← Proyectos  |  🚍 Nombre del Proyecto    •  X vehículos       │
├─────────────┬──────────────────────────────┬────────────────────┤
│             │   [ Barra de Simulación ]     │                    │
│  Capas GTFS │                               │    Viajes          │
│  ├ GTFS 1   │   ┌─────────────────────┐    │    Paradas         │
│  │ └ Línea A │   │                     │    │    GTFS Info       │
│  │ └ Línea B │   │    MAPA OSM         │    │                    │
│  └ GTFS 2   │   │   (vehículos +      │    │  [Info Parada /    │
│             │   │    paradas)         │    │   Info Vehículo]   │
│             │   │                     │    │                    │
│             │   └─────────────────────┘    │                    │
└─────────────┴──────────────────────────────┴────────────────────┘
```

## 📊 Formato GTFS soportado

La aplicación soporta los siguientes ficheros del estándar GTFS:

| Fichero | Descripción |
|---|---|
| `agency.txt` | Operadoras de transporte |
| `stops.txt` | Paradas |
| `routes.txt` | Líneas/Rutas |
| `trips.txt` | Viajes (expediciones) |
| `stop_times.txt` | Horarios por parada |
| `shapes.txt` | Trazado geográfico de rutas |
| `calendar.txt` | Calendarios semanales |
| `calendar_dates.txt` | Excepciones de calendario |

## 🔧 Estructura del proyecto

```
flutter_app/
├── lib/
│   ├── main.dart                    # Punto de entrada
│   ├── app.dart                     # App + Router
│   ├── core/
│   │   ├── database/
│   │   │   ├── app_database.dart    # SQLite schema
│   │   │   └── gtfs_repository.dart # Repositorio de datos
│   │   ├── theme/
│   │   │   └── app_theme.dart       # Tema Material 3 oscuro
│   │   └── utils/
│   │       ├── interpolation_helper.dart  # Interpolación geodésica
│   │       └── gtfs_importer.dart         # Importador GTFS
│   ├── models/
│   │   ├── project_model.dart
│   │   └── gtfs_models.dart         # Todos los modelos GTFS
│   ├── providers/
│   │   ├── project_providers.dart   # Estado de proyectos y capas
│   │   └── simulation_providers.dart # Estado de simulación
│   └── screens/
│       ├── projects/
│       │   └── projects_screen.dart # Pantalla de proyectos
│       └── main/
│           ├── main_screen.dart     # Pantalla principal
│           └── widgets/
│               ├── simulation_bar.dart   # Barra de simulación
│               ├── layers_panel.dart     # Panel izquierdo: capas
│               ├── map_widget.dart       # Mapa con vehículos/paradas
│               ├── info_panels.dart      # Paneles de info (parada/viaje)
│               └── right_panel.dart      # Panel derecho: viajes/paradas
├── web/
│   ├── index.html
│   └── manifest.json
└── pubspec.yaml
```

## 📝 Licencia

MIT — Ver [LICENSE](../LICENSE)
