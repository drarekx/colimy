import Combine
import Foundation

/// Languages the UI is translated to. Spanish strings are the keys.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es, ca
    var id: String { rawValue }

    /// Shown in its own language, so anyone can find theirs.
    var nativeName: String {
        switch self {
        case .system: return tr("Sistema")
        case .en: return "English"
        case .es: return "Español"
        case .ca: return "Català"
        }
    }
}

final class Localizer: ObservableObject {
    static let shared = Localizer()

    @Published var choice: AppLanguage {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "appLanguage") }
    }

    private init() {
        choice = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
    }

    /// The language actually used: the chosen one, or the first supported system language (English otherwise).
    var language: AppLanguage {
        if choice != .system { return choice }
        for preferred in Locale.preferredLanguages {
            let code = String(preferred.prefix(2))
            if let match = AppLanguage(rawValue: code), match != .system { return match }
        }
        return .en
    }

    var locale: Locale { Locale(identifier: language.rawValue) }

    func translate(_ key: String) -> String {
        switch language {
        case .en: return Translations.en[key] ?? key
        case .ca: return Translations.ca[key] ?? key
        default: return key
        }
    }
}

/// Translated UI text. `key` is the Spanish text.
func tr(_ key: String) -> String {
    Localizer.shared.translate(key)
}

/// Translated format string (`%@`, `%d`) with arguments.
func tr(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.translate(key), locale: Localizer.shared.locale, arguments: args)
}

