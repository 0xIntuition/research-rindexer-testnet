FROM postgres:16

# Install Python and PL/Python extension
RUN apt-get update && \
    apt-get install -y \
    postgresql-plpython3-16 \
    python3-pip && \
    rm -rf /var/lib/apt/lists/*

# Install Python packages for Keccak-256
RUN pip3 install --break-system-packages eth-hash[pycryptodome]
