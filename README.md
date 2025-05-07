# 📝 Markdown-to-Html-Xtra

**Enhanced Markdown to HTML Converter**
A PowerShell script that converts a **Markdown (.md)** file into an enriched, **self-contained HTML** page, ready to be viewed in any web browser.

---

## ✨ Features

* 🔁 Converts Markdown to HTML using **Pandoc**
* 🖋️ Supports:

  * **Code blocks** with **syntax highlighting (Prism.js)**
  * **Mermaid** diagrams
  * **LaTeX** formulas via **KaTeX**
  * **Copy buttons** for code blocks (one-click copy of code snippets)
* 🎨 Uses a **simple and responsive HTML template** (`simple_standalone_tmpl.html`)
* 📎 Generates a **lightweight HTML file**, viewable locally without a server
* 📌 Displays a **download banner** when opened via HTTP (optional)

---

## 🚀 Usage

```powershell
.\markdown_to_htmlx.ps1 -InputFile "example.md"
```

### Options:

* `-InputFile`: Path to the `.md` file to convert (**required**)
* `-OutputFile`: Name of the generated `.html` file (default: same name as input)
* `-TemplateFile`: Path to the HTML template (default: `simple_standalone_tmpl.html`)

---

## ⚙️ Requirements

* PowerShell (Windows, Linux, or macOS)
* [Pandoc](https://pandoc.org/installing.html) installed and available in your `PATH`
