## Descargas

| Sistema | Archivo | Cómo instalar |
|---|---|---|
| Windows | `RetroHub-windows.zip` | Descomprime y abre `RetroHub.exe` |
| Android | `RetroHub-android.apk` | Ábrelo en el teléfono (permite instalar apps de origen desconocido) |
| Linux / SteamOS | `RetroHub-linux-x64.tar.gz` | Descomprime y ejecuta `install-desktop-entry.sh` |

## Novedades de la 0.5

- **Crear biblioteca.** Si RetroHub no encuentra una biblioteca, te ofrece crearla con todas las carpetas: `roms/{plataforma}` para cada consola, `bios`, `saves` y las carpetas de imágenes. También completa las carpetas que falten en una biblioteca existente, sin tocar nada de lo que ya tienes.
- RetroHub ahora usa sus propios nombres en toda la aplicación; la compatibilidad con bibliotecas y emuladores ya instalados se mantiene.

## En la 0.4

- **Botón Jugar.** Detecta el emulador configurado para cada sistema. En Linux/SteamOS usa los scripts de `tools/launchers` y RetroArch. En Android abre RetroArch, PPSSPP, Dolphin, NetherSX2 o DuckStation. Puedes poner un comando propio por plataforma en Ajustes → Emuladores.
- **Navegación con mando** en Windows, Linux/SteamOS y Android: cruceta o stick para moverte, **A** abrir, **B** volver, **Y** jugar, **X** favorito, **LB/RB** cambiar de sección.
- **Favoritos y Recientes** en la barra de plataformas.
- **Ordenar** por nombre, año, género, tamaño o plataforma; la búsqueda también encuentra por género y desarrollador.
- **Buscar duplicados** (menú Herramientas): versiones repetidas del mismo juego y espacio que ocupan.
- **Verificar BIOS** (menú Herramientas): compara tus BIOS con la base de datos de libretro por su huella MD5.
