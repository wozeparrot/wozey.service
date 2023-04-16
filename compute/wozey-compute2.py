import gc
import json

from gevent import monkey

monkey.patch_all()

from transformers import pipeline
from transformers import (
    AutoConfig,
    AutoTokenizer,
    AutoModelForCausalLM,
)
from e2e_question_generation import pipeline as e2eqg_pipeline

import romajitable
from espnet2.bin.tts_inference import Text2Speech
import soundfile

from bottle import Bottle, request

# ----- CHANGE MODELS HERE -----
# context_preprocessor = pipeline(
#     "question-answering",
#     model="deepset/tinyroberta-squad2",
#     tokenizer="deepset/tinyroberta-squad2",
# )

input_classifier = pipeline(
    "zero-shot-classification",
    model="valhalla/distilbart-mnli-12-9",
)

ltmqg = e2eqg_pipeline("e2e-qg")

# chat_model_name = "deepparag/Aeona"
# chat_model_name = "S34NtheGuy/DialoGPT-medium-Glass_Of_Water"
chat_model_name = "PygmalionAI/pygmalion-350m"
# chat_model_name = "PygmalionAI/pygmalion-1.3b"
chat_config = AutoConfig.from_pretrained(chat_model_name, is_decoder=True)
chat_tokenizer = AutoTokenizer.from_pretrained(chat_model_name)
chat_model = AutoModelForCausalLM.from_pretrained(chat_model_name, config=chat_config)

voice_model = Text2Speech.from_pretrained(
    # "mio/Artoria",
    "espnet/kan-bayashi_ljspeech_vits",
    speed_control_alpha=0.75,
    noise_scale=0.4,
    noise_scale_dur=0.4,
)


class UserContext:
    data: str
    generated: bool

    usage: int
    age: int

    def __init__(self, data: str, generated: bool):
        self.data = data
        self.generated = generated

        self.usage = 0
        self.age = 0


class Character:
    short_term_memory: list[UserContext]
    long_term_memory: list[UserContext]

    name: str
    greeting: str
    persona: str
    world: str
    examples: list[list[str]]

    def __init__(
        self,
        name: str,
        greeting: str,
        persona: str,
        world: str,
        examples: list[list[str]],
    ):
        self.short_term_memory = []
        self.long_term_memory = []

        self.name = name
        self.greeting = greeting
        self.persona = persona
        self.world = world
        self.examples = examples

        # add greeting to short term memory
        self.add_short_term(greeting, True)

    def update_memory(self) -> None:
        for i in range(len(self.short_term_memory)):
            self.short_term_memory[i].age += 1

        for i in range(len(self.long_term_memory)):
            self.long_term_memory[i].age += 1

    def add_short_term(self, memory: str, generated: bool) -> None:
        self.update_memory()

        # can store 6 pairs of short term memory
        if len(self.short_term_memory) > 12:
            self.short_term_memory.pop(0)

        self.short_term_memory.append(UserContext(memory, generated))

    def add_long_term(self, memory: str) -> None:
        self.update_memory()

        # can store 3 pairs of long term memory
        if len(self.long_term_memory) > 6:
            self.long_term_memory.pop(0)

        # generate question that can be answered by the memory
        question = ltmqg(memory)[0].replace("my ", "your ")
        print(question)

        self.long_term_memory.append(UserContext(question, True))
        self.long_term_memory.append(UserContext(memory, False))

    def get_memory(self, seperator: str = "\n") -> str:
        # generate persona string
        personality_str = f"{self.name}'s Persona: {self.persona}{seperator}"

        world_str = (
            f"{seperator}World Scenario: {self.world}{seperator}"
            if self.world != ""
            else ""
        )

        # generate example dialog string
        example_dialog_str = ""
        for example in self.examples:
            # add <START>
            example_dialog_str += f"<START>{seperator}"

            # add greeting
            example_dialog_str += f"{self.name}: {self.greeting}{seperator}"

            # add example dialog; user is first
            for i, line in enumerate(example):
                if i % 2 == 0:
                    example_dialog_str += f"You: {line}{seperator}"
                else:
                    example_dialog_str += f"{self.name}: {line}{seperator}"

        # generate long term memory string
        long_term_memory_str = ""
        for memory in self.long_term_memory:
            if memory.generated:
                long_term_memory_str += f"{self.name}: {memory.data}{seperator}"
            else:
                long_term_memory_str += f"You: {memory.data}{seperator}"

        # generate short term memory string
        short_term_memory_str = ""
        for memory in self.short_term_memory:
            if memory.generated:
                short_term_memory_str += f"{self.name}: {memory.data}{seperator}"
            else:
                short_term_memory_str += f"You: {memory.data}{seperator}"

        return (
            personality_str
            + world_str
            + example_dialog_str
            + f"<START>{seperator}"
            + long_term_memory_str
            + short_term_memory_str
        )

    def chat(self) -> str:
        # memory = self.get_memory(chat_tokenizer.eos_token)
        memory = self.get_memory("\n")
        generation_input = f"{memory}{self.name}:"
        print(f"Input: {generation_input}")

        for _ in range(5):
            input_ids = chat_tokenizer.encode(generation_input, return_tensors="pt")

            output_ids = chat_model.generate(
                input_ids,
                max_length=2000,
                pad_token_id=chat_tokenizer.eos_token_id,
                num_beams=5,
                do_sample=True,
                top_k=35,
                top_p=0.94,
                temperature=0.55,
                no_repeat_ngram_size=4,
                length_penalty=-6.0,
                exponential_decay_length_penalty=(10, 3.0),
                repetition_penalty=1.02,
                max_time=20,
                use_cache=True,
            )

            output_text = chat_tokenizer.decode(
                output_ids[:, input_ids.shape[-1] :][0], skip_special_tokens=True
            )

            print("Output:", output_text)

            # remove extra space before colon in name that sometimes generates
            output_text = output_text.replace(" : ", ": ")

            # cut it on the You
            output_text = output_text[
                : (output_text.find("\n") + 1) or len(output_text)
            ]

            # strip name
            output_text = output_text[output_text.find(":") + 1 :]

            # strip
            output_text = output_text.strip()

            # strip quotes only if they are at the beginning and end
            if output_text.startswith('"') and output_text.endswith('"'):
                output_text = output_text[1:-1]

            # strip again
            output_text = output_text.strip()

            if output_text != "":
                if len(self.short_term_memory) > 1:
                    if all(
                        map(lambda x: x.data != output_text, self.short_term_memory)
                    ):
                        break
                else:
                    break
        else:
            output_text = "Filtered."

        return output_text


