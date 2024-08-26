#!/bin/bash

# VMarchiver.sh - Version 1.9.2
# Script to list ZFS zvols, QCOW2 disks, and Libvirt VMs

# Global variable for QCOW2 path
QCOW2_PATH="/var/lib/libvirt/images"


# Function to get zvol size
get_zvol_size() {
    local zvol_path=$1
    zvol_path=${zvol_path#/dev/zvol/}
    zfs get -H -o value volsize "$zvol_path" 2>/dev/null
}

# Function to get zvol used space
get_zvol_used() {
    local zvol_path=$1
    zvol_path=${zvol_path#/dev/zvol/}
    zfs get -H -o value used "$zvol_path" 2>/dev/null
}

# Function to get number of snapshots for a zvol
get_zvol_snapshots() {
    local zvol_path=$1
    zvol_path=${zvol_path#/dev/zvol/}
    local snapshots=$(zfs list -t snapshot -o name -H $zvol_path 2>/dev/null | wc -l)
    if [ "$snapshots" -eq 0 ] && ! zfs list "$zvol_path" &>/dev/null; then
        echo ""
    else
        echo "$snapshots"
    fi
}

# Function to get QCOW2 disk size
get_qcow2_size() {
    local disk_path=$1
    qemu-img info "$disk_path" 2>/dev/null | awk '/virtual size:/ {print $3$4}'
}

# Function to get QCOW2 disk used space
get_qcow2_used() {
    local disk_path=$1
    qemu-img info "$disk_path" 2>/dev/null | awk '/disk size:/ {print $3$4}'
}

# New function to get QCOW2 snapshots
get_qcow2_snapshots() {
    local disk_path=$1
    local snapshot_count=$(qemu-img snapshot -l "$disk_path" 2>/dev/null | grep -c "^[0-9]")
    echo "$snapshot_count"
}


# Function to get VM UUID
get_vm_uuid() {
    local vm=$1
    virsh domuuid "$vm" 2>/dev/null
}

# Function to check if VM exists
vm_exists() {
    virsh list --all --name | grep -q "^$1$"
}

# Function to find associated VM for a zvol
find_associated_vm() {
    local zvol=$1
    local vm_name=$(basename $zvol)
    if vm_exists "$vm_name"; then
        echo "$vm_name"
    else
        virsh list --all --name | while read vm; do
            if virsh dumpxml "$vm" 2>/dev/null | grep -q "$zvol"; then
                echo "$vm"
                return
            fi
        done
    fi
}

# New function to list QCOW2 files
list_qcow2_files() {
    echo "VMarchiver v1.9.2 - Listing QCOW2 files in $QCOW2_PATH:"
    echo "-------------------------------------"
    printf "%-60s %-15s %-15s %-10s\n" "File Name" "Size" "Used" "Snapshots"
    echo "-------------------------------------"
    find "$QCOW2_PATH" -name "*.qcow2" | while read -r file; do
        filename=$(basename "$file")
        size=$(get_qcow2_size "$file")
        used=$(get_qcow2_used "$file")
        snapshots=$(get_qcow2_snapshots "$file")
        printf "%-60s %-15s %-15s %-10s\n" "$filename" "$size" "$used" "$snapshots"
    done
}


# Function to list ZFS zvols associated with VMs
list_zfs_zvols() {
    echo "VMarchiver v1.9.1 - Listing ZFS zvols associated with VMs:"
    echo "-------------------------------------"
    printf "%-45s %-25s %-10s %-10s %-10s\n" "Zvol" "VM" "Size" "Used" "Snapshots"
    echo "-------------------------------------"
    zfs list -t volume -o name -H | grep LIBVIRT | while read zvol; do
        vm_name=$(find_associated_vm "$zvol")
        size=$(get_zvol_size "$zvol")
        used=$(get_zvol_used "$zvol")
        snapshots=$(get_zvol_snapshots "$zvol")
        printf "%-45s %-25s %-10s %-10s %-10s\n" "$zvol" "${vm_name:--}" "$size" "$used" "$snapshots"
    done
}

# Function to list all Libvirt VMs
list_libvirt_vms() {
    local show_uuid=$1
    echo "VMarchiver v1.9.2 - Listing all VMs in Libvirt:"
    echo "-------------------------------------"
    if [ "$show_uuid" = true ]; then
        printf "%-30s %-15s %-36s %-15s %-60s %-10s %-10s %-10s\n" "VM Name" "State" "UUID" "Storage Type" "Path" "Size" "Used" "Snapshots"
    else
        printf "%-30s %-15s %-15s %-60s %-10s %-10s %-10s\n" "VM Name" "State" "Storage Type" "Path" "Size" "Used" "Snapshots"
    fi
    echo "-------------------------------------"
    virsh list --all --name | while IFS= read -r vm; do
        if [ ! -z "$vm" ]; then
            state=$(virsh domstate $vm)
            uuid=$(get_vm_uuid "$vm")
            virsh dumpxml $vm | grep -E '<source dev|<source file' | sed -n 's/.*\(dev\|file\)=["'"'"']\([^"'"'"']*\).*/\2/p' | while read disk; do
                if [[ $disk == /dev/zvol/* ]]; then
                    size=$(get_zvol_size "$disk")
                    used=$(get_zvol_used "$disk")
                    snapshots=$(get_zvol_snapshots "$disk")
                    if [ -n "$size" ] && [ -n "$used" ]; then
                        if [ "$show_uuid" = true ]; then
                            printf "%-30s %-15s %-36s %-15s %-60s %-10s %-10s %-10s\n" "$vm" "$state" "$uuid" "ZVol" "$disk" "$size" "$used" "$snapshots"
                        else
                            printf "%-30s %-15s %-15s %-60s %-10s %-10s %-10s\n" "$vm" "$state" "ZVol" "$disk" "$size" "$used" "$snapshots"
                        fi
                    else
                        if [ "$show_uuid" = true ]; then
                            printf "%-30s %-15s %-36s %-15s %-60s\n" "$vm" "$state" "$uuid" "ZVol" "$disk"
                        else
                            printf "%-30s %-15s %-15s %-60s\n" "$vm" "$state" "ZVol" "$disk"
                        fi
                    fi
                elif [[ $disk == *.qcow2 ]]; then
                    size=$(get_qcow2_size "$disk")
                    used=$(get_qcow2_used "$disk")
                    snapshots=$(get_qcow2_snapshots "$disk")
                    if [ "$show_uuid" = true ]; then
                        printf "%-30s %-15s %-36s %-15s %-60s %-10s %-10s %-10s\n" "$vm" "$state" "$uuid" "QCOW2" "$disk" "$size" "$used" "$snapshots"
                    else
                        printf "%-30s %-15s %-15s %-60s %-10s %-10s %-10s\n" "$vm" "$state" "QCOW2" "$disk" "$size" "$used" "$snapshots"
                    fi
                else
                    if [ "$show_uuid" = true ]; then
                        printf "%-30s %-15s %-36s %-15s %-60s\n" "$vm" "$state" "$uuid" "Unknown" "$disk"
                    else
                        printf "%-30s %-15s %-15s %-60s\n" "$vm" "$state" "Unknown" "$disk"
                    fi
                fi
            done
        fi
    done
}


# Function to display help
show_help() {
    echo "VMarchiver v1.9.2"
    echo "Usage: $0 [OPTION]"
    echo "Options:"
    echo "  --vms              List all Libvirt VMs"
    echo "  --vms --all        List all Libvirt VMs including UUID"
    echo "  --qcow2            List all QCOW2 files in $QCOW2_PATH"
    echo "  --zfs              List ZFS zvols associated with VMs"
    echo "  --help             Display this help message"
    echo
    echo "Examples:"
    echo "  $0 --vms"
    echo "  $0 --vms --all"
    echo "  $0 --qcow2"
    echo "  $0 --zfs"
    echo
    echo "If no option is provided, or if an invalid option is used, this help message will be displayed."
}


# Main menu
if [ $# -eq 0 ]; then
    show_help
else
    case "$1" in
        --zfs)
            list_zfs_zvols
            ;;
        --vms)
            if [ "$2" = "--all" ]; then
                list_libvirt_vms true
            else
                list_libvirt_vms false
            fi
            ;;
        --qcow2)
            list_qcow2_files
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Error: Invalid option '$1'"
            echo
            show_help
            exit 1
            ;;
    esac
fi