private enum Translations {
    static let en: [String: String] = [
        // Menus
        "Cerrar ventana": "Close Window",
        "Salir de Colimy": "Quit Colimy",
        "Edición": "Edit",
        "Deshacer": "Undo",
        "Rehacer": "Redo",
        "Cortar": "Cut",
        "Copiar": "Copy",
        "Pegar": "Paste",
        "Seleccionar todo": "Select All",
        "Buscar": "Find",
        "Colima en marcha (%@)": "Colima running (%@)",
        "Colima parado (%@)": "Colima stopped (%@)",
        "Falta instalar: %@": "Not installed: %@",
        "Colima no tiene ningún perfil": "Colima has no profiles",
        "Parar Colima": "Stop Colima",
        "Reiniciar Colima": "Restart Colima",
        "Arrancar Colima": "Start Colima",
        "No hay contenedores": "No containers",
        "Stacks": "Stacks",
        "Contenedores sueltos": "Standalone Containers",
        "Abrir Colimy…": "Open Colimy…",
        "Abrir al iniciar sesión": "Open at Login",
        "Actualizando…": "Updating…",
        "Buscar actualizaciones…": "Check for Updates…",
        "Invítame a un café…": "Buy Me a Coffee…",
        "Trabajando…": "Working…",
        "Arrancar": "Start",
        "Parar": "Stop",
        "Reiniciar": "Restart",
        "Ver logs…": "Show Logs…",
        "Mostrar en Finder": "Show in Finder",
        "Abrir terminal": "Open Terminal",
        "Abrir localhost:%@": "Open localhost:%@",
        "Reanudar": "Resume",
        "¿Parar Colima?": "Stop Colima?",
        "Se pararán los %d contenedores en marcha.": "The %d running containers will stop.",

        // Colima
        "Arrancando Colima…": "Starting Colima…",
        "Parando Colima…": "Stopping Colima…",
        "Reiniciando Colima…": "Restarting Colima…",
        "Colima": "Colima",
        "Actualizar": "Refresh",
        "Para crear otro perfil o cambiar CPU, memoria y disco, usa «colima start -p <nombre> --cpu 4 --memory 8» o «colima start --edit» en Terminal.": "To create another profile or change CPU, memory and disk, run “colima start -p <name> --cpu 4 --memory 8” or “colima start --edit” in Terminal.",
        "Colima aún no tiene ningún perfil": "Colima has no profiles yet",
        "Arrancarlo crea el perfil «default» con 2 CPU, 2 GB de memoria y Docker.": "Starting it creates the “default” profile with 2 CPUs, 2 GB of memory and Docker.",
        "Crear y arrancar": "Create and Start",
        "Última operación": "Last Operation",
        "Ocultar": "Hide",
        "En marcha": "Running",
        "Parado": "Stopped",
        "En uso": "In use",
        "Usar este perfil": "Use This Profile",
        "CPU": "CPU",
        "Memoria": "Memory",
        "Disco": "Disk",
        "Arquitectura": "Architecture",
        "Motor": "Runtime",
        "Dirección": "Address",

        // Errors
        "No se encontró el contenedor.": "Container not found.",
        "No se pudo completar la acción": "The action couldn't be completed",
        "No se pudo completar la acción en «%@»": "The action on “%@” couldn't be completed",
        "No se pudo arrancar Colima": "Couldn't start Colima",
        "No se pudo parar Colima": "Couldn't stop Colima",
        "No se pudo reiniciar Colima": "Couldn't restart Colima",
        "Cancelar": "Cancel",
        "No se encuentra %@. Instálalo con: brew install %@": "%@ not found. Install it with: brew install %@",
        "Cancelado.": "Cancelled.",
        "%@ terminó con error %d.": "%@ exited with error %d.",

        // Inspector
        "Logs": "Logs",
        "Detalles": "Details",
        "Ir al stack": "Go to Stack",
        "%d/%d en marcha": "%d/%d running",
        "Cerrar": "Close",
        "Filtrar": "Filter",
        "En directo": "Live",
        "Reconectar": "Reconnect",
        "Copiar todo": "Copy All",
        "Vaciar": "Clear",
        "Abrir en Terminal": "Open in Terminal",
        "Esperando registros…": "Waiting for logs…",
        "Sin registros": "No logs",
        "General": "General",
        "Imagen": "Image",
        "ID": "ID",
        "Creado": "Created",
        "Iniciado": "Started",
        "código %d": "code %d",
        "Comando": "Command",
        "Directorio": "Directory",
        "Usuario": "User",
        "Reinicio": "Restart Policy",
        "Puertos": "Ports",
        "Redes": "Networks",
        "Montajes": "Mounts",
        "Variables de entorno": "Environment Variables",
        "Mostrar %d variables": "Show %d Variables",
        "Pueden contener contraseñas.": "They may contain passwords.",
        "Proyecto": "Project",
        "Carpeta": "Folder",
        "Servicios": "Services",
        "Archivos de Compose": "Compose Files",
        "Abrir": "Open",
        "Faltan archivos: solo se puede arrancar, parar, reiniciar y bajar.": "Files are missing: only start, stop, restart and down work.",

        // Lists
        "No hay stacks": "No stacks",
        "Nada coincide con «%@»": "Nothing matches “%@”",
        "Plegar": "Collapse",
        "Desplegar": "Expand",
        "Ver logs": "Show Logs",
        "Recrear (up -d)": "Recreate (up -d)",
        "Descargar imágenes (pull)": "Pull Images",
        "Abrir terminal en la carpeta": "Open Terminal in Folder",
        "Copiar ruta": "Copy Path",
        "Bajar (down)…": "Down…",
        "Más acciones": "More Actions",
        "¿Bajar «%@»?": "Take “%@” down?",
        "Se pararán y eliminarán sus contenedores y redes. Los volúmenes y las imágenes se conservan.": "Its containers and networks will be stopped and removed. Volumes and images are kept.",
        "Bajar": "Down",
        "sano": "healthy",
        "con fallos": "unhealthy",
        "comprobando": "checking",
        "Pausar": "Pause",
        "Forzar parada (kill)": "Force Stop (kill)",
        "Copiar nombre": "Copy Name",
        "Copiar ID": "Copy ID",
        "Copiar comando de terminal": "Copy Shell Command",
        "Eliminar…": "Delete…",
        "¿Eliminar «%@»?": "Delete “%@”?",
        "El contenedor se borrará. Sus volúmenes con nombre se conservan.": "The container will be deleted. Its named volumes are kept.",
        "El contenedor se borrará. Volverá a crearse la próxima vez que arranques el stack.": "The container will be deleted. It will be created again the next time you start the stack.",
        "Eliminar": "Delete",

        // Main window
        "Sistema": "System",
        "Contenedores": "Containers",
        "Ajustes": "Settings",
        "Versión %@": "Version %@",
        "Faltan herramientas": "Missing tools",
        "Comprobando…": "Checking…",
        "Colima en marcha": "Colima running",
        "Colima parado": "Colima stopped",
        "Instálalas con: brew install colima docker docker-compose": "Install them with: brew install colima docker docker-compose",
        "Perfil «%@» · %d contenedores en marcha": "Profile “%@” · %d containers running",
        "Perfil «%@»": "Profile “%@”",
        "Todos": "All",
        "Colima está parado": "Colima is stopped",
        "Arráncalo para ver tus stacks y contenedores.": "Start it to see your stacks and containers.",
        "Colimy usa Colima y el cliente de Docker. Instálalos con Homebrew:": "Colimy uses Colima and the Docker client. Install them with Homebrew:",
        "Comprobar de nuevo": "Check Again",

        // Settings
        "Automático": "Automatic",
        "Mostrar stacks y contenedores parados": "Show stopped stacks and containers",
        "Actualizar la lista cada": "Refresh the list every",
        "Con la ventana abierta. Los cambios de los contenedores se ven al momento igualmente.": "While the window is open. Container changes show up right away anyway.",
        "Idioma": "Language",
        "Terminal": "Terminal",
        "Abrir las terminales en": "Open terminals in",
        "Shell dentro del contenedor": "Shell inside the container",
        "Automático usa bash si el contenedor lo tiene y, si no, sh.": "Automatic uses bash if the container has it, otherwise sh.",
        "Líneas anteriores al abrir": "Previous lines when opening",
        "Actualizaciones": "Updates",
        "Buscar actualizaciones automáticamente": "Check for updates automatically",
        "Versión ": "Version ",
        "Buscar ahora": "Check Now",
        "Herramientas": "Tools",
        "No instalado": "Not installed",
        "En pausa": "Paused",
        "Reiniciando": "Restarting",
        "Muerto": "Dead",
        "Eliminando": "Removing",

        // Updates
        "Colimy está actualizado": "Colimy is up to date",
        "Tienes la última versión (%@).": "You have the latest version (%@).",
        "No se pudo buscar actualizaciones": "Couldn't check for updates",
        "Colimy %@ está disponible": "Colimy %@ is available",
        "Tienes la versión %@.": "You have version %@.",
        "Actualizar ahora": "Update Now",
        "Más tarde": "Later",
        "Omitir esta versión": "Skip This Version",
        "No se puede actualizar desde aquí": "Can't update from here",
        "Mueve Colimy a la carpeta Aplicaciones, ábrela de nuevo y vuelve a intentarlo.": "Move Colimy to the Applications folder, open it again and retry.",
        "No se puede actualizar": "Can't update",
        "No hay permiso para escribir en %@.\nUsa el instalador:\n\n%@": "No permission to write to %@.\nUse the installer:\n\n%@",
        "La versión %@ no incluye los archivos de actualización.": "Version %@ doesn't include the update files.",
        "La actualización falló": "Update failed",
        "GitHub no respondió correctamente. Inténtalo más tarde.": "GitHub didn't respond correctly. Try again later.",
        "El archivo descargado no coincide con su huella SHA-256. No se ha instalado nada.": "The downloaded file doesn't match its SHA-256 fingerprint. Nothing was installed.",
        "No se pudo descomprimir la actualización.": "Couldn't unzip the update.",
        "La descarga no contiene una versión válida de Colimy.": "The download doesn't contain a valid version of Colimy.",
    ]

