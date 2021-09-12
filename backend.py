from flask import Flask
from flask import request, abort
from struct import unpack
import os

app = Flask(__name__)
app.debug = True

@app.route('/')
def home():
    return "hello world"

def read_null_terminated_string(file):
	return str().join(iter(lambda: file.read(1).decode("ascii"), '\x00'))

@app.route('/replays/', methods=['GET'])
def request_replays():
    if "map" in request.args:
        map = request.args.get("map", type=str)
    else:
        return "404"

    track = style = 0
    time = -1.0

    if "style" in request.args:
        style = request.args.get("style", type=int)

    if "track" in request.args:
        track = request.args.get("track", type=int)

    if "time" in request.args:
        time = request.args.get("time", type=float)


    if track > 0:
        map += f"_{track}.replay"
    else:
        map += ".replay"

    app_root = os.path.dirname(os.path.abspath(__file__))
    file_path = os.path.join(app_root, f'replays/{style}/{map}')

    if os.path.isfile(file_path):
        with open(file_path, "rb") as file:
            a = read_null_terminated_string(file)
            a = unpack("bbii", file.read(12))[3]
            fTime = round(unpack("f", file.read(4))[0], 3)
            if fTime > time and time > 0:
                abort(404)
            file.seek(0, 0)
            return file.read()

    abort(404)

    
if __name__ == "__main__":
    app.run()
