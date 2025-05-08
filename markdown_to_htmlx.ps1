<#
.SYNOPSIS
  Converts Markdown (.md) files to standalone HTML supporting:
    - Mermaid diagrams
    - KaTeX math formulas ($$...$$)
    - Syntax-highlighted code blocks
  Requires Pandoc and an HTML template.

.PARAMETER InputFile
  Path to the Markdown input file.

.PARAMETER OutputFile
  (Optional) HTML output file. Defaults to the input filename with `.html`.

.PARAMETER TemplateFile
  (Optional) HTML template path. Default: `.\tmpl_simple_standalone.html`.

.NOTES
  - Mermaid diagrams rendered via <div class="mermaid">
  - KaTeX formulas rendered client-side (e.g., MathJax)
  - Pandoc must be installed and available in PATH.
#>

param (
    [Parameter(Mandatory)]
    [string]$InputFile,

    [string]$OutputFile,

    [string]$TemplateFile = ".\tmpl_simple_standalone.html"
)

Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Initialization & Validation ---

function Validate-Inputs {

    $OutputFile
    $checks = @(
        @{ Condition = ($OutputFile -eq $TemplateFile); Message = "The output file [$OutputFile] is the same as the template file. Aborting." },
        @{ Condition = ($InputFile -eq $TemplateFile); Message = "The input file is the template file. Operation would overwrite it. Aborting." },
        @{ Condition = ($InputFile -eq $OutputFile); Message = "The input and output files are identical. Aborting." },
        @{ Condition = (-not (Test-Path $InputFile)); Message = "Input file not found: $InputFile" },
        @{ Condition = (-not (Test-Path $TemplateFile)); Message = "HTML template not found: $TemplateFile" },
        @{ Condition = (-not (Get-Command pandoc -ErrorAction SilentlyContinue)); Message = "Pandoc is not installed. https://pandoc.org/installing.html" }
    )

    foreach ($check in $checks) {
        if ($check.Condition) {
            Write-Error $check.Message
            exit 1
        }
    }
}

# --- Markdown Processing ---

function Extract-CodeBlocks {
    param (
        [Parameter(Mandatory)]
        [string]$markdown
    )

    $script:codeBlocks = @()
    $lines = $markdown -split "`n"
    $insideBlock = $false
    $blockFence = ""
    $buffer = @()
    $resultLines = @()

    foreach ($line in $lines) {
        if (-not $insideBlock) {
            if ($line -match '^([`~]{3,})(.*)$') {
                $blockFence = $matches[1]
                $insideBlock = $true
                $buffer = @($line)
            } else {
                $resultLines += $line
            }
        } else {
            $buffer += $line
            $fencePattern = '^' + [regex]::Escape($blockFence) + '\s*$'
            if ($line -match $fencePattern) {
                $script:codeBlocks += ($buffer -join "`n")
                $index = $script:codeBlocks.Count - 1
                $resultLines += "<!-- BLOCK_$index -->"
                $insideBlock = $false
                $buffer = @()
            }
        }
    }

    Write-Host "Markdown code blocks extracted: $($script:codeBlocks.Count)"
    return $resultLines -join "`n"
}

function Convert-MarkdownToHtml {
    param ([string]$markdown)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pandoc"
    $psi.Arguments = "-f gfm -t html5"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null

    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($markdown)
    $process.StandardInput.BaseStream.Write($utf8Bytes, 0, $utf8Bytes.Length)
    $process.StandardInput.Close()

    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    Write-Host "Markdown to HTML conversion completed"
    return $output
}

function Fix-KaTeXInlineMathInText {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    # Pattern that matches math span blocks (inline KaTeX)
    $pattern = '(?s)<span class="math inline">(.*?)</span>'

    $cleaned = [regex]::Replace(
        $Text,
        $pattern,
        {
            param($match)
            # Clean the inner math content
            $inner = $match.Groups[1].Value -replace '\s*\r?\n\s*', ' '
            return $inner.Trim()  # Return only the raw $...$ math string
        },
        'IgnoreCase'
    )

    return $cleaned
}


# --- Anchor Repair ---

function Clean-Id ($raw) {
    return ($raw -replace '[^a-zA-Z0-9]+', '-').Trim('-')
}

function Extract-Matches ($html, $pattern) {
    $list = New-Object 'System.Collections.Generic.List[string]'
    $rx = [regex]::new($pattern)
    foreach ($m in $rx.Matches($html)) {
        $list.Add($m.Groups[1].Value)
    }
    return $list.ToArray()
}

function Get-LevenshteinDistance ($s, $t) {
    $n = $s.Length
    $m = $t.Length
    $d = New-Object 'int[,]' ($n + 1), ($m + 1)

    for ($i = 0; $i -le $n; $i++) { $d.SetValue($i, $i, 0) }
    for ($j = 0; $j -le $m; $j++) { $d.SetValue($j, 0, $j) }

    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($s[$i - 1] -eq $t[$j - 1]) { 0 } else { 1 }
            $del = $d.GetValue($i - 1, $j) + 1
            $ins = $d.GetValue($i, $j - 1) + 1
            $sub = $d.GetValue($i - 1, $j - 1) + $cost
            $d.SetValue([Math]::Min([Math]::Min($del, $ins), $sub), $i, $j)
        }
    }

    return $d.GetValue($n, $m)
}

function Find-BestMatch ($anchor, $ids) {
    $cleanAnchor = Clean-Id $anchor
    $candidates = $ids | Where-Object { $_ -like "*$cleanAnchor*" }
    if (-not $candidates) { $candidates = $ids }

    $best = $null
    $score = [int]::MaxValue
    foreach ($id in $candidates) {
        $dist = Get-LevenshteinDistance $cleanAnchor $id
        if ($dist -lt $score) {
            $score = $dist
            $best = $id
        }
    }
    return $best
}

