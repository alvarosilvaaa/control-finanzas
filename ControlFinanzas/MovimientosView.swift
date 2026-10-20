import SwiftUI

struct MovimientosView: View {
    @Environment(Almacen.self) private var almacen
    @Binding var mostrandoNuevo: Bool
    @State private var busqueda = ""
    @State private var categoria: String?
    @State private var metodo: String?

    private var filtrados: [Gasto] {
        let t = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
        return almacen.datos.gastos
            .filter { t.isEmpty || $0.concepto.lowercased().contains(t) || $0.categoria.lowercased().contains(t) }
            .filter { categoria == nil || $0.categoria == categoria }
            .filter { metodo == nil || Formato.metodo($0.metodo) == metodo }
            .sorted { $0.fecha > $1.fecha }
    }

    var body: some View {
        NavigationStack {
            ListaGastos(gastos: filtrados)
                .navigationTitle("Movimientos")
                .refreshable { await almacen.recargar() }
                .safeAreaInset(edge: .bottom) { barraBusqueda }
                .toolbar {
                    ToolbarItem(placement: .fin) {
                        Button { mostrandoNuevo = true } label: { Image(systemName: "plus") }
                    }
                }
        }
    }

    /// Buscador flotante abajo con el botón de filtros al lado, como en las apps de banca.
    private var barraBusqueda: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar movimientos", text: $busqueda, prompt: Text("Buscar movimientos"))
                    .labelsHidden()
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !busqueda.isEmpty {
                    Button { busqueda = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .cristal(Capsule())

            Menu {
                Picker("Categoría", selection: $categoria) {
                    Text("Todas las categorías").tag(String?.none)
                    ForEach(almacen.categorias + ["Sin clasificar"], id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Método", selection: $metodo) {
                    Text("Todos los métodos").tag(String?.none)
                    ForEach(["Tarjeta", "Bizum", "Efectivo"], id: \.self) { Text($0).tag(String?.some($0)) }
                }
                if categoria != nil || metodo != nil {
                    Button("Quitar filtros", role: .destructive) { categoria = nil; metodo = nil }
                }
            } label: {
                Image(systemName: categoria == nil && metodo == nil
                      ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Tema.tinta)
                    .frame(width: 48, height: 48)
                    .cristal(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

/// Gastos agrupados por día (más reciente primero), con el total de cada día.
func gastosPorDia(_ gastos: [Gasto]) -> [(dia: Date, gastos: [Gasto])] {
    Dictionary(grouping: gastos) { Calendar.current.startOfDay(for: $0.fecha) }
        .map { ($0.key, $0.value.sorted { $0.fecha > $1.fecha }) }
        .sorted { $0.0 > $1.0 }
}

/// Lista de gastos por día, sin cajas ni separadores. Al tocar uno se abre para editarlo.
struct ListaGastos: View {
    let gastos: [Gasto]
    @State private var editando: Gasto?

    var body: some View {
        List {
            if gastos.isEmpty {
                ContentUnavailableView("No hay gastos", systemImage: "tray")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(gastosPorDia(gastos), id: \.dia) { grupo in
                Section {
                    ForEach(grupo.gastos) { g in
                        Button { editando = g } label: { FilaGasto(gasto: g) }
                            .buttonStyle(.plain)
                            .disabled(g.pendiente)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    }
                } header: {
                    EncabezadoDia(dia: grupo.dia, total: grupo.gastos.reduce(0) { $0 + $1.importe })
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .listSectionSpacing(4)
        #endif
        .estiloLimpio()
        .sheet(item: $editando) { EditarGastoView(gasto: $0) }
    }
}

/// "Hoy                20,50 €" · "martes, 14 oct        19,60 €"
struct EncabezadoDia: View {
    let dia: Date
    let total: Double

    private var titulo: String {
        let cal = Calendar.current
        if cal.isDateInToday(dia) { return "Hoy" }
        if cal.isDateInYesterday(dia) { return "Ayer" }
        let mismoAño = cal.component(.year, from: dia) == cal.component(.year, from: Date())
        var estilo = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))
        if !mismoAño { estilo = estilo.year() }
        let texto = dia.formatted(estilo)
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titulo).font(.headline).foregroundStyle(Tema.tinta)
            Spacer()
            Text(Formato.eur(total)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
        }
        .textCase(nil)
        .padding(.top, 16)
        .padding(.bottom, 2)
        .padding(.horizontal, 4)
    }
}

struct FilaGasto: View {
    let gasto: Gasto
    /// En listas agrupadas por día basta con la hora; en el resto se muestra también la fecha.
    var conFecha = false

    var body: some View {
        HStack(spacing: 14) {
            IconoCategoria(categoria: gasto.categoria, concepto: gasto.concepto, tamaño: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(gasto.concepto.trimmingCharacters(in: .whitespaces))
                    .font(.body.weight(.semibold)).lineLimit(1)
                Text(detalle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if gasto.pendiente { ProgressView().controlSize(.mini) }
            Text(Formato.eur(gasto.importe)).font(.body.weight(.semibold)).monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    /// "15:45 · Limpieza · Bizum" (o "20 oct · Limpieza · Bizum" con fecha)
    private var detalle: String {
        let fecha = conFecha
            ? gasto.fecha.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
            : gasto.fecha.formatted(Formato.hora)
        return [fecha, gasto.categoria == "Sin clasificar" ? "Sin clasificar" : gasto.categoria, Formato.metodo(gasto.metodo)]
            .joined(separator: " · ")
    }
}

/// Lista filtrada que se mantiene al día cuando se edita un gasto.
struct ListaGastosView: View {
    let titulo: String
    let incluir: (Gasto) -> Bool
    @Environment(Almacen.self) private var almacen

    var body: some View {
        ListaGastos(gastos: almacen.datos.gastos.filter(incluir))
            .navigationTitle(titulo)
            .tituloEnLinea()
    }
}
