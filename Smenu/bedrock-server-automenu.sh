#!/usr/bin/env bash
set -euo pipefail


# ========== DETECTAR RUTA BASE ==========
BASE_DIR="$(dirname "$(readlink -f "$0")")"
cd "$BASE_DIR" || exit 1
# ========== LOG ==========
LOG_FILE="$BASE_DIR/server.log"

log(){
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo -e "$msg" | tee -a "$LOG_FILE"
}

# ========== DETECTAR RUTA BASE ==========
BASE_DIR="$(dirname "$(readlink -f "$0")")"
cd "$BASE_DIR" || exit 1

# ========== CONFIGURACIÓN ==========
# Buscar carpeta padre de Smenu
PARENT_DIR="$(dirname "$BASE_DIR")"

# Crear config.sh si no existe
if [[ ! -f "$BASE_DIR/config.sh" ]]; then
  cat > "$BASE_DIR/config.sh" <<'EOF'
# ========= CONFIGURACIÓN AUTO-GENERADA =========
AUTOBKP_ENABLED="off"
AUTOBKP_INTERVAL=3600
UPLOAD_TO_MEGA="off"
MEGA_REMOTE_DIR="/MinecraftBackups"
BAT_MODE="off"
BAT_LOW=15
BAT_ON=50
EOF
  echo "⚙️  Archivo config.sh generado con valores por defecto en $BASE_DIR"
fi

# Cargar configuración desde config.sh
source "$BASE_DIR/config.sh"

# Cargar .env si existe (sobrescribe valores de config.sh)
if [[ -f "$BASE_DIR/.env" ]]; then
  set -a
  source "$BASE_DIR/.env"
  set +a
fi


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
# Validar permisos de ejecución
if [[ ! -x "$BDS_BIN" ]]; then
  echo -e "${rojo}⚠ El servidor no es ejecutable.${neutro}"
  echo "   Solución rápida:"
  echo "   chmod +x \"$BDS_BIN\""
  exit 1
fi

