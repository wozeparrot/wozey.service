import numpy as np
import json
import asyncio

from vosk import Model, KaldiRecognizer

HOST = "localhost"
PORT = 6768
MODEL = Model(lang="en-us")


async def handle_client(client_reader, client_writer):
    print("Client connected")

    keyword_rec = KaldiRecognizer(MODEL, 48000, """["potato", "[unk]"]""")
    rec = KaldiRecognizer(
        MODEL,
        48000,
        """[
            "play one",
            "play three",
            "esposito",
            "stop",
            "[unk]"
        ]""",
    )

    keyword_detected = False
    last_data = None

    while True:
        data = await client_reader.read(4096)
        if not data:
            break

        int16_data = np.frombuffer(data, dtype="int16")
        # extract the left channel
        mono_audio = int16_data[::2]

        if keyword_detected:
            if rec.AcceptWaveform(mono_audio.tobytes()):
                text = json.loads(rec.Result())["text"]

                keyword_rec.Reset()
                if last_data is not None:
                    keyword_rec.AcceptWaveform(last_data.tobytes())
                keyword_detected = False
            else:
                text = json.loads(rec.PartialResult())["partial"]

            if "play one" in text:
                print("Playing music (one)")

                # send command to socket
                client_writer.write(json.dumps({"command": "play one"}).encode("utf-8"))

                keyword_rec.Reset()
                if last_data is not None:
                    keyword_rec.AcceptWaveform(last_data.tobytes())
                keyword_detected = False
            elif "esposito" in text:
                print("Playing music (despacito)")

                # send command to socket
                client_writer.write(
                    json.dumps({"command": "play despacito"}).encode("utf-8")
                )

                keyword_rec.Reset()
                if last_data is not None:
                    keyword_rec.AcceptWaveform(last_data.tobytes())
                keyword_detected = False
            elif "play three" in text:
                print("Playing music (three)")

                # send command to socket
                client_writer.write(
                    json.dumps({"command": "play three"}).encode("utf-8")
                )

                keyword_rec.Reset()
                if last_data is not None:
                    keyword_rec.AcceptWaveform(last_data.tobytes())
                keyword_detected = False
            elif "stop" in text:
                print("Stopping music")

                # send command to socket
                client_writer.write(json.dumps({"command": "stop"}).encode("utf-8"))

                keyword_rec.Reset()
                if last_data is not None:
                    keyword_rec.AcceptWaveform(last_data.tobytes())
                keyword_detected = False
            else:
                if text != "":
                    print("Unknown: " + text)
        else:
            if keyword_rec.AcceptWaveform(mono_audio.tobytes()):
                text = keyword_rec.Result()
            else:
                text = keyword_rec.PartialResult()

            if "potato" in text:
                print("Keyword detected")
                rec.Reset()
                if last_data is not None:
                    rec.AcceptWaveform(last_data.tobytes())
                keyword_detected = True

        last_data = mono_audio


async def start_server():
    server = await asyncio.start_server(handle_client, HOST, PORT)

    print(f"Server is listening on {HOST}:{PORT}")

    async with server:
        await server.serve_forever()


asyncio.run(start_server())
