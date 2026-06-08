FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Cloud Run sets PORT env variable (default 8080)
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=5s \
  CMD python -c "import requests; requests.get(f'http://localhost:{__import__(\"os\").getenv(\"PORT\",8080)}/api/health')" || exit 1

# Run the server
CMD exec uvicorn ultra_simple_server:app --host 0.0.0.0 --port ${PORT}
