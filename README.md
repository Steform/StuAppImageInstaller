# StuAppImage Installer

A robust shell script for installing and managing AppImage applications on Linux systems. This script provides a user-friendly way to install, update, and manage AppImage applications with desktop integration.

## Features

- 🚀 Easy installation of AppImage applications
- 🔄 Automatic updates with version checking
- 🖥️ Desktop integration (launcher and icons)
- 📦 Dependency management
- 🔐 Secure installation with proper permissions
- 🎨 Custom icon support
- 📝 JSON configuration based

## Prerequisites

- Linux operating system
- `jq` for JSON parsing
- `curl` for downloading

## Installation

1. Clone this repository:
```bash
git clone https://github.com/yourusername/appimage-installer.git
cd appimage-installer
```

2. Make the script executable:
```bash
chmod +x appImageInstaller.sh
```

## Configuration

Create a JSON configuration file in the `appjson` directory. Example structure:

```json
{
    "APP_NAME": "YourApp",
    "INSTALL_DIR": "/opt/yourapp",
    "APPIMAGE_NAME": "yourapp.AppImage",
    "DESKTOP_FILE": "/usr/share/applications/yourapp.desktop",
    "ICON_PATH": "/usr/share/icons/hicolor/scalable/apps/yourapp.svg",
    "API_URL": "https://api.example.com/latest",
    "UPDATER_SCRIPT": "/opt/yourapp/updater.sh",
    "CMD_PATTERN": "yourapp",
    "DOWNLOAD_METHOD": "json",
    "DOWNLOAD_URL_KEY": "download_url",
    "ICON_SVG": "<svg>...</svg>",
    "UPDATER_ICON_SVG": "<svg>...</svg>",
    "UPDATER_DESKTOP_FILE": "/usr/share/applications/yourapp-updater.desktop"
}
```

### Configuration Parameters

| Parameter | Description |
|-----------|-------------|
| APP_NAME | Name of the application |
| INSTALL_DIR | Installation directory |
| APPIMAGE_NAME | Name of the AppImage file |
| DESKTOP_FILE | Path to desktop launcher |
| ICON_PATH | Path to application icon |
| API_URL | URL for version checking |
| UPDATER_SCRIPT | Path to updater script |
| CMD_PATTERN | Pattern to identify running app |
| DOWNLOAD_METHOD | Method to get download URL (json/redirect) |
| DOWNLOAD_URL_KEY | JSON key for download URL |
| ICON_SVG | SVG content for app icon |
| UPDATER_ICON_SVG | SVG content for updater icon |
| UPDATER_DESKTOP_FILE | Path to updater desktop file |

## Usage

### Installation

Run the script with sudo:

```bash
sudo ./appImageInstaller.sh
```

### Updating

The script creates an updater that can be launched from the applications menu or directly:

```bash
/opt/yourapp/updater.sh
```

## Features in Detail

### Installation Process
1. Checks for required dependencies
2. Downloads the latest AppImage
3. Creates desktop integration for app and updater
4. Sets up the updater

### Update Process
1. Checks if the application is running
2. Verifies for new versions
3. Downloads and installs updates
4. Maintains desktop integration

## Security

- Requires root privileges for installation
- Verifies file integrity
- Uses secure download methods
- Proper permission management

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the GNU General Public License v3.0 - see the file for details.

## Acknowledgments

- AppImage project for the application format
- Linux community for desktop integration standards 