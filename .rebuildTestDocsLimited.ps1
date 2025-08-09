# ===================================================================
#  PowerShell Build Script for LDoc
#
#  This script rebuilds LDoc, cleans the old output, generates
#  new documentation, and copies custom assets.
# ===================================================================

# Set the window title for clarity
$Host.UI.RawUI.WindowTitle = "LDoc Build Script"

# --- Main Script Logic in a Try/Catch block for error handling ---
try {
    Write-Host -ForegroundColor Yellow "[~] Starting documentation build..."
    Write-Host ""

    # --- 1. Re-install LDoc ---
    Write-Host -ForegroundColor Cyan "[STEP 1/4] Re-installing LDoc..."
    
    # Find the .rockspec file automatically to make the command explicit.
    $rockspecFile = Get-ChildItem -Filter *.rockspec | Select-Object -First 1
    if (-not $rockspecFile) {
        throw "Could not find a .rockspec file in the current directory."
    }

    # Run luarocks commands explicitly with the found rockspec.
    luarocks remove ldoc *>$null # Hide output, we don't care if it fails
    luarocks make $rockspecFile.FullName -ErrorAction Stop
    
    Write-Host -ForegroundColor Green "    -> Done."
    Write-Host ""

    # --- 2. Clean previous build output ---
    Write-Host -ForegroundColor Cyan "[STEP 2/4] Cleaning old documentation..."
    if (Test-Path -Path "docs\html") {
        Remove-Item -Path "docs\html" -Recurse -Force
        Write-Host -ForegroundColor Green "    -> Old directory removed."
    }
    else {
        Write-Host -ForegroundColor Gray "    -> No directory to clean."
    }
    Write-Host ""

    # --- 3. Generate new documentation ---
    Write-Host -ForegroundColor Cyan "[STEP 3/4] Generating new documentation..."
    
    # Find where luarocks installs binaries and add it to the PATH for this session.
    $luarocksBinPath = (luarocks path --bin)
    $env:Path = "$luarocksBinPath;$env:Path"
    
    # Use the 'ldoc' command, which is now findable via the updated PATH.
    ldoc.lua -c cityrp_tests.ld . -v
    
    # Check the exit code of the external command.
    # A non-zero exit code indicates an error.
    if ($LASTEXITCODE -ne 0) {
        throw "LDoc generation failed. Exit code: $LASTEXITCODE"
    }

    Write-Host -ForegroundColor Green "    -> Done."
    Write-Host ""

    # --- 4. Copy custom assets ---
    Write-Host -ForegroundColor Cyan "[STEP 4/4] Copying assets..."
    if (Test-Path -Path "docs\html") {
        Copy-Item -Path "docs\css\*" -Destination "docs\html" -Force
        Copy-Item -Path "docs\js\*" -Destination "docs\html" -Force
        Write-Host -ForegroundColor Green "    -> Done."
    }
    else {
        # This is a critical check to ensure the build actually succeeded.
        throw "LDoc failed to create the 'docs\html' output directory."
    }
    Write-Host ""

    Write-Host -ForegroundColor Green "[SUCCESS] Build process completed."
}
catch {
    # This block runs if any command with '-ErrorAction Stop' fails or if 'throw' is called.
    Write-Host -ForegroundColor Red "[!] BUILD FAILED: $($_.Exception.Message)"
}
finally {
    # This block runs regardless of success or failure.
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit"
}
