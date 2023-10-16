#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")

LOG_FILE=${LOG_FILE:="host_setup_ubuntu.log"}
#---------      Functions    -------------------
declare -F "log_func" >/dev/null || log_func() {
    declare -F "$1" >/dev/null
    if [ $? -eq 0 ]; then
        start=`date +%s`
        echo -e "$(date)   start:   \t$1" >> $LOG_FILE
        $@
        end=`date +%s`
        echo -e "$(date)   end ($((end-start))s):\t$1" >> $LOG_FILE
    else
        echo "Error: $1 is not a function"
        exit -1
    fi
}

function setup_pre_post_sleep_actions() {

    dest_script_path="/usr/local/bin"
    local_state_path="/var/lib/libvirt"
    libvirt_script_path=$(realpath "$scriptpath/../../libvirt_scripts/")

    # script for handling sleep dependencies
    tee libvirt-guests-sleep-dep.sh &>/dev/null <<EOF
#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

# define wake source to enable before sleep here
declare -a wake_sources_to_enable >/dev/null
wake_sources_to_enable=("XDCI"
                        "XHCI"
                        "GLAN")

# define wake source to be disabled before sleep here
declare -a wake_sources_to_disable >/dev/null
wake_sources_to_disable=()


function enable_wake_sources() {
    local -n sources=\$1
    local -n enabled_sources=\$2
    for src in "\${sources[@]}"; do
        set +e
        status=\$(cat /proc/acpi/wakeup | grep \$src | awk '{ print \$3 }')
        set -e
        if [[ "\$status" =~ "disabled" ]]; then
            echo \$src | sudo tee /proc/acpi/wakeup >/dev/null
            enabled_sources+=(\$src)
        fi
    done
}

function disable_wake_sources() {
    local -n sources=\$1
    local -n disabled_sources=\$2
    for src in "\${sources[@]}"; do
        set +e
        status=\$(cat /proc/acpi/wakeup | grep \$src | awk '{ print \$3 }')
        set -e
        if [[ "\$status" =~ "enabled" ]]; then
            echo \$src | sudo tee /proc/acpi/wakeup >/dev/null
            disabled_sources+=(\$src)
        fi
    done
}

function usage() {
    local prog_name="\$0"
    printf "\$(basename "\$0") {pre|post} {suspend|hibernate}\n"
}

function main() {
    while [[ \$# -gt 0 ]]; do
        case "\$1" in
            -h|-\?|--help)
                usage
                return -1
                ;;

            pre)
                # Enable desired wake sources
                local wake_sources_enabled=()
                enable_wake_sources wake_sources_to_enable wake_sources_enabled
                cat /dev/null > $local_state_path/wake_sources_enabled.txt
                for src in "\${wake_sources_enabled[@]}"; do
                    echo \$src | sudo tee -a $local_state_path/wake_sources_enabled.txt >/dev/null
                done
                # disable undesired wake sources
                local wake_sources_disabled=()
                disable_wake_sources wake_sources_to_disable wake_sources_disabled
                cat /dev/null > $local_state_path/wake_sources_disabled.txt
                for src in "\${wake_sources_disabled[@]}"; do
                    echo \$src | sudo tee -a $local_state_path/wake_sources_disabled.txt >/dev/null
                done

                # Workaround for S4 hugepages/RAM allocation issue.
                # As for now, to Hibernate, RAM need to be free up 50%.
                # Reference: https://www.kernel.org/doc/Documentation/power/pci.rst (2.4.3. System Hibernation)
                # Backup used huge pages and free them
                nr_hugepg=\$(cat /proc/sys/vm/nr_hugepages)
                echo "nr_hugepg=\$nr_hugepg"
                sudo echo "\$nr_hugepg" > $local_state_path/hugepage_restore.txt
                echo "0" | sudo tee /proc/sys/vm/nr_hugepages >/dev/null
                return
                ;;

            post)
                # Restore any modified wake sources
                if [ -f "$local_state_path/wake_sources_enabled.txt" ]; then
                    local restore_sources=()
                    local restored_sources=()
                    readarray -t restore_sources < $local_state_path/wake_sources_enabled.txt
                    disable_wake_sources restore_sources restored_sources
                    sudo rm $local_state_path/wake_sources_enabled.txt
                fi
                if [ -f "$local_state_path/wake_sources_disabled.txt" ]; then
                    local restore_sources=()
                    local restored_sources=()
                    readarray -t restore_sources < $local_state_path/wake_sources_disabled.txt
                    enable_wake_sources restore_sources restored_sources
                    sudo rm $local_state_path/wake_sources_disabled.txt
                fi
                # Restore previously used hugepages
                if [ -f $local_state_path/hugepage_restore.txt ]; then
                    restore=\$(cat $local_state_path/hugepage_restore.txt)
                    echo "restore nr_hugepg=\$restore"
                    echo \$restore | sudo tee /proc/sys/vm/nr_hugepages >/dev/null
                    sudo rm $local_state_path/hugepage_restore.txt
                fi
                return
                ;;

            -?*)
                echo "Error: Invalid option: \$1"
                usage
                return -1
                ;;

            *)
                echo "Error: Invalid option: \$1"
                usage
                return -1
                ;;
        esac
        shift
    done
}

