FROM alpine:latest

# Install necessary tools for permission watching and ACLs
RUN apk add --no-cache \
    inotify-tools \
    acl \
    bash

COPY fixer.sh /usr/local/bin/fixer.sh

ENTRYPOINT ["/usr/local/bin/fixer.sh"]
