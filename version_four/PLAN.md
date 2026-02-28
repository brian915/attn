# PLAN.md (Version Four - Synthesized Baseline)

**Evaluation Context:** Unified architecture merging Open Code (Stability), Claude Code (Interface Design), and Codex (Logic Density).
**Role:** Project Blueprint for Agent Implementation.

## 1. Unified Architecture
The system functions as a stateless pipeline with local file-based persistence.

* **Extraction (Codex Source):** Uses a robust `GmailAdapter` with a strict 24-hour UTC lookback window.
* **Normalization (Claude Interface):** `AdapterFactory` maps raw provider JSON to a standard `Attn::Record` (Subject, Sender, Body, Timestamp).
* **Evaluation (Open Code Logic):** The `Summarizer` injects `SCORING.md` and `PREFERENCES.md` directly into the LLM system prompt for qualitative ranking.
* **Deduplication (Synthesized):** A `state/processed_message_ids.txt` file acts as the source of truth to prevent re-processing.


## 2. Directory Structure
```text
attn/
├── bin/attn                    # Executable entry point
├── config/
│   ├── attn.yml                # Configuration (YAML)
│   └── attn.yml.example        # Reference template
├── evaluation/refs/
│   ├── PREFERENCES.md          # Qualitative: Editorial Interests
│   └── SCORING.md              # Qualitative: Quality Benchmarks
├── lib/attn/
│   ├── adapter_factory.rb      # Source Abstraction
│   ├── gmail_adapter.rb        # Gmail API Implementation
│   ├── runner.rb               # Pipeline Orchestrator
│   ├── storage.rb              # File I/O & State Management
│   └── summarizer.rb           # LLM Orchestration & Prompting
└── output/
    ├── runs/[TIMESTAMP]/       # Raw Records, Summaries, and final Digest
    └── state/                  # Deduplication State

## 3. Integration Requirements

* **Prompting**: The `Summarizer` must perform a file-read of the `evaluation/refs/` directory to construct the context window.
* **Error Handling**: If the LLM returns an error, the `Runner` must halt to prevent partial/failed state updates in `processed_message_ids.txt`.
* **Output Format**: Every run produces a `digest.md` containing a "Top 5" ranked section followed by "All Other Signals" based on the `SCORING.md` criteria.

## 4. Evaluation Benchmarks

* **Success**: `bin/attn` execution results in a unique timestamped folder with a valid Markdown digest.
* **Idempotency**: Consecutive runs within the same 24-hour window yield zero new records after the initial fetch.
* **Configurability**: Model and Provider (OpenAI/Anthropic) are swappable via `attn.yml` without modifying `lib/`.
