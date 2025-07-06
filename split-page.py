from PyPDF2 import PdfReader, PdfWriter
import os

def diviser_pdf(chemin_pdf_original, page_min, page_max, chemin_pdf_sortie):
    """
    Divise un fichier PDF pour en récupérer une partie spécifique.

    Args:
        chemin_pdf_original (str): Le chemin complet vers le fichier PDF original.
        page_min (int): Le numéro de la première page à inclure (1-basé).
        page_max (int): Le numéro de la dernière page à inclure (1-basé).
        chemin_pdf_sortie (str): Le chemin complet où le PDF divisé sera sauvegardé.
    """
    if not os.path.exists(chemin_pdf_original):
        print(f"Erreur : Le fichier source '{chemin_pdf_original}' n'existe pas.")
        return

    try:
        reader = PdfReader(chemin_pdf_original)
        writer = PdfWriter()

        total_pages = len(reader.pages)

        # Ajuster les index pour qu'ils soient 0-basés pour PyPDF2
        # et gérer les cas où page_min ou page_max sont hors limites
        start_index = max(0, page_min - 1)
        end_index = min(total_pages, page_max)

        if start_index >= total_pages:
            print(f"Attention : La page de début ({page_min}) est au-delà du nombre total de pages ({total_pages}).")
            return
        if start_index >= end_index:
            print(f"Attention : La page de début ({page_min}) est égale ou supérieure à la page de fin ({page_max}). Aucun intervalle valide.")
            return

        print(f"Le PDF original contient {total_pages} pages.")
        print(f"Extraction des pages de {page_min} à {page_max} (indices 0-basés de {start_index} à {end_index-1})...")

        for i in range(start_index, end_index):
            if i < total_pages: # Sécurité supplémentaire, bien que min/max le gère
                writer.add_page(reader.pages[i])
            else:
                print(f"Avertissement : La page {i+1} n'existe pas dans le document original et sera ignorée.")

        if not writer.pages:
            print("Aucune page n'a été ajoutée au nouveau PDF. Vérifiez vos numéros de page.")
            return

        with open(chemin_pdf_sortie, 'wb') as output_pdf:
            writer.write(output_pdf)

        print(f"Succès : Les pages de {page_min} à {page_max} ont été extraites dans '{chemin_pdf_sortie}'.")

    except Exception as e:
        print(f"Une erreur est survenue : {e}")

# --- EXEMPLE D'UTILISATION ---
if __name__ == "__main__":
    # Assurez-vous que ce fichier PDF existe dans le même répertoire que votre script,
    # ou fournissez le chemin complet.
    pdf_entree = "mon_document.pdf"
    pdf_sortie = "partie_extraite.pdf"

    # Définissez les pages min et max que vous souhaitez extraire
    # Exemple : extraire les pages 2 à 5
    page_debut = 81
    page_fin = 153

    diviser_pdf(pdf_entree, page_debut, page_fin, pdf_sortie)

    # print("\n--- Deuxième exemple ---")
    # # Exemple : extraire seulement la page 1
    # pdf_sortie_simple_page = "premiere_page.pdf"
    # diviser_pdf(pdf_entree, 1, 1, pdf_sortie_simple_page)

    # print("\n--- Exemple avec pages hors limites ---")
    # # Exemple : tenter d'extraire des pages qui n'existent pas
    # diviser_pdf(pdf_entree, 100, 105, "pages_inexistantes.pdf")

    # print("\n--- Exemple avec fichier inexistant ---")
    # diviser_pdf("fichier_non_existant.pdf", 1, 2, "resultat_erreur.pdf")