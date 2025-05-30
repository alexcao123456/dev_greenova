#!/bin/bash

set -e
set -euo pipefail
echo "=== Running post_start.sh ==="
echo "Starting post_start process..."



#Function to clone the project
clone(){
  VENV_PATH="/workspaces/greenova/.venv"
  VOLUME_PATH="/workspaces/greenova"
  REPO_URL="https://github.com/alexcao123456/dev_greenova.git"

  # if the volume is empty, clone from github
  if [ ! -d "$VOLUME_PATH/.git" ]; then
    echo "[build.sh] No .git detected. Cloning from $REPO_URL ..."
    cd "$VOLUME_PATH"
    git init
    git remote add origin "$REPO_URL"
    git clean -fd
    git fetch origin --verbose
    # Check available branches
    echo "Available remote branches:"
    git branch -r
    # Attempt to checkout debug branch
    git checkout -b main origin/debug || {
      echo "Failed to checkout origin/debug. Available branches are listed above." >&2
      return 1
    }
    #git pull origin main
  else
    echo "[build.sh] .git folder found. Skipping clone."
  fi
}

# Function to setup pyenv environment
setup_pyenv(){
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  export PYTHON_CONFIGURE_OPTS="--enable-shared"

  if [ ! -d "$PYENV_ROOT" ]; then
    echo "[pyenv] Installing pyenv..."
    git clone https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
  fi

  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"

  # install Python
  PYTHON_VERSION="3.9.21"
  if ! pyenv versions | grep -q "$PYTHON_VERSION"; then
    echo "[pyenv] Installing Python $PYTHON_VERSION..."
    pyenv install "$PYTHON_VERSION"
  fi

  pyenv global "$PYTHON_VERSION"
  export PATH="$PYENV_ROOT/versions/$PYTHON_VERSION/bin:$PATH"
  echo "[pyenv] Python set to: $(python --version)"
}

# Function to setup NVM environment
setup_nvm() {
  # First, update NVM to latest version
  echo "Updating NVM to latest version..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash

  # Force reload NVM
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

  # Setup NVM environment variables
  {
    echo '. /usr/local/share/nvm/nvm.sh'
    echo '. /usr/local/share/nvm/bash_completion'
  } >"${HOME}/.bash_env"

  # Source the environment file
  . "${HOME}/.bash_env"

  # Rest of your existing setup...
  command -v nvm >/dev/null 2>&1 || {
    echo "Error: NVM not found" >&2
    return 1
  }

  # Continue with Node.js installation
  if ! nvm install 18.20.7 -b; then
    echo "Error: Failed to install Node.js 18.20.7" >&2
    return 1
  fi

  command -v nvm >/dev/null 2>&1 || {
    echo "Error: NVM not found" >&2
    return 1
  }

  if ! nvm use 18.20.7; then
    echo "Error: Failed to use Node.js 18.20.7" >&2
    return 1
  fi

  if ! nvm alias default node; then
    echo "Error: Failed to set default Node.js version" >&2
    return 1
  fi
}

