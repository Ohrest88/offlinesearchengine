#Usage:
#1) docker build -t pocketsearch-builder .
#2) docker create --name temp pocketsearch-builder
#3) docker cp temp:/home/builder/app/PocketSearchEngine-x86_64.AppImage .
#4) docker rm temp

FROM ubuntu:20.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    git \
    wget \
    unzip \
    xz-utils \
    zip \
    libgtk-3-dev \
    cmake \
    ninja-build \
    clang \
    pkg-config \
    libblkid-dev \
    liblzma-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -ms /bin/bash builder
USER builder
WORKDIR /home/builder

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/builder/.cargo/bin:${PATH}"
RUN rustup default stable

# Install Flutter with exact version
RUN git clone https://github.com/flutter/flutter.git /home/builder/flutter
ENV PATH="/home/builder/flutter/bin:${PATH}"
WORKDIR /home/builder/flutter
RUN git fetch && \
    git checkout 3.29.0 && \
    ./bin/flutter precache && \
    ./bin/dart --version
WORKDIR /home/builder
RUN flutter doctor

# Set the working directory
WORKDIR /home/builder/app

# Before copying, switch back to root to handle permissions
USER root
COPY --chown=builder:builder . .

# Switch back to builder user
USER builder

# Clean and build with verbose output
RUN flutter clean && \
    flutter build linux --release -v

# Create AppImage
RUN chmod +x create_appimage.sh && \
    ./create_appimage.sh 