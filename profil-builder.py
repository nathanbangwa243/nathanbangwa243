import shutil
from datetime import datetime

from PyPDF2 import PdfMerger


OUTPUT_NAME = 'docs/Nathan-Bangwa-Profile-CV'
OUTPUT_PROFILE_FILE = f"{OUTPUT_NAME}.pdf"

PROFIL_CERTIF_FILES = [
    'docs/profile.pdf',
    'docs/aws-machine-learning-fundamentals.pdf',
    'docs/ai-programming-with-python.pdf',
]

# Get today's date and format it
today_str = datetime.today().strftime('%d%m%y')
LATEST_OUTPUT_PROFILE_FILE = f"{OUTPUT_NAME}-{today_str}.pdf"

# open pdf merger
merger = PdfMerger()

for certif in PROFIL_CERTIF_FILES:
    merger.append(certif)

# write pdf merger content
merger.write(OUTPUT_PROFILE_FILE)

# close pdf merger
merger.close()

# Copy the file
shutil.copy(OUTPUT_PROFILE_FILE, LATEST_OUTPUT_PROFILE_FILE)