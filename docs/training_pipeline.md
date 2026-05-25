# Training Pipeline

Local STT collects reviewed examples locally, then exports a dataset for external GPU training.

## Exported Dataset

Use Settings -> Training -> Export Dataset. The export contains:

```text
metadata.csv
audio/*.wav
README.md
```

`metadata.csv` columns:

```text
audio,transcription,profile,model_name,created_at
```

## External Fine-Tune Outline

1. Upload the exported folder to a GPU machine.
2. Load it with Hugging Face Datasets:

```python
from datasets import load_dataset, Audio

dataset = load_dataset("csv", data_files="metadata.csv")["train"]
dataset = dataset.cast_column("audio", Audio(sampling_rate=16000))
```

3. Fine-tune `openai/whisper-small` with Transformers.
4. Convert the fine-tuned model to `ggml` using the current `whisper.cpp` conversion tools.
5. Generate the matching Core ML encoder:

```sh
./models/generate-coreml-model.sh -h5 trained-model /path/to/fine-tuned-model
```

6. Import the `.bin` and optional `.mlmodelc` folder in Settings -> Training.

The app validates the `.bin` with bundled `whisper-cli` before making it selectable.
