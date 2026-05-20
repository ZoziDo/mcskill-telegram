from flask import Flask, request
import requests
import os

app = Flask(__name__)

TOKEN = os.getenv("TOKEN")
CHAT_ID = os.getenv("CHAT_ID")
KEY = os.getenv("KEY")

@app.route("/send")
def send():
    if request.args.get("key") != KEY:
        return "denied"

    msg = request.args.get("msg", "")

    requests.post(
        f"https://api.telegram.org/bot{TOKEN}/sendMessage",
        data={
            "chat_id": CHAT_ID,
            "text": msg
        }
    )

    return "ok"

app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)))