#!/usr/bin/env bash
set -euo pipefail

# ========== CONFIGURACIÓN ==========
SERVER_DIR="/home/nube/mcbedrock/Server-Minecraft-Bedrock"
BDS_BIN="$SERVER_DIR/bedrock_server"
SESSION="bedrock"
BACKUP_DIR="/home/nube/mcbedrock/backups"
WORLD_NAME="$(awk -F= '/^level-name=/{print $2}' "$SERVER_DIR/server.properties" 2>/dev/null || echo 'STWR_SERVER')"

# Configuración de batería
BAT_MODE="off"   # modos: auto / apagado / off
BAT_LOW=15       # % mínimo para apagar
BAT_ON=50        # % para volver a encender en modo auto

# ========== COLORES ==========
verde='\033[0;32m'; rojo='\033[0;31m'; neutro='\033[0m'

# ========== AUXILIARES ==========
have() { command -v "$1" >/dev/null 2>&1; }

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

# Opción 1: iniciar o abrir consola
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

  # Estado del servidor (sesión)
  if is_running; then
    echo -e "🟢 Servidor: ${verde}EN EJECUCIÓN${neutro} (sesión: $SESSION)"
  else
    echo -e "🔴 Servidor: ${rojo}DETENIDO${neutro}"
  fi

  # Info del mundo (tolerante a errores)
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

  # Backups (no romper si no hay archivos)
  local count latest size_total
  count="$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l || true)"
  echo "💾 Copias: ${count:-0}"
  if [[ "${count:-0}" -gt 0 ]]; then
    latest="$(basename "$(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1 || true)")"
    size_total="$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")"
    echo "   Última: ${latest:-N/A}"
    echo "   Tamaño total: ${size_total}"
  fi

  # Autocopia (tmux o crontab)
  if tmux has-session -t autocopia 2>/dev/null; then
    echo "⏰ Autocopia: ${verde}ACTIVADA (tmux: autocopia)${neutro}"
  elif crontab -l 2>/dev/null | grep -qF "$BACKUP_DIR"; then
    echo "⏰ Autocopia: ${verde}ACTIVADA (crontab)${neutro}"
  else
    echo "⏰ Autocopia: ${rojo}DESACTIVADA${neutro}"
  fi

  # Monitor batería en tmux
  if tmux has-session -t bateria 2>/dev/null; then
    echo "🔋 Monitor batería: ${verde}ACTIVO (tmux: bateria)${neutro}"
  else
    echo "🔋 Monitor batería: ${rojo}INACTIVO${neutro}"
  fi

  # Nivel de batería actual (si hay utilidades)
  if have upower || have acpi; then
    local nivel
    if have upower; then
      nivel="$(upower -i "$(upower -e | grep BAT || true)" 2>/dev/null | awk '/percentage:/ {print $2}' | tr -d '%' || true)"
    else
      nivel="$(acpi -b 2>/dev/null | grep -oP '\d+%' | tr -d '%' || true)"
    fi
    [[ -n "${nivel:-}" ]] && echo "🔋 Batería actual: ${nivel}% | Protección: ${BAT_MODE}"
  fi

  echo -e "===========================================\n"
}

