import Foundation

/// Un consejo de ahorro calculado a partir de los gastos.
struct Consejo: Identifiable {
    enum Tipo: Int, Comparable {
        case alerta, aviso, info, bien
        static func < (a: Tipo, b: Tipo) -> Bool { a.rawValue < b.rawValue }
    }

    let id: String
    let tipo: Tipo
    let icono: String
    let titulo: String
    let texto: String
    /// Si se indica, el consejo ofrece ponerle un límite a esta categoría.
    var limiteSugerido: String? = nil
    /// Gastos a los que se refiere el consejo, para verlos al pulsarlo.
    var detalle: Detalle? = nil

    struct Detalle {
        let titulo: String
        let incluir: (Gasto) -> Bool
    }
}

extension Almacen {
    /// Consejos del mes en curso, los más urgentes primero.
    var consejos: [Consejo] {
        let r = resumen(de: .actual)
        let dias = r.diasTranscurridos
        var lista: [Consejo] = []

        func proyectar(_ gastado: Double) -> Double {
            dias > 0 ? gastado / Double(dias) * Double(r.mes.numeroDeDias) : gastado
        }
        let porCategoria = Dictionary(uniqueKeysWithValues: r.porCategoria.map { ($0.categoria, $0.total) })
        let mes = r.mes
        let delMes = Consejo.Detalle(titulo: "Gastos de \(mes.nombreMes.lowercased())") { mes.contiene($0.fecha) }
        func deCategoria(_ c: String) -> Consejo.Detalle {
            Consejo.Detalle(titulo: "\(c) · \(mes.nombreMes.lowercased())") { $0.categoria == c && mes.contiene($0.fecha) }
        }

        // 1. Ritmo del mes
        if r.restante < 0 {
            lista.append(Consejo(id: "ritmo", tipo: .alerta, icono: "exclamationmark.triangle",
                                 titulo: "Te has pasado del presupuesto",
                                 texto: "Llevas \(Formato.eur(r.totalGastado)), \(Formato.eur(-r.restante)) por encima de \(Formato.eurSinDecimales(r.presupuesto)).",
                                 detalle: delMes))
        } else if dias >= 3, r.proyeccion > r.presupuesto {
            var texto = "Acabarías el mes en unos \(Formato.eurSinDecimales(r.proyeccion)), \(Formato.eurSinDecimales(r.proyeccion - r.presupuesto)) por encima del presupuesto."
            if let porDia = r.disponiblePorDia {
                texto += " Para no pasarte, gasta como máximo \(Formato.eur(porDia)) al día lo que queda de mes."
            }
            lista.append(Consejo(id: "ritmo", tipo: .alerta, icono: "speedometer",
                                 titulo: "A este ritmo te pasarás", texto: texto, detalle: delMes))
        } else if dias >= 3 {
            lista.append(Consejo(id: "ritmo", tipo: .bien, icono: "checkmark.circle",
                                 titulo: "Vas bien este mes",
                                 texto: "Al ritmo actual acabarías en unos \(Formato.eurSinDecimales(r.proyeccion)), \(Formato.eurSinDecimales(r.presupuesto - r.proyeccion)) por debajo del presupuesto.",
                                 detalle: delMes))
        }

        // 2. Límites por categoría
        for l in limites {
            let gastado = porCategoria[l.categoria] ?? 0
            if gastado > l.limite {
                lista.append(Consejo(id: "limite-\(l.categoria)", tipo: .alerta, icono: "exclamationmark.circle",
                                     titulo: "Te has pasado en \(l.categoria)",
                                     texto: "Llevas \(Formato.eur(gastado)) de \(Formato.eurSinDecimales(l.limite)): \(Formato.eur(gastado - l.limite)) de más.",
                                     detalle: deCategoria(l.categoria)))
            } else if gastado >= l.limite * 0.8 {
                lista.append(Consejo(id: "limite-\(l.categoria)", tipo: .aviso, icono: "gauge.with.dots.needle.67percent",
                                     titulo: "Casi en el límite de \(l.categoria)",
                                     texto: "Llevas \(Formato.eur(gastado)) de \(Formato.eurSinDecimales(l.limite)). Te quedan \(Formato.eur(l.limite - gastado)) para \(r.diasRestantes + 1) días.",
                                     detalle: deCategoria(l.categoria)))
            } else if dias >= 7, proyectar(gastado) > l.limite * 1.1 {
                lista.append(Consejo(id: "limite-\(l.categoria)", tipo: .aviso, icono: "chart.line.uptrend.xyaxis",
                                     titulo: "\(l.categoria) va camino de pasarse",
                                     texto: "Al ritmo actual gastarías unos \(Formato.eurSinDecimales(proyectar(gastado))) y tu límite es \(Formato.eurSinDecimales(l.limite)).",
                                     detalle: deCategoria(l.categoria)))
            }
        }

        // 3. Categorías por encima de lo habitual (necesita meses anteriores)
        if dias >= 7 {
            let subidas = porCategoria.compactMap { categoria, gastado -> (String, Double, Double)? in
                guard categoria != "Sin clasificar", limite(de: categoria) == nil,
                      let media = mediaPrevia(de: categoria) else { return nil }
                let previsto = proyectar(gastado)
                return previsto > media * 1.3 && previsto - media >= 15 ? (categoria, previsto, media) : nil
            }
            for (categoria, previsto, media) in subidas.sorted(by: { $0.1 - $0.2 > $1.1 - $1.2 }).prefix(2) {
                lista.append(Consejo(id: "subida-\(categoria)", tipo: .aviso, icono: "arrow.up.right",
                                     titulo: "Más que de costumbre en \(categoria)",
                                     texto: "Al ritmo actual gastarías unos \(Formato.eurSinDecimales(previsto)) este mes; tu media es \(Formato.eurSinDecimales(media)).",
                                     limiteSugerido: categoria, detalle: deCategoria(categoria)))
            }
        }

        // 4. Gastos hormiga
        let pequeños = r.gastos.filter { $0.importe < 5 }
        if pequeños.count >= 8, dias > 0 {
            let total = pequeños.reduce(0) { $0 + $1.importe }
            let alAño = total / Double(dias) * 365
            let porcentaje = r.totalGastado > 0 ? Int((total / r.totalGastado * 100).rounded()) : 0
            lista.append(Consejo(id: "hormiga", tipo: .info, icono: "ant",
                                 titulo: "Gastos hormiga",
                                 texto: "\(pequeños.count) compras de menos de 5 € suman \(Formato.eur(total)) este mes (\(porcentaje) % de lo gastado). Al año serían unos \(Formato.eurSinDecimales(alAño)); reducirlos a la mitad te ahorraría \(Formato.eurSinDecimales(alAño / 2)).",
                                 detalle: Consejo.Detalle(titulo: "Gastos de menos de 5 €") { $0.importe < 5 && mes.contiene($0.fecha) }))
        }

        // 5. Sitios a los que vas muy a menudo
        let fijos = Set(datos.frecuentes.map { $0.concepto.trimmingCharacters(in: .whitespaces).lowercased() })
        let porSitio = Dictionary(grouping: r.gastos) { $0.concepto.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.value.count >= 4 && !fijos.contains($0.key) }
            .sorted { $0.value.count > $1.value.count }
        for (clave, gastos) in porSitio.prefix(2) {
            let total = gastos.reduce(0) { $0 + $1.importe }
            let nombre = gastos[0].concepto.trimmingCharacters(in: .whitespaces)
            lista.append(Consejo(id: "sitio-\(nombre)", tipo: .info, icono: "repeat",
                                 titulo: "\(gastos.count) veces en \(nombre)",
                                 texto: "Suman \(Formato.eur(total)) este mes, unos \(Formato.eur(total / Double(gastos.count))) cada vez. Agrupar las compras ayuda a evitar caprichos.",
                                 detalle: Consejo.Detalle(titulo: "\(nombre) · \(mes.nombreMes.lowercased())") {
                                     $0.concepto.trimmingCharacters(in: .whitespaces).lowercased() == clave && mes.contiene($0.fecha)
                                 }))
        }

        // 6. Ponerle límite a la categoría que más pesa
        if limites.isEmpty, let mayor = r.porCategoria.first(where: { $0.categoria != "Sin clasificar" }),
           r.totalGastado > 0, mayor.total / r.totalGastado >= 0.15, dias >= 5 {
            let porcentaje = Int((mayor.total / r.totalGastado * 100).rounded())
            lista.append(Consejo(id: "mayor", tipo: .info, icono: "chart.pie",
                                 titulo: "\(mayor.categoria) es tu mayor gasto",
                                 texto: "Llevas \(Formato.eur(mayor.total)) este mes, el \(porcentaje) % del total. Ponerle un límite te ayuda a controlarlo.",
                                 limiteSugerido: mayor.categoria, detalle: deCategoria(mayor.categoria)))
        }

        // 7. Coste anual de los gastos fijos
        let anuales = datos.frecuentes.compactMap { f -> (String, Double)? in
            guard let importe = f.importe else { return nil }
            switch f.frecuencia {
            case .mensual: return (f.concepto, importe * 12)
            case .semanal: return (f.concepto, importe * 52)
            case .ninguna: return nil
            }
        }.sorted { $0.1 > $1.1 }
        if !anuales.isEmpty {
            let total = anuales.reduce(0) { $0 + $1.1 }
            let detalle = anuales.prefix(3).map { "\($0.0) \(Formato.eurSinDecimales($0.1))" }.joined(separator: ", ")
            lista.append(Consejo(id: "fijos", tipo: .info, icono: "calendar.badge.clock",
                                 titulo: "Tus gastos fijos: \(Formato.eurSinDecimales(total)) al año",
                                 texto: "\(detalle). Revisa de vez en cuando si sigues aprovechándolos todos.",
                                 detalle: Consejo.Detalle(titulo: "Gastos fijos") { fijos.contains($0.concepto.trimmingCharacters(in: .whitespaces).lowercased()) }))
        }

        // 8. Gastos sin clasificar (los consejos son mejores con todo clasificado)
        if sinClasificar.count >= 5 {
            lista.append(Consejo(id: "clasificar", tipo: .info, icono: "tag",
                                 titulo: "Clasifica \(sinClasificar.count) gastos",
                                 texto: "Con todos los gastos en su categoría, los consejos y los límites son más precisos.",
                                 detalle: Consejo.Detalle(titulo: "Sin clasificar") { $0.categoria == "Sin clasificar" }))
        }

        return lista.enumerated()
            .sorted { $0.element.tipo != $1.element.tipo ? $0.element.tipo < $1.element.tipo : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Gasto medio mensual de una categoría en los últimos meses con datos (hasta 3, sin contar el actual).
    func mediaPrevia(de categoria: String) -> Double? {
        let anteriores = meses.filter { $0 < .actual }.prefix(3)
        guard !anteriores.isEmpty else { return nil }
        let total = anteriores.reduce(0.0) { suma, mes in
            suma + datos.gastos.filter { $0.categoria == categoria && mes.contiene($0.fecha) }.reduce(0) { $0 + $1.importe }
        }
        return total / Double(anteriores.count)
    }

    /// Límite orientativo para una categoría: algo menos de lo que sueles gastar en ella, redondeado a 5 €.
    func limiteSugerido(para categoria: String) -> Double? {
        let r = resumen(de: .actual)
        let base: Double
        if let media = mediaPrevia(de: categoria), media > 0 {
            base = media
        } else {
            let gastado = r.gastos.filter { $0.categoria == categoria }.reduce(0) { $0 + $1.importe }
            guard gastado > 0, r.diasTranscurridos > 0 else { return nil }
            base = gastado / Double(r.diasTranscurridos) * Double(r.mes.numeroDeDias)
        }
        return max(5, (base * 0.85 / 5).rounded(.down) * 5)
    }

    func gastado(en categoria: String, mes: Mes = .actual) -> Double {
        datos.gastos.filter { $0.categoria == categoria && mes.contiene($0.fecha) }.reduce(0) { $0 + $1.importe }
    }
}
