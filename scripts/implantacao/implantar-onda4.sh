#!/bin/bash
# RAIZ — Onda 4 (Cockpit v2). Uso: cd ~/Downloads/raiz-onda4 && bash implantar-onda4.sh
set -u
ORG=radar
TESTES="RaizCockpitServiceTest RaizMitigationServiceTest RaizSimulationServiceTest RaizRiskEngineTest"
cd "$(dirname "$0")"; mkdir -p saida
passo() { echo; echo "==== $1"; }
falhou() { echo; echo "XXXX PAROU em: $1 — veja saida/$2"; exit 1; }
TL=""; CN=""; for t in $TESTES; do TL="$TL --tests $t"; CN="$CN --class-names $t"; done
passo "1/3 Validacao (dry-run, nada e gravado)"
sf project deploy start --dry-run --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 2>&1 | tee saida/01-validacao.txt
[ ${PIPESTATUS[0]} -eq 0 ] || falhou "validacao" 01-validacao.txt
passo "2/3 Deploy"
sf project deploy start --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 2>&1 | tee saida/02-deploy.txt
[ ${PIPESTATUS[0]} -eq 0 ] || falhou "deploy" 02-deploy.txt
passo "3/3 Verificacao"
sf apex run --file scripts/apex/verificar-onda4.apex --target-org $ORG > saida/03-verificar-bruto.txt 2>&1
grep -E "RAIZ |Error|EXCEPTION" saida/03-verificar-bruto.txt | sed 's/.*DEBUG|//' | tee saida/03-verificar.txt
sf apex run test $CN --code-coverage --result-format human --target-org $ORG --wait 20 > saida/04-testes.txt 2>&1
grep -E "Outcome|Pass Rate|Tests Ran|RaizCockpitService " saida/04-testes.txt | tee saida/04-resumo.txt
echo; echo "OK — abra: sf org open --path lightning/n/Cockpit_RAIZ --target-org $ORG"
