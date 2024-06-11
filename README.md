# URL Crawler and SFTP Uploader

This script crawls URLs, downloads files, and uploads them to an SFTP server. It provides flexibility in specifying URLs to crawl, file extensions to filter, SFTP server details, and depth of crawling.

## Usage

```bash
./crawler.sh [-f url_file] [-u urls] [-s sftp_server] [-P sftp_port] [-U sftp_user] [-p sftp_password] [-e file_extensions] [-b sftp_base_path] [-d depth] [-x external_script] [-h]
```

### Options

- `-f url_file`: File containing a list of URLs (one per line).
- `-u urls`: Comma-separated list of URLs to crawl or direct links.
- `-s sftp_server`: SFTP server address.
- `-P sftp_port`: SFTP server port (default is 22).
- `-U sftp_user`: SFTP username.
- `-p sftp_password`: SFTP password.
- `-e file_extensions`: File extensions to filter and crawl (comma-separated, e.g., `pcap,txt`).
- `-b sftp_base_path`: Base path on the SFTP server (default is `/`).
- `-d depth`: Depth of crawling (-1 for infinite, 0 only direct link, positive integers for custom depth, default is 1).
- `-x external_script`: External script to generate the path suffix for the output file.
- `-h`: Display help information.

## Examples

```bash
./crawler.sh -f urls.txt -e txt,pdf -d 2
./crawler.sh -u http://example.com,https://example.org -e html,css -d 1
./crawler.sh -x generate_next_folder.sh
```

## Dependencies

- `curl`: Used for downloading files and checking URL accessibility.

## Security

- Ensure that sensitive information like passwords is handled securely.
- Consider using environment files for managing configuration variables.

## Contributing

Contributions are welcome! If you find any issues or have suggestions for improvement, please feel free to open an issue or submit a pull request.
