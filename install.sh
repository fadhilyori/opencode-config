#!/bin/bash
set -euo pipefail

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_ARGS=1
readonly EXIT_MISSING_DEPENDENCY=2
readonly EXIT_VALIDATION_ERROR=3
readonly EXIT_FILE_ERROR=4
readonly EXIT_CONFIG_ERROR=5
readonly EXIT_USER_CANCEL=6

# Error reporting helper
error_exit() {
	local code="$1"
	local message="$2"
	echo "Error: $message" >&2
	exit "$code"
}

# Temp file tracking for cleanup
TEMP_FILES=()

cleanup() {
	local tmp
	for tmp in "${TEMP_FILES[@]}"; do
		[[ -f "$tmp" ]] && rm -f "$tmp"
	done
}

trap cleanup EXIT INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
# Resolve DEST_DIR to canonical path (follows symlinks)
DEST_DIR="$(realpath "${HOME}/.config/opencode" 2>/dev/null || echo "${HOME}/.config/opencode")"
for f in "${SCRIPT_DIR}/map-models.json" "${SCRIPT_DIR}/map-models.jsonc"; do
	if [[ -f "$f" ]]; then
		CONFIG_FILE="$f"
		break
	fi
done
if [[ ! -f "$CONFIG_FILE" ]]; then
	error_exit "$EXIT_CONFIG_ERROR" "Config file not found (looked for map-models.json and map-models.jsonc)"
fi
DRY_RUN=false
VALIDATE_ONLY=false
LIST_ONLY=false
SKIP_CONFIRM=false
AVAILABLE_MODELS=""
MODEL_VALIDATED=0
ORPHANED_FILES=""
CACHED_JSON_CONTENT=""

fetch_models_once() {
	if [[ -z "$AVAILABLE_MODELS" ]]; then
		AVAILABLE_MODELS=$(opencode models 2>/dev/null | grep -oE '[^[:space:]]+/[^[:space:]]+' | sort -u || true)
	fi
}

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    --dry-run       Preview changes without executing
    --validate      Only validate models without installing
    --list          List current models from src files
    --config FILE   Use specified config file (default: ./map-models.json[.c])
    -y, --yes       Skip all confirmations
    -h, --help      Show this help message

Installs opencode configuration by copying files from src/ to ~/.config/opencode/,
replacing model names according to map-models.jsonc.

Examples:
    $(basename "$0") --list
    $(basename "$0") --validate
    $(basename "$0") --dry-run
    $(basename "$0")
EOF
	exit 0
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case $1 in
		--dry-run)
			DRY_RUN=true
			shift
			;;
		--validate)
			VALIDATE_ONLY=true
			shift
			;;
		--list)
			LIST_ONLY=true
			shift
			;;
		--config)
			if [[ -z "$2" ]] || [[ "$2" == --* ]]; then
				error_exit "$EXIT_INVALID_ARGS" "--config requires a file path"
			fi
			if [[ ! -f "$2" ]]; then
				error_exit "$EXIT_FILE_ERROR" "Config file not found: $2"
			fi
			if [[ "$2" == *".."* ]]; then
				error_exit "$EXIT_INVALID_ARGS" "Invalid path: $2 (contains ..)"
			fi
			if [[ "$2" =~ [[:cntrl:]] ]]; then
				error_exit "$EXIT_INVALID_ARGS" "Invalid path: $2 (contains control characters)"
			fi
			# Validate config content
			validate_config_content "$2"
			CONFIG_FILE="$2"
			shift 2
			;;
		-h | --help)
			usage
			;;
		-y | --yes)
			SKIP_CONFIRM=true
			shift
			;;
		*)
			error_exit "$EXIT_INVALID_ARGS" "Unknown option: $1"
			;;
		esac
	done
}

check_dependencies() {
	local missing_deps=()

	if ! command -v opencode &>/dev/null; then
		missing_deps+=("opencode")
	fi

	if ! command -v jq &>/dev/null; then
		missing_deps+=("jq")
	fi

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "Error: Missing required dependencies:" >&2
		printf '  - %s\n' "${missing_deps[@]}" >&2
		exit "$EXIT_MISSING_DEPENDENCY"
	fi

	# Check for Python (optional but recommended for JSONC comment handling)
	local has_json_parser=false
	if command -v python3 &>/dev/null || command -v python &>/dev/null; then
		has_json_parser=true
	fi

	if [[ "$has_json_parser" == false ]]; then
		echo "Warning: Python not found. JSONC comment stripping will use basic sed (may fail on complex comments)" >&2
		echo "         Install Python for full JSONC support" >&2
	fi
}

