FROM alpine:3.9

RUN apk add --no-cache bash curl wget

COPY web2sftp_crawler.sh /app/
COPY generate_next_folder.sh /app/

# Set the working directory
WORKDIR /app

# Run the script
CMD ["/bin/bash", "/app/web2sftp_crawler.sh"]