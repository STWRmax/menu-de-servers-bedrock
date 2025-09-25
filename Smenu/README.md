# 🟩 Bedrock Server AutoMenu

**Bedrock Server AutoMenu** es un script en **Bash** que provee un **menú interactivo** para gestionar un servidor de **Minecraft Bedrock** en Linux.

Incluye funciones de:
- Iniciar / detener / reiniciar el servidor.
- Copias de seguridad automáticas (locales y en Terabox vía `rclone`).
- Restaurar copias.
- Protección por batería (apaga el server al 15%, reinicia al 50%).
- Submenús organizados para facilitar la administración.

---

## 📂 Estructura recomendada de carpetas

Coloca la carpeta **Smenu** **dentro** de tu servidor Bedrock:

Server-Minecraft-Bedrock/
├── bedrock_server
├── server.properties
├── worlds/
├── resource_packs/
├── behavior_packs/
├── ...
└── Smenu/                 <-------------------------------------
├── bedrock-server-automenu.sh
├── minecraft-server.desktop
├── LICENSE
├── README.md
└── backups/

📌 Esto asegura que el script detecte el servidor automáticamente y que todas las copias se guarden en `Smenu/backups`.

---

## 🚀 Uso rápido

1. Da permisos de ejecución al script:

   ```bash
   chmod +x Smenu/bedrock-server-automenu.sh


./Smenu/bedrock-server-automenu.sh

También puedes abrir el archivo .desktop incluido (minecraft-server.desktop) para lanzar el menú en una terminal.

📌 Opciones principales del menú

0 → Iniciar servidor con consola

2 → Detener servidor

3 → Reiniciar servidor

4 → Estado general (muestra backups, batería, modo de juego, etc.)

B → Submenú de batería (proteger contra apagados inesperados)

C → Submenú de copias de seguridad

R → Restaurar copia

Q → Salir

🔋 Submenú de batería

Activar protección (apagar al 15%, encender al 50%).

Activar solo apagado (apaga al 15% y no reinicia).

Desactivar protección.

Ver estado actual de la batería.

💾 Submenú de copias de seguridad

Crear copia del mundo.

Mostrar últimas 10 copias.

Eliminar copias antiguas (mantener 4 más recientes).

Activar copias automáticas cada 24h o cada 6h (con opción de subida a Terabox vía rclone).

🎮 Requisitos

Linux con bash.

screen o tmux.

upower o acpi (para control de batería).

rclone (si deseas enviar copias a Terabox).