import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Pequeñas diferencias entre iPhone y Mac, para que las vistas compartidas no se llenen de `#if`.

extension View {
    func tecladoDecimal() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    func tecladoURL() -> some View {
        #if os(iOS)
        keyboardType(.URL).textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    func sinMayusculas() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    func tituloEnLinea() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// En Mac, las hojas modales necesitan un tamaño mínimo y el estilo de formulario agrupado.
    func hojaMac(ancho: CGFloat = 480, alto: CGFloat = 560) -> some View {
        #if os(macOS)
        formStyle(.grouped).frame(minWidth: ancho, minHeight: alto)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var inicio: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    static var fin: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

extension Color {
    static var fondoAgrupado: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Fondo de la pantalla (blanco en claro, negro en oscuro): para texto sobre elementos en `Tema.tinta`.
    static var fondo: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var fondoTarjeta: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

enum Sistema {
    static func vibrarExito() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func ocultarTeclado() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    static var esMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}
