"""Minimal Flask app — sample workload for the DevSecOps pipeline."""
import os

from flask import Flask

app = Flask(__name__)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}, 200


@app.get("/")
def index():
    return {"service": "app-python", "env": os.environ.get("APP_ENV", "unknown")}, 200


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080)
