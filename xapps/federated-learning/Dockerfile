# Federated Learning xApp Dockerfile
# O-RAN Release J compliant
FROM python:3.11-slim

LABEL maintainer="O-RAN xApp Developer"
LABEL description="Federated Learning xApp for O-RAN Release J"
LABEL version="1.0.0"

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
    libssl-dev \
    libhdf5-dev \
    pkg-config \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

# Install RMR library (Release J version)
RUN git clone https://gerrit.o-ran-sc.org/r/ric-plt/lib/rmr && \
    cd rmr && \
    git checkout 4.9.4 && \
    mkdir build && \
    cd build && \
    cmake .. -DPACK_EXTERNALS=1 && \
    make install && \
    ldconfig && \
    cd ../.. && \
    rm -rf rmr

# Set library path for RMR
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
ENV RMR_SEED_RT=/app/config/rmr-routes.txt
ENV RMR_SRC_ID=federated-learning
ENV PYTHONUNBUFFERED=1

# Install Python dependencies
# CRITICAL: Install ricsdl first to lock down redis version
COPY requirements.txt .
RUN pip install --no-cache-dir ricsdl==3.0.2 && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY config/ ./config/
COPY models/ ./models/
COPY aggregator/ ./aggregator/

# Create directories
RUN mkdir -p /app/models/global && \
    mkdir -p /app/models/local && \
    mkdir -p /app/models/checkpoints && \
    mkdir -p /app/data/train && \
    mkdir -p /app/data/test && \
    mkdir -p /app/logs

# Create health check script
RUN echo '#!/bin/bash\ncurl -f http://localhost:8110/health/alive || exit 1' > /usr/local/bin/health_check.sh && \
    chmod +x /usr/local/bin/health_check.sh

# Create RMR route file
RUN echo "newrt|start" > /app/config/rmr-routes.txt && \
    echo "mse|30001|1|e2term-rmr.ricplt:4560" >> /app/config/rmr-routes.txt && \
    echo "mse|30003|1|e2term-rmr.ricplt:4560" >> /app/config/rmr-routes.txt && \
    echo "mse|30006|1|e2term-rmr.ricplt:4560" >> /app/config/rmr-routes.txt && \
    echo "mse|30007|1|e2term-rmr.ricplt:4560" >> /app/config/rmr-routes.txt && \
    echo "mse|30002|1|federated-learning:4590" >> /app/config/rmr-routes.txt && \
    echo "mse|30004|1|federated-learning:4590" >> /app/config/rmr-routes.txt && \
    echo "mse|30005|1|federated-learning:4590" >> /app/config/rmr-routes.txt && \
    echo "mse|30008|1|federated-learning:4590" >> /app/config/rmr-routes.txt && \
    echo "mse|30009|1|federated-learning:4590" >> /app/config/rmr-routes.txt && \
    echo "mse|12050|1|federated-learning:4590" >> /app/config/rmr-routes.txt && \
    echo "newrt|end" >> /app/config/rmr-routes.txt

# Create non-root user
RUN useradd -m -u 1000 xapp && \
    chown -R xapp:xapp /app

# Switch to non-root user
USER xapp

# Expose ports
EXPOSE 4590 4591 8110

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/health_check.sh

# Run the xApp
CMD ["python3", "/app/src/federated_learning.py"]
