# RetroHub

[![CI](https://github.com/akairostech/RetroHub/actions/workflows/ci.yml/badge.svg)](https://github.com/akairostech/RetroHub/actions/workflows/ci.yml)

Gestor de ROMs retro para Windows, Linux y Android, construido con Flutter.

- **Biblioteca**: escanea `roms/{plataforma}` de tu carpeta de biblioteca y muestra las carátulas de `storage/downloaded_media`. Si no existe la estructura, RetroHub la crea por ti.
- **Servidor** (solo escritorio): comparte ROMs, BIOS y partidas en tu red local. Se protege con un PIN y se anuncia por UDP para que los otros dispositivos lo encuentren.
- **Descargar**: explora la biblioteca de otro dispositivo y descarga juegos o las BIOS que te falten.
- **Scraper**: descarga carátulas, capturas y pantallas de título, y metadatos (desarrollador, editor, género, año, jugadores) desde libretro, sin cuenta. Con credenciales gratuitas de IGDB agrega descripciones y cubre consolas modernas. Las imágenes se guardan en `storage/downloaded_media`, la estructura estándar que también usan otros frontends.
- **Partidas**: sincroniza `saves/` en ambos sentidos con el servidor. Nunca borra archivos. Antes de sobrescribir uno guarda una copia en `saves/.retrohub_history`, y te pregunta qué hacer si un archivo cambió en los dos lados.

## Descargar

La última versión para Android (`.apk`), Windows (`.zip`) y Linux/SteamOS (`.tar.gz`) está siempre en **[Releases](https://github.com/akairostech/RetroHub/releases/latest)**.

Para publicar una versión nueva: en GitHub, *Releases → Draft a new release*, crea una etiqueta como `v0.4.0` y pulsa *Publish*. GitHub Actions compila y adjunta los tres ejecutables en unos 15 minutos.

## Instalar en SteamOS / Linux

1. Descarga `RetroHub-linux-x64.tar.gz` de la página de [Releases](https://github.com/akairostech/RetroHub/releases/latest) (en Modo Escritorio).
2. Descomprímelo donde quieras (por ejemplo en `~/Applications`).
3. Ejecuta `install-desktop-entry.sh` (clic derecho → Ejecutar, o desde la terminal) para que aparezca en el menú.
4. Opcional: en Steam, *Añadir un juego que no es de Steam* → RetroHub, para abrirlo en Modo Juego.

La app detecta sola una biblioteca existente (incluida la de la tarjeta SD) y, si no hay ninguna, te ofrece crearla.

## Desarrollo

Requisitos en Windows: Flutter, Visual Studio con "Desarrollo para el escritorio con C++" (incluyendo *C++ CMake tools*), Android Studio (para el SDK de Android) y el Modo de desarrollador de Windows activado.

```powershell
.\dev.ps1   # trae los cambios de GitHub, analiza, prueba y abre la app
```

En Android: conecta el teléfono con depuración USB y ejecuta `flutter run`. En la app, concede "Acceso a todos los archivos" y elige tu carpeta Emulation.

## Estructura de la biblioteca

```
Emulation/
  roms/{plataforma}/        juegos (snes, psx, gc, switch…)
  bios/                     BIOS y firmware
  saves/{emulador}/         partidas guardadas (se sincronizan)
  storage/downloaded_media/ carátulas, capturas y pantallas de título
  storage/retrohub/         metadatos, cachés y registros de RetroHub
```

## Estructura del código

```
lib/
  core/      modelos, plataformas, escaneo de biblioteca, hashes, estructura de carpetas
  compat/    detección de bibliotecas y perfiles de emuladores ya instalados
  launch/    botón Jugar (perfiles de lanzamiento, scripts y Android)
  input/     lectura de mandos
  net/       servidor HTTP (shelf), cliente y descubrimiento UDP
  sync/      cola de descargas y sincronización de saves
  ui/        pantallas y widgets
```

## API del servidor (puerto 8787 por defecto)

Todas las rutas requieren el PIN en la cabecera `x-retrohub-pin` o en `?pin=`.

| Método | Ruta | Uso |
|---|---|---|
| GET | `/api/info` | nombre del servidor y cantidad de juegos |
| GET | `/api/library` | plataformas y juegos |
| GET | `/api/cover?platform=&file=` | carátula |
| GET | `/api/tree?area=roms\|bios\|saves&path=&hash=1` | lista de archivos (con SHA-1 opcional) |
| GET | `/api/file?area=&path=` | descarga |
| PUT | `/api/file?area=saves&path=` | subida (solo saves) |

## Créditos

- Íconos de PlayStation, Sega y Atari: [Simple Icons](https://simpleicons.org) (CC0 1.0). Las marcas pertenecen a sus dueños.
- Íconos de Switch, Wii, Wii U, Game Boy, Xbox y mandos: [Material Design Icons](https://pictogrammers.com/library/mdi/) (Pictogrammers Free License).
- Ícono de la app: diseño original de RetroHub.
