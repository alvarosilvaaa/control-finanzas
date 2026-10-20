import SwiftUI

/// Muestra la foto de arranque mientras se actualizan los datos al abrir la app.
/// Si la conexión tarda, se quita igualmente pasados unos segundos y la carga sigue por detrás.
struct ConArranque<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido
    @Environment(Almacen.self) private var almacen
    @State private var listo = false

    /// Tiempo mínimo en pantalla, para que no sea un parpadeo.
    private let minimo: Duration = .seconds(1.2)
    /// Tiempo máximo esperando a la hoja de cálculo.
    private let maximo: Duration = .seconds(6)

    var body: some View {
        ZStack {
            contenido
            if !listo {
                PantallaArranque()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task { await arrancar() }
    }

    private func arrancar() async {
        let inicio = ContinuousClock.now
        if almacen.configurado {
            let carga = Task { await almacen.recargar() }
            await withTaskGroup(of: Void.self) { grupo in
                grupo.addTask { await carga.value }
                grupo.addTask { try? await Task.sleep(for: maximo) }
                await grupo.next()
                grupo.cancelAll()
            }
        }
        let restante = minimo - (ContinuousClock.now - inicio)
        if restante > .zero { try? await Task.sleep(for: restante) }
        withAnimation(.easeOut(duration: 0.6)) { listo = true }
    }
}

struct PantallaArranque: View {
    var body: some View {
        Color.black
            .overlay {
                Image("Arranque")
                    .resizable()
                    .scaledToFill()
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 320)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Finanzas")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Actualizando datos…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.bottom, 56)
            }
            .clipped()
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }
}

#Preview {
    PantallaArranque()
}
