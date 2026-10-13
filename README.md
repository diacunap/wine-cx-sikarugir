# wine-cx-sikarugir

Compila un **engine de Sikarugir** a partir de las **fuentes oficiales de CrossOver** (LGPL, publicadas por CodeWeavers), sin licencia de CrossOver y sin depender de un launcher armado por otra persona.

Resultado: `dist/WS12WineCX26.3_1.tar.xz`, un engine que se usa en Sikarugir igual que los oficiales, pero con los hacks de CodeWeavers que necesita Battle.net y los juegos de Blizzard:

- `WINE_SIMULATE_WRITECOPY` (CW Hack 22996): sin esto, el instalador y el login de Battle.net (CEF) se caen o quedan en blanco
- `CX_APPLEGPTK_LIBD3DSHARED_PATH`: el mismo puente a D3DMetal que usa Sikarugir
- msync, `WINE_LARGE_ADDRESS_AWARE`, `WINE_HEAP_ZERO_MEMORY`

El engine **no trae D3DMetal ni DXMT**: esos los pone el wrapper de Sikarugir (`Frameworks/renderer/`). Por eso el engine es Wine puro y se puede compartir.

## Requisitos

- Mac Apple Silicon, Command Line Tools (`xcode-select --install`)
- Homebrew:
  ```
  brew install mingw-w64 bison flex ninja cmake pkgconf autoconf automake libtool llvm lld nasm freetype
  ```
  (opcional: `brew install ccache` acelera recompilaciones, pero ocupa unos GB)
- Rosetta 2 (solo para probar el resultado; para compilar no hace falta)
- **~15 GB libres** mientras compila. Al final puedes borrar `build/` con `./build.sh --clean`

## Uso

```
./build.sh                    # ~30-60 min en un M4; logs en build/logs/
./scripts/install-engine.sh   # copia el engine a ~/Library/Application Support/Sikarugir/Engines
./build.sh --clean            # libera los ~12 GB de build/
```

Si un paso falla, `build.sh` muestra las últimas líneas del log. Al volver a correrlo, los pasos que ya terminaron se saltan.

## Sin compilar: bajar el engine de Releases

GitHub Actions compila el engine en un runner macOS ARM cada vez que cambian `build.sh`,
`config.sh` o `scripts/` en `main` (o a mano: Actions → build-engine → Run workflow) y lo publica
en [Releases](../../releases) con su `.sha256`. Bajas el `.tar.xz`, lo copias a
`~/Library/Application Support/Sikarugir/Engines/` y listo. Gratis porque el repo es público.

## Configurar el wrapper (Battle.net / D2R)

Probado con Battle.net 2.53 + Diablo II: Resurrected en un M4, macOS 27, Sikarugir template 1.0.21.

1. Sikarugir Creator → **Change** engine → `WS12WineCX26.3_1` → Create (o, en un wrapper existente: Configure → Tools → Change Engine)
2. Install Software → `Battle.net-Setup.exe` → instalar en C:. Al terminar, el instalador abre Battle.net
   solo y sin los flags de abajo: se queda en el logo girando. Ciérralo (o `wineserver -k`).
3. Configurar el wrapper. Son estas claves de `Contents/Info.plist` (o lo mismo desde Configure):

   | Clave | Valor |
   |---|---|
   | `Program Name and Path` | `/Program Files (x86)/Battle.net/Battle.net.exe` (no el Launcher) |
   | `Program Flags` | `--in-process-gpu --use-gl=swiftshader` |
   | `D3DMETAL` | `1` |
   | `WINEMSYNC` / `WINEESYNC` | `0` / `0` |
   | `WINEDEBUG` | `-all` |
   | `CLI Custom Commands` | `export WINE_SIMULATE_WRITECOPY=1 WINE_LARGE_ADDRESS_AWARE=1 WINE_HEAP_ZERO_MEMORY=1 ROSETTA_ADVERTISE_AVX=1 DOTNET_EnableWriteXorExecute=0` |

   ```
   P=~/Applications/Sikarugir/<wrapper>.app/Contents/Info.plist
   plutil -replace "Program Flags" -string "--in-process-gpu --use-gl=swiftshader" "$P"
   plutil -replace D3DMETAL -integer 1 "$P"
   plutil -replace WINEMSYNC -integer 0 "$P"; plutil -replace WINEESYNC -integer 0 "$P"
   plutil -replace WINEDEBUG -string "-all" "$P"
   plutil -replace "CLI Custom Commands" -string "export WINE_SIMULATE_WRITECOPY=1 WINE_LARGE_ADDRESS_AWARE=1 WINE_HEAP_ZERO_MEMORY=1 ROSETTA_ADVERTISE_AVX=1 DOTNET_EnableWriteXorExecute=0" "$P"
   ```

   No pongas `WINEDLLOVERRIDES` ahí: el launcher de Sikarugir la arma él para cargar D3DMetal.