# Setup Python virtual environment
setup_venv() {
  VENV_PATH="/workspaces/greenova/.venv"

  # Remove any existing .direnv folder to avoid conflicts
  if [ -d "/workspaces/greenova/.direnv" ]; then
    echo "Removing conflicting .direnv directory..."
    rm -rf "/workspaces/greenova/.direnv"
  fi

  #if the current venv is owned by root, remove it
  #if [ -d "$VENV_PATH" ]; then
  #  owner=$(stat -c "%U" "$VENV_PATH")
  #  if [ "$owner" = "root" ]; then
  #    echo " .venv is owned by root. Deleting to avoid permission issues..."
  #    rm -rf "$VENV_PATH"
  #  fi
  #fi

  # Create virtual environment if it doesn't exist
  if [ ! -d "$VENV_PATH" ]; then
    echo "Creating Python virtual environment..."
    python -m venv "$VENV_PATH"
  fi

  # Activate virtual environment
  #echo "Activating virtual environment..."
  #source "$VENV_PATH/bin/activate"

  # Check if pip is actually usable
  if ! python -m pip --version >/dev/null 2>&1; then
    echo " pip not found or broken, attempting to bootstrap with ensurepip..."
    python -m ensurepip --upgrade
  fi

  # Now upgrade pip properly
  if python -m pip --version >/dev/null 2>&1; then
    echo " Upgrading pip..."
    "$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel
  else
    echo " pip still broken after ensurepip. Aborting setup."
    exit 1
  fi

  # Upgrade pip
  # python -m pip install --upgrade pip

  # Install requirements if present
  if [ -f "/workspaces/greenova/requirements.txt" ]; then
    echo "Installing Python requirements with constraints..."
    if [ -f "/workspaces/greenova/constraints.txt" ]; then
      "$VENV_PATH/bin/pip" install -r "/workspaces/greenova/requirements.txt" -c "/workspaces/greenova/constraints.txt" --no-deps
    else
      echo "Warning: constraints.txt not found, installing without constraints"
      "$VENV_PATH/bin/pip" install -r "/workspaces/greenova/requirements.txt"
    fi

    if command -v pre-commit >/dev/null 2>&1; then
      pre-commit install
    else
      echo "Warning: pre-commit not found, skipping installation"
    fi
  fi

}

# Fix django-hyperscript syntax error
fix_django_hyperscript() {
  echo "Checking for django-hyperscript syntax error..."

  # Create directory for scripts if it doesn't exist
  mkdir -p "/workspaces/greenova/scripts"

  # Create the fix script if it doesn't exist
  if [ ! -f "/workspaces/greenova/scripts/fix_hyperscript.py" ]; then
    cat >"/workspaces/greenova/scripts/fix_hyperscript.py" <<'EOL'
#!/usr/bin/env python3
"""
Fix for django-hyperscript syntax error in templatetags/hyperscript.py.
"""
import os
import sys
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def fix_hyperscript():
    """Fix syntax error in django_hyperscript package."""
    # Get the virtual environment path
    venv_path = os.environ.get('VIRTUAL_ENV', '/workspaces/greenova/.venv')

    # Build the path to the problematic file
    file_path = Path(venv_path) / "lib" / "python3.9" / "site-packages" / "django_hyperscript" / "templatetags" / "hyperscript.py"

    if not file_path.exists():
        logger.info(f"File not found: {file_path}")
        return True

    logger.info(f"Found hyperscript.py at {file_path}")

    # Read the file
    with open(file_path, 'r') as f:
        content = f.readlines()

    # Look for the specific pattern with the error
    fixed = False
    for i, line in enumerate(content):
        if "accepted_kwargs.items(" in line and line.strip().endswith("accepted_kwargs.items("):
            if i+1 < len(content) and ")])}." in content[i+1]:
                # Join the broken lines
                content[i] = line.rstrip() + "])}.\n"
                content.pop(i+1)
                fixed = True
                break

    if fixed:
        # Write the fixed content back
        with open(file_path, 'w') as f:
            f.writelines(content)
        logger.info("Successfully fixed the syntax error in django_hyperscript")
    else:
        logger.info("No syntax error pattern found or it's already fixed")

    return True

if __name__ == "__main__":
    success = fix_hyperscript()
    sys.exit(0 if success else 1)
EOL
    chmod +x "/workspaces/greenova/scripts/fix_hyperscript.py"
  fi

  # Run the fix script with the virtual environment's Python
  echo "Running django-hyperscript fix script..."
  "${VENV_PATH}/bin/python" "/workspaces/greenova/scripts/fix_hyperscript.py"
}