    static let ca: [String: String] = [
        // Menus
        "Cerrar ventana": "Tanca la finestra",
        "Salir de Colimy": "Surt de Colimy",
        "Edición": "Edició",
        "Deshacer": "Desfés",
        "Rehacer": "Refés",
        "Cortar": "Retalla",
        "Copiar": "Copia",
        "Pegar": "Enganxa",
        "Seleccionar todo": "Selecciona-ho tot",
        "Buscar": "Cerca",
        "Colima en marcha (%@)": "Colima en marxa (%@)",
        "Colima parado (%@)": "Colima aturat (%@)",
        "Falta instalar: %@": "Falta instal·lar: %@",
        "Colima no tiene ningún perfil": "Colima no té cap perfil",
        "Parar Colima": "Atura Colima",
        "Reiniciar Colima": "Reinicia Colima",
        "Arrancar Colima": "Engega Colima",
        "No hay contenedores": "No hi ha contenidors",
        "Stacks": "Stacks",
        "Contenedores sueltos": "Contenidors solts",
        "Abrir Colimy…": "Obre Colimy…",
        "Abrir al iniciar sesión": "Obre en iniciar la sessió",
        "Actualizando…": "S'està actualitzant…",
        "Buscar actualizaciones…": "Cerca actualitzacions…",
        "Invítame a un café…": "Convida'm a un cafè…",
        "Trabajando…": "Treballant…",
        "Arrancar": "Engega",
        "Parar": "Atura",
        "Reiniciar": "Reinicia",
        "Ver logs…": "Mostra els logs…",
        "Mostrar en Finder": "Mostra al Finder",
        "Abrir terminal": "Obre un terminal",
        "Abrir localhost:%@": "Obre localhost:%@",
        "Reanudar": "Reprèn",
        "¿Parar Colima?": "Vols aturar Colima?",
        "Se pararán los %d contenedores en marcha.": "S'aturaran els %d contenidors en marxa.",

        // Colima
        "Arrancando Colima…": "S'està engegant Colima…",
        "Parando Colima…": "S'està aturant Colima…",
        "Reiniciando Colima…": "S'està reiniciant Colima…",
        "Colima": "Colima",
        "Actualizar": "Actualitza",
        "Para crear otro perfil o cambiar CPU, memoria y disco, usa «colima start -p <nombre> --cpu 4 --memory 8» o «colima start --edit» en Terminal.": "Per crear un altre perfil o canviar la CPU, la memòria i el disc, fes servir «colima start -p <nom> --cpu 4 --memory 8» o «colima start --edit» al Terminal.",
        "Colima aún no tiene ningún perfil": "Colima encara no té cap perfil",
        "Arrancarlo crea el perfil «default» con 2 CPU, 2 GB de memoria y Docker.": "Engegar-lo crea el perfil «default» amb 2 CPU, 2 GB de memòria i Docker.",
        "Crear y arrancar": "Crea i engega",
        "Última operación": "Última operació",
        "Ocultar": "Amaga",
        "En marcha": "En marxa",
        "Parado": "Aturat",
        "En uso": "En ús",
        "Usar este perfil": "Fes servir aquest perfil",
        "CPU": "CPU",
        "Memoria": "Memòria",
        "Disco": "Disc",
        "Arquitectura": "Arquitectura",
        "Motor": "Motor",
        "Dirección": "Adreça",

        // Errors
        "No se encontró el contenedor.": "No s'ha trobat el contenidor.",
        "No se pudo completar la acción": "No s'ha pogut completar l'acció",
        "No se pudo completar la acción en «%@»": "No s'ha pogut completar l'acció a «%@»",
        "No se pudo arrancar Colima": "No s'ha pogut engegar Colima",
        "No se pudo parar Colima": "No s'ha pogut aturar Colima",
        "No se pudo reiniciar Colima": "No s'ha pogut reiniciar Colima",
        "Cancelar": "Cancel·la",
        "No se encuentra %@. Instálalo con: brew install %@": "No es troba %@. Instal·la'l amb: brew install %@",
        "Cancelado.": "Cancel·lat.",
        "%@ terminó con error %d.": "%@ ha acabat amb l'error %d.",

        // Inspector
        "Logs": "Logs",
        "Detalles": "Detalls",
        "Ir al stack": "Ves a l'stack",
        "%d/%d en marcha": "%d/%d en marxa",
        "Cerrar": "Tanca",
        "Filtrar": "Filtra",
        "En directo": "En directe",
        "Reconectar": "Reconnecta",
        "Copiar todo": "Copia-ho tot",
        "Vaciar": "Buida",
        "Abrir en Terminal": "Obre al Terminal",
        "Esperando registros…": "Esperant registres…",
        "Sin registros": "Sense registres",
        "General": "General",
        "Imagen": "Imatge",
        "ID": "ID",
        "Creado": "Creat",
        "Iniciado": "Iniciat",
        "código %d": "codi %d",
        "Comando": "Ordre",
        "Directorio": "Directori",
        "Usuario": "Usuari",
        "Reinicio": "Reinici",
        "Puertos": "Ports",
        "Redes": "Xarxes",
        "Montajes": "Muntatges",
        "Variables de entorno": "Variables d'entorn",
        "Mostrar %d variables": "Mostra %d variables",
        "Pueden contener contraseñas.": "Poden contenir contrasenyes.",
        "Proyecto": "Projecte",
        "Carpeta": "Carpeta",
        "Servicios": "Serveis",
        "Archivos de Compose": "Fitxers de Compose",
        "Abrir": "Obre",
        "Faltan archivos: solo se puede arrancar, parar, reiniciar y bajar.": "Falten fitxers: només es pot engegar, aturar, reiniciar i baixar.",

        // Lists
        "No hay stacks": "No hi ha stacks",
        "Nada coincide con «%@»": "Res no coincideix amb «%@»",
        "Plegar": "Plega",
        "Desplegar": "Desplega",
        "Ver logs": "Mostra els logs",
        "Recrear (up -d)": "Recrea (up -d)",
        "Descargar imágenes (pull)": "Baixa les imatges (pull)",
        "Abrir terminal en la carpeta": "Obre un terminal a la carpeta",
        "Copiar ruta": "Copia el camí",
        "Bajar (down)…": "Baixa (down)…",
        "Más acciones": "Més accions",
        "¿Bajar «%@»?": "Vols baixar «%@»?",
        "Se pararán y eliminarán sus contenedores y redes. Los volúmenes y las imágenes se conservan.": "S'aturaran i s'eliminaran els seus contenidors i xarxes. Els volums i les imatges es conserven.",
        "Bajar": "Baixa",
        "sano": "sa",
        "con fallos": "amb errors",
        "comprobando": "comprovant",
        "Pausar": "Pausa",
        "Forzar parada (kill)": "Força l'aturada (kill)",
        "Copiar nombre": "Copia el nom",
        "Copiar ID": "Copia l'ID",
        "Copiar comando de terminal": "Copia l'ordre del terminal",
        "Eliminar…": "Elimina…",
        "¿Eliminar «%@»?": "Vols eliminar «%@»?",
        "El contenedor se borrará. Sus volúmenes con nombre se conservan.": "El contenidor s'esborrarà. Els seus volums amb nom es conserven.",
        "El contenedor se borrará. Volverá a crearse la próxima vez que arranques el stack.": "El contenidor s'esborrarà. Es tornarà a crear la pròxima vegada que engeguis l'stack.",
        "Eliminar": "Elimina",

        // Main window
        "Sistema": "Sistema",
        "Contenedores": "Contenidors",
        "Ajustes": "Configuració",
        "Versión %@": "Versió %@",
        "Faltan herramientas": "Falten eines",
        "Comprobando…": "Comprovant…",
        "Colima en marcha": "Colima en marxa",
        "Colima parado": "Colima aturat",
        "Instálalas con: brew install colima docker docker-compose": "Instal·la-les amb: brew install colima docker docker-compose",
        "Perfil «%@» · %d contenedores en marcha": "Perfil «%@» · %d contenidors en marxa",
        "Perfil «%@»": "Perfil «%@»",
        "Todos": "Tots",
        "Colima está parado": "Colima està aturat",
        "Arráncalo para ver tus stacks y contenedores.": "Engega'l per veure els teus stacks i contenidors.",
        "Colimy usa Colima y el cliente de Docker. Instálalos con Homebrew:": "Colimy fa servir Colima i el client de Docker. Instal·la'ls amb Homebrew:",
        "Comprobar de nuevo": "Torna-ho a comprovar",

        // Settings
        "Automático": "Automàtic",
        "Mostrar stacks y contenedores parados": "Mostra els stacks i contenidors aturats",
        "Actualizar la lista cada": "Actualitza la llista cada",
        "Con la ventana abierta. Los cambios de los contenedores se ven al momento igualmente.": "Amb la finestra oberta. Els canvis dels contenidors es veuen a l'instant igualment.",
        "Idioma": "Idioma",
        "Terminal": "Terminal",
        "Abrir las terminales en": "Obre els terminals a",
        "Shell dentro del contenedor": "Shell dins del contenidor",
        "Automático usa bash si el contenedor lo tiene y, si no, sh.": "Automàtic fa servir bash si el contenidor en té i, si no, sh.",
        "Líneas anteriores al abrir": "Línies anteriors en obrir",
        "Actualizaciones": "Actualitzacions",
        "Buscar actualizaciones automáticamente": "Cerca actualitzacions automàticament",
        "Versión ": "Versió ",
        "Buscar ahora": "Cerca ara",
        "Herramientas": "Eines",
        "No instalado": "No instal·lat",
        "En pausa": "En pausa",
        "Reiniciando": "Reiniciant",
        "Muerto": "Mort",
        "Eliminando": "Eliminant",

        // Updates
        "Colimy está actualizado": "Colimy està actualitzat",
        "Tienes la última versión (%@).": "Tens l'última versió (%@).",
        "No se pudo buscar actualizaciones": "No s'han pogut cercar actualitzacions",
        "Colimy %@ está disponible": "Colimy %@ està disponible",
        "Tienes la versión %@.": "Tens la versió %@.",
        "Actualizar ahora": "Actualitza ara",
        "Más tarde": "Més tard",
        "Omitir esta versión": "Omet aquesta versió",
        "No se puede actualizar desde aquí": "No es pot actualitzar des d'aquí",
        "Mueve Colimy a la carpeta Aplicaciones, ábrela de nuevo y vuelve a intentarlo.": "Mou Colimy a la carpeta Aplicacions, torna-la a obrir i torna-ho a provar.",
        "No se puede actualizar": "No es pot actualitzar",
        "No hay permiso para escribir en %@.\nUsa el instalador:\n\n%@": "No hi ha permís per escriure a %@.\nFes servir l'instal·lador:\n\n%@",
        "La versión %@ no incluye los archivos de actualización.": "La versió %@ no inclou els fitxers d'actualització.",
        "La actualización falló": "L'actualització ha fallat",
        "GitHub no respondió correctamente. Inténtalo más tarde.": "GitHub no ha respost correctament. Torna-ho a provar més tard.",
        "El archivo descargado no coincide con su huella SHA-256. No se ha instalado nada.": "El fitxer baixat no coincideix amb la seva empremta SHA-256. No s'ha instal·lat res.",
        "No se pudo descomprimir la actualización.": "No s'ha pogut descomprimir l'actualització.",
        "La descarga no contiene una versión válida de Colimy.": "La baixada no conté una versió vàlida de Colimy.",
    ]
}
