import SwiftUI
import UserNotifications

struct AjustesView: View {
    @Environment(Almacen.self) private var almacen
    @AppStorage(Almacen.claveURL) private var url = ""
    @AppStorage(Almacen.claveToken) private var token = ""
    @AppStorage(Almacen.claveDemo) private var modoDemo = false
    @AppStorage("avisoMensual") private var avisoMensual = false
    @State private var probando = false
    @State private var resultado: (ok: Bool, texto: String)?
    /// `false` cuando ya está dentro de una navegación (el menú "Más" del iPhone).
    var conNavegacion = true

    var body: some View {
        if conNavegacion {
            NavigationStack { formulario }
        } else {
            formulario
        }
    }

    private var formulario: some View {
            Form {
                Section {
                    TextField("https://script.google.com/macros/s/…/exec", text: $url, prompt: Text("https://script.google.com/macros/s/…/exec"))
                        .labelsHidden()
                        .submitLabel(.done)
                        .tecladoURL()
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    SecureField("Token", text: $token)
                        .sinMayusculas()
                        .autocorrectionDisabled()
                    Button {
                        Task { await probar() }
                    } label: {
                        HStack {
                            Text("Conectar y cargar datos")
                            Spacer()
                            if probando { ProgressView() }
                        }
                    }
                    .disabled(probando || modoDemo || API(url: url, token: token) == nil)
                    if let resultado {
                        Label(resultado.texto, systemImage: resultado.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(resultado.ok ? Tema.tinta : Tema.alerta)
                            .font(.footnote)
                    }
                } header: {
                    Text("Conexión con Google Sheets")
                } footer: {
                    Text("Pega la URL de la aplicación web de Apps Script y el token (en Apps Script: Configuración del proyecto → Propiedades del script → TOKEN).")
                }

                Section {
                    Toggle("Aviso del resumen mensual", isOn: $avisoMensual)
                } footer: {
                    Text("El día 1 de cada mes te avisa de que ya tienes el resumen del mes anterior.")
                }

                Section {
                    Toggle("Modo demostración", isOn: $modoDemo)
                } footer: {
                    Text("Usa datos inventados para probar la app sin tocar tu hoja.")
                }

                Section {
                    LabeledContent("Gastos cargados", value: "\(almacen.datos.gastos.count)")
                    if let fecha = almacen.ultimaActualizacion {
                        LabeledContent("Última actualización",
                                       value: fecha.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .estiloLimpio()
            .navigationTitle("Ajustes")
            .hojaMac(ancho: 520, alto: 520)
            .ocultarTecladoFacil()
            .onChange(of: url) { _, nuevo in
                if nuevo.contains("\n") {
                    url = nuevo.replacingOccurrences(of: "\n", with: "")
                    Sistema.ocultarTeclado()
                }
            }
            .onChange(of: modoDemo) { Task { await almacen.ajustesCambiados() } }
            .onChange(of: avisoMensual) { _, activo in Task { await Avisos.configurar(activo: activo) } }
    }

    private func probar() async {
        probando = true
        defer { probando = false }
        await almacen.recargar()
        if let error = almacen.error {
            resultado = (false, error)
        } else {
            resultado = (true, "Conectado: \(almacen.datos.gastos.count) gastos cargados")
        }
    }
}

enum Avisos {
    private static let id = "resumen-mensual"

    static func configurar(activo: Bool) async {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: [id])
        guard activo else { return }
        guard (try? await centro.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }

        let contenido = UNMutableNotificationContent()
        contenido.title = "Tu resumen mensual está listo"
        contenido.body = "Mira cuánto gastaste el mes pasado y en qué categorías."
        contenido.sound = .default
        let disparador = UNCalendarNotificationTrigger(dateMatching: DateComponents(day: 1, hour: 10), repeats: true)
        try? await centro.add(UNNotificationRequest(identifier: id, content: contenido, trigger: disparador))
    }
}
