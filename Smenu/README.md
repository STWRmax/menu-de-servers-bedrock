# 🟢 Menu de Servidor Minecraft Bedrock

Un script en **Bash** para administrar un servidor de **Minecraft Bedrock Edition** en Linux.
Permite iniciar, detener, reiniciar, hacer copias de seguridad automáticas, monitorear batería y subir copias a **MEGA** en segundo plano.

---

## 🚀 Características

* Inicia, detiene y reinicia el servidor fácilmente.
* Consola integrada (en **tmux**, **screen** o terminal normal).
* Menú visual con opciones numeradas.
* Copias de seguridad automáticas cada hora.
* Subida de copias a **MEGA** en segundo plano.
* Monitor de batería con apagado preventivo.
* Restauración rápida de mundos desde las copias.

---

## 📦 Dependencias

El script puede funcionar con distintos niveles de integración:

### 🔹 Recomendadas

* `tmux` → sesiones persistentes (autoguardado, batería, consola).
* `megatools` → subir copias automáticas a MEGA.

### 🔹 Alternativas

* `screen` → usado si no existe `tmux`.
* `upower` o `acpi` → para leer nivel de batería.

### 🔹 Instalación en Debian/Ubuntu

```bash
sudo apt update
sudo apt install tmux megatools upower
```

En Fedora:

```bash
sudo dnf install tmux megatools upower
```

En Arch:

```bash
sudo pacman -S tmux megatools upower
```

---

## ⚙️ Uso

Clona el repositorio y dale permisos al script:

```bash
git clone https://github.com/STWRmax/menu-de-servers-bedrock.git
cd menu-de-servers-bedrock/Smenu
chmod +x bedrock-server-automenu.sh
./bedrock-server-automenu.sh
```

---

## 📂 Estructura esperada

```
Smenu/
 ├── bedrock-server-automenu.sh
 ├── bedrock_server
 ├── server.properties
 ├── worlds/
 │    └── <tu_mundo>
 └── backups/
```

---

## 📋 Menú principal

```
========== Menú Servidor Minecraft Bedrock ==========
1) Iniciar servidor con consola
2) Detener servidor
3) Reiniciar servidor
4) Estado general
5) Menú de batería ⚡
6) Menú de copias 💾
7) Restaurar una copia
Q) Salir
=====================================================
```

---

## 💾 Copias de seguridad

En el **submenú de copias** podrás:

1. Crear copia local del mundo.
2. Mostrar últimas 10 copias.
3. Eliminar copias viejas (mantener 4 recientes).
4. Iniciar autoguardado en segundo plano.
5. Subir última copia a MEGA ☁️.
6. Listar copias en MEGA 📂.

### 🔹 Copias automáticas

* Si tienes **tmux** y **megatools**, cada copia creada se subirá automáticamente a MEGA.
* Si no está megatools → la copia se guarda localmente y se muestra un aviso.

---

## 🔋 Batería

* Protege contra apagados inesperados.
* Modos:

  * **Auto** → apaga al 15%, vuelve a encender al 50%.
  * **Solo apagado** → apaga al 15%.
  * **Off** → sin protección.
* Monitor en segundo plano disponible con `tmux`.

---

## 🌍 Estado General

Con la opción 4 puedes ver:

* Estado del servidor (🟢 en ejecución / 🔴 detenido).
* Nombre del mundo.
* Dificultad y modo de juego.
* Número de copias locales y su tamaño.
* Estado del autoguardado (tmux o crontab).
* Estado del monitor de batería.
* Nivel de batería actual (si hay utilidades instaladas).

---

## 🤝 Contribuciones

¡Bienvenidas! Puedes enviar PR o abrir issues con mejoras.

---

## 📜 Licencia

Este proyecto es libre y de uso educativo.
