#!/usr/bin/env bash

set -euo pipefail

# Core environment setup
declare REPO_ROOT
REPO_ROOT="$(cd "$(git rev-parse --show-toplevel)" && pwd)"
export REPO_ROOT

declare SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Constants
export BANNER="============================================================"

# Check if we're in a terminal that supports colors
if [ -t 1 ]; then
  readonly SUPPORTS_COLOR=1
  export GREEN='\033[0;32m'
  export RED='\033[0;31m'
  export NC='\033[0m'
else
  readonly SUPPORTS_COLOR=0
  export GREEN=''
  export RED=''
  export NC=''
fi

# Core utility functions
normalize_path() {
  local path="$1"
  echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
}

cleanup() {
  local exit_code=$?
  # Add cleanup tasks here if needed
  exit $exit_code
}

setup_trap() {
  trap cleanup EXIT
  trap 'log_error "An error occurred at line $LINENO. Exit code: $?"' ERR
}

# Logging functions
log_info() {
  if [ "$SUPPORTS_COLOR" -eq 1 ]; then
    echo -e "${GREEN}[INFO]${NC} $1"
  else
    echo "[INFO] $1"
  fi
}

log_error() {
  if [ "$SUPPORTS_COLOR" -eq 1 ]; then
    echo -e "${RED}[ERROR]${NC} $1" >&2
  else
    echo "[ERROR] $1" >&2
  fi
}

print_banner() {
  local message="$1"
  echo "$BANNER"
  echo "$message"
  echo "$BANNER"
  echo ""
}

confirm_action() {
  local prompt="$1"
  local default_answer="${2:-Y}"

  while true; do
    read -rp "${prompt} [Y/n]: " choice
    choice=${choice:-$default_answer}
    case "$choice" in
      [Yy]*)
        echo ""
        return 0
        ;;
      [Nn]*)
        echo ""
        return 1
        ;;
      *)
        log_error "Please answer Y or n"
        ;;
    esac
  done
}

check_command() {
  local cmd="$1"
  local install_msg="$2"

  if ! command -v "$cmd" &>/dev/null; then
    log_error "$cmd is not installed. Please install it first:"
    log_error "$install_msg"
    exit 1
  fi
}

ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
}

get_timestamp() {
  date +%Y%m%d%H%M%S
}

execute_with_log() {
  local cmd="$1"
  local log_file="$2"
  ensure_dir "$(dirname "$log_file")"
  eval "$cmd" | tee "$log_file"
}

select_terraform_dir() {
  local environments_dir="${REPO_ROOT}/tofu/environments"

  # Check if environments directory exists
  if [ ! -d "$environments_dir" ]; then
    log_error "Environments directory not found: ${environments_dir}"
    exit 1
  fi

  local options=()

  # Collect all directories under environments/
  while IFS= read -r dir; do
    if [ -d "$dir" ]; then # Only add if it's a valid directory
      options+=("$(basename "$dir")")
    fi
  done < <(find "$environments_dir" -mindepth 1 -maxdepth 1 -type d)

  if [ ${#options[@]} -eq 0 ]; then
    log_error "No environment directories found in ${environments_dir}"
    exit 1
  fi

  echo "Available environments:"
  select env in "${options[@]}"; do
    if [ -n "$env" ]; then
      local selected_dir="${environments_dir}/${env}"
      if [ -d "$selected_dir" ]; then
        declare -g TF_DIR
        TF_DIR=$(normalize_path "$selected_dir")
        export TF_DIR
        return
      else
        log_error "Selected directory does not exist: ${selected_dir}"
        exit 1
      fi
    else
      log_error "Invalid selection. Please try again."
    fi
  done
}

# Process management
acquire_lock() {
  local lockfile="/tmp/${1:-default}.lock"
  if [ -e "$lockfile" ]; then
    local pid
    pid=$(cat "$lockfile")
    if ps -p "$pid" >/dev/null 2>&1; then
      log_error "Another instance is running (PID: $pid)"
      exit 1
    fi
  fi
  echo $$ >"$lockfile"
}

release_lock() {
  local lockfile="/tmp/${1:-default}.lock"
  rm -f "$lockfile"
}

execute_with_timeout() {
  local cmd="$1"
  local timeout="${2:-300}" # Default 5 minutes

  perl -e "alarm $timeout; exec @ARGV" "$cmd"
}

# Export all functions
export -f normalize_path
export -f cleanup
export -f setup_trap
export -f log_info
export -f log_error
export -f print_banner
export -f confirm_action
export -f check_command
export -f ensure_dir
export -f get_timestamp
export -f execute_with_log
export -f select_terraform_dir
export -f acquire_lock
export -f release_lock
export -f execute_with_timeout
