import SwiftUI

enum Formato {
    static let euros: FloatingPointFormatStyle<Double>.Currency =
        .currency(code: "EUR").locale(Locale(identifier: "es_ES"))

    static func eur(_ valor: Double) -> String { valor.formatted(euros) }

    static func eurSinDecimales(_ valor: Double) -> String {
        valor.formatted(.currency(code: "EUR").locale(Locale(identifier: "es_ES")).precision(.fractionLength(0)))
    }

    /// Nombre corto del método de pago.
    static func metodo(_ m: String) -> String {
        let n = m.lowercased()
        if n.contains("bizum") { return "Bizum" }
        if n.contains("efectivo") { return "Efectivo" }
        if n.isEmpty { return "Otro" }
        return "Tarjeta"
    }

    static let hora: Date.FormatStyle = .dateTime.hour().minute().locale(Locale(identifier: "es_ES"))
    static let diaLargo: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))
}

/// Paleta monocroma: negro / grises, y rojo solo para alertas (pasarse del presupuesto).
enum Tema {
    /// Color principal de los elementos: negro en modo claro, blanco en modo oscuro.
    static let tinta = Color.primary
    static let alerta = Color.red

    /// Gris para la posición `i` de `n` (0 = el más oscuro). Para distinguir porciones de un gráfico.
    static func gris(_ i: Int, de n: Int) -> Color {
        guard n > 1 else { return tinta }
        return tinta.opacity(1 - 0.78 * Double(i) / Double(n - 1))
    }
}

/// Icono de cada categoría. El color es el mismo para todas (monocromo); se distinguen por el símbolo.
struct EstiloCategoria {
    let icono: String
    var color: Color { Tema.tinta }

    private static let conocidas: [String: String] = [
        "super": "cart.fill",
        "supermercado": "cart.fill",
        "bares": "wineglass.fill",
        "cafeteria": "cup.and.saucer.fill",
        "restaurantes": "fork.knife",
        "comida": "takeoutbag.and.cup.and.straw.fill",
        "deporte": "figure.run",
        "cuidado personal": "comb.fill",
        "videojuegos": "gamecontroller.fill",
        "cultura": "book.fill",
        "tecnologia": "iphone",
        "transporte": "tram.fill",
        "ocio": "party.popper.fill",
        "ropa": "tshirt.fill",
        "salud": "cross.case.fill",
        "hogar": "house.fill",
        "limpieza": "bubbles.and.sparkles.fill",
        "estudio": "graduationcap.fill",
        "regalos": "gift.fill",
        "suscripciones": "repeat",
        "sin clasificar": "questionmark",
    ]

    static func de(_ categoria: String) -> EstiloCategoria {
        let clave = categoria
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
        return .init(icono: conocidas[clave] ?? "tag.fill")
    }
}

/// Círculo gris suave con el símbolo de la categoría. Si el gasto no tiene categoría, muestra la
/// inicial del concepto (como hacen las apps de banca cuando no hay logo).
struct IconoCategoria: View {
    let categoria: String
    var concepto: String? = nil
    var tamaño: CGFloat = 40

    var body: some View {
        let inicial = concepto?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
        Group {
            if categoria == "Sin clasificar", let inicial {
                Text(inicial).font(.system(size: tamaño * 0.42, weight: .semibold, design: .rounded))
            } else {
                Image(systemName: EstiloCategoria.de(categoria).icono)
                    .font(.system(size: tamaño * 0.4, weight: .medium))
            }
        }
        .foregroundStyle(categoria == "Sin clasificar" ? Color.secondary : Tema.tinta)
        .frame(width: tamaño, height: tamaño)
        .background(Tema.tinta.opacity(0.07), in: Circle())
    }
}

/// Bloque de contenido sin caja: se separa del resto solo con espacio.
struct Tarjeta<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido

    var body: some View {
        contenido
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Formularios y listas sin cajas: fondo liso y filas sin fondo propio.
    func estiloLimpio() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.fondo)
            .listRowBackground(Color.clear)
    }
}

extension View {
    /// Muestra un aviso emergente cuando `error` tiene valor.
    func alertaError(_ error: Binding<String?>, titulo: String = "No se ha podido guardar") -> some View {
        alert(titulo,
              isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })) {
            Button("Vale", role: .cancel) {}
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}

extension View {
    /// Barra con botón "OK" justo encima del teclado y cierre al deslizar.
    /// Hace falta porque el teclado numérico no tiene tecla de retorno.
    func ocultarTecladoFacil() -> some View {
        #if os(iOS)
        modifier(BarraTeclado())
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct BarraTeclado: ViewModifier {
    @State private var tecladoVisible = false

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if tecladoVisible {
                    HStack {
                        Spacer()
                        Button("OK") { Sistema.ocultarTeclado() }
                        .bold()
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                tecladoVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                tecladoVisible = false
            }
    }
}
#endif

extension View {
    /// Efecto de cristal del sistema (iOS 26 / macOS 26) o material translúcido en versiones anteriores.
    @ViewBuilder func cristal<Forma: Shape>(_ forma: Forma) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: forma)
        } else {
            background(.regularMaterial, in: forma)
        }
    }
}
