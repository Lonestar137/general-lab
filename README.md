# General Playground

This repository is intended to be a **playground** for experimenting with a variety of programming languages, frameworks, and technology stacks.  The goal is to keep the structure simple and self‑contained so you can quickly spin up a new experiment, run it locally, and then delete it when you’re done.

## Global Structure

- **`.gitignore`** – A minimal ignore file that covers common artifacts.
- **`README.md`** – This file – read the documentation to understand the layout.
- **`LICENSE`** – MIT license.
- **`/projects`** – Top‑level directory containing one subdirectory per language or tech stack.  Each subdirectory follows a “mini‑project” structure:
  1. `README.md` – what the experiment does, how to run it.
  2. Source files – a minimal working example.
  3. Configuration files – package‑manager or build files.

Feel free to **add more sub‑directories** or **remove** ones that you don’t plan to use.  The repository is meant to be lightweight, so do not add large binary artifacts.

## How to Use

```bash
# Clone the repository
git clone <repo-url>
cd general-lab

# Explore a language
cd projects/nodejs
npm install
node hello.js
```

When you’re done, if the experiment produced any compiled or generated files (e.g., `dist/`, `target/`) just delete them, they will be ignored.

Happy hacking!
