import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Botón que abre la app de Claude con un resumen de tus gastos y una pregunta ya escrita.
/// No usa la API: la conversación ocurre en tu app de Claude, con tu cuenta.
struct BotonPreguntarClaude: View {
    @Environment(Almacen.self) private var almacen
    @Environment(\.openURL) private var abrir

    static let preguntas = [
        "¿Dónde puedo recortar este mes?",
        "¿Cómo llego a fin de mes sin pasarme?",
        "¿Qué límites por categoría me pondrías?",
        "¿En qué gasto más de lo que debería?",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(Self.preguntas, id: \.self) { p in
                    Button(p) { preguntar(p) }
                }
                Divider()
                Button("Abrir con mis datos y preguntar yo") { preguntar(nil) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.title3.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preguntar a Claude").font(.body.weight(.semibold))
                        Text("Abre la app de Claude con tus gastos").font(.caption).opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).opacity(0.6)
                }
                .foregroundStyle(Color.fondo)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Tema.tinta, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            Text("El texto también se copia: si Claude no lo muestra, pégalo en el chat.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func preguntar(_ pregunta: String?) {
        let texto = almacen.textoParaClaude(pregunta: pregunta)
        copiar(texto)

        var app = URLComponents(string: "claude://claude.ai/new")!
        app.queryItems = [URLQueryItem(name: "q", value: texto)]
        // URLComponents deja los "+" sin codificar y la web los leería como espacios.
        app.percentEncodedQuery = app.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var web = URLComponents(string: "https://claude.ai/new")!
        web.percentEncodedQuery = app.percentEncodedQuery

        guard let urlApp = app.url, let urlWeb = web.url else { return }
        // Si la app de Claude no está instalada, se abre claude.ai en el navegador.
        abrir(urlApp) { aceptado in
            if !aceptado { abrir(urlWeb) }
        }
    }

    private func copiar(_ texto: String) {
        #if os(iOS)
        UIPasteboard.general.string = texto
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        #endif
    }
}

extension Almacen {
    /// Mensaje para Claude: instrucciones, resumen de tus finanzas y la pregunta (o ninguna, para hacerla tú).
    func textoParaClaude(pregunta: String?) -> String {
        var partes = [
            "Te paso un resumen de mis gastos, sacado de mi app de control de finanzas. Ayúdame a ahorrar: responde en español, breve y con recomendaciones concretas basadas en estas cifras (di cuánto ahorraría cuando se pueda estimar). Si los datos no bastan, dímelo.",
            contextoParaClaude,
        ]
        if let pregunta {
            partes.append("Mi pregunta: \(pregunta)")
        } else {
            partes.append("Léelo y espera a mi pregunta.")
        }
        return partes.joined(separator: "\n\n")
    }

    /// Resumen compacto de tus finanzas para que Claude responda con tus cifras.
    var contextoParaClaude: String {
        let es = Locale(identifier: "es_ES")
        let r = resumen(de: .actual)
        var lineas: [String] = []

        lineas.append("Hoy: \(Date().formatted(.dateTime.day().month(.wide).year().locale(es))).")
        lineas.append("""
            \(r.mes.nombre): presupuesto \(Formato.eur(r.presupuesto)), gastado \(Formato.eur(r.totalGastado)), \
            quedan \(Formato.eur(r.restante)). Día \(r.diasTranscurridos) de \(r.mes.numeroDeDias). \
            Previsión a fin de mes: \(Formato.eurSinDecimales(r.proyeccion)).
            """)

        if !r.porCategoria.isEmpty {
            let categorias = r.porCategoria.map { c -> String in
                let tope = limite(de: c.categoria).map { " (límite \(Formato.eurSinDecimales($0)))" } ?? ""
                return "\(c.categoria) \(Formato.eur(c.total))\(tope)"
            }
            lineas.append("Por categoría: " + categorias.joined(separator: "; ") + ".")
        }

        let anteriores = meses.filter { $0 < .actual }.prefix(3)
        for mes in anteriores {
            let rm = resumen(de: mes)
            let categorias = rm.porCategoria.map { "\($0.categoria) \(Formato.eurSinDecimales($0.total))" }.joined(separator: ", ")
            lineas.append("\(mes.nombre): \(Formato.eurSinDecimales(rm.totalGastado)) de \(Formato.eurSinDecimales(rm.presupuesto)). \(categorias).")
        }
        if anteriores.isEmpty { lineas.append("No hay meses anteriores: empecé a registrar gastos este mes.") }

        let fijos = datos.frecuentes.compactMap { f -> String? in
            guard let importe = f.importe else { return nil }
            return "\(f.concepto) \(Formato.eur(importe)) (\(f.descripcion))"
        }
        if !fijos.isEmpty { lineas.append("Gastos fijos: " + fijos.joined(separator: "; ") + ".") }

        lineas.append("Gastos de este mes:")
        let formatoFecha = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(es)
        for g in r.gastos {
            lineas.append("- \(g.fecha.formatted(formatoFecha)) \(g.concepto.trimmingCharacters(in: .whitespaces)) · \(g.categoria) · \(Formato.eur(g.importe))")
        }
        return lineas.joined(separator: "\n")
    }
}
