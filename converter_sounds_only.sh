#!/usr/bin/env bash
: ${1?'Please specify the input Java Resource Pack file (e.g., ./converter_sound.sh MyResourcePack.zip)'}

# --- [ V37 DEBUG SETUP ] ---
DEBUG_MODE=true
DEBUG_LOG_FILE="./target/debug.log"

# 1. Create target folder (and ensure it exists for the log file)
mkdir -p target
# 2. Redirect all shell error output (including set -x trace) to the log file permanently.
exec 2>> "$DEBUG_LOG_FILE" 
# 3. Write start message and enable trace (both now go ONLY to the log file).
printf "[INFO] DEBUG MODE START (V37). Final Logic: Correct Key Namespace & Full Path Structure (Added RP Root 'sounds/' prefix). Full trace redirected to %s\n" "$DEBUG_LOG_FILE"
set -x 
# ---------------------------

# define color placeholders for status messages
C_RED='\e[31m'
C_GREEN='\e[32m'
C_YELLOW='\e[33m'
C_BLUE='\e[36m'
C_GRAY='\e[37m'
C_CLOSE='\e[m'

# --- [ Universal CPU Core Command Detection ] ---
case "$(uname -s)" in
    Darwin*)
        CPU_CORE_CMD="sysctl -n hw.ncpu"
        ;;\
    *|*)\
        CPU_CORE_CMD="nproc"
        if ! command -v nproc &> /dev/null; then
            CPU_CORE_CMD="echo 1"
        fi
        ;;\
esac
export CPU_CORE_CMD
# ------------------------------------------------

# status message function
status_message () {
  local type="$1"
  local message="$2"
  
  # 1. Log to DEBUG_LOG_FILE
  if [ "$DEBUG_MODE" = "true" ] && [ "$type" != "plain" ]; then
      printf "[%s] %s\n" "$(echo "$type" | tr '[:lower:]' '[:upper:]')" "$message" >> "$DEBUG_LOG_FILE"
  fi
  
  # 2. Print to Console (stdout) for user visibility
  case "$type" in
    "completion")
      printf "${C_GREEN}[+] ${C_GRAY}${message}${C_CLOSE}\n" 
      ;;\
    "process")
      printf "${C_YELLOW}[•] ${C_GRAY}${message}${C_CLOSE}\n" 
      ;;\
    "error")
      printf "${C_RED}[ERROR] ${C_GRAY}${message}${C_CLOSE}\n" 
      { set +x; printf "[ERROR] Script failed. Trace stopped.\n" >> "$DEBUG_LOG_FILE"; } 
      exit 1 
      ;;\
    "info")
      if [ "$DEBUG_MODE" != "true" ]; then
          printf "${C_BLUE}[INFO] ${C_GRAY}${message}${C_CLOSE}\n" 
      fi
      ;;\
    "plain")
      if [ "$DEBUG_MODE" != "true" ]; then
          printf "${C_GRAY}${message}${C_CLOSE}\n"
      fi
      ;;\
  esac
}

# --- [ INITIAL CLEANUP (Cleaning target sub-folders) ] ---
status_message process "Initial cleanup: Removing old assets, scratch files, and previous target sub-folders."
rm -rf assets ia_overlay_* scratch_files target/bp target/rp target/packaged target/unpackaged target/sound_paths_temp.json && rm -f pack.mcmeta pack.png config.json sprites.json default_assets.zip
# -----------------------------------------------------------------

# dependency check function (omitted for brevity)
dependency_check () {
  if command ${3} 2>/dev/null | grep -q "${4}"; then
      status_message completion "Dependency ${1} satisfied"
  else
      status_message error "Dependency ${1} must be installed to proceed\nSee ${2}"
  fi
}

# JQ version check function (omitted for brevity)
check_jq_version () {
  local program_name="$1"
  local download_link="$2"
  local min_version="1.6" 
  
  if command -v jq &> /dev/null; then
      local current_version
      current_version=$(jq --version | grep -oE '[0-9]+\.[0-9]+' | head -n 1)

      if awk -v cur="$current_version" -v min="$min_version" 'BEGIN { exit (cur >= min) ? 0 : 1 }'; then
          status_message completion "Dependency ${program_name} satisfied (v${current_version} >= v${min_version})"
      else
          status_message error "Dependency ${program_name} must be version ${min_version} or higher to proceed. Current: v${current_version}\nSee ${2}"
      fi
  else
      status_message error "Dependency ${program_name} must be installed to proceed\nSee ${2}"
  fi
}

# wait for jobs function
wait_for_jobs () {
  while test $(jobs -p | wc -w) -ge "$(echo "$((2 * $(${CPU_CORE_CMD})))")"; do wait -n; done
}

