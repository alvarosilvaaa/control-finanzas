import SwiftUI
import Charts

struct ResumenView: View {
    @Environment(Almacen.self) private var almacen
    @Binding var mostrandoNuevo: Bool
    @State private var mes = Mes.actual
    @State private var mostrandoPresupuesto = false

    var body: some View {
        let r = almacen.resumen(de: mes)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SelectorMes(mes: $mes)

                    if let error = almacen.error {
                        AvisoError(mensaje: error)
                    }
                }
                .padding(.horizontal, 16)
                Rejilla {

                    TarjetaPresupuesto(resumen: r) { mostrandoPresupuesto = true }

                    if !almacen.sinClasificar.isEmpty {
                        AvisoSinClasificar(cantidad: almacen.sinClasificar.count)
                    }

                    if r.mes == .actual {
                        TarjetaRitmo(resumen: r)
                    }

                    if !r.gastos.isEmpty {
                        GraficoAcumulado(resumen: r)
                        GraficoCategorias(resumen: r)
                    } else {
                        Tarjeta {
                            ContentUnavailableView("Sin gastos este mes", systemImage: "eurosign.circle",
                                                   description: Text("Los gastos que registres aparecerán aquí."))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Sistema.esMac ? 16 : 90)
            }
            .background(Color.fondoAgrupado)
            .navigationTitle("Finanzas")
            .refreshable { await almacen.recargar() }
            #if os(iOS)
            .overlay(alignment: .bottomTrailing) {
                BotonAñadir { mostrandoNuevo = true }
            }
            .toolbar {
                if almacen.cargando { ProgressView() }
            }
            #else
            .toolbar {
                ToolbarItem {
                    if almacen.cargando { ProgressView().controlSize(.small) } else {
                        Button { Task { await almacen.recargar() } } label: { Label("Recargar", systemImage: "arrow.clockwise") }
                    }
                }
                ToolbarItem {
                    Button { mostrandoNuevo = true } label: { Label("Nuevo gasto", systemImage: "plus") }
                }
            }
            #endif
            .sheet(isPresented: $mostrandoPresupuesto) {
                PresupuestoView(mes: mes)
            }
            .navigationDestination(for: String.self) { categoria in
                ListaGastosView(titulo: categoria) { [mes] in mes.contiene($0.fecha) && $0.categoria == categoria }
            }
        }
    }
}

/// Una columna en iPhone; tarjetas en varias columnas en Mac.
private struct Rejilla<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido

    var body: some View {
        #if os(macOS)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)], spacing: 16) {
            contenido
        }
        #else
        VStack(spacing: 16) { contenido }
        #endif
    }
}

struct SelectorMes: View {
    @Binding var mes: Mes

    var body: some View {
        HStack {
            Button { mes = mes.anterior } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(mes.nombre).font(.headline)
            Spacer()
            Button { mes = mes.siguiente } label: { Image(systemName: "chevron.right") }
                .disabled(mes >= .actual)
        }
        .font(.title3.weight(.semibold))
        .padding(.vertical, 4)
    }
}

private struct TarjetaPresupuesto: View {
    let resumen: ResumenMes
    let editar: () -> Void

    var body: some View {
        let r = resumen
        let color: Color = r.progreso >= 1 ? Tema.alerta : Tema.tinta
        Tarjeta {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.restante >= 0 ? "Te quedan" : "Te has pasado")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(Formato.eur(abs(r.restante)))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(r.restante >= 0 ? Color.primary : Tema.alerta)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Gauge(value: min(r.progreso, 1)) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(Int((r.progreso * 100).rounded()))%").font(.caption.bold())
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(color)
                    .scaleEffect(1.2)
                    .padding(6)
                }

                ProgressView(value: min(r.progreso, 1)).tint(color)

                HStack {
                    Dato(titulo: "Gastado", valor: Formato.eur(r.totalGastado))
                    Spacer()
                    Button(action: editar) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Presupuesto")
                                Image(systemName: "pencil.circle.fill")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            Text(Formato.eur(r.presupuesto)).font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }

