# RetroHub

Gestor de ROMs retro para Windows, Linux y Android, construido con Flutter.

- **Biblioteca**: escanea `roms/{plataforma}` de tu carpeta EmuDeck y muestra las carátulas que ES-DE ya descargó en `storage/downloaded_media`. Si una carátula no existe, intenta usar libretro-thumbnails.
- **Servidor** (solo escritorio): comparte ROMs, BIOS y partidas en tu red local. Se protege con un PIN y se anuncia por UDP para que los otros dispositivos lo encuentren.
- **Descargar**: explora la biblioteca de otro dispositivo y descarga juegos o las BIOS que te falten.
- **Partidas**: sincroniza `saves/` en ambos sentidos con el servidor. Nunca borra archivos. Antes de sobrescribir uno guarda una copia en `saves/.retrohub_history`, y te pregunta qué hacer si un archivo cambió en los dos lados.

## Primera vez

Requisitos en Windows: Flutter, Visual Studio con "Desarrollo para el escritorio con C++" (incluyendo *C++ CMake tools*) y el Modo de desarrollador de Windows activado.

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1   # solo la primera vez
.\dev.ps1                                              # analiza, prueba y abre la app
```

Para Android: conecta el teléfono con depuración USB y ejecuta `flutter run`. En la app, concede "Acceso a todos los archivos" y elige tu carpeta Emulation.

## Estructura del código

```
lib/
  core/      modelos, plataformas, escaneo de biblioteca, hashes, rutas de EmuDeck
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