# ========== FUNCIONES BACKUP ==========
copia_mundo(){
  local MAX_BACKUPS=4
  local LOCK_FILE="/tmp/bedrock_backup.lock"
  local WORLD_SRC="$SERVER_DIR/worlds/$WORLD_NAME"

  mkdir -p "$BACKUP_DIR"
  [[ -d "$WORLD_SRC" ]] || { echo "No existe el mundo en: $WORLD_SRC" >&2; return 1; }

  # lock
  if [[ -f "$LOCK_FILE" ]]; then
    oldpid="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    if [[ -n "$oldpid" ]] && ps -p "$oldpid" >/dev/null 2>&1; then
      echo "Otro backup está en curso (PID $oldpid)."
      return 0
    fi
  fi
  echo "$$" > "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT

  # nombre → fecha YYYY-MM-DD
  STAMP="$(date '+%F')"
  DEST="$BACKUP_DIR/${WORLD_NAME// /_}_$STAMP.tar.gz"
  [ -f "$DEST" ] && rm -f "$DEST"

  echo "[INFO] Creando backup de $WORLD_NAME ..."
  tar -C "$SERVER_DIR/worlds" -czf "$DEST" "$WORLD_NAME"
  echo "[INFO] Backup completado → $DEST"

  # retención
  mapfile -t ALL_BACKUPS < <(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true)
  if [[ ${#ALL_BACKUPS[@]} -gt $MAX_BACKUPS ]]; then
    for ((i=MAX_BACKUPS; i<${#ALL_BACKUPS[@]}; i++)); do
      echo "[INFO] Eliminando viejo: ${ALL_BACKUPS[$i]}"
      rm -f -- "${ALL_BACKUPS[$i]}" || true
    done
  fi
}

mostrar_copias(){ ls -lt "$BACKUP_DIR" 2>/dev/null | head -n 11 || echo "No hay copias."; }

eliminar_copias(){
  echo -e "${rojo}¿Eliminar todas excepto las 4 más recientes? (s/n)${neutro}"
  read -r c; [[ "$c" == "s" ]] || return
  mapfile -t FILES < <(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true)
  for ((i=4; i<${#FILES[@]}; i++)); do rm -f -- "${FILES[$i]}"; echo "Eliminado: ${FILES[$i]}"; done
}

restaurar_copia(){
  mapfile -t FILES < <(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true)
  [[ ${#FILES[@]} -eq 0 ]] && echo -e "${rojo}No hay copias disponibles.${neutro}" && return
  echo "== Copias disponibles =="
  for i in "${!FILES[@]}"; do echo "$((i+1))) $(basename "${FILES[$i]}")"; done
  read -r -p "Número de copia a restaurar (q para cancelar): " idx
  [[ "$idx" == "q" || "$idx" == "Q" ]] && echo "❌ Cancelado." && return
  if [[ "$idx" =~ ^[0-9]+$ && $idx -ge 1 && $idx -le ${#FILES[@]} ]]; then
    local ARCHIVO="${FILES[$((idx-1))]}"
    echo -e "${rojo}⚠ Restaurar ${ARCHIVO}? (s/n)${neutro}"
    read -r confirm; [[ "$confirm" != "s" ]] && echo "❌ Cancelado." && return
    detener_servidor
    local WORLD_PATH="$SERVER_DIR/worlds/$WORLD_NAME"
    [[ -d "$WORLD_PATH" ]] && mv "$WORLD_PATH" "${WORLD_PATH}_backup_$(date +%F_%T)"
    mkdir -p "$SERVER_DIR/worlds"
    tar -C "$SERVER_DIR/worlds" -xzf "$ARCHIVO"
    echo -e "${verde}✅ Restauración completa.${neutro}"
    iniciar_con_terminal_nueva
  else
    echo -e "${rojo}❌ Opción inválida.${neutro}"
  fi
}

# ========== FUNCIONES BATERÍA ==========
bateria_nivel(){
  if have upower; then upower -i $(upower -e | grep BAT) | awk '/percentage:/ {print $2}' | tr -d '%'
  elif have acpi; then acpi -b | grep -oP '\d+%' | tr -d '%'
  else echo 100; fi
}

monitor_bateria_tmux(){
  tmux new -d -s bateria "while true; do echo \"🔋 Batería: \$(date) \$(upower -i \$(upower -e | grep BAT) | awk '/percentage:/ {print \$2}')\"; sleep 60; done"
  echo -e "${verde}Monitor de batería corriendo en segundo plano (tmux sesión: bateria).${neutro}"
}

submenu_bateria(){
  while true; do
    echo ""
    echo "========== Submenú Batería ⚡ =========="
    echo "1) Activar protección (apagar 15%, encender 50%)"
    echo "2) Activar solo apagado (15%)"
    echo "3) Desactivar protección"
    echo "4) Mostrar estado batería"
    echo "5) Iniciar monitor en segundo plano (tmux)"
    echo "B) Volver"
    echo "========================================"
    read -r -p "Opción: " bat
    case $bat in
      1) BAT_MODE="auto"; echo "Modo auto activado." ;;
      2) BAT_MODE="apagado"; echo "Modo solo apagado activado." ;;
      3) BAT_MODE="off"; echo "Protección desactivada." ;;
      4) echo "🔋 Nivel: $(bateria_nivel)% | Protección: $BAT_MODE" ;;
      5) monitor_bateria_tmux ;;
      B|b) break ;;
      *) echo "❌ Opción inválida." ;;
    esac
  done
}

# ========== SUBMENÚ COPIAS ==========
autoguardado_tmux(){
  tmux new -d -s autocopia "while true; do $(realpath "$0") --backup; sleep 3600; done"
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
    echo "B) Volver"
    echo "========================================="
    read -r -p "Opción: " sub
    case $sub in
      1) copia_mundo ;;
      2) mostrar_copias ;;
      3) eliminar_copias ;;
      4) autoguardado_tmux ;;
      B|b) break ;;
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