# --- [ DEPENDENCY CHECK ] ---
status_message process "Checking required dependencies: jq, sponge, and ffmpeg."
check_jq_version "jq" "https://stedolan.github.io/jq/download/"
dependency_check "sponge" "https://joeyh.name/code/moreutils/" "-v sponge" ""
dependency_check "ffmpeg" "https://ffmpeg.org/download.html" "ffmpeg -version" "ffmpeg version"
status_message completion "All required dependencies satisfied\n"
# --------------------------

# --- [ UNZIP INPUT PACK ] ---
if ! test -f "${1}"; then
   status_message error "Input resource pack ${1} is not in this directory"
fi

status_message process "Decompressing input pack ${1}"
mkdir -p target/bp target/rp
unzip -n -q "${1}"
status_message completion "Input pack decompressed"

if [ ! -f pack.mcmeta ]; then
	status_message error "Invalid resource pack! The pack.mcmeta file does not exist."
fi
# ----------------------------


# ------ [ SOUND CONVERSION FUNCTION ] ------
convert_sound_file() {
    local input_file="$1"
    local output_file="$2"
    
    local output_dir=$(dirname "$output_file")
    mkdir -p "$output_dir"
    
    # Convert audio to OGG Vorbis (quality level 4)
    ffmpeg -i "$input_file" -map 0:a -c:a libvorbis -q:a 4 "$output_file" -loglevel quiet 2> /dev/null
}
export -f convert_sound_file
# -------------------------------------------


# --- [ SOUND CONVERSION AND DEFINITION GENERATION (V37: Path Prefix Fix Applied) ] ---
status_message process "Processing Java sound files (V37: Key Namespace Fix & RP Root 'sounds/' Path Prefix Fix Applied)."

JAVA_ASSETS_ROOT="./assets" 
RP_SOUNDS_DIR="./target/rp/sounds"
TEMP_JSON_FILE="./scratch_files/sound_paths_temp.json" 

mkdir -p "$RP_SOUNDS_DIR"
mkdir -p "./scratch_files" 
echo "" > "$TEMP_JSON_FILE"

# 1. --- PROCESS ALL sounds.json FILES (SOURCE OF TRUTH) ---

