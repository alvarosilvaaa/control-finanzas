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
            .background(Color.fondo)
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
                            .foregroundStyle(Tema.tinta.opacity(0.06).gradient)
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
    /// Categoría (o "Otras") resaltada en el gráfico.
    @State private var seleccion: String?

    private static let otras = "Otras"
    /// Por debajo de este peso, una categoría se agrupa en "Otras" dentro del gráfico.
    private static let umbral = 0.04

    private var total: Double { resumen.totalGastado }

    /// Categorías pequeñas que se juntan en "Otras" (solo si hay al menos dos).
    private var pequeñas: [(categoria: String, total: Double)] {
        guard total > 0 else { return [] }
        let lista = resumen.porCategoria.filter { $0.total / total < Self.umbral }
        return lista.count >= 2 ? lista : []
    }

    /// Porciones del gráfico: las categorías grandes y, al final, "Otras".
    private var porciones: [(categoria: String, total: Double)] {
        let agrupadas = Set(pequeñas.map(\.categoria))
        var lista = resumen.porCategoria.filter { !agrupadas.contains($0.categoria) }
        if !pequeñas.isEmpty { lista.append((Self.otras, pequeñas.reduce(0) { $0 + $1.total })) }
        return lista
    }

    /// Porción a la que pertenece una categoría.
    private func porcion(de categoria: String) -> String {
        pequeñas.contains { $0.categoria == categoria } ? Self.otras : categoria
    }

    /// Porción bajo un punto del gráfico, o `nil` si el punto no cae sobre el anillo.
    /// Las porciones empiezan arriba (las 12) y avanzan en el sentido de las agujas del reloj.
    private func porcion(en punto: CGPoint, marco: CGRect) -> String? {
        let dx = punto.x - marco.midX, dy = punto.y - marco.midY
        let radio = min(marco.width, marco.height) / 2
        let distancia = (dx * dx + dy * dy).squareRoot()
        guard distancia >= radio * 0.5, distancia <= radio * 1.15, total > 0 else { return nil }
        var angulo = atan2(dx, -dy)
        if angulo < 0 { angulo += 2 * .pi }
        let valor = angulo / (2 * .pi) * porciones.reduce(0) { $0 + $1.total }
        var acumulado = 0.0
        for p in porciones {
            acumulado += p.total
            if valor <= acumulado { return p.categoria }
        }
        return porciones.last?.categoria
    }

    var body: some View {
        let porciones = porciones
        let resaltada = seleccion.map(porcion(de:))
        Tarjeta {
            VStack(alignment: .leading, spacing: 12) {
                Text("Por categoría").font(.headline)
                Chart(porciones, id: \.categoria) { d in
                    let indice = porciones.firstIndex { $0.categoria == d.categoria } ?? 0
                    SectorMark(angle: .value("Total", d.total),
                               innerRadius: .ratio(0.62),
                               outerRadius: .ratio(resaltada == d.categoria ? 1 : 0.94),
                               angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(resaltada == d.categoria ? Tema.tinta : Tema.gris(indice, de: porciones.count))
                        .opacity(resaltada == nil || resaltada == d.categoria ? 1 : 0.25)
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let marco = proxy.plotFrame.map { geo[$0] } ?? geo.frame(in: .local)
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            // Tocar una porción la selecciona; tocar la misma otra vez la quita.
                            .onTapGesture { punto in
                                guard let p = porcion(en: punto, marco: marco) else { return }
                                seleccion = seleccion.map(porcion(de:)) == p ? nil : p
                            }
                    }
                }
                .overlay { centro }
                .frame(height: 220)
                .animation(.snappy(duration: 0.25), value: seleccion)
                .sensoryFeedback(.selection, trigger: seleccion)

                VStack(spacing: 0) {
                    ForEach(resumen.porCategoria, id: \.categoria) { d in
                        fila(d)
                        if d.categoria != resumen.porCategoria.last?.categoria { Divider().padding(.leading, 42) }
                    }
                }
            }
        }
    }

    // MARK: - Centro del anillo

    @ViewBuilder private var centro: some View {
        if let seleccion {
            if seleccion == Self.otras {
                NavigationLink {
                    ListaGastosView(titulo: "Otras categorías") { [mes = resumen.mes, nombres = Set(pequeñas.map(\.categoria))] in
                        mes.contiene($0.fecha) && nombres.contains($0.categoria)
                    }
                } label: {
                    textoCentro(titulo: "Otras", importe: pequeñas.reduce(0) { $0 + $1.total },
                                detalle: "\(pequeñas.count) categorías")
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: seleccion) {
                    let gastado = resumen.porCategoria.first { $0.categoria == seleccion }?.total ?? 0
                    let cuantos = resumen.gastos.filter { $0.categoria == seleccion }.count
                    textoCentro(titulo: seleccion, importe: gastado,
                                detalle: "\(cuantos) \(cuantos == 1 ? "gasto" : "gastos")")
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 2) {
                Text(Formato.eurSinDecimales(total)).font(.title2.bold())
                Text("\(resumen.gastos.count) gastos").font(.caption).foregroundStyle(.secondary)
                Text("Toca el gráfico").font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
            }
            .allowsHitTesting(false)
        }
    }

    private func textoCentro(titulo: String, importe: Double, detalle: String) -> some View {
        let porcentaje = total > 0 ? Int((importe / total * 100).rounded()) : 0
        return VStack(spacing: 2) {
            Text(titulo).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(Formato.eur(importe)).font(.title3.bold()).monospacedDigit()
            Text("\(porcentaje) % · \(detalle)").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text("Ver gastos")
                Image(systemName: "chevron.right").imageScale(.small)
            }
            .font(.caption2.weight(.semibold))
            .padding(.top, 2)
        }
        .frame(width: 120, height: 120)
        .contentShape(Circle())
        .transition(.opacity)
    }

    // MARK: - Lista

    /// La primera vez que tocas una fila se resalta en el gráfico; si ya estaba resaltada, abre sus gastos.
    @ViewBuilder private func fila(_ d: (categoria: String, total: Double)) -> some View {
        let elegida = seleccion == d.categoria
        let contenido = HStack(spacing: 12) {
            IconoCategoria(categoria: d.categoria, tamaño: 30)
            Text(d.categoria).foregroundStyle(.primary)
            Spacer()
            Text("\(total > 0 ? Int((d.total / total * 100).rounded()) : 0)%")
                .font(.caption).foregroundStyle(.secondary)
            Text(Formato.eur(d.total)).font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(elegida ? .secondary : .tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(elegida ? Tema.tinta.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, -8)
        .contentShape(Rectangle())

        if elegida {
            NavigationLink(value: d.categoria) { contenido }
                .buttonStyle(.plain)
        } else {
            Button { seleccion = d.categoria } label: { contenido }
                .buttonStyle(.plain)
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
            .padding(.horizontal, -14)
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
