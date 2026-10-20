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
                .searchable(text: $busqueda, prompt: "Buscar comercio o categoría")
                .refreshable { await almacen.recargar() }
                .toolbar {
                    ToolbarItem(placement: .inicio) {
                        Menu {
                            Picker("Categoría", selection: $categoria) {
                                Text("Todas las categorías").tag(String?.none)
                                ForEach(almacen.categorias + ["Sin clasificar"], id: \.self) { Text($0).tag(String?.some($0)) }
                            }
                            Picker("Método", selection: $metodo) {
                                Text("Todos los métodos").tag(String?.none)
                                ForEach(["Tarjeta", "Bizum", "Efectivo"], id: \.self) { Text($0).tag(String?.some($0)) }
                            }
                        } label: {
                            Image(systemName: categoria == nil && metodo == nil
                                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                    ToolbarItem(placement: .fin) {
                        Button { mostrandoNuevo = true } label: { Image(systemName: "plus") }
                    }
                }
        }
    }
}

/// Lista de gastos agrupada por mes, sin cajas ni separadores. Al tocar uno se abre para editarlo.
struct ListaGastos: View {
    let gastos: [Gasto]
    @State private var editando: Gasto?

    private var porMes: [(mes: Mes, gastos: [Gasto])] {
        Dictionary(grouping: gastos) { Mes($0.fecha) }
            .map { ($0.key, $0.value.sorted { $0.fecha > $1.fecha }) }
            .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        List {
            if gastos.isEmpty {
                ContentUnavailableView("No hay gastos", systemImage: "tray")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(porMes, id: \.mes) { grupo in
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
                    EncabezadoMes(mes: grupo.mes, total: grupo.gastos.reduce(0) { $0 + $1.importe })
                }
            }
        }
        .listStyle(.plain)
        .estiloLimpio()
        .sheet(item: $editando) { EditarGastoView(gasto: $0) }
    }
}

/// "octubre                356,54 €", en negrita y sin adornos.
struct EncabezadoMes: View {
    let mes: Mes
    let total: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(mes == .actual || mes.año == Mes.actual.año ? mes.nombreMes : mes.nombre.lowercased())
                .font(.title3.bold())
                .foregroundStyle(Tema.tinta)
            Spacer()
            Text(Formato.eur(total)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
        .textCase(nil)
        .padding(.top, 18)
        .padding(.bottom, 4)
        .padding(.horizontal, 4)
    }
}

struct FilaGasto: View {
    let gasto: Gasto

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

    /// "20 oct · Limpieza · Bizum"
    private var detalle: String {
        let fecha = gasto.fecha.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
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
