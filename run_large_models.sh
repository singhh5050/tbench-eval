#!/usr/bin/env bash
# Wrapper script to run the full benchmark with video/render groups for Vulkan GPU access
# Usage: nohup ./run_large_models.sh > logs/large_models.log 2>&1 &

exec sg video -c "sg render -c 'bash /scratch/harshsin/tbench-eval/run_easy_tasks_full.sh'"