SESSION="bedrock"
BACKUP_DIR="$SERVER_DIR/backups"
WORLD_NAME="$(awk -F= '/^level-name=/{print $2}' "$SERVER_DIR/server.properties" 2>/dev/null)"
if [[ -z "$WORLD_NAME" ]]; then
  WORLD_NAME="$(basename "$(ls -d "$SERVER_DIR/worlds"/* 2>/dev/null | head -n1)")"
fi
[[ -z "$WORLD_NAME" ]] && WORLD_NAME="default"

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
estado_servidor(){
  echo -e "\n========== ${verde}ESTADO GENERAL${neutro} =========="

  # 1. Estado del servidor
  if is_running; then
    echo -e "🟢 Servidor: ${verde}EN EJECUCIÓN${neutro} (sesión: $SESSION)"
  else
    echo -e "🔴 Servidor: ${rojo}DETENIDO${neutro}"
  fi

  # 2. Info del mundo desde server.properties en el directorio padre de Smenu
  local difficulty gamemode_raw gamemode
  difficulty="$(awk -F= '/^difficulty=/{print $2}' "$SERVER_DIR/server.properties" 2>/dev/null || true)"
  [[ -z "${difficulty:-}" ]] && difficulty="desconocida"

  gamemode_raw="$(awk -F= '/^game.?mode=/{print $2}' "$SERVER_DIR/server.properties" 2>/dev/null || true)"
  case "${gamemode_raw:-}" in
    0|survival)  gamemode="survival" ;;
    1|creative)  gamemode="creative" ;;
    2|adventure) gamemode="adventure" ;;
    3|spectator) gamemode="spectator" ;;
    *)           gamemode="desconocido" ;;
  esac

  echo "🌍 Mundo: $WORLD_NAME"
  echo "🎮 Dificultad: $difficulty"
  echo "🎮 Modo: $gamemode"

  # 3. Copias de seguridad
  local count latest size_total
  count="$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l || true)"
  echo "💾 Copias: ${count:-0}"
  if [[ "${count:-0}" -gt 0 ]]; then
    latest="$(basename "$(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1 || true)")"
    size_total="$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")"
    echo "   Última: ${latest:-N/A}"
    echo "   Tamaño total: ${size_total}"
  fi

  # 4. Estado autocopia
  if tmux has-session -t autocopia 2>/dev/null; then
    echo -e "⏰ Autocopia: ${verde}ACTIVADA (tmux: autocopia)${neutro}"
  else
    echo -e "⏰ Autocopia: ${rojo}DESACTIVADA${neutro}"
  fi

  # 5. Estado batería
  if tmux has-session -t bateria 2>/dev/null; then
    echo -e "🔋 Monitor batería: ${verde}ACTIVO (tmux: bateria)${neutro}"
  else
    echo -e "🔋 Monitor batería: ${rojo}INACTIVO${neutro}"
  fi

  echo -e "===========================================\n"
}
# ========== LISTAR MUNDOS ==========
listar_mundos(){
  local WORLDS_DIR="$SERVER_DIR/worlds"
  if [[ ! -d "$WORLDS_DIR" ]]; then
    echo "❌ No existe la carpeta de mundos en $WORLDS_DIR"
    return
  fi

  echo "🌍 Mundos disponibles:"
  for dir in "$WORLDS_DIR"/*; do
    [[ -d "$dir" ]] || continue
    local nombre="$(basename "$dir")"
    if [[ -f "$dir/levelname.txt" ]]; then
      local display_name="$(cat "$dir/levelname.txt")"
      echo " - $nombre  (Nombre en juego: $display_name)"
    else
      echo " - $nombre"
    fi
  done
}

# ========== FUNCIONES MEGA ==========
subir_backup_mega() {
  local file="$1"
  check_megatools || return 0   # no cortes el script por faltar megatools
  if [[ -f "$file" ]]; then
    echo "☁️ Subiendo copia a MEGA: $(basename "$file")..."
    if megacopy --reload --local "$file" --remote "$MEGA_REMOTE_DIR/"; then
      echo "✅ Copia subida a MEGA."
    else
      echo "❌ Error al subir la copia."
    fi
  else
    echo "❌ El archivo de backup no existe: $file"
  fi
}

listar_backups_mega() {
  check_megatools || return
  echo "📂 Copias disponibles en MEGA:"
  megals /MinecraftBackups/
}

# ===== Nivel de batería sin romper con pipefail =====
bateria_nivel(){
  local nivel=""
  if have upower; then
    # Busca un device de batería; si no hay, no rompe
    local dev
    dev="$(upower -e 2>/dev/null | grep -m1 -E 'BAT|battery' || true)"
    if [[ -n "$dev" ]]; then
      nivel="$(upower -i "$dev" 2>/dev/null | awk -F': *' '/percentage/{print $2}' | tr -d '%' || true)"
    fi
  elif have acpi; then
    nivel="$(acpi -b 2>/dev/null | grep -oE '[0-9]+%' | head -n1 | tr -d '%' || true)"
  fi
  [[ -n "$nivel" ]] && printf '%s\n' "$nivel" || printf '%s\n' "N/A"
}

monitor_bateria_tmux(){
  if ! have tmux; then echo "❌ tmux no está instalado."; return; fi
  if tmux has-session -t bateria 2>/dev/null; then
    echo "ℹ️ El monitor ya está corriendo (tmux: bateria)."; return
  fi
  # Bucle robusto dentro de tmux (no hereda tu set -euo pipefail)
  tmux new -d -s bateria "
    while true; do
      dev=\$(upower -e 2>/dev/null | grep -m1 -E 'BAT|battery' || true)
      if [ -n \"\$dev\" ]; then
        lvl=\$(upower -i \"\$dev\" 2>/dev/null | awk -F': *' '/percentage/{print \$2}' | tr -d '%' || true)
      else
        lvl=N/A
      fi
      echo \"[\$(date '+%F %T')] 🔋 Batería: \$lvl%\"
      sleep 60
    done
  " || true
  echo "🔋 Monitor de batería corriendo (tmux: bateria)."
}

# ========== SUBMENÚ COPIAS ==========
autoguardado_tmux(){
  if ! have tmux; then
    echo "❌ tmux no está instalado. Instálalo con: sudo apt install tmux"
    return
  fi

  if tmux has-session -t autocopia 2>/dev/null; then
    echo "ℹ️ La sesión 'autocopia' ya está corriendo."
    return
  fi

  AUTOBKP_INTERVAL="${AUTOBKP_INTERVAL:-3600}"
  SCRIPT_PATH_ESCAPED="$(printf "%q" "$(realpath "$0")")"

  tmux new -d -s autocopia "
    while true; do
      # 1) Crear copia local
      $SCRIPT_PATH_ESCAPED --backup

      # 2) Subir la última copia a MEGA (si megatools está disponible)
      latest=\$(ls -1t \"$BACKUP_DIR\"/*.tar.gz 2>/dev/null | head -n1)
      if [ -n \"\$latest\" ]; then
        if command -v megacopy >/dev/null 2>&1; then
          echo \"☁️ Subiendo copia automática a MEGA: \$(basename \"\$latest\")\"
          megacopy --reload --local \"\$latest\" --remote /MinecraftBackups/
        else
          echo \"⚠️ megatools no instalado, copia no subida a MEGA.\"
        fi
      fi

      sleep $AUTOBKP_INTERVAL
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
 5)
  latest="$(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest" ]]; then
    subir_backup_mega "$latest" || echo "⚠️ No se pudo subir la copia a MEGA."
  else
    echo "❌ No hay copias locales."
  fi
  ;;
      6) listar_backups_mega ;;
      B|b) break ;;
      *) echo "❌ Opción inválida." ;;
    esac
  done
}

# ========== SUBMENÚ BATERÍA ==========
submenu_bateria(){
  while true; do
    echo ""
    echo "========== Submenú Batería ⚡ =========="
    echo "1) Activar protección (apagar ${BAT_LOW}%, encender ${BAT_ON}%)"
    echo "2) Activar solo apagado (${BAT_LOW}%)"
    echo "3) Desactivar protección"
    echo "4) Mostrar estado batería"
    echo "5) Iniciar monitor en segundo plano (tmux)"
    echo "B) Volver"
    echo "========================================"
    read -r -p "Opción: " bat
    case "$bat" in
      1) BAT_MODE="auto"; echo "Modo auto activado." ;;
      2) BAT_MODE="apagado"; echo "Modo solo apagado activado." ;;
      3) BAT_MODE="off"; echo "Protección desactivada." ;;
      4) lvl="$(bateria_nivel)"
         if [[ "$lvl" == "N/A" ]]; then
           echo "🔋 No se pudo leer el nivel de batería (sin batería o sin upower/acpi)."
         else
           echo "🔋 Nivel: $lvl% | Protección: $BAT_MODE"
         fi ;;
      5) monitor_bateria_tmux ;;
      [Bb]) break ;;
      *) echo "❌ Opción inválida." ;;
    esac
  done
}
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
  echo "8) Listar mundos disponibles 🌍"
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
    8) listar_mundos ;;
    Q|q) echo "👋 Hasta luego."; break ;;
    *) echo "❌ Opción no válida." ;;
  esac
done
