import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)
VERSION = os.getenv("APP_VERSION", "dev")


@app.route("/")
def home():
    return jsonify(
        message="Deployed via GitHub Actions + Jenkins!",
        version=VERSION,
        pod=socket.gethostname(),
    )


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
