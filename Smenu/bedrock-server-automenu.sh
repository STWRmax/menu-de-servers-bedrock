#!/usr/bin/env bash
set -euo pipefail

# ================== CONFIGURACIÓN AUTOMÁTICA ==================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$SCRIPT_DIR/backups"

BDS_BIN="$SERVER_DIR/bedrock_server"
SESSION="bedrock"
USE_TMUX=false
WORLD_NAME="$(awk -F= '/^level-name=/{print $2}' "$SERVER_DIR/server.properties" 2>/dev/null || echo 'STWR_SERVER')"

mkdir -p "$BACKUP_DIR"

# ================== CONFIGURACIÓN DE BATERÍA ==================
BAT_MODE="off"   # modos: auto / apagado / off
BAT_LOW=15       # % mínimo para apagar
BAT_ON=50        # % para volver a encender en modo auto

# ================== COLORES ==================
verde='\033[0;32m'; rojo='\033[0;31m'; neutro='\033[0m'

# ================== FUNCIONES AUXILIARES ==================
have()      { command -v "$1" >/dev/null 2>&1; }
use_screen(){ $USE_TMUX && return 1 || return 0; }

sess_exists(){
  if use_screen; then
    screen -ls | grep -q "[.]${SESSION}[[:space:]]"
  else
    tmux has-session -t "$SESSION" 2>/dev/null
  fi
}
sess_send(){ local cmd="$*"; if use_screen; then screen -S "$SESSION" -p 0 -X stuff "$cmd$(printf '\r')"; else tmux send-keys -t "$SESSION" "$cmd" C-m; fi; }
sess_new(){
  if use_screen; then
    have screen || { echo -e "${rojo}Falta 'screen'.${neutro}"; exit 1; }
    screen -dmS "$SESSION" bash -lc "cd '$SERVER_DIR' && exec '$BDS_BIN'"
  else
    have tmux || { echo -e "${rojo}Falta 'tmux'.${neutro}"; exit 1; }
    tmux new -d -s "$SESSION" "cd '$SERVER_DIR' && exec '$BDS_BIN'"
  fi
}
is_running(){ sess_exists; }

# ================== GESTIÓN DEL SERVIDOR ==================
_iniciar_base(){
  if is_running; then echo -e "${rojo}Servidor ya está en ejecución.${neutro}"; return; fi
  [[ -x "$BDS_BIN" ]] || { echo -e "${rojo}No se puede ejecutar: $BDS_BIN${neutro}"; return 1; }
  sess_new && sleep 2
  is_running && echo -e "${verde}Servidor iniciado.${neutro}" || echo -e "${rojo}Error al iniciar el servidor.${neutro}"
}
iniciar_con_terminal_nueva(){ _iniciar_base; (use_screen && screen -r "$SESSION" || tmux attach -t "$SESSION"); }
detener_servidor(){
  if ! is_running; then echo -e "${rojo}Servidor no está activo.${neutro}"; return; fi
  echo -e "${verde}Guardando y deteniendo...${neutro}"
  sess_send "save-all"; sleep 1; sess_send "stop"
  for i in {1..25}; do ! sess_exists && echo -e "${verde}Servidor detenido.${neutro}" && return; sleep 1; done
  echo -e "${rojo}Forzando cierre...${neutro}"
  use_screen && screen -S "$SESSION" -X quit || tmux kill-session -t "$SESSION"
}
reiniciar_servidor(){ detener_servidor; sleep 2; iniciar_con_terminal_nueva; }

# ================== COPIAS DE SEGURIDAD ==================
# Copia diaria (1 archivo fijo local)
copia_diaria(){
  local DEST="$BACKUP_DIR/backup_daily.tar.gz"
  echo "[INFO] Creando copia diaria..."
  tar -C "$SERVER_DIR/worlds" -czf "$DEST" "$WORLD_NAME"
  echo "[INFO] Copia diaria lista → $DEST"
}

# Copia 6h (1 local fijo + subida con fecha a Terabox)
copia_6h(){
  local DEST="$BACKUP_DIR/backup_6h.tar.gz"
  local REMOTE_NAME="backup_6h_$(date '+%F_%H').tar.gz"

  echo "[INFO] Creando copia 6h local..."
  tar -C "$SERVER_DIR/worlds" -czf "$DEST" "$WORLD_NAME"
  echo "[INFO] Copia 6h local lista → $DEST"

  if have rclone; then
    echo "[INFO] Subiendo copia a Terabox como $REMOTE_NAME ..."
    rclone copy "$DEST" "terabox:/mcbedrock_backups/$REMOTE_NAME"
    echo "[INFO] Subida completada."
  else
    echo "[WARN] rclone no está instalado/configurado. No se subió a Terabox."
  fi
}

mostrar_copias(){
  ls -lh "$BACKUP_DIR" 2>/dev/null || echo "No hay copias."
}

