#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
exec "$SCRIPT_DIR/../MacOS/Pearcleaner" ask-password --message "Enter your password to upgrade Homebrew packages"