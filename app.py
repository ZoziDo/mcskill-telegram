from flask import Flask, request
import requests
import os

app = Flask(__name__)

TOKEN = os.getenv("TOKEN")
CHAT_ID = os.getenv("CHAT_ID")
KEY = os.getenv("KEY")

@app.route("/")
def home():
    return "online"

@app.route("/send")
def send():
    if request.args.get("key") != KEY:
        return "denied", 403

    msg = request.args.get("msg", "")
    if not msg:
        return "empty"

    requests.post(
        f"https://api.telegram.org/bot{TOKEN}/sendMessage",
        data={"chat_id": CHAT_ID, "text": msg}
    )

    return "ok"

