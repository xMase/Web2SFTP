#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 [-f url_file] [-u urls] [-s sftp_server] [-U sftp_user] [-p sftp_password] [-e file_extensions] [-b sftp_base_path] [-d depth] [-x external_script]"
    echo "  -f url_file         File containing a list of URLs (one per line)"
    echo "  -u urls             Comma-separated list of URLs to crawl or direct links"
    echo "  -s sftp_server      SFTP server address"
    echo "  -U sftp_user        SFTP username"
    echo "  -p sftp_password    SFTP password"
    echo "  -e file_extensions  File extensions to filter and crawl (comma-separated, e.g., pcap,txt)"
    echo "  -b sftp_base_path   Base path on the SFTP server (default is '/')"
    echo "  -d depth            Depth of crawling (-1 for infinite, 0 only direct link, positive integers for custom depth, default is 1)"
    echo "  -x external_script  External script to generate the path suffix for the output file"
    exit 1
}

# Function to display help information
help() {
    echo "This script crawls URLs and uploads files to an SFTP server."
    echo "You can provide either a file containing a list of URLs or a comma-separated list of URLs."
    echo "Example usage:"
    echo "  $0 -f urls.txt -e txt,pdf -d 2"
    echo "  $0 -u http://example.com,https://example.org -e html,css -d 1"
    echo "  $0 -x generate_next_folder.sh -o output.txt"
    exit 0
}

# Function to download and upload files from a given URL
process_url() {
    local url=$1
    local depth=$2

    url=$(echo "$url" | sed 's/[[:space:]]*$//') # Trim trailing spaces

    # Set wget depth parameter
    if [ "$depth" == "-1" ]; then
        wget_depth="inf"
    else
        wget_depth="$depth"
    fi

    file_extensions=$(echo "$FILE_EXTENSIONS" | tr ',' '|')

    echo "Filtering files with extensions: $file_extensions"

    # Download files matching the specified criteria
    # --reject-regex "(.*)\?(.*)" : Reject URLs with query parameters
    # --reject-regex 'html' : Reject URLs ending with 'html'
    wget -r --accept "$file_extensions" --reject-regex '(.*)\?(.*)|.html' -e robots=off --ignore-case --spider --no-directories --no-parent --level="$wget_depth" "$url" 2>&1 | \
    while read -r line; do       
        # Extract URLs using parameter expansion and pattern matching
        if [[ "$line" =~ https?://[^[:space:]]+ ]]; then 
            download_url="${BASH_REMATCH[0]}"            
            echo "$download_url"
            if [[ "$download_url" =~ \.($file_extensions)$ ]]; then            
                echo "Downloading file: $download_url"
                filename=$(basename "$download_url")

                # If an external script is specified, use it to generate the path suffix
                if [ -n "$EXTERNAL_SCRIPT" ]; then
                    sftp_path=$(bash "$EXTERNAL_SCRIPT" -s "$SFTP_SERVER" -U "$SFTP_USER" -p "$SFTP_PASSWORD" -P "$SFTP_PORT" -b "$SFTP_BASE_PATH" -u "$download_url")           
                    # check error code
                    if [ $? -ne 0 ]; then
                        echo "Error in external script: $sftp_path"
                        exit 1
                    fi
                else
                    sftp_path="$SFTP_BASE_PATH/$filename"
                fi

                # Check if file not exists 
                if ! curl --insecure --user "$SFTP_USER:$SFTP_PASSWORD" --head --fail "sftp://$SFTP_SERVER:$SFTP_PORT/$sftp_path" > /dev/null 2>&1; then
                    # Download the file and upload it to the SFTP server
                    echo "Downloading $filename and uploading to $sftp_path"
                    curl -s "$download_url" | curl --insecure -T - --user "$SFTP_USER:$SFTP_PASSWORD" "sftp://$SFTP_SERVER:$SFTP_PORT/$sftp_path.tmp" --ftp-create-dirs

                    # Rename the file after upload is complete
                    curl --insecure --user "$SFTP_USER:$SFTP_PASSWORD" --head "sftp://$SFTP_SERVER:$SFTP_PORT" -Q "RENAME $sftp_path.tmp $sftp_path" 2>&1
                else 
                    echo "File $(basename "$download_url") already exists on the server"
                fi               
            fi
        fi
    done    
}

# Automatically load .env file if it exists
if [ -f ".env" ]; then
    source .env
fi

# Set default values
SFTP_PORT=${SFTP_PORT:-22}

# Parse command-line options
while getopts ":f:u:s:P:U:p:e:b:d:x:h" opt; do
    case $opt in
        f) URL_FILE="$OPTARG" ;;
        u) IFS=',' read -ra URLS <<< "$OPTARG" ;;
        s) SFTP_SERVER="$OPTARG" ;;
        P) SFTP_PORT="$OPTARG" ;;
        U) SFTP_USER="$OPTARG" ;;
        p) SFTP_PASSWORD="$OPTARG" ;;
        e) FILE_EXTENSIONS="$OPTARG" ;;
        b) SFTP_BASE_PATH="$OPTARG" ;;
        d) DEPTH="$OPTARG" ;;
        x) EXTERNAL_SCRIPT="$OPTARG" ;;
        h) help ;;
        *) usage ;;
    esac
done
shift $((OPTIND -1))

# Set default depth if not provided
DEPTH=${DEPTH:5}

# Check if SFTP server, user, password, file extensions, and base path are provided
if [ -z "$SFTP_SERVER" ] || [ -z "$SFTP_USER" ] || [ -z "$SFTP_PASSWORD" ] || [ -z "$FILE_EXTENSIONS" ]; then
    echo "SFTP server, user, password, file extensions, and base path must be specified via command line or environment file."
    usage
fi

# Prompt for the SFTP password if not provided
if [ -z "$SFTP_PASSWORD" ]; then
    echo -n "Enter SFTP password: "
    read -s SFTP_PASSWORD
    echo
fi

# Process URLs from file or single URL
if [ -n "$URL_FILE" ]; then
    while IFS= read -r url || [ -n "$url" ]; do
        [ -z "$url" ] && continue # Skip empty lines
        process_url "$url" $DEPTH
    done < "$URL_FILE"
elif [ ${#URLS[@]} -gt 0 ]; then
    for url in "${URLS[@]}"; do   
        process_url "$url" $DEPTH
    done
else
    usage
fi

echo "All files have been uploaded to the SFTP server."
