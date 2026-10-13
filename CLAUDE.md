# Colimy

App de macOS (barra de menú + ventana) para gestionar Colima y Docker: stacks de Compose, contenedores, logs, terminal dentro del contenedor. Swift + AppKit/SwiftUI, sin dependencias externas en el código. Mismo esqueleto que Wallpy (`../wallpapers`): instalador, autoactualizador, workflows y tema. Repo: https://github.com/drarekx/colimy (público).

## Compilar y ejecutar

```sh
swift build                      # debug, comprobación rápida
./build-app.sh                   # release universal (arm64 + x86_64) → build/Colimy.app + build/Colimy.zip
VERSION=1.2.0 ./build-app.sh     # versión en Info.plist (por defecto 1.0.0)
open build/Colimy.app
.build/debug/Colimy --snapshot /tmp/x.png [--section stacks|containers|colima|settings] [--select <contenedor|stack>] [--tab details]
```

- Requisitos: macOS 14+, Xcode 16+. `Package.swift` usa tools 5.10 (modo Swift 5).
- `--snapshot` (solo en debug, `Snapshot.swift`) guarda una imagen de la ventana y sale: sirve para revisar la interfaz sin permiso de grabación de pantalla.
- La copia instalada vive en `/Applications/Colimy.app`; la de `build/` tiene versión 1.0.0 (su actualizador siempre ve versiones nuevas). Cierra una antes de abrir otra.
- No hay tests. Verificar compilando (`swift build` y `swift build --arch x86_64`) y lanzando la app.

## GitHub: ramas y versiones

Igual que Wallpy: `main` protegida, cambios por PR con squash y comprobación `build` (`.github/workflows/build.yml`: compila arm64 + x86_64 y verifica que `en` y `ca` tienen las mismas claves y que todo `tr()` está traducido). Publicar: `git tag v1.2.0 && git push origin v1.2.0` → `release.yml` crea el release con `Colimy.zip` y `Colimy.zip.sha256`; las apps instaladas se actualizan solas (`Updater.swift`). Instalador: `install.sh` (`curl … | bash`). La app no está notarizada (firma ad-hoc).

## Estructura (`Sources/Colimy/`)

| Archivo | Qué hace |
|---|---|
| `main.swift`, `AppDelegate.swift` | Arranque, app accesoria (`LSUIElement`), menú de barra con stacks y contenedores en submenús, menú principal oculto (Edición), ventana principal |
| `ExternalTools.swift` | Localiza `colima` / `docker` y los ejecuta (`ToolProcess`: líneas de stdout, stderr para errores, cancelable) |
| `Docker.swift` | Modelos (`Container`, `Stack`, `PortMapping`, `ContainerStats`, `ContainerDetail`) y llamadas a la CLI de Docker |
| `Colima.swift` | Perfiles (`colima list --json`), socket de Docker, arrancar/parar/reiniciar |
| `DockerStore.swift` | Estado observable: refresco por temporizador y por `docker events`, estadísticas, acciones y errores |
| `LogStream.swift` | `docker logs -f` / `docker compose logs -f` y la vista de texto (`NSTextView`) que añade líneas sin redibujar todo |
| `Terminal.swift` | Abre comandos (shell del contenedor, logs) en Terminal / iTerm / Ghostty mediante un `.command` temporal |
| `MainView.swift` | Navegación (`MainSelection`), barra lateral, tarjeta de Colima, zona de listas + inspector |
| `ListsView.swift` | Lista de stacks (tarjetas plegables) y de contenedores, filas, acciones y menús |
| `InspectorView.swift` | Panel derecho: logs y detalles del contenedor o stack seleccionado |
| `ColimaView.swift` | Perfiles de Colima y salida de la última operación |
| `SettingsView.swift`, `Settings.swift` | Ajustes (`UserDefaults` `com.egluu.colimy`) y login item |
| `Theme.swift` | Colores y componentes del estilo oscuro compartido con Wallpy (`ColimyButtonStyle`, `SegmentedControl`, `SwitchRow`, `colimyCard`, `Badge`, `StatusDot`) |
| `Updater.swift` | Autoactualización desde GitHub Releases con verificación SHA-256 |
| `Localization.swift` | Idiomas (en, es, ca): `tr()`, `Localizer`, tablas de traducción |

## Cómo habla con Docker

- Todo pasa por la CLI con `DOCKER_HOST` = socket del perfil de Colima elegido (`colima status -p <perfil> --json` → `docker_socket`), sin depender del contexto activo de Docker.
- `docker ps -a` con un `--format` JSON propio que saca las etiquetas de Compose con `.Label` (la columna `Labels` es un texto separado por comas y los valores también llevan comas).
- Los stacks se reconstruyen agrupando contenedores por `com.docker.compose.project`. Las acciones usan `docker compose -p <nombre> --project-directory <dir> -f <archivos>`; si los archivos ya no existen, solo `-p` (sirven start/stop/restart/down, no `up`).
- `docker events` filtrado a eventos de ciclo de vida (sin `exec_*`, que los healthchecks lanzan continuamente) dispara un refresco agrupado.
- `docker stats --no-stream` tarda ~2 s: solo se pide con la ventana visible.

## Convenciones

- Código, comentarios y commits en inglés. Interfaz en castellano, inglés y catalán.
- **Todo texto visible pasa por `tr("…")`** (o `tr("… %@ …", arg)`). La clave es el texto en castellano; añadir la traducción a las tablas `en` y `ca` de `Localization.swift` con los mismos `%@`/`%d`. Nunca interpolar dentro de un texto traducible. Las claves no pueden repetirse (un diccionario literal con claves duplicadas revienta al arrancar).
- El idioma cambia en caliente (`.id(localizer.language)`). Probar otro idioma: `Colimy -appLanguage ca`.
- Estilo visual: usar siempre `Theme` y sus componentes, nunca colores sueltos.
- Tipos de estado de UI en `@MainActor`; los procesos corren en `ToolProcess` (hilos de fondo).
- Antes de borrar o bajar algo (contenedor, `down`, parar Colima con contenedores en marcha) se pide confirmación con `confirm()`.
- Mantener el README al día cuando cambian funciones visibles.

## Cosas que ya costaron (no repetir)

- **Sin menú principal no funciona ⌘V** en los campos de texto (app accesoria): `setupMainMenu()` crea un menú Edición invisible.
- **`NSHostingController` encoge la ventana**: `sizingOptions = []` y `setContentSize` después. El nombre de autosave del marco se pone **después** de `setFrameUsingName`, o guarda el marco inicial y la ventana sale al tamaño mínimo.
- `main.swift` envuelve el arranque en `MainActor.assumeIsolated` porque `AppDelegate` es `@MainActor`.
- Las apps abiertas desde Finder tienen un PATH mínimo: `ExternalTool.childPath` añade Homebrew para que `colima` encuentre `limactl` y `docker` su plugin de compose.
- Leer stdout/stderr con lecturas bloqueantes en hilos propios y esperar a EOF antes de dar el proceso por terminado; con `readabilityHandler` se perdía la última línea.

## Pruebas manuales

- El Docker del usuario tiene stacks reales en marcha: no pararlos ni bajarlos para probar. Usar un stack desechable (`docker compose -p colimytest …` con `nginx:alpine`) y borrarlo con `down` al acabar.
- No parar ni reiniciar Colima sin permiso: para todos los contenedores del usuario.
