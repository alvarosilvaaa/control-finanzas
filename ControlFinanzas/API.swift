import Foundation

enum ErrorAPI: LocalizedError {
    case sinConfigurar
    case servidor(String)
    case respuestaInvalida

    var errorDescription: String? {
        switch self {
        case .sinConfigurar: "Configura la URL del script y el token en Ajustes."
        case .servidor(let mensaje): mensaje
        case .respuestaInvalida: "La respuesta del script no es válida. ¿Está bien desplegado?"
        }
    }
}

/// Cliente del Apps Script que hace de puente con Google Sheets.
struct API {
    let url: URL
    let token: String

    init?(url: String, token: String) {
        let limpia = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: limpia), u.scheme == "https", !token.isEmpty else { return nil }
        self.url = u
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func datos() async throws -> DatosFinanzas {
        try await enviar(["action": "datos"], como: DatosFinanzas.self)
    }

    func nuevoGasto(importe: Double, concepto: String, categoria: String, metodo: String, fecha: Date?) async throws {
        var cuerpo: [String: Any] = ["action": "nuevoGasto", "importe": importe, "concepto": concepto,
                                     "categoria": categoria, "metodo": metodo]
        if let fecha { cuerpo["fecha"] = iso(fecha) }
        try await enviar(cuerpo)
    }

    func editarGasto(_ original: Gasto, por nuevo: Gasto, regla: String?) async throws {
        var cuerpo: [String: Any] = [
            "action": "editarGasto", "fechaOriginal": iso(original.fecha), "fila": original.fila ?? 0,
            "fecha": iso(nuevo.fecha), "importe": nuevo.importe, "concepto": nuevo.concepto,
            "categoria": nuevo.categoria, "metodo": nuevo.metodo,
        ]
        if let regla { cuerpo["regla"] = regla }
        try await enviar(cuerpo)
    }

    func borrarGasto(_ gasto: Gasto) async throws {
        try await enviar(["action": "borrarGasto", "fechaOriginal": iso(gasto.fecha), "fila": gasto.fila ?? 0])
    }

    /// Con milisegundos: la marca temporal del formulario los tiene y se usa para encontrar la fila.
    private func iso(_ fecha: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: fecha)
    }

    func guardarFrecuente(_ f: Frecuente) async throws {
        var cuerpo: [String: Any] = ["action": "guardarFrecuente", "concepto": f.concepto, "categoria": f.categoria,
                                     "metodo": f.metodo, "frecuencia": f.frecuencia.rawValue]
        if !f.id.hasPrefix("nuevo-") { cuerpo["id"] = f.id }
        if let importe = f.importe { cuerpo["importe"] = importe }
        if let dia = f.dia { cuerpo["dia"] = dia }
        try await enviar(cuerpo)
    }

    func borrarFrecuente(id: String) async throws {
        try await enviar(["action": "borrarFrecuente", "id": id])
    }

    func nuevoIngreso(importe: Double, concepto: String, fecha: Date) async throws {
        try await enviar(["action": "nuevoIngreso", "importe": importe, "concepto": concepto,
                          "fecha": ISO8601DateFormatter().string(from: fecha)])
    }

    func borrarIngreso(id: String) async throws {
        try await enviar(["action": "borrarIngreso", "id": id])
    }

    func fijarPresupuesto(mes: Mes, base: Double) async throws {
        try await enviar(["action": "fijarPresupuesto", "mes": mes.clave, "base": base])
    }

    /// `limite` nulo quita el límite de esa categoría.
    func fijarLimite(categoria: String, limite: Double?) async throws {
        var cuerpo: [String: Any] = ["action": "fijarLimite", "categoria": categoria]
        if let limite { cuerpo["limite"] = limite }
        try await enviar(cuerpo)
    }

    struct RespuestaClaude: Decodable {
        let texto: String
        /// Bloques de la respuesta tal cual (JSON), para reenviarlos sin cambios en la siguiente pregunta.
        let contenido: String?
    }

    /// `mensajes` en el formato de la API de Claude: [{"role": "user"|"assistant", "content": …}].
    func preguntarClaude(mensajes: [[String: Any]]) async throws -> RespuestaClaude {
        try await enviar(["action": "preguntarClaude", "mensajes": mensajes], como: RespuestaClaude.self, espera: 180)
    }

    // MARK: - Transporte

    private struct Estado: Decodable {
        let ok: Bool
        let error: String?
    }

    private struct Vacio: Decodable {}

    private func enviar(_ cuerpo: [String: Any]) async throws {
        _ = try await enviar(cuerpo, como: Vacio.self)
    }

    private func enviar<T: Decodable>(_ cuerpo: [String: Any], como tipo: T.Type, espera: TimeInterval = 30) async throws -> T {
        var cuerpo = cuerpo
        cuerpo["token"] = token
        var peticion = URLRequest(url: url, timeoutInterval: espera)
        peticion.httpMethod = "POST"
        // Apps Script responde con una redirección; text/plain evita problemas con ella.
        peticion.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        peticion.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)

        let (data, _) = try await URLSession.shared.data(for: peticion)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let texto = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let fecha = f.date(from: texto) ?? ISO8601DateFormatter().date(from: texto) { return fecha }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Fecha no válida: \(texto)"))
        }

        guard let estado = try? decoder.decode(Estado.self, from: data) else { throw ErrorAPI.respuestaInvalida }
        guard estado.ok else {
            let mensaje = estado.error ?? "Error desconocido"
            if mensaje.hasPrefix("Acción desconocida") {
                throw ErrorAPI.servidor("El script de tu hoja está desactualizado. Publica una nueva versión en Apps Script (Implementar → Gestionar implementaciones → ✏️ → Nueva versión).")
            }
            throw ErrorAPI.servidor(mensaje)
        }
        return try decoder.decode(T.self, from: data)
    }
}
