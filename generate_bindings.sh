#!/bin/bash
# =========================================================================================
# FINAL CORRECTED Multi-Compiler Go Bindings Generator
#
# This version fixes the `Unimplemented feature` compiler error by removing the
# `--via-ir` flag. The IR pipeline is not compatible with all dependencies,
# and removing it forces Foundry to use the stable, legacy compilation path.
# =========================================================================================

set -e
set -o pipefail

# --- Configuration ---
FOUNDRY_PROJECT_ROOT="smart-contracts"
BINDINGS_DIR="bot/contracts/bindings"
TEMP_ARCHIVE_DIR="temp_build_archive"

# --- Safety Cleanup ---
trap cleanup EXIT

# --- Main ---
main() {
    echo "Starting robust multi-compiler bindings generation..."

    # 1. Setup
    rm -rf "$BINDINGS_DIR" "$TEMP_ARCHIVE_DIR"
    mkdir -p "$BINDINGS_DIR" "$TEMP_ARCHIVE_DIR"
    mv "$FOUNDRY_PROJECT_ROOT/foundry.toml" "$FOUNDRY_PROJECT_ROOT/foundry.toml.bak"
    echo "✅ Backed up original foundry.toml"

    # 2. Build for each required solc version
    build_for_version "0.8.28" "script/Bindings-0.8.sol"
    build_for_version "0.7.6"  "script/Bindings-0.7.sol"

    # 3. Generate bindings from all archived artifacts
    generate_all_bindings

    echo ""
    echo "✅ All Go bindings generated successfully."
}

# --- Build & Archive Function ---
build_for_version() {
    local solc_version="$1"
    local target_script="$2"
    local archive_path="${TEMP_ARCHIVE_DIR}/v${solc_version}"

    echo ""
    echo "--- Building for solc v${solc_version} targeting ${target_script} ---"

    # Create a temporary toml by copying the backup and replacing the solc version
    sed "s/^solc = .*/solc = \"${solc_version}\"/" "$FOUNDRY_PROJECT_ROOT/foundry.toml.bak" > "$FOUNDRY_PROJECT_ROOT/foundry.toml"

    echo "   - Running 'forge build' (without IR pipeline)..."
    (
        cd "$FOUNDRY_PROJECT_ROOT"
        # THE FIX: Removed --via-ir to use the more stable legacy compiler pipeline.
        forge build "$target_script" --force
    )
    echo "   - ✅ Compilation successful."

    # Archive results
    mkdir -p "$archive_path"
    mv "$FOUNDRY_PROJECT_ROOT/out" "$archive_path/"
    echo "   - Archived artifacts to ${archive_path}/out"
    (cd "$FOUNDRY_PROJECT_ROOT" && forge clean >/dev/null 2>&1)
}

# --- Abigen Function ---
generate_all_bindings() {
    echo ""
    echo "--- Generating Go bindings from all archived artifacts... ---"
    find "$TEMP_ARCHIVE_DIR" -type f -name "*.json" ! -name "*.dbg.json" ! -path "*.t.sol/*" | while IFS= read -r artifact; do
        local contract_name=$(basename "$artifact" .json)
        local pkg_name=$(echo "$contract_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]//g')
        local out_dir="${BINDINGS_DIR}/${pkg_name}"
        
        if [ -d "$out_dir" ]; then continue; fi
        mkdir -p "$out_dir"
        
        echo "  -> Generating for ${contract_name}"
        
        local abi_data; abi_data=$(jq .abi "$artifact")
        local bin_data; bin_data=$(jq -r .bytecode.object "$artifact")
        
        local cmd="abigen --pkg \"${pkg_name}\" --type \"${contract_name}\" --out \"${out_dir}/${pkg_name}.go\""
        cmd+=" --abi <(echo '${abi_data}')"
        if [[ -n "$bin_data" && "$bin_data" != "null" ]]; then
            cmd+=" --bin <(echo '${bin_data}')"
        fi

        eval "$cmd" 2>/dev/null || echo "   - ⚠️  abigen failed for ${contract_name}. Might be an interface. Skipping."
    done
}

# --- Cleanup Function ---
cleanup() {
    echo ""
    echo "--- Cleaning up... ---"
    if [ -f "$FOUNDRY_PROJECT_ROOT/foundry.toml.bak" ]; then
        mv "$FOUNDRY_PROJECT_ROOT/foundry.toml.bak" "$FOUNDRY_PROJECT_ROOT/foundry.toml"
        echo "✅ Restored original foundry.toml"
    fi
    rm -rf "$TEMP_ARCHIVE_DIR"
    echo "✅ Removed temporary build archive."
}

# --- Run ---main "$@"
