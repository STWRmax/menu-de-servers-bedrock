#!/usr/bin/env bash
set -euo pipefail

# ========== DETECTAR RUTA BASE ==========
BASE_DIR="$(dirname "$(readlink -f "$0")")"
cd "$BASE_DIR" || exit 1

# ========== CONFIGURACIÓN ==========
# Buscar carpeta padre de Smenu
PARENT_DIR="$(dirname "$BASE_DIR")"

# Si existe el binario en el padre
if [ -x "$PARENT_DIR/bedrock_server" ]; then
  SERVER_DIR="$PARENT_DIR"
  BDS_BIN="$SERVER_DIR/bedrock_server"
else
  # Si no, buscar en /home
  BDS_BIN="$(find /home -type f -name 'bedrock_server' -executable 2>/dev/null | head -n1 || true)"
  if [ -n "$BDS_BIN" ]; then
    SERVER_DIR="$(dirname "$BDS_BIN")"
  else
    echo "❌ No se encontró bedrock_server ni en el directorio padre ni en /home"
    exit 1
  fi
fi

SESSION="bedrock"
BACKUP_DIR="$SERVER_DIR/backups"
WORLD_NAME="$(awk -F= '/^level-name=/{print $2}' "$SERVER_DIR/server.properties" 2>/dev/null || echo 'STWR_SERVER')"

# Configuración de batería
BAT_MODE="off"
BAT_LOW=15
BAT_ON=50

# ========== COLORES ==========
verde='\033[0;32m'; rojo='\033[0;31m'; amarillo='\033[1;33m'; neutro='\033[0m'

# ========== AUXILIARES ==========
have() { command -v "$1" >/dev/null 2>&1; }

check_megatools() {
  if ! have megacopy; then
    echo "❌ megatools no está instalado."
    echo "   Instálalo con:"
    echo "     sudo apt install megatools     # Debian/Ubuntu"
    echo "     sudo pacman -S megatools       # Arch"
    echo "     sudo dnf install megatools     # Fedora"
    read -p 'Pulsa ENTER para continuar...'
    return 1
  fi
  return 0
}

choose_session() {
  if have tmux; then echo "tmux"
  elif have screen; then echo "screen"
  else echo "none"
  fi
}

sess_exists(){
  case "$(choose_session)" in
    tmux)   tmux has-session -t "$SESSION" 2>/dev/null ;;
    screen) screen -ls | grep -q "[.]${SESSION}[[:space:]]" ;;
    *)      false ;;
  esac
}

sess_send(){
  local cmd="$*"
  case "$(choose_session)" in
    tmux)   tmux send-keys -t "$SESSION" "$cmd" C-m ;;
    screen) screen -S "$SESSION" -p 0 -X stuff "$cmd$(printf '\r')" ;;
  esac
}

sess_new(){
  mkdir -p "$BACKUP_DIR"
  case "$(choose_session)" in
    tmux)   tmux new -d -s "$SESSION" "cd '$SERVER_DIR' && exec '$BDS_BIN'" ;;
    screen) screen -dmS "$SESSION" bash -lc "cd '$SERVER_DIR' && exec '$BDS_BIN'" ;;
    none)   bash -lc "cd '$SERVER_DIR' && exec '$BDS_BIN'" ;;
  esac
}

is_running(){ sess_exists; }

# Abrir consola del server en terminal nueva
_open_new_terminal(){
  local cmd="$1"
  for term in gnome-terminal konsole xfce4-terminal mate-terminal tilix kitty alacritty lxterminal xterm; do
    if have "$term"; then
      case $term in
        gnome-terminal|mate-terminal) "$term" -- bash -c "$cmd; exec bash" && return ;;
        konsole|tilix|alacritty|kitty) "$term" -e bash -c "$cmd; exec bash" && return ;;
        xfce4-terminal|lxterminal) "$term" -e "bash -c '$cmd; exec bash'" && return ;;
        xterm) xterm -e bash -c "$cmd; exec bash" && return ;;
      esac
    fi
  done
  echo -e "${rojo}No hay terminal gráfica disponible. Ejecutando aquí...${neutro}"
  bash -c "$cmd"
}

# ========== FUNCIONES SERVIDOR ==========
_iniciar_base(){
  if is_running; then return; fi
  [[ -x "$BDS_BIN" ]] || { echo -e "${rojo}No se puede ejecutar: $BDS_BIN${neutro}"; return 1; }
  sess_new && sleep 2
  is_running && echo -e "${verde}Servidor iniciado.${neutro}" || echo -e "${rojo}Error al iniciar el servidor.${neutro}"
}

iniciar_con_terminal_nueva(){
  if is_running; then
    echo -e "${verde}Servidor ya estaba en ejecución. Abriendo consola...${neutro}"
  else
    _iniciar_base
  fi
  case "$(choose_session)" in
    tmux)   _open_new_terminal "tmux attach -t $SESSION" ;;
    screen) _open_new_terminal "screen -r $SESSION" ;;
    none)   _open_new_terminal "$BDS_BIN" ;;
  esac
}

