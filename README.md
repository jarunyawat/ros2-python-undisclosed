# 🤖 ROS2 Python Code Protection with Cython

Automate the compilation of ROS2 Python packages into native `.so` binaries using Cython — protecting your source code before shipping to clients.

---

## 📋 Overview

When deploying ROS2 Python packages to clients, raw `.py` source files are fully readable. This project provides a `deploy.sh` script that:

- Automatically finds all `ament_python` packages in your workspace
- Injects Cython compilation into `setup.py` (if not already configured)
- Builds the workspace with `colcon build`
- Removes Python source files from the `install/` folder
- Leaves only compiled `.so` binaries — unreadable without reverse engineering tools

```
your_node.py  →  colcon build  →  your_node.cpython-312-aarch64-linux-gnu.so
```

---

## 🛡️ Protection Comparison

| Format | Protection | Reversible |
|--------|-----------|------------|
| `.py` | ❌ None | Directly readable |
| `.pyc` | ❌ Weak | ~95% recoverable with pycdc/decompyle3 |
| `.so` (Cython) | ✅ Strong | Requires assembly-level reverse engineering |

---

## 🔧 Requirements

- ROS2 (Humble / Jazzy)
- Python 3.10+
- Cython

```bash
pip install cython --break-system-packages
```

---

## 📁 Project Structure

```
your_ws/
├── src/
|   ├── resource/
│           └── your_pkg
│   └── your_pkg/
│       |   ├── __init__.py
│       │   └── your_node.py  ← compiled to .so
│       ├── package.xml
│       ├── setup.py          ← Cython injected here 
├── install/                  ← ship this to client
└── deploy.sh                 ← put script here
```

---

## 🚀 Usage

### 1. Place `deploy.sh` in your workspace root

```
your_ws/
├── src/
└── deploy.sh   ← here
```

### 2. Make it executable

```bash
chmod +x deploy.sh
```

### 3. Run it

```bash
# Auto-detect workspace
./deploy.sh

# Or specify workspace path
./deploy.sh /path/to/your_ws
```

---

## 📦 What the Script Does

```
[1/4] Scan src/     →  find all ament_python packages
[2/4] Check setup.py →  inject Cython if not already there
[3/4] colcon build   →  compile .py → .so, then clean build/ and log/
[4/4] Remove .py     →  delete source files from install/
        ↓
   install/ ready to ship — no source code visible
```

---

## ⚠️ Important Notes

| Requirement | Detail |
|-------------|--------|
| ROS2 distro must match | Built with Jazzy → client needs Jazzy |
| OS must match | Built on Ubuntu 24 → client needs Ubuntu 24 |
| Python version must match | Built with Python 3.12 → client needs 3.12 |
| Architecture must match | Built on `aarch64` (Pi) → client needs `aarch64` |

`.so` files are platform-specific and will not run on a different OS, architecture, or Python version.

---

## 🐳 Docker

You can copy the `install/` folder after executing `deploy.sh` into a Docker image to make your code unreadable.
```dockerfile
FROM ros:jazzy

# Install dependencies
RUN apt-get update && apt-get install -y \
    python3-cython \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Copy workspace source
COPY src/ /ros2_ws/src/
COPY deploy.sh /ros2_ws/deploy.sh

RUN chmod +x /ros2_ws/deploy.sh

# Run deploy.sh during build
RUN cd /ros2_ws && bash deploy.sh

# Remove src/ and deploy.sh after build — client cant see source
RUN rm -rf /ros2_ws/src /ros2_ws/deploy.sh

# Source ROS2 on startup
RUN echo "source /ros2_ws/install/setup.bash" >> ~/.bashrc
```
This gives you **two layers of protection**:
- `deploy.sh` removes `.py` source → only `.so` binaries in `install/`
- Docker image hides the filesystem from the client

---