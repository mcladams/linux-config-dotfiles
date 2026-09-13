# git-utils.sh
# Cohesive Git utility kit for independent professionals.
# Source this file inside your ~/.bashrc or ~/.bash_aliases

# ------------------------------------------------------------------------------
# 1. Internal Log Engine & Color Definitions
# ------------------------------------------------------------------------------
_git_log_init() {
  # Only output ANSI colors if Stderr is a live interactive TTY stream
  if [[ -t 2 ]]; then
    _G_CLR_BRED='\033[1;31m'
    _G_CLR_BGREEN='\033[1;32m'
    _G_CLR_BYELLOW='\033[1;33m'
    _G_CLR_BOLD='\033[1m'
    _G_CLR_NC='\033[0m'
  else
    _G_CLR_BRED='' _G_CLR_BGREEN='' _G_CLR_BYELLOW='' _G_CLR_BOLD='' _G_CLR_NC=''
  fi
}
_git_log_init

_git_log_info()  { printf "[${_G_CLR_BGREEN}+${_G_CLR_NC}] INFO: %s\n' "$*" >&2; }
_git_log_warn()  { printf "[${_G_CLR_BYELLOW}*${_G_CLR_NC}] ${_G_CLR_BYELLOW}WARNING:${_G_CLR_NC} %s\n" "$*" >&2; }
_git_log_error() { printf "[${_G_CLR_BRED}!${_G_CLR_NC}] ${_G_CLR_BOLD}ERROR:${_G_CLR_NC} %s\n" "$*" >&2; }
_git_log_debug() {
  [[ "${VERBOSE:-0}" -eq 1 ]] || return 0
  printf "[${_G_CLR_BOLD}?${_G_CLR_NC}] DEBUG: %s\n" "$*" >&2
}

# ------------------------------------------------------------------------------
# 2. Forge & Platform Abstraction Layer
# ------------------------------------------------------------------------------
_git_host_detect() {
  local -r repo_url="$1"
  case "$repo_url" in
    *github.com*) echo "github" ;;
    *gitlab.com*) echo "gitlab" ;;
    *)            echo "unknown" ;;
  case
}

_git_host_raw_url() {
  local -r host="$1"
  local -r repo_url="$2"
  local -r branch="$3"
  local -r path="$4"

  local clean_url="${repo_url%.git}"
  
  if [[ "$host" == "github" ]]; then
    local repo_slug="${clean_url#https://github.com/}"
    echo "https://raw.githubusercontent.com/${repo_slug}/${branch}/${path}"
  elif [[ "$host" == "gitlab" ]]; then
    echo "${clean_url}/-/raw/${branch}/${path}"
  else
    return 1
  fi
}

# ------------------------------------------------------------------------------
# 3. Private Structural Context Guards
# ------------------------------------------------------------------------------
_git_require_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    _git_log_error "Command requires a valid git repository environment context."
    return 1
  }
}

# ------------------------------------------------------------------------------
# 4. Public API - Repository Read-Only Information
# ------------------------------------------------------------------------------
git_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || return 1
}

git_repo_default_branch() {
  local -r repo_url="${1:?Repository HTTPS tracking source URL required}"
  git ls-remote --symref "$repo_url" HEAD 2>/dev/null | \
    awk '/^ref:/ { sub("refs/heads/", "", $2); print $2 }'
}

