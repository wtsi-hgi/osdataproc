FROM python:3.8-slim

# Install system dependencies needed for Python packages (e.g., cryptography)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libffi-dev \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /opt/osdataproc

# Copy the application source so that osdataproc.py sits next to vars.yml
COPY . /opt/osdataproc

# Install Python runtime dependencies only (do not install the module package)
RUN pip install --no-cache-dir \
        ansible==2.9.4 \
        Jinja2==3.0.3 \
        jmespath==0.9.4 \
        python-openstackclient==5.2.0 \
        openstacksdk==0.46.0

# Provide a lightweight CLI shim so `osdataproc` runs the script with its co-located vars.yml
RUN printf '#!/bin/sh\nexec python3 /opt/osdataproc/osdataproc.py "$@"\n' > /usr/local/bin/osdataproc \
    && chmod +x /usr/local/bin/osdataproc

# Default workdir; no entrypoint so callers can override. To test: `osdataproc --help`


