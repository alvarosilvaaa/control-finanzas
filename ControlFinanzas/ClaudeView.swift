import SwiftUI

/// Un mensaje de la conversación con Claude.
struct MensajeChat: Identifiable {
    let id = UUID()
    let deUsuario: Bool
    let texto: String
    /// El mensaje tal como se envía a la API. `nil` si no debe reenviarse (p. ej. una pregunta rechazada).
    var api: [String: Any]?
}

extension Almacen {
    func preguntarClaude(mensajes: [[String: Any]]) async throws -> API.RespuestaClaude {
        if modoDemo {
            try await Task.sleep(for: .seconds(1.5))
            return API.RespuestaClaude(
                texto: "En modo demo no se consulta a Claude. Con tus datos reales te diría, por ejemplo: **reduce las compras pequeñas en el súper** agrupándolas en una compra semanal; podrías ahorrar unos 15 € al mes.",
                contenido: nil)
        }
        guard let api else { throw ErrorAPI.sinConfigurar }
        return try await api.preguntarClaude(mensajes: mensajes)
    }

    /// Resumen de tus finanzas que acompaña a la primera pregunta, para que Claude responda con tus cifras.
    var contextoParaClaude: String {
        let es = Locale(identifier: "es_ES")
        let r = resumen(de: .actual)
        var lineas: [String] = []

        lineas.append("Hoy es \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(es))).")
        lineas.append("""
            Mes en curso (\(r.mes.nombre)): presupuesto \(Formato.eur(r.presupuesto)) \
            (base \(Formato.eur(r.base)) + ingresos extra \(Formato.eur(r.totalExtra))). \
            Gastado \(Formato.eur(r.totalGastado)), quedan \(Formato.eur(r.restante)). \
            Día \(r.diasTranscurridos) de \(r.mes.numeroDeDias). Previsión a fin de mes al ritmo actual: \(Formato.eur(r.proyeccion)).
            """)

        if !r.porCategoria.isEmpty {
            lineas.append("Por categoría este mes:")
            for c in r.porCategoria {
                let tope = limite(de: c.categoria).map { " (límite \(Formato.eur($0)))" } ?? ""
                lineas.append("- \(c.categoria): \(Formato.eur(c.total))\(tope)")
            }
        }
        let sinGasto = limites.filter { l in !r.porCategoria.contains { $0.categoria == l.categoria } }
        for l in sinGasto { lineas.append("- \(l.categoria): 0 € (límite \(Formato.eur(l.limite)))") }

        let anteriores = meses.filter { $0 < .actual }.prefix(3)
        if !anteriores.isEmpty {
            lineas.append("Meses anteriores:")
            for mes in anteriores {
                let rm = resumen(de: mes)
                let categorias = rm.porCategoria.map { "\($0.categoria) \(Formato.eurSinDecimales($0.total))" }.joined(separator: ", ")
                lineas.append("- \(mes.nombre): \(Formato.eur(rm.totalGastado)) de \(Formato.eur(rm.presupuesto)). \(categorias)")
            }
        } else {
            lineas.append("No hay meses anteriores registrados: la app se empezó a usar este mes.")
        }

        if !datos.frecuentes.isEmpty {
            lineas.append("Gastos fijos o frecuentes:")
            for f in datos.frecuentes {
                let importe = f.importe.map(Formato.eur) ?? "importe variable"
                lineas.append("- \(f.concepto): \(importe), \(f.descripcion)")
            }
        }

        let consejos = self.consejos
        if !consejos.isEmpty {
            lineas.append("Avisos que ya muestra la app:")
            for c in consejos { lineas.append("- \(c.titulo): \(c.texto)") }
        }

        lineas.append("Gastos de este mes (fecha · concepto · categoría · método · importe):")
        let formatoFecha = Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute().locale(es)
        for g in r.gastos {
            lineas.append("- \(g.fecha.formatted(formatoFecha)) · \(g.concepto.trimmingCharacters(in: .whitespaces)) · \(g.categoria) · \(Formato.metodo(g.metodo)) · \(Formato.eur(g.importe))")
        }
        return lineas.joined(separator: "\n")
    }
}

/// Conversación con Claude sobre tus gastos.
struct ChatClaudeView: View {
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @State private var mensajes: [MensajeChat] = []
    @State private var entrada = ""
    @State private var pensando = false
    @State private var error: String?
    @FocusState private var escribiendo: Bool