validate_path_safety() {
	local path="$1"

	# Check for path traversal
	if [[ "$path" == *".."* ]]; then
		return 1
	fi

	# Check for control characters
	if [[ "$path" =~ [[:cntrl:]] ]]; then
		return 1
	fi

	return 0
}

validate_config_content() {
	local file="$1"

	# Basic JSON structure validation
	if ! jq empty "$file" 2>/dev/null; then
		error_exit "$EXIT_VALIDATION_ERROR" "Invalid JSON in config file: $file"
	fi

	# Check for at least one agent definition
	local agent_count
	agent_count=$(jq 'keys | length' "$file" 2>/dev/null || echo "0")

	if [[ "$agent_count" -lt 1 ]]; then
		error_exit "$EXIT_VALIDATION_ERROR" "No agents defined in config file: $file"
	fi

	return 0
}

validate_model() {
	local model="$1"

	if echo "$AVAILABLE_MODELS" | grep -qxF "$model"; then
		return 0
	fi
	return 1
}

parse_jsonc() {
	local file="$1"
	if [[ ! -f "$file" ]]; then
		error_exit "$EXIT_FILE_ERROR" "Config file not found: $file"
	fi

	if [[ ! -r "$file" ]]; then
		error_exit "$EXIT_FILE_ERROR" "Config file not readable: $file"
	fi

	# Use command-line argument instead of heredoc to prevent injection
	if command -v python3 &>/dev/null; then
		python3 -c 'import json, sys; print(json.dumps(json.loads(open(sys.argv[1]).read())))' "$file"
	elif command -v python &>/dev/null; then
		python -c 'import json, sys; print(json.dumps(json.loads(open(sys.argv[1]).read())))' "$file"
	else
		# Fallback: remove single-line and multi-line comments
		sed 's|^[[:space:]]*//.*||g' "$file" | sed 's|/\*.*\*/||g'
	fi
}

get_json_content() {
	if [[ -z "$CACHED_JSON_CONTENT" ]]; then
		CACHED_JSON_CONTENT=$(parse_jsonc "$CONFIG_FILE")
	fi
	echo "$CACHED_JSON_CONTENT"
}

clear_json_cache() {
	CACHED_JSON_CONTENT=""
}

get_config_for_agent() {
	local agent="$1"
	local json_content
	json_content=$(get_json_content)

	local model temp
	model=$(echo "$json_content" | jq -r ".${agent}.model // empty" 2>/dev/null || true)
	temp=$(echo "$json_content" | jq -r ".${agent}.temperature // empty" 2>/dev/null || true)

	if [[ -z "$model" ]]; then
		return 1
	fi

	echo "${model}|${temp}"
}

extract_name_from_file() {
	local file="$1"
	awk '/^name:/ {$1=""; print tolower(substr($0,2)); exit}' "$file"
}

extract_model_from_file() {
	local file="$1"
	awk '/^model:/ {$1=""; print substr($0,2); exit}' "$file"
}

extract_temperature_from_file() {
	local file="$1"
	awk '/^temperature:/ {$1=""; print substr($0,2); exit}' "$file"
}

extract_agent_metadata() {
	local file="$1"
	awk '
		/^name:/ {
			$1=""
			name=tolower(substr($0,2))
		}
		/^model:/ {
			$1=""
			model=substr($0,2)
		}
		/^temperature:/ {
			$1=""
			temp=substr($0,2)
		}
		END {
			print name "|" model "|" temp
		}
	' "$file"
}

normalize_value() {
	local value="$1"
	# Trim whitespace
	value=$(echo "$value" | tr -d '[:space:]')
	# Normalize null/empty
	if [[ -z "$value" || "$value" == "null" ]]; then
		echo ""
	else
		echo "$value"
	fi
}

compare_temperature() {
	local old_temp="$1"
	local new_temp="$2"

	local norm_old norm_new
	norm_old=$(normalize_value "$old_temp")
	norm_new=$(normalize_value "$new_temp")

	# Both empty/null means same
	if [[ -z "$norm_old" && -z "$norm_new" ]]; then
		return 0
	fi

	# One empty, one not - different
	if [[ -z "$norm_old" || -z "$norm_new" ]]; then
		return 1
	fi

	# Both have values - compare
	[[ "$norm_old" == "$norm_new" ]]
	return $?
}

