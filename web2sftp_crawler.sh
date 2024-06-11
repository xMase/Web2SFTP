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

# Function to check if URL is accessible
is_url_accessible() {
    local url=$1
    if curl --output /dev/null --silent --head --fail "$url"; then
        return 0
    else
        return 1
    fi
}

# Function to check if URL ends with one of the specified file extensions
url_has_extension() {
    local url=$1
    local extensions=$2
    local filename=$(basename "$url")
    local file_extension="${filename##*.}"
    IFS=',' read -ra ext_list <<< "$extensions"
    for ext in "${ext_list[@]}"; do
        [ "$file_extension" = "$ext" ] && return 0
    done
    return 1
}

# Function to remove query parameters from a URL
remove_query_params() {
    local url=$1
    echo "${url%%\?*}"
}

# Function to download and upload files from a given URL
process_url() {
    local url=$1
    local depth=$2
    url=$(remove_query_params "$url")
    url=$(echo "$url" | sed 's/[[:space:]]*$//') # Trim trailing spaces

    # Check if the URL has one of the specified file extensions
    if url_has_extension "$url" "$FILE_EXTENSIONS"; then
        echo "Processing URL: $url"

        # Check if the URL is accessible
        if ! is_url_accessible "$url"; then
            echo "$url is NOT accessible"
            return
        fi

        # Download and upload the file
        local filename=$(basename "$url")
        local sftp_path="$SFTP_BASE_PATH/$filename"
        
        # If an external script is specified, use it to generate the path suffix
        if [ -n "$EXTERNAL_SCRIPT" ]; then
            sftp_path=$(bash "$EXTERNAL_SCRIPT" -s "$SFTP_SERVER"  -P "$SFTP_PORT" -U "$SFTP_USER" -p "$SFTP_PASSWORD"  -b "$SFTP_BASE_PATH" -f "$URL_FILE" -u "$url" -e "$FILE_EXTENSIONS" -d "$DEPTH" -n "$filename")
            # check error code
            if [ $? -ne 0 ]; then
                echo "Error in external script"
                exit 1
            fi
        fi

        # Check if file already exists
        if curl --insecure --user "$SFTP_USER:$SFTP_PASSWORD" --head --fail "sftp://$SFTP_SERVER:$SFTP_PORT/$sftp_path" > /dev/null 2>&1; then
            echo "File $filename already exists on the server"
            return
        fi
        
        # Download the file and upload it to the SFTP server
        echo "Downloading $filename and uploading to $sftp_path"
        curl -s "$url" | curl --insecure -T - --user "$SFTP_USER:$SFTP_PASSWORD" "sftp://$SFTP_SERVER:$SFTP_PORT/$sftp_path.tmp" --ftp-create-dirs

        # Rename the file after upload is complete
        curl --insecure --user "$SFTP_USER:$SFTP_PASSWORD" "sftp://$SFTP_SERVER:$SFTP_PORT/$sftp_path.tmp" -Q "RENAME $sftp_path.tmp $sftp_path"
    fi

    # Process URLs recursively if depth is not 0
    if [ "$depth" != "0" ]; then
        local new_depth=$((depth - 1))
        local new_urls
        base_url=$(echo "$url" | sed 's#/$##')  # Remove trailing slash if exists
        new_urls=$(curl -s "$url" | grep -o 'href="[^"]*"' | sed 's/href="//;s/"$//' | while read -r link; do
            link=$(remove_query_params "$link")
            # Check if the link is an absolute URL
            if [[ "$link" =~ ^https?:// ]]; then
                # Extract the domain part from the base URL
                base_domain=$(echo "$base_url" | awk -F/ '{print $3}')
                # Extract the domain part from the link
                link_domain=$(echo "$link" | awk -F/ '{print $3}')
                # Check if the link domain matches the base domain
                if [ "$base_domain" = "$link_domain" ]; then
                    echo "$link"
                fi
            else
                # Construct the absolute URL based on the base URL and the relative link
                if [[ "$base_url" == *"/" && "$link" == /* ]]; then
                    echo "${base_url}${link:1}"  # Remove the leading slash from the relative path
                elif [[ "$base_url" != *"/" && "$link" != /* ]]; then
                    echo "${base_url}/${link}"  # Add a slash between the base URL and relative path
                else
                    echo "${base_url}${link}"   # Concatenate as is
                fi
            fi
        done | sort -u)
        
        for new_url in $new_urls; do
            if [ -z "${visited_urls[$new_url]}" ]; then
                echo "Found new URL: $new_url"
                visited_urls[$new_url]=1
                process_url "$new_url" $new_depth
            fi
        done
    fi
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
DEPTH=${DEPTH:-1}

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

# Initialize an associative array to track visited URLs
declare -A visited_urls

# Process URLs from file or single URL
if [ -n "$URL_FILE" ]; then
    while IFS= read -r url || [ -n "$url" ]; do
        [ -z "$url" ] && continue # Skip empty lines
        url=$(remove_query_params "$url")
        if [ -z "${visited_urls[$url]}" ]; then
            visited_urls[$url]=1
            process_url "$url" $DEPTH
        fi
    done < "$URL_FILE"
elif [ ${#URLS[@]} -gt 0 ]; then
    for url in "${URLS[@]}"; do
        url=$(remove_query_params "$url")
        if [ -z "${visited_urls[$url]}" ]; then
            visited_urls[$url]=1
            process_url "$url" $DEPTH
        fi
    done
else
    usage
fi

echo "All files have been uploaded to the SFTP server."