    private let sugerencias = [
        "¿Dónde puedo recortar este mes?",
        "¿Cómo llego a fin de mes sin pasarme?",
        "¿Qué límites por categoría me pondrías?",
        "¿En qué gasto más de lo que debería?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { lector in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if mensajes.isEmpty { bienvenida }
                        ForEach(mensajes) { m in
                            Burbuja(mensaje: m).id(m.id)
                        }
                        if pensando {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Claude está pensando…").foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .id("pensando")
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: mensajes.count) {
                    withAnimation { lector.scrollTo(mensajes.last?.id, anchor: .top) }
                }
                .onChange(of: pensando) { _, ahora in
                    if ahora { withAnimation { lector.scrollTo("pensando", anchor: .bottom) } }
                }
            }
            .background(Color.fondo)
            .safeAreaInset(edge: .bottom) { barraEntrada }
            .navigationTitle("Preguntar a Claude")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                if !mensajes.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { mensajes = []; entrada = "" } label: {
                            Label("Nueva conversación", systemImage: "square.and.pencil")
                        }
                        .disabled(pensando)
                        .help("Empezar una conversación nueva")
                    }
                }
            }
            .alertaError($error, titulo: "Claude no ha podido responder")
            .hojaMac(ancho: 600, alto: 680)
        }
    }

    private var bienvenida: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Tema.tinta)
            Text("Pregúntale a Claude por tus gastos")
                .font(.title3.bold())
            Text("Claude verá un resumen de tu presupuesto y de tus gastos de este mes y de los anteriores para darte ideas concretas para ahorrar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sugerencias, id: \.self) { s in
                    Button { Task { await enviar(s) } } label: {
                        Text(s)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Tema.tinta.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private var barraEntrada: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Escribe tu pregunta", text: $entrada, prompt: Text("Escribe tu pregunta"), axis: .vertical)
                .labelsHidden()
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($escribiendo)
                .onSubmit { Task { await enviar(entrada) } }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .cristal(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Button { Task { await enviar(entrada) } } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.fondo)
                    .frame(width: 44, height: 44)
                    .background(Tema.tinta, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(entrada.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pensando)
            .opacity(entrada.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pensando ? 0.35 : 1)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func enviar(_ texto: String) async {
        let pregunta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pregunta.isEmpty, !pensando else { return }
        entrada = ""
        escribiendo = false

        // La primera pregunta que se envía lleva el resumen de tus finanzas; las siguientes van solas.
        let esPrimera = !mensajes.contains { $0.api != nil }
        let contenido = esPrimera ? "\(almacen.contextoParaClaude)\n\nMi pregunta: \(pregunta)" : pregunta
        mensajes.append(MensajeChat(deUsuario: true, texto: pregunta, api: ["role": "user", "content": contenido]))
        let indicePregunta = mensajes.count - 1

        pensando = true
        defer { pensando = false }
        do {
            let r = try await almacen.preguntarClaude(mensajes: mensajes.compactMap(\.api))
            if let json = r.contenido, let bloques = try? JSONSerialization.jsonObject(with: Data(json.utf8)) {
                mensajes.append(MensajeChat(deUsuario: false, texto: r.texto, api: ["role": "assistant", "content": bloques]))
            } else {
                // Sin bloques que reenviar (rechazo o modo demo): ni la pregunta ni la respuesta pasan al historial.
                mensajes[indicePregunta].api = nil
                mensajes.append(MensajeChat(deUsuario: false, texto: r.texto, api: nil))
            }
        } catch {
            mensajes.removeLast()
            entrada = pregunta
            self.error = error.localizedDescription
        }
    }
}

private struct Burbuja: View {
    let mensaje: MensajeChat

    var body: some View {
        if mensaje.deUsuario {
            HStack {
                Spacer(minLength: 48)
                Text(mensaje.texto)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(Color.fondo)
                    .background(Tema.tinta, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                Text(Self.formatear(mensaje.texto))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    /// Negritas y cursivas de Markdown, conservando los saltos de línea.
    static func formatear(_ texto: String) -> AttributedString {
        (try? AttributedString(markdown: texto, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(texto)
    }
}
