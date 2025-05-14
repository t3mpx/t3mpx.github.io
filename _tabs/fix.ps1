Get-ChildItem -Path . -Recurse -File | ForEach-Object { (Get-Content $_.FullName -Raw) -replace '<img\s+src="(../../assets/img/[^"]+)"', '<img src="$1" alt="$1"' | Set-Content $_.FullName }

