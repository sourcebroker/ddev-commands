#!/bin/bash
#sb-generated

## Description: Open PHPStorm with the current project
## Usage: phpstorm
## Example: "ddev phpstorm"

# Example is macOS-specific, but easy to adapt to any OS
open -a PHPStorm.app ${DDEV_APPROOT}