find "$JAVA_ASSETS_ROOT" -type f -name "sounds.json" -print0 | while IFS= read -r -d $'\0' json_file; do
    
    # Determine the namespace from the folder structure (e.g., rpg_pet) - THIS IS THE BASE FOR THE KEY NAMESPACE
    java_folder_namespace=$(echo "$json_file" | sed -E 's/^\.\/assets\/([a-z0-9_-]+)\/sounds\.json$/\1/g')
    
    if [ "$java_folder_namespace" = "minecraft" ]; then
        status_message info "Skipping vanilla sounds.json: $json_file"
        continue
    fi
    
    if [ -z "$java_folder_namespace" ]; then
        status_message info "Warning: Could not determine namespace for sounds.json file at $json_file. Skipping."
        continue
    fi
    
    jq -c '. | to_entries[]' "$json_file" | while IFS= read -r json_entry; do
        
        java_sound_key=$(echo "$json_entry" | jq -r '.key') 
        
        echo "$json_entry" | jq -c '.value.sounds[]' | while IFS= read -r sound_path_entry; do
            
            sound_path_string=$(echo "$sound_path_entry" | jq -r 'if type == "object" then .name else . end')
            
            
            # --- PATH PARSING (Find the audio file's details) ---
            
            # path_namespace will store the namespace found in the sound path string (e.g., "pet_1" from "pet_1:...")
            path_namespace="$java_folder_namespace" 
            sound_file_path_relative_to_sounds="$sound_path_string" 
            
            # Handle namespaced paths (e.g., "pet_1:samus/rpg_pet/lightning_static")
            if [[ "$sound_path_string" == *:* ]]; then
                # path_namespace is used ONLY for searching the Java RP file location
                path_namespace=$(echo "$sound_path_string" | cut -d: -f1)
                sound_file_path_relative_to_sounds=$(echo "$sound_path_string" | cut -d: -f2)
            fi
            
            # Remove redundant namespace prefix if present (e.g., "archer/samus/...")
            if [[ "$sound_file_path_relative_to_sounds" == "$path_namespace/"* ]] && [ "$path_namespace" != "minecraft" ]; then
                sound_file_path_relative_to_sounds="${sound_file_path_relative_to_sounds#$path_namespace/}"
            fi

            path_id="$sound_file_path_relative_to_sounds"
            
            if [ -z "$path_id" ]; then
                 status_message info "Warning: path_id is empty for key $java_sound_key. Skipping."
                 continue
            fi
            
            # --- FILE FINDING (Critical for Location-Based Logic) ---
            
            # Search logic remains the same (using path_namespace derived above to find the file)
            search_path_1="$JAVA_ASSETS_ROOT/$path_namespace/sounds/$path_id"
            search_path_2="$JAVA_ASSETS_ROOT/minecraft/sounds/$path_id" 

            input_file=""
            
            # Check for the file with various extensions in both its native namespace and the 'minecraft' namespace
            for ext in ogg wav mp3; do
                if [[ -f "$search_path_1.$ext" ]]; then
                    input_file="$search_path_1.$ext"
                    break
                fi
                if [[ -f "$search_path_2.$ext" ]]; then
                    input_file="$search_path_2.$ext"
                    break
                fi
            done

            if [ -z "$input_file" ]; then
                status_message info "Warning: Could not find sound file. Searched base paths: 1) $search_path_1.* 2) $search_path_2.* (Key: $path_namespace:$java_sound_key)"
                continue
            fi


            # --- V37: NAMESPACE RESOLUTION LOGIC (Path Depth Rule & Key Fix) ---
            
            # FIX: Base the Bedrock Key Namespace on the folder where the sounds.json lives (e.g., rpg_pet), NOT the one from the sound path string (e.g., pet_1)
            bedrock_namespace_for_key="$java_folder_namespace"
            ADD_SOUNDS_SUFFIX="false"
            
            # 1. Calculate Path Depth (Number of path components: sounds/A/B/file.ogg -> Depth 3)
            # NF (Number of Fields) in awk is the depth
            depth=$(echo "$path_id" | awk -F'/' '{print NF}')
            
            # Rule 1: Special Exception for Minecraft Namespace or Misplaced Asset
            if [[ "$java_folder_namespace" == "minecraft" ]] || [[ "$input_file" == "./assets/minecraft/sounds/"* ]]; then
                # Always NO suffix for Vanilla assets (or misplaced ones)
                status_message info "Rule 1 Match: Folder Namespace is 'minecraft' or a Misplaced Asset. Depth: $depth. Skipping '_sounds' suffix."
                
            # Rule 2: Custom Namespace Logic (If not Rule 1)
            else
                if [[ "$depth" -ge 3 ]]; then
                    # Depth 3 or more (e.g., A/B/file.ogg) requires suffix
                    status_message info "Rule 2 Match: Custom Namespace. Path Depth $depth >= 3. Adding '_sounds' suffix to '$java_folder_namespace'."
                    ADD_SOUNDS_SUFFIX="true"
                else
                    # Depth 1 or 2 (e.g., file.ogg or A/file.ogg) requires NO suffix
                    status_message info "Rule 2 Match: Custom Namespace. Path Depth $depth < 3. Skipping '_sounds' suffix for '$java_folder_namespace'."
                fi
            fi
            
            # Apply suffix if flag is true
            if [[ "$ADD_SOUNDS_SUFFIX" == "true" ]]; then
                if [[ ! "$bedrock_namespace_for_key" =~ _sounds$ ]]; then
                    bedrock_namespace_for_key="${bedrock_namespace_for_key}_sounds"
                fi
            fi
            
            
            # --- V37: KEY ID PROCESSING (Verbatim Key) ---
            java_key_id_cleaned="$java_sound_key" 
            
            bedrock_sound_event_key="${bedrock_namespace_for_key}:${java_key_id_cleaned}"

            # --- FILE CONVERSION AND MAPPING (FIXED PATH) ---
            
            # FIX: The output OGG file path (where the file is physically saved) remains the same: [RP]/sounds/[Folder Namespace]/sounds/[Path ID].ogg
            output_file="$RP_SOUNDS_DIR/$java_folder_namespace/sounds/$path_id.ogg"
            
            convert_sound_file "$input_file" "$output_file" &
            wait_for_jobs 
            
            # This message appears on the CONSOLE and is logged to debug.log
            status_message process "JSON Key: ${bedrock_sound_event_key} (File: $input_file -> $output_file)"

            # FIX V37: The path in sound_definitions.json must reflect the full path from the RP root, 
            # including the top-level 'sounds/' folder, as requested by the user.
            # Expected format: sounds/[Folder Namespace]/sounds/[Path ID]
            full_sound_path_bedrock="sounds/$java_folder_namespace/sounds/$path_id" 
            
            jq -n --arg key "$bedrock_sound_event_key" --arg path "$full_sound_path_bedrock" '
            [ $key, $path ]
            ' >> "$TEMP_JSON_FILE"

        done
    done
