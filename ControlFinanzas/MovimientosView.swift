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

/// Lista de gastos agrupada por día. Al tocar uno se abre para editarlo.
struct ListaGastos: View {
    let gastos: [Gasto]
    @State private var editando: Gasto?

    private var porDia: [(dia: Date, gastos: [Gasto])] {
        Dictionary(grouping: gastos) { Calendar.current.startOfDay(for: $0.fecha) }
            .map { ($0.key, $0.value.sorted { $0.fecha > $1.fecha }) }
            .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        List {
            if gastos.isEmpty {
                ContentUnavailableView("No hay gastos", systemImage: "tray")
                    .listRowBackground(Color.clear)
            }
            ForEach(porDia, id: \.dia) { grupo in
                Section {
                    ForEach(grupo.gastos) { g in
                        Button { editando = g } label: { FilaGasto(gasto: g) }
                            .foregroundStyle(.primary)
                            .disabled(g.pendiente)
                    }
                } header: {
                    HStack {
                        Text(grupo.dia.formatted(Formato.diaLargo).capitalized)
                        Spacer()
                        Text(Formato.eur(grupo.gastos.reduce(0) { $0 + $1.importe }))
                    }
                }
            }
        }
        .sheet(item: $editando) { EditarGastoView(gasto: $0) }
    }
}

struct FilaGasto: View {
    let gasto: Gasto

    var body: some View {
        HStack(spacing: 12) {
            IconoCategoria(categoria: gasto.categoria)
            VStack(alignment: .leading, spacing: 2) {
                Text(gasto.concepto.trimmingCharacters(in: .whitespaces)).font(.body).lineLimit(1)
                Text("\(gasto.categoria) · \(Formato.metodo(gasto.metodo)) · \(gasto.fecha.formatted(Formato.hora))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Formato.eur(gasto.importe)).font(.body.weight(.semibold)).monospacedDigit()
            if gasto.pendiente {
                ProgressView().controlSize(.mini)
            }
        }
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
