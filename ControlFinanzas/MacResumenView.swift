#if os(macOS)
import SwiftUI
import Charts

/// Resumen del mes con diseño de escritorio: cifras clave arriba, gráfico grande y dos columnas debajo.
struct MacResumenView: View {
    @Environment(Almacen.self) private var almacen
    @Environment(Navegacion.self) private var navegacion
    private var mes: Mes {
        get { navegacion.mesResumen }
        nonmutating set { navegacion.mesResumen = newValue }
    }
    @State private var editandoPresupuesto = false
    @State private var cerrandoMes = false
    @State private var editando: Gasto?

    var body: some View {
        let r = almacen.resumen(de: mes)
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if let error = almacen.error { AvisoError(mensaje: error) }

                FilaIndicadores(resumen: r) { editandoPresupuesto = true }

                if r.gastos.isEmpty {
                    Panel {
                        ContentUnavailableView("Sin gastos en \(mes.nombre.lowercased())", systemImage: "eurosign.circle",
                                               description: Text("Los gastos que registres aparecerán aquí."))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                } else {
                    Panel(titulo: "Gasto acumulado") { GraficoAcumuladoMac(resumen: r) }

                    HStack(alignment: .top, spacing: 48) {
                        Panel(titulo: "Por categoría") { CategoriasMac(resumen: r) }
                        Panel(titulo: "Últimos movimientos", accion: ("Ver todos", { navegacion.seccion = .movimientos })) {
                            UltimosMovimientos(gastos: Array(r.gastos.prefix(10))) { editando = $0 }
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
        .background(Color.fondo)
        .navigationTitle(mes.nombre)
        .navigationSubtitle(mes.personalizado ? mes.rango : (mes == .actual ? "Mes en curso" : "Resumen"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button { mes = mes.anterior } label: { Label("Mes anterior", systemImage: "chevron.left") }
                    Button { mes = mes.siguiente } label: { Label("Mes siguiente", systemImage: "chevron.right") }
                        .disabled(mes >= .actual)
                }
                .help("Cambiar de mes")
            }
            if mes != .actual {
                ToolbarItem(placement: .navigation) {
                    Button("Hoy") { mes = .actual }
                }
            }
            if mes == .actual {
                ToolbarItem {
                    Button { cerrandoMes = true } label: { Label("Cerrar el mes", systemImage: "calendar.badge.checkmark") }
                        .help("Cerrar el mes hoy y abrir el siguiente (si ya has cobrado)")
                }
            }
            ToolbarItem {
                BotonRecargar()
            }
            ToolbarItem {
                Button { navegacion.mostrandoNuevo = true } label: { Label("Nuevo gasto", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $editandoPresupuesto) { PresupuestoView(mes: mes) }
        .sheet(isPresented: $cerrandoMes) {
            CerrarMesView { abierto in mes = abierto }.fontDesign(.rounded)
        }
        .sheet(item: $editando) { EditarGastoView(gasto: $0) }
    }
}

// MARK: - Piezas

/// Contenedor integrado con la ventana (en lugar de tarjetas flotantes).
private struct Panel<Contenido: View>: View {
    var titulo: String?
    var accion: (String, () -> Void)?
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let titulo {
                HStack {
                    Text(titulo).font(.title3.bold())
                    Spacer()
                    if let accion {
                        Button(action: accion.1) {
                            HStack(spacing: 2) { Text(accion.0); Image(systemName: "chevron.right").imageScale(.small) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            contenido
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct FilaIndicadores: View {
    let resumen: ResumenMes
    let editarPresupuesto: () -> Void

    var body: some View {
        let r = resumen
        let colorProgreso: Color = r.progreso >= 1 ? Tema.alerta : Tema.tinta
        HStack(alignment: .top, spacing: 28) {
            Indicador(titulo: r.restante >= 0 ? "Te quedan" : "Te has pasado",
                      valor: Formato.eur(abs(r.restante)), grande: true,
                      color: r.restante >= 0 ? .primary : .red) {
                ProgressView(value: min(r.progreso, 1)).tint(colorProgreso)
                Text("\(Int((r.progreso * 100).rounded()))% del presupuesto gastado")
            }
            .frame(minWidth: 240)

            Indicador(titulo: "Gastado", valor: Formato.eur(r.totalGastado)) {
                Text("\(r.gastos.count) gastos")
            }

            Button(action: editarPresupuesto) {
                Indicador(titulo: "Presupuesto", valor: Formato.eur(r.presupuesto), icono: "pencil") {
                    Text(r.totalExtra > 0 ? "Incluye \(Formato.eur(r.totalExtra)) extra" : "Base mensual")
                }
            }
            .buttonStyle(.plain)
            .help("Cambiar el presupuesto o añadir ingresos extra")

            if r.mes == .actual {
                Indicador(titulo: "Puedes gastar al día", valor: r.disponiblePorDia.map(Formato.eur) ?? "—") {
                    Text("\(r.diasRestantes) días restantes")
                }
                Indicador(titulo: "Previsión fin de mes", valor: Formato.eurSinDecimales(r.proyeccion),
                          color: r.proyeccion > r.presupuesto ? Tema.alerta : .primary) {
                    Text("Media de \(Formato.eur(r.mediaDiaria)) al día")
                }
            } else {
                Indicador(titulo: r.restante >= 0 ? "Ahorrado" : "Exceso", valor: Formato.eur(abs(r.restante)),
                          color: r.restante >= 0 ? .primary : Tema.alerta) {
                    Text("Media de \(Formato.eur(r.mediaDiaria)) al día")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Indicador<Detalle: View>: View {
    let titulo: String
    let valor: String
    var grande = false
    var color: Color = .primary
    var icono: String?
    @ViewBuilder var detalle: Detalle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(titulo)
                if let icono { Image(systemName: icono).imageScale(.small) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(valor)
                .font(.system(size: grande ? 34 : 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) { detalle }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

private struct GraficoAcumuladoMac: View {
    let resumen: ResumenMes
    @Environment(Navegacion.self) private var navegacion
    @State private var diaSeleccionado: Int?

    /// Día del mes bajo el puntero, o `nil` si está fuera del gráfico o en un día que aún no ha llegado.
    private func dia(en x: CGFloat, _ proxy: ChartProxy, _ geo: GeometryProxy) -> Int? {
        guard let marco = proxy.plotFrame else { return nil }
        let origen = geo[marco].origin.x
        guard let valor = proxy.value(atX: x - origen, as: Double.self) else { return nil }
        let d = Int(valor.rounded())
        return resumen.acumuladoPorDia.contains { $0.dia == d } ? d : nil
    }

    var body: some View {
        let r = resumen
        let puntos = r.acumuladoPorDia
        let ritmo = r.presupuesto / Double(r.mes.numeroDeDias)
        let punto = diaSeleccionado.flatMap { d in puntos.first { $0.dia == d } }

        Chart {
            ForEach(puntos, id: \.dia) { p in
                AreaMark(x: .value("Día", p.dia), y: .value("Gastado", p.total))
                    .foregroundStyle(Tema.tinta.opacity(0.06).gradient)
                LineMark(x: .value("Día", p.dia), y: .value("Gastado", p.total), series: .value("Serie", "Real"))
                    .foregroundStyle(Tema.tinta)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            LineMark(x: .value("Día", 1), y: .value("Ideal", ritmo), series: .value("Serie", "Ideal"))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            LineMark(x: .value("Día", r.mes.numeroDeDias), y: .value("Ideal", r.presupuesto), series: .value("Serie", "Ideal"))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Presupuesto", r.presupuesto))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, alignment: .leading) {
                    Text("Presupuesto \(Formato.eurSinDecimales(r.presupuesto))").font(.caption2).foregroundStyle(.secondary)
                }
            if let punto {
                RuleMark(x: .value("Día", punto.dia))
                    .foregroundStyle(.secondary.opacity(0.4))
                PointMark(x: .value("Día", punto.dia), y: .value("Gastado", punto.total))
                    .foregroundStyle(Tema.tinta)
                    .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.mes.fecha(dia: punto.dia).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))).capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(Formato.eur(punto.total)).font(.callout.bold())
                            let delDia = r.gastos.filter { r.mes.dia(de: $0.fecha) == punto.dia }
                            Text(delDia.isEmpty ? "Sin gastos ese día"
                                 : "\(Formato.eur(delDia.reduce(0) { $0 + $1.importe })) ese día · \(delDia.count) \(delDia.count == 1 ? "gasto" : "gastos")")
                                .font(.caption2).foregroundStyle(.secondary)
                            let diferencia = punto.total - ritmo * Double(punto.dia)
                            Text(diferencia > 0 ? "\(Formato.eur(diferencia)) por encima del ritmo"
                                                : "\(Formato.eur(-diferencia)) por debajo del ritmo")
                                .font(.caption2).foregroundStyle(diferencia > 0 ? Tema.alerta : .secondary)
                        }
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartXScale(domain: 1...r.mes.numeroDeDias)
        // Pasar el ratón muestra el día; hacer clic abre sus gastos.
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { fase in
                        switch fase {
                        case .active(let p): diaSeleccionado = dia(en: p.x, proxy, geo)
                        case .ended: diaSeleccionado = nil
                        }
                    }
                    .onTapGesture { p in
                        guard let d = dia(en: p.x, proxy, geo) else { return }
                        navegacion.seccion = .dia(r.mes.fecha(dia: d))
                    }
                    .pointerStyle(diaSeleccionado == nil ? .default : .link)
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(Formato.eurSinDecimales(d)) } }
            }
        }
        .frame(height: 260)

        HStack(spacing: 16) {
            Label("Gasto real", systemImage: "line.diagonal").foregroundStyle(Tema.tinta)
            Label("Ritmo para llegar justo al presupuesto", systemImage: "line.diagonal").foregroundStyle(.secondary)
            Spacer()
            Text("Haz clic en un día para ver sus gastos").foregroundStyle(.tertiary)
        }
        .font(.caption)
    }
}

private struct CategoriasMac: View {
    let resumen: ResumenMes
    @Environment(Navegacion.self) private var navegacion
    @State private var anguloSeleccionado: Double?

    private var seleccionada: String? {
        guard let anguloSeleccionado else { return nil }
        var acumulado = 0.0
        for c in resumen.porCategoria {
            acumulado += c.total
            if anguloSeleccionado <= acumulado { return c.categoria }
        }
        return nil
    }

    var body: some View {
        let datos = resumen.porCategoria
        let total = resumen.totalGastado
        let actual = seleccionada.flatMap { s in datos.first { $0.categoria == s } }

        // Leyenda al lado del gráfico si cabe; si la ventana es estrecha, debajo.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                grafico(datos: datos, total: total, actual: actual)
                leyenda(datos: datos, total: total).frame(minWidth: 240)
            }
            VStack(spacing: 16) {
                grafico(datos: datos, total: total, actual: actual)
                leyenda(datos: datos, total: total)
            }
        }
    }

    private func grafico(datos: [(categoria: String, total: Double)], total: Double,
                         actual: (categoria: String, total: Double)?) -> some View {
        Chart(datos, id: \.categoria) { d in
            SectorMark(angle: .value("Total", d.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(Tema.gris(datos.firstIndex { $0.categoria == d.categoria } ?? 0, de: datos.count))
                .opacity(seleccionada == nil || seleccionada == d.categoria ? 1 : 0.35)
        }
        .chartAngleSelection(value: $anguloSeleccionado)
        .chartBackground { _ in
            VStack(spacing: 2) {
                Text(Formato.eurSinDecimales(actual?.total ?? total)).font(.title2.bold()).monospacedDigit()
                Text(actual?.categoria ?? "Total").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: 110)
        }
        .frame(width: 180, height: 180)
    }

    private func leyenda(datos: [(categoria: String, total: Double)], total: Double) -> some View {
        VStack(spacing: 2) {
            ForEach(datos, id: \.categoria) { d in
                Button {
                    navegacion.seccion = .categoria(d.categoria)
                } label: {
                    HStack(spacing: 10) {
                        IconoCategoria(categoria: d.categoria, tamaño: 26)
                        Text(d.categoria).lineLimit(1).fixedSize()
                        Spacer(minLength: 8)
                        Text("\(Int((d.total / total * 100).rounded()))%")
                            .foregroundStyle(.secondary).monospacedDigit()
                            .fixedSize()
                        Text(Formato.eur(d.total)).monospacedDigit()
                            .frame(minWidth: 64, alignment: .trailing)
                            .fixedSize()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(seleccionada == d.categoria ? Tema.tinta.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ver los gastos de \(d.categoria)")
            }
        }
        .font(.callout)
    }
}

private struct UltimosMovimientos: View {
    let gastos: [Gasto]
    let editar: (Gasto) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(gastos) { g in
                Button { editar(g) } label: {
                    HStack(spacing: 10) {
                        IconoCategoria(categoria: g.categoria, concepto: g.concepto, tamaño: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.concepto.trimmingCharacters(in: .whitespaces)).fontWeight(.semibold).lineLimit(1)
                            Text("\(g.categoria) · \(Formato.metodo(g.metodo))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Formato.eur(g.importe)).monospacedDigit()
                            Text(g.fecha.formatted(.dateTime.day().month(.abbreviated).hour().minute()
                                .locale(Locale(identifier: "es_ES"))))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(g.pendiente)
            }
        }
        .font(.callout)
    }
}
#endif
