# probably change to better
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
LABEL name="windows_mount"

# Combine all operations into one RUN layer to keep the image light
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    # Add Neovim PPA
    && add-apt-repository ppa:neovim-ppa/unstable -y \
    && apt-get update \
    # Install packages
    && apt-get install -y --no-install-recommends \
    sshfs \
    sshpass \
    neovim \
    npm \
    curl \
    fzf \
    gcc \
    make \
    git \
    rsync \
    inotify-tools \
    openssh-client \
    ca-certificates \
    # CLEANUP: Remove setup tools to save space
    && apt-get purge -y --auto-remove software-properties-common gpg-agent \
    && rm -rf /var/lib/apt/lists/* \
    # Setup directories
    && mkdir -p /key /mnt/workdir

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
