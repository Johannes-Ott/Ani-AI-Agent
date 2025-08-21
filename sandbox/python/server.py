
from flask import Flask, request, jsonify
import sys, io, contextlib

app = Flask(__name__)

@app.post("/run")
def run():
    code = request.json.get("code","")
    stdout = io.StringIO()
    stderr = io.StringIO()
    exit_code = 0
    ns = {}
    try:
        with contextlib.redirect_stdout(stdout):
            exec(code, ns, ns)
    except Exception as e:
        exit_code = 1
        print(repr(e), file=stderr)
    return jsonify(stdout=stdout.getvalue(), stderr=stderr.getvalue(), exit_code=exit_code)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