# Fix hyperscript_dump.py type annotation issues
fix_hyperscript_dump() {
  echo "Checking for hyperscript_dump.py type annotation issues..."

  # Create directory for scripts if it doesn't exist
  mkdir -p "/workspaces/greenova/scripts"

  # Create the fix script if it doesn't exist
  if [ ! -f "/workspaces/greenova/scripts/fix_hyperscript_dump.py" ]; then
    cat >"/workspaces/greenova/scripts/fix_hyperscript_dump.py" <<'EOL'
#!/usr/bin/env python3
"""
Fix for hyperscript_dump.py type annotation syntax for Python 3.9 compatibility.
"""
import os
import sys
import logging
import re
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def fix_hyperscript_dump():
    """Fix type annotation syntax in hyperscript_dump.py for Python 3.9."""
    # Get the virtual environment path
    venv_path = os.environ.get('VIRTUAL_ENV', '/workspaces/greenova/.venv')

    # Build the path to the problematic file
    file_path = Path(venv_path) / "lib" / "python3.9" / "site-packages" / "hyperscript_dump.py"

    if not file_path.exists():
        logger.info(f"File not found: {file_path}")
        return True

    logger.info(f"Found hyperscript_dump.py at {file_path}")

    # Read the file
    with open(file_path, 'r') as f:
        content = f.read()

    # Check if the file already imports Union
    imports_union = re.search(r'from\s+typing\s+import\s+.*Union.*', content) is not None

    # Replace the pipe syntax with Union
    pattern = r'event:\s*str\s*\|\s*None\s*='
    replacement = 'event: Union[str, None] ='

    if re.search(pattern, content):
        # Add Union import if needed
        if not imports_union:
            if 'from typing import' in content:
                content = re.sub(
                    r'from\s+typing\s+import\s+(.*)',
                    r'from typing import \1, Union',
                    content
                )
            else:
                content = re.sub(
                    r'import json',
                    r'import json\nfrom typing import Union',
                    content
                )

        # Replace the type annotation
        content = re.sub(pattern, replacement, content)

        # Write the fixed content back
        with open(file_path, 'w') as f:
            f.write(content)
        logger.info("Successfully fixed the type annotation in hyperscript_dump.py")
        return True
    else:
        logger.info("No type annotation issue found or it's already fixed")
        return True

if __name__ == "__main__":
    success = fix_hyperscript_dump()
    sys.exit(0 if success else 1)
EOL
    chmod +x "/workspaces/greenova/scripts/fix_hyperscript_dump.py"
  fi

  # Run the fix script with the virtual environment's Python
  echo "Running hyperscript_dump fix script..."
  "${VENV_PATH}/bin/python" "/workspaces/greenova/scripts/fix_hyperscript_dump.py"
}

