# Clasp.sh - Command Line Argument Spec Parser for Bash

**Clasp.sh: A feature-rich, specification-driven command-line argument parser for Bash 4.3+ scripts.**

Clasp.sh empowers you to define and parse complex command-line interfaces for your Bash scripts with ease and precision, moving beyond the limitations of basic `getopts`.

## Table of Contents

- [Clasp.sh - Command Line Argument Spec Parser for Bash](#claspsh---command-line-argument-spec-parser-for-bash)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation \& Setup](#installation--setup)
  - [Usage](#usage)
    - [The Specification String](#the-specification-string)
    - [Parsing Arguments with `clasp::parse`](#parsing-arguments-with-claspparse)
    - [Accessing Parsed Arguments](#accessing-parsed-arguments)
    - [Using `clasp::set` (Optional Helper)](#using-claspset-optional-helper)
    - [Automatic Help Message](#automatic-help-message)
  - [Full Example](#full-example)
  - [API Reference](#api-reference)
    - [`clasp::parse <spec_string> <named_args_map_ref> <positional_args_array_ref> [arguments...]`](#claspparse-spec_string-named_args_map_ref-positional_args_array_ref-arguments)
    - [`clasp::set <parsed_args_map_ref> [var_name_1] [var_name_2] ...`](#claspset-parsed_args_map_ref-var_name_1-var_name_2-)
  - [Limitations](#limitations)
  - [Contributing](#contributing)
  - [License](#license)

## Introduction

Dealing with command-line arguments in Bash can become cumbersome with anything more than a few simple flags. `Clasp.sh` (Command Line Argument Spec Parser) provides a robust solution by allowing you to define your entire CLI structure—including options, flags, positional arguments, default values, choices, and basic type validation—through a human-readable specification string. It then parses the incoming arguments according to this specification, populates easy-to-use Bash arrays, and can even generate a formatted help message automatically.

This library is designed for Bash 4.3+ and aims to be a pure Bash solution with no external dependencies beyond standard system utilities used for basic string operations.

## Features

- **Specification-Driven:** Define your entire CLI with a concise and powerful string format.
- **Versatile Option Parsing:**
  - Long options (`--option`)
  - Short options (`-o`)
  - Combined short options (e.g., `-xyz` expanded to `-x -y -z`)
  - Option arguments (`--option=value` or `--option value`)

- **Boolean Flags:** Simple on/off flags, with support for `default=true`.
- **Positional Arguments:** Define and capture ordered arguments.
  - Defined positional arguments are also accessible by their canonical name in the main parsed arguments map.
- **Default Values:** Specify default values for options if they are not provided on the command line.
- **Choice Validation:** Restrict argument values to a predefined set of choices.
- **Type Hinting & Basic Validation:** Specify argument types (e.g., `type=int`); integer types are validated.
- **Required Arguments:** Mark options or positional arguments as mandatory.
- **Automatic Help Message:** Generates a formatted `--help` / `-h` message based on your specification.
- **Pure Bash:** No external program dependencies beyond Bash 4.3+ and common GNU utilities (like `grep`, `sort` used internally for some features like help sorting).

## Requirements

- **Bash version 4.3 or higher** (due to usage of namerefs (`local -n`), associative arrays, and certain string manipulations like `${VAR^^}`).

## Installation & Setup

1. **Download `clasp.sh`:**
    You can clone this repository or download the `clasp.sh` script directly.

    ```bash
    # Example:
    # git clone https://your-repo-url/clasp.sh.git
    # Or save the script content as clasp.sh
    ```

2. **Source the Script:**
    In your Bash script, source `clasp.sh` to make its functions available:

    ```bash
    #!/usr/bin/env bash

    # Source the Clasp library
    source /path/to/clasp.sh
    # Or if it's in the same directory:
    # source ./clasp.sh

    # Your script logic here...
    ```

## Usage

Using Clasp.sh involves three main steps:

1. Defining your argument specification string.
2. Calling `clasp::parse` to process the command-line arguments.
3. Accessing the parsed arguments from the populated arrays.

### The Specification String

This is the heart of Clasp.sh. You define all your expected arguments as a single comma-separated string. Each argument definition within this string follows the format:

`"long_name:short_alias#FLAGS#METADATA#DESCRIPTION"`

- **`long_name:short_alias`** (Aliases):
  - The long option name (e.g., `verbose`).
  - Optionally, a colon (`:`) followed by a single-character short alias (e.g., `v`).
  - The first name provided (typically the long name) is considered the **canonical name** for the argument.
  - For positional arguments, this is just the canonical name (e.g., `inputfile`).
  - Example: `output:o`, `username`, `inputfile`

* **`#FLAGS#`**:

  - A sequence of single characters indicating properties. Separated from aliases by `#`.
  - `f`: Marks the option as a boolean **flag** (takes no value).
  - `r`: Marks the option or positional argument as **required**.
  - `p`: Marks the argument as **positional**.
  - Example: `f` (for a flag), `r` (for a required value option), `pr` (for a required positional argument). If no flags, this part can be empty (e.g., `##`).

* **`#METADATA#`**:
  
  - Semicolon-separated `key=value` pairs providing additional information. Separated from FLAGS by `#`.
  - `default=VALUE`: Specifies a default value if the option is not provided. For boolean flags, use `default=true` to make the flag active by default.
  - `choices=VAL1|VAL2|VAL3`: A pipe-separated list of allowed values for the argument. The parser will validate against these.
  - `type=TYPENAME`: A type hint for the argument (e.g., `int`, `file`, `string`). `int` is currently validated by the parser. This also influences the placeholder in the help message (e.g., `<INT>`).
  - Example: `default=/tmp/out.log;type=file`, `choices=low|medium|high`, `default=true`. If no metadata, this part can be empty.

* **`#DESCRIPTION`**:
  
  - A human-readable description of the argument, used in the help message. Separated from METADATA by `#`.
  - Example: `Enable verbose output`, `Path to the input file`.

**Full Specification String Example:**

```bash
ARG_SPEC="output:o##default=/tmp/default.out;type=file#Output file path,mode##choices=read|write;default=read#Operation mode,verbose:v#f##Be verbose,input#pr#type=filepath#Input file (required, positional)"
```

### Parsing Arguments with `clasp::parse`

Once you have your specification string, you call `clasp::parse`:

```bash
# 1. Define your argument specification
ARG_SPEC="file:f#r#type=filepath#Input file,verbose:v#f##Enable verbose mode"

# 2. Declare arrays to hold parsed results
declare -A cli_options # Associative array for named options and defined positionals by name
declare -a cli_positionals # Indexed array for all positional arguments in order

# 3. Call the parser
if ! clasp::parse "${ARG_SPEC}" cli_options cli_positionals "$@"; then
  # Error message already printed by clasp::parse or its helpers
  exit 1
fi

# Arguments are now in cli_options and cli_positionals
```

### Accessing Parsed Arguments

After a successful call to `clasp::parse`:

1. **`cli_options` (Associative Array, e.g., `${cli_options[canonical_name]}`):**
    - Contains all named options (flags and value-taking options) using their **canonical names** as keys.
      - Boolean flags set by presence (or `default=true`) will have the value `true`.
      - Options with values will have their provided (or default) value.
    - Also contains **defined positional arguments** using their canonical names as keys.

2. **`cli_positionals` (Indexed Array, e.g., `${cli_positionals[0]}`):**

- Contains **all** positional arguments in the order they appeared on the command line.
- This includes defined positional arguments as well as any "extra" positional arguments not explicitly defined in the spec.

**Example Access:**

```bash
# Assuming ARG_SPEC="file:f#r#type=filepath#Input file,verbose:v#f##Enable verbose mode,target#p##Target host"
# And command: my_script.sh --file /path/to/data --verbose server1 server2

# Accessing named option:
input_file="${cli_options[file]}" # Value: /path/to/data
is_verbose="${cli_options[verbose]}" # Value: true

# Accessing defined positional by name:
target_host_by_name="${cli_options[target]}" # Value: server1

# Accessing all positionals by index:
first_pos="${cli_positionals[0]}"  # Value: server1
second_pos="${cli_positionals[1]}" # Value: server2 (an "extra" positional)
```

### Using `clasp::set` (Optional Helper)

For convenience, `Clasp.sh` provides `clasp::set` to populate local shell variables directly from the `cli_options` map.

```bash
# ... after clasp::parse ...

# Declare local variables that match canonical names in your spec
local file verbose_mode target_host

# Use clasp::set (this is optional)
clasp::set cli_options file verbose target # Note: 'verbose' is the canonical name for -v

# Now you can use the local variables:
# echo "File: $file"
# if [[ "$verbose" == "true" ]]; then echo "Verbose mode is ON"; fi
# echo "Target: $target_host" # If 'target' was set in cli_options by clasp::parse
```

Note: `clasp::set` only sets variables if the corresponding key exists in the `cli_options` map.

### Automatic Help Message

If `-h` or `--help` is passed on the command line, `clasp::parse` will automatically call an internal `__usage` function to print a formatted help message based on your `ARG_SPEC` and then exit. You don't need to handle this explicitly.

## Full Example

```bash
#!/usr/bin/env bash

# Source the Clasp library (assuming clasp.sh is in the same directory or in PATH)
source ./clasp.sh || { echo "ERROR: clasp.sh not found or failed to source."; exit 1; }

# Define the main function for your script
function main() {
  local ARG_SPEC=""
  ARG_SPEC+="output:o##default=/tmp/default.out;type=file#Output file path,"
  ARG_SPEC+="mode##choices=read|write|append;default=read#Operation mode,"
  ARG_SPEC+="retries##type=int;default=3#Number of retries,"
  ARG_SPEC+="verbose:v#f##Be verbose," # Canonical name 'verbose'
  ARG_SPEC+="debug:d#f#default=true#Enable debug (defaults to true)," # Canonical name 'debug'
  ARG_SPEC+="input#pr#type=filepath;choices=src/main.c|lib/utils.c#Input file path (required, positional)," # Canonical name 'input'
  ARG_SPEC+="count#p#type=int#An optional count (positional)" # Canonical name 'count'

  declare -A parsed_args   # Will hold named options and defined positionals by name
  declare -a positional_args # Will hold ALL positional arguments in order

  # Parse command-line arguments
  if ! clasp::parse "${ARG_SPEC}" parsed_args positional_args "$@"; then
    # Error message already printed by clasp::parse or its helpers
    exit 1
  fi

  # --- Accessing Parsed Arguments ---

  # Optionally use clasp::set to populate local variables.
  # Ensure variable names match canonical names used in ARG_SPEC.
  local output_file mode retries verbose debug 
  clasp::set parsed_args output_file mode retries verbose debug 

  # Access defined positional arguments (also available in 'parsed_args' by name).
  local input_file="${parsed_args[input]}" 
  local count_val="${parsed_args[count]}"  

  # Example of manually applying a default for an *optional* positional argument
  # if it wasn't provided and a default is defined for it in its metadata.
  # This is necessary because the parser doesn't auto-apply defaults for *omitted* positionals
  # into the positional_args array or automatically into parsed_args for positionals.
  # We check if 'count' (the 2nd defined positional) was actually provided.
  if [[ ${#positional_args[@]} -lt 2 ]] && [[ -z "$count_val" ]] && [[ -v CANONICAL_OPT_META_DEFAULT[count] ]]; then
      count_val="${CANONICAL_OPT_META_DEFAULT[count]}"
      # parsed_args[count]="$count_val" # Optionally update the map too if desired after manual default
  fi

  echo "--- Parsed Arguments Demonstration ---"
  echo "Verbose Flag: ${verbose:-false}" # 'verbose' was populated by clasp::set
  echo "Debug Flag: ${debug:-false}"     # 'debug' was populated by clasp::set; spec default is true
  echo "Output File: ${output_file}"    # Populated by clasp::set from default or CLI
  echo "Mode: ${mode}"                  # Populated by clasp::set from default or CLI
  echo "Retries: ${retries}"              # Populated by clasp::set from default or CLI
  
  echo "Input File (Positional 1, name 'input'): ${input_file}"
  echo "Count (Positional 2, name 'count'): ${count_val:-"Not provided"}"

  echo ""
  echo "--- Raw Data Structures ---"
  echo "Raw parsed_args map (includes named options and defined positionals by name):"
  for key in "${!parsed_args[@]}"; do
    echo "  '${key}': '${parsed_args[${key}]}'"
  done

  echo "Raw positional_args array (all positionals in order, including any extras):"
  local idx=0
  for val in "${positional_args[@]}"; do
    echo "  [$idx] = '${val}'"
    ((idx++))
  done
}

# Execute the main function with all script arguments
main "$@"
```

## API Reference

### `clasp::parse <spec_string> <named_args_map_ref> <positional_args_array_ref> [arguments...]`

- **Purpose:** Parses command-line arguments according to the specification.

- **`<spec_string>`:** The string defining all expected arguments.
- **`<named_args_map_ref>`:** The name of an associative array (passed by nameref) that will be populated with named options and defined positional arguments (keyed by their canonical names).
- **`<positional_args_array_ref>`:** The name of an indexed array (passed by nameref) that will be populated with all positional arguments in the order they appeared.
- **`[arguments...]`:** The actual command-line arguments to parse (typically `"$@"`).
- **Returns:** `0` on success, `1` on parsing errors (messages are printed to `stderr`). Exits with `0` if `-h` or `--help` is processed.

### `clasp::set <parsed_args_map_ref> [var_name_1] [var_name_2] ...`

- **Purpose:** (Optional convenience function) Populates shell variables in the current scope from the parsed arguments map.
- **`<parsed_args_map_ref>`:** The name of the associative array populated by `clasp::parse`.
- **`[var_name_N]`:** Names of shell variables to create/set. These names should match the canonical names of arguments stored as keys in the map. If a key doesn't exist in the map, the corresponding variable is not set or changed.
- **Returns:** `0`.

## Limitations

- The option specification parser is simple and uses `#`, `;`, `:`, `=` as delimiters. These characters should generally not be used within alias names, flag characters, metadata keys/values, or (unescaped) in descriptions if they are to be parsed correctly by this script.
- Advanced features like sub-commands or mutually exclusive argument groups are not supported.
- While robust for many use cases, extremely complex or ambiguously defined CLIs might expose edge cases.

## Contributing

Contributions, bug reports, and feature requests are welcome! Please feel free to open an issue or submit a pull request on the project's repository.

## License

This project is licensed under the MIT License - see the `LICENSE` file for details (or choose your preferred open-source license).