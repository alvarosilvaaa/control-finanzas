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

/// Icono y color de cada categoría. Las desconocidas reciben un color estable según su nombre.
struct EstiloCategoria {
    let icono: String
    let color: Color

    private static let conocidas: [String: EstiloCategoria] = [
        "super": .init(icono: "cart.fill", color: .green),
        "supermercado": .init(icono: "cart.fill", color: .green),
        "bares": .init(icono: "wineglass.fill", color: .orange),
        "cafeteria": .init(icono: "cup.and.saucer.fill", color: .brown),
        "restaurantes": .init(icono: "fork.knife", color: .red),
        "comida": .init(icono: "takeoutbag.and.cup.and.straw.fill", color: .pink),
        "deporte": .init(icono: "figure.run", color: .mint),
        "cuidado personal": .init(icono: "comb.fill", color: .purple),
        "videojuegos": .init(icono: "gamecontroller.fill", color: .indigo),
        "cultura": .init(icono: "book.fill", color: .teal),
        "tecnologia": .init(icono: "iphone", color: .blue),
        "transporte": .init(icono: "tram.fill", color: .cyan),
        "ocio": .init(icono: "party.popper.fill", color: .yellow),
        "ropa": .init(icono: "tshirt.fill", color: .pink),
        "salud": .init(icono: "cross.case.fill", color: .red),
        "hogar": .init(icono: "house.fill", color: .brown),
        "suscripciones": .init(icono: "repeat", color: .indigo),
        "sin clasificar": .init(icono: "questionmark.circle.fill", color: .gray),
    ]

    private static let paleta: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .red, .mint, .cyan]

    static func de(_ categoria: String) -> EstiloCategoria {
        let clave = categoria
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
        if let e = conocidas[clave] { return e }
        let indice = clave.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % paleta.count
        return .init(icono: "tag.fill", color: paleta[indice])
    }
}

struct IconoCategoria: View {
    let categoria: String
    var tamaño: CGFloat = 36

    var body: some View {
        let e = EstiloCategoria.de(categoria)
        Image(systemName: e.icono)
            .font(.system(size: tamaño * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: tamaño, height: tamaño)
            .background(e.color.gradient, in: RoundedRectangle(cornerRadius: tamaño * 0.3, style: .continuous))
    }
}

struct Tarjeta<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido

    var body: some View {
        contenido
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fondoTarjeta, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    /// Muestra un aviso emergente cuando `error` tiene valor.
    func alertaError(_ error: Binding<String?>) -> some View {
        alert("No se ha podido guardar",
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
