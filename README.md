# Colimy

Gestiona [Colima](https://github.com/abiosoft/colima) y Docker desde la barra de menú de macOS. Ve tus stacks de Docker Compose y tus contenedores, arráncalos, páralos, reinícialos, mira sus logs en directo y abre una terminal dentro de cualquiera con un clic.

## Instalar

Abre Terminal y pega:

```sh
curl -fsSL https://raw.githubusercontent.com/drarekx/colimy/main/install.sh | bash
```

El instalador descarga la última versión, la copia en `/Applications`, la abre y, si tienes [Homebrew](https://brew.sh), instala `colima`, `docker` y `docker-compose` si faltan (si ya tienes el cliente de Docker de Docker Desktop, solo instala Colima). Para no instalar nada más que la app:

```sh
curl -fsSL https://raw.githubusercontent.com/drarekx/colimy/main/install.sh | bash -s -- --no-deps
```

Colimy se actualiza sola: busca versiones nuevas al arrancar y una vez al día (o desde el menú → **Buscar actualizaciones…**), comprueba la descarga con su SHA-256 y se reinicia ya actualizada. Se puede desactivar en Ajustes. Volver a ejecutar el comando de instalación también actualiza.

**Instalación manual:** descarga `Colimy.zip` de [Releases](https://github.com/drarekx/colimy/releases/latest), descomprímelo y mueve `Colimy.app` a Aplicaciones. La app no está notarizada por Apple, así que la primera vez ábrela con clic derecho → **Abrir** (o Ajustes del Sistema → Privacidad y seguridad → **Abrir igualmente**).

Requisitos: macOS 14 (Sonoma) o posterior, Apple Silicon o Intel. Colima y el cliente de Docker (`brew install colima docker docker-compose`).

## Qué hace

- **Colima**: estado del perfil (CPU, memoria, disco, arquitectura), arrancar, parar y reiniciar, con la salida de `colima` en directo. Si tienes varios perfiles, eliges cuál usar.
- **Stacks**: tus proyectos de Docker Compose agrupados, con cuántos servicios están en marcha y sus puertos. Arrancar (`up -d`), parar, reiniciar, bajar (`down`), descargar imágenes (`pull`), abrir la carpeta en Finder o en una terminal.
- **Contenedores**: estado y salud, puertos (clic para abrir `localhost:<puerto>`), CPU y memoria en directo. Arrancar, parar, reiniciar, pausar, forzar parada y eliminar.
- **Terminal dentro del contenedor**: abre `docker exec -it` en Terminal, iTerm o Ghostty, con bash si el contenedor lo tiene y si no sh.
- **Logs en directo** de un contenedor o de un stack entero, con filtro, copiar y abrir en Terminal.
- **Detalles**: comando, imagen, redes con su IP, montajes, política de reinicio y variables de entorno (ocultas hasta que las pides).
- **Barra de menú**: estado de Colima y cada stack con sus contenedores en submenús, para hacer lo básico sin abrir la ventana.
- Se entera al momento de los cambios hechos desde fuera (`docker events`), abrir al iniciar sesión e **idiomas**: castellano, inglés y catalán.

## Dónde guarda las cosas

- Ajustes: `defaults read com.egluu.colimy`
- No guarda nada más: todo se lee de Colima y Docker cada vez.

## Desinstalar

```sh
osascript -e 'quit app "Colimy"'
rm -rf /Applications/Colimy.app
defaults delete com.egluu.colimy
```

Colima, Docker y tus contenedores no se tocan.

## Compilar desde el código

Necesitas Xcode 16 o posterior.

```sh
git clone https://github.com/drarekx/colimy.git
cd colimy
./build-app.sh          # deja build/Colimy.app y build/Colimy.zip
open build/Colimy.app
```

Para publicar una versión nueva, crea y sube una etiqueta; GitHub Actions compila la app y crea el release con el zip:

```sh
git tag v1.0.1 && git push origin v1.0.1
```
