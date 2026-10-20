import Foundation
import Observation

@Observable
final class Almacen {
    private(set) var datos: DatosFinanzas = .vacio
    private(set) var cargando = false
    private(set) var ultimaActualizacion: Date?
    var error: String?

    static let claveURL = "urlScript"
    static let claveToken = "tokenScript"
    static let claveDemo = "modoDemo"

    private let defaults = UserDefaults.standard

    var modoDemo: Bool { defaults.bool(forKey: Self.claveDemo) }

    var configurado: Bool { modoDemo || api != nil }

    private var api: API? {
        API(url: defaults.string(forKey: Self.claveURL) ?? "", token: defaults.string(forKey: Self.claveToken) ?? "")
    }

    init() {
        if let cache = Self.leerCache() {
            datos = cache.datos
            ultimaActualizacion = cache.fecha
        }
        if modoDemo { datos = Demo.datos() }
    }

    // MARK: - Consultas

    /// Todas las categorías conocidas, las más usadas primero.
    var categorias: [String] {
        var usos = [String: Int]()
        for g in datos.gastos { usos[g.categoria, default: 0] += 1 }
        for r in datos.reglas where usos[r.categoria] == nil { usos[r.categoria] = 0 }
        usos["Sin clasificar"] = nil
        return usos.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Conceptos usados antes, para autocompletar al escribir.
    func sugerencias(para texto: String) -> [(concepto: String, categoria: String)] {
        let t = texto.trimmingCharacters(in: .whitespaces).lowercased()
        guard t.count >= 2 else { return [] }
        var vistos = Set<String>()
        var resultado: [(String, String)] = []
        for g in datos.gastos.reversed() where g.concepto.lowercased().contains(t) {
            let clave = g.concepto.trimmingCharacters(in: .whitespaces).lowercased()
            if vistos.insert(clave).inserted {
                resultado.append((g.concepto.trimmingCharacters(in: .whitespaces), g.categoria))
            }
            if resultado.count == 4 { break }
        }
        return resultado
    }

    /// Presupuesto base de un mes: el fijado para ese mes o, si no hay, el último fijado antes.
    func base(de mes: Mes) -> Double {
        datos.presupuestos
            .compactMap { p in Mes(clave: p.mes).map { ($0, p.base) } }
            .filter { $0.0 <= mes }
            .max { $0.0 < $1.0 }?.1 ?? datos.presupuestoPorDefecto
    }

    func resumen(de mes: Mes) -> ResumenMes {
        ResumenMes(
            mes: mes,
            gastos: datos.gastos.filter { mes.contiene($0.fecha) }.sorted { $0.fecha > $1.fecha },
            ingresos: datos.ingresos.filter { mes.contiene($0.fecha) }.sorted { $0.fecha > $1.fecha },
            base: base(de: mes)
        )
    }

    /// Meses con algún movimiento, del más reciente al más antiguo (siempre incluye el actual).
    var meses: [Mes] {
        var s = Set(datos.gastos.map { Mes($0.fecha) })
        s.formUnion(datos.ingresos.map { Mes($0.fecha) })
        s.insert(.actual)
        return s.sorted(by: >)
    }

    // MARK: - Acciones

    /// Si ya hay una recarga en marcha, espera a esa en vez de lanzar otra.
    func recargar() async {
        if let enCurso = recargaEnCurso { return await enCurso.value }
        let tarea = Task { await descargarDatos() }
        recargaEnCurso = tarea
        await tarea.value
        recargaEnCurso = nil
    }

    @ObservationIgnored private var recargaEnCurso: Task<Void, Never>?

    private func descargarDatos() async {
        if modoDemo {
            datos = Demo.datos()
            ultimaActualizacion = Date()
            return
        }
        guard let api else { error = ErrorAPI.sinConfigurar.localizedDescription; return }
        cargando = true
        defer { cargando = false }
        do {
            datos = try await api.datos()
            ultimaActualizacion = Date()
            error = nil
            Self.guardarCache(datos)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// - Parameter fecha: `nil` para usar el momento actual.
    func añadirGasto(importe: Double, concepto: String, categoria: String, metodo: String, fecha: Date? = nil) async throws {
        if modoDemo {
            datos.gastos.append(Gasto(id: UUID().uuidString, fecha: fecha ?? Date(), importe: importe,
                                      concepto: concepto, categoria: categoria, metodo: metodo))
            return
        }
        guard let api else { throw ErrorAPI.sinConfigurar }
        try await api.nuevoGasto(importe: importe, concepto: concepto, categoria: categoria, metodo: metodo, fecha: fecha)
        // Se muestra al momento mientras la hoja recalcula sus fórmulas.
        datos.gastos.append(Gasto(id: "local-\(UUID().uuidString)", fecha: fecha ?? Date(), importe: importe,
                                  concepto: concepto, categoria: categoria, metodo: metodo))
        Task {
            try? await Task.sleep(for: .seconds(3))
            await recargar()
        }
    }

    /// - Parameter regla: si se indica, se crea una regla para que ese texto se clasifique siempre así.
    func editarGasto(_ original: Gasto, por nuevo: Gasto, regla: String?) async throws {
        if !modoDemo {
            guard let api else { throw ErrorAPI.sinConfigurar }
            try await api.editarGasto(original, por: nuevo, regla: regla)
        }
        if let i = datos.gastos.firstIndex(where: { $0.id == original.id }) { datos.gastos[i] = nuevo }
        if let regla, modoDemo {
            datos.reglas.append(Regla(palabra: regla, categoria: nuevo.categoria))
            for i in datos.gastos.indices where datos.gastos[i].categoria == "Sin clasificar"
                && datos.gastos[i].concepto.lowercased().contains(regla.lowercased()) {
                datos.gastos[i].categoria = nuevo.categoria
            }
        }
        if !modoDemo { await recargar() }
    }

    func borrarGasto(_ gasto: Gasto) async throws {
        if !modoDemo {
            guard let api else { throw ErrorAPI.sinConfigurar }
            try await api.borrarGasto(gasto)
        }
        datos.gastos.removeAll { $0.id == gasto.id }
        if !modoDemo { await recargar() }
    }

    /// Cambia la categoría de varios gastos a la vez (selección múltiple en Mac).
    func cambiarCategoria(_ gastos: [Gasto], a categoria: String) async throws {
        defer { if !modoDemo { Task { await recargar() } } }
        for original in gastos where original.categoria != categoria {
            var nuevo = original
            nuevo.categoria = categoria
            if !modoDemo {
                guard let api else { throw ErrorAPI.sinConfigurar }
                try await api.editarGasto(original, por: nuevo, regla: nil)
            }
            if let i = datos.gastos.firstIndex(where: { $0.id == original.id }) { datos.gastos[i] = nuevo }
        }
    }

    func borrarGastos(_ gastos: [Gasto]) async throws {
        defer { if !modoDemo { Task { await recargar() } } }
        for gasto in gastos {
            if !modoDemo {
                guard let api else { throw ErrorAPI.sinConfigurar }
                try await api.borrarGasto(gasto)
            }
            datos.gastos.removeAll { $0.id == gasto.id }
        }
    }

    // MARK: Gastos frecuentes

    /// Frecuentes guardados, primero los que tocan y aún no se han registrado.
    var frecuentes: [Frecuente] {
        datos.frecuentes.sorted { a, b in
            let pa = a.pendiente(en: datos.gastos), pb = b.pendiente(en: datos.gastos)
            return pa != pb ? pa : a.concepto.localizedCompare(b.concepto) == .orderedAscending
        }
    }

    /// Conceptos que se repiten en el historial y aún no son frecuentes.
    var sugerenciasFrecuentes: [Frecuente] { Frecuente.sugerencias(gastos: datos.gastos, existentes: datos.frecuentes) }

    func guardarFrecuente(_ f: Frecuente) async throws {
        if !modoDemo {
            guard let api else { throw ErrorAPI.sinConfigurar }
            try await api.guardarFrecuente(f)
            await recargar()
        } else {
            datos.frecuentes.removeAll { $0.id == f.id }
            datos.frecuentes.append(f)
        }
    }

    func borrarFrecuente(_ f: Frecuente) async throws {
        if !modoDemo {
            guard let api else { throw ErrorAPI.sinConfigurar }
            try await api.borrarFrecuente(id: f.id)
            await recargar()
        } else {
            datos.frecuentes.removeAll { $0.id == f.id }
        }
    }

    var sinClasificar: [Gasto] {
        datos.gastos.filter { $0.categoria == "Sin clasificar" && !$0.pendiente }.sorted { $0.fecha > $1.fecha }
    }

    func añadirIngreso(importe: Double, concepto: String, fecha: Date) async throws {
        if modoDemo {
            datos.ingresos.append(IngresoExtra(id: UUID().uuidString, fecha: fecha, importe: importe, concepto: concepto))
            return
        }
        guard let api else { throw ErrorAPI.sinConfigurar }
        try await api.nuevoIngreso(importe: importe, concepto: concepto, fecha: fecha)
        await recargar()
    }

    func borrarIngreso(_ ingreso: IngresoExtra) async throws {
        if modoDemo {
            datos.ingresos.removeAll { $0.id == ingreso.id }
            return
        }
        guard let api else { throw ErrorAPI.sinConfigurar }
        try await api.borrarIngreso(id: ingreso.id)
        await recargar()
    }

    func fijarPresupuesto(_ base: Double, desde mes: Mes) async throws {
        if modoDemo {
            datos.presupuestos.removeAll { $0.mes == mes.clave }
            datos.presupuestos.append(PresupuestoMes(mes: mes.clave, base: base))
            return
        }
        guard let api else { throw ErrorAPI.sinConfigurar }
        try await api.fijarPresupuesto(mes: mes, base: base)
        await recargar()
    }

    func ajustesCambiados() async {
        if !modoDemo, let cache = Self.leerCache() { datos = cache.datos } else if !modoDemo { datos = .vacio }
        await recargar()
    }

    // MARK: - Caché local (para abrir la app sin conexión)

    private struct Cache: Codable {
        let fecha: Date
        let datos: DatosFinanzas
    }

    private static var urlCache: URL {
        URL.applicationSupportDirectory.appending(path: "datos.json")
    }

    private static func leerCache() -> Cache? {
        guard let data = try? Data(contentsOf: urlCache) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func guardarCache(_ datos: DatosFinanzas) {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Cache(fecha: Date(), datos: datos)) {
            try? data.write(to: urlCache, options: .atomic)
        }
    }
}
