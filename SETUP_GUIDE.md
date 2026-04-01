# Harbor Benchmark Setup Guide - llama.cpp + Vulkan GPU

This guide covers setting up the Terminal Bench (Harbor) benchmark environment with llama.cpp for testing large language models locally. Created after migrating from lemonade-server to llama.cpp b8580.

## Table of Contents
1. [System Requirements](#system-requirements)
2. [Initial Setup](#initial-setup)
3. [llama.cpp Installation](#llamacpp-installation)
4. [Docker Configuration](#docker-configuration)
5. [Repository Setup](#repository-setup)
6. [Model Testing](#model-testing)
7. [Running Benchmarks](#running-benchmarks)
8. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Hardware
- **RAM**: 64GB+ recommended for larger models
  - Qwen3-Coder-Next (80B): ~45GB
  - GPT-OSS-120B: ~60GB
  - Nemotron-3-Super (120B): ~60GB
- **GPU**: Vulkan-compatible GPU recommended (tested on AMD Radeon Graphics RADV GFX1151)
- **Disk**: 200GB+ free space for models and results

### Software
- Ubuntu 22.04+ (tested on Ubuntu 24.04)
- Python 3.10+
- Git
- Docker (native, not snap)
- CUDA/ROCm/Vulkan drivers (for GPU acceleration)

---

## Initial Setup

### 1. Clone Repository
```bash
cd /scratch/$USER  # Or your preferred working directory
git clone https://github.com/singhh5050/tbench-eval.git
cd tbench-eval
```

### 2. Install System Dependencies
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install build tools
sudo apt install -y build-essential cmake git curl wget

# Install Python and pip
sudo apt install -y python3 python3-pip python3-venv

# Install Docker (if not already installed)
# IMPORTANT: Use native Docker, NOT snap Docker
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker  # Apply group changes without logout
```

### 3. Install Harbor (Terminal Bench)
```bash
# Install uv (fast Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.local/bin/env

# Install harbor
uv tool install harbor

# Verify installation
harbor --version
```

---

## llama.cpp Installation

### 1. Download and Build llama.cpp b8580

```bash
# Create installation directory
mkdir -p ~/.local/bin/llama.cpp
cd ~/.local/bin/llama.cpp

# Clone llama.cpp
git clone https://github.com/ggml-org/llama.cpp.git llama-b8580-src
cd llama-b8580-src

# Checkout specific version (b8580)
git checkout 7c203670f  # This is commit for b8580

# Build with Vulkan support (for AMD/NVIDIA GPUs)
mkdir build && cd build
cmake .. -DGGML_VULKAN=ON
cmake --build . --config Release -j $(nproc)

# Copy binary to expected location
mkdir -p ~/.local/bin/llama.cpp/llama-b8580
cp bin/llama-server ~/.local/bin/llama.cpp/llama-b8580/
cp bin/libggml-*.so ~/.local/bin/llama.cpp/llama-b8580/

# Verify installation
~/.local/bin/llama.cpp/llama-b8580/llama-server --version
```

**Alternative: Build with CUDA (NVIDIA)**
```bash
cmake .. -DGGML_CUDA=ON
cmake --build . --config Release -j $(nproc)
```

**Alternative: Build with ROCm (AMD)**
```bash
cmake .. -DGGML_HIPBLAS=ON
cmake --build . --config Release -j $(nproc)
```

### 2. Create Model Cache Directory
```bash
mkdir -p ~/.cache/llama-models
```

---

## Docker Configuration

### CRITICAL: Fix Docker Network Conflicts

**Problem**: Snap Docker uses restricted filesystem access and default Docker networks (172.17-19.x.x) can conflict with NFS mounts.

**Solution**: Configure Docker to use non-conflicting subnets and ensure native Docker.

### 1. Remove Snap Docker (if installed)
```bash
sudo snap remove docker
```

### 2. Install Native Docker
```bash
sudo apt install -y docker.io
```

### 3. Configure Docker Network Subnets
```bash
# Backup existing config
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null || true

# Create/update Docker daemon config
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/scratch/docker-data",
  "default-address-pools": [
    {"base": "10.10.0.0/16", "size": 24}
  ]
}
EOF

# Create data directory
sudo mkdir -p /scratch/docker-data

# Restart Docker
sudo systemctl restart docker

# Verify new subnet
docker network inspect bridge --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
# Should show: 10.10.0.0/24
```

### 4. Fix Docker Socket Permissions
```bash
sudo chgrp docker /var/run/docker.sock
sudo chmod 666 /var/run/docker.sock
```

---

## Repository Setup

### 1. Configure Environment
```bash
cd /scratch/$USER/tbench-eval

# Create .env file
cat > .env << 'EOF'
OPENAI_API_KEY=lemonade
OPENAI_API_BASE=http://localhost:8000/v1
EOF

# Create logs directory
mkdir -p logs
```

### 2. Verify Key Scripts
The repository includes these key scripts:
- `model_manager.sh` - Model download, server management, cleanup
- `run_easy_tasks_full.sh` - Benchmark all models on 13 easy tasks
- `run_frontier_v2.sh` - Test frontier models (Qwen 3.5, Nemotron, GLM)
- `ISSUES.md` - Documentation of all issues encountered and fixes

### 3. Check Model Manager Configuration
```bash
# Verify paths in model_manager.sh
grep LLAMA_BIN model_manager.sh
# Should show: LLAMA_BIN="${HOME}/.local/bin/llama.cpp/llama-b8580/llama-server"

grep LLAMA_MODELS_DIR model_manager.sh
# Should show: LLAMA_MODELS_DIR="${HOME}/.cache/llama-models"
```

---

## Model Testing

### 1. Test Download Function
```bash
source model_manager.sh

# Test with a small model first (GPT-OSS-20B, ~12GB)
download_model "gpt-oss-20b-GGUF" "ggml-org/gpt-oss-20b-GGUF" "mxfp4"

# Check download
ls -lh ~/.cache/llama-models/gpt-oss-20b-GGUF/
```

### 2. Test Server Start
```bash
source model_manager.sh

# Start server (will bind to localhost:8000)
start_model "gpt-oss-20b-GGUF"

# Test API endpoint (in another terminal)
curl -sf http://localhost:8000/v1/models | jq

# Stop server
stop_llama
```

### 3. Test Single Task
```bash
source .env

# Run one task to verify everything works
harbor run \
  -d terminal-bench@2.0 \
  -a terminus-2 \
  -m "openai/gpt-oss-20b-GGUF" \
  -n 1 \
  --timeout-multiplier 2.0 \
  --jobs-dir "/var/tmp/harbor-results/test-$(date +%H%M)" \
  -t fix-git

# Check results
find /var/tmp/harbor-results/test-* -name "reward.txt" -exec cat {} \;
```

---

## Running Benchmarks

### Large Models to Test (64GB+ RAM Server)

```bash
# Edit run_easy_tasks_full.sh to include larger models:
MODELS=(
  # Working models from 30GB tests
  "Qwen3.5-35B-A3B-GGUF|unsloth/Qwen3.5-35B-A3B-GGUF|Q4_K_M"
  "GLM-4.7-Flash-GGUF|unsloth/GLM-4.7-Flash-GGUF|Q4_K_M"

  # Larger models (require 64GB+)
  "Qwen3-Coder-Next-GGUF|Qwen/Qwen3-Coder-Next-GGUF|Q4_K_M"  # 80B total, ~45GB
  "gpt-oss-120b-GGUF|ggml-org/gpt-oss-120b-GGUF|Q4_K_M"  # 120B total, ~60GB
  "Nemotron-3-Super-30B-GGUF|nvidia/Nemotron-3-Super-30B-GGUF|Q4_K_M"  # If available
)
```

### Full Benchmark Run
```bash
# Run full benchmark (5-8 hours for 5 models × 13 tasks)
nohup ./run_easy_tasks_full.sh > logs/easy_tasks_full.log 2>&1 &

# Monitor progress
tail -f logs/easy_tasks_full.log

# Check results
cat /var/tmp/harbor-results/easy-tasks-full-*/summary.txt
```

### Quick Test (Single Model)
```bash
# Test just one model on easy tasks
MODELS=(
  "gpt-oss-120b-GGUF|ggml-org/gpt-oss-120b-GGUF|Q4_K_M"
)

# Run the benchmark
nohup ./run_easy_tasks_full.sh > logs/single_test.log 2>&1 &
```

---

## Troubleshooting

### Issue 1: `--flash-attn` Flag Error
**Error**: `error: option '--flash-attn' requires an argument`

**Fix**: Change `--flash-attn` to `--flash-attn auto` in model_manager.sh
```bash
# In model_manager.sh, line ~230:
--flash-attn auto \  # NOT just --flash-attn
```

### Issue 2: Docker Permission Denied
**Error**: `permission denied while trying to connect to the Docker daemon socket`

**Fix**:
```bash
sudo chgrp docker /var/run/docker.sock
sudo chmod 666 /var/run/docker.sock
# OR add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### Issue 3: RewardFileNotFoundError (Snap Docker)
**Error**: Tests pass but `reward.txt` not found

**Root Cause**: Snap Docker cannot write to certain partitions (like `/scratch`)

**Fix**: Use native Docker and write results to `/var/tmp`:
```bash
--jobs-dir "/var/tmp/harbor-results/..."  # NOT /scratch/
```

### Issue 4: Disk Full During Download
**Error**: `No space left on device` when downloading models

**Fix**: Clean up old model caches
```bash
source model_manager.sh

# List models
ls ~/.cache/llama-models/

# Delete specific model
delete_model "ModelName-GGUF"

# Check disk space
df -h /scratch
df -h /tmp
```

### Issue 5: Model Server Crashes Mid-Benchmark
**Error**: `ConnectionRefusedError` on port 8000

**Possible Causes**:
1. Model incompatibility with llama.cpp version
2. Out of memory
3. Corrupted GGUF file

**Debug**:
```bash
# Check server logs
tail -100 logs/easy_tasks_full.log | grep -A10 -B10 "error\|crash\|killed"

# Test model manually
source model_manager.sh
start_model "ModelName-GGUF"
# Watch for errors in startup

# Check memory
free -h
```

### Issue 6: Trinity-Mini Generates 28K Tokens
**Problem**: Reasoning models fill context with thinking tokens

**Fix**: Reasoning budget is already set in model_manager.sh:
```bash
--reasoning-budget 2048 \  # Limits thinking tokens
```

### Issue 7: NFS Mount Conflicts with Docker Networks
**Error**: Cannot access files on 172.19.x.x NFS mounts

**Fix**: Docker networks configured to use 10.10.x.x (see Docker Configuration section)

---

## Key Configuration Values

### File Locations
```bash
# llama.cpp binary
~/.local/bin/llama.cpp/llama-b8580/llama-server

# Model cache
~/.cache/llama-models/

# Results directory
/var/tmp/harbor-results/

# Logs
/scratch/$USER/tbench-eval/logs/
```

### API Configuration
```bash
# Server endpoint
http://localhost:8000/v1  # Note: /v1 not /api/v1

# API key
lemonade  # Hardcoded in scripts

# Timeout
600s per task (10 minutes)
```

### Model Manager Settings (in model_manager.sh)
```bash
# Context size: 32768 tokens
# Threads: 16
# Flash attention: auto
# Reasoning budget: 2048 tokens
# API key: lemonade
```

---

## Example: Testing GPT-OSS-120B

```bash
# 1. Download model (~60GB)
source model_manager.sh
download_model "gpt-oss-120b-GGUF" "ggml-org/gpt-oss-120b-GGUF" "Q4_K_M"

# 2. Start server
start_model "gpt-oss-120b-GGUF"

# 3. Test API
curl -sf http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer lemonade" \
  -d '{
    "model": "gpt-oss-120b",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }' | jq

# 4. Run benchmark
harbor run \
  -d terminal-bench@2.0 \
  -a terminus-2 \
  -m "openai/gpt-oss-120b-GGUF" \
  -n 1 \
  --timeout-multiplier 2.0 \
  --jobs-dir "/var/tmp/harbor-results/gpt120-test" \
  -t fix-git

# 5. Check results
cat /var/tmp/harbor-results/gpt120-test/*/reward.txt
```

---

## Current Benchmark Results (30GB RAM Server)

**Tested Models:**
| Model | Size | Pass Rate | Notes |
|-------|------|-----------|-------|
| Qwen 3.5-35B-A3B | 35B (3B active) | 8/13 (62%) | Best performer |
| GLM-4.7-Flash | 30B (3B active) | Testing | Fast inference |
| Nemotron-3-Nano-30B-A3B | 30B (3B active) | 1/13 (8%) | Unexpectedly poor |
| Qwen3-Coder-30B-A3B | 30B (3B active) | 0/1 (0%) | Failed fix-git |
| GPT-OSS-20B | 20B (2B active) | 0/1 (0%) | Failed fix-git |
| Trinity-Mini | 26B (3B active) | 0/1 (0%) | Timeout (reasoning loop) |

**Too Large for 30GB RAM:**
- Qwen3-Coder-Next (80B) - needs ~45GB
- GPT-OSS-120B (120B) - needs ~60GB
- Nemotron-3-Super (120B) - needs ~60GB

---

## Next Steps for Larger Server

1. **Verify Hardware**: Check RAM and GPU availability
2. **Install Dependencies**: Follow Initial Setup section
3. **Build llama.cpp**: With appropriate backend (Vulkan/CUDA/ROCm)
4. **Test Small Model**: Verify setup with GPT-OSS-20B
5. **Run Large Models**: Test Qwen3-Coder-Next, GPT-OSS-120B
6. **Compare Results**: Against 30GB server baseline

---

## References

- **Repository**: https://github.com/singhh5050/tbench-eval
- **llama.cpp**: https://github.com/ggml-org/llama.cpp
- **Harbor (Terminal Bench)**: https://pypi.org/project/harbor/
- **Issues Log**: See `ISSUES.md` in repository

---

## Contact

For questions about this setup, refer to:
- `ISSUES.md` - Detailed log of all problems and solutions
- Git commit `42d7f2c` - Full migration from lemonade to llama.cpp
- This guide was created after successful deployment on AMD Ryzen AI MAX+ 395 with 30GB RAM

Good luck with the larger models! 🚀