list_src_models() {
	echo "Current model configuration in src/:"
	echo ""

	local seen_agents=()
	local agent model temp

	while IFS= read -r -d '' file; do
		agent=$(extract_name_from_file "$file")
		if [[ -z "$agent" ]]; then
			continue
		fi

		if [[ " ${seen_agents[*]} " =~ " ${agent} " ]]; then
			continue
		fi
		seen_agents+=("$agent")

		model=$(extract_model_from_file "$file")
		temp=$(extract_temperature_from_file "$file")

		local config
		config=$(get_config_for_agent "$agent") || true

		local configured_model configured_temp="(not defined)"
		if [[ -n "$config" ]]; then
			IFS='|' read -r configured_model configured_temp <<<"$config"
		else
			configured_model="(no config)"
		fi

		echo "Agent: $agent"
		echo "  File:        ${file#$SRC_DIR/}"
		echo "  Source:      model=$model, temp=$temp"
		echo "  Configured:  model=$configured_model, temp=$configured_temp"
		echo ""

	done < <(find "$SRC_DIR/agent" -name '*.md' -print0 2>/dev/null || true)
}

validate_all_models() {
	fetch_models_once

	local json_content invalid_models=0
	json_content=$(get_json_content)

	echo "Validating models from: $CONFIG_FILE"
	echo ""

	local agents
	agents=$(echo "$json_content" | jq -r 'keys | map(select(. != "$schema"))[]' 2>/dev/null || true)

	if [[ -z "$agents" ]]; then
		error_exit "$EXIT_VALIDATION_ERROR" "No agents found in config file"
	fi

	for agent in $agents; do
		local config
		config=$(get_config_for_agent "$agent")
		local model temp
		IFS='|' read -r model temp <<<"$config"

		if validate_model "$model"; then
			echo "✓ $agent: $model"
		else
			echo "✗ $agent: $model (not available)"
			echo "  Hint: Run 'opencode models' to see available models"
			((invalid_models++))
		fi
	done

	echo ""
	if [[ $invalid_models -gt 0 ]]; then
		error_exit "$EXIT_VALIDATION_ERROR" "$invalid_models invalid model(s) found. Run 'opencode models' to see available models."
	fi

	echo "All models validated successfully."
}

dry_run() {
	echo "Dry run - preview of changes:"
	echo ""

	local prev_group=""
	while IFS= read -r -d '' file; do
		local rel_path="${file#$SRC_DIR/}"
		local top_dir="${rel_path%%/*}"

		if [[ "$top_dir" != "$prev_group" ]]; then
			[[ -n "$prev_group" ]] && echo ""
			echo "## $top_dir"
			prev_group="$top_dir"
		fi

		echo "  ✓ $rel_path"
	done < <(find "$SRC_DIR" -name '*.md' -print0 2>/dev/null || true)
}