# Setup Fish shell with direnv
setup_fish_direnv() {
  FISH_CONFIG="${HOME}/.config/fish/config.fish"

  # Ensure fish config directory exists
  mkdir -p "$(dirname "$FISH_CONFIG")"

  # Check if direnv hook already exists in config
  if ! grep -q "direnv hook fish" "$FISH_CONFIG" 2>/dev/null; then
    echo "Configuring direnv hook for Fish shell..."
    {
      echo ""
      echo "# Set up direnv"
      echo "if type -q direnv"
      echo "    direnv hook fish | source"
      echo "end"

      echo "# Python virtual environment indicator for Fish"
      echo "function show_virtual_env --description 'Show virtual env name'"
      echo "    if set -q VIRTUAL_ENV"
      echo "        echo -n '('(basename \$VIRTUAL_ENV)') '"
      echo "    end"
      echo "end"

      echo "# Setup Fish prompt to show virtual env"
      echo "if not set -q __fish_prompt_orig"
      echo "    functions -c fish_prompt __fish_prompt_orig"
      echo "    functions -e fish_prompt"
      echo "end"

      echo "function fish_prompt"
      echo "    show_virtual_env"
      echo "    __fish_prompt_orig"
      echo "end"

      echo "# Activate Python virtual environment on startup"
      echo "if test -d /workspaces/greenova/.venv"
      echo "    if not set -q VIRTUAL_ENV"
      echo "        cd /workspaces/greenova"
      echo "    end"
      echo "end"

      echo "# NVM and Node.js setup for fish"
      echo "set -gx NVM_DIR /usr/local/share/nvm"
      echo "if test -d \$NVM_DIR"
      echo "    # Add Node.js binary path to fish PATH"
      echo "    set -gx PATH \$HOME/.nvm/versions/node/v18.20.7/bin \$PATH"
      echo "    # For accessing node and npm globally from default NVM version"
      echo "    set -gx PATH /usr/local/share/nvm/versions/node/v18.20.7/bin \$PATH"
      echo "end"

      echo "# Function to use NVM in fish"
      echo "function nvm"
      echo "    bass source /usr/local/share/nvm/nvm.sh --no-use ';' nvm \$argv"
      echo "end"

      echo "# Ensure npm is accessible as a command"
      echo "if not type -q npm"
      echo "    alias npm='/usr/local/share/nvm/versions/node/v18.20.7/bin/npm'"
      echo "end"

      echo "# Ensure node is accessible as a command"
      echo "if not type -q node"
      echo "    alias node='/usr/local/share/nvm/versions/node/v18.20.7/bin/node'"
      echo "end"
    } >>"$FISH_CONFIG"
    echo "Fish shell configured with direnv hook, virtual env support, and Node.js/npm"

    # If bass (Bash script adapter for fish) is not installed, install it
    fish -c 'if not type -q bass; and type -q fisher; fisher install edc/bass; end' || true
  else
    echo "Fish shell already configured with direnv hook"
    # Still ensure NVM paths are added if not already present
    if ! grep -q "NVM_DIR" "$FISH_CONFIG" 2>/dev/null; then
      echo "Adding NVM configuration to fish shell..."
      {
        echo ""
        echo "# NVM and Node.js setup for fish"
        echo "set -gx NVM_DIR /usr/local/share/nvm"
        echo "if test -d \$NVM_DIR"
        echo "    # Add Node.js binary path to fish PATH"
        echo "    set -gx PATH \$HOME/.nvm/versions/node/v18.20.7/bin \$PATH"
        echo "    # For accessing node and npm globally from default NVM version"
        echo "    set -gx PATH /usr/local/share/nvm/versions/node/v18.20.7/bin \$PATH"
        echo "end"

        echo "# Function to use NVM in fish"
        echo "function nvm"
        echo "    bass source /usr/local/share/nvm/nvm.sh --no-use ';' nvm \$argv"
        echo "end"

        echo "# Ensure npm is accessible as a command"
        echo "if not type -q npm"
        echo "    alias npm='/usr/local/share/nvm/versions/node/v18.20.7/bin/npm'"
        echo "end"

        echo "# Ensure node is accessible as a command"
        echo "if not type -q node"
        echo "    alias node='/usr/local/share/nvm/versions/node/v18.20.7/bin/node'"
        echo "end"
      } >>"$FISH_CONFIG"
      echo "Added Node.js and npm configuration to fish shell"
    fi
  fi

  # Ensure .envrc has proper permissions
  if [ -f "/workspaces/greenova/.envrc" ]; then
    chmod +x "/workspaces/greenova/.envrc"
    echo "Set execute permissions on .envrc file"

    # Force direnv to reload with the new .envrc
    cd /workspaces/greenova
    direnv allow
  fi
}

