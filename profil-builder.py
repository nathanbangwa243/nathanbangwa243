import shutil
from datetime import datetime
from PyPDF2 import PdfMerger

# Base output name (without language or date)
OUTPUT_NAME = 'docs/Nathan-Ilunga-Lubaba-Bangwa-Profile-CV'

# List of certification PDFs to include (order matters)
PROFIL_CERTIF_FILES = [
    'docs/aws-ai-practitioner-challenge.pdf',
    'docs/aws-machine-learning-fundamentals.pdf',
    'docs/ai-programming-with-python.pdf',
    'docs/java-OOP.pdf',
]

# Language specific base profile PDFs
LANGUAGE_BASE_FILES = {
    'fr': 'docs/profile-fr.pdf',
    'en': 'docs/profile-en.pdf',
}

# Get today's date for versioned filenames
today_str = datetime.today().strftime('%d%m%y')

for lang_code, base_pdf in LANGUAGE_BASE_FILES.items():
    # Create a new merger for each language profile
    merger = PdfMerger()
    # First add the language‑specific base profile PDF
    merger.append(base_pdf)
    # Append all certification PDFs in the defined order
    for certif in PROFIL_CERTIF_FILES:
        merger.append(certif)
    # Define output filenames
    output_file = f"{OUTPUT_NAME}-{lang_code}.pdf"
    dated_output_file = f"{OUTPUT_NAME}-{lang_code}-{today_str}.pdf"
    # Write merged PDF to the language‑specific file
    merger.write(output_file)
    merger.close()
    # Copy the file to a dated version for easy tracking
    shutil.copy(output_file, dated_output_file)

print("Profile PDFs generated for languages: " + ", ".join(LANGUAGE_BASE_FILES.keys()))