done

wait # Wait for all background conversions from JSON processing to finish

# 2. Final JSON Assembly (Merge, Group and Create sound_definitions.json)
if [ -s "$TEMP_JSON_FILE" ]; then 
    status_message process "Generating final sound_definitions.json..."
    
    jq -s '
    {
        "format_version": "1.14.0",
        "sound_definitions": (
            group_by(.[0]) | 
            map({
                (.[0][0]): { 
                    "category": "master",
                    "sounds": (map(.[1]) | unique) 
                }
            }) |
            add 
        )
    }
    ' "$TEMP_JSON_FILE" | sponge "$RP_SOUNDS_DIR/sound_definitions.json"
    
    status_message completion "Generated ./target/rp/sounds/sound_definitions.json successfully."
else
    status_message error "CRITICAL: No sound files successfully processed. Check file names/paths in the input pack structure. See debug.log for details."
fi

# ----------------------------------------------------


# --- [ MANIFEST GENERATION (Minimal) ] ---
status_message process "Generating manifest.json files for Bedrock packs"

if test -f "./pack.png"; then
    cp ./pack.png ./target/rp/pack_icon.png
fi

uuid1=$(uuidgen) # RP UUID
uuid2=$(uuidgen) # RP Module UUID
uuid3=$(uuidgen) # BP UUID (Minimal)
uuid4=$(uuidgen) # BP Module UUID

pack_desc="$(jq -r '(.pack.description // "Converted Java Sound Resource Pack")' ./pack.mcmeta)"

jq -c --arg pack_desc "${pack_desc}" --arg uuid1 "${uuid1}" --arg uuid2 "${uuid2}" -n '
{
    "format_version": 2,
    "header": {
        "description": $pack_desc,
        "name": "Converted Java Sound Pack (geyser_sound)",
        "uuid": ($uuid1 | ascii_downcase),
        "version": [1, 0, 0],
        "min_engine_version": [1, 18, 3]
    },
    "modules": [
        {
            "description": "Resource module for sounds",
            "type": "resources",
            "uuid": ($uuid2 | ascii_downcase),
            "version": [1, 0, 0]
        }
    ]
}
' | sponge ./target/rp/manifest.json

jq -c --arg pack_desc "${pack_desc}" --arg uuid3 "${uuid3}" --arg uuid4 "${uuid4}" --arg uuid1 "${uuid1}" -n '
{
    "format_version": 2,
    "header": {
        "description": "Minimal Behavior Pack for Sound Conversion",
        "name": "Converted Sound BP (Empty)",
        "uuid": ($uuid3 | ascii_downcase),
        "version": [1, 0, 0],
        "min_engine_version": [ 1, 18, 3]
    },
    "modules": [
        {
            "description": "Data module (empty)",
            "type": "data",
            "uuid": ($uuid4 | ascii_downcase),
            "version": [1, 0, 0]
        }
    ],
    "dependencies": [
        {
            "uuid": ($uuid1 | ascii_downcase),
            "version": [1, 0, 0]
        }
    ]
}
' | sponge ./target/bp/manifest.json
status_message completion "Manifests generated"
# --------------------------------------------------------


# --- [ PACKAGING AND FINAL CLEANUP ] ---
status_message process "Compressing output packs"
mkdir -p ./target/packaged

cd ./target/rp > /dev/null && zip -rq8 geyser_sound.mcpack . -x "*/.*" && cd ../.. > /dev/null && mv ./target/rp/geyser_sound.mcpack ./target/packaged/geyser_sound.mcpack

cd ./target/bp > /dev/null && zip -rq8 geyser_behavior.mcpack . -x "*/.*" && cd ../.. > /dev/null && mv ./target/bp/geyser_behavior.mcpack ./target/packaged/geyser_behavior.mcpack

cd ./target/packaged > /dev/null && zip -rq8 geyser_addon.mcaddon . -i "*.mcpack" && cd ../.. > /dev/null

mkdir -p ./target/unpackaged
mv ./target/rp ./target/unpackaged/rp && mv ./target/bp ./target/unpackaged/bp

status_message process "Final cleanup: Removing extracted Java files and temporary data."
rm -rf assets ia_overlay_* scratch_files && rm -f pack.mcmeta pack.png config.json sprites.json default_assets.zip

status_message completion "Process Complete. Files are in ./target/packaged/ (specifically geyser_sound.mcpack and geyser_addon.mcaddon)"

# Final debug log entry and turn off tracing
{
    set +x
    printf "[INFO] DEBUG TRACE ENDED.\n"
} 

printf "\n\e[37mExiting...\e[m\n\n"