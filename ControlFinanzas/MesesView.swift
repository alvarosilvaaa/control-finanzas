import SwiftUI
import Charts

struct MesesView: View {
    @Environment(Almacen.self) private var almacen

    var body: some View {
        let resumenes = almacen.meses.map { almacen.resumen(de: $0) }
        NavigationStack {
            List {
                if resumenes.count > 1 {
                    Section {
                        Chart(resumenes.reversed(), id: \.mes) { r in
                            BarMark(x: .value("Mes", r.mes.nombreCorto), y: .value("Gastado", r.totalGastado))
                                .foregroundStyle(r.restante < 0 ? Color.red.gradient : Color.accentColor.gradient)
                                .cornerRadius(6)
                        }
                        .frame(height: 160)
                        .padding(.vertical, 8)
                    }
                }
                Section("Resúmenes mensuales") {
                    ForEach(resumenes, id: \.mes) { r in
                        NavigationLink {
                            ResumenMensualView(mes: r.mes)
                        } label: {
                            FilaMes(resumen: r)
                        }
                    }
                }
            }
            .navigationTitle("Meses")
            .refreshable { await almacen.recargar() }
        }
    }
}

private struct FilaMes: View {
    let resumen: ResumenMes

    var body: some View {
        let r = resumen
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.mes.nombre).font(.headline)
                if r.mes == .actual {
                    Text("En curso").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule()).foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text(Formato.eur(r.totalGastado)).bold()
            }
            ProgressView(value: min(r.progreso, 1)).tint(r.progreso >= 1 ? .red : .accentColor)
            Text(r.restante >= 0 ? "Ahorrado \(Formato.eur(r.restante)) de \(Formato.eur(r.presupuesto))"
                                 : "Pasado \(Formato.eur(-r.restante)) de \(Formato.eur(r.presupuesto))")
                .font(.caption).foregroundStyle(r.restante >= 0 ? Color.secondary : Color.red)
        }
        .padding(.vertical, 4)
    }
}

/// Resumen de un mes con comparación frente al mes anterior.
struct ResumenMensualView: View {
    let mes: Mes
    @Environment(Almacen.self) private var almacen

    var body: some View {
        let r = almacen.resumen(de: mes)
        let anterior = almacen.resumen(de: mes.anterior)
        let totalesAnterior = Dictionary(uniqueKeysWithValues: anterior.porCategoria.map { ($0.categoria, $0.total) })

        List {
            Section {
                LabeledContent("Presupuesto", value: Formato.eur(r.presupuesto))
                LabeledContent("Gastado", value: Formato.eur(r.totalGastado))
                LabeledContent(r.restante >= 0 ? "Ahorrado" : "Exceso") {
                    Text(Formato.eur(abs(r.restante))).bold().foregroundStyle(r.restante >= 0 ? .green : .red)
                }
                LabeledContent("Número de gastos", value: "\(r.gastos.count)")
                LabeledContent("Media diaria", value: Formato.eur(r.mediaDiaria))
                if !anterior.gastos.isEmpty {
                    LabeledContent("Frente a \(mes.anterior.nombre.lowercased())") {
                        Variacion(actual: r.totalGastado, anterior: anterior.totalGastado)
                    }
                }
            }

            Section("Categorías") {
                ForEach(r.porCategoria, id: \.categoria) { c in
                    NavigationLink {
                        ListaGastosView(titulo: c.categoria) { mes.contiene($0.fecha) && $0.categoria == c.categoria }
                    } label: {
                        HStack(spacing: 12) {
                            IconoCategoria(categoria: c.categoria, tamaño: 30)
                            VStack(alignment: .leading) {
                                Text(c.categoria)
                                if !anterior.gastos.isEmpty {
                                    Variacion(actual: c.total, anterior: totalesAnterior[c.categoria] ?? 0)
                                        .font(.caption)
                                }
                            }
                            Spacer()
                            Text(Formato.eur(c.total)).bold()
                        }
                    }
                }
            }

            Section("Por método de pago") {
                ForEach(r.porMetodo, id: \.metodo) { m in
                    LabeledContent(m.metodo, value: Formato.eur(m.total))
                }
            }

            if !r.gastos.isEmpty {
                Section("Gastos más grandes") {
                    ForEach(r.gastos.sorted { $0.importe > $1.importe }.prefix(5)) { FilaGasto(gasto: $0) }
                }
            }

            if !r.ingresos.isEmpty {
                Section("Ingresos extra") {
                    ForEach(r.ingresos) { i in LabeledContent(i.concepto, value: "+" + Formato.eur(i.importe)) }
                }
            }
        }
        .navigationTitle(mes.nombre)
        .tituloEnLinea()
    }
}

/// Muestra la variación frente al mes anterior (rojo si gastas más, verde si menos).
struct Variacion: View {
    let actual: Double
    let anterior: Double

    var body: some View {
        if anterior == 0 {
            Text(actual > 0 ? "Nuevo" : "—").foregroundStyle(.secondary)
        } else {
            let cambio = (actual - anterior) / anterior
            Label("\(cambio >= 0 ? "+" : "")\(Int((cambio * 100).rounded()))%",
                  systemImage: cambio >= 0 ? "arrow.up.right" : "arrow.down.right")
                .foregroundStyle(cambio > 0 ? .red : .green)
        }
    }
}
