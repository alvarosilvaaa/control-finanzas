#if os(macOS)
import SwiftUI

/// Ventana principal en Mac: barra lateral + contenido.
struct MacContentView: View {
    @Environment(Almacen.self) private var almacen
    @Environment(Navegacion.self) private var navegacion

    var body: some View {
        @Bindable var navegacion = navegacion
        let mesActual = almacen.resumen(de: .actual)

        NavigationSplitView {
            List(selection: $navegacion.seccion) {
                Section {
                    Label("Resumen", systemImage: "chart.pie.fill").tag(SeccionMac.resumen)
                    Label("Movimientos", systemImage: "list.bullet").tag(SeccionMac.movimientos)
                    if !almacen.sinClasificar.isEmpty {
                        Label("Sin clasificar", systemImage: "questionmark.circle")
                            .badge(almacen.sinClasificar.count)
                            .tag(SeccionMac.sinClasificar)
                    }
                    Label("Meses", systemImage: "calendar").tag(SeccionMac.meses)
                }

                if !mesActual.porCategoria.isEmpty {
                    Section("Categorías · \(Mes.actual.nombre)") {
                        ForEach(mesActual.porCategoria, id: \.categoria) { c in
                            HStack {
                                IconoCategoria(categoria: c.categoria, tamaño: 20)
                                Text(c.categoria)
                                Spacer()
                                Text(Formato.eurSinDecimales(c.total)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .tag(SeccionMac.categoria(c.categoria))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
            .safeAreaInset(edge: .bottom) { PieBarraLateral() }
        } detail: {
            detalle
        }
        .sheet(isPresented: $navegacion.mostrandoNuevo) {
            NuevoMovimientoView()
        }
        .task {
            if almacen.configurado { await almacen.recargar() }
        }
    }

    @ViewBuilder private var detalle: some View {
        @Bindable var navegacion = navegacion
        if !almacen.configurado {
            ContentUnavailableView {
                Label("Conecta tu hoja de Google", systemImage: "link")
            } description: {
                Text("Pega la URL del script y el token en Ajustes.")
            } actions: {
                SettingsLink { Text("Abrir Ajustes…") }
            }
        } else {
            switch navegacion.seccion ?? .resumen {
            case .resumen:
                MacResumenView()
            case .movimientos:
                TablaGastos(titulo: "Movimientos") { _ in true }
            case .sinClasificar:
                TablaGastos(titulo: "Sin clasificar", mostrarFiltroMes: false) { $0.categoria == "Sin clasificar" }
            case .meses:
                MesesView()
            case .categoria(let c):
                TablaGastos(titulo: c) { $0.categoria == c }
            }
        }
    }
}

private struct PieBarraLateral: View {
    @Environment(Almacen.self) private var almacen

    var body: some View {
        HStack(spacing: 6) {
            if almacen.cargando {
                ProgressView().controlSize(.small)
                Text("Actualizando…")
            } else if almacen.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Sin conexión con la hoja")
            } else if let fecha = almacen.ultimaActualizacion {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Actualizado \(fecha.formatted(.relative(presentation: .named).locale(Locale(identifier: "es_ES"))))")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Botón de recargar para la barra de herramientas. Es una vista aparte para que se actualice
/// al terminar la carga (el contenido de la barra no siempre se refresca con el de la pantalla).
struct BotonRecargar: View {
    @Environment(Almacen.self) private var almacen

    var body: some View {
        Button { Task { await almacen.recargar() } } label: {
            Label("Recargar", systemImage: "arrow.clockwise")
                .symbolEffect(.rotate, isActive: almacen.cargando)
        }
        .disabled(almacen.cargando)
        .help("Recargar los datos de la hoja (⌘R)")
    }
}

/// Tabla de gastos ordenable, con selección múltiple, menú contextual y borrado con ⌫.
struct TablaGastos: View {
    let titulo: String
    var mostrarFiltroMes = true
    let incluir: (Gasto) -> Bool

    @Environment(Almacen.self) private var almacen
    @Environment(Navegacion.self) private var navegacion
    @State private var seleccion = Set<Gasto.ID>()
    @State private var orden = [KeyPathComparator(\Gasto.fecha, order: .reverse)]
    @State private var busqueda = ""
    @State private var mes: Mes? = .actual
    @State private var editando: Gasto?
    @State private var aBorrar: [Gasto] = []
    @State private var trabajando = false
    @State private var error: String?

    init(titulo: String, mostrarFiltroMes: Bool = true, incluir: @escaping (Gasto) -> Bool) {
        self.titulo = titulo
        self.mostrarFiltroMes = mostrarFiltroMes
        self.incluir = incluir
        _mes = State(initialValue: mostrarFiltroMes ? .actual : nil)
    }

    private var filas: [Gasto] {
        let t = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
        return almacen.datos.gastos
            .filter(incluir)
            .filter { mes == nil || mes!.contiene($0.fecha) }
            .filter { t.isEmpty || $0.concepto.lowercased().contains(t) || $0.categoria.lowercased().contains(t) }
            .sorted(using: orden)
    }

    private func gastos(_ ids: Set<Gasto.ID>) -> [Gasto] {
        almacen.datos.gastos.filter { ids.contains($0.id) && !$0.pendiente }
    }

    var body: some View {
        let filas = filas
        Table(filas, selection: $seleccion, sortOrder: $orden) {
            TableColumn("Fecha", value: \.fecha) { g in
                Text(g.fecha.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()
                    .locale(Locale(identifier: "es_ES"))))
                    .monospacedDigit()
            }
            .width(min: 130, ideal: 150)

            TableColumn("Concepto", value: \.concepto) { g in
                HStack(spacing: 8) {
                    IconoCategoria(categoria: g.categoria, tamaño: 20)
                    Text(g.concepto.trimmingCharacters(in: .whitespaces))
                    if g.pendiente { ProgressView().controlSize(.mini) }
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn("Categoría", value: \.categoria) { g in
                Text(g.categoria).foregroundStyle(g.categoria == "Sin clasificar" ? .secondary : .primary)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Método", value: \.metodo) { g in Text(Formato.metodo(g.metodo)) }
                .width(min: 70, ideal: 90)

            TableColumn("Importe", value: \.importe) { g in
                Text(Formato.eur(g.importe)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: Gasto.ID.self) { ids in
            let lista = gastos(ids)
            Button("Editar…") { editando = lista.first }
                .disabled(lista.count != 1)
            Menu("Cambiar categoría") {
                ForEach(almacen.categorias, id: \.self) { c in
                    Button(c) { Task { await cambiarCategoria(lista, a: c) } }
                }
            }
            .disabled(lista.isEmpty)
            Divider()
            Button(lista.count > 1 ? "Borrar \(lista.count) gastos" : "Borrar", role: .destructive) { aBorrar = lista }
                .disabled(lista.isEmpty)
        } primaryAction: { ids in
            if let g = gastos(ids).first, ids.count == 1 { editando = g }
        }
        .onDeleteCommand {
            let lista = gastos(seleccion)
            if !lista.isEmpty { aBorrar = lista }
        }
        .searchable(text: $busqueda, prompt: "Buscar comercio o categoría")
        .navigationTitle(titulo)
        .navigationSubtitle("\(filas.count) gastos · \(Formato.eur(filas.reduce(0) { $0 + $1.importe }))")
        .toolbar {
            if mostrarFiltroMes {
                ToolbarItem {
                    Picker("Mes", selection: $mes) {
                        Text("Todos los meses").tag(Mes?.none)
                        Divider()
                        ForEach(almacen.meses) { m in Text(m.nombre).tag(Mes?.some(m)) }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 160)
                }
            }
            ToolbarItem {
                BotonRecargar()
            }
            ToolbarItem {
                Button { navegacion.mostrandoNuevo = true } label: { Label("Nuevo gasto", systemImage: "plus") }
            }
        }
        .sheet(item: $editando) { EditarGastoView(gasto: $0) }
        .confirmationDialog(aBorrar.count > 1 ? "¿Borrar \(aBorrar.count) gastos?" : "¿Borrar este gasto?",
                            isPresented: Binding(get: { !aBorrar.isEmpty }, set: { if !$0 { aBorrar = [] } })) {
            Button("Borrar", role: .destructive) {
                let lista = aBorrar
                Task { await borrar(lista) }
            }
        } message: {
            Text("Se eliminará también de tu hoja de Google. Total: \(Formato.eur(aBorrar.reduce(0) { $0 + $1.importe }))")
        }
        .alertaError($error)
    }

    private func cambiarCategoria(_ lista: [Gasto], a categoria: String) async {
        await ejecutar { try await almacen.cambiarCategoria(lista, a: categoria) }
    }

    private func borrar(_ lista: [Gasto]) async {
        await ejecutar { try await almacen.borrarGastos(lista) }
        seleccion = []
    }

    private func ejecutar(_ accion: () async throws -> Void) async {
        trabajando = true
        defer { trabajando = false }
        do { try await accion() } catch { self.error = error.localizedDescription }
    }
}
#endif