def classify(text: str) -> dict[str, float]:
    classification = input_classifier(
        text,
        [
            "information",
            "my information",
            "question",
            "query",
            "command",
            "other",
        ],
        multi_label=True,
    )

    classes = {}
    for i, c in enumerate(classification["labels"]):
        classes[c] = classification["scores"][i]

    return classes


char = Character(
    "Amber",
    "Hey there, traveler! I'm Amber, the Outrider from Mondstadt. If you ever need help finding your way around these parts, just let me know! I'm always ready to lend a hand.",
    "Amber is a playable character in Genshin Impact. She is a young Outrider from Mondstadt who dreams of joining the Knights of Favonius. She is a kind-hearted and optimistic person, but can sometimes be a little clumsy. She is skilled with the bow and arrow and is always eager to help those in need.",
    "As you are exploring the wilderness outside of Mondstadt, you come across Amber practicing her archery skills.",
    [
        [
            "Hey Amber, how's it going?",
            "Hey there! I'm doing pretty well, thanks for asking. How about you?",
            "I'm good too. So, I heard that you're a talented archer. What kind of targets do you like to practice on?",
            "Oh, I like to practice on all kinds of targets. Whether it's stationary dummies or moving targets, I always find a way to challenge myself.",
            "That's really impressive. Do you have a favorite bow that you like to use?",
            "Yes, I have a favorite bow called the Sharpshooter's Oath. It's a bow that's been passed down in my family for generations, and it has a lot of sentimental value to me.",
            "That's really cool. What do you do when you're not practicing archery?",
            "When I'm not practicing archery, I like to explore the world around me and help out anyone who needs it. I'm a member of the Knights of Favonius, so I'm always on the lookout for ways to protect Mondstadt and its people.",
        ]
    ],
)

# API definition
app = Bottle()


@app.route("/chat", method="POST")
def do_chat():
    user_id = request.json["id"]
    user_name = request.json["user"]
    user_input = request.json["text"].strip()
    print(f"[chat][{user_id}, {user_name}]: {user_input}")

    char.add_short_term(user_input, False)

    response = char.chat()
    char.add_short_term(response, True)

    print(f"[chat][{char.name}]: {response}")

    # generate audio
    # trans = romajitable.to_kana(response).katakana
    wav = voice_model(response)["wav"].numpy()

    soundfile.write("output.wav", wav, voice_model.fs, "PCM_16")

    return json.dumps({"reply": response})


def main():
    # while True:
    #     u = input("U: ")
    #     char.add_short_term(u, False)
    #
    #     classes = classify(u)
    #     print(classes)
    #     if (
    #         classes["my information"] > 0.72
    #         and classes["question"] < 0.5
    #         and classes["query"] < 0.5
    #         and classes["command"] < 0.5
    #         and classes["other"] < 0.5
    #     ):
    #         char.add_long_term(u)
    #
    #     r = char.chat()
    #     char.add_short_term(r, True)
    #     print(f"R: {r}")

    gc.collect()
    app.run(server="gevent", host="::", port=6769)


if __name__ == "__main__":
    main()
