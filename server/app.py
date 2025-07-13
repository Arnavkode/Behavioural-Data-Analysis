from flask import Flask, request, jsonify
from model import XGBWrapper
import numpy as np

app = Flask(__name__)
wrapper = XGBWrapper(model_path="xgboost_with_11classes.pkl")

@app.route("/predict", methods=["POST"])
def predict():
    payload = request.get_json(force=True)
    flat = payload.get("data")

    seq_len = 50
    feat_dim = 12
    expected_len = seq_len * feat_dim

    # Validate input
    if not isinstance(flat, list) or len(flat) != expected_len:
        return jsonify(error=f"'data' must be a list of length {expected_len}"), 400

    try:
        # reshape into a single window
        arr = np.array(flat, dtype=np.float32).reshape(seq_len, feat_dim)
        windows = [arr]

        # get hard & soft predictions
        # preds = wrapper.predict_batch(windows)
        probs = wrapper.predict(flat)

        # final = int(preds[0])

    except Exception as e:
        return jsonify(error=str(e)), 500

    return jsonify(probabilities=probs)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
