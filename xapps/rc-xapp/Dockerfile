# RAN Control xApp Dockerfile
# O-RAN Release J compliant
FROM python:3.11-slim

LABEL maintainer="O-RAN xApp Developer"
LABEL description="RAN Control xApp for O-RAN Release J"
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
ENV RMR_SRC_ID=ran-control
ENV PYTHONUNBUFFERED=1

# Install Python dependencies
# Install ricsdl 3.0.2 first to ensure compatibility with redis 4.x
# (ricxappframe 3.2.2 depends on ricsdl>=3.0.0,<4.0.0, which might pull 3.0.0)
COPY requirements.txt .
RUN pip install --no-cache-dir ricsdl==3.0.2 && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

# Create directories
RUN mkdir -p /app/logs && \
    mkdir -p /app/data

# Create health check script
RUN echo '#!/bin/bash\ncurl -f http://localhost:8100/health/alive || exit 1' > /usr/local/bin/health_check.sh && \
    chmod +x /usr/local/bin/health_check.sh

# Create RMR route file
RUN echo "newrt|start" > /app/config/rmr-routes.txt && \
    echo "mse|12040|1|e2term-rmr.ricplt:4560" >> /app/config/rmr-routes.txt && \
    echo "mse|12010|1|e2term-rmr.ricplt:4560" >> /app/config/rmr-routes.txt && \
    echo "mse|12012|1|e2term-rmr.ricplt:4560" >> /app/config/rmr-routes.txt && \
    echo "mse|12041|1|ran-control:4580" >> /app/config/rmr-routes.txt && \
    echo "mse|12042|1|ran-control:4580" >> /app/config/rmr-routes.txt && \
    echo "mse|12050|1|ran-control:4580" >> /app/config/rmr-routes.txt && \
    echo "mse|12011|1|ran-control:4580" >> /app/config/rmr-routes.txt && \
    echo "mse|12013|1|ran-control:4580" >> /app/config/rmr-routes.txt && \
    echo "mse|20010|1|ran-control:4580" >> /app/config/rmr-routes.txt && \
    echo "mse|20011|1|a1mediator-rmr.ricplt:4562" >> /app/config/rmr-routes.txt && \
    echo "newrt|end" >> /app/config/rmr-routes.txt

# Create non-root user
RUN useradd -m -u 1000 xapp && \
    chown -R xapp:xapp /app

# Switch to non-root user
USER xapp

# Expose ports
EXPOSE 4580 4581 8100

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/health_check.sh

# Run the xApp
CMD ["python3", "/app/src/ran_control.py"]
