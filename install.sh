#!/usr/bin/env bash
# ezCMD automated installer for Linux and macOS
# Works across Bash, Zsh, and Fish terminals.

set -e

REPO="ItzEvhyx/ezcmd"
INSTALL_DIR="${HOME}/.local/bin"
BIN_NAME="ezcmd"
TARGET_PATH="${INSTALL_DIR}/${BIN_NAME}"

echo "Installing ezCMD..."
mkdir -p "${INSTALL_DIR}"

# If running from within the repository and release binary exists, install directly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
if [ -f "${SCRIPT_DIR}/target/release/ezcmd" ]; then
    rm -f "${TARGET_PATH}"
    cp "${SCRIPT_DIR}/target/release/ezcmd" "${TARGET_PATH}"
    chmod +x "${TARGET_PATH}"
elif [ -f "${SCRIPT_DIR}/ezcmd" ]; then
    rm -f "${TARGET_PATH}"
    cp "${SCRIPT_DIR}/ezcmd" "${TARGET_PATH}"
    chmod +x "${TARGET_PATH}"

else
    # Detect OS & Arch for prebuilt release download
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "${OS}" in
        Linux*)
            case "${ARCH}" in
                x86_64) ASSET_TARGET="x86_64-unknown-linux-gnu" ;;
                aarch64|arm64) ASSET_TARGET="aarch64-unknown-linux-gnu" ;;
                *) echo "Unsupported Linux architecture: ${ARCH}"; exit 1 ;;
            esac
            ;;
        Darwin*)
            case "${ARCH}" in
                x86_64) ASSET_TARGET="x86_64-apple-darwin" ;;
                arm64|aarch64) ASSET_TARGET="aarch64-apple-darwin" ;;
                *) echo "Unsupported macOS architecture: ${ARCH}"; exit 1 ;;
            esac
            ;;
        *)
            echo "Unsupported OS: ${OS}. Please use install.ps1 on Windows."
            exit 1
            ;;
    esac

    TMP_DIR="$(mktemp -d)"
    TAR_URL="https://github.com/${REPO}/releases/latest/download/ezcmd-${ASSET_TARGET}.tar.gz"

    echo "Downloading ${TAR_URL}..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${TAR_URL}" -o "${TMP_DIR}/ezcmd.tar.gz"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${TMP_DIR}/ezcmd.tar.gz" "${TAR_URL}"
    else
        echo "Error: curl or wget is required to download ezcmd."
        exit 1
    fi

    tar -xzf "${TMP_DIR}/ezcmd.tar.gz" -C "${TMP_DIR}"
    mv "${TMP_DIR}/ezcmd" "${TARGET_PATH}"
    chmod +x "${TARGET_PATH}"
    rm -rf "${TMP_DIR}"
fi

echo ""
echo "✓ ezcmd was successfully installed to ${TARGET_PATH}!"
echo ""

# Check if ~/.local/bin is in PATH
case ":${PATH}:" in
    *:"${INSTALL_DIR}":*) ;;
    *)
        echo "NOTE: ${INSTALL_DIR} is not currently in your PATH."
        echo "Add it with:"
        echo "  • Fish:        set -Ua fish_user_paths ~/.local/bin"
        echo "  • Bash:        echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
        echo "  • Zsh:         echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
        echo ""
        ;;
esac

# Trigger welcome banner
"${TARGET_PATH}" --welcome
