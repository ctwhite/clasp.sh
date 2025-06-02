#!/usr/bin/env bash

# clasp.sh - Command Line Argument Spec Parser for Bash
#
# Version: 1.0
# Last Updated: 2025-06-02 # (Based on interaction context)
#
# Features:
#   - Parses long options (--option), short options (-o), and combined short options (-xyz).
#   - Handles options with required values (--option=value or --option value).
#   - Supports boolean flags.
#   - Supports positional arguments.
#   - Custom option specification string:
#     "long:short#FLAGS#METADATA#DESCRIPTION,another_opt..."
#     - Aliases: `long_name:short_alias` (e.g., `verbose:v`, `output:o`). First is canonical.
#     - FLAGS: Single characters:
#       - `f`: Boolean flag (option takes no value).
#       - `r`: Required option/positional argument.
#       - `p`: Positional argument.
#     - METADATA: Semicolon-separated key=value pairs (e.g., `default=foo;choices=a|b|c;type=int`).
#       - `default=VALUE`: Default value for the option. For flags, use `default=true`.
#       - `choices=VAL1|VAL2`: Pipe-separated list of allowed values.
#       - `type=TYPENAME`: Type hint (e.g., `int`, `file`). `int` is validated.
#     - DESCRIPTION: Help text for the option/argument.
#   - Generates a formatted help/usage message.
#   - Validates argument choices and basic integer types.
#   - Allows default values for options (including `default=true` for flags).
#   - Defined positional arguments are also accessible by name from the main parsed arguments map.
#
# Usage as a library:
#   1. Source this script: `source clasp.sh`
#   2. Define your ARG_SPEC string.
#   3. Declare an associative array for named/defined-positional args (e.g., `declare -A my_args`).
#   4. Declare an indexed array for all positional args (e.g., `declare -a my_pos_args`).
#   5. Call `clasp::parse "$ARG_SPEC" my_args my_pos_args "$@"`
#   6. Access values:
#      - Directly: `${my_args[option_name]}`, `${my_pos_args[0]}`
#      - Optionally, use `clasp::set my_args var1 var2` to populate local variables.
#
# Script Dependencies: Bash 4.3+ for namerefs, ${VAR^^}, associative arrays.
#
# --- Limitations ---
# The option specification parser is simple and uses '#', ';', ':', '=' as delimiters.
# These characters should generally not be used within alias names, flag characters,
# metadata keys/values, or unescaped in descriptions if they are to be parsed correctly by this script.

# --- Global Metadata Maps ---
# Store parsed details about options. Cleared at the start of clasp::parse.
declare -gA CANONICAL_OPT_META_CHOICES
declare -gA CANONICAL_OPT_META_DEFAULT
declare -gA CANONICAL_OPT_META_TYPE

# Helper: Get script name.
function __get_script_name() {
  basename "$0"
}

# Helper: Echo errors to stderr.
function __err() {
  echo "ERROR: $1" >&2
}

# Internal Helper: Parse metadata string (key=val;key2=val2) into a nameref map.
# Args: $1: metadata_str, $2: nameref to associative array.
function __parse_metadata_str() {
  local metadata_str="$1"
  local -n metadata_map=$2
  metadata_map=()

  if [[ -z "${metadata_str}" ]]; then
    return
  fi

  local old_ifs="$IFS"
  IFS=';'
  local -a pairs
  read -r -a pairs <<<"${metadata_str}"
  IFS="$old_ifs"

  for pair in "${pairs[@]}"; do
    if [[ "$pair" == *=* ]]; then
      local key="${pair%%=*}"
      local value="${pair#*=}"
      metadata_map["$key"]="$value"
    fi
  done
}

