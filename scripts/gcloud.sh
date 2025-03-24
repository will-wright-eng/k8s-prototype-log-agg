#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Constants
readonly BANNER="==============================================================="
readonly MIN_BASH_VERSION=3

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m' # No Color

# Function to print formatted messages
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to display banner messages
print_banner() {
  local message="$1"
  echo "$BANNER"
  echo "$message"
  echo "$BANNER"
  echo ""
}

# Function to check prerequisites
check_prerequisites() {
  # Check Bash version
  if ((BASH_VERSINFO[0] < MIN_BASH_VERSION)); then
    log_error "Bash version $MIN_BASH_VERSION or higher is required"
    exit 1
  fi

  check_command "gcloud" "Please install it from: https://cloud.google.com/sdk/docs/install"
}

# Function to handle authentication
authenticate_gcloud() {
  log_info "Step 1: Authenticating with Google Cloud..."
  log_info "This will open a browser window for you to log in."

  if ! confirm_action "Continue with Google Cloud authentication?" "Y"; then
    log_info "Skipping authentication. Using existing credentials if available."
    return 0
  fi

  if ! gcloud auth login; then
    log_error "Authentication failed. Please try again."
    exit 1
  fi

  log_info "Authentication successful!"
  echo ""
}

# Function to set up application default credentials
setup_default_credentials() {
  log_info "Step 2: Creating application default credentials..."
  log_info "This will set up local credentials for your applications."

  if ! confirm_action "Continue with application default credentials setup?" "Y"; then
    log_info "Skipping application default credentials setup."
    return 0
  fi

  if ! gcloud auth application-default login; then
    log_error "Failed to set up application default credentials. Please try again."
    exit 1
  fi

  log_info "Application default credentials created successfully!"
  echo ""
}

# Function to list and select project
select_project() {
  log_info "Step 3: Listing available Google Cloud projects..."

  local projects
  # Get project ID, name, and project number in a tabular format
  projects=$(execute_with_timeout "gcloud projects list --format='table(projectNumber,projectId,name)' --sort-by=projectId" 30) || {
    log_error "Failed to fetch projects"
    exit 1
  }

  if [[ -z "$projects" ]]; then
    log_error "No projects found in your Google Cloud account"
    log_error "Please create a project in the Google Cloud Console first"
    exit 1
  fi

  # Extract just the project IDs for selection
  local project_ids
  project_ids=$(gcloud projects list --format="value(projectId)" --sort-by=projectId)

  # Store projects in an indexed array
  local -a project_list
  local counter=1
  while IFS= read -r project; do
    project_list[${counter}]=$project
    ((counter++))
  done <<<"$project_ids"

  echo ""
  echo "Available projects:"
  echo "$projects"
  echo ""

  if ! confirm_action "Continue with project selection?" "Y"; then
    # Return current project if skipping
    SELECTED_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$SELECTED_PROJECT" ]]; then
      log_error "No project currently configured. Project selection is required."
      exit 1
    fi
    return 0
  fi

  local project_number
  while true; do
    read -rp "Please enter the row number (1-$((counter - 1))) of the project you want to use: " project_number
    if [[ "$project_number" =~ ^[0-9]+$ ]] && ((project_number >= 1 && project_number < counter)); then
      break
    fi
    log_error "Invalid selection. Please enter a number between 1 and $((counter - 1))"
  done

  SELECTED_PROJECT="${project_list[$project_number]}"
}

# Function to set project configuration
configure_project() {
  local project="$1"
  log_info "Step 4: Setting up the default project configuration..."

  if ! confirm_action "Continue with project configuration?" "Y"; then
    log_info "Skipping project configuration."
    return 0
  fi

  if ! gcloud config set project "$project"; then
    log_error "Failed to set project configuration"
    exit 1
  fi

  log_info "Default project set to: $project"
  echo ""
}

# Function to display final configuration
display_configuration() {
  local project="$1"
  log_info "Step 5: Current Google Cloud configuration:"
  echo ""
  gcloud config list

  echo ""
  print_banner "Setup Complete!"
  log_info "Your Google Cloud CLI is now configured with:"
  echo "  - User authentication"
  echo "  - Application Default Credentials"
  echo "  - Default project: $project"
  echo ""
}

# Main function
main() {
  # Set up error handling and cleanup
  setup_trap

  # Acquire lock to prevent multiple instances
  acquire_lock "gcloud_setup"

  print_banner "Google Cloud Interactive Login Script"

  check_prerequisites
  authenticate_gcloud
  setup_default_credentials

  # Initialize the project selection variable
  SELECTED_PROJECT=""
  select_project

  if [[ -n "$SELECTED_PROJECT" ]]; then
    configure_project "$SELECTED_PROJECT"
    display_configuration "$SELECTED_PROJECT"
  else
    log_info "Setup completed with existing configuration"
    display_configuration "$(gcloud config get-value project 2>/dev/null || echo 'not set')"
  fi
}

# Execute main function
main
