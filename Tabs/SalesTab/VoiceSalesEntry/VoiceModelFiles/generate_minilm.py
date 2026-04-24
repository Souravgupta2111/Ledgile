import torch
import coremltools as ct
from transformers import AutoTokenizer, AutoModel
import numpy as np
import os

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
OUTPUT_DIR = "."
MLPACKAGE_NAME = "MiniLM.mlpackage"

# Fixed sequence length for CoreML stability (must match MiniLMEncoder.swift)
SEQ_LENGTH = 128 

# -----------------------------------------------------------------------------
# MODEL WRAPPER
# -----------------------------------------------------------------------------
class MiniLMWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        # We only need the embeddings, typically we use mean pooling or CLS
        # For all-MiniLM-L6-v2, mean pooling is standard standard.
        # But here let's just return the raw last_hidden_state and do pooling in Swift 
        # OR better yet, do pooling here so Swift gets a clean 384 vector.
        
        outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
        token_embeddings = outputs.last_hidden_state # [Batch, Seq, 384]
        
        # Mean Pooling
        # attention_mask is [Batch, Seq]
        # Expand mask to [Batch, Seq, Hidden]
        input_mask_expanded = attention_mask.unsqueeze(-1).expand(token_embeddings.size()).float()
        
        # Sum embeddings * mask
        sum_embeddings = torch.sum(token_embeddings * input_mask_expanded, 1)
        
        # Sum mask (clamp to avoid div by zero)
        sum_mask = torch.clamp(input_mask_expanded.sum(1), min=1e-9)
        
        # Mean
        embeddings = sum_embeddings / sum_mask # [Batch, 384]
        
        # Normalize (Optional but recommended for cosine similarity)
        embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)
        
        return embeddings

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
def main():
    print(f"🔄 Downloading model: {MODEL_NAME}...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    hf_model = AutoModel.from_pretrained(MODEL_NAME)
    
    # Wrap to include pooling
    model = MiniLMWrapper(hf_model)
    model.eval()

    print("🔄 Exporting Vocab...")
    vocab = tokenizer.vocab
    vocab_path = os.path.join(OUTPUT_DIR, "vocab.txt")
    with open(vocab_path, "w", encoding="utf-8") as f:
        # Write vocab in order of IDs
        sorted_vocab = sorted(vocab.items(), key=lambda x: x[1])
        for token, index in sorted_vocab:
            f.write(token + "\n")
    print(f"✅ Vocab saved to {vocab_path}")

    print("🔄 Tracing model...")
    example_input_ids = torch.zeros((1, SEQ_LENGTH), dtype=torch.int32)
    example_attention_mask = torch.zeros((1, SEQ_LENGTH), dtype=torch.int32)
    
    traced_model = torch.jit.trace(model, (example_input_ids, example_attention_mask))

    print("🔄 Converting to CoreML...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, SEQ_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, SEQ_LENGTH), dtype=np.int32)
        ],
        outputs=[
            ct.TensorType(name="embeddings")
        ],
        minimum_deployment_target=ct.target.iOS16,
        compute_units=ct.ComputeUnit.ALL
    )

    output_path = os.path.join(OUTPUT_DIR, MLPACKAGE_NAME)
    mlmodel.save(output_path)
    print(f"✅ CoreML model saved to {output_path}")
    print("\n⚠️ IMPORTANT: Move 'MiniLM.mlpackage' and 'vocab.txt' to your Xcode project.")

if __name__ == "__main__":
    main()
