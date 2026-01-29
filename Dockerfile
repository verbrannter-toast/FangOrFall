FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    wget unzip \
    && rm -rf /var/lib/apt/lists/*

# Download Godot headless
RUN wget https://github.com/godotengine/godot-builds/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip && \
    unzip Godot_v4.3-stable_linux.x86_64.zip && \
    rm Godot_v4.3-stable_linux.x86_64.zip && \
    mv Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot && \
    chmod +x /usr/local/bin/godot

# Copy project
COPY godot-project /app
WORKDIR /app

# Railway $PORT (9080 for local tests)
ENV PORT=9080
EXPOSE $PORT

# Start server
CMD ["godot", "--headless", "--", "--server"]
