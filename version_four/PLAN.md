# Project Plan: attn (v0)

**Goal:** A stateless Ruby pipeline to fetch, summarize, and rank 24-hour email digests.

---

## 1. Core Architecture
1. **Fetch**: `Attn::GmailAdapter` retrieves messages from the last 24 hours.
2. **Deduplicate**: `Attn::Storage` filters against `state/processed_message_ids.txt`.
3. **Summarize**: `Attn::Summarizer` processes content via LLM, incorporating qualitative context from `evaluation/refs/`.
4. **Rank**: `Attn::Ranker` categorizes output based on `SCORING.md`.
5. **Output**: `Attn::DigestRenderer` generates a Markdown report in `output/runs/[TIMESTAMP]/`.

---

## 2. Directory Structure
```text
.
	bin/attn                    # Entry point
	config/
		attn.yml                # Active configuration
		attn.yml.example        # Template
	evaluation/refs/
		PREFERENCES.md          # User Interests (Markdown)
		SCORING.md              # Quality Benchmarks (Markdown)
	lib/attn/
		adapter_factory.rb      # Source mapping
		gmail_adapter.rb        # Gmail API interface
		ranker.rb               # Logic for categorization
		digest_renderer.rb      # Markdown template engine
		runner.rb               # Orchestration logic
		storage.rb              # File I/O and State
		summarizer.rb           # LLM interaction logic
	output/
		runs/[TIMESTAMP]/       # Records, Summaries, and Digest
		state/                  # processed_message_ids.txt