# debug in setup fish
setup_fish_direnv_debug() {
  FISH_CONFIG="${HOME}/.config/fish/config.fish"

  # Ensure fish config directory exists
  echo "Creating Fish config directory..."
  mkdir -p "$(dirname "$FISH_CONFIG")" || {
    echo "Failed to create Fish config directory" >&2
    return 1
  }

  # Check if direnv hook already exists in config
  echo "Checking if direnv hook exists in Fish config..."
  if ! grep -q "direnv hook fish" "$FISH_CONFIG" 2>/dev/null; then
    echo "Configuring direnv hook for Fish shell..."
    {
      echo ""
      echo "# Set up direnv"
      echo "if type -q direnv"
      echo "    direnv hook fish | source"
      echo "end"

      echo "# Python virtual environment indicator for Fish"
      echo "function show_virtual_env --description 'Show virtual env name'"
      echo "    if set -q VIRTUAL_ENV"
      echo "        echo -n '('(basename \$VIRTUAL_ENV)') '"
      echo "    end"
      echo "end"

      echo "# Setup Fish prompt to show virtual env"
      echo "if not set -q __fish_prompt_orig"
      echo "    functions -c fish_prompt __fish_prompt_orig"
      echo "    functions -e fish_prompt"
      echo "end"

      echo "function fish_prompt"
      echo "    show_virtual_env"
      echo "    __fish_prompt_orig"
      echo "end"

      echo "# Activate Python virtual environment on startup"
      echo "if test -d /workspaces/greenova/.venv"
      echo "    if not set -q VIRTUAL_ENV"
      echo "        cd /workspaces/greenova"
      echo "    end"
      echo "end"

      echo "# NVM and Node.js setup for fish"
      echo "set -gx NVM_DIR /usr/local/share/nvm"
      echo "if test -d \$NVM_DIR"
      echo "    # Add Node.js binary path to fish PATH"
      echo "    set -gx PATH \$HOME/.nvm/versions/node/v18.20.7/bin \$PATH"
      echo "    # For accessing node and npm globally from default NVM version"
      echo "    set -gx PATH /usr/local/share/nvm/versions/node/v18.20.7/bin \$PATH"
      echo "end"

      echo "# Function to use NVM in fish"
      echo "function nvm"
      echo "    bass source /usr/local/share/nvm/nvm.sh --no-use ';' nvm \$argv"
      echo "end"

      echo "# Ensure npm is accessible as a command"
      echo "if not type -q npm"
      echo "    alias npm='/usr/local/share/nvm/versions/node/v18.20.7/bin/npm'"
      echo "end"

      echo "# Ensure node is accessible as a command"
      echo "if not type -q node"
      echo "    alias node='/usr/local/share/nvm/versions/node/v18.20.7/bin/node'"
      echo "end"
    } >>"$FISH_CONFIG" || {
      echo "Failed to write to Fish config file: $FISH_CONFIG" >&2
      return 1
    }
    echo "Fish shell configured with direnv hook, virtual env support, and Node.js/npm"

    # If bass (Bash script adapter for fish) is not installed, install it
    echo "Installing bass if not present..."
    fish -c 'if not type -q bass; and type -q fisher; fisher install edc/bass; end' || {
      echo "Warning: Failed to install bass, continuing..." >&2
    }
  else
    echo "Fish shell already configured with direnv hook"
    # Still ensure NVM paths are added if not already present
    if ! grep -q "NVM_DIR" "$FISH_CONFIG" 2>/dev/null; then
      echo "Adding NVM configuration to fish shell..."
      {
        echo ""
        echo "# NVM and Node.js setup for fish"
        echo "set -gx NVM_DIR /usr/local/share/nvm"
        echo "if test -d \$NVM_DIR"
        echo "    # Add Node.js binary path to fish PATH"
        echo "    set -gx PATH \$HOME/.nvm/versions/node/v18.20.7/bin \$PATH"
        echo "    # For accessing node and npm globally from default NVM version"
        echo "    set -gx PATH /usr/local/share/nvm/versions/node/v18.20.7/bin \$PATH"
        echo "end"

        echo "# Function to use NVM in fish"
        echo "function nvm"
        echo "    bass source /usr/local/share/nvm/nvm.sh --no-use ';' nvm \$argv"
        echo "end"

        echo "# Ensure npm is accessible as a command"
        echo "if not type -q npm"
        echo "    alias npm='/usr/local/share/nvm/versions/node/v18.20.7/bin/npm'"
        echo "end"

        echo "# Ensure node is accessible as a command"
        echo "if not type -q node"
        echo "    alias node='/usr/local/share/nvm/versions/node/v18.20.7/bin/node'"
        echo "end"
      } >>"$FISH_CONFIG" || {
        echo "Failed to write NVM configuration to Fish config file: $FISH_CONFIG" >&2
        return 1
      }
      echo "Added Node.js and npm configuration to fish shell"
    fi
  fi

  # Ensure .envrc has proper permissions
  if [ -f "/workspaces/greenova/.envrc" ]; then
    echo "Setting execute permissions on .envrc..."
    chmod +x "/workspaces/greenova/.envrc" || {
      echo "Failed to set permissions on .envrc" >&2
      return 1
    }
    echo "Set execute permissions on .envrc file"

    # Force direnv to reload with the new .envrc
    echo "Running cd /workspaces/greenova..."
    cd /workspaces/greenova || {
      echo "Failed to cd to /workspaces/greenova" >&2
      return 1
    }

    echo "Running direnv allow..."
    direnv allow || {
      echo "Failed to run direnv allow, output:" >&2
      direnv allow 2>&1 | tee /dev/stderr
      echo "Continuing despite direnv allow failure..." >&2
    }
  fi

  return 0
}

