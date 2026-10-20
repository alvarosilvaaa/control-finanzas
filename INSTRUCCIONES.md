# Control de Finanzas — puesta en marcha

## 1. Instalar el script en la hoja (una sola vez)

1. Abre la hoja **Control finanzas** → menú **Extensiones → Apps Script**.
2. Borra lo que haya en `Código.gs` y pega el contenido de `AppsScript/Codigo.gs`. Guarda.
3. Pulsa **Implementar → Nueva implementación**.
   - Tipo: **Aplicación web**
   - Ejecutar como: **Yo**
   - Quién tiene acceso: **Cualquier usuario**
4. Autoriza los permisos (Google avisará de que la app no está verificada: *Configuración avanzada → Ir a…*).
5. Copia la **URL de la aplicación web** (termina en `/exec`).
6. En Apps Script, ve a **⚙️ Configuración del proyecto → Propiedades del script → Añadir propiedad**:
   nombre `TOKEN`, valor: una contraseña larga (p. ej. 32 letras y números). Guarda.
   Para el botón **Preguntar a Claude**, añade otra propiedad: nombre `ANTHROPIC_API_KEY`,
   valor: tu clave de la API de Anthropic (se crea en console.anthropic.com → API Keys).
   El token no está en el código para que no se suba a GitHub. Tu token actual está en
   `AppsScript/token.local.txt` (este archivo no se sube).

> "Cualquier usuario" es necesario para que la app pueda llamar al script sin iniciar sesión.
> Lo protege el `TOKEN` del script: sin él no se puede leer ni escribir nada.

Si más adelante cambias el script: **Implementar → Gestionar implementaciones → ✏️ → Versión: Nueva versión → Implementar** (así la URL no cambia). Si usas "Nueva implementación", Google crea una URL nueva y hay que pegarla otra vez en Ajustes de la app.

## 2. Conectar la app

En la app, pestaña **Ajustes**: pega la URL y el token (el de las Propiedades del script), desactiva el modo demostración y pulsa **Conectar y cargar datos**.

## 3. Instalar en el iPhone (cuenta gratuita)

1. Abre `ControlFinanzas.xcodeproj` en Xcode.
2. Xcode → Settings → Accounts → añade tu Apple ID.
3. Selecciona el target **ControlFinanzas** → *Signing & Capabilities* → Team: tu nombre (Personal Team).
   Si se queja del Bundle Identifier, cámbialo por otro único (p. ej. `com.tunombre.finanzas`).
4. Conecta el iPhone por cable, elígelo arriba como destino y pulsa ▶︎.
5. La primera vez, en el iPhone: Ajustes → General → VPN y gestión de dispositivos → confía en tu perfil.
   Y activa Ajustes → Privacidad y seguridad → **Modo desarrollador**.

Con cuenta gratuita la app caduca a los 7 días: basta con repetir el paso 4.

## Qué se guarda dónde

| Dato | Pestaña de la hoja |
|---|---|
| Gastos (app, atajo y pagos automáticos) | `Respuestas de formulario 1` → `Gastos` (vía el mismo formulario) |
| Presupuesto base por mes | `Presupuesto` (se crea sola) |
| Propinas e ingresos extra | `Ingresos extra` (se crea sola) |

## App de Mac

Está instalada en **/Applications/Finanzas.app**. Para actualizarla tras un cambio:

```
./actualizar_mac.sh
```

Compila la versión final, cierra la app, sustituye la copia de Aplicaciones y la vuelve a abrir. La URL, el token y los datos se conservan.
