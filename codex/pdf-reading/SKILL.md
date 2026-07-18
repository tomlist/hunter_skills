---
name: pdf-reading
description: Use this skill when you need to read, inspect, or extract content from PDF files — especially when file content is NOT in your context and you need to read it from disk. Covers content inventory, text extraction, page rasterization for visual inspection, embedded image/attachment/table/form-field extraction, and choosing the right reading strategy for different document types (text-heavy, scanned, slide-decks, forms, data-heavy). Do NOT use for PDF creation, form filling, merging, splitting, watermarking, or encryption — use the pdf skill instead.
---

# PDF Processing Guide

## Overview

This guide covers essential PDF reading operations using Python libraries and command-line tools. For advanced features, see [REFERENCE.md](REFERENCE.md).

## Reading and Inspecting PDFs

### Content inventory

Run diagnostic commands first:

```bash
# Page count, file size, PDF version, metadata
pdfinfo document.pdf

# Quick text extraction check — text PDF or scan?
pdftotext -f 1 -l 1 document.pdf - | head -20

# If figures/charts may matter:
pdfimages -list document.pdf

# If embedded files:
pdfdetach -list document.pdf

# If text extraction looks garbled:
pdffonts document.pdf
```

### Text extraction

**pypdf** for basic text:
```python
from pypdf import PdfReader
reader = PdfReader("document.pdf")
text = ""
for page in reader.pages:
    text += page.extract_text()
```

**pdftotext** preserving layout:
```bash
pdftotext -layout document.pdf output.txt
pdftotext -f 1 -l 5 document.pdf output.txt
```

**pdfplumber** for layout-aware extraction:
```python
import pdfplumber
with pdfplumber.open("document.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text()
```

### Visual inspection (rasterize pages)

```bash
pdftoppm -jpeg -r 150 -f 3 -l 3 document.pdf /tmp/page
```

**When to rasterize**: figures/charts, slide-decks, scanned documents, form layouts.
**When to text-extract**: content/data questions, text-heavy documents.

### Choosing your reading strategy

- **Text-heavy**: text extraction primary, rasterize only for figures
- **Scanned**: rasterize at 150 DPI, OCR for bulk text
- **Slide-decks**: every page is visual — rasterize on demand
- **Form-heavy**: extract field values programmatically, rasterize for context
- **Data-heavy**: pdfplumber for tables, rasterize for charts

### Extracting embedded images

```bash
pdfimages -list document.pdf
pdfimages -png document.pdf /tmp/img
pdfimages -all document.pdf /tmp/img
```

### Extracting file attachments

```bash
pdfdetach -list document.pdf
pdfdetach -saveall -o /tmp/attachments/ document.pdf
```

### Extracting form field data

```python
from pypdf import PdfReader
reader = PdfReader("form.pdf")
fields = reader.get_form_text_fields()
for name, value in fields.items():
    print(f"{name}: {value}")
```

## Quick Reference

| Task | Best Tool | Command/Code |
|------|-----------|--------------|
| Inspect PDF | poppler-utils | `pdfinfo`, `pdfimages -list` |
| Extract text | pdfplumber | `page.extract_text()` |
| Extract text (CLI) | pdftotext | `pdftotext -layout input.pdf output.txt` |
| Extract tables | pdfplumber | `page.extract_tables()` |
| See page visually | pdftoppm | `pdftoppm -jpeg -r 150 -f N -l N` |
| Extract images | pdfimages | `pdfimages -png input.pdf prefix` |
| Extract attachments | pdfdetach | `pdfdetach -saveall -o /tmp/` |
| Read form fields | pypdf | `reader.get_fields()` |

For PDF form filling, creation, merging, splitting, and other operations, use the pdf skill.
