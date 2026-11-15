"""Merge the PDF documents listed in mergeConfig.json into a single profile PDF."""

import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

from pypdf import PdfReader, PdfWriter

ROOT = Path(__file__).resolve().parent
DEFAULT_CONFIG = ROOT / "mergeConfig.json"


def load_config(config_path):
    if not config_path.is_file():
        sys.exit(f"Erreur : le fichier de configuration '{config_path}' est introuvable.")

    try:
        with config_path.open(encoding="utf-8") as fp:
            config = json.load(fp)
    except json.JSONDecodeError as exc:
        sys.exit(f"Erreur : '{config_path}' n'est pas un JSON valide ({exc}).")

    documents = config.get("documents")
    if not documents or not isinstance(documents, list):
        sys.exit(f"Erreur : '{config_path}' doit contenir une liste non vide 'documents'.")

    output = config.get("output", {})
    output_name = output.get("name")
    if not output_name or not isinstance(output_name, str):
        sys.exit(f"Erreur : '{config_path}' doit définir 'output.name'.")

    return documents, output


def resolve_documents(documents):
    resolved = []
    for entry in documents:
        if isinstance(entry, str):
            entry = {"path": entry}
        path = ROOT / entry.get("path", "")
        pages = entry.get("pages")
        if pages is not None:
            if not isinstance(pages, list) or len(pages) != 2:
                sys.exit(f"Erreur : 'pages' de '{entry.get('path')}' doit être [page_min, page_max].")
            pages = (int(pages[0]), int(pages[1]))
        if not path.is_file():
            sys.exit(f"Erreur : le document '{path}' est introuvable.")
        resolved.append((path, pages))
    return resolved


def merge_documents(documents, output_file):
    writer = PdfWriter()
    for path, pages in documents:
        reader = PdfReader(path)
        total_pages = len(reader.pages)
        if pages is None:
            print(f"Fusion de '{path}' ({total_pages} pages)...")
            writer.append(reader)
            continue

        page_min, page_max = pages
        start_index = max(0, page_min - 1)
        end_index = min(total_pages, page_max)
        if start_index >= end_index:
            sys.exit(
                f"Erreur : intervalle de pages invalide pour '{path}' "
                f"({page_min}-{page_max} sur {total_pages} pages)."
            )
        print(f"Fusion de '{path}' (pages {page_min} à {page_max})...")
        writer.append(reader, pages=(start_index, end_index))

    if not writer.pages:
        sys.exit("Erreur : aucun document à fusionner.")

    output_file.parent.mkdir(parents=True, exist_ok=True)
    with output_file.open("wb") as fp:
        writer.write(fp)
    print(f"Profil généré : '{output_file}' ({len(writer.pages)} pages).")


def main():
    parser = argparse.ArgumentParser(description="Fusionne les PDFs définis dans mergeConfig.json.")
    parser.add_argument(
        "-c",
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help=f"Chemin du fichier de configuration (défaut : {DEFAULT_CONFIG}).",
    )
    args = parser.parse_args()

    documents, output = load_config(args.config)
    resolved = resolve_documents(documents)

    output_file = ROOT / output["name"]
    merge_documents(resolved, output_file)

    if output.get("datedCopy", True):
        date_format = output.get("dateFormat", "%d%m%y")
        today_str = datetime.today().strftime(date_format)
        dated_file = output_file.with_name(f"{output_file.stem}-{today_str}{output_file.suffix}")
        shutil.copy(output_file, dated_file)
        print(f"Copie datée : '{dated_file}'.")


if __name__ == "__main__":
    main()
