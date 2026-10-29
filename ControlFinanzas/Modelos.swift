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
    /// Lo pagado de verdad cuando parte del gasto se reparte con el piso; `importe` es entonces solo tu parte.
    var pagado: Double?

    /// Recién creado y aún sin confirmar por la hoja: no se puede editar todavía.
    var pendiente: Bool { id.hasPrefix("local-") }

    /// Importe del ticket completo (el que está en la hoja).
    var total: Double { pagado ?? importe }
    var compartido: Bool { pagado != nil }

    /// Identifica el gasto en la hoja de repartos: su marca temporal en ISO, como la envía el script.
    var clave: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: fecha)
    }
}

/// Qué parte de un gasto se reparte con el piso, y si ya te lo han pagado.
struct Reparto: Codable, Hashable {
    struct Parte: Codable, Hashable {
        var importe: Double
        /// Entre cuántas personas se divide, contándote a ti.
        var personas: Int

        var tuParte: Double { importe / Double(personas) }
        var teDeben: Double { importe - tuParte }
    }

    var clave: String
    var partes: [Parte]
    var saldado: Bool

    static func redondear(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// Lo que te cuesta a ti un ticket de `total`: lo no compartido más tu parte de lo compartido.
    func tuParte(de total: Double) -> Double {
        Self.redondear(total - partes.reduce(0) { $0 + $1.importe } + partes.reduce(0) { $0 + $1.tuParte })
    }

    var teDeben: Double { Self.redondear(partes.reduce(0) { $0 + $1.teDeben }) }
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

/// Algo que quieres comprarte (wishlist).
struct Deseo: Codable, Identifiable, Hashable {
    enum Prioridad: String, Codable, CaseIterable, Identifiable {
        case alta, media, baja
        var id: String { rawValue }
        var nombre: String { rawValue.capitalized }
        var orden: Int { self == .alta ? 0 : self == .media ? 1 : 2 }
    }

    var id: String
    var nombre: String
    var precio: Double?
    var enlace: String
    var nota: String
    var prioridad: Prioridad
    var comprado: Bool
    var añadido: Date

    /// Deseo vacío para el formulario de alta. Su id empieza por "nuevo-" hasta que se guarda.
    static func nuevo() -> Deseo {
        Deseo(id: "nuevo-\(UUID().uuidString)", nombre: "", precio: nil, enlace: "", nota: "",
              prioridad: .media, comprado: false, añadido: Date())
    }

    var esNuevo: Bool { id.hasPrefix("nuevo-") }

    var url: URL? {
        let t = enlace.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return URL(string: t.contains("://") ? t : "https://\(t)")
    }
}

/// Tope de gasto mensual para una categoría.
struct LimiteCategoria: Codable, Hashable {
    var categoria: String
    var limite: Double
}

struct DatosFinanzas: Codable {
    var gastos: [Gasto]
    var reglas: [Regla]
    var presupuestos: [PresupuestoMes]
    var ingresos: [IngresoExtra]
    var frecuentes: [Frecuente] = []
    var limites: [LimiteCategoria] = []
    var deseos: [Deseo] = []
    var repartos: [Reparto] = []
    var presupuestoPorDefecto: Double

    /// Ajusta cada gasto compartido para que `importe` sea solo tu parte. Se puede aplicar varias veces.
    mutating func aplicarRepartos() {
        var porClave = [String: Reparto]()
        for r in repartos where !r.partes.isEmpty { porClave[r.clave] = r }
        for i in gastos.indices {
            let total = gastos[i].total
            if let r = porClave[gastos[i].clave] {
                gastos[i].pagado = total
                gastos[i].importe = r.tuParte(de: total)
            } else {
                gastos[i].pagado = nil
                gastos[i].importe = total
            }
        }
    }

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

    /// `frecuentes`, `limites` y `deseos` son opcionales al leer: scripts antiguos y la caché previa no lo traen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gastos = try c.decode([Gasto].self, forKey: .gastos)
        reglas = try c.decode([Regla].self, forKey: .reglas)
        presupuestos = try c.decode([PresupuestoMes].self, forKey: .presupuestos)
        ingresos = try c.decode([IngresoExtra].self, forKey: .ingresos)
        frecuentes = try c.decodeIfPresent([Frecuente].self, forKey: .frecuentes) ?? []
        limites = try c.decodeIfPresent([LimiteCategoria].self, forKey: .limites) ?? []
        deseos = try c.decodeIfPresent([Deseo].self, forKey: .deseos) ?? []
        repartos = try c.decodeIfPresent([Reparto].self, forKey: .repartos) ?? []
        presupuestoPorDefecto = try c.decode(Double.self, forKey: .presupuestoPorDefecto)
        aplicarRepartos()
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

    /// Solo el mes, en minúscula: "octubre".
    var nombreMes: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL"
        return f.string(from: inicio)
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
