import Foundation

/// Datos inventados para probar la app sin conectarla a la hoja.
enum Demo {
    private static let plantillas: [(String, String, String, ClosedRange<Double>)] = [
        ("Mercadona", "Súper", "MASTERCARD BSCARD", 4...28),
        ("Dia", "Súper", "MASTERCARD BSCARD", 1...12),
        ("Cañas", "Bares", "Bizum", 5...18),
        ("Café", "Cafetería", "MASTERCARD BSCARD", 1.2...3.5),
        ("Cena con amigos", "Restaurantes", "MASTERCARD BSCARD", 15...35),
        ("Abono transporte", "Transporte", "MASTERCARD BSCARD", 10...10),
        ("Librería", "Cultura", "Efectivo", 8...20),
        ("Peluquería", "Cuidado personal", "MASTERCARD BSCARD", 12...15),
        ("Steam", "Videojuegos", "MASTERCARD BSCARD", 2...15),
    ]

    static func datos() -> DatosFinanzas {
        var generador = Aleatorio(semilla: 42)
        var gastos: [Gasto] = []
        let cal = Calendar.current
        let hoy = Date()
        for desplazamiento in 0..<3 {
            let mes = Mes.actual.sumando(-desplazamiento)
            let ultimoDia = desplazamiento == 0 ? cal.component(.day, from: hoy) : mes.numeroDeDias
            gastos.append(gasto(&generador, mes, dia: 1, ("Gimnasio", "Deporte", "MASTERCARD BSCARD", 56...56)))
            for dia in 1...ultimoDia {
                for _ in 0..<Int(generador.siguiente() * 2.4) {
                    let p = plantillas[Int(generador.siguiente() * Double(plantillas.count))]
                    gastos.append(gasto(&generador, mes, dia: dia, p))
                }
            }
        }
        let propina = IngresoExtra(id: "demo-propina", fecha: Mes.actual.inicio.addingTimeInterval(86400 * 5),
                                   importe: 30, concepto: "Propina")
        return DatosFinanzas(gastos: gastos.filter { $0.fecha <= hoy },
                             reglas: [Regla(palabra: "mercadona", categoria: "Súper")],
                             presupuestos: [], ingresos: [propina], presupuestoPorDefecto: 450)
    }

    private static func gasto(_ g: inout Aleatorio, _ mes: Mes, dia: Int,
                              _ p: (String, String, String, ClosedRange<Double>)) -> Gasto {
        let fecha = Calendar.current.date(byAdding: .minute, value: 9 * 60 + Int(g.siguiente() * 720),
                                          to: Calendar.current.date(byAdding: .day, value: dia - 1, to: mes.inicio)!)!
        let importe = ((p.3.lowerBound + g.siguiente() * (p.3.upperBound - p.3.lowerBound)) * 100).rounded() / 100
        return Gasto(id: UUID().uuidString, fecha: fecha, importe: importe,
                     concepto: p.0, categoria: p.1, metodo: p.2)
    }

    private struct Aleatorio {
        var estado: UInt64
        init(semilla: UInt64) { estado = semilla }
        mutating func siguiente() -> Double {
            estado = estado &* 6364136223846793005 &+ 1442695040888963407
            return Double(estado >> 11) / Double(1 << 53)
        }
    }
}