function Repair-Anchors ($htmlBody, $ids, $anchors) {
    $report = [PSCustomObject]@{
        Fixed   = @()
        Missing = @()
        Unused  = @()
    }

    $body = $htmlBody
    foreach ($anchor in $anchors) {
        if ($ids -notcontains $anchor) {
            $best = Find-BestMatch $anchor $ids
            if ($best) {
                $body = $body.Replace("href=`"#$anchor`"", "href=`"#$best`"")
                $report.Fixed += [PSCustomObject]@{ Original = $anchor; Replacement = $best }
            } else {
                $report.Missing += $anchor
            }
        }
    }

    $newIds     = Extract-Matches $body '<h[1-6][^>]*?id="([^"]+)"'
    $newAnchors = Extract-Matches $body 'href="#([^"]+)"'
    $report.Unused = $newIds | Where-Object { $newAnchors -notcontains $_ }

    return @{ HtmlBody = $body; Report = $report }
}

# --- Reinjection of Code Blocks ---

function Inject-CodeBlocks ($html, $blocks) {
    for ($i = 0; $i -lt $blocks.Count; $i++) {
        $placeholder = "<!-- BLOCK_$i -->"
        $block = $blocks[$i]

        # Match first line to get the actual fence and language (e.g., ````python)
        if ($block -match '^(?<fence>`{3,}|~{3,})(?<lang>\w*)\r?\n') {
            $fence = $matches['fence']
            $lang = $matches['lang'].ToLower()
        } else {
            $fence = '```'
            $lang = 'bash'
        }

        # Split into lines for precise control
        $lines = $block -split "`r?`n"

        # Remove the opening fence (first line)
        if ($lines[0] -match "^$fence(\w*)?$") {
            $lines = $lines[1..($lines.Count - 1)]
        }

        # Remove the closing fence (last line) only if it exactly matches
        if ($lines.Count -gt 0 -and $lines[-1] -match "^$fence\s*$") {
            $lines = $lines[0..($lines.Count - 2)]
        }

        $code = [string]::Join("`n", $lines)

        # Wrap appropriately
        if ($lang -eq 'mermaid') {
            $htmlBlock = "<div class='mermaid'>$code</div>"
        } else {
            $class = if ($lang) { "language-$lang" } else { "" }
            $htmlBlock = "<pre><code class='$class'>$code</code></pre>"
        }

        # Replace placeholder
        $html = $html.Replace($placeholder, $htmlBlock)
    }

    Write-Host "Code blocks reinjected into HTML"
    return $html
}



# --- Final Assembly ---

function Finalize-Html ($templatePath, $bodyHtml, $title) {
    [string]$template = Get-Content -Path "$templatePath" -Raw -Encoding UTF8
    $html = $template.Replace('{{BODY}}', $bodyHtml).Replace('{{TITLE}}', $title)
    return $html -replace '<span class="math display">\$(.*?)\$</span>', '<span class="math display">$$$$$1$$$$</span>'
}

function Write-Report ($report, $cleanHtml) {
    Write-Host "`n=== Anchor Correction Report ===" -ForegroundColor Cyan

    if ($report.Fixed.Count -gt 0) {
        Write-Host "Anchors fixed:" -ForegroundColor Green
        $report.Fixed | Format-Table Original, Replacement -AutoSize
    } else {
        Write-Host "No anchors were fixed." -ForegroundColor Yellow
    }

    if ($report.Missing.Count -gt 0) {
        Write-Host "Missing anchors:" -ForegroundColor Red
        $report.Missing | ForEach-Object { Write-Host "  #$_" }
    } else {
        Write-Host "No missing anchors." -ForegroundColor Green
    }

    if ($report.Unused.Count -gt 0) {
        Write-Host "Unused IDs:" -ForegroundColor Magenta
        $report.Unused | ForEach-Object { Write-Host "  id=`"$_`"" }
    } else {
        Write-Host "No unused IDs." -ForegroundColor Green
    }
}

# --- Main Execution ---

Validate-Inputs
if (-not $OutputFile) {
    $OutputFile = [IO.Path]::ChangeExtension($InputFile, ".html")
}
$rawMarkdown = Get-Content -Raw -Encoding UTF8 $InputFile
$preservedMarkdown = Extract-CodeBlocks -markdown $rawMarkdown
$htmlBody = Convert-MarkdownToHtml -markdown $preservedMarkdown
$katexFixedhtmlBody = Fix-KaTeXInlineMathInText -Text $htmlBody

$ids     = Extract-Matches $katexFixedhtmlBody '<h[1-6][^>]*?id="([^"]+)"'
$anchors = Extract-Matches $katexFixedhtmlBody 'href="#([^"]+)"'
$repairResult = Repair-Anchors -htmlBody $katexFixedhtmlBody -ids $ids -anchors $anchors
$cleanHtml = $repairResult.HtmlBody

Write-Report -report $repairResult.Report -cleanHtml $cleanHtml
$htmlWithBlocks = Inject-CodeBlocks -html $cleanHtml -blocks $script:codeBlocks

$title = [IO.Path]::GetFileNameWithoutExtension($InputFile)
$htmlFinal = Finalize-Html -templatePath $TemplateFile -bodyHtml $htmlWithBlocks -title $title
Set-Content -Encoding utf8 -NoNewline -Path $OutputFile -Value $htmlFinal
Write-Host "HTML file generated: $OutputFile"