# Function: __usage
# Purpose: Generates and prints the help/usage message based on the option specification.
# Args: $1: The option specification string.
function __usage() {
  local spec_string="$1"
  local -a spec_defs_orig
  IFS=',' read -r -a spec_defs_orig <<<"${spec_string}"

  local -a option_help_lines=()
  local -a synopsis_options_parts=()
  local -a synopsis_positionals_parts=()

  local -a spec_defs=("${spec_defs_orig[@]}")
  spec_defs+=("help:h#f##Show this help message and exit") # Add help definition for processing

  for opt_full_spec in "${spec_defs[@]}"; do
    local num_hashes=0
    local temp_spec="$opt_full_spec"
    local stripped_spec="${temp_spec//[^#]/}"
    num_hashes=${#stripped_spec}

    if [[ $num_hashes -gt 3 ]]; then
      __err "Usage: Malformed option spec (too many '#'): ${opt_full_spec}"
      continue
    fi

    local -a opt_parts
    IFS='#' read -r -a opt_parts <<<"${opt_full_spec}"

    local aliases_str="${opt_parts[0]}"
    if [[ -z "$aliases_str" ]]; then
      __err "Usage: Malformed option spec (empty alias part): ${opt_full_spec}"
      continue
    fi
    local flags_str="${opt_parts[1]:-}"
    local metadata_str="${opt_parts[2]:-}"
    local description="${opt_parts[3]:-}"

    local -A current_metadata
    __parse_metadata_str "${metadata_str}" current_metadata

    local -a aliases_arr
    IFS=':' read -r -a aliases_arr <<<"${aliases_str}"

    description="${description//[$'\t\r\n']/ }"
    description="${description//  / }"

    local is_flag=false is_required=false is_positional=false
    if [[ -n "${flags_str}" ]]; then
      for ((i = 0; i < ${#flags_str}; i++)); do
        local flag_char="${flags_str:$i:1}"
        case "${flag_char}" in
        f) is_flag=true ;;
        r) is_required=true ;;
        p) is_positional=true ;;
        esac
      done
    fi

    local primary_name="${aliases_arr[0]//[$'\t\r\n ']/}"
    local meta_info_for_desc=""

    if [[ -n "${current_metadata[type]}" ]]; then
      meta_info_for_desc+=" (type: ${current_metadata[type]})"
    fi
    if [[ -n "${current_metadata[choices]}" ]]; then
      meta_info_for_desc+=" (choices: ${current_metadata[choices]//|/, })"
    fi
    if [[ -n "${current_metadata[default]}" ]] && (! ${is_flag} || [[ "${current_metadata[default]}" == "true" ]]); then
      meta_info_for_desc+=" (default: ${current_metadata[default]})"
    fi

    if ${is_positional}; then
      local display_name="${primary_name^^}"
      local synopsis_part="${display_name}"
      if ! ${is_required}; then
        synopsis_part="[${synopsis_part}]"
      fi
      synopsis_positionals_parts+=("${synopsis_part}")

      if [[ -n "${description}" || -n "${meta_info_for_desc}" ]]; then
        option_help_lines+=("$(printf "  %-28s %s%s" "${display_name}" "${description}" "${meta_info_for_desc}")")
      fi
    else
      local long_opt="--${aliases_arr[0]//[$'\t\r\n ']/}"
      local short_opt_str=""
      local help_line_opt_part=""

      if [[ ${#aliases_arr[@]} -gt 1 ]]; then
        short_opt_str="-${aliases_arr[1]//[$'\t\r\n ']/}"
        help_line_opt_part="${short_opt_str}, ${long_opt}"
      else
        help_line_opt_part="    ${long_opt}"
      fi

      local arg_placeholder=""
      local arg_placeholder_name="${primary_name^^}"
      if [[ -n "${current_metadata[type]}" ]]; then
        arg_placeholder_name="${current_metadata[type]^^}"
      fi

      if ! ${is_flag}; then
        arg_placeholder=" <${arg_placeholder_name}>"
        help_line_opt_part+="${arg_placeholder}"
      fi

      local current_opt_synopsis_part="${long_opt}${arg_placeholder}"
      if [[ "$primary_name" == "help" ]]; then
        current_opt_synopsis_part="-h|--help"
      fi
      if ! ${is_required} && ! (${is_flag} && [[ "${current_metadata[default]}" == "true" ]]); then
        current_opt_synopsis_part="[${current_opt_synopsis_part}]"
      fi
      synopsis_options_parts+=("${current_opt_synopsis_part}")

      local full_desc="${description}"
      if ${is_required} && ! ${is_flag}; then
        full_desc+="${description:+, } (required)"
      fi
      option_help_lines+=("$(printf "  %-28s %s%s" "${help_line_opt_part}" "${full_desc}" "${meta_info_for_desc}")")
    fi
  done

  local usage_line
  usage_line="usage: $(__get_script_name)"
  [[ ${#synopsis_options_parts[@]} -gt 0 ]] && usage_line+=" ${synopsis_options_parts[*]}"
  [[ ${#synopsis_positionals_parts[@]} -gt 0 ]] && usage_line+=" ${synopsis_positionals_parts[*]}"
  echo "${usage_line}"

  if [[ ${#option_help_lines[@]} -gt 0 ]]; then
    echo ""
    echo "Options:"
    local -a sorted_option_lines
    mapfile -t sorted_option_lines < <(printf '%s\n' "${option_help_lines[@]}" | sort)
    for line in "${sorted_option_lines[@]}"; do
      echo "$line"
    done
  fi
}

# Function: __invalid_arg
# Purpose: Prints an error message for an invalid argument and standard "try --help" advice.
# Args: $1: Error message string.
function __invalid_arg() {
  __err "$1"
  echo "Try '$("$(__get_script_name)") --help' for more information." >&2
  return 1
}

# Function: clasp::set
# Purpose: Assigns parsed arguments to variables in the caller's scope. This is a convenience.
# Args:
#   $1: Name of the associative array holding parsed arguments (e.g., 'my_args').
#   $@: Names of shell variables to populate (these should match canonical arg names).
function clasp::set() {
  local -n __parsed_args_map=$1
  shift

  for var_name_to_set in "${@}"; do
    if [[ -v "__parsed_args_map[${var_name_to_set}]" ]]; then
      local -n __target_var=${var_name_to_set}
      __target_var="${__parsed_args_map[${var_name_to_set}]}"
    fi
  done
  return 0
}

# Function: clasp::parse
# Purpose: Core argument parsing logic.
# Args:
#   $1: Option specification string.
#   $2: Nameref to an associative array to store named arguments and defined positionals by name.
#   $3: Nameref to an indexed array to store all positional arguments in order.
#   $@: The command-line arguments to parse (typically "${@}").
function clasp::parse() {
  local opt_spec_str="$1"
  local -n __out_named_args=$2
  local -n __out_positional_args=$3
  shift 3
  local -a cli_args=("$@")

  CANONICAL_OPT_META_CHOICES=()
  CANONICAL_OPT_META_DEFAULT=()
  CANONICAL_OPT_META_TYPE=()
  __out_named_args=()
  __out_positional_args=()

  local -a spec_option_defs
  IFS=',' read -r -a spec_option_defs <<<"${opt_spec_str}"

  local -A alias_to_canonical_map
  local -a defined_opts_aliases=()
  local -a defined_flags_aliases=()
  local -a defined_required_canonicals=()
  local -a defined_positional_canonicals_ordered=()

  for opt_def in "${spec_option_defs[@]}"; do
    local num_hashes=0
    local temp_spec="$opt_def"
    local stripped_spec="${temp_spec//[^#]/}"
    num_hashes=${#stripped_spec}

    if [[ $num_hashes -gt 3 ]]; then
      __invalid_arg "Malformed option specification (too many '#'): ${opt_def}"
      return 1
    fi

    local -a opt_def_parts
    IFS='#' read -r -a opt_def_parts <<<"${opt_def}"

    local current_aliases_str="${opt_def_parts[0]}"
    if [[ -z "$current_aliases_str" ]]; then
      __invalid_arg "Malformed option specification (empty alias part): ${opt_def}"
      return 1
    fi
    local current_flags_str="${opt_def_parts[1]:-}"
    local current_metadata_str="${opt_def_parts[2]:-}"

    local -a current_aliases_arr
    IFS=':' read -r -a current_aliases_arr <<<"${current_aliases_str}"
    local canonical_name="${current_aliases_arr[0]//[$'\t\r\n ']/}"

    local -A opt_meta
    __parse_metadata_str "${current_metadata_str}" opt_meta

    local is_opt_flag=false is_opt_required=false is_opt_positional=false
    if [[ -n "${current_flags_str}" ]]; then
      for ((i = 0; i < ${#current_flags_str}; i++)); do
        local flag_char="${current_flags_str:$i:1}"
        case "${flag_char}" in
        f) is_opt_flag=true ;;
        r) is_opt_required=true ;;
        p) is_opt_positional=true ;;
        esac
      done
    fi

    if [[ -n "${opt_meta[choices]}" ]]; then CANONICAL_OPT_META_CHOICES["${canonical_name}"]="${opt_meta[choices]}"; fi
    if [[ -n "${opt_meta[default]}" ]]; then CANONICAL_OPT_META_DEFAULT["${canonical_name}"]="${opt_meta[default]}"; fi
    if [[ -n "${opt_meta[type]}" ]]; then CANONICAL_OPT_META_TYPE["${canonical_name}"]="${opt_meta[type]}"; fi

    if ${is_opt_positional}; then
      if [[ ${#current_aliases_arr[@]} -gt 1 ]]; then
        __invalid_arg "Positional option '${canonical_name}' cannot have aliases."
        return 1
      fi
      defined_positional_canonicals_ordered+=("${canonical_name}")
    elif ${is_opt_flag}; then
      if [[ "${opt_meta[default]}" == "true" ]]; then
        __out_named_args["${canonical_name}"]=true
      fi
    else
      if [[ -v opt_meta[default] ]]; then
        __out_named_args["${canonical_name}"]="${opt_meta[default]}"
      fi
    fi

    if ${is_opt_required}; then
      defined_required_canonicals+=("${canonical_name}")
    fi

    for alias in "${current_aliases_arr[@]}"; do
      local clean_alias="${alias//[$'\t\r\n ']/}"
      alias_to_canonical_map["${clean_alias}"]="${canonical_name}"
      if ${is_opt_positional}; then
        :
      elif ${is_opt_flag}; then
        defined_flags_aliases+=("${clean_alias}")
      else
        defined_opts_aliases+=("${clean_alias}")
      fi
    done
  done

  local -a processed_cli_args=()
  local passthrough_args=false
  for ((i = 0; i < ${#cli_args[@]}; i++)); do
    local arg="${cli_args[$i]}"
    if ${passthrough_args}; then
      processed_cli_args+=("${arg}")
      continue
    fi
    case "${arg}" in
    --)
      processed_cli_args+=("${arg}")
      passthrough_args=true
      ;;
    --*=*) processed_cli_args+=("${arg%%=*}" "${arg#*=}") ;;
    -?*)
      if [[ "${arg}" == "-" ]]; then
        processed_cli_args+=("${arg}")
        continue
      fi
      local first_char_opt="${arg:1:1}"
      local is_known_value_opt=false
      local is_known_flag=false
      if [[ " ${defined_opts_aliases[*]} " =~ " ${first_char_opt} " ]]; then is_known_value_opt=true; fi
      if [[ " ${defined_flags_aliases[*]} " =~ " ${first_char_opt} " ]]; then is_known_flag=true; fi
      if ${is_known_value_opt} && [[ ${#arg} -gt 2 ]]; then
        processed_cli_args+=("-${first_char_opt}")
        processed_cli_args+=("${arg:2}")
      elif ${is_known_flag}; then
        for ((j = 1; j < ${#arg}; j++)); do processed_cli_args+=("-${arg:$j:1}"); done
      else processed_cli_args+=("${arg}"); fi
      ;;
    *) processed_cli_args+=("${arg}") ;;
    esac
  done

  passthrough_args=false
  local i=0
  local current_defined_positional_index=0

  while [[ $i -lt ${#processed_cli_args[@]} ]]; do
    local arg="${processed_cli_args[$i]}"

    if ${passthrough_args}; then
      __out_positional_args+=("${arg}")
      if [[ ${current_defined_positional_index} -lt ${#defined_positional_canonicals_ordered[@]} ]]; then
        local def_pos_name="${defined_positional_canonicals_ordered[${current_defined_positional_index}]}"
        __out_named_args["${def_pos_name}"]="$arg"
      fi
      current_defined_positional_index=$((current_defined_positional_index + 1))
      i=$((i + 1))
      continue
    fi

    case "${arg}" in
    -h | --help)
      __usage "${opt_spec_str}"
      exit 0
      ;;
    --) passthrough_args=true ;;
    -?* | --?*)
      local key
      if [[ "${arg}" == --* ]]; then key="${arg#--}"; else key="${arg#-}"; fi
      local current_canonical_name="${alias_to_canonical_map[${key}]}"

      if [[ -z "${current_canonical_name}" ]]; then
        __invalid_arg "Unrecognized option: ${arg}"
        return 1
      elif [[ " ${defined_flags_aliases[*]} " =~ " ${key} " ]]; then
        __out_named_args["${current_canonical_name}"]=true
      elif [[ " ${defined_opts_aliases[*]} " =~ " ${key} " ]]; then
        i=$((i + 1))
        if [[ $i -ge ${#processed_cli_args[@]} ]] ||
          ([[ "${processed_cli_args[$i]}" == --* ]] && [[ -n "${alias_to_canonical_map[${processed_cli_args[$i]#--}]}" ]]) ||
          ([[ "${processed_cli_args[$i]}" == -* ]] && [[ "${processed_cli_args[$i]}" != "-" ]] && [[ -n "${alias_to_canonical_map[${processed_cli_args[$i]#-}]}" ]]); then
          __invalid_arg "Option '${arg}' requires an argument."
          return 1
        fi
        local value_provided="${processed_cli_args[$i]}"

        if [[ -v CANONICAL_OPT_META_TYPE["${current_canonical_name}"] &&
          "${CANONICAL_OPT_META_TYPE[${current_canonical_name}]}" == "int" ]]; then
          if ! [[ "$value_provided" =~ ^-?[0-9]+$ ]]; then
            __invalid_arg "Invalid integer value for ${arg}: '${value_provided}'. Expected integer."
            return 1
          fi
        fi
        if [[ -v CANONICAL_OPT_META_CHOICES["${current_canonical_name}"] ]]; then
          local allowed_choices_str="${CANONICAL_OPT_META_CHOICES[${current_canonical_name}]}"
          if ! echo "|${allowed_choices_str}|" | grep -qF "|${value_provided}|"; then
            __invalid_arg "Invalid choice for ${arg}: '${value_provided}'. Allowed: ${allowed_choices_str//|/, }."
            return 1
          fi
        fi
        __out_named_args["${current_canonical_name}"]="${value_provided}"
      else
        __invalid_arg "Internal parser error: Option '${arg}' (alias '${key}' for '${current_canonical_name}') has an inconsistent definition."
        return 1
      fi
      ;;
    *)
      local positional_value="$arg"
      __out_positional_args+=("${positional_value}")

      if [[ ${current_defined_positional_index} -lt ${#defined_positional_canonicals_ordered[@]} ]]; then
        local def_pos_name="${defined_positional_canonicals_ordered[${current_defined_positional_index}]}"

        if [[ -v CANONICAL_OPT_META_TYPE["${def_pos_name}"] &&
          "${CANONICAL_OPT_META_TYPE[${def_pos_name}]}" == "int" ]]; then
          if ! [[ "$positional_value" =~ ^-?[0-9]+$ ]]; then
            __invalid_arg "Invalid integer value for positional argument '${def_pos_name}': '${positional_value}'. Expected integer."
            return 1
          fi
        fi
        if [[ -v CANONICAL_OPT_META_CHOICES["${def_pos_name}"] ]]; then
          local allowed_choices_str="${CANONICAL_OPT_META_CHOICES[${def_pos_name}]}"
          if ! echo "|${allowed_choices_str}|" | grep -qF "|${positional_value}|"; then
            __invalid_arg "Invalid choice for positional argument '${def_pos_name}': '${positional_value}'. Allowed: ${allowed_choices_str//|/, }."
            return 1
          fi
        fi
        __out_named_args["${def_pos_name}"]="$positional_value"
      fi
      current_defined_positional_index=$((current_defined_positional_index + 1))
      ;;
    esac
    i=$((i + 1))
  done

  local missing_required_msg=""
  for req_canonical_name in "${defined_required_canonicals[@]}"; do
    local is_provided=false
    local is_defined_positional=false
    local positional_idx=-1

    for j in "${!defined_positional_canonicals_ordered[@]}"; do
      if [[ "${defined_positional_canonicals_ordered[$j]}" == "$req_canonical_name" ]]; then
        is_defined_positional=true
        positional_idx=$j
        break
      fi
    done

    if ${is_defined_positional}; then
      if [[ ${#__out_positional_args[@]} -gt $positional_idx ]] && [[ -n "${__out_positional_args[$positional_idx]}" ]]; then
        is_provided=true
      elif [[ -v "__out_named_args[${req_canonical_name}]" ]] && [[ -n "${__out_named_args[${req_canonical_name}]}" ]]; then
        is_provided=true
      fi
    else
      if [[ -v "__out_named_args[${req_canonical_name}]" ]]; then
        if [[ "${CANONICAL_OPT_META_TYPE[${req_canonical_name}]}" == "flag" ]]; then
          [[ "${__out_named_args[${req_canonical_name}]}" == "true" ]] && is_provided=true
        elif [[ -n "${__out_named_args[${req_canonical_name}]}" ]] || [[ -v CANONICAL_OPT_META_DEFAULT["${req_canonical_name}"] ]]; then
          is_provided=true
        fi
      fi
    fi

    if ! ${is_provided}; then
      missing_required_msg+="Missing required argument: '${req_canonical_name}'. "
    fi
  done
  if [[ -n "$missing_required_msg" ]]; then
    __invalid_arg "${missing_required_msg}"
    return 1
  fi

  return 0
}

# Example Usage (Uncomment to run as a standalone script for testing):
# function main() {
#   local ARG_SPEC=""
#   ARG_SPEC+="output:o##default=/tmp/default.out;type=file#Output file path,"
#   ARG_SPEC+="mode##choices=read|write|append;default=read#Operation mode,"
#   ARG_SPEC+="retries##type=int;default=3#Number of retries,"
#   ARG_SPEC+="verbose:v#f##Be verbose,"
#   ARG_SPEC+="debug:d#f#default=true#Enable debug (defaults to true),"
#   ARG_SPEC+="input#pr#type=filepath;choices=src/main.c|lib/utils.c#Input file path (required, positional),"
#   ARG_SPEC+="count#p#type=int#An optional count (positional)"

#   declare -A parsed_args
#   declare -a positional_args

#   # Note: Source clasp.sh before calling its functions if it's in a separate file
#   # source ./clasp.sh

#   if ! clasp::parse "${ARG_SPEC}" parsed_args positional_args "$@"; then
#     # __invalid_arg already printed messages and help hint
#     exit 1
#   fi

#   # --- Accessing Parsed Arguments ---

#   # Method 1: Directly from the 'parsed_args' associative array (always available for named options
#   # and defined positionals).
#   # echo "Mode (direct access): ${parsed_args[mode]}"
#   # echo "Input file (direct access for defined positional): ${parsed_args[input]}"

#   # Method 2: Using the (OPTIONAL) 'clasp::set' helper to populate local variables.
#   # This is convenient for commonly used arguments. Ensure variable names passed to
#   # 'clasp::set' match the canonical names defined in your ARG_SPEC.
#   local output_file mode retries verbose debug
#   clasp::set parsed_args output_file mode retries verbose debug

#   # Now, local variables like 'output_file', 'mode', 'verbose', 'debug' are set if the
#   # corresponding arguments were provided or had defaults in 'parsed_args'.

#   # Accessing defined positional arguments:
#   # These are available both by their name in 'parsed_args' AND by index in 'positional_args'.
#   local input_file="${parsed_args[input]}"
#   local count_val="${parsed_args[count]}"

#   # Example of manually applying a default for an *optional* positional argument
#   # if it wasn't provided and you have a default defined for it in its metadata.
#   # This is necessary because the parser doesn't auto-apply defaults for *omitted* positionals.
#   # Check if 'count' (the 2nd defined positional) was actually provided by checking number of positionals.
#   if [[ ${#positional_args[@]} -lt 2 ]] && [[ -z "$count_val" ]] && [[ -v CANONICAL_OPT_META_DEFAULT[count] ]]; then
#       count_val="${CANONICAL_OPT_META_DEFAULT[count]}"
#       # parsed_args[count]="$count_val" # Optionally update the map too if desired after manual default
#   fi

#   echo "--- Parsed Arguments Demonstration ---"
#   echo "Verbose: ${verbose:-false}" # 'verbose' was populated by clasp::set
#   echo "Debug: ${debug:-false}"     # 'debug' was populated by clasp::set; defaults to true from spec
#   echo "Output File: ${output_file}"
#   echo "Mode: ${mode}"
#   echo "Retries: ${retries}"
#   echo "Input File (Positional 1, by name 'input'): ${input_file}"
#   echo "Count (Positional 2, by name 'count'): ${count_val:-"Not provided"}"

#   echo ""
#   echo "Raw parsed_args map (includes named options and defined positionals by name):"
#   for key in "${!parsed_args[@]}"; do
#     echo "  '${key}': '${parsed_args[${key}]}'"
#   done
#   echo "Raw positional_args array (all positionals in order, including any extras):"
#   idx=0
#   for val in "${positional_args[@]}"; do
#     echo "  [$idx] = '${val}'"
#     ((idx++))
#   done
# }

# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#    main "$@"
# fi
