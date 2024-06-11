#!/bin/bash

# Parse command-line options
while getopts ":s:U:P:p:b:f:u:e:d:n:" opt; do
    case $opt in
        s) SFTP_SERVER="$OPTARG" ;;
        U) SFTP_USER="$OPTARG" ;;
        P) SFTP_PORT="$OPTARG" ;;
        p) SFTP_PASSWORD="$OPTARG" ;;
        b) SFTP_BASE_PATH="$OPTARG" ;;
        f) URL_FILE="$OPTARG" ;;
        u) URL="$OPTARG" ;;
        e) FILE_EXTENSIONS="$OPTARG" ;;
        d) DEPTH="$OPTARG" ;;
        n) FILE_NAME="$OPTARG" ;;
    esac
done
shift $((OPTIND -1))

# Check if SFTP server, user, password, and base path are provided
if [ -z "$SFTP_SERVER" ] || [ -z "$SFTP_USER" ] || [ -z "$SFTP_PASSWORD" ] || [ -z "$URL" ] || [ -z "$SFTP_PORT" ]; then
    echo "SFTP server, user, password, base path, URL and port must be specified."
    exit 1
fi

# Function to extract domain from URL
extract_domain() {
    local url=$1
    # Remove protocol part
    local domain=${url#*://}
    # Extract domain
    domain=${domain%%/*}
    echo "$domain"
}

sanitize_domain() {
    local domain=$1
    # Using sed to remove characters not matching the regex [a-zA-Z0-9]+
    sanitized_domain=$(echo "$domain" | sed -E 's/[^a-zA-Z0-9]+//g')
    echo "$sanitized_domain"
}

# Function to list directories and find the highest ID
list_directories_and_find_highest_id() {
    local sftp_server=$1
    local sftp_user=$2
    local sftp_password=$3
    local sftp_base_path=$4
    local url=$5
    local sftp_port=$6

    local domain=$(sanitize_domain $(extract_domain "$url"))
    local highest_id=0
    local existing_directory=""

    # Check if the directory for the domain already exists
    directories=$(curl -s --insecure --user "$sftp_user:$sftp_password" "sftp://$sftp_server:$sftp_port/$sftp_base_path/" | grep '^d' | awk '{print $9}')
    for dir in $directories; do
        if [[ $dir == "01_"*"_${domain}" ]]; then
            existing_directory=$dir
            break
        fi
    done

    if [[ ! -z $existing_directory ]]; then
        echo $existing_directory
    else
        # Find the highest ID
        for dir in $directories; do
            if [[ $dir =~ ^01_([0-9]{5})_ ]]; then
                id=${BASH_REMATCH[1]}
                if ((10#$id > 10#$highest_id)); then
                    highest_id=$id
                fi
            fi
        done

        # Increment the highest ID by 1
        next_id=$(printf "%05d" $((10#$highest_id + 1)))

        echo "01_${next_id}_$domain"
    fi
}

# Function to reconstruct the folder tree like the URL
reconstruct_folder_tree() {
    local url=$1
    local base_path=$2
    local next_folder=$3

    # Remove protocol and domain from the URL
    path=${url#*://}

    # Check if base path is "/"
    if [ -z "$base_path" ]; then
        # Output reconstructed path without double initial slash
        echo "$next_folder/$path"
    else
        # Output reconstructed path with base path and URL path
        echo "$base_path/$next_folder/$path"
    fi
}

# Generate the next folder name
next_folder=$(list_directories_and_find_highest_id "$SFTP_SERVER" "$SFTP_USER" "$SFTP_PASSWORD" "$SFTP_BASE_PATH" "$URL" "$SFTP_PORT")

# Reconstruct folder tree based on the URL
echo $(reconstruct_folder_tree "$URL" "$SFTP_BASE_PATH" "$next_folder")
