# Runs every CHECKLIST command and saves the output to evidence.txt
$out = "evidence.txt"
"" | Out-File $out -Encoding utf8

function Run($title, [scriptblock]$cmd) {
    "`n===== $title =====" | Out-File $out -Append -Encoding utf8
    "> $cmd" | Out-File $out -Append -Encoding utf8
    & $cmd 2>&1 | Out-String -Width 300 | Out-File $out -Append -Encoding utf8
    Write-Host "done: $title"
}

Run "1 build dev"   { docker build -q -t loan-api:dev -f Dockerfile . }
Run "1 build prod"  { docker build -q -t loan-api:prod -f Dockerfile.prod . }
Run "1 sizes"       { docker images loan-api }
Run "2 whoami"      { docker run --rm loan-api:prod whoami }
Run "2 user"        { docker inspect --format '{{.Config.User}}' loan-api:prod }
Run "3 compose up"  { docker compose up -d --build }
Start-Sleep 35
Run "3 compose ps"  { docker compose ps }
Run "4 env"         { docker inspect --format '{{json .Config.Env}}' loan-api:prod }
Run "4 bad path"    { docker run --name bad-path -e MODEL_PATH=/app/model/missing.joblib loan-api:prod; docker rm bad-path | Out-Null }
Run "5 requirements" { Get-Content requirements.txt }
Run "5 no dev pkgs" { docker run --rm loan-api:prod pip list | Select-String -Pattern "pytest|httpx"; "(empty above = no dev packages)" }
Run "6 app files"   { docker run --rm loan-api:prod ls -la /app }
Run "6 history"     { docker history --no-trunc loan-api:prod | Select-String -Pattern "password|secret|token"; "(empty above = no secrets in history)" }
Run "6 git grep"    { git grep -nIiE "password|secret|token" -- ':!CHECKLIST.md' ':!collect-evidence.ps1' }
Run "7 trivy"       { docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL --no-progress loan-api:prod }

Write-Host "`nAll done. Evidence saved to $out"
