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
        }
        #else
        WindowGroup {
            ContentView()
                .environment(almacen)
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
    @Environment(Almacen.self) private var almacen
    @Environment(\.scenePhase) private var fase
    @State private var mostrandoNuevo = false
    @State private var pestaña = 0

    var body: some View {
        TabView(selection: $pestaña) {
            Tab("Resumen", systemImage: "chart.pie.fill", value: 0) {
                ResumenView(mostrandoNuevo: $mostrandoNuevo)
            }
            Tab("Movimientos", systemImage: "list.bullet", value: 1) {
                MovimientosView(mostrandoNuevo: $mostrandoNuevo)
            }
            Tab("Meses", systemImage: "calendar", value: 2) {
                MesesView()
            }
            Tab("Ajustes", systemImage: "gearshape.fill", value: 3) {
                AjustesView()
            }
        }
        .sheet(isPresented: $mostrandoNuevo) {
            NuevoMovimientoView()
        }
        .task {
            if almacen.configurado { await almacen.recargar() } else { pestaña = 3 }
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .active, almacen.configurado { Task { await almacen.recargar() } }
        }
    }
}
