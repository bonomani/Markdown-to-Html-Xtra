<#
.SYNOPSIS
  Converts a Markdown (.md) file to HTML using a simple standalone template with support for:
  - Mermaid diagrams
  - KaTeX math formulas ($$...$$)
  - Syntax-highlighted code blocks
  Requires Pandoc and a template file (default: simple_standalone_tmpl.html).

.DESCRIPTION
  This script (markdown_to_htmlx.ps1):
    - Extracts fenced code blocks (```lang) and replaces them with placeholders
    - Converts Markdown to HTML via Pandoc
    - Reinserts preserved code and diagram blocks (e.g., Mermaid, Bash)
    - Injects the result into a minimal HTML template
    - Outputs a clean, standalone HTML file

.PARAMETER InputFile
  Path to the source Markdown (.md) file

.PARAMETER OutputFile
  (Optional) Path to the output HTML file. Defaults to same name as input with `.html` extension

.PARAMETER TemplateFile
  (Optional) Path to the HTML template. Defaults to `C:\po\simple_standalone_tmpl.html`

.NOTES
  - Mermaid blocks are rendered via <div class="mermaid">
  - KaTeX math is expected to be rendered client-side (e.g., via MathJax)
  - Requires Pandoc to be installed and available in the system PATH
#>

# Define script parameters
param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile,  # Path to the Markdown input file

    [Parameter(Mandatory = $false)]
    [string]$OutputFile, # Optional path to the output HTML file

    [string]$TemplateFile = ".\tmpl_simple_standalone.html" # Default HTML template
)

# Ensure console output uses UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# If no output file is provided, default to input filename with .html extension
if (-not $OutputFile) {
    $OutputFile = [System.IO.Path]::ChangeExtension($InputFile, ".html")
}

# Prevent accidental overwrite of the template file
if ($OutputFile -eq $TemplateFile) {
    Write-Error "Le fichier de sortie [$OutputFile] est identique au template. Abandon."
    exit 1
}

# Prevent using the template file as input
if ($InputFile -eq $TemplateFile) {
    Write-Error "Le fichier d'entrée est le template. Tu vas le détruire. Abandon."
    exit 1
}

# Prevent input and output file from being the same
if ($InputFile -eq $OutputFile) {
    Write-Error "Le fichier d'entrée et de sortie sont identiques. Abandon."
    exit 1
}

# Check that the input Markdown file exists
if (-not (Test-Path $InputFile)) {
    Write-Error "Fichier d'entrée introuvable : $InputFile"
    exit 1
}

# Check that the HTML template file exists
if (-not (Test-Path $TemplateFile)) {
    Write-Error "Template HTML introuvable : $TemplateFile"
    exit 1
}

# Check that Pandoc is installed and accessible
if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
    Write-Error "Pandoc n'est pas installé. https://pandoc.org/installing.html"
    exit 1
}

# Step 1: Read the raw content of the Markdown file
$md = Get-Content -Raw -Encoding UTF8 $InputFile
Write-Host "Fichier Markdown chargé"

# Step 2: Define a regex pattern to extract code blocks (```...```)
$pattern = '```([\s\S]*?)```'
$regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:codeBlocks = @()  # Store code blocks globally for reinjection

# Step 3: Replace code blocks with unique HTML comments <!-- BLOCK_n -->
$mdPreserved = $regex.Replace($md, {
    param($match)
    $block = $match.Value
    $script:codeBlocks += $block
    $index = $script:codeBlocks.Count - 1
    return "<!-- BLOCK_${index} -->"
})

Write-Host "Blocs Markdown extraits : $($script:codeBlocks.Count)"

# Step 4: Convert Markdown (with placeholders) to HTML using Pandoc via a temp file
$tempFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempFile -Encoding UTF8 -Value $mdPreserved

$htmlBody = pandoc $tempFile -f markdown+emoji -t html5

Remove-Item $tempFile
Write-Host "Conversion Markdown -> HTML terminée"

# Step 5: Reinject the extracted code blocks back into the generated HTML
for ($i = 0; $i -lt $script:codeBlocks.Count; $i++) {
    $placeholder = "<!-- BLOCK_${i} -->"
    
    $block = $script:codeBlocks[$i]  # Retrieve original block

    # Try to detect the language from the opening backticks
    if ($block -match '^```(\w+)\r?\n') {
        $lang = $matches[1].ToLower()
    } else {
        $lang = 'bash'  # Default fallback
    }

    # Strip triple backticks from beginning and end
    $code = $block -replace '^```[^\r\n]*\r?\n?', '' -replace '\r?\n?```$', ''

    # Inject as mermaid div or regular <pre><code> block
    if ($lang -eq 'mermaid') {
        $htmlBlock = "<div class=`"mermaid`">$code</div>"
    } else {
        $class = if ($lang) { "language-$lang" } else { "" }
        $htmlBlock = "<pre><code class=`"$class`">$code</code></pre>"
    }

    # Replace the placeholder with the actual HTML block
    $htmlBody = $htmlBody -replace [regex]::Escape($placeholder), $htmlBlock
}

Write-Host "Blocs Mermaid réinjectés dans le HTML"

# Step 6: Integrate the generated HTML body into the template
$template = Get-Content -Raw -Encoding UTF8 $TemplateFile
$title = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)

# Replace placeholders in the template
$htmlFinal = $template -replace '{{TITLE}}', [Regex]::Escape($title) -replace '{{BODY}}', $htmlBody

# Restore display math delimiters ($$...$$) removed during the -replace '{{BODY}}', $htmlBody operation
# PowerShell interprets $... as variables in replacement strings, causing $$ math to be stripped
$htmlFinal = $htmlFinal -replace '<span class="math display">\$(.*?)\$</span>', '<span class="math display">$$$$$1$$$$</span>'

# Step 7: Write the final HTML content to the output file (UTF-8, no newline at end)
Set-Content -Encoding utf8 -NoNewline -LiteralPath $OutputFile -Value $htmlFinal

Write-Host "Fichier HTML généré : $OutputFile"
