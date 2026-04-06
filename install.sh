#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
DEST_DIR="${HOME}/.config/opencode"
for f in "${SCRIPT_DIR}/map-models.json" "${SCRIPT_DIR}/map-models.jsonc"; do
	if [[ -f "$f" ]]; then
		CONFIG_FILE="$f"
		break
	fi
done
if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "Error: Config file not found (looked for map-models.json and map-models.jsonc)"
	exit 1
fi
DRY_RUN=false
VALIDATE_ONLY=false
LIST_ONLY=false
AVAILABLE_MODELS=""
MODEL_VALIDATED=0

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
			CONFIG_FILE="$2"
			shift 2
			;;
		-h | --help)
			usage
			;;
		*)
			echo "Unknown option: $1"
			usage
			;;
		esac
	done
}

check_opencode() {
	if ! command -v opencode &>/dev/null; then
		echo "Error: 'opencode' command not found in PATH"
		echo "Please install opencode or add it to your PATH"
		exit 1
	fi
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
		echo "Error: Config file not found: $file"
		exit 1
	fi

	if command -v python3 &>/dev/null; then
		python3 <<EOF
import json
print(json.dumps(json.loads(open("$file").read())))
EOF
	elif command -v python &>/dev/null; then
		python <<EOF
import json
print(json.dumps(json.loads(open("$file").read())))
EOF
	else
		sed 's|^[[:space:]]*//.*||g' "$file" | sed 's|/\*.*\*/||g'
	fi
}

get_config_for_agent() {
	local agent="$1"
	local json_content
	json_content=$(parse_jsonc "$CONFIG_FILE")

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
	grep -m1 '^name:' "$file" | sed 's/^name:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true
}

extract_model_from_file() {
	local file="$1"
	grep -m1 '^model:' "$file" | sed 's/^model:[[:space:]]*//' || true
}

extract_temperature_from_file() {
	local file="$1"
	grep -m1 '^temperature:' "$file" | sed 's/^temperature:[[:space:]]*//' || true
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
	json_content=$(parse_jsonc "$CONFIG_FILE")

	echo "Validating models from: $CONFIG_FILE"
	echo ""

	local agents
	agents=$(echo "$json_content" | jq -r 'keys | map(select(. != "$schema"))[]' 2>/dev/null || true)

	if [[ -z "$agents" ]]; then
		echo "Error: No agents found in config file"
		exit 1
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
			((invalid_models++))
		fi
	done

	echo ""
	if [[ $invalid_models -gt 0 ]]; then
		echo "Error: $invalid_models invalid model(s) found."
		exit 1
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
		mkdir -p "$(dirname "$dest_file")"

		local agent_name
		agent_name=$(extract_name_from_file "$file")

		local temp_content
		temp_content=$(cat "$file")

		if [[ -n "$agent_name" ]]; then
			local config
			config=$(get_config_for_agent "$agent_name") || true

			if [[ -n "$config" ]]; then
				local new_model new_temp
				IFS='|' read -r new_model new_temp <<<"$config"

				local old_model old_temp
				old_model=$(extract_model_from_file "$file")
				old_temp=$(extract_temperature_from_file "$file")

				if [[ "$old_model" != "$new_model" ]]; then
					temp_content=$(echo "$temp_content" | sed "s|^model:.*|model: $new_model|")
				fi

				if [[ -n "$new_temp" && "$new_temp" != "null" && -n "$old_temp" ]]; then
					if [[ "$old_temp" != "$new_temp" ]]; then
						temp_content=$(echo "$temp_content" | sed "s|^temperature:.*|temperature: $new_temp|")
					fi
				fi
			fi
		fi

		printf '%s\n' "$temp_content" >"$dest_file"
		echo "  ✓ $rel_path"
	done < <(find "$SRC_DIR" -name '*.md' -print0 2>/dev/null || true)
}

confirm_install() {
	echo "This will install configuration to: $DEST_DIR"
	echo ""
	read -p "Do you want to continue? [y/N] " -n 1 -r
	echo ""
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "Installation cancelled."
		exit 0
	fi
}

main() {
	parse_args "$@"

	if [[ ! -d "$SRC_DIR" ]]; then
		echo "Error: Source directory not found: $SRC_DIR"
		exit 1
	fi

	if [[ "$LIST_ONLY" == true ]]; then
		list_src_models
		exit 0
	fi

	check_opencode

	if [[ "$VALIDATE_ONLY" == true ]]; then
		validate_all_models
		exit 0
	fi

	if [[ "$DRY_RUN" == true ]]; then
		validate_all_models
		echo ""
		dry_run
		exit 0
	fi

	validate_all_models
	echo ""
	confirm_install
	install_files
}

main "$@"
