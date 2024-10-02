from datetime import datetime
from PyPDF2 import PdfMerger

OUT_PUT_PROFILE_FILE = 'docs/Nathan-Bangwa-Profile-CV'

PROFIL_CERTIF_FILES = [
    'docs/profile.pdf',
    'docs/aws-machine-learning-fundamentals.pdf',
    'docs/ai-programming-with-python.pdf',
]

# Get today's date and format it
today_str = datetime.today().strftime('%d%m%y')

# open pdf merger
merger = PdfMerger()

for certif in PROFIL_CERTIF_FILES:
    merger.append(certif)

# write pdf merger content
merger.write(f"{OUT_PUT_PROFILE_FILE}.pdf")
merger.write(f"{OUT_PUT_PROFILE_FILE}-{today_str}.pdf")

# close pdf merger
merger.close()