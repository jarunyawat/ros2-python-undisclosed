#!/bin/bash
# deploy.sh
# Automates build + Cython protection for ALL ament_python packages

set -e  # Exit on error

# ─── Config ───────────────────────────────────────────────────────────────────
# Auto-detect workspace: go up from script location until we find a src/ folder
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

find_workspace() {
    echo "aha" >&2          # ← >&2 sends to stderr, not captured by $()
    local dir="$1"
    echo "searching: $dir" >&2   # >&2 visible on screen
    while [ "$dir" != "/" ]; do
        echo "checking: $dir" >&2
        if [ -d "$dir/src" ]; then
            echo "$dir"     # ← only this gets captured into WS
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

if [ -n "$1" ]; then
    # Use argument if provided
    WS=$1
elif WS=$(find_workspace "$SCRIPT_DIR"); then
    echo "  Auto-detected workspace: $WS"
else
    echo "  Could not auto-detect workspace!"
    echo "  Usage: ./deploy.sh [/path/to/ws]"
    exit 1
fi
SRC=$WS/src
INSTALL=$WS/install
BUILD=$WS/build
# ──────────────────────────────────────────────────────────────────────────────

echo "============================================"
echo "  ROS2 Python Deploy Script"
echo "  Workspace: $WS"
echo "============================================"

# ─── Step 1: Find all ament_python packages ───────────────────────────────────
echo ""
echo "[1/4] Scanning for ament_python packages..."

PYTHON_PKGS=()
while IFS= read -r pkg_xml; do
    pkg_dir=$(dirname "$pkg_xml")
    pkg_name=$(basename "$pkg_dir")

    # Check if it's ament_python build type
    if grep -q "ament_python" "$pkg_xml"; then
        PYTHON_PKGS+=("$pkg_name")
        echo "  Found: $pkg_name"
    fi
done < <(find "$SRC" -name "package.xml")

if [ ${#PYTHON_PKGS[@]} -eq 0 ]; then
    echo "  No ament_python packages found!"
    exit 1
fi

echo "  Total: ${#PYTHON_PKGS[@]} package(s)"

# ─── Step 2: Inject Cython into setup.py if not already there ─────────────────
echo ""
echo "[2/4] Checking setup.py for Cython support..."

for pkg in "${PYTHON_PKGS[@]}"; do
    pkg_dir="$SRC/$pkg"
    setup_py="$pkg_dir/setup.py"

    if [ ! -f "$setup_py" ]; then
        echo "  [$pkg] No setup.py found, skipping..."
        continue
    fi

    if grep -q "cythonize" "$setup_py"; then
        echo "  [$pkg] Cython already configured ✓"
    else
        echo "  [$pkg] Injecting Cython into setup.py..."

        # Backup original
        cp "$setup_py" "$setup_py.bak"

        # Inject Cython imports and ext_modules at top
        python3 - <<PYEOF
import re

with open("$setup_py", "r") as f:
    content = f.read()

# Add imports after existing imports
cython_import = """from Cython.Build import cythonize
import os
"""
# Insert after last import line
content = re.sub(
    r'((?:from|import).*\n)(?!(?:from|import))',
    r'\1' + cython_import,
    content,
    count=1
)

# Add ext_modules before setup( or inside setup()
package_name_match = re.search(r"package_name\s*=\s*['\"](.+?)['\"]", content)
if package_name_match:
    pkg = package_name_match.group(1)
    ext_module_code = f"""
ext_modules = []
try:
    _files = "{pkg}/*.py"
    ext_modules = cythonize(
        _files,
        compiler_directives={{'language_level': '3'}},
        force=True,
        quiet=True,
        exclude=["{pkg}/__init__.py"],
    )
except Exception as e:
    print(f"Cython warning: {{e}}")

"""
    # Insert before setup(
    content = content.replace("setup(", ext_module_code + "setup(\n    ext_modules=ext_modules,", 1)

with open("$setup_py", "w") as f:
    f.write(content)

print("    Injection complete")
PYEOF
    fi
done

# ─── Step 3: colcon build ──────────────────────────────────────────────────────
echo ""
echo "[3/4] Building workspace..."
cd "$WS"

colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release

echo "  Build complete ✓"

# ─── Cleanup build and log folders ────────────────────────────────────────────
echo ""
echo "  Cleaning up build/ and log/..."
rm -rf "$WS/build" "$WS/log"
echo "  Cleaned build/ and log/ ✓"

# ─── Step 4: Remove .py source files from install ─────────────────────────────
echo ""
echo "[4/4] Removing Python source files from install/..."

for pkg in "${PYTHON_PKGS[@]}"; do
    install_dir="$INSTALL/$pkg"

    if [ ! -d "$install_dir" ]; then
        echo "  [$pkg] Install dir not found, skipping..."
        continue
    fi

    # Count before
    py_count=$(find "$install_dir" -name "*.py" ! -name "__init__.py" | wc -l)
    so_count=$(find "$install_dir" -name "*.so" | wc -l)

    # Delete source .py files
    find "$install_dir" -name "*.py" ! -name "__init__.py" -delete

    # Also delete __pycache__
    find "$install_dir" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

    echo "  [$pkg] Removed $py_count .py file(s), kept $so_count .so file(s) ✓"
done

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Deploy Complete!"
echo "============================================"
echo ""
echo "Packages protected:"
for pkg in "${PYTHON_PKGS[@]}"; do
    echo "  ✓ $pkg"
    find "$INSTALL/$pkg" -name "*.so" | while read so; do
        echo "      $(basename $so)"
    done
done

echo ""
echo "To ship to client, copy the install/ folder:"
echo "  tar -czf robot_deploy.tar.gz -C $WS install/"
echo ""
echo "Client runs:"
echo "  tar -xzf robot_deploy.tar.gz"
echo "  source install/setup.bash"
echo "  ros2 run <pkg> <node>"