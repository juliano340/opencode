# sync-upstream.ps1
# Sincroniza o fork com o repositorio oficial e rebasa as branches de feature.

$ErrorActionPreference = "Stop"

$UPSTREAM_URL = "https://github.com/anomalyco/opencode.git"
$BASE_BRANCH = "dev"
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

function Write-Err($msg) {
    Write-Host "    ERRO: $msg" -ForegroundColor Red
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $argsList)

    & git @argsList
    if ($LASTEXITCODE -ne 0) {
        throw "git $($argsList -join ' ') falhou"
    }
}

function Test-BranchExists($branch) {
    git rev-parse --verify --quiet $branch *> $null
    return $LASTEXITCODE -eq 0
}

function Test-RemoteBranchExists($branch) {
    git rev-parse --verify --quiet "refs/remotes/$branch" *> $null
    return $LASTEXITCODE -eq 0
}

function Assert-CleanWorktree {
    $status = git status --porcelain
    if (-not $status) {
        return
    }

    Write-Err "worktree nao esta limpo. Commit, stash ou descarte as mudancas antes de sincronizar."
    Write-Host ""
    git status --short
    exit 1
}

Assert-CleanWorktree

$currentBranch = git branch --show-current
if (-not $currentBranch) {
    Write-Err "HEAD destacado. Faca checkout de uma branch antes de sincronizar."
    exit 1
}

try {
    Write-Step "Verificando remote upstream..."
    $remotes = git remote
    if ($remotes -notcontains "upstream") {
        Invoke-Git @("remote", "add", "upstream", $UPSTREAM_URL)
        Write-Ok "upstream adicionado"
    } else {
        Write-Ok "upstream ja configurado"
    }

    Write-Step "Buscando atualizacoes..."
    Invoke-Git @("fetch", "origin", "--prune")
    Invoke-Git @("fetch", "upstream", $BASE_BRANCH, "--prune")
    Write-Ok "origin e upstream/$BASE_BRANCH atualizados"

    if (-not (Test-BranchExists $BASE_BRANCH)) {
        Write-Step "Criando branch local $BASE_BRANCH..."
        if (Test-RemoteBranchExists "origin/$BASE_BRANCH") {
            Invoke-Git @("checkout", "-B", $BASE_BRANCH, "origin/$BASE_BRANCH")
        } else {
            Invoke-Git @("checkout", "-B", $BASE_BRANCH, "upstream/$BASE_BRANCH")
        }
        Write-Ok "$BASE_BRANCH criado"
    }

    $behind = git rev-list "$BASE_BRANCH..upstream/$BASE_BRANCH" --count
    $localOnly = git rev-list "upstream/$BASE_BRANCH..$BASE_BRANCH" --count

    if ([int]$localOnly -gt 0) {
        Write-Err "$BASE_BRANCH tem $localOnly commit(s) locais que nao existem no upstream."
        Write-Warn "Nao vou executar reset --hard para evitar apagar trabalho local."
        Write-Host "    Revise com: git log --oneline upstream/$BASE_BRANCH..$BASE_BRANCH" -ForegroundColor White
        exit 1
    }

    if ([int]$behind -eq 0) {
        Write-Ok "$BASE_BRANCH ja esta igual ao upstream/$BASE_BRANCH"
    } else {
        Write-Warn "$behind commit(s) novos no upstream/$BASE_BRANCH"
        Write-Step "Atualizando branch $BASE_BRANCH local..."
        Invoke-Git @("checkout", $BASE_BRANCH)
        Invoke-Git @("reset", "--hard", "upstream/$BASE_BRANCH")
        Invoke-Git @("push", "origin", $BASE_BRANCH)
        Write-Ok "$BASE_BRANCH sincronizado e enviado para origin"
    }

    foreach ($branch in $FEATURE_BRANCHES) {
        Write-Step "Rebasing $branch em $BASE_BRANCH..."

        if (Test-BranchExists $branch) {
            Invoke-Git @("checkout", $branch)
        } elseif (Test-RemoteBranchExists "origin/$branch") {
            Invoke-Git @("checkout", "-b", $branch, "origin/$branch")
            Write-Ok "$branch recuperado de origin/$branch"
        } else {
            Write-Warn "$branch nao encontrado localmente nem em origin; pulando"
            continue
        }

        git rebase $BASE_BRANCH
        if ($LASTEXITCODE -ne 0) {
            Write-Err "conflito no rebase de $branch"
            Write-Warn "Resolva manualmente e continue:"
            Write-Host "      git status" -ForegroundColor White
            Write-Host "      # resolva os conflitos" -ForegroundColor White
            Write-Host "      git add <arquivos>" -ForegroundColor White
            Write-Host "      git rebase --continue" -ForegroundColor White
            Write-Host "      git push origin $branch --force-with-lease" -ForegroundColor White
            exit 1
        }

        Invoke-Git @("push", "origin", $branch, "--force-with-lease")
        Write-Ok "$branch rebased e enviado para origin"
    }

    Write-Step "Voltando para $currentBranch..."
    Invoke-Git @("checkout", $currentBranch)

    Write-Host "`nSincronizacao concluida!" -ForegroundColor Green
} catch {
    Write-Err $_
    exit 1
}