#-------------    main processes    -------------
trap 'echo "Error line \${LINENO}: \$BASH_COMMAND"' ERR

main "\$@"

echo "Done: \"\$(realpath \${BASH_SOURCE[0]}) \$@\""
EOF

    # create systemd libvirt-guests suspend/hibernate service files
    tee libvirt-guests-suspend.service &>/dev/null <<EOF
[Unit]
Description=libvirt guests suspend hook
Wants=libvirtd.service
After=network.target
After=time-sync.target
After=libvirtd.service
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=$dest_script_path/libvirt-guests-sleep.sh --suspend
ExecStart=$dest_script_path/libvirt-guests-sleep-dep.sh pre suspend
ExecStop=$dest_script_path/libvirt-guests-sleep-dep.sh post suspend ; $dest_script_path/libvirt-guests-sleep.sh --resume

[Install]
RequiredBy=suspend.target systemd-suspend.service
EOF

    tee libvirt-guests-hibernate.service &>/dev/null <<EOF
[Unit]
Description=libvirt guests hibernate hook
Wants=libvirtd.service
After=network.target
After=time-sync.target
After=libvirtd.service
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=$dest_script_path/libvirt-guests-sleep.sh --hibernate
ExecStart=$dest_script_path/libvirt-guests-sleep-dep.sh pre hibernate
ExecStop=$dest_script_path/libvirt-guests-sleep-dep.sh post hibernate

[Install]
RequiredBy=hibernate.target systemd-hibernate.service
EOF
    sudo cp $libvirt_script_path/libvirt-guests-sleep.sh $dest_script_path/
    sudo chmod +x $dest_script_path/libvirt-guests-sleep.sh
    sudo chown root:root $dest_script_path/libvirt-guests-sleep.sh

    sudo mv libvirt-guests-sleep-dep.sh $dest_script_path/
    sudo chmod +x $dest_script_path/libvirt-guests-sleep-dep.sh
    sudo chown root:root $dest_script_path/libvirt-guests-sleep-dep.sh

    sudo chown root:root libvirt-guests-suspend.service libvirt-guests-hibernate.service
    sudo chmod 644 libvirt-guests-suspend.service libvirt-guests-hibernate.service
    sudo mv libvirt-guests-suspend.service libvirt-guests-hibernate.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable libvirt-guests-suspend.service
    sudo systemctl enable libvirt-guests-hibernate.service
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

log_func setup_pre_post_sleep_actions || exit -1

echo "Done: \"$(realpath ${BASH_SOURCE[0]}) $@\""
