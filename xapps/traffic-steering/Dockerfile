# Traffic Steering xApp Dockerfile
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    make \
    cmake \
    git \
    curl \
    libboost-all-dev \
    && rm -rf /var/lib/apt/lists/*

# Install RMR library
RUN git clone https://gerrit.o-ran-sc.org/r/ric-plt/lib/rmr && \
    cd rmr && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make install && \
    cd ../.. && \
    rm -rf rmr

# Set library path for RMR
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Install Python dependencies
# Install ricsdl 3.0.2 first to ensure compatibility with redis 4.x
COPY requirements.txt .
RUN pip install --no-cache-dir ricsdl==3.0.2 && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

# Create non-root user
RUN useradd -m -u 1000 xapp && \
    chown -R xapp:xapp /app

# Switch to non-root user
USER xapp

# Expose RMR ports
EXPOSE 4560 4561

# Expose health check port
EXPOSE 8080

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV RMR_SEED_RT=/app/config/rmr-routes.txt
ENV RMR_SRC_ID=traffic-steering

# Run the xApp
CMD ["python3", "/app/src/traffic_steering.py"]
