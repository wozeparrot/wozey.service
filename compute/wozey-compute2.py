from gevent import monkey

monkey.patch_all()

from transformers import pipeline
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
    AutoModelForCausalLM,
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


class Agent:
    short_term_memory: list[UserContext]
    long_term_memory: list[UserContext]

    def __init__(self):
        self.short_term_memory = []
        self.long_term_memory = []

    def update_memory(self) -> None:
        for i in range(len(self.short_term_memory)):
            self.short_term_memory[i].age += 1

        for i in range(len(self.long_term_memory)):
            self.long_term_memory[i].age += 1

    def add_short_term(self, memory: str, generated: bool) -> None:
        self.update_memory()

        if len(self.short_term_memory) > 10:
            self.short_term_memory.pop(0)

        self.short_term_memory.append(UserContext(memory, generated))

    def add_long_term(self, memory: str) -> None:
        self.update_memory()

        if len(self.long_term_memory) > 4:
            self.long_term_memory.pop(0)

        self.long_term_memory.append(UserContext(memory, True))

    def get_memory(self, seperator: str) -> str:
        context = []
        for memory in self.long_term_memory:
            if memory.data != self.short_term_memory[-1].data:
                context.append(f"{memory.data}")
        context_string = ", ".join(context)

        history = []
        for i, memory in enumerate(self.short_term_memory):
            if i == len(self.short_term_memory) - 1 and len(context) > 0:
                history.append(
                    f"{context_string}{seperator}ok.{seperator}{memory.data}"
                )
            else:
                history.append(f"{memory.data}")

        return seperator.join(history) + seperator


context_preprocessor = pipeline(
    "question-answering",
    model="deepset/tinyroberta-squad2",
    tokenizer="deepset/tinyroberta-squad2",
)

ic_tokenizer = AutoTokenizer.from_pretrained("typeform/distilbert-base-uncased-mnli")
ic_model = AutoModelForSequenceClassification.from_pretrained(
    "typeform/distilbert-base-uncased-mnli",
)
input_classifier = pipeline(
    "zero-shot-classification",
    model=ic_model,
    tokenizer=ic_tokenizer,
)


def classify(text: str) -> dict[str, float]:
    classification = input_classifier(
        text,
        [
            "information",
            "my information",
            "question",
            "query",
            "asking",
            "other",
            "command",
        ],
        multi_label=True,
    )

    classes = {}
    for i, c in enumerate(classification["labels"]):
        classes[c] = classification["scores"][i]

    return classes


chat_model_name = "deepparag/Aeona"
# chat_model_name = "S34NtheGuy/DialoGPT-medium-Glass_Of_Water"
chat_tokenizer = AutoTokenizer.from_pretrained(chat_model_name)
chat_model = AutoModelForCausalLM.from_pretrained(chat_model_name)


def chat(agent: Agent, text: str) -> str:
    for i in range(5):
        input_ids = chat_tokenizer.encode(text, return_tensors="pt")

        output_ids = chat_model.generate(
            input_ids,
            max_length=1000,
            pad_token_id=chat_tokenizer.eos_token_id,
            num_beams=5,
            do_sample=True,
            top_k=80,
            top_p=0.9,
            temperature=1.2,
            no_repeat_ngram_size=4,
            length_penalty=3.0,
            repetition_penalty=2.0,
            max_time=5,
            use_cache=True,
        )

        output_text = chat_tokenizer.decode(
            output_ids[:, input_ids.shape[-1] :][0], skip_special_tokens=True
        )
        if output_text != "":
            if len(agent.short_term_memory) > 1:
                if all(map(lambda x: x.data != output_text, agent.short_term_memory)):
                    break
            else:
                break
    else:
        output_text = "I'm sorry, I don't know how to respond to that."

    return output_text


agent1 = Agent()
agent1.add_long_term("i like trees")
agent2 = Agent()

u = input("U: ")

while True:
    agent1.add_short_term(u, False)

    classes = classify(u)
    # print(classes)
    if (
        classes["my information"] > 0.72
        and classes["asking"] < 0.5
        and classes["query"] < 0.5
        and classes["command"] < 0.5
    ):
        agent1.add_long_term(u)

    r = chat(agent1, agent1.get_memory(chat_tokenizer.eos_token))
    agent1.add_short_term(r, True)
    print(f"R: {r}")

    agent2.add_short_term(r, False)

    classes = classify(r)
    # print(classes)
    if (
        classes["my information"] > 0.72
        and classes["asking"] < 0.5
        and classes["query"] < 0.5
        and classes["command"] < 0.5
    ):
        agent2.add_long_term(r)

    u = chat(agent2, agent2.get_memory(chat_tokenizer.eos_token))
    agent2.add_short_term(u, True)
    print(f"U: {u}")
