# sync-upstream.ps1
# Sincroniza o fork com o repositorio oficial e rebasa as features

$ErrorActionPreference = "Stop"

$UPSTREAM = "https://github.com/anomalyco/opencode.git"
$FEATURE_BRANCHES = @(
    "feature/voice-input"
    # Adicione novos branches de feature aqui:
    # "feature/flutter-client"
    # "feature/outra-feature"
)

function Write-Step($msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "    OK: $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "    AVISO: $msg" -ForegroundColor Yellow
}

# Garante que upstream existe
Write-Step "Verificando remote upstream..."
$remotes = git remote
if ($remotes -notcontains "upstream") {
    git remote add upstream $UPSTREAM
    Write-Ok "upstream adicionado"
} else {
    Write-Ok "upstream ja configurado"
}

# Salva branch atual pra voltar depois
$currentBranch = git branch --show-current

# Busca atualizacoes do upstream
Write-Step "Buscando atualizacoes do upstream..."
git fetch upstream dev
Write-Ok "upstream/dev atualizado"

# Verifica se tem algo novo
$behind = git rev-list HEAD..upstream/dev --count 2>$null
if ($behind -eq "0") {
    Write-Host "`n Nenhuma atualizacao nova no upstream. Tudo em dia!" -ForegroundColor Green
    exit 0
}

Write-Warn "$behind commit(s) novos no upstream"

# Atualiza o branch dev local
Write-Step "Atualizando branch dev..."
git checkout dev
git reset --hard upstream/dev
git push origin dev
Write-Ok "dev sincronizado e enviado pro fork"

# Rebasa cada feature branch
foreach ($branch in $FEATURE_BRANCHES) {
    Write-Step "Rebasing $branch..."

    # Verifica se o branch existe localmente
    $exists = git branch --list $branch
    if (-not $exists) {
        # Tenta buscar do origin
        $existsRemote = git branch -r --list "origin/$branch"
        if ($existsRemote) {
            git checkout -b $branch "origin/$branch"
            Write-Ok "$branch recuperado do origin"
        } else {
            Write-Warn "$branch nao encontrado, pulando..."
            continue
        }
    } else {
        git checkout $branch
    }

    # Tenta o rebase
    $rebaseOutput = git rebase dev 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ERRO: Conflito no rebase de $branch!" -ForegroundColor Red
        Write-Host "    Resolva manualmente com:" -ForegroundColor Yellow
        Write-Host "      git checkout $branch" -ForegroundColor White
        Write-Host "      git rebase dev" -ForegroundColor White
        Write-Host "      # resolva os conflitos" -ForegroundColor White
        Write-Host "      git rebase --continue" -ForegroundColor White
        git rebase --abort
    } else {
        git push origin $branch --force-with-lease
        Write-Ok "$branch rebased e enviado pro fork"
    }
}

# Volta pro branch original
Write-Step "Voltando para $currentBranch..."
git checkout $currentBranch

Write-Host "`n Sincronizacao concluida!" -ForegroundColor Green
