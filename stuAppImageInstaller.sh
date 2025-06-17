#!/bin/bash
# StuAppImageInstaller - A script for installing and managing AppImage applications
# This script handles the installation, updating, and management of AppImage applications
# with support for automatic updates and desktop integration.
#
# Features:
# - JSON-based configuration
# - Automatic update checking
# - Desktop integration
# - Icon management
# - Multiple download methods support
#
# Author: Original author
# License: See LICENSE file

UPDATER_MODE=0

# Function: load_json_file
# Purpose: Loads and validates JSON configuration files from the appjson directory
# Input: None
# Output: Sets JSON_FILES array with valid JSON files
# Returns: 0 on success, 1 on failure
load_json_file() {
    # Get the absolute path of the appjson directory relative to the script location
    APPJSON_DIR="$(dirname "$(realpath "$0")")/appjson"
    # Store all JSON files from the appjson directory in an array
    JSON_FILES=("$APPJSON_DIR"/*.json)

    # Check if jq (JSON processor) is installed
    # Exit with error if not found
    command -v jq >/dev/null || {
        echo "❌ jq is not installed. Install it with: sudo apt install jq"
        exit 1
    }

    # Verify that JSON files exist in the directory
    # Check if array is empty or if the glob pattern wasn't expanded (meaning no files found)
    if [ "${#JSON_FILES[@]}" -eq 0 ] || [ "${JSON_FILES[0]}" = "$APPJSON_DIR/*.json" ]; then
        echo "❌ No JSON files found in $APPJSON_DIR. Stopping."
        exit 1
    fi
}

# Function: select_json_file
# Purpose: Allows user to select a JSON configuration file if multiple exist, or uses the only one if single file
# Input: None
# Output: Sets CONFIG_FILE variable with the selected file path
# Returns: None
select_json_file() {
    # If only one JSON file exists, use it automatically
    if [ "${#JSON_FILES[@]}" -eq 1 ]; then
        echo "ℹ️  Only one JSON file found: ${JSON_FILES[0]}"
        CONFIG_FILE="${JSON_FILES[0]}"
    else
        # If multiple files exist, display a selection menu
        echo "🔽 Multiple JSON files found:"
        # Set the prompt for the select menu
        PS3="Select a JSON file (number) or Ctrl+C to quit: "
        # Display interactive menu with all JSON files
        select choice in "${JSON_FILES[@]}"; do
            # Check if a valid choice was made
            if [[ -n "$choice" ]]; then
                CONFIG_FILE="$choice"
                echo "✅ Selected file: $CONFIG_FILE"
                break
            else
                # Handle invalid selection
                echo "❌ Invalid choice, try again."
            fi
        done
    fi
}

# Function: load_config
# Purpose: Loads and parses configuration values from the selected JSON file
# Input: None
# Output: Sets multiple configuration variables (APP_NAME, INSTALL_DIR, APPIMAGE_NAME, etc.)
# Returns: None
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

# Function: check_root
# Purpose: Verifies if the script is running with root privileges
# Input: Command line arguments
# Output: None
# Returns: Restarts script with sudo if not running as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "🔐 This script must be run as root. Restarting with sudo."
    exec sudo "$0" "$@"
  fi
}

# Function: check_curl
# Purpose: Verifies if curl is installed and installs it if missing
# Input: Command line arguments
# Output: None
# Returns: 0 on success, 1 on failure
check_curl() {
    # Check if curl is installed by trying to run it
    if ! command -v curl >/dev/null; then
        echo "❌ curl is not installed. Installing..."
        
        # Check if we have root privileges for installation
        if [[ $EUID -ne 0 ]]; then
            echo "🔐 Administrator rights required to install curl."
            # Restart script with sudo to get root privileges
            exec sudo "$0" "$@"
        fi

        # Update package list and install curl
        apt update && apt install -y curl || {
            echo "❌ Failed to install curl."
            exit 1
        }
    fi
}

# Function: write_icon
# Purpose: Creates or updates application and updater icons from SVG content
# Input: None
# Output: Creates or updates icon files in their respective locations
# Returns: None
write_icon() {
    # Process main application icon if SVG content is provided
    if [[ -n "$ICON_SVG" ]]; then
        # Check if icon needs to be created or updated
        if [[ ! -f "$ICON_PATH" ]] || ! cmp -s <(echo "$ICON_SVG") "$ICON_PATH"; then
            # Create directory structure if it doesn't exist
            mkdir -p "$(dirname "$ICON_PATH")"
            # Write SVG content to icon file
            echo "$ICON_SVG" > "$ICON_PATH"
        else
            echo "✅ App icon is already up to date."
        fi
    fi

    # Process updater icon if SVG content is provided
    if [[ -n "$UPDATER_ICON_SVG" ]]; then
        # Define updater icon path
        UPDATER_ICON_PATH="$INSTALL_DIR/updater_icon.svg"
        # Check if updater icon needs to be created or updated
        if [[ ! -f "$UPDATER_ICON_PATH" ]] || ! cmp -s <(echo "$UPDATER_ICON_SVG") "$UPDATER_ICON_PATH"; then
            # Create directory structure if it doesn't exist
            mkdir -p "$INSTALL_DIR"
            # Write SVG content to updater icon file
            echo "$UPDATER_ICON_SVG" > "$UPDATER_ICON_PATH"
        else
            echo "✅ Updater icon is already up to date."
        fi
    fi
}

# Function: get_appimage_url
# Purpose: Retrieves the download URL for the AppImage based on the configured download method
# Input: None
# Output: Sets DOWNLOAD_URL variable with the URL to download
# Returns: 0 on success, 1 on failure
get_appimage_url() {
    echo "🔍 Searching for AppImage URL..."
    # Process URL based on configured download method
    case "$DOWNLOAD_METHOD" in
        json)
            # For JSON method, verify DOWNLOAD_URL_KEY is set
            if [[ -z "$DOWNLOAD_URL_KEY" ]]; then
                echo "❌ Empty DOWNLOAD_URL_KEY for json method."
                exit 1
            fi
            # Extract download URL from JSON response using jq
            DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".${DOWNLOAD_URL_KEY}")
            ;;
        redirect)
            # For redirect method, follow HTTP redirect to get final URL
            DOWNLOAD_URL=$(curl -sI "$API_URL" | grep -i '^Location:' | awk '{print $2}' | tr -d '\r')
            ;;
        *)
            # Handle unknown download methods
            echo "❌ Unknown download method: $DOWNLOAD_METHOD"
            exit 1
            ;;
    esac

    # Verify that a valid URL was obtained
    if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
        echo "❌ Unable to retrieve download URL."
        exit 1
    fi
}

# Function: hash_file
# Purpose: Calculates SHA256 hash of a local file
# Input: File path as first argument
# Output: SHA256 hash string
# Returns: None
hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

# Function: hash_remote
# Purpose: Calculates SHA256 hash of remote file by downloading it temporarily
# Input: None
# Output: SHA256 hash string
# Returns: None
# Note: This function requires a temporary download of the file since there's no direct way
# to get the hash without downloading the content. This is a limitation when the server
# doesn't provide hash information directly.
hash_remote() {
    # Create a temporary file to store the download
    TMP=$(mktemp)
    # Download the file silently (-s) and follow redirects (-L)
    curl -sL "$DOWNLOAD_URL" -o "$TMP"
    # Calculate SHA256 hash of the downloaded file
    HASH=$(sha256sum "$TMP" | awk '{print $1}')
    # Clean up: remove the temporary file
    rm "$TMP"
    # Return the calculated hash
    echo "$HASH"
}

# Function: install_appimage
# Purpose: Downloads and installs the AppImage file to the configured directory
# Input: Command line arguments
# Output: Installs AppImage and creates backup of old version if exists
# Returns: 0 on success, 1 on failure
install_appimage() {
    # Check for root privileges
    if [[ $EUID -ne 0 ]]; then
        echo "🔐 Administrator rights required to install $APP_NAME."
        exec sudo "$0" "$@"
    fi

    echo "⚙️ Downloading new version..."
    # Create installation directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    # Create temporary file for download
    TMPFILE=$(mktemp --suffix=".AppImage")
    # Download the AppImage file
    curl -L "$DOWNLOAD_URL" -o "$TMPFILE" || {
        echo "❌ Download failed"
        rm -f "$TMPFILE"
        return 1
    }
    # Make the AppImage executable
    chmod 755 "$TMPFILE"
    # Backup existing AppImage if it exists
    [[ -f "$INSTALL_DIR/$APPIMAGE_NAME" ]] && mv "$INSTALL_DIR/$APPIMAGE_NAME" "$INSTALL_DIR/$APPIMAGE_NAME.old"
    # Move the new AppImage to its final location
    mv "$TMPFILE" "$INSTALL_DIR/$APPIMAGE_NAME"
}

# Function: create_desktop_files
# Purpose: Creates desktop entry files for both the main application and its updater
# Input: None
# Output: Creates .desktop files in appropriate locations with proper permissions
# Returns: None
create_desktop_files() {
    # Create main application desktop entry
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
    # Set appropriate permissions for the desktop file
    chmod 644 "$DESKTOP_FILE"

    # Create updater desktop entry
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
    # Set appropriate permissions for the updater desktop file
    chmod 644 "$UPDATER_DESKTOP_FILE"
}

# Function: copy_self_to_updater
# Purpose: Creates a copy of the current script as the updater script
# Input: None
# Output: Creates updater script and copies necessary configuration files
# Returns: None
copy_self_to_updater() {
    # Copy the current script to the updater location
    cp "$0" "$UPDATER_SCRIPT"
    # Make the updater script executable
    chmod +x "$UPDATER_SCRIPT"

    # Create updater's appjson directory
    UPDATER_DIR="$(dirname "$UPDATER_SCRIPT")"
    UPDATER_APPJSON_DIR="$UPDATER_DIR/appjson"
    mkdir -p "$UPDATER_APPJSON_DIR"
    # Copy the configuration file to updater's appjson directory
    cp "$CONFIG_FILE" "$UPDATER_APPJSON_DIR/"

    # Modify the updater script to run in updater mode
    sed -i 's/^UPDATER_MODE=0$/UPDATER_MODE=1/' "$UPDATER_SCRIPT"
}

# Function: is_running
# Purpose: Checks if the application is currently running
# Input: None
# Output: None
# Returns: 0 if application is running, 1 if not running
is_running() {
    # Use pgrep to search for processes matching the focus command pattern
    pgrep -f "$FOCUS_CMD_PATTERN" >/dev/null
}

# Function: launch_app
# Purpose: Launches the application with appropriate user permissions
# Input: Command line arguments to pass to the application
# Output: None
# Returns: None
launch_app() {
    # Determine the user who should run the application
    # Use SUDO_USER if available, otherwise try logname, fallback to $USER
    USER_TO_RUN="${SUDO_USER:-$(logname 2>/dev/null || echo $USER)}"

    # Launch the application with appropriate permissions
    if [[ $EUID -ne 0 ]]; then
        # If not root, use sudo to run as the correct user
        sudo -u "$USER_TO_RUN" bash -c 'env DISPLAY='"$DISPLAY"' XAUTHORITY='"$XAUTHORITY"' "'"$INSTALL_DIR/$APPIMAGE_NAME"'" --no-sandbox '"$@"' >/dev/null 2>&1 & disown'
    else
        # If already root, run directly with environment variables
        env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY "$INSTALL_DIR/$APPIMAGE_NAME" --no-sandbox "$@" >/dev/null 2>&1 & disown
    fi
}

# Function: main
# Purpose: Main installation function that orchestrates the entire installation process
# Input: Command line arguments
# Output: None
# Returns: None
main() {
    # Check for root privileges
    check_root "$@"
    # Load and validate JSON configuration files
    load_json_file
    # Let user select configuration file if multiple exist
    select_json_file
    # Load configuration values from selected file
    load_config
    # Ensure curl is installed
    check_curl
    # Create or update application icons
    write_icon
    # Create updater script
    copy_self_to_updater
    # Get download URL for AppImage
    get_appimage_url
    # Download and install AppImage
    install_appimage
    # Create desktop entry files
    create_desktop_files
    # Display success message
    echo "🎉 $APP_NAME installed. Launch it from the menu or via $DESKTOP_FILE"
}

# Function: updater_main
# Purpose: Main update function that handles the application update process
# Input: None
# Output: None
# Returns: 0 on success, 1 on failure
updater_main() {
    # Load and validate JSON configuration files
    if ! load_json_file; then
        echo "❌ Failed load_json_file"
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    fi

    # Let user select configuration file if multiple exist
    if ! select_json_file; then
        echo "❌ Failed select_json_file"
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    fi

    # Load configuration values from selected file
    if ! load_config; then
        echo "❌ Failed load_config"
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    fi

    # Check if application is currently running
    if is_running; then
        echo "🪟 $APP_NAME is running"
        exit 0
    fi

    # Ensure curl is installed for download operations
    if ! check_curl; then
        echo "❌ curl missing and installation failed"
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    fi

    # Create or update application icons (non-critical operation)
    if ! write_icon; then
        echo "⚠️ Failed write_icon (can be ignored)"
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    fi

    # Get download URL for the new version
    if ! get_appimage_url; then
        echo "❌ Unable to get AppImage URL"
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    fi

    # Calculate hash of remote file
    remote_hash=$(hash_remote)
    if [[ -z "$remote_hash" ]]; then
        echo "❌ hash_remote empty or error"
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    fi

    # Calculate hash of local file if it exists
    local_hash=""
    if [[ -f "$INSTALL_DIR/$APPIMAGE_NAME" ]]; then
        local_hash=$(hash_file "$INSTALL_DIR/$APPIMAGE_NAME")
    fi

    # Compare hashes to determine if update is needed
    if [[ "$local_hash" != "$remote_hash" ]]; then
        echo "🔄 Update required"
        # Install new version if hashes differ
        if ! install_appimage; then
            echo "❌ Failed to install AppImage"
            read -n 1 -s -r -p "Press any key to exit..."
            exit 1
        fi
    fi
    
    # Launch the application with provided arguments
    if ! launch_app "$@"; then
        read -n 1 -s -r -p "Press any key to exit..."
        exit 1
    else
        echo "🚀 Launch successful"
    fi
}

# Main script execution
# Determine whether to run in normal installation mode or updater mode
if [[ "$UPDATER_MODE" -eq 1 ]]; then
    # Run in updater mode if UPDATER_MODE is set to 1
    updater_main "$@"
else
    # Run in normal installation mode
    main "$@"
fi