4. Abrir el wrapper, iniciar sesión, instalar D2R desde el cliente.

## Problemas conocidos (y por qué la config es así)

- **Battle.net es de 32 bits** (`Battle.net.exe` es PE32). D3DMetal solo trae x86_64, así que al
  cliente no le sirve; D2R (64 bits) sí lo usa. La UI del cliente (CEF/Chromium) tiene que dibujar
  por software:
  - sin flags, el proceso GPU de CEF cae en wined3d/OpenGL y gira al ~200% de CPU para siempre
    (`GL_INVALID_OPERATION from glClientWaitSync`): logo girando.
  - con `"HardwareAcceleration": "false"` en `Battle.net.config`, ANGLE no inicializa nada y el
    panel de login queda **negro**.
  - con DXVK de 32 bits en `syswow64` + override `n,b`, el loader de CrossOver igual carga su
    `d3d11` builtin.
  - `--in-process-gpu --use-gl=swiftshader` (la receta de [D4Mac](https://github.com/MichaelLod/D4Mac))
    funciona.
- **msync/esync apagados**: con ellos la descarga de Battle.net se arrastra a ~4 KB/s bajo Rosetta.
- **Wrapper movido/renombrado = Wine no arranca** (`could not load ntdll.so` desde
  `.../T/winetemp-…/`). CW Hack 22144 crea `$TMPDIR/winetemp-<inode-del-loader>/ntdll.so` como
  symlink la primera vez y nunca lo actualiza; Sikarugir Creator arma el wrapper en `$TMPDIR` y
  después lo mueve (mismo inode), así que el symlink queda apuntando a la ruta vieja. También
  explica el "No new executables found!" al instalar. Arreglo:
  ```
  rm -rf "$(getconf DARWIN_USER_TEMP_DIR)"/winetemp-*
  ```
- **UI pixelada**: Wine dibuja a 1x y macOS lo escala. Opcional: `HKCU\Software\Wine\Mac Driver`
  `RetinaMode=y` + `HKCU\Control Panel\Desktop` `LogPixels=192` (ojo: D2R también renderiza a 2x).
- **D2R**: no hagas ⌘-Tab en medio de la partida (crash conocido). El primer arranque puede
  colgarse compilando shaders: forzar salida y volver a abrir.

## Problemas al compilar

- `gmp configure: could not find a working compiler` con
  `ld: tapi error: ... unknown architecture arm64e.x1` → `xcode-select` apunta a un Xcode viejo cuyo
  `ld` no entiende el SDK de macOS 27. Usar las Command Line Tools:
  `sudo xcode-select -s /Library/Developer/CommandLineTools` (o actualizar Xcode).

## Actualizar a un CrossOver nuevo

En `config.sh`, cambia `CX_VERSION` y `CX_SHA256` (la checksum del tarball en
<https://media.codeweavers.com/pub/crossover/source/>) y vuelve a correr `./build.sh`.

## Qué se cambió del original

Los scripts de build vienen de [steamplay-mac](https://github.com/thedankest/steamplay-mac) (GPL-3.0, por eso este repo también es GPL-3.0). Se les sacó todo lo de Steam (lsteamclient, NotProton, steam.exe), las fuentes van **sin parches extra** (lo mismo que trae CrossOver) y se agregó el empaquetado en formato de engine de Sikarugir (`wswine.bundle`).

Licencias: Wine/CrossOver sources LGPL-2.1; gnutls LGPL; FFmpeg LGPL; SDL2 zlib; MoltenVK Apache-2.0; Wine Mono/Gecko según sus licencias.
