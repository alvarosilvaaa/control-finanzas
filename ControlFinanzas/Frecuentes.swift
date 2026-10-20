import Foundation

/// Gasto que se repite (gimnasio, Bizum semanal…) para registrarlo con un toque.
struct Frecuente: Codable, Identifiable, Hashable {
    enum Frecuencia: String, Codable, CaseIterable, Identifiable {
        case ninguna, mensual, semanal
        var id: String { rawValue }
        var nombre: String {
            switch self {
            case .ninguna: "Sin periodicidad"
            case .mensual: "Cada mes"
            case .semanal: "Cada semana"
            }
        }
    }

    var id: String
    var concepto: String
    var importe: Double?
    var categoria: String
    var metodo: String
    var frecuencia: Frecuencia
    /// Día del mes (1-31) si es mensual; día de la semana (1 lunes … 7 domingo) si es semanal.
    var dia: Int?

    static func nuevo() -> Frecuente {
        Frecuente(id: "nuevo-\(UUID().uuidString)", concepto: "", importe: nil, categoria: "Sin clasificar",
                  metodo: "Bizum", frecuencia: .ninguna, dia: nil)
    }

    static let diasSemana = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

    /// "56,00 € · cada mes, día 1"
    var descripcion: String {
        var partes: [String] = []
        if let importe { partes.append(Formato.eur(importe)) }
        switch frecuencia {
        case .mensual: partes.append(dia.map { "cada mes, día \($0)" } ?? "cada mes")
        case .semanal: partes.append(dia.flatMap { (1...7).contains($0) ? "cada \(Self.diasSemana[$0 - 1])" : nil } ?? "cada semana")
        case .ninguna: break
        }
        partes.append(Formato.metodo(metodo))
        return partes.joined(separator: " · ")
    }

    // MARK: Coincidencias y pendientes

    static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }

    func coincide(con gasto: Gasto) -> Bool {
        let a = Self.normalizar(concepto), b = Self.normalizar(gasto.concepto)
        return !a.isEmpty && (a == b || b.contains(a))
    }

    /// Ya tocaba pagarlo y no hay ningún gasto registrado en el periodo actual.
    func pendiente(en gastos: [Gasto], hoy: Date = Date()) -> Bool {
        let cal = Calendar.current
        switch frecuencia {
        case .ninguna:
            return false
        case .mensual:
            let mes = Mes(hoy)
            if let dia, cal.component(.day, from: hoy) < min(dia, mes.numeroDeDias) { return false }
            return !gastos.contains { mes.contiene($0.fecha) && coincide(con: $0) }
        case .semanal:
            // Lunes = 1 … domingo = 7
            let hoySemana = (cal.component(.weekday, from: hoy) + 5) % 7 + 1
            if let dia, hoySemana < dia { return false }
            let inicioSemana = cal.date(byAdding: .day, value: -(hoySemana - 1), to: cal.startOfDay(for: hoy))!
            return !gastos.contains { $0.fecha >= inicioSemana && coincide(con: $0) }
        }
    }

    // MARK: Sugerencias

    /// Conceptos registrados al menos dos veces, con su importe y categoría más habituales.
    static func sugerencias(gastos: [Gasto], existentes: [Frecuente], limite: Int = 6) -> [Frecuente] {
        let grupos = Dictionary(grouping: gastos.filter { !$0.pendiente }) { normalizar($0.concepto) }
        return grupos
            .filter { clave, lista in
                lista.count >= 2 && !clave.isEmpty
                    && !existentes.contains { f in lista.contains { f.coincide(con: $0) } }
            }
            .sorted { $0.value.count > $1.value.count }
            .prefix(limite)
            .map { _, lista in
                let recientes = lista.sorted { $0.fecha > $1.fecha }
                // Importe más repetido; si hay empate, el del gasto más reciente.
                let importes = Dictionary(grouping: lista, by: \.importe)
                    .max { a, b in
                        a.value.count != b.value.count ? a.value.count < b.value.count
                            : a.value.map(\.fecha).max()! < b.value.map(\.fecha).max()!
                    }?.key
                let categoria = recientes.first { $0.categoria != "Sin clasificar" }?.categoria ?? "Sin clasificar"
                return Frecuente(id: "nuevo-\(UUID().uuidString)",
                                 concepto: recientes[0].concepto.trimmingCharacters(in: .whitespaces),
                                 importe: importes, categoria: categoria, metodo: recientes[0].metodo,
                                 frecuencia: .ninguna, dia: nil)
            }
    }
}