main() {
  VENV_PATH="/workspaces/greenova/.venv"
  clone

  # install Python
  #echo "Installing up Python environment..."
  #setup_pyenv

  # Setup Python environment first
  echo "Setting up Python environment..."
  setup_venv

  #install Python tools
  echo "Installing Python lint & format tools inside venv..."
  "$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel
  "$VENV_PATH/bin/pip" install --no-cache-dir isort autopep8 pylint

  # Fix django-hyperscript syntax error
   echo "Fixing django-hyperscript..."
   fix_django_hyperscript

  # Fix hyperscript_dump type annotation
  echo "Fixing hyperscript_dump..."
  fix_hyperscript_dump

  # Setup NVM and Node.js
  #echo "Setting up NVM and Node.js..."
  #setup_nvm || {
  #  echo "NVM setup failed. Exiting." >&2
  #  exit 1
  #}

  # Install npm 10.8.2 (compatible with Node.js 18.20.7)
  echo "Installing npm 10.8.2..."
  npm install -g npm@10.8.2

  # Install snyk globally only if not already installed
  if ! command -v snyk &>/dev/null; then
    echo "Installing snyk globally..."
    npm install snyk -g
  else
    echo "Snyk is already installed, skipping..."
  fi

  #install prettier
  echo "Installing global prettier..."
  npm install -g prettier

  # Install node packages if package.json exists
  [ -f "/workspaces/greenova/package.json" ] && npm install

  # Configure Fish shell with direnv (after venv is set up)
  echo "Setting up Fish shell with direnv..."
  setup_fish_direnv_debug

  #echo "Removing DEFAULT_KWARGS block in hyperscript.py by keyword..."
  #sed -i '/^DEFAULT_KWARGS *= *{/,/^ *raise TypeError/d' /workspaces/greenova/.venv/lib/python3.9/site-packages/django_hyperscript/templatetags/hyperscript.py
  
  #echo " Pulling environment variables from dotenv-vault..."
  #npx dotenv-vault@latest pull -y

  #echo " Run a series of make commands"
  #(
  #make migrations &&
  #make migrate &&
  #make import &&
  #make sync &&
  #make static &&
  #make user
  #) || {
  #echo " Make commands failed."
  #exit 1
  #}

  # Ensure PYTHONPATH is set
  export PYTHONPATH=/workspaces/greenova:${PYTHONPATH:-}

  # Ensure Pre-Commit is updated
  if command -v pre-commit >/dev/null 2>&1; then
    echo "Updating pre-commit hooks..."
    pre-commit autoupdate
  fi

  echo " Post-create script completed successfully!"
}
main "$@"
