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
                    Label("Ahorro", systemImage: "lightbulb").tag(SeccionMac.ahorro)
                }

                if !mesActual.porCategoria.isEmpty {
                    Section("Categorías · \(Mes.actual.nombre)") {
                        ForEach(mesActual.porCategoria, id: \.categoria) { c in
                            HStack {
                                IconoCategoria(categoria: c.categoria, tamaño: 22)
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
            .fontDesign(.rounded)
            .safeAreaInset(edge: .bottom) { PieBarraLateral() }
        } detail: {
            detalle.fontDesign(.rounded)
        }
        .sheet(isPresented: $navegacion.mostrandoNuevo) {
            NuevoMovimientoView().fontDesign(.rounded)
        }
        .task {
            // En Mac la app abre rápido: se actualiza sin pantalla de arranque.
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
            case .ahorro:
                AhorroView()
            case .categoria(let c):
                TablaGastos(titulo: c) { $0.categoria == c }
            case .dia(let fecha):
                TablaGastos(titulo: SeccionMac.titulo(dia: fecha), mostrarFiltroMes: false) {
                    Calendar.current.isDate($0.fecha, inSameDayAs: fecha)
                }
                .id(fecha)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button { navegacion.seccion = .resumen } label: { Label("Volver al resumen", systemImage: "chevron.left") }
                            .help("Volver al resumen")
                    }
                }
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
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tema.alerta)
                Text("Sin conexión con la hoja")
            } else if let fecha = almacen.ultimaActualizacion {
                Image(systemName: "checkmark.circle.fill")
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
    @State private var busqueda = ""
    @State private var mes: Mes? = .actual
    @State private var orden = OrdenGastos.recientes
    @State private var categoria: String?
    @State private var metodo: String?
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
            .filter { categoria == nil || $0.categoria == categoria }
            .filter { metodo == nil || Formato.metodo($0.metodo) == metodo }
            .filter { t.isEmpty || $0.concepto.lowercased().contains(t) || $0.categoria.lowercased().contains(t) }
            .ordenados(orden)
    }

    private func gastos(_ ids: Set<Gasto.ID>) -> [Gasto] {
        almacen.datos.gastos.filter { ids.contains($0.id) && !$0.pendiente }
    }

    var body: some View {
        let filas = filas
        // Lista al estilo de las apps de banca: filas altas y una cabecera por día con su total.
        GeometryReader { geo in
            List(selection: $seleccion) {
                if filas.isEmpty {
                    ContentUnavailableView("No hay gastos", systemImage: "tray")
                        .listRowSeparator(.hidden)
                }
                if orden == .recientes {
                    ForEach(gastosPorDia(filas), id: \.dia) { grupo in
                        Section {
                            ForEach(grupo.gastos) { filaMac($0, conFecha: false) }
                        } header: {
                            EncabezadoDia(dia: grupo.dia, total: grupo.gastos.reduce(0) { $0 + $1.importe })
                        }
                    }
                } else {
                    ForEach(filas) { filaMac($0, conFecha: true) }
                }
            }
            .listStyle(.plain)
            // En ventanas anchas, la lista queda centrada con un ancho cómodo de leer.
            .contentMargins(.horizontal, max(16, (geo.size.width - 860) / 2), for: .scrollContent)
        }
        .scrollContentBackground(.hidden)
        .background(Color.fondo)
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
            ToolbarItem {
                let activo = categoria != nil || metodo != nil || orden != .recientes
                Menu {
                    ContenidoFiltros(orden: $orden, categoria: $categoria, metodo: $metodo)
                } label: {
                    Label("Filtros", systemImage: ContenidoFiltros.icono(activo: activo))
                }
                .help(activo ? "Filtros activos" : "Ordenar y filtrar")
            }
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

    private func filaMac(_ g: Gasto, conFecha: Bool) -> some View {
        FilaGasto(gasto: g, conFecha: conFecha)
            .padding(.vertical, 6)
            .tag(g.id)
            .listRowSeparator(.hidden)
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
