#!/bin/bash

# Copyright (c) 2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#-------------    functions    -------------
function install_dpdk() {
    sudo apt-get update
    sudo apt-get install -y dpdk dpdk-dev
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

install_dpdk || exit 255

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""
