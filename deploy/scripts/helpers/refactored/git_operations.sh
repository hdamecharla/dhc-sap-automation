#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# shellcheck disable=SC1090,SC1091,SC2034,SC2154
# git operations for pipeline integration with conflict resolution

#==============================================================================
# Git Operation Constants
#==============================================================================

declare -gr GIT_MAX_RETRIES=3
declare -gr GIT_RETRY_DELAY=5
declare -gr GIT_TIMEOUT=300

#==============================================================================
# Pipeline Git Operations
#==============================================================================

function execute_pipeline_git_operations() {
    local branch="$1"
    local build_user="$2"
    local build_email="$3"

    display_banner "Git Operations" "Managing repository state and version control" "info"
    send_pipeline_event "progress" "Managing git operations" "85"

    # Execute secure git checkout with conflict resolution
    if ! execute_secure_git_checkout "$branch"; then
        send_pipeline_event "error" "Git checkout failed"
        return $GIT_ERROR
    fi

    # Configure git for pipeline operations
    if ! setup_git_credentials "$build_user" "$build_email"; then
        send_pipeline_event "error" "Git configuration failed"
        return $GIT_ERROR
    fi

    display_success "Git Operations" "Repository state managed successfully"
    return $SUCCESS
}

function execute_git_state_persistence_with_retry() {
    log_info "Persisting deployment state to repository with retry logic"

    local max_attempts="$GIT_MAX_RETRIES"
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if execute_git_state_persistence; then
            log_info "State persistence successful on attempt $attempt"
            return $SUCCESS
        fi

        log_warn "State persistence failed on attempt $attempt"
        ((attempt++))

        if [[ $attempt -le $max_attempts ]]; then
            log_info "Retrying state persistence in ${GIT_RETRY_DELAY}s..."
            sleep "$GIT_RETRY_DELAY"
        fi
    done

    display_error "Git State" "Failed to persist state after $max_attempts attempts" "$GIT_ERROR"
    return $GIT_ERROR
}