restaurar_copia(){
  echo "== Copias disponibles en local =="
  ls -lh "$BACKUP_DIR" || { echo "No hay copias."; return; }
  read -r -p "¿Restaurar 'backup_daily.tar.gz' o 'backup_6h.tar.gz'? (d/6/q): " opt
  case $opt in
    d) ARCHIVO="$BACKUP_DIR/backup_daily.tar.gz" ;;
    6) ARCHIVO="$BACKUP_DIR/backup_6h.tar.gz" ;;
    q|Q) echo "❌ Cancelado."; return ;;
    *) echo "❌ Opción inválida."; return ;;
  esac
  [[ ! -f "$ARCHIVO" ]] && { echo "❌ No existe $ARCHIVO"; return; }
  echo -e "${rojo}⚠ Restaurar desde $(basename "$ARCHIVO")? (s/n)${neutro}"
  read -r confirm; [[ "$confirm" != "s" ]] && echo "❌ Cancelado." && return
  detener_servidor
  local WORLD_PATH="$SERVER_DIR/worlds/$WORLD_NAME"
  [[ -d "$WORLD_PATH" ]] && mv "$WORLD_PATH" "${WORLD_PATH}_backup_$(date +%F_%T)"
  mkdir -p "$SERVER_DIR/worlds"
  tar -C "$SERVER_DIR/worlds" -xzf "$ARCHIVO"
  echo -e "${verde}✅ Restauración completa.${neutro}"
  iniciar_con_terminal_nueva
}

# ================== BATERÍA ==================
bateria_nivel(){
  if have upower; then upower -i $(upower -e | grep BAT) | awk '/percentage:/ {print $2}' | tr -d '%'
  elif have acpi; then acpi -b | grep -oP '\d+%' | tr -d '%'
  else echo 100; fi
}

submenu_bateria(){
  while true; do
    echo ""
    echo "========== Submenú Batería ⚡ =========="
    echo "1) Activar protección (apagar 15%, encender 50%)"
    echo "2) Activar solo apagado (15%)"
    echo "3) Desactivar protección"
    echo "4) Mostrar estado batería"
    echo "B) Volver"
    echo "========================================"
    read -r -p "Opción: " bat
    case $bat in
      1) BAT_MODE="auto"; echo "Modo auto activado." ;;
      2) BAT_MODE="apagado"; echo "Modo solo apagado activado." ;;
      3) BAT_MODE="off"; echo "Protección desactivada." ;;
      4) echo "🔋 Batería: $(bateria_nivel)% | Protección: $BAT_MODE" ;;
      B|b) break ;;
      *) echo "❌ Opción inválida." ;;
    esac
  done
}

# ================== SUBMENÚ COPIAS ==================
submenu_copias(){
  while true; do
    echo ""
    echo "====== Submenú Copias de Seguridad ======"
    echo "1) Crear copia diaria (backup_daily)"
    echo "2) Crear copia 6h + subida a Terabox (backup_6h)"
    echo "3) Mostrar copias locales"
    echo "R) Restaurar copia"
    echo "B) Volver"
    echo "========================================="
    read -r -p "Opción: " sub
    case $sub in
      1) copia_diaria ;;
      2) copia_6h ;;
      3) mostrar_copias ;;
      R|r) restaurar_copia ;;
      B|b) break ;;
      *) echo "❌ Opción inválida." ;;
    esac
  done
}

# ================== ESTADO GENERAL ==================
estado_servidor(){
  echo -e "\n========== ${verde}ESTADO GENERAL${neutro} =========="
  if is_running; then echo -e "🟢 Servidor: ${verde}EN EJECUCIÓN${neutro}"; else echo -e "🔴 Servidor: ${rojo}DETENIDO${neutro}"; fi
  echo "🌍 Mundo: $WORLD_NAME"
  echo "🎮 Dificultad: $(awk -F= '/^difficulty=/{print $2}' "$SERVER_DIR/server.properties")"

  local mode=$(awk -F= '/^game.?mode=/{print $2}' "$SERVER_DIR/server.properties")
  case "$mode" in
    0|"survival")  mode="Survival" ;;
    1|"creative")  mode="Creative" ;;
    2|"adventure") mode="Adventure" ;;
    3|"spectator") mode="Spectator" ;;
    *)             mode="Desconocido" ;;
  esac
  echo "🎮 Modo: $mode"

  echo "💾 Backups en local:"
  ls -lh "$BACKUP_DIR" || echo "No hay copias."

  echo "🔋 Batería: $(bateria_nivel)% | Protección: $BAT_MODE"
  echo -e "===========================================\n"
}

# ================== MENÚ PRINCIPAL ==================
while true; do
  echo ""
  echo "========== Menú Servidor Minecraft Bedrock =========="
  echo "0) Iniciar servidor con consola"
  echo "2) Detener servidor"
  echo "3) Reiniciar servidor"
  echo "4) Estado general"
  echo "B) Menú de batería ⚡"
  echo "C) Menú de copias 💾"
  echo "Q) Salir"
  echo "====================================================="
  read -r -p "Selecciona una opción: " opcion
  case $opcion in
    0) iniciar_con_terminal_nueva ;;
    2) detener_servidor ;;
    3) reiniciar_servidor ;;
    4) estado_servidor ;;
    B|b) submenu_bateria ;;
    C|c) submenu_copias ;;
    Q|q) echo "👋 Hasta luego."; break ;;
    *) echo "❌ Opción no válida." ;;
  esac
done
