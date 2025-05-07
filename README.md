Here is the English translation of your Markdown description:

---

# 📝 Markdown-to-Html-Xtra:

Enhanced Markdown to HTML Converter
A PowerShell script that converts a **Markdown (.md)** file into an enriched, **self-contained HTML** page, ready to be viewed in a web browser.

---

## ✨ Features

* 🔁 Converts Markdown to HTML using **Pandoc**
* 🖋️ Supports:

  * **Code blocks** with **syntax highlighting (Prism.js)**
  * **Mermaid** diagrams
  * **LaTeX** formulas via **KaTeX**
* 💡 Preserves original code blocks for custom processing
* 🎨 Uses a **simple and responsive HTML template** (`simple_standalone_tmpl.html`)
* 📎 Generates a **lightweight HTML file**, viewable locally without a server
* 📌 Displays a **download banner** when opened via HTTP (optional)

---

## 🚀 Usage

```powershell
.\markdown_to_htmlx.ps1 -InputFile "example.md"
```

Options:

* `-InputFile`: path to the `.md` file to convert (**required**)
* `-OutputFile`: name of the generated HTML file (default: same name with `.html`)
* `-TemplateFile`: path to the HTML template (default: `simple_standalone_tmpl.html`)

---

## ⚙️ Requirements

* PowerShell (Windows, Linux, or Mac)
* [Pandoc](https://pandoc.org/installing.html) installed and available in the `PATH` environment variable