                if r.totalExtra > 0 {
                    Label("Incluye \(Formato.eur(r.totalExtra)) de ingresos extra", systemImage: "plus.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TarjetaRitmo: View {
    let resumen: ResumenMes

    var body: some View {
        let r = resumen
        Tarjeta {
            HStack {
                if let porDia = r.disponiblePorDia {
                    Dato(titulo: "Puedes gastar/día", valor: Formato.eur(porDia))
                    Spacer()
                }
                Dato(titulo: "Media diaria", valor: Formato.eur(r.mediaDiaria))
                Spacer()
                Dato(titulo: "Fin de mes", valor: Formato.eurSinDecimales(r.proyeccion),
                     color: r.proyeccion > r.presupuesto ? Tema.alerta : .primary)
            }
        }
    }
}

struct Dato: View {
    let titulo: String
    let valor: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).font(.caption).foregroundStyle(.secondary)
            Text(valor).font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
    }
}

private struct GraficoAcumulado: View {
    let resumen: ResumenMes

    var body: some View {
        let r = resumen
        Tarjeta {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gasto acumulado").font(.headline)
                Chart {
                    ForEach(r.acumuladoPorDia, id: \.dia) { punto in
                        AreaMark(x: .value("Día", punto.dia), y: .value("Gastado", punto.total))
                            .foregroundStyle(Tema.tinta.opacity(0.15).gradient)
                        LineMark(x: .value("Día", punto.dia), y: .value("Gastado", punto.total),
                                 series: .value("Serie", "Real"))
                            .foregroundStyle(Tema.tinta)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    // Ritmo ideal: repartir el presupuesto por igual entre todos los días.
                    LineMark(x: .value("Día", 1), y: .value("Ideal", r.presupuesto / Double(r.mes.numeroDeDias)),
                             series: .value("Serie", "Ideal"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    LineMark(x: .value("Día", r.mes.numeroDeDias), y: .value("Ideal", r.presupuesto),
                             series: .value("Serie", "Ideal"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("Presupuesto", r.presupuesto))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Presupuesto").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartXScale(domain: 1...r.mes.numeroDeDias)
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel { if let d = v.as(Double.self) { Text(Formato.eurSinDecimales(d)) } }
                    }
                }
                .frame(height: 180)
                HStack(spacing: 12) {
                    Label("Real", systemImage: "line.diagonal").foregroundStyle(Tema.tinta)
                    Label("Ritmo ideal", systemImage: "line.diagonal").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

private struct GraficoCategorias: View {
    let resumen: ResumenMes

    var body: some View {
        let datos = resumen.porCategoria
        let total = resumen.totalGastado
        Tarjeta {
            VStack(alignment: .leading, spacing: 12) {
                Text("Por categoría").font(.headline)
                Chart(datos, id: \.categoria) { d in
                    SectorMark(angle: .value("Total", d.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(Tema.gris(datos.firstIndex { $0.categoria == d.categoria } ?? 0, de: datos.count))
                }
                .chartBackground { _ in
                    VStack {
                        Text(Formato.eurSinDecimales(total)).font(.title2.bold())
                        Text("\(resumen.gastos.count) gastos").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)

                VStack(spacing: 0) {
                    ForEach(datos, id: \.categoria) { d in
                        NavigationLink(value: d.categoria) {
                            HStack(spacing: 12) {
                                IconoCategoria(categoria: d.categoria, tamaño: 30)
                                Text(d.categoria).foregroundStyle(.primary)
                                Spacer()
                                Text("\(Int((d.total / total * 100).rounded()))%")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(Formato.eur(d.total)).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                        }
                        if d.categoria != datos.last?.categoria { Divider().padding(.leading, 42) }
                    }
                }
            }
        }
    }
}

private struct AvisoSinClasificar: View {
    let cantidad: Int

    var body: some View {
        NavigationLink {
            ListaGastosView(titulo: "Sin clasificar") { $0.categoria == "Sin clasificar" }
        } label: {
            HStack(spacing: 12) {
                IconoCategoria(categoria: "Sin clasificar", tamaño: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cantidad == 1 ? "1 gasto sin clasificar" : "\(cantidad) gastos sin clasificar")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Tócalos para asignarles una categoría").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.fondoTarjeta, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct BotonAñadir: View {
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(Color.fondo)
                .frame(width: 60, height: 60)
                .background(Tema.tinta, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .padding(20)
        .accessibilityLabel("Añadir movimiento")
    }
}

struct AvisoError: View {
    let mensaje: String

    var body: some View {
        Label(mensaje, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(Tema.alerta)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.alerta.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
