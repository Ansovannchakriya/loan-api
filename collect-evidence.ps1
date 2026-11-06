# Runs every CHECKLIST command and saves the output to evidence.txt
$out = "evidence.txt"
"" | Out-File $out -Encoding utf8

function Run($title, [scriptblock]$cmd) {
    "`n===== $title =====" | Out-File $out -Append -Encoding utf8
    "> $cmd" | Out-File $out -Append -Encoding utf8
    & $cmd 2>&1 | Out-String -Width 300 | Out-File $out -Append -Encoding utf8
    Write-Host "done: $title"
}

# build both images
Run "build full"    { docker build -q -t loan-api:full -f Dockerfile . }
Run "build prod"    { docker build -q -t loan-api:prod -f Dockerfile.prod . }

# 1. multi-stage, slim, non-root, healthcheck
Run "1 stages"      { Select-String -Path Dockerfile.prod -Pattern "^FROM|^USER|^HEALTHCHECK" }
Run "1 whoami"      { docker run --rm loan-api:prod whoami }
Run "1 health"      { docker run -d --name hc-test loan-api:prod | Out-Null; Start-Sleep 30; docker ps --filter name=hc-test --format "{{.Names}}  {{.Status}}"; docker rm -f hc-test | Out-Null }

# 2. .dockerignore
Run "2 dockerignore" { Get-Content .dockerignore }

# 3. MODEL_PATH with a mounted 1.1.0 model
New-Item -ItemType Directory -Force models | Out-Null
Run "3 train 1.1.0" { docker run --rm -v "${PWD}/models:/out" -e MODEL_PATH=/out/model-1.1.0.joblib -e MODEL_VERSION=1.1.0 loan-api:full python train.py }
Run "3 default"     { docker run -d --name m-default -p 8001:8000 loan-api:prod | Out-Null; Start-Sleep 8; Invoke-RestMethod http://localhost:8001/health | ConvertTo-Json -Compress; docker rm -f m-default | Out-Null }
Run "3 mounted"     { docker run -d --name m-110 -p 8002:8000 -v "${PWD}/models:/models:ro" -e MODEL_PATH=/models/model-1.1.0.joblib loan-api:prod | Out-Null; Start-Sleep 8; Invoke-RestMethod http://localhost:8002/health | ConvertTo-Json -Compress; docker rm -f m-110 | Out-Null }

# 4. compose
Run "4 compose up"  { docker compose up -d --build }
Start-Sleep 35
Run "4 compose ps"  { docker compose ps }

# 5. size
Run "5 sizes"       { docker images loan-api }

# 6. trivy
Run "6 trivy"       { docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL --no-progress loan-api:prod }

# extra: no secrets
Run "x history"     { docker history --no-trunc loan-api:prod | Select-String -Pattern "password|secret|token"; "(empty above = no secrets in history)" }
Run "x app files"   { docker run --rm loan-api:prod ls -la /app }
Run "x git grep"    { git grep -nIiE "password|secret|token" -- ':!CHECKLIST.md' ':!collect-evidence.ps1' }

Write-Host "`nAll done. Evidence saved to $out"