install_files() {
	echo "Installing to: $DEST_DIR"
	echo ""

	local prev_group=""
	while IFS= read -r -d '' file; do
		local rel_path="${file#$SRC_DIR/}"
		local top_dir="${rel_path%%/*}"

		if [[ "$top_dir" != "$prev_group" ]]; then
			[[ -n "$prev_group" ]] && echo ""
			echo "## $top_dir"
			prev_group="$top_dir"
		fi

		local dest_file="${DEST_DIR}/${rel_path}"

		# Validate path safety
		if ! validate_path_safety "$rel_path"; then
			echo "  ✗ Skipping unsafe path: $rel_path" >&2
			continue
		fi

		mkdir -p "$(dirname "$dest_file")"

		# Single-pass metadata extraction
		local metadata agent_name old_model old_temp
		metadata=$(extract_agent_metadata "$file")
		IFS='|' read -r agent_name old_model old_temp <<<"$metadata"

		local temp_content
		temp_content=$(cat "$file")

		if [[ -n "$agent_name" ]]; then
			local config
			config=$(get_config_for_agent "$agent_name") || true

			if [[ -n "$config" ]]; then
				local new_model new_temp
				IFS='|' read -r new_model new_temp <<<"$config"

				# Replace model if different
				if [[ -n "$old_model" && -n "$new_model" && "$old_model" != "$new_model" ]]; then
					temp_content=$(echo "$temp_content" | sed "s|^model:.*|model: $new_model|")
				fi

				# Replace temperature if different and valid
				if [[ -n "$new_temp" && "$new_temp" != "null" ]]; then
					if ! compare_temperature "$old_temp" "$new_temp"; then
						temp_content=$(echo "$temp_content" | sed "s|^temperature:.*|temperature: $new_temp|")
					fi
				fi
			fi
		fi

		printf '%s\n' "$temp_content" >"$dest_file"
		echo "  ✓ $rel_path"
	done < <(find "$SRC_DIR" -name '*.md' -print0 2>/dev/null || true)

	# Orphan file detection - only check subdirectories that exist in src/
	# Get list of subdirectories in src/
	local subdirs=()
	while IFS= read -r -d '' subdir; do
		subdirs+=("$(basename "$subdir")")
	done < <(find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)

	# For each subdir, find orphan files in DEST_DIR/subdir/
	local orphaned_tmp
	orphaned_tmp=$(mktemp) || error_exit "$EXIT_FILE_ERROR" "Failed to create temporary file"
	TEMP_FILES+=("$orphaned_tmp")

	for subdir in "${subdirs[@]}"; do
		# Find all .md files in DEST_DIR/subdir/ and check against SRC_DIR/subdir/
		while IFS= read -r -d '' dest_file; do
			# Get relative path from DEST_DIR
			local rel_path="${dest_file#$DEST_DIR/}"
			# Check if file exists in SRC_DIR
			local src_file="${SRC_DIR}/${rel_path}"
			if [[ ! -f "$src_file" ]]; then
				# File exists in DEST_DIR/subdir/ but not in SRC_DIR/subdir/ -> orphan
				echo "$rel_path" >>"$orphaned_tmp"
			fi
		done < <(find "$DEST_DIR/$subdir" -name '*.md' -print0 2>/dev/null || true)
	done

	ORPHANED_FILES=$(cat "$orphaned_tmp")
}

confirm_install() {
	if [[ "$SKIP_CONFIRM" == true ]]; then
		return
	fi
	echo "This will install configuration to: $DEST_DIR"
	echo ""
	read -p "Do you want to continue? [y/N] " -n 1 -r
	echo ""
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "Installation cancelled."
		exit "$EXIT_USER_CANCEL"
	fi
}

handle_orphaned_files() {
	if [[ -z "$ORPHANED_FILES" ]]; then
		return
	fi

	local count
	count=$(echo "$ORPHANED_FILES" | grep -c '^' || true)
	if [[ "$count" -eq 0 ]]; then
		return
	fi

	echo ""
	echo "Orphaned files detected ($count file(s)):"
	echo ""
	echo "$ORPHANED_FILES" | while IFS= read -r line; do
		[[ -n "$line" ]] && echo "  - $line"
	done

	if [[ "$SKIP_CONFIRM" == true ]]; then
		echo ""
		echo "Deleting orphaned files (--yes)..."
		echo "$ORPHANED_FILES" | while IFS= read -r rel_path; do
			[[ -z "$rel_path" ]] && continue
			local dest_file="${DEST_DIR}/${rel_path}"
			if [[ -f "$dest_file" ]]; then
				rm "$dest_file"
				echo "  removed: $rel_path"
			fi
		done
		echo "Orphaned files removed."
		return
	fi

	echo ""
	read -p "Delete these orphaned files? [y/N] " -n 1 -r
	echo ""
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "Orphaned files kept."
		return
	fi

	echo "$ORPHANED_FILES" | while IFS= read -r rel_path; do
		[[ -z "$rel_path" ]] && continue
		local dest_file="${DEST_DIR}/${rel_path}"
		if [[ -f "$dest_file" ]]; then
			rm "$dest_file"
			echo "  removed: $rel_path"
		fi
	done
	echo "Orphaned files removed."
}

main() {
	parse_args "$@"

	if [[ ! -d "$SRC_DIR" ]]; then
		error_exit "$EXIT_FILE_ERROR" "Source directory not found: $SRC_DIR"
	fi

	if [[ "$LIST_ONLY" == true ]]; then
		list_src_models
		exit "$EXIT_SUCCESS"
	fi

	check_dependencies

	if [[ "$VALIDATE_ONLY" == true ]]; then
		validate_all_models
		exit "$EXIT_SUCCESS"
	fi

	if [[ "$DRY_RUN" == true ]]; then
		validate_all_models
		echo ""
		dry_run
		exit "$EXIT_SUCCESS"
	fi

	validate_all_models
	echo ""
	confirm_install
	install_files
	handle_orphaned_files
}

main "$@"
