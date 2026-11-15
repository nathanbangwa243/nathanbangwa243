@echo off
echo ============================================================
echo   Outil de nettoyage disque - Windows 11
echo   Fichiers lourds (^> 500 Mo) + Doublons + Cache systeme
echo ============================================================
echo.
echo   IMPORTANT : Executez en tant qu'administrateur pour
echo   un scan complet de tous les dossiers.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Find-LargeFiles.ps1"

echo.
pause
