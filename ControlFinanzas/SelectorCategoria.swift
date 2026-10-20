import SwiftUI

/// Rejilla de categorías con opción de crear una nueva. Una cadena vacía significa "ninguna".
struct SelectorCategoria: View {
    @Binding var categoria: String

    @Environment(Almacen.self) private var almacen
    @State private var creando = false
    @State private var nueva = ""
    @FocusState private var enfocado: Bool

    private var opciones: [String] {
        var lista = almacen.categorias
        if !categoria.isEmpty, categoria != "Sin clasificar", !creando, !lista.contains(categoria) {
            lista.insert(categoria, at: 0)
        }
        return lista
    }

    var body: some View {
        Group {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(opciones, id: \.self) { c in
                    let estilo = EstiloCategoria.de(c)
                    Chip(texto: c, icono: estilo.icono, color: estilo.color, seleccionado: !creando && categoria == c) {
                        creando = false
                        categoria = c
                    }
                }
                Chip(texto: "Nueva", icono: "plus", color: .gray, seleccionado: creando) {
                    creando = true
                    categoria = nueva.trimmingCharacters(in: .whitespaces)
                    enfocado = true
                }
            }
            .padding(.vertical, 4)

            if creando {
                TextField("Nombre de la categoría", text: $nueva, prompt: Text("Nombre de la categoría"))
                    .labelsHidden()
                    .focused($enfocado)
                    .onChange(of: nueva) { _, valor in categoria = valor.trimmingCharacters(in: .whitespaces) }
            }
        }
    }
}

struct Chip: View {
    let texto: String
    let icono: String
    let color: Color
    let seleccionado: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 4) {
                Image(systemName: icono).font(.caption)
                Text(texto).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .foregroundStyle(seleccionado ? .white : color)
            .background(seleccionado ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.12)),
                        in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