detener_servidor(){
  if ! is_running; then echo -e "${rojo}Servidor no está activo.${neutro}"; return; fi
  echo -e "${verde}Guardando y deteniendo...${neutro}"
  sess_send "save-all"; sleep 1; sess_send "stop"
  for i in {1..25}; do ! sess_exists && echo -e "${verde}Servidor detenido.${neutro}" && return; sleep 1; done
  echo -e "${rojo}Forzando cierre...${neutro}"
  case "$(choose_session)" in
    tmux)   tmux kill-session -t "$SESSION" ;;
    screen) screen -S "$SESSION" -X quit ;;
  esac
}

reiniciar_servidor(){ detener_servidor; sleep 2; iniciar_con_terminal_nueva; }

# ========== ESTADO ==========
# (igual que en tu versión, solo corregido echo -e en autocopia/inactivo)

# ========== FUNCIONES BACKUP ==========
# (igual que las tuyas: copia_mundo, mostrar_copias, eliminar_copias, restaurar_copia)

# ========== FUNCIONES MEGA ==========
subir_backup_mega() {
  local file="$1"
  check_megatools || return
  if [ -f "$file" ]; then
    echo "☁️ Subiendo copia a MEGA: $(basename "$file")..."
    megacopy --reload --local "$file" --remote /MinecraftBackups/
    [ $? -eq 0 ] && echo "✅ Copia subida a MEGA." || echo "❌ Error al subir la copia."
  else
    echo "❌ El archivo de backup no existe: $file"
  fi
}

listar_backups_mega() {
  check_megatools || return
  echo "📂 Copias disponibles en MEGA:"
  megals /MinecraftBackups/
}

# ========== SUBMENÚ COPIAS ==========
autoguardado_tmux(){
  if ! have tmux; then
    echo "❌ tmux no está instalado. Instálalo con: sudo apt install tmux"
    return
  fi
  tmux new -d -s autocopia "
    while true; do
      # Crear copia local
      $(realpath "$0") --backup
      # Subir la última copia a MEGA (si está megatools)
      latest=\$(ls -1t \"$BACKUP_DIR\"/*.tar.gz 2>/dev/null | head -n1)
      if [ -n \"\$latest\" ]; then
        if command -v megacopy >/dev/null 2>&1; then
          echo \"☁️ Subiendo copia automática a MEGA: \$(basename \"\$latest\")\"
          megacopy --reload --local \"\$latest\" --remote /MinecraftBackups/
        else
          echo \"⚠️ megatools no instalado, copia no subida a MEGA.\"
        fi
      fi
      sleep 3600
    done
  "
  echo -e "${verde}Autoguardado corriendo en segundo plano (tmux sesión: autocopia).${neutro}"
}


submenu_copias(){
  while true; do
    echo ""
    echo "====== Submenú Copias de Seguridad ======"
    echo "1) Crear copia del mundo"
    echo "2) Mostrar últimas 10 copias"
    echo "3) Eliminar copias (mantener 4 más recientes)"
    echo "4) Iniciar autoguardado en segundo plano (tmux)"
    echo "5) Subir última copia a MEGA ☁️"
    echo "6) Listar copias en MEGA 📂"
    echo "B) Volver"
    echo "========================================="
    read -r -p "Opción: " sub
    case $sub in
      1) copia_mundo ;;
      2) mostrar_copias ;;
      3) eliminar_copias ;;
      4) autoguardado_tmux ;;
      5) latest="$(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1)"
         [ -n "$latest" ] && subir_backup_mega "$latest" || echo "❌ No hay copias locales." ;;
      6) listar_backups_mega ;;
      B|b) break ;;
      *) echo "❌ Opción inválida." ;;
    esac
  done
}

# ========== SUBMENÚ BATERÍA ==========
# (igual que en tu script)

# ========== MENÚ PRINCIPAL ==========
while true; do
  echo ""
  echo "========== Menú Servidor Minecraft Bedrock =========="
  echo "1) Iniciar servidor con consola"
  echo "2) Detener servidor"
  echo "3) Reiniciar servidor"
  echo "4) Estado general"
  echo "5) Menú de batería ⚡"
  echo "6) Menú de copias 💾"
  echo "7) Restaurar una copia"
  echo "Q) Salir"
  echo "====================================================="
  read -r -p "Selecciona una opción: " opcion
  case $opcion in
    1) iniciar_con_terminal_nueva ;;
    2) detener_servidor ;;
    3) reiniciar_servidor ;;
    4) estado_servidor ;;
    5) submenu_bateria ;;
    6) submenu_copias ;;
    7) restaurar_copia ;;
    Q|q) echo "👋 Hasta luego."; break ;;
    *) echo "❌ Opción no válida." ;;
  esac
done
