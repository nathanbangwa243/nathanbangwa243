# Find-LargeFiles.ps1
# =============================================================================
# Outil complet de nettoyage disque pour Windows 11
# - Fichiers lourds (> 500 Mo)
# - Detection de doublons (toutes tailles)
# - Nettoyage systeme (temp, cache, corbeille, etc.)
# - Suppression supervisee (confirmation pour chaque fichier)
# - Optimisations systeme (hibernation, cleanmgr, Storage Sense, etc.)
# =============================================================================

param (
    [string]$RootPath   = 'C:\',
    [float] $MinSizeMB  = 500
)

$MinSizeBytes  = $MinSizeMB * 1MB
$largeFiles    = @()
$allFiles      = @()
$foldersScanned = 0

# --- Output file (Desktop, timestamped) ---
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$outputFile = Join-Path -Path $env:USERPROFILE -ChildPath "Desktop\DiskCleanup_$timestamp.txt"
$reportLines = @()

function Write-Section ($title) {
    $bar = "=" * 60
    Write-Host ""
    Write-Host "  $bar" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "  $bar" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Verbose-Info ($message) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "  [$ts] [INFO]    $message" -ForegroundColor DarkCyan
}

function Write-Verbose-Action ($message) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "  [$ts] [ACTION]  $message" -ForegroundColor White
}

function Write-Verbose-OK ($message) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "  [$ts] [OK]      $message" -ForegroundColor Green
}

function Write-Verbose-Warn ($message) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "  [$ts] [WARN]    $message" -ForegroundColor Yellow
}

function Write-Verbose-Error ($message) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "  [$ts] [ERREUR]  $message" -ForegroundColor Red
}

function Write-Verbose-Skip ($message) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "  [$ts] [SKIP]    $message" -ForegroundColor DarkGray
}

function Add-Report ($text) {
    $script:reportLines += $text
}

# =============================================================================
#  PHASE 1 : Scan du disque
# =============================================================================
Write-Section "PHASE 1 : Scan du disque $RootPath"
Write-Verbose-Info "Objectif : parcourir tout le disque et collecter les fichiers."
Write-Verbose-Info "Seuil fichiers lourds : $MinSizeMB Mo ($("{0:N2}" -f ($MinSizeMB / 1024)) Go)"
Write-Verbose-Info "Doublons : tous les fichiers sont indexes pour la detection."
Write-Verbose-Info "Les dossiers proteges seront ignores silencieusement (acces refuse)."
Write-Host ""
Write-Verbose-Action "Enumeration des dossiers racine de $RootPath..."

$topDirs = @($RootPath)
try {
    $topDirs += Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName
} catch { }

Write-Verbose-Info "$($topDirs.Count) dossier(s) racine trouves. Demarrage du scan..."
Write-Host ""

$scanStart = Get-Date
$fileCount = 0

foreach ($dir in $topDirs) {
    $foldersScanned++
    Write-Host "`r  [Scan] ($foldersScanned/$($topDirs.Count)) $dir                                        " -NoNewline -ForegroundColor Yellow

    try {
        $files = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue

        foreach ($f in $files) {
            $fileCount++
            # Collect ALL files for duplicate detection
            $allFiles += $f

            # Collect large files
            if ($f.Length -ge $MinSizeBytes) {
                $largeFiles += [PSCustomObject]@{
                    FullPath      = $f.FullName
                    SizeGB        = [math]::Round($f.Length / 1GB, 2)
                    SizeMB        = [math]::Round($f.Length / 1MB, 2)
                    LastWriteTime = $f.LastWriteTime
                    Length        = $f.Length
                }
                Write-Host ""
                Write-Verbose-Info "Fichier lourd trouve : $($f.FullName) ($("{0:N0}" -f ($f.Length / 1MB)) Mo)"
            }
        }
    } catch { }
}

$scanDuration = (Get-Date) - $scanStart
Write-Host ""
Write-Verbose-OK "Scan termine en $("{0:mm\:ss}" -f $scanDuration)."
Write-Verbose-Info "$foldersScanned dossier(s) parcourus, $($allFiles.Count) fichier(s) indexes."
Write-Verbose-Info "$($largeFiles.Count) fichier(s) depassent le seuil de $MinSizeMB Mo."

# Sort large files
$largeFiles = $largeFiles | Sort-Object Length -Descending

# =============================================================================
#  PHASE 2 : Detection des doublons
# =============================================================================
Write-Section "PHASE 2 : Detection des doublons"
Write-Verbose-Info "Objectif : identifier les fichiers presents en plusieurs copies."
Write-Verbose-Info "Methode : regroupement par taille, puis verification par hash MD5."
Write-Verbose-Info "Seuls les fichiers de meme taille sont compares (optimisation)."
Write-Host ""

Write-Verbose-Action "Etape 1/2 : Regroupement des fichiers par taille..."
$sizeGroups = $allFiles | Group-Object -Property Length | Where-Object { $_.Count -gt 1 -and $_.Name -ne '0' }

