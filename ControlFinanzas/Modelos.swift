import Foundation

struct Gasto: Codable, Identifiable, Hashable {
    let id: String
    var fecha: Date
    var importe: Double
    var concepto: String
    var categoria: String
    var metodo: String
    /// Fila en la hoja (pista para localizarlo al editar).
    var fila: Int?

    /// Recién creado y aún sin confirmar por la hoja: no se puede editar todavía.
    var pendiente: Bool { id.hasPrefix("local-") }
}

struct IngresoExtra: Codable, Identifiable, Hashable {
    let id: String
    let fecha: Date
    let importe: Double
    let concepto: String
}

struct PresupuestoMes: Codable, Hashable {
    let mes: String   // "aaaa-MM"
    let base: Double
}

struct Regla: Codable, Hashable {
    let palabra: String
    let categoria: String
}

struct DatosFinanzas: Codable {
    var gastos: [Gasto]
    var reglas: [Regla]
    var presupuestos: [PresupuestoMes]
    var ingresos: [IngresoExtra]
    var frecuentes: [Frecuente] = []
    var presupuestoPorDefecto: Double

    static let vacio = DatosFinanzas(gastos: [], reglas: [], presupuestos: [], ingresos: [], presupuestoPorDefecto: 450)

    init(gastos: [Gasto], reglas: [Regla], presupuestos: [PresupuestoMes], ingresos: [IngresoExtra],
         frecuentes: [Frecuente] = [], presupuestoPorDefecto: Double) {
        self.gastos = gastos
        self.reglas = reglas
        self.presupuestos = presupuestos
        self.ingresos = ingresos
        self.frecuentes = frecuentes
        self.presupuestoPorDefecto = presupuestoPorDefecto
    }

    /// `frecuentes` es opcional al leer: scripts antiguos y la caché previa no lo traen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gastos = try c.decode([Gasto].self, forKey: .gastos)
        reglas = try c.decode([Regla].self, forKey: .reglas)
        presupuestos = try c.decode([PresupuestoMes].self, forKey: .presupuestos)
        ingresos = try c.decode([IngresoExtra].self, forKey: .ingresos)
        frecuentes = try c.decodeIfPresent([Frecuente].self, forKey: .frecuentes) ?? []
        presupuestoPorDefecto = try c.decode(Double.self, forKey: .presupuestoPorDefecto)
    }
}

/// Identifica un mes natural, p. ej. octubre de 2026.
struct Mes: Hashable, Comparable, Identifiable {
    let año: Int
    let mes: Int

    var id: String { clave }
    var clave: String { String(format: "%04d-%02d", año, mes) }

    init(año: Int, mes: Int) {
        self.año = año
        self.mes = mes
    }

    init(_ fecha: Date, calendario: Calendar = .current) {
        let c = calendario.dateComponents([.year, .month], from: fecha)
        self.init(año: c.year!, mes: c.month!)
    }

    init?(clave: String) {
        let partes = clave.split(separator: "-").compactMap { Int($0) }
        guard partes.count == 2 else { return nil }
        self.init(año: partes[0], mes: partes[1])
    }

    static var actual: Mes { Mes(Date()) }

    var inicio: Date { Calendar.current.date(from: DateComponents(year: año, month: mes, day: 1))! }
    var fin: Date { Calendar.current.date(byAdding: .month, value: 1, to: inicio)! }
    var numeroDeDias: Int { Calendar.current.range(of: .day, in: .month, for: inicio)!.count }

    func sumando(_ meses: Int) -> Mes { Mes(Calendar.current.date(byAdding: .month, value: meses, to: inicio)!) }
    var anterior: Mes { sumando(-1) }
    var siguiente: Mes { sumando(1) }

    func contiene(_ fecha: Date) -> Bool { fecha >= inicio && fecha < fin }

    var nombre: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: inicio).capitalized(with: f.locale)
    }

    var nombreCorto: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLL"
        return f.string(from: inicio).capitalized(with: f.locale)
    }

    static func < (a: Mes, b: Mes) -> Bool { (a.año, a.mes) < (b.año, b.mes) }
}

/// Resumen ya calculado de un mes.
struct ResumenMes {
    let mes: Mes
    let gastos: [Gasto]
    let ingresos: [IngresoExtra]
    let base: Double

    var totalGastado: Double { gastos.reduce(0) { $0 + $1.importe } }
    var totalExtra: Double { ingresos.reduce(0) { $0 + $1.importe } }
    var presupuesto: Double { base + totalExtra }
    var restante: Double { presupuesto - totalGastado }
    var progreso: Double { presupuesto > 0 ? totalGastado / presupuesto : 0 }

    var porCategoria: [(categoria: String, total: Double)] {
        Dictionary(grouping: gastos, by: \.categoria)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.importe }) }
            .sorted { $0.1 > $1.1 }
    }

    var porMetodo: [(metodo: String, total: Double)] {
        Dictionary(grouping: gastos, by: { Formato.metodo($0.metodo) })
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.importe }) }
            .sorted { $0.1 > $1.1 }
    }

    /// Días transcurridos del mes (todo el mes si ya terminó).
    var diasTranscurridos: Int {
        let hoy = Date()
        if hoy >= mes.fin { return mes.numeroDeDias }
        if hoy < mes.inicio { return 0 }
        return Calendar.current.component(.day, from: hoy)
    }

    var diasRestantes: Int { mes.numeroDeDias - diasTranscurridos }

    var mediaDiaria: Double { diasTranscurridos > 0 ? totalGastado / Double(diasTranscurridos) : 0 }

    /// Lo que puedes gastar al día a partir de hoy para no pasarte.
    var disponiblePorDia: Double? {
        guard diasRestantes > 0 else { return nil }
        return max(restante, 0) / Double(diasRestantes + 1)
    }

    /// Gasto estimado a final de mes al ritmo actual.
    var proyeccion: Double { mediaDiaria * Double(mes.numeroDeDias) }

    /// Gasto acumulado por día, para el gráfico.
    var acumuladoPorDia: [(dia: Int, total: Double)] {
        let cal = Calendar.current
        var porDia = [Int: Double]()
        for g in gastos { porDia[cal.component(.day, from: g.fecha), default: 0] += g.importe }
        var acumulado = 0.0
        return (1...max(diasTranscurridos, 1)).map { dia in
            acumulado += porDia[dia] ?? 0
            return (dia, acumulado)
        }
    }
}
