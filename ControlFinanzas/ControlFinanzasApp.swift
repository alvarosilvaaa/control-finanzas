import SwiftUI

@main
struct ControlFinanzasApp: App {
    @State private var almacen = Almacen()
    @State private var navegacion = Navegacion()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacContentView()
                .environment(almacen)
                .environment(navegacion)
                .fontDesign(.rounded)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nuevo gasto…") { navegacion.mostrandoNuevo = true }
                    .keyboardShortcut("n")
            }
            CommandMenu("Datos") {
                Button("Recargar") { Task { await almacen.recargar() } }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            AjustesView()
                .environment(almacen)
                .fontDesign(.rounded)
        }
        #else
        WindowGroup {
            ConArranque { ContentView() }
                .environment(almacen)
                .fontDesign(.rounded)
        }
        #endif
    }
}

/// Estado de navegación compartido con los menús de la app (solo se usa en Mac).
@Observable
final class Navegacion {
    var seccion: SeccionMac? = .resumen
    var mostrandoNuevo = false
}

enum SeccionMac: Hashable {
    case resumen, movimientos, sinClasificar, meses
    case categoria(String)
}

struct ContentView: View {
    init() {
        #if os(iOS)
        // Los títulos de navegación los dibuja UIKit: hay que darles la letra redondeada aparte.
        func redondeada(_ estilo: UIFont.TextStyle, _ peso: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: estilo).pointSize, weight: peso)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 0) } ?? base
        }
        let barra = UINavigationBar.appearance()
        barra.largeTitleTextAttributes = [.font: redondeada(.largeTitle, .bold)]
        barra.titleTextAttributes = [.font: redondeada(.headline, .semibold)]
        #endif
    }

    @Environment(Almacen.self) private var almacen
    @Environment(\.scenePhase) private var fase
    @State private var mostrandoNuevo = false
    @State private var pestaña = 0

    var body: some View {
        TabView(selection: $pestaña) {
            Tab("Resumen", systemImage: "chart.pie.fill", value: 0) {
                ResumenView(mostrandoNuevo: $mostrandoNuevo).fontDesign(.rounded)
            }
            Tab("Movimientos", systemImage: "list.bullet", value: 1) {
                MovimientosView(mostrandoNuevo: $mostrandoNuevo).fontDesign(.rounded)
            }
            Tab("Meses", systemImage: "calendar", value: 2) {
                MesesView().fontDesign(.rounded)
            }
            Tab("Ajustes", systemImage: "gearshape.fill", value: 3) {
                AjustesView().fontDesign(.rounded)
            }
        }
        .sheet(isPresented: $mostrandoNuevo) {
            NuevoMovimientoView().fontDesign(.rounded)
        }
        .task {
            // La primera carga la hace la pantalla de arranque.
            if !almacen.configurado { pestaña = 3 }
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .active, almacen.configurado { Task { await almacen.recargar() } }
        }
    }
}
