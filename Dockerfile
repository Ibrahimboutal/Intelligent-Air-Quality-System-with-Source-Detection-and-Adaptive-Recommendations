FROM python:3.9-slim

WORKDIR /app

# Install system dependencies for pyserial
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies
RUN pip install --no-cache-dir pyserial

# Copy the monitoring script
COPY scripts/air_quality_monitor.py .

# Create logs directory
RUN mkdir logs

# Environment variables (can be overridden by docker-compose)
ENV SERIAL_PORT=/dev/ttyUSB0
ENV BAUD_RATE=9600
ENV MATLAB_IP=127.0.0.1
ENV MATLAB_PORT=5005

# Run the monitor
CMD ["python", "air_quality_monitor.py"]
