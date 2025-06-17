#!/bin/bash
UPDATER_MODE=0

load_json_file() {
    APPJSON_DIR="$(dirname "$(realpath "$0")")/appjson"
    JSON_FILES=("$APPJSON_DIR"/*.json)

    command -v jq >/dev/null || {
        echo "❌ jq is not installed. Install it with: sudo apt install jq"
        exit 1
    }

    if [ "${#JSON_FILES[@]}" -eq 0 ] || [ "${JSON_FILES[0]}" = "$APPJSON_DIR/*.json" ]; then
        echo "❌ No JSON files found in $APPJSON_DIR. Stopping."
        exit 1
    fi
}

select_json_file() {
    if [ "${#JSON_FILES[@]}" -eq 1 ]; then
        echo "ℹ️  Only one JSON file found: ${JSON_FILES[0]}"
        CONFIG_FILE="${JSON_FILES[0]}"
    else
        echo "🔽 Multiple JSON files found:"
        PS3="Select a JSON file (number) or Ctrl+C to quit: "
        select choice in "${JSON_FILES[@]}"; do
            if [[ -n "$choice" ]]; then
                CONFIG_FILE="$choice"
                echo "✅ Selected file: $CONFIG_FILE"
                break
            else
                echo "❌ Invalid choice, try again."
            fi
        done
    fi
}

load_config() {
    APP_NAME=$(jq -r '.APP_NAME' "$CONFIG_FILE")
    INSTALL_DIR=$(jq -r '.INSTALL_DIR' "$CONFIG_FILE")
    APPIMAGE_NAME=$(jq -r '.APPIMAGE_NAME' "$CONFIG_FILE")
    DESKTOP_FILE=$(jq -r '.DESKTOP_FILE' "$CONFIG_FILE")
    ICON_PATH=$(jq -r '.ICON_PATH' "$CONFIG_FILE")
    API_URL=$(jq -r '.API_URL' "$CONFIG_FILE")
    UPDATER_SCRIPT=$(jq -r '.UPDATER_SCRIPT' "$CONFIG_FILE")
    FOCUS_CMD_PATTERN=$(jq -r '.FOCUS_CMD_PATTERN' "$CONFIG_FILE")
    DOWNLOAD_METHOD=$(jq -r '.DOWNLOAD_METHOD' "$CONFIG_FILE")
    DOWNLOAD_URL_KEY=$(jq -r '.DOWNLOAD_URL_KEY' "$CONFIG_FILE")
    ICON_SVG=$(jq -r '.ICON_SVG' "$CONFIG_FILE")
    UPDATER_ICON_SVG=$(jq -r '.UPDATER_ICON_SVG // empty' "$CONFIG_FILE")
    UPDATER_DESKTOP_FILE=$(jq -r '.UPDATER_DESKTOP_FILE // empty' "$CONFIG_FILE")
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "🔐 This script must be run as root. Restarting with sudo."
    exec sudo "$0" "$@"
  fi
}

check_curl() {
  if ! command -v curl >/dev/null; then
    echo "❌ curl is not installed. Installing..."
    
    if [[ $EUID -ne 0 ]]; then
      echo "🔐 Administrator rights required to install curl."
      exec sudo "$0" "$@"
    fi

    apt update && apt install -y curl || {
      echo "❌ Failed to install curl."
      exit 1
    }
  fi
}

write_icon() {
    if [[ -n "$ICON_SVG" ]]; then
        if [[ ! -f "$ICON_PATH" ]] || ! cmp -s <(echo "$ICON_SVG") "$ICON_PATH"; then
            mkdir -p "$(dirname "$ICON_PATH")"
            echo "$ICON_SVG" > "$ICON_PATH"
        else
            echo "✅ App icon is already up to date."
        fi
    fi

    if [[ -n "$UPDATER_ICON_SVG" ]]; then
        UPDATER_ICON_PATH="$INSTALL_DIR/updater_icon.svg"
        if [[ ! -f "$UPDATER_ICON_PATH" ]] || ! cmp -s <(echo "$UPDATER_ICON_SVG") "$UPDATER_ICON_PATH"; then
            mkdir -p "$INSTALL_DIR"
            echo "$UPDATER_ICON_SVG" > "$UPDATER_ICON_PATH"
        else
            echo "✅ Updater icon is already up to date."
        fi
    fi
}

get_appimage_url() {
  echo "🔍 Searching for AppImage URL..."
  case "$DOWNLOAD_METHOD" in
    json)
      if [[ -z "$DOWNLOAD_URL_KEY" ]]; then
        echo "❌ Empty DOWNLOAD_URL_KEY for json method."
        exit 1
      fi
      DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".${DOWNLOAD_URL_KEY}")
      ;;
    redirect)
      DOWNLOAD_URL=$(curl -sI "$API_URL" | grep -i '^Location:' | awk '{print $2}' | tr -d '\r')
      ;;
    *)
      echo "❌ Unknown download method: $DOWNLOAD_METHOD"
      exit 1
      ;;
  esac

  if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
    echo "❌ Unable to retrieve download URL."
    exit 1
  fi
}

hash_file() {
  sha256sum "$1" | awk '{print $1}'
}

hash_remote() {
  TMP=$(mktemp)
  curl -sL "$DOWNLOAD_URL" -o "$TMP"
  HASH=$(sha256sum "$TMP" | awk '{print $1}')
  rm "$TMP"
  echo "$HASH"
}

install_appimage() {
  if [[ $EUID -ne 0 ]]; then
    echo "🔐 Administrator rights required to install $APP_NAME."
    exec sudo "$0" "$@"
  fi

  echo "⚙️ Downloading new version..."
  mkdir -p "$INSTALL_DIR"
  TMPFILE=$(mktemp --suffix=".AppImage")
  curl -L "$DOWNLOAD_URL" -o "$TMPFILE" || {
    echo "❌ Download failed"
    rm -f "$TMPFILE"
    return 1
  }
  chmod 755 "$TMPFILE"
  [[ -f "$INSTALL_DIR/$APPIMAGE_NAME" ]] && mv "$INSTALL_DIR/$APPIMAGE_NAME" "$INSTALL_DIR/$APPIMAGE_NAME.old"
  mv "$TMPFILE" "$INSTALL_DIR/$APPIMAGE_NAME"
}

create_desktop_files() {
    echo "🖥️ Creating application launcher"
    cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=$APP_NAME
Exec=$INSTALL_DIR/$APPIMAGE_NAME
Icon=$ICON_PATH
Type=Application
Categories=Development;IDE;
Terminal=false
EOF
    chmod 644 "$DESKTOP_FILE"

    echo "🖥️ Creating updater launcher"
    UPDATER_ICON_PATH="$INSTALL_DIR/updater_icon.svg"
    cat <<EOF > "$UPDATER_DESKTOP_FILE"
[Desktop Entry]
Name=$APP_NAME Updater
Exec=$UPDATER_SCRIPT
Icon=$UPDATER_ICON_PATH
Type=Application
Categories=Utility;
Terminal=true
EOF
    chmod 644 "$UPDATER_DESKTOP_FILE"
}

copy_self_to_updater() {
    cp "$0" "$UPDATER_SCRIPT"
    chmod +x "$UPDATER_SCRIPT"

    UPDATER_DIR="$(dirname "$UPDATER_SCRIPT")"
    UPDATER_APPJSON_DIR="$UPDATER_DIR/appjson"
    mkdir -p "$UPDATER_APPJSON_DIR"
    cp "$CONFIG_FILE" "$UPDATER_APPJSON_DIR/"

    sed -i 's/^UPDATER_MODE=0$/UPDATER_MODE=1/' "$UPDATER_SCRIPT"
}

is_running() {
  pgrep -f "$FOCUS_CMD_PATTERN" >/dev/null
}


launch_app() {
  USER_TO_RUN="${SUDO_USER:-$(logname 2>/dev/null || echo $USER)}"

  if [[ $EUID -ne 0 ]]; then
    sudo -u "$USER_TO_RUN" bash -c 'env DISPLAY='"$DISPLAY"' XAUTHORITY='"$XAUTHORITY"' "'"$INSTALL_DIR/$APPIMAGE_NAME"'" --no-sandbox '"$@"' >/dev/null 2>&1 & disown'
  else
    env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY "$INSTALL_DIR/$APPIMAGE_NAME" --no-sandbox "$@" >/dev/null 2>&1 & disown
  fi
}

main() {
    check_root "$@"
    load_json_file
    select_json_file
    load_config
    check_curl
    write_icon
    copy_self_to_updater
    get_appimage_url
    install_appimage
    create_desktop_files
    echo "🎉 $APP_NAME installed. Launch it from the menu or via $DESKTOP_FILE"
}

updater_main() {
  if ! load_json_file; then
    echo "❌ Failed load_json_file"
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  fi

  if ! select_json_file; then
    echo "❌ Failed select_json_file"
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  fi

  if ! load_config; then
    echo "❌ Failed load_config"
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  fi

  if is_running; then
    echo "🪟 $APP_NAME is running"
    exit 0
  fi

  if ! check_curl; then
    echo "❌ curl missing and installation failed"
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  fi

  if ! write_icon; then
    echo "⚠️ Failed write_icon (can be ignored)"
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  fi

  if ! get_appimage_url; then
    echo "❌ Unable to get AppImage URL"
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  fi

  remote_hash=$(hash_remote)
  if [[ -z "$remote_hash" ]]; then
    echo "❌ hash_remote empty or error"
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  fi

  local_hash=""
  if [[ -f "$INSTALL_DIR/$APPIMAGE_NAME" ]]; then
    local_hash=$(hash_file "$INSTALL_DIR/$APPIMAGE_NAME")
  fi

  if [[ "$local_hash" != "$remote_hash" ]]; then
    echo "🔄 Update required"
    if ! install_appimage; then
      echo "❌ Failed to install AppImage"
      read -n 1 -s -r -p "Press any key to exit..."
      exit 1
    fi
  fi
  
  if ! launch_app "$@"; then
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  else
    echo "🚀 Launch successful"
  fi
}

if [[ "$UPDATER_MODE" == "1" ]]; then
    updater_main "$@"
else
    main "$@"
fi