$candidateFiles = ($sizeGroups | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
Write-Verbose-OK "$($sizeGroups.Count) groupe(s) de meme taille trouves ($candidateFiles fichiers candidats)."
Write-Host ""

Write-Verbose-Action "Etape 2/2 : Calcul des empreintes MD5 des fichiers candidats..."
Write-Verbose-Info "Cela peut prendre du temps selon le nombre et la taille des fichiers..."

$duplicateGroups = @()
$hashCount = 0
$hashStart = Get-Date

foreach ($group in $sizeGroups) {
    $hashes = @{}
    foreach ($file in $group.Group) {
        $hashCount++
        if ($hashCount % 200 -eq 0) {
            $elapsed = (Get-Date) - $hashStart
            Write-Host "`r  [Hash] $hashCount / $candidateFiles fichiers traites ($('{0:mm\:ss}' -f $elapsed) ecoules)...          " -NoNewline -ForegroundColor Yellow
        }
        try {
            $hash = (Get-FileHash -Path $file.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
            if ($hash) {
                if (-not $hashes.ContainsKey($hash)) {
                    $hashes[$hash] = @()
                }
                $hashes[$hash] += $file
            }
        } catch { }
    }

    foreach ($key in $hashes.Keys) {
        if ($hashes[$key].Count -gt 1) {
            $duplicateGroups += [PSCustomObject]@{
                Hash  = $key
                Files = $hashes[$key]
                Count = $hashes[$key].Count
                SizeMB = [math]::Round($hashes[$key][0].Length / 1MB, 2)
            }
        }
    }
}

$hashDuration = (Get-Date) - $hashStart
Write-Host ""
Write-Verbose-OK "$hashCount fichiers hashes en $('{0:mm\:ss}' -f $hashDuration)."
Write-Verbose-Info "$($duplicateGroups.Count) groupe(s) de doublons confirmes (hash MD5 identique)."

# =============================================================================
#  PHASE 3 : Analyse systeme (mecanismes supplementaires)
# =============================================================================
Write-Section "PHASE 3 : Analyse systeme"
Write-Verbose-Info "Objectif : detecter les sources de gaspillage systeme."
Write-Verbose-Info "Analyse des dossiers temporaires, caches, corbeille, etc."
Write-Host ""

$cleanupItems = @()

# 3a. Dossier TEMP utilisateur
Write-Verbose-Action "Analyse du dossier TEMP utilisateur..."
$userTemp = $env:TEMP
if (Test-Path $userTemp) {
    $tempFiles = Get-ChildItem -Path $userTemp -Recurse -File -ErrorAction SilentlyContinue
    $tempSizeMB = [math]::Round(($tempFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $cleanupItems += [PSCustomObject]@{ Name = "Fichiers temporaires utilisateur"; Path = $userTemp; SizeMB = $tempSizeMB; FileCount = $tempFiles.Count }
    Write-Verbose-OK "[TEMP User]     $tempSizeMB Mo ($($tempFiles.Count) fichiers) - $userTemp"
} else {
    Write-Verbose-Skip "Dossier TEMP utilisateur introuvable."
}

# 3b. Dossier TEMP Windows
Write-Verbose-Action "Analyse du dossier TEMP Windows..."
$winTemp = "$env:SystemRoot\Temp"
if (Test-Path $winTemp) {
    $tempFiles = Get-ChildItem -Path $winTemp -Recurse -File -ErrorAction SilentlyContinue
    $tempSizeMB = [math]::Round(($tempFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $cleanupItems += [PSCustomObject]@{ Name = "Fichiers temporaires Windows"; Path = $winTemp; SizeMB = $tempSizeMB; FileCount = $tempFiles.Count }
    Write-Verbose-OK "[TEMP Windows]  $tempSizeMB Mo ($($tempFiles.Count) fichiers) - $winTemp"
} else {
    Write-Verbose-Skip "Dossier TEMP Windows introuvable."
}

# 3c. Cache Windows Update
Write-Verbose-Action "Analyse du cache Windows Update..."
$wuCache = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $wuCache) {
    $wuFiles = Get-ChildItem -Path $wuCache -Recurse -File -ErrorAction SilentlyContinue
    $wuSizeMB = [math]::Round(($wuFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $cleanupItems += [PSCustomObject]@{ Name = "Cache Windows Update"; Path = $wuCache; SizeMB = $wuSizeMB; FileCount = $wuFiles.Count }
    Write-Verbose-OK "[WinUpdate]     $wuSizeMB Mo ($($wuFiles.Count) fichiers) - $wuCache"
} else {
    Write-Verbose-Skip "Cache Windows Update introuvable."
}

# 3d. Corbeille
Write-Verbose-Action "Analyse de la corbeille..."
try {
    $shell = New-Object -ComObject Shell.Application
    $recycleBin = $shell.NameSpace(0x0a)
    $rbCount = $recycleBin.Items().Count
    $rbSizeMB = 0
    foreach ($item in $recycleBin.Items()) {
        try { $rbSizeMB += [math]::Round($recycleBin.GetDetailsOf($item, 2) / 1MB, 2) } catch {}
    }
    $cleanupItems += [PSCustomObject]@{ Name = "Corbeille"; Path = "Recycle Bin"; SizeMB = $rbSizeMB; FileCount = $rbCount }
    Write-Verbose-OK "[Corbeille]     $rbCount element(s) dans la corbeille"
} catch {
    Write-Verbose-Warn "Impossible de lire la corbeille."
}

# 3e. Prefetch
Write-Verbose-Action "Analyse du dossier Prefetch..."
$prefetchPath = "$env:SystemRoot\Prefetch"
if (Test-Path $prefetchPath) {
    $pfFiles = Get-ChildItem -Path $prefetchPath -File -ErrorAction SilentlyContinue
    $pfSizeMB = [math]::Round(($pfFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $cleanupItems += [PSCustomObject]@{ Name = "Prefetch"; Path = $prefetchPath; SizeMB = $pfSizeMB; FileCount = $pfFiles.Count }
    Write-Verbose-OK "[Prefetch]      $pfSizeMB Mo ($($pfFiles.Count) fichiers) - $prefetchPath"
} else {
    Write-Verbose-Skip "Dossier Prefetch introuvable."
}

# 3f. Windows.old
Write-Verbose-Action "Recherche du dossier Windows.old..."
$winOld = "C:\Windows.old"
if (Test-Path $winOld) {
    $woFiles = Get-ChildItem -Path $winOld -Recurse -File -ErrorAction SilentlyContinue
    $woSizeMB = [math]::Round(($woFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $cleanupItems += [PSCustomObject]@{ Name = "Windows.old (ancienne installation)"; Path = $winOld; SizeMB = $woSizeMB; FileCount = $woFiles.Count }
    Write-Verbose-Warn "[Windows.old]   $woSizeMB Mo - $winOld  << Peut liberer beaucoup d'espace !"
} else {
    Write-Verbose-Skip "Pas de dossier Windows.old (aucune ancienne installation)."
}

# 3g. Fichier d'hibernation
Write-Verbose-Action "Verification du fichier d'hibernation (hiberfil.sys)..."
$hiberfil = "C:\hiberfil.sys"
if (Test-Path $hiberfil) {
    $hibSize = [math]::Round((Get-Item $hiberfil -Force -ErrorAction SilentlyContinue).Length / 1GB, 2)
    Write-Verbose-Warn "[Hibernation]   $hibSize Go - $hiberfil (desactivable en Phase 6)"
} else {
    Write-Verbose-Skip "Hibernation deja desactivee (hiberfil.sys absent)."
}

# 3h. Fichier de swap / pagefile
Write-Verbose-Action "Verification du fichier pagefile (pagefile.sys)..."
$pagefile = "C:\pagefile.sys"
if (Test-Path $pagefile) {
    $pfSize = [math]::Round((Get-Item $pagefile -Force -ErrorAction SilentlyContinue).Length / 1GB, 2)
    Write-Verbose-Info "[Pagefile]      $pfSize Go - $pagefile (gere par Windows, non modifiable ici)"
} else {
    Write-Verbose-Skip "Pagefile introuvable."
}

Write-Host ""
Write-Verbose-OK "Analyse systeme terminee. $($cleanupItems.Count) source(s) de nettoyage identifiee(s)."

# =============================================================================
#  PHASE 4 : Affichage des resultats
# =============================================================================
Write-Section "RESULTATS : Fichiers lourds (> $MinSizeMB Mo)"
Write-Verbose-Info "Affichage de tous les fichiers depassant $MinSizeMB Mo, tries par taille decroissante."
Write-Host ""

Add-Report "============================================================"
Add-Report "  RAPPORT DE NETTOYAGE DISQUE"
Add-Report "  Racine     : $RootPath"
Add-Report "  Date       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-Report "============================================================"
Add-Report ""
Add-Report "--- FICHIERS LOURDS (> $MinSizeMB Mo) ---"
Add-Report ""

if ($largeFiles.Count -eq 0) {
    Write-Verbose-Info "Aucun fichier superieur a $MinSizeMB Mo."
    Add-Report "Aucun fichier superieur a $MinSizeMB Mo."
} else {
    $totalSizeGB = ($largeFiles | Measure-Object -Property SizeGB -Sum).Sum
    Write-Verbose-OK "$($largeFiles.Count) fichier(s) trouves - Total : $("{0:N2}" -f $totalSizeGB) Go"
    Write-Host ""
    Write-Host ("  {0,4}  {1,-10}  {2,-22}  {3}" -f "#", "Taille", "Derniere modif.", "Chemin") -ForegroundColor White
    Write-Host ("  {0,4}  {1,-10}  {2,-22}  {3}" -f "---", "------", "---------------", "------") -ForegroundColor DarkGray

    $i = 0
    foreach ($file in $largeFiles) {
        $i++
        if ($file.SizeGB -ge 1) {
            $sizeLabel = "{0:N2} Go" -f $file.SizeGB
        } else {
            $sizeLabel = "{0:N0} Mo" -f $file.SizeMB
        }
        Write-Host ("  {0,4}  {1,-10}  {2,-22}  {3}" -f $i, $sizeLabel, $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $file.FullPath)
        Add-Report ("{0,4}. [{1}]  {2}  (modifie: {3})" -f $i, $sizeLabel, $file.FullPath, $file.LastWriteTime)
    }
    Write-Host ""
    Write-Host "  Total : $("{0:N2}" -f $totalSizeGB) Go en $($largeFiles.Count) fichier(s)" -ForegroundColor White
    Add-Report ""
    Add-Report "Total : $("{0:N2}" -f $totalSizeGB) Go en $($largeFiles.Count) fichier(s)"
}

# --- Duplicates display ---
Write-Section "RESULTATS : Doublons detectes"
Write-Verbose-Info "Les doublons sont des fichiers identiques (meme hash MD5) presents a plusieurs endroits."
Write-Verbose-Info "Le premier fichier de chaque groupe est marque comme [ORIGINAL]."
Write-Host ""

Add-Report ""
Add-Report "--- DOUBLONS DETECTES ---"
Add-Report ""

if ($duplicateGroups.Count -eq 0) {
    Write-Verbose-Info "Aucun doublon detecte."
    Add-Report "Aucun doublon detecte."
} else {
    $dupWaste = 0
    $groupNum = 0
    foreach ($dg in $duplicateGroups) {
        $groupNum++
        $wastedMB = [math]::Round($dg.SizeMB * ($dg.Count - 1), 2)
        $dupWaste += $wastedMB

        Write-Host "  Groupe $groupNum | $($dg.Count) copies | $($dg.SizeMB) Mo chacun | Gaspillage: $wastedMB Mo" -ForegroundColor Yellow
        Add-Report "Groupe $groupNum | $($dg.Count) copies | $($dg.SizeMB) Mo chacun | Gaspillage: $wastedMB Mo"

        $fileIdx = 0
        foreach ($f in $dg.Files) {
            $fileIdx++
            $marker = if ($fileIdx -eq 1) { "[ORIGINAL]" } else { "[DOUBLON] " }
            Write-Host "    $marker $($f.FullName)" -ForegroundColor $(if ($fileIdx -eq 1) { 'Green' } else { 'DarkGray' })
            Add-Report "    $marker $($f.FullName)"
        }
        Write-Host ""
        Add-Report ""
    }
    Write-Verbose-Warn "Espace total gaspille par les doublons : $("{0:N2}" -f ($dupWaste / 1024)) Go"
    Add-Report "Espace gaspille par les doublons : $("{0:N2}" -f ($dupWaste / 1024)) Go"
}

# --- System cleanup summary ---
Add-Report ""
Add-Report "--- NETTOYAGE SYSTEME ---"
Add-Report ""
foreach ($ci in $cleanupItems) {
    Add-Report "$($ci.Name) : $($ci.SizeMB) Mo ($($ci.FileCount) fichiers) - $($ci.Path)"
}

# =============================================================================
#  PHASE 5 : Suppression supervisee
# =============================================================================
Write-Section "PHASE 5 : Suppression supervisee"
Write-Verbose-Info "Objectif : vous proposer de supprimer chaque element un par un."
Write-Verbose-Info "RIEN ne sera supprime sans votre accord explicite."
Write-Verbose-Info "Raccourcis : [O] = Oui supprimer, [N] = Non garder, [Q] = Tout quitter."
Write-Host ""

$deletedCount = 0
$freedBytes   = 0
$globalQuit   = $false

# --- 5a. Large files ---
if ($largeFiles.Count -gt 0) {
    Write-Host "  --- Fichiers lourds ($($largeFiles.Count) fichier(s)) ---" -ForegroundColor Cyan
    Write-Verbose-Info "Chaque fichier sera affiche avec sa taille et son chemin complet."
    Write-Host ""
    $fileNum = 0
    foreach ($file in $largeFiles) {
        $fileNum++
        if ($file.SizeGB -ge 1) {
            $sizeLabel = "{0:N2} Go" -f $file.SizeGB
        } else {
            $sizeLabel = "{0:N0} Mo" -f $file.SizeMB
        }

        Write-Host "  [$fileNum/$($largeFiles.Count)] [$sizeLabel] $($file.FullPath)" -ForegroundColor White
        Write-Verbose-Info "Derniere modification : $($file.LastWriteTime)"
        $choice = Read-Host "  Supprimer ce fichier ? (O/N/Q)"

        switch ($choice.ToUpper()) {
            'O' {
                Write-Verbose-Action "Suppression de $($file.FullPath)..."
                try {
                    Remove-Item -Path $file.FullPath -Force -ErrorAction Stop
                    Write-Verbose-OK "Fichier supprime ! $sizeLabel liberes."
                    $deletedCount++
                    $freedBytes += $file.Length
                    Add-Report "[SUPPRIME] $($file.FullPath) ($sizeLabel)"
                } catch {
                    Write-Verbose-Error "Impossible de supprimer : $_"
                    Add-Report "[ERREUR]   $($file.FullPath) - $_"
                }
            }
            'Q' {
                Write-Verbose-Warn "Suppression des fichiers lourds interrompue par l'utilisateur."
                $globalQuit = $true
                break
            }
            default {
                Write-Verbose-Skip "Fichier conserve."
                Add-Report "[CONSERVE] $($file.FullPath)"
            }
        }
        Write-Host ""
        if ($globalQuit) { break }
    }
}

# --- 5b. Duplicate files ---
if (-not $globalQuit -and $duplicateGroups.Count -gt 0) {
    Write-Host ""
    Write-Host "  --- Doublons ($($duplicateGroups.Count) groupe(s)) ---" -ForegroundColor Cyan
    Write-Verbose-Info "Le 1er fichier de chaque groupe est l'original et sera TOUJOURS conserve."
    Write-Verbose-Info "Seules les copies (doublons) vous seront proposees a la suppression."
    Write-Host ""

    $groupNum = 0
    foreach ($dg in $duplicateGroups) {
        $groupNum++
        Write-Host "  Groupe $groupNum/$($duplicateGroups.Count) | $($dg.Count) copies | $($dg.SizeMB) Mo chacun" -ForegroundColor Yellow
        Write-Verbose-Info "Hash MD5 : $($dg.Hash)"
        Write-Host "  Original (conserve) : $($dg.Files[0].FullName)" -ForegroundColor Green

        for ($idx = 1; $idx -lt $dg.Files.Count; $idx++) {
            $dup = $dg.Files[$idx]
            $sizeLbl = "{0:N2} Mo" -f ($dup.Length / 1MB)
            Write-Host "  [DOUBLON $idx/$($dg.Count - 1)] [$sizeLbl] $($dup.FullName)" -ForegroundColor Yellow
            Write-Verbose-Info "Derniere modification : $($dup.LastWriteTime)"
            $choice = Read-Host "  Supprimer ce doublon ? (O/N/Q)"

            switch ($choice.ToUpper()) {
                'O' {
                    Write-Verbose-Action "Suppression du doublon $($dup.FullName)..."
                    try {
                        Remove-Item -Path $dup.FullName -Force -ErrorAction Stop
                        Write-Verbose-OK "Doublon supprime ! $sizeLbl liberes."
                        $deletedCount++
                        $freedBytes += $dup.Length
                        Add-Report "[SUPPRIME] $($dup.FullName) (doublon)"
                    } catch {
                        Write-Verbose-Error "Impossible de supprimer : $_"
                        Add-Report "[ERREUR]   $($dup.FullName) - $_"
                    }
                }
                'Q' {
                    Write-Verbose-Warn "Suppression des doublons interrompue par l'utilisateur."
                    $globalQuit = $true
                    break
                }
                default {
                    Write-Verbose-Skip "Doublon conserve."
                    Add-Report "[CONSERVE] $($dup.FullName)"
                }
            }
            if ($globalQuit) { break }
        }
        Write-Host ""
        if ($globalQuit) { break }
    }
}

# --- 5c. System cleanup ---
if (-not $globalQuit) {
    Write-Host ""
    Write-Host "  --- Nettoyage systeme ($($cleanupItems.Count) source(s)) ---" -ForegroundColor Cyan
    Write-Verbose-Info "Chaque dossier systeme sera propose au nettoyage."
    Write-Verbose-Info "Certains fichiers en cours d'utilisation ne pourront pas etre supprimes."
    Write-Host ""

    foreach ($ci in $cleanupItems) {
        if ($ci.SizeMB -gt 0 -and $ci.Path -ne "Recycle Bin") {
            Write-Host "  [$($ci.SizeMB) Mo | $($ci.FileCount) fichiers] $($ci.Name)" -ForegroundColor White
            Write-Verbose-Info "Chemin : $($ci.Path)"
            $choice = Read-Host "  Vider ce dossier ? (O/N/Q)"

            switch ($choice.ToUpper()) {
                'O' {
                    Write-Verbose-Action "Nettoyage de $($ci.Path)..."
                    try {
                        $beforeCount = (Get-ChildItem -Path $ci.Path -Recurse -ErrorAction SilentlyContinue).Count
                        Get-ChildItem -Path $ci.Path -Recurse -ErrorAction SilentlyContinue |
                            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                        $afterCount = (Get-ChildItem -Path $ci.Path -Recurse -ErrorAction SilentlyContinue).Count
                        $cleaned = $beforeCount - $afterCount
                        Write-Verbose-OK "Nettoyage termine ! $cleaned element(s) supprime(s) sur $beforeCount."
                        if ($afterCount -gt 0) {
                            Write-Verbose-Warn "$afterCount element(s) n'ont pas pu etre supprimes (fichiers en cours d'utilisation)."
                        }
                        Add-Report "[NETTOYE]  $($ci.Name) ($($ci.Path)) - $cleaned elements supprimes"
                    } catch {
                        Write-Verbose-Error "Erreur lors du nettoyage : $_"
                    }
                }
                'Q' {
                    Write-Verbose-Warn "Nettoyage systeme interrompu par l'utilisateur."
                    $globalQuit = $true
                    break
                }
                default {
                    Write-Verbose-Skip "Dossier ignore."
                }
            }
            Write-Host ""
            if ($globalQuit) { break }
        }
    }

    # Propose emptying recycle bin
    if (-not $globalQuit) {
        Write-Host ""
        Write-Host "  [Corbeille] Vider la corbeille ?" -ForegroundColor White
        Write-Verbose-Info "Cette action supprimera definitivement tous les fichiers dans la corbeille."
        $choice = Read-Host "  (O/N)"
        if ($choice.ToUpper() -eq 'O') {
            Write-Verbose-Action "Vidage de la corbeille..."
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                Write-Verbose-OK "Corbeille videe !"
                Add-Report "[NETTOYE]  Corbeille videe"
            } catch {
                Write-Verbose-Error "Impossible de vider la corbeille : $_"
            }
        } else {
            Write-Verbose-Skip "Corbeille conservee."
        }
    }
}

# =============================================================================
#  PHASE 6 : Optimisations systeme (supervisees)
# =============================================================================
Write-Section "PHASE 6 : Optimisations systeme"
Write-Verbose-Info "Objectif : appliquer des optimisations Windows pour liberer encore plus d'espace."
Write-Verbose-Info "Chaque action est optionnelle et demande votre confirmation."
Write-Verbose-Info "Raccourcis : [O] = Oui appliquer, [N] = Non ignorer, [Q] = Tout quitter."
Write-Host ""

$quitOptim = $false

# --- 6a. Desactiver l'hibernation ---
if (-not $quitOptim) {
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  6a. HIBERNATION" -ForegroundColor Cyan
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Verbose-Info "L'hibernation sauvegarde la RAM sur disque dans hiberfil.sys."
    Write-Verbose-Info "Ce fichier est souvent aussi gros que votre RAM (4-16 Go)."
    Write-Verbose-Info "Si vous n'utilisez pas l'hibernation, le desactiver libere cet espace."
    Write-Verbose-Info "Note : la mise en veille (sleep) continuera de fonctionner normalement."
    Write-Host ""

    $hiberfil = "C:\hiberfil.sys"
    if (Test-Path $hiberfil) {
        $hibSize = [math]::Round((Get-Item $hiberfil -Force -ErrorAction SilentlyContinue).Length / 1GB, 2)
        Write-Verbose-Warn "hiberfil.sys detecte : $hibSize Go"
        Write-Verbose-Info "Commande qui sera executee : powercfg /h off"
        $choice = Read-Host "  Desactiver l'hibernation et liberer ~$hibSize Go ? (O/N/Q)"
        switch ($choice.ToUpper()) {
            'O' {
                Write-Verbose-Action "Execution de 'powercfg /h off'..."
                try {
                    Start-Process -FilePath "powercfg.exe" -ArgumentList "/h off" -Verb RunAs -Wait -ErrorAction Stop
                    Write-Verbose-OK "Hibernation desactivee ! ~$hibSize Go liberes."
                    Write-Verbose-Info "Pour reactiver : powercfg /h on"
                    Add-Report "[OPTIMISE] Hibernation desactivee (~$hibSize Go)"
                } catch {
                    Write-Verbose-Error "Echec (droits administrateur requis) : $_"
                }
            }
            'Q' { $quitOptim = $true; Write-Verbose-Warn "Optimisations interrompues." }
            default { Write-Verbose-Skip "Hibernation conservee." }
        }
    } else {
        Write-Verbose-OK "Hibernation deja desactivee (hiberfil.sys absent)."
    }
    Write-Host ""
}

# --- 6b. Nettoyage de disque Windows (cleanmgr) ---
if (-not $quitOptim) {
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  6b. NETTOYAGE DE DISQUE WINDOWS (cleanmgr)" -ForegroundColor Cyan
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Verbose-Info "L'outil integre cleanmgr nettoie les fichiers systeme inutiles :"
    Write-Verbose-Info "  - Fichiers Windows Update obsoletes"
    Write-Verbose-Info "  - Journaux systeme et rapports d'erreur"
    Write-Verbose-Info "  - Miniatures (thumbnails cache)"
    Write-Verbose-Info "  - Fichiers d'installation temporaires"
    Write-Verbose-Info "L'outil s'ouvrira dans une fenetre separee."
    Write-Host ""

    $choice = Read-Host "  Lancer le nettoyage de disque Windows ? (O/N/Q)"
    switch ($choice.ToUpper()) {
        'O' {
            Write-Verbose-Action "Configuration des categories de nettoyage dans le registre..."
            try {
                $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
                if (Test-Path $regPath) {
                    $categories = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
                    $catCount = 0
                    $categories | ForEach-Object {
                        Set-ItemProperty -Path $_.PSPath -Name "StateFlags0099" -Value 2 -ErrorAction SilentlyContinue
                        $catCount++
                    }
                    Write-Verbose-OK "$catCount categories de nettoyage activees."
                }
                Write-Verbose-Action "Lancement de cleanmgr.exe /sagerun:99 (attendez la fin de la fenetre)..."
                Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:99" -Wait -ErrorAction Stop
                Write-Verbose-OK "Nettoyage de disque termine !"
                Add-Report "[OPTIMISE] Nettoyage de disque cleanmgr execute"
            } catch {
                Write-Verbose-Error "Erreur lors du nettoyage : $_"
            }
        }
        'Q' { $quitOptim = $true; Write-Verbose-Warn "Optimisations interrompues." }
        default { Write-Verbose-Skip "Nettoyage de disque ignore." }
    }
    Write-Host ""
}

# --- 6c. Activer Storage Sense ---
if (-not $quitOptim) {
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  6c. STORAGE SENSE (nettoyage automatique)" -ForegroundColor Cyan
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Verbose-Info "Storage Sense est une fonctionnalite Windows 11 qui nettoie"
    Write-Verbose-Info "automatiquement les fichiers inutiles en arriere-plan."
    Write-Verbose-Info "Configuration qui sera appliquee :"
    Write-Verbose-Info "  - Fichiers temporaires : supprimes automatiquement"
    Write-Verbose-Info "  - Corbeille : videe apres 30 jours"
    Write-Verbose-Info "  - Dossier Telechargements : NON touche (securite)"
    Write-Verbose-Info "Modification via le registre (HKCU), aucun redemarrage requis."
    Write-Host ""

    $choice = Read-Host "  Activer Storage Sense ? (O/N/Q)"
    switch ($choice.ToUpper()) {
        'O' {
            Write-Verbose-Action "Ecriture des cles de registre Storage Sense..."
            try {
                $ssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
                if (-not (Test-Path $ssPath)) {
                    New-Item -Path $ssPath -Force | Out-Null
                    Write-Verbose-Info "Cle de registre creee : $ssPath"
                }
                Set-ItemProperty -Path $ssPath -Name "01" -Value 1 -Type DWord -Force
                Write-Verbose-Info "  -> Storage Sense : ACTIVE"
                Set-ItemProperty -Path $ssPath -Name "04" -Value 1 -Type DWord -Force
                Write-Verbose-Info "  -> Declenchement : espace disque faible"
                Set-ItemProperty -Path $ssPath -Name "08" -Value 1 -Type DWord -Force
                Write-Verbose-Info "  -> Nettoyage fichiers temp : ACTIVE"
                Set-ItemProperty -Path $ssPath -Name "256" -Value 30 -Type DWord -Force
                Write-Verbose-Info "  -> Corbeille auto : apres 30 jours"
                Set-ItemProperty -Path $ssPath -Name "512" -Value 0 -Type DWord -Force
                Write-Verbose-Info "  -> Telechargements : NON touche (0 = jamais)"

                Write-Verbose-OK "Storage Sense active avec succes !"
                Write-Verbose-Info "Vous pouvez verifier dans : Parametres > Systeme > Stockage"
                Add-Report "[OPTIMISE] Storage Sense active (temp auto, corbeille 30j)"
            } catch {
                Write-Verbose-Error "Erreur lors de l'activation : $_"
            }
        }
        'Q' { $quitOptim = $true; Write-Verbose-Warn "Optimisations interrompues." }
        default { Write-Verbose-Skip "Storage Sense non modifie." }
    }
    Write-Host ""
}

# --- 6d. Supprimer les anciens points de restauration ---
if (-not $quitOptim) {
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  6d. POINTS DE RESTAURATION (shadow copies)" -ForegroundColor Cyan
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Verbose-Info "Windows cree des points de restauration regulierement."
    Write-Verbose-Info "Les anciens points peuvent occuper plusieurs Go."
    Write-Verbose-Info "Seul le plus ancien sera supprime (le plus recent est conserve)."
    Write-Verbose-Info "Commande : vssadmin delete shadows /for=C: /oldest /quiet"
    Write-Host ""

    Write-Verbose-Action "Comptage des points de restauration existants..."
    try {
        $shadows = (vssadmin list shadows 2>$null | Select-String "Shadow Copy Volume").Count
        Write-Verbose-Info "$shadows point(s) de restauration detecte(s)."
    } catch {
        $shadows = "?"
        Write-Verbose-Warn "Impossible de compter les points (acces refuse ?)."
    }

    $choice = Read-Host "  Supprimer le plus ancien point de restauration ? (O/N/Q)"
    switch ($choice.ToUpper()) {
        'O' {
            Write-Verbose-Action "Execution de 'vssadmin delete shadows /for=C: /oldest /quiet'..."
            try {
                $proc = Start-Process -FilePath "vssadmin.exe" -ArgumentList "delete shadows /for=C: /oldest /quiet" -Verb RunAs -Wait -PassThru -ErrorAction Stop
                if ($proc.ExitCode -eq 0) {
                    Write-Verbose-OK "Ancien point de restauration supprime !"
                    Add-Report "[OPTIMISE] Ancien point de restauration supprime"
                } else {
                    Write-Verbose-Warn "La commande a retourne le code $($proc.ExitCode)."
                }
            } catch {
                Write-Verbose-Error "Echec (droits administrateur requis) : $_"
            }
        }
        'Q' { $quitOptim = $true; Write-Verbose-Warn "Optimisations interrompues." }
        default { Write-Verbose-Skip "Points de restauration conserves." }
    }
    Write-Host ""
}

# --- 6e. Nettoyage des caches developpeur ---
if (-not $quitOptim) {
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  6e. CACHES DEVELOPPEUR" -ForegroundColor Cyan
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Verbose-Info "Les outils de developpement stockent des caches volumineux."
    Write-Verbose-Info "Les supprimer est sans risque : ils seront recrees a la prochaine utilisation."
    Write-Verbose-Info "Detection des caches installes sur votre machine..."
    Write-Host ""

    $devCaches = @()

    # npm cache
    Write-Verbose-Action "Recherche du cache npm..."
    $npmCache = Join-Path $env:APPDATA "npm-cache"
    if (Test-Path $npmCache) {
        $size = [math]::Round((Get-ChildItem $npmCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 2)
        $devCaches += [PSCustomObject]@{ Name = "npm cache"; Path = $npmCache; SizeMB = $size; CleanCmd = "npm cache clean --force" }
        Write-Verbose-OK "npm cache detecte : $size Mo"
    } else {
        Write-Verbose-Skip "npm cache non trouve."
    }

    # pip cache
    Write-Verbose-Action "Recherche du cache pip..."
    $pipCache = Join-Path $env:LOCALAPPDATA "pip\Cache"
    if (Test-Path $pipCache) {
        $size = [math]::Round((Get-ChildItem $pipCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 2)
        $devCaches += [PSCustomObject]@{ Name = "pip cache"; Path = $pipCache; SizeMB = $size; CleanCmd = "pip cache purge" }
        Write-Verbose-OK "pip cache detecte : $size Mo"
    } else {
        Write-Verbose-Skip "pip cache non trouve."
    }

    # NuGet cache
    Write-Verbose-Action "Recherche du cache NuGet..."
    $nugetCache = Join-Path $env:LOCALAPPDATA "NuGet\v3-cache"
    if (Test-Path $nugetCache) {
        $size = [math]::Round((Get-ChildItem $nugetCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 2)
        $devCaches += [PSCustomObject]@{ Name = "NuGet cache"; Path = $nugetCache; SizeMB = $size; CleanCmd = "dotnet nuget locals all --clear" }
        Write-Verbose-OK "NuGet cache detecte : $size Mo"
    } else {
        Write-Verbose-Skip "NuGet cache non trouve."
    }

    # yarn cache
    Write-Verbose-Action "Recherche du cache Yarn..."
    $yarnCache = Join-Path $env:LOCALAPPDATA "Yarn\Cache"
    if (Test-Path $yarnCache) {
        $size = [math]::Round((Get-ChildItem $yarnCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 2)
        $devCaches += [PSCustomObject]@{ Name = "Yarn cache"; Path = $yarnCache; SizeMB = $size; CleanCmd = "yarn cache clean" }
        Write-Verbose-OK "Yarn cache detecte : $size Mo"
    } else {
        Write-Verbose-Skip "Yarn cache non trouve."
    }

    # Gradle cache
    Write-Verbose-Action "Recherche du cache Gradle..."
    $gradleCache = Join-Path $env:USERPROFILE ".gradle\caches"
    if (Test-Path $gradleCache) {
        $size = [math]::Round((Get-ChildItem $gradleCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 2)
        $devCaches += [PSCustomObject]@{ Name = "Gradle cache"; Path = $gradleCache; SizeMB = $size; CleanCmd = $null }
        Write-Verbose-OK "Gradle cache detecte : $size Mo"
    } else {
        Write-Verbose-Skip "Gradle cache non trouve."
    }

    # Maven cache
    Write-Verbose-Action "Recherche du cache Maven..."
    $mavenCache = Join-Path $env:USERPROFILE ".m2\repository"
    if (Test-Path $mavenCache) {
        $size = [math]::Round((Get-ChildItem $mavenCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 2)
        $devCaches += [PSCustomObject]@{ Name = "Maven cache (.m2)"; Path = $mavenCache; SizeMB = $size; CleanCmd = $null }
        Write-Verbose-OK "Maven cache detecte : $size Mo"
    } else {
        Write-Verbose-Skip "Maven cache non trouve."
    }

    # Docker
    Write-Verbose-Action "Recherche de Docker..."
    $dockerPath = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerPath) {
        $devCaches += [PSCustomObject]@{ Name = "Docker (images/containers inutilises)"; Path = "docker system"; SizeMB = 0; CleanCmd = "docker system prune -a -f" }
        Write-Verbose-OK "Docker detecte. 'docker system prune' disponible."
    } else {
        Write-Verbose-Skip "Docker non installe."
    }

    Write-Host ""

    if ($devCaches.Count -eq 0) {
        Write-Verbose-Info "Aucun cache developpeur detecte sur cette machine."
    } else {
        Write-Verbose-Info "$($devCaches.Count) cache(s) developpeur detecte(s). Nettoyage individuel :"
        Write-Host ""

        foreach ($dc in $devCaches) {
            $sizeLabel = if ($dc.SizeMB -gt 0) { "$($dc.SizeMB) Mo" } else { "taille variable" }
            Write-Host "    [$sizeLabel] $($dc.Name)" -ForegroundColor White
            Write-Verbose-Info "Chemin : $($dc.Path)"
            if ($dc.CleanCmd) {
                Write-Verbose-Info "Commande : $($dc.CleanCmd)"
            } else {
                Write-Verbose-Info "Methode : suppression directe du contenu du dossier."
            }
            $choice = Read-Host "    Nettoyer ? (O/N/Q)"

            switch ($choice.ToUpper()) {
                'O' {
                    if ($dc.CleanCmd) {
                        Write-Verbose-Action "Execution de '$($dc.CleanCmd)'..."
                        try {
                            Invoke-Expression $dc.CleanCmd 2>$null
                            Write-Verbose-OK "$($dc.Name) nettoye !"
                            Add-Report "[NETTOYE]  $($dc.Name) ($sizeLabel)"
                        } catch {
                            Write-Verbose-Error "Erreur partielle : $_"
                        }
                    } else {
                        Write-Verbose-Action "Suppression du contenu de $($dc.Path)..."
                        try {
                            Get-ChildItem -Path $dc.Path -Recurse -ErrorAction SilentlyContinue |
                                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                            Write-Verbose-OK "$($dc.Name) nettoye !"
                            Add-Report "[NETTOYE]  $($dc.Name) ($sizeLabel)"
                        } catch {
                            Write-Verbose-Error "Erreur partielle : $_"
                        }
                    }
                }
                'Q' {
                    $quitOptim = $true
                    Write-Verbose-Warn "Nettoyage des caches interrompu."
                    break
                }
                default { Write-Verbose-Skip "Cache conserve." }
            }
            Write-Host ""
            if ($quitOptim) { break }
        }
    }
}

# =============================================================================
#  PHASE 7 : Resume final
# =============================================================================
Write-Section "PHASE 7 : Resume final"

$freedMB = [math]::Round($freedBytes / 1MB, 2)
$freedGB = [math]::Round($freedBytes / 1GB, 2)

Write-Verbose-Info "Recapitulatif de cette session de nettoyage :"
Write-Host ""
Write-Host "  Fichiers analyses    : $($allFiles.Count)" -ForegroundColor White
Write-Host "  Fichiers lourds      : $($largeFiles.Count) (> $MinSizeMB Mo)" -ForegroundColor White
Write-Host "  Groupes de doublons  : $($duplicateGroups.Count)" -ForegroundColor White
Write-Host "  Fichiers supprimes   : $deletedCount" -ForegroundColor $(if ($deletedCount -gt 0) { 'Green' } else { 'DarkGray' })
Write-Host "  Espace libere        : $freedMB Mo ($freedGB Go)" -ForegroundColor $(if ($freedGB -gt 0) { 'Green' } else { 'DarkGray' })
Write-Host ""

Add-Report ""
Add-Report "============================================================"
Add-Report "  RESUME"
Add-Report "  Fichiers analyses    : $($allFiles.Count)"
Add-Report "  Fichiers lourds      : $($largeFiles.Count)"
Add-Report "  Groupes de doublons  : $($duplicateGroups.Count)"
Add-Report "  Fichiers supprimes   : $deletedCount"
Add-Report "  Espace libere        : $freedMB Mo ($freedGB Go)"
Add-Report "============================================================"

# Save report
Write-Verbose-Action "Sauvegarde du rapport dans $outputFile..."
$reportLines | Out-File -FilePath $outputFile -Encoding UTF8
Write-Verbose-OK "Rapport sauvegarde avec succes !"
Write-Host ""
Write-Host "  >> $outputFile" -ForegroundColor Green
Write-Host ""
Write-Verbose-Info "Fin du script. Merci d'avoir utilise l'outil de nettoyage !"
Write-Host ""
