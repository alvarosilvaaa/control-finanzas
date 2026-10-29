import SwiftUI

/// Lo que te debe el piso: gastos compartidos sin saldar, con un botón para marcarlos como pagados.
struct PisoView: View {
    @Environment(Almacen.self) private var almacen
    @State private var editando: Gasto?
    @State private var verSaldados = false
    @State private var trabajando: String?
    @State private var error: String?

    var body: some View {
        let pendientes = almacen.pendientesPiso
        let saldados = almacen.saldadosPiso

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Te deben").font(.subheadline).foregroundStyle(.secondary)
                    Text(Formato.eur(almacen.teDeben))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(pendientes.isEmpty ? "No tienes nada pendiente con el piso."
                         : pendientes.count == 1 ? "1 gasto compartido sin saldar"
                         : "\(pendientes.count) gastos compartidos sin saldar")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if pendientes.isEmpty && saldados.isEmpty {
                    Text("Para repartir un gasto, ábrelo y usa «Repartir con el piso»: indica qué parte es compartida y entre cuántas personas.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(pendientes, id: \.gasto.id) { fila($0.gasto, $0.reparto) }
                }

                if !saldados.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Button { withAnimation(.snappy) { verSaldados.toggle() } } label: {
                            HStack {
                                Text("Saldados").font(.title3.bold())
                                Text("\(saldados.count)").foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(verSaldados ? 0 : -90))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 6)
                        if verSaldados { ForEach(saldados, id: \.gasto.id) { fila($0.gasto, $0.reparto) } }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.fondo)
        .refreshable { await almacen.recargar() }
        .navigationTitle("Piso compartido")
        .tituloEnLinea()
        #if os(macOS)
        .toolbar { ToolbarItem { BotonRecargar() } }
        #endif
        .sheet(item: $editando) { EditarGastoView(gasto: $0).fontDesign(.rounded) }
        .alertaError($error)
    }

    private func fila(_ g: Gasto, _ r: Reparto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { editando = g } label: { FilaGasto(gasto: g, conFecha: true) }
                .buttonStyle(.plain)
            HStack {
                Text(r.partes.map { "\(Formato.eur($0.importe)) entre \($0.personas)" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if trabajando == g.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await marcar(g, !r.saldado) } } label: {
                        Text(r.saldado ? "Deshacer" : "Saldado · \(Formato.eur(r.teDeben))")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(r.saldado ? Tema.tinta : Color.fondo)
                            .background(r.saldado ? AnyShapeStyle(Tema.tinta.opacity(0.07)) : AnyShapeStyle(Tema.tinta),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 58)
        }
        .padding(.vertical, 4)
        .opacity(r.saldado ? 0.7 : 1)
    }

    private func marcar(_ g: Gasto, _ saldado: Bool) async {
        trabajando = g.id
        defer { trabajando = nil }
        do { try await almacen.marcarSaldado(g, saldado) } catch { self.error = error.localizedDescription }
    }
}

/// Aviso en el resumen del iPhone cuando el piso te debe dinero.
struct AvisoPiso: View {
    let importe: Double
    let cantidad: Int

    var body: some View {
        NavigationLink { PisoView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.tinta)
                    .frame(width: 36, height: 36)
                    .background(Tema.tinta.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("El piso te debe \(Formato.eur(importe))")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(cantidad == 1 ? "1 gasto compartido sin saldar" : "\(cantidad) gastos compartidos sin saldar")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
