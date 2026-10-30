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
    /// Si cerraste el mes anterior antes del día 1: cuándo empezó este periodo (ISO).
    var inicio: String? = nil

    var fechaInicio: Date? {
        guard let inicio, !inicio.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: inicio) ?? ISO8601DateFormatter().date(from: inicio)
    }
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

    /// El periodo al que pertenece una fecha, teniendo en cuenta los meses cerrados antes de tiempo.
    init(_ fecha: Date, calendario: Calendar = .current) {
        let c = calendario.dateComponents([.year, .month], from: fecha)
        let natural = Mes(año: c.year!, mes: c.month!)
        if fecha >= natural.siguiente.inicio {
            self = natural.siguiente
        } else if fecha < natural.inicio {
            self = natural.anterior
        } else {
            self = natural
        }
    }

    init?(clave: String) {
        let partes = clave.split(separator: "-").compactMap { Int($0) }
        guard partes.count == 2 else { return nil }
        self.init(año: partes[0], mes: partes[1])
    }

    /// Inicio de los periodos que no empiezan el día 1 (clave "aaaa-MM" → fecha). Lo rellena el almacén.
    static var inicios: [String: Date] = [:]

    static var actual: Mes { Mes(Date()) }

    /// Día 1 del mes de calendario.
    var inicioNatural: Date { Calendar.current.date(from: DateComponents(year: año, month: mes, day: 1))! }
    var inicio: Date { Mes.inicios[clave] ?? inicioNatural }
    var fin: Date { siguiente.inicio }
    /// El periodo no coincide con el mes de calendario (se cerró antes o después del día 1).
    var personalizado: Bool { inicio != inicioNatural || fin != siguiente.inicioNatural }

    /// Días del periodo, contando entero el día en que se cerró (por la mañana aún era de este mes).
    var numeroDeDias: Int { max(dia(de: fin.addingTimeInterval(-1)), 1) }

    /// Número de día dentro del periodo (1 = primer día).
    func dia(de fecha: Date) -> Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: inicio), to: cal.startOfDay(for: fecha)).day ?? 0) + 1
    }

    func fecha(dia: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dia - 1, to: Calendar.current.startOfDay(for: inicio))!
    }

    func sumando(_ meses: Int) -> Mes {
        let total = año * 12 + (mes - 1) + meses
        return Mes(año: total / 12, mes: total % 12 + 1)
    }
    var anterior: Mes { sumando(-1) }
    var siguiente: Mes { sumando(1) }

    func contiene(_ fecha: Date) -> Bool { fecha >= inicio && fecha < fin }

    /// "28 oct – 27 nov"
    var rango: String {
        let estilo = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES"))
        let ultimo = Calendar.current.date(byAdding: .second, value: -1, to: fin)!
        return "\(inicio.formatted(estilo)) – \(ultimo.formatted(estilo))"
    }

    var nombre: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: inicioNatural).capitalized(with: f.locale)
    }

    /// Solo el mes, en minúscula: "octubre".
    var nombreMes: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL"
        return f.string(from: inicioNatural)
    }

    var nombreCorto: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLL"
        return f.string(from: inicioNatural).capitalized(with: f.locale)
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
        return min(mes.dia(de: hoy), mes.numeroDeDias)
    }

    var diasRestantes: Int { mes.numeroDeDias - diasTranscurridos }

    var mediaDiaria: Double { diasTranscurridos > 0 ? totalGastado / Double(diasTranscurridos) : 0 }

    /// Lo que puedes gastar al día a partir de hoy para no pasarte.
    var disponiblePorDia: Double? {
        guard diasRestantes > 0 else { return nil }
        return max(restante, 0) / Double(diasRestantes + 1)
    }

    /// Gasto estimado a final de mes al ritmo actual.
    /// Los dos primeros días hay muy poco dato: se supone que el resto del mes sigues el ritmo previsto.
    var proyeccion: Double {
        if diasTranscurridos < 3 {
            return totalGastado + presupuesto / Double(mes.numeroDeDias) * Double(mes.numeroDeDias - diasTranscurridos)
        }
        return mediaDiaria * Double(mes.numeroDeDias)
    }

    /// Gasto acumulado por día, para el gráfico.
    var acumuladoPorDia: [(dia: Int, total: Double)] {
        var porDia = [Int: Double]()
        for g in gastos { porDia[mes.dia(de: g.fecha), default: 0] += g.importe }
        var acumulado = 0.0
        return (1...max(diasTranscurridos, 1)).map { dia in
            acumulado += porDia[dia] ?? 0
            return (dia, acumulado)
        }
    }
}