git_branch_current() {
  git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

git_branch_exists() {
  local -r target_branch="${1:?Target branch name target parameter required}"
  git show-ref --verify --quiet "refs/heads/${target_branch}"
}

git_status_dirty() {
  _git_require_repo || return 1
  [[ -n "$(git status --porcelain 2>/dev/null)" ]]
}

# ------------------------------------------------------------------------------
# 5. Public API - Modifying & Cloning Engine
# ------------------------------------------------------------------------------
git_clone_sparse() {
  local repo="" path="" output="" branch="" Help=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)   repo="$2"; shift 2 ;;
      --path)   path="$2"; shift 2 ;;
      --output) output="$2"; shift 2 ;;
      --branch) branch="$2"; shift 2 ;;
      --help)   Help=1; shift ;;
      *)        _git_log_error "Unknown parameter string identifier: $1"; return 1 ;;
    esac
  done

  if [[ "$Help" -eq 1 || -z "$repo" || -z "$path" ]]; then
    printf "Usage: git_clone_sparse --repo URL --path PATH [--output DIR] [--branch NAME]\n"
    return 0
  fi

  [[ -z "$output" ]] && output="${path##*/}"
  [[ -z "$branch" ]] && branch=$(git_repo_default_branch "$repo")
  branch="${branch:-main}"

  _git_log_info "Initializing context sparse tracking repository branch allocation..."
  git clone --filter=blob:none --no-checkout --depth=1 --branch "$branch" "$repo" "$output" || return 1
  
  (
    cd "$output" || exit 1
    git sparse-checkout set "$path"
    git checkout "$branch"
  )
}

# ------------------------------------------------------------------------------
# 6. Public API - Destructive Capabilities (Vendor Engine)
# ------------------------------------------------------------------------------
git_vendor_tree() {
  local repo="" path="" output="" branch="" force=0 Help=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)   repo="$2"; shift 2 ;;
      --path)   path="$2"; shift 2 ;;
      --output) output="$2"; shift 2 ;;
      --branch) branch="$2"; shift 2 ;;
      --force)  force=1; shift ;;
      --help)   Help=1; shift ;;
      *)        _git_log_error "Unknown validation argument option parsed: $1"; return 1 ;;
    esac
  done

  if [[ "$Help" -eq 1 || -z "$repo" || -z "$path" ]]; then
    printf "Usage: git_vendor_tree --repo URL --path REMOTE_PATH [--output DIR] [--branch NAME] [--force]\n"
    printf "Note: Content extraction flattens tree directories down directly into execution destination.\n"
    return 0
  fi

  [[ -z "$output" ]] && output="${path##*/}"
  [[ -z "$branch" ]] && branch=$(git_repo_default_branch "$repo")
  branch="${branch:-main}"

  # Safe enforcement check against target directory paths
  if [[ -d "$output" && "$force" -eq 0 ]]; then
    _git_log_error "Destination target directory '$output' already exists. Aborting execution."
    _git_log_warn "Rerun operation including trailing --force flag arguments to explicitly override protection targets."
    return 1
  fi

  local -r host_profile=$(_git_host_detect "$repo")
  _git_log_info "Vendoring capability module asset structure into path: $output"
  
  rm -rf "$output"
  mkdir -p "$output"

  (
    cd "$output" || exit 1

    # 1. Fetch Remote Licenses via Abstraction Engine
    if [[ "$host_profile" != "unknown" ]]; then
      _git_log_debug "Querying asset host layout profiles..."
      for license_name in LICENSE LICENSE.md LICENSE.txt; do
        local url
        url=$(_git_host_raw_url "$host_profile" "$repo" "$branch" "$license_name")
        if curl -fsSLo "$license_name" "$url" 2>/dev/null; then
          _git_log_debug "Successfully locked asset license: $license_name"
          break
        fi
      done
    fi

    # 2. Modern Sparse Tracking Initialization
    git init -q
    git remote add origin "$repo"
    git config core.sparseCheckout true
    git sparse-checkout set "$path"

    # 3. Pull Blobless Assets
    git fetch --depth=1 --filter=blob:none origin "$branch" 2>/dev/null
    git checkout "$branch" 2>/dev/null

    # 4. Flatten Structure Processing Execution
    if [[ -d "$path" ]]; then
      find "$path" -mindepth 1 -maxdepth 1 -exec mv {} . \;
      local remote_top="${path%%/*}"
      rm -rf "$remote_top"
    fi

    # 5. Drop Tracking Wrappers
    rm -rf .git

    # 6. Structured Provenance File Delivery
    {
      echo "Repository : $repo"
      echo "Directory  : $path"
      echo "Branch     : $branch"
      echo "Retrieved  : $(date --iso-8601=seconds)"
      echo ""
      echo "LICENSE extracted directly from target upstream origin infrastructure."
    } > .provenance
  )

  _git_log_info "Pristine code block extracted securely into target path '$output'."
}