function execute_git_state_persistence() {
    log_info "Executing git state persistence"

    local added=0
    local files_to_add=()

    # Identify files to add to git
    if [[ -f ".sap_deployment_automation/${ENVIRONMENT}${LOCATION}" ]]; then
        files_to_add+=(".sap_deployment_automation/${ENVIRONMENT}${LOCATION}")
    fi

    if [[ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform/terraform.tfstate" ]]; then
        files_to_add+=("DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform/terraform.tfstate")
    fi

    if [[ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/terraform.tfstate" ]]; then
        # Create encrypted state zip
        if create_encrypted_state_zip; then
            files_to_add+=("DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip")
        fi
    fi

    # Add files to git if any exist
    if [[ ${#files_to_add[@]} -gt 0 ]]; then
        for file in "${files_to_add[@]}"; do
            if git add -f "$file"; then
                added=1
                log_info "Added file to git: $file"
            else
                log_warn "Failed to add file to git: $file"
            fi
        done
    fi

    # Commit and push if files were added
    if [[ $added -eq 1 ]]; then
        if commit_and_push_changes; then
            return $SUCCESS
        else
            return $GIT_ERROR
        fi
    else
        log_info "No files to persist to git"
        return $SUCCESS
    fi
}

function create_encrypted_state_zip() {
    log_info "Creating encrypted state zip file"

    # Install zip if not available
    if ! command -v zip &> /dev/null; then
        if ! sudo apt-get install zip -y; then
            log_warn "Failed to install zip utility"
            return $TOOL_ERROR
        fi
    fi

    # Create encrypted zip file using collection ID as password
    local password="${SYSTEM_COLLECTIONID//-/}"

    if zip -q -j -P "$password" "DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" "DEPLOYER/$DEPLOYER_FOLDERNAME/terraform.tfstate"; then
        log_info "Encrypted state zip created successfully"
        return $SUCCESS
    else
        log_error "Failed to create encrypted state zip"
        return $TOOL_ERROR
    fi
}

function commit_and_push_changes() {
    log_info "Committing and pushing changes to repository"

    # Pull latest changes before pushing
    if ! safe_git_pull "$BUILD_SOURCEBRANCHNAME" 1; then
        log_warn "Failed to pull latest changes, attempting to continue"
    fi

    # Commit changes
    local commit_message="Added updates from Control Plane Deployment for $DEPLOYER_FOLDERNAME $LIBRARY_FOLDERNAME $BUILD_BUILDNUMBER [skip ci]"

    if ! git commit -m "$commit_message"; then
        log_error "Failed to commit changes"
        return $GIT_ERROR
    fi

    # Push with authentication token using safe push
    if ! safe_git_push "$BUILD_SOURCEBRANCHNAME" "$SYSTEM_ACCESSTOKEN" 1; then
        echo "##vso[task.logissue type=error]Failed to push changes to the repository."
        log_error "Failed to push changes to repository"
        return $GIT_ERROR
    fi

    log_info "Changes committed and pushed successfully"
    return $SUCCESS
}

#==============================================================================
# Enhanced Git Operations
#==============================================================================

function resolve_git_conflicts() {
    local branch="$1"

    log_info "Attempting to resolve git conflicts for branch: $branch"

    # Check if there are conflicts
    if git status --porcelain | grep -q "^UU"; then
        log_warn "Merge conflicts detected, attempting automatic resolution"

        # For automated pipeline scenarios, we'll favor remote changes
        # This is a conservative approach for CI/CD environments
        git checkout --theirs .
        git add .

        if git commit -m "Automated conflict resolution - favoring remote changes [skip ci]"; then
            log_info "Conflicts resolved automatically"
            return $SUCCESS
        else
            log_error "Failed to resolve conflicts automatically"
            return $GIT_ERROR
        fi
    fi

    return $SUCCESS
}

function safe_git_pull() {
    local branch="$1"
    local max_attempts="${2:-$GIT_MAX_RETRIES}"

    log_info "Performing safe git pull for branch: $branch"

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Git pull attempt $attempt/$max_attempts"

        if git pull origin "$branch"; then
            log_info "Git pull successful on attempt $attempt"
            return $SUCCESS
        else
            log_warn "Git pull failed on attempt $attempt"

            # Try to resolve conflicts
            if resolve_git_conflicts "$branch"; then
                log_info "Conflicts resolved, retrying pull"
                continue
            fi

            ((attempt++))
            if [[ $attempt -le $max_attempts ]]; then
                log_info "Retrying git pull in ${GIT_RETRY_DELAY}s..."
                sleep "$GIT_RETRY_DELAY"
            fi
        fi
    done

    log_error "Git pull failed after $max_attempts attempts"
    return $GIT_ERROR
}

function safe_git_push() {
    local branch="$1"
    local token="$2"
    local max_attempts="${3:-$GIT_MAX_RETRIES}"

    log_info "Performing safe git push for branch: $branch"

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Git push attempt $attempt/$max_attempts"

        # Use force-with-lease for safety
        if git -c http.extraheader="AUTHORIZATION: bearer $token" push --set-upstream origin "$branch" --force-with-lease; then
            log_info "Git push successful on attempt $attempt"
            return $SUCCESS
        else
            log_warn "Git push failed on attempt $attempt"

            # Pull latest changes and retry
            if safe_git_pull "$branch" 1; then
                log_info "Pulled latest changes, retrying push"
                ((attempt++))
                if [[ $attempt -le $max_attempts ]]; then
                    sleep "$GIT_RETRY_DELAY"
                fi
                continue
            fi

            ((attempt++))
            if [[ $attempt -le $max_attempts ]]; then
                log_info "Retrying git push in ${GIT_RETRY_DELAY}s..."
                sleep "$GIT_RETRY_DELAY"
            fi
        fi
    done

    log_error "Git push failed after $max_attempts attempts"
    return $GIT_ERROR
}

function execute_secure_git_checkout() {
    local branch="$1"

    log_info "Executing secure git checkout for branch: $branch"

    # Checkout branch with error handling
    if ! git checkout -q "$branch"; then
        display_error "Git Checkout" "Failed to checkout branch: $branch" "$GIT_ERROR"
        return $GIT_ERROR
    fi

    log_info "Git checkout completed successfully"
    return $SUCCESS
}

function setup_git_credentials() {
    local user_name="$1"
    local user_email="$2"

    log_info "Setting up git credentials for pipeline"

    if [[ -n "$user_name" ]]; then
        git config --global user.name "$user_name"
        log_debug "Git user name set to: $user_name"
    fi

    if [[ -n "$user_email" ]]; then
        git config --global user.email "$user_email"
        log_debug "Git user email set to: $user_email"
    fi

    # Configure git for pipeline use
    git config --global push.default simple
    git config --global pull.rebase false

    return $SUCCESS
}

function cleanup_git_credentials() {
    log_info "Cleaning up git credentials"

    git config --global --unset user.name 2>/dev/null || true
    git config --global --unset user.email 2>/dev/null || true
    git config --global --unset push.default 2>/dev/null || true
    git config --global --unset pull.rebase 2>/dev/null || true

    return $SUCCESS
}

function validate_git_repository() {
    log_info "Validating git repository state"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir &>/dev/null; then
        log_error "Not in a git repository"
        return $GIT_ERROR
    fi

    # Check if repository has uncommitted changes that might conflict
    if git status --porcelain | grep -q "^M"; then
        log_warn "Repository has uncommitted changes"
        return $GIT_WARNING
    fi

    # Check if repository is in a clean state
    if ! git status --porcelain | grep -q .; then
        log_debug "Repository is in clean state"
    fi

    return $SUCCESS
}

function create_git_backup() {
    local backup_name="$1"

    log_info "Creating git backup: $backup_name"

    # Create a backup branch
    if git branch "$backup_name" 2>/dev/null; then
        log_info "Backup branch created: $backup_name"
        return $SUCCESS
    else
        log_warn "Failed to create backup branch: $backup_name"
        return $GIT_WARNING
    fi
}

function restore_git_backup() {
    local backup_name="$1"

    log_info "Restoring from git backup: $backup_name"

    # Check if backup branch exists
    if git show-ref --verify --quiet "refs/heads/$backup_name"; then
        if git checkout "$backup_name"; then
            log_info "Restored from backup: $backup_name"
            return $SUCCESS
        else
            log_error "Failed to restore from backup: $backup_name"
            return $GIT_ERROR
        fi
    else
        log_error "Backup branch not found: $backup_name"
        return $GIT_ERROR
    fi
}

function cleanup_git_backups() {
    local backup_pattern="$1"

    log_info "Cleaning up git backups matching pattern: $backup_pattern"

    # Find and delete backup branches
    local backup_branches
    backup_branches=$(git branch | grep "$backup_pattern" | xargs)

    if [[ -n "$backup_branches" ]]; then
        for branch in $backup_branches; do
            if git branch -D "$branch" 2>/dev/null; then
                log_debug "Deleted backup branch: $branch"
            fi
        done
    fi

    return $SUCCESS
}
